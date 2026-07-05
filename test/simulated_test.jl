@testset "SimulatedLineSource" begin
    @testset "read_line never returns nothing while open" begin
        src = Squelch.SimulatedLineSource(; interval=0.001)
        for _ in 1:20
            line = Squelch.read_line(src)
            @test line !== nothing
        end
    end

    @testset "every 4th line is a log-style noise line, others are JSON status" begin
        src = Squelch.SimulatedLineSource(; interval=0.001)
        for i in 1:12
            line = Squelch.read_line(src)
            if i % 4 == 0
                @test occursin("machine_", line)
            else
                obj = Squelch.try_parse_json(line)
                @test obj !== nothing
                @test obj[:cmd] == "status"
                @test 0.0 <= obj[:speed] <= 12.0
                @test 0.0 <= obj[:incline] <= 10.0
            end
        end
    end

    @testset "close_source! stops the stream" begin
        src = Squelch.SimulatedLineSource(; interval=0.001)
        Squelch.read_line(src)
        Squelch.close_source!(src)
        @test Squelch.read_line(src) === nothing
    end
end

@testset "Simulated device hotkey" begin
    @testset "connect_simulated! seeds a ruleset and jumps to Monitor" begin
        m = Squelch.SquelchModel()
        Squelch.connect_simulated!(m)
        @test m.mode == Squelch.MONITOR
        @test m.state !== nothing
        @test m.state.ruleset.device_name == "simulated"
        @test length(m.state.ruleset.rules) == 3
        @test m.reader_task !== nothing

        # Let a little real data flow through and confirm it dispatches.
        sleep(1.0)
        Squelch.drain_channel!(m)
        @test haskey(m.state.variables, "speed") || haskey(m.state.variables, "connected")
    end

    @testset "'s' key on the Connect screen triggers connect_simulated!" begin
        m = Squelch.SquelchModel()
        Squelch.update!(m, Squelch.KeyEvent('s'))
        @test m.mode == Squelch.MONITOR
        @test m.state.ruleset.device_name == "simulated"
    end
end
