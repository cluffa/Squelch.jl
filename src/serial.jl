abstract type LineSource end

function list_serial_ports()
    return LibSerialPort.get_port_list()
end

struct RealSerialSource <: LineSource
    sp::LibSerialPort.SerialPort
end

function open_serial_source(port::AbstractString, baud::Int)
    sp = LibSerialPort.open(port, baud)
    return RealSerialSource(sp)
end

function read_line(src::RealSerialSource)
    try
        return readline(src.sp)
    catch
        return nothing
    end
end

function close_source!(src::RealSerialSource)
    close(src.sp)
    return nothing
end

mutable struct FakeLineSource <: LineSource
    lines::Vector{String}
    idx::Int
end

FakeLineSource(lines::Vector{String}) = FakeLineSource(lines, 0)

function read_line(src::FakeLineSource)
    src.idx += 1
    src.idx > length(src.lines) && return nothing
    return src.lines[src.idx]
end

close_source!(::FakeLineSource) = nothing

"""
A `LineSource` that needs no hardware or OS-level serial port at all -
it generates plausible garmin-ftms-sync-esp32-style lines on a timer
(JSON status updates with a slowly drifting speed/incline, interspersed
with ESP_LOG-style noise). Exists because real virtual serial ports
(e.g. via `socat`) don't work here: `libserialport`'s macOS backend
does modem-control-line ioctls that plain BSD ptys don't support, so
there's no OS-level way to fake a port on this platform. This sidesteps
that entirely and works on any platform.
"""
mutable struct SimulatedLineSource <: LineSource
    tick::Int
    speed::Float64
    incline::Float64
    closed::Bool
    interval::Float64
end

function SimulatedLineSource(; interval::Float64=0.4)
    return SimulatedLineSource(0, 0.0, 0.0, false, interval)
end

const SIMULATED_LOG_LINES = [
    "I (%d) machine_ftms: CCCD enabled — notifications active on handle 42",
    "I (%d) machine_ftms: Treadmill Data found: val_handle=45",
    "W (%d) machine_ifit: gap 12.3 s — distance reset",
    "I (%d) machine_ifit: init 3/8",
]

function read_line(src::SimulatedLineSource)
    src.closed && return nothing
    src.tick += 1
    sleep(src.interval)

    # Every 4th tick emits a noise line; the rest emit a JSON status
    # update with speed/incline random-walking within plausible bounds.
    if src.tick % 4 == 0
        template = SIMULATED_LOG_LINES[mod1(div(src.tick, 4), length(SIMULATED_LOG_LINES))]
        return replace(template, "%d" => string(src.tick * 137))
    end

    src.speed = clamp(src.speed + (rand() - 0.5) * 1.5, 0.0, 12.0)
    src.incline = clamp(src.incline + (rand() - 0.5) * 0.8, 0.0, 10.0)
    connected = true
    return "{\"cmd\":\"status\",\"connected\":$connected,\"speed\":$(round(src.speed; digits=1)),\"incline\":$(round(src.incline; digits=1))}"
end

function close_source!(src::SimulatedLineSource)
    src.closed = true
    return nothing
end

function start_reader_task(src::LineSource, ch::Channel{String})
    return Threads.@spawn begin
        while true
            line = read_line(src)
            line === nothing && break
            put!(ch, line)
        end
        close(ch)
    end
end
