module Squelch

using TOML
using JSON3
using Match
using Tachikoma
using LibSerialPort

include("extractors.jl")
include("ruleset.jl")
include("history.jl")
include("dispatch.jl")
include("serial.jl")
include("app.jl")
include("precompile.jl")

end # module Squelch
