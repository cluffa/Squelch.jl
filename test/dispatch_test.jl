@testset "MonitorState dispatch" begin
    @testset "JSON line updates variable and appends to log" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
        ])
        state = Squelch.MonitorState(rs)
        Squelch.process_line!(state, "{\"cmd\":\"status\",\"speed\":6.4}", 1.0)

        @test state.log_lines == ["{\"cmd\":\"status\",\"speed\":6.4}"]
        @test haskey(state.variables, "speed")
        @test Squelch.latest(state.variables["speed"]) == 6.4
    end

    @testset "non-matching line goes to log only" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
        ])
        state = Squelch.MonitorState(rs)
        Squelch.process_line!(state, "I (1234) machine_ftms: CCCD enabled", 1.0)

        @test state.log_lines == ["I (1234) machine_ftms: CCCD enabled"]
        @test isempty(state.variables)
    end

    @testset "regex rule matches non-JSON log line" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("gap", "s", Squelch.RegexCapture(r"gap (\d+\.\d+) s", 1)),
        ])
        state = Squelch.MonitorState(rs)
        Squelch.process_line!(state, "I (1234) machine_ifit: gap 12.3 s — distance reset", 1.0)

        @test length(state.log_lines) == 1
        @test Squelch.latest(state.variables["gap"]) == 12.3
    end

    @testset "log buffer evicts beyond capacity" begin
        rs = Squelch.Ruleset("d", 9600, Squelch.VariableRule[])
        state = Squelch.MonitorState(rs; log_capacity=2)
        Squelch.process_line!(state, "one", 1.0)
        Squelch.process_line!(state, "two", 2.0)
        Squelch.process_line!(state, "three", 3.0)
        @test state.log_lines == ["two", "three"]
    end

    @testset "multiple rules against same JSON line" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
            Squelch.VariableRule("incline", "%", Squelch.JSONField(["incline"])),
        ])
        state = Squelch.MonitorState(rs)
        Squelch.process_line!(state, "{\"cmd\":\"status\",\"speed\":6.4,\"incline\":2.0}", 1.0)
        @test Squelch.latest(state.variables["speed"]) == 6.4
        @test Squelch.latest(state.variables["incline"]) == 2.0
    end
end
