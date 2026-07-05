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

function connect_simulated!(m::SquelchModel)
    src = SimulatedLineSource()
    ch = Channel{String}(1000)
    m.line_channel = ch
    m.reader_task = start_reader_task(src, ch)
    rs = Ruleset("simulated", 0, [
        VariableRule("connected", "", JSONField(["connected"])),
        VariableRule("speed", "km/h", JSONField(["speed"])),
        VariableRule("incline", "%", JSONField(["incline"])),
    ])
    m.state = MonitorState(rs)
    m.mode = MONITOR
    m.status_message = "Connected to simulated device"
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
            (:char, 's')                 => connect_simulated!(m)
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
    area = render_status_bar(m, f.area, buf, "j/k: select port │ enter: connect │ r: refresh │ s: simulated device │ q: quit")
    inner = render(Block(title="Squelch — Connect"), area, buf)
    isempty(m.ports) && refresh_ports!(m)
    m.selected_port_idx = clamp(m.selected_port_idx, 1, max(length(m.ports), 1))
    rows = [i == m.selected_port_idx ? "> $p" : "  $p" for (i, p) in enumerate(m.ports)]
    text = isempty(rows) ? "No serial ports found — press r to refresh or s for a simulated device" : join(rows, "\n")
    render(Paragraph([Span(text)]), inner, buf)
    return nothing
end

function add_rule_from_selected_line!(m::SquelchModel)
    m.state === nothing && return
    if isempty(m.state.log_lines)
        m.status_message = "No log lines yet — wait for device output"
        return
    end
    name = strip(text(m.pending_rule_name))
    if isempty(name)
        m.status_message = "Variable name is required (tab to the name field)"
        return
    end
    unit = strip(text(m.pending_rule_unit))
    line = m.state.log_lines[clamp(m.configure_log_idx, 1, length(m.state.log_lines))]
    pattern_str = strip(text(m.pending_pattern))

    extractor = if !isempty(pattern_str)
        re = try
            Regex(pattern_str)
        catch
            m.status_message = "Invalid regex: $pattern_str"
            return
        end
        RegexCapture(re, 1)
    elseif try_parse_json(line) !== nothing
        JSONField([String(name)])
    else
        m.status_message = "Selected line is not JSON — enter a regex with a capture group"
        return
    end

    push!(m.state.ruleset.rules, VariableRule(String(name), String(unit), extractor))
    m.status_message = "Added rule '$name' ($(length(m.state.ruleset.rules)) total) — press s to save"
    set_text!(m.pending_rule_name, "")
    set_text!(m.pending_rule_unit, "")
    set_text!(m.pending_pattern, "")
    return nothing
end

const CONFIGURE_FOCUS_ORDER = (:log, :name, :unit, :pattern)

function cycle_configure_focus!(m::SquelchModel)
    i = findfirst(==(m.configure_focus), CONFIGURE_FOCUS_ORDER)
    m.configure_focus = CONFIGURE_FOCUS_ORDER[mod1(something(i, 1) + 1, length(CONFIGURE_FOCUS_ORDER))]
    return nothing
end

function focused_input(m::SquelchModel)
    return m.configure_focus == :name ? m.pending_rule_name :
           m.configure_focus == :unit ? m.pending_rule_unit : m.pending_pattern
end

function save_current_ruleset!(m::SquelchModel)
    m.state === nothing && return
    path = joinpath(profiles_dir(), m.state.ruleset.device_name * ".toml")
    save_ruleset(m.state.ruleset, path)
    m.status_message = "Saved profile to $path"
    return nothing
end

function update_screen!(m::SquelchModel, ::Val{CONFIGURE}, evt::KeyEvent)
    # While a text field is focused, plain characters (including 'm' and
    # 's') must reach the field — only tab/escape/enter act as commands.
    if m.configure_focus != :log
        @match (evt.key, evt.char) begin
            (:escape, _) => (m.configure_focus = :log)
            (:tab, _)    => cycle_configure_focus!(m)
            (:enter, _)  => add_rule_from_selected_line!(m)
            _            => handle_key!(focused_input(m), evt)
        end
        return nothing
    end
    @match (evt.key, evt.char) begin
        (:escape, _) || (:char, 'm') => (m.mode = MONITOR)
        (:tab, _)                    => cycle_configure_focus!(m)
        (:char, 'j') || (:down, _)   => begin
            if m.state !== nothing && !isempty(m.state.log_lines)
                m.configure_log_idx = min(m.configure_log_idx + 1, length(m.state.log_lines))
            end
        end
        (:char, 'k') || (:up, _)     => (m.configure_log_idx = max(m.configure_log_idx - 1, 1))
        (:enter, _)                  => add_rule_from_selected_line!(m)
        (:char, 's')                 => save_current_ruleset!(m)
        _ => nothing
    end
    return nothing
end

# Splits a status-bar row off the bottom of `area`, renders `hints` (and
# the current status message, if any) into it, and returns the remaining
# area for the screen's content.
function render_status_bar(m::SquelchModel, area, buf, hints::String)
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(1)]), area)
    length(rows) < 2 && return area
    content, bar = rows[1], rows[2]
    spans = Span[Span(" $hints", tstyle(:text_dim))]
    isempty(m.status_message) || push!(spans, Span("  │  $(m.status_message)", tstyle(:accent)))
    render(Paragraph(spans), bar, buf)
    return content
end

function view_screen(m::SquelchModel, ::Val{CONFIGURE}, f::Frame)
    buf = f.buffer
    hints = m.configure_focus == :log ?
        "j/k: select line │ tab: edit fields │ enter: add rule │ s: save │ esc/m: monitor" :
        "type into field │ tab: next field │ enter: add rule │ esc: back to log"
    area = render_status_bar(m, f.area, buf, hints)
    inner = render(Block(title="Configure"), area, buf)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(44)]), inner)
    length(cols) < 2 && return
    log_area, form_area = cols[1], cols[2]

    lines = m.state === nothing ? String[] : m.state.log_lines
    m.configure_log_idx = clamp(m.configure_log_idx, 1, max(length(lines), 1))
    marker = m.configure_focus == :log ? ">" : "·"
    rows = [i == m.configure_log_idx ? "$marker $l" : "  $l" for (i, l) in enumerate(lines)]
    # Keep the selected line visible: scroll so it sits inside the pane.
    offset = max(0, m.configure_log_idx - max(log_area.height, 1))
    render(ScrollPane(rows; following=false, offset=offset), log_area, buf)

    m.pending_rule_name.focused = m.configure_focus == :name
    m.pending_rule_unit.focused = m.configure_focus == :unit
    m.pending_pattern.focused = m.configure_focus == :pattern

    form_rows = split_layout(Layout(Vertical, [Fixed(3), Fixed(3), Fixed(3), Fill()]), form_area)
    length(form_rows) < 4 && return
    render(m.pending_rule_name, form_rows[1], buf)
    render(m.pending_rule_unit, form_rows[2], buf)
    render(m.pending_pattern, form_rows[3], buf)

    rules = m.state === nothing ? VariableRule[] : m.state.ruleset.rules
    rule_lines = isempty(rules) ? ["(none yet — fill in a name and press enter)"] :
        ["$(r.name)$(isempty(r.unit) ? "" : " ($(r.unit))")" for r in rules]
    render(ScrollPane(rule_lines; following=false, block=Block(title="Rules")), form_rows[4], buf)
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
        (:char, 'j') || (:down, _) => (m.selected_var_idx = min(m.selected_var_idx + 1, max(length(names), 1)))
        (:char, 'k') || (:up, _)   => (m.selected_var_idx = max(m.selected_var_idx - 1, 1))
        (:enter, _) => (m.show_chart = !isempty(names))
        (:escape, _) => (m.show_chart = false)
        _ => nothing
    end
    return nothing
end

function view_screen(m::SquelchModel, ::Val{MONITOR}, f::Frame)
    buf = f.buffer
    names = sorted_variable_names(m)

    m.selected_var_idx = clamp(m.selected_var_idx, 1, max(length(names), 1))

    if m.show_chart && !isempty(names)
        area = render_status_bar(m, f.area, buf, "esc: back to monitor")
        selected = names[m.selected_var_idx]
        h = m.state.variables[selected]
        series = [DataSeries(h.values; label=selected)]
        render(Chart(series; block=Block(title="$selected ($(h.unit))")), area, buf)
        return nothing
    end

    area = render_status_bar(m, f.area, buf, "j/k: select variable │ enter: chart │ c: configure │ q: quit")
    inner = render(Block(title="Monitor"), area, buf)
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
    selected = isempty(names) ? 0 : m.selected_var_idx
    render(Table(headers, table_rows; block=Block(title="Variables"), selected=selected), table_area, buf)
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
