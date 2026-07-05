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

function (@main)(args::Vector{String})::Cint
    app(SquelchModel())
    return 0
end
