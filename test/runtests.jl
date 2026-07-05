using Test
using Squelch

@testset "Squelch.jl" begin
    include("extractors_test.jl")
    include("history_test.jl")
    include("ruleset_test.jl")
    include("dispatch_test.jl")
end
