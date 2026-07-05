using Test
using Squelch

@testset "Squelch.jl" begin
    include("extractors_test.jl")
    include("history_test.jl")
end
