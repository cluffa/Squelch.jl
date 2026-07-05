@testset "Configure screen logic" begin
    @testset "add_rule_from_selected_line! with JSON line and name/unit filled in" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        push!(m.state.log_lines, "{\"cmd\":\"status\",\"speed\":6.4}")
        m.configure_log_idx = 1
        Squelch.set_text!(m.pending_rule_name, "speed")
        Squelch.set_text!(m.pending_rule_unit, "km/h")

        Squelch.add_rule_from_selected_line!(m)

        @test length(m.state.ruleset.rules) == 1
        @test m.state.ruleset.rules[1].name == "speed"
        @test m.state.ruleset.rules[1].extractor isa Squelch.JSONField
        @test m.state.ruleset.rules[1].extractor.path == ["speed"]
    end

    @testset "add_rule_from_selected_line! with regex pattern filled in" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        push!(m.state.log_lines, "I (1234) machine_ifit: gap 12.3 s")
        m.configure_log_idx = 1
        Squelch.set_text!(m.pending_rule_name, "gap")
        Squelch.set_text!(m.pending_rule_unit, "s")
        Squelch.set_text!(m.pending_pattern, "gap (\\d+\\.\\d+) s")

        Squelch.add_rule_from_selected_line!(m)

        @test length(m.state.ruleset.rules) == 1
        @test m.state.ruleset.rules[1].extractor isa Squelch.RegexCapture
    end

    @testset "add_rule_from_selected_line! does nothing with empty name" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        push!(m.state.log_lines, "{\"cmd\":\"status\",\"speed\":6.4}")
        m.configure_log_idx = 1

        Squelch.add_rule_from_selected_line!(m)

        @test isempty(m.state.ruleset.rules)
    end
end
