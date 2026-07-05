import Tachikoma: should_quit, task_queue, update!, view

@enum ScreenMode CONNECT CONFIGURE MONITOR

@kwdef mutable struct SquelchModel <: Model
    tq::TaskQueue = TaskQueue()
    mode::ScreenMode = CONNECT
    quit::Bool = false
    ports::Vector{String} = String[]
    selected_port_idx::Int = 1
    baud::Int = 115200
    state::Union{Nothing,MonitorState} = nothing
    line_channel::Union{Nothing,Channel{String}} = nothing
    reader_task::Union{Nothing,Task} = nothing
    selected_var_idx::Int = 1
    show_chart::Bool = false
    status_message::String = ""
    configure_log_idx::Int = 1
    pending_rule_name::TextInput = TextInput(; label="Variable name:")
    pending_rule_unit::TextInput = TextInput(; label="Unit:")
    pending_pattern::TextInput = TextInput(; label="Regex (with 1 capture group):")
    configure_focus::Symbol = :log
end

task_queue(m::SquelchModel) = m.tq
should_quit(m::SquelchModel) = m.quit

function refresh_ports!(m::SquelchModel)
    m.ports = list_serial_ports()
    if isempty(m.ports)
        m.status_message = "No serial ports found"
    end
    return nothing
end

function connect!(m::SquelchModel)
    isempty(m.ports) && return
    port = m.ports[clamp(m.selected_port_idx, 1, length(m.ports))]
    src = open_serial_source(port, m.baud)
    ch = Channel{String}(1000)
    m.line_channel = ch
    m.reader_task = start_reader_task(src, ch)
    rs = Ruleset(port, m.baud, VariableRule[])
    m.state = MonitorState(rs)
    m.mode = CONFIGURE
    m.status_message = "Connected to $port @ $(m.baud)"
    return nothing
end

function drain_channel!(m::SquelchModel)
    m.state === nothing && return
    ch = m.line_channel
    ch === nothing && return
    while isready(ch)
        line = take!(ch)
        process_line!(m.state, line)
    end
    return nothing
end

function update!(m::SquelchModel, evt::KeyEvent)
    if m.mode == CONNECT
        @match (evt.key, evt.char) begin
            (:char, 'q') || (:escape, _) => (m.quit = true)
            (:char, 'j') || (:down, _)   => (m.selected_port_idx = min(m.selected_port_idx + 1, max(length(m.ports), 1)))
            (:char, 'k') || (:up, _)     => (m.selected_port_idx = max(m.selected_port_idx - 1, 1))
            (:char, 'r')                 => refresh_ports!(m)
            (:enter, _)                  => connect!(m)
            _ => nothing
        end
    else
        update_screen!(m, Val(m.mode), evt)
    end
    return nothing
end

function update!(m::SquelchModel, evt::TaskEvent)
    if evt.id == :poll
        drain_channel!(m)
    end
    return nothing
end

function view(m::SquelchModel, f::Frame)
    spawn_timer!(m.tq, :poll, 0.05; repeat=true)
    if m.mode == CONNECT
        view_connect(m, f)
    else
        view_screen(m, Val(m.mode), f)
    end
    return nothing
end

function view_connect(m::SquelchModel, f::Frame)
    buf = f.buffer
    inner = render(Block(title="Squelch — Connect (r: refresh, enter: connect, q: quit)"), f.area, buf)
    isempty(m.ports) && refresh_ports!(m)
    rows = [i == m.selected_port_idx ? "> $p" : "  $p" for (i, p) in enumerate(m.ports)]
    text = isempty(rows) ? m.status_message : join(rows, "\n")
    render(Paragraph([Span(text)]), inner, buf)
    return nothing
end

function add_rule_from_selected_line!(m::SquelchModel)
    m.state === nothing && return
    isempty(m.state.log_lines) && return
    name = strip(text(m.pending_rule_name))
    isempty(name) && return
    unit = strip(text(m.pending_rule_unit))
    line = m.state.log_lines[clamp(m.configure_log_idx, 1, length(m.state.log_lines))]
    pattern_str = strip(text(m.pending_pattern))

    extractor = if !isempty(pattern_str)
        RegexCapture(Regex(pattern_str), 1)
    elseif try_parse_json(line) !== nothing
        JSONField([name])
    else
        return
    end

    push!(m.state.ruleset.rules, VariableRule(String(name), String(unit), extractor))
    set_text!(m.pending_rule_name, "")
    set_text!(m.pending_rule_unit, "")
    set_text!(m.pending_pattern, "")
    return nothing
end

function update_screen!(m::SquelchModel, ::Val{CONFIGURE}, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:escape, _) => (m.mode = MONITOR)
        (:char, 'm') => (m.mode = MONITOR)
        (:tab, _) => (m.configure_focus = m.configure_focus == :log ? :name :
                       m.configure_focus == :name ? :unit :
                       m.configure_focus == :unit ? :pattern : :log)
        (:down, _) => begin
            if m.configure_focus == :log && m.state !== nothing && !isempty(m.state.log_lines)
                m.configure_log_idx = min(m.configure_log_idx + 1, length(m.state.log_lines))
            end
        end
        (:up, _) => begin
            if m.configure_focus == :log
                m.configure_log_idx = max(m.configure_log_idx - 1, 1)
            end
        end
        (:enter, _) => add_rule_from_selected_line!(m)
        (:char, 's') => begin
            if m.state !== nothing
                save_ruleset(m.state.ruleset, joinpath(profiles_dir(), m.state.ruleset.device_name * ".toml"))
            end
        end
        _ => begin
            if m.configure_focus == :name
                handle_key!(m.pending_rule_name, evt)
            elseif m.configure_focus == :unit
                handle_key!(m.pending_rule_unit, evt)
            elseif m.configure_focus == :pattern
                handle_key!(m.pending_pattern, evt)
            end
        end
    end
    return nothing
end

function view_screen(m::SquelchModel, ::Val{CONFIGURE}, f::Frame)
    buf = f.buffer
    inner = render(Block(title="Configure (tab: switch field, enter: add rule, s: save, esc: monitor)"), f.area, buf)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(40)]), inner)
    length(cols) < 2 && return
    log_area, form_area = cols[1], cols[2]

    lines = m.state === nothing ? String[] : m.state.log_lines
    rows = [i == m.configure_log_idx ? "> $l" : "  $l" for (i, l) in enumerate(lines)]
    render(ScrollPane(rows; following=false), log_area, buf)

    form_rows = split_layout(Layout(Vertical, [Fixed(3), Fixed(3), Fixed(3), Fill()]), form_area)
    if length(form_rows) >= 3
        render(m.pending_rule_name, form_rows[1], buf)
        render(m.pending_rule_unit, form_rows[2], buf)
        render(m.pending_pattern, form_rows[3], buf)
    end
    return nothing
end

function sorted_variable_names(m::SquelchModel)
    m.state === nothing && return String[]
    return sort(collect(keys(m.state.variables)))
end

function update_screen!(m::SquelchModel, ::Val{MONITOR}, evt::KeyEvent)
    names = sorted_variable_names(m)
    @match (evt.key, evt.char) begin
        (:char, 'q') => (m.quit = true)
        (:char, 'c') => (m.mode = CONFIGURE)
        (:down, _) => (m.selected_var_idx = min(m.selected_var_idx + 1, max(length(names), 1)))
        (:up, _) => (m.selected_var_idx = max(m.selected_var_idx - 1, 1))
        (:enter, _) => (m.show_chart = !isempty(names))
        (:escape, _) => (m.show_chart = false)
        _ => nothing
    end
    return nothing
end

function view_screen(m::SquelchModel, ::Val{MONITOR}, f::Frame)
    buf = f.buffer
    names = sorted_variable_names(m)

    if m.show_chart && !isempty(names)
        selected = names[clamp(m.selected_var_idx, 1, length(names))]
        h = m.state.variables[selected]
        series = [DataSeries(h.values; label=selected)]
        render(Chart(series; block=Block(title="$selected ($(h.unit)) — esc: back")), f.area, buf)
        return nothing
    end

    inner = render(Block(title="Monitor (c: configure, enter: chart selected var, q: quit)"), f.area, buf)
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(10)]), inner)
    length(rows) < 2 && return

    log_area, table_area = rows[1], rows[2]

    loglines = m.state === nothing ? String[] : m.state.log_lines
    render(ScrollPane(loglines; following=true), log_area, buf)

    headers = ["Name", "Value", "Unit"]
    table_rows = [
        [n, string(something(latest(m.state.variables[n]), m.state.variables[n].latest_raw)), m.state.variables[n].unit]
        for n in names
    ]
    render(Table(headers, table_rows; block=Block(title="Variables")), table_area, buf)
    return nothing
end

"""
Path to the optional prebuilt sysimage (see `sysimage/build.jl`). Baking
Squelch + Tachikoma + dependencies into a custom sysimage skips almost
all of Julia's package-loading/JIT overhead on every launch — building
it is an explicit opt-in step (several minutes, needs PackageCompiler),
not something that happens automatically on `pkg> app add`.
"""
function squelch_sysimage_path()
    ext = Sys.isapple() ? "dylib" : Sys.iswindows() ? "dll" : "so"
    return joinpath(homedir(), ".julia", "squelch_sysimage", "squelch.$ext")
end

function current_image_file()
    try
        return unsafe_string(Base.JLOptions().image_file)
    catch
        return ""
    end
end

function (@main)(args::Vector{String})::Cint
    if get(ENV, "SQUELCH_RELAUNCHED", "") != "1"
        # The serial reader runs on a background task (Threads.@spawn in
        # start_reader_task) that does a blocking readline() call. On a
        # single-threaded process that task has no worker thread to run
        # on, so a blocking read stalls the entire UI. `julia_flags` in
        # Project.toml already requests --threads=auto for installs via
        # `pkg> app add`, but this guards direct invocations too.
        needs_threads = Threads.nthreads() == 1

        sysimage_path = squelch_sysimage_path()
        needs_sysimage = isfile(sysimage_path) && current_image_file() != sysimage_path

        if needs_threads || needs_sysimage
            flags = String["--threads=auto"]
            needs_sysimage && push!(flags, "-J$sysimage_path")
            code = "using Squelch; exit(Squelch.main(ARGS))"
            cmd = `$(Base.julia_cmd()) $flags --project=$(Base.active_project()) -e $code -- $args`
            cmd = addenv(cmd, "SQUELCH_RELAUNCHED" => "1")
            proc = run(ignorestatus(cmd))
            return proc.exitcode
        end
    end
    app(SquelchModel())
    return 0
end
