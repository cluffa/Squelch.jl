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
