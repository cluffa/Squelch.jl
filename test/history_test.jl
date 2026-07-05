@testset "VariableHistory" begin
    @testset "push and latest" begin
        h = Squelch.VariableHistory("speed", "km/h"; capacity=3)
        Squelch.push_value!(h, "6.4", 1.0)
        Squelch.push_value!(h, "7.1", 2.0)
        @test Squelch.latest(h) == 7.1
        @test h.latest_raw == "7.1"
        @test h.values == [6.4, 7.1]
        @test h.timestamps == [1.0, 2.0]
    end

    @testset "ring buffer eviction" begin
        h = Squelch.VariableHistory("x", ""; capacity=2)
        Squelch.push_value!(h, "1", 1.0)
        Squelch.push_value!(h, "2", 2.0)
        Squelch.push_value!(h, "3", 3.0)
        @test h.values == [2.0, 3.0]
        @test h.timestamps == [2.0, 3.0]
    end

    @testset "non-numeric value stored raw only" begin
        h = Squelch.VariableHistory("status", "")
        Squelch.push_value!(h, "connected", 1.0)
        @test h.latest_raw == "connected"
        @test isempty(h.values)
        @test Squelch.latest(h) === nothing
    end

    @testset "empty history latest is nothing" begin
        h = Squelch.VariableHistory("y", "")
        @test Squelch.latest(h) === nothing
    end
end
