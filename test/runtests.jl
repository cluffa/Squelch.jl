using Test
using Squelch

@testset "Squelch.jl" begin
    include("extractors_test.jl")
    include("history_test.jl")
    include("ruleset_test.jl")
    include("dispatch_test.jl")
    include("serial_test.jl")
    include("configure_test.jl")
    include("monitor_test.jl")
    include("example_profile_test.jl")
end
