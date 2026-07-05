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
        @test !isempty(m.status_message)
    end

    @testset "invalid regex is rejected without throwing" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        push!(m.state.log_lines, "I (1) noise")
        m.configure_log_idx = 1
        Squelch.set_text!(m.pending_rule_name, "x")
        Squelch.set_text!(m.pending_pattern, "([unclosed")

        Squelch.add_rule_from_selected_line!(m)

        @test isempty(m.state.ruleset.rules)
        @test occursin("Invalid regex", m.status_message)
    end

    @testset "non-JSON line without a pattern reports an error" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        push!(m.state.log_lines, "I (1) noise")
        m.configure_log_idx = 1
        Squelch.set_text!(m.pending_rule_name, "x")

        Squelch.add_rule_from_selected_line!(m)

        @test isempty(m.state.ruleset.rules)
        @test occursin("not JSON", m.status_message)
    end

    @testset "typing 's' and 'm' into a focused field is text, not a command" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs), mode=Squelch.CONFIGURE)
        m.configure_focus = :name

        for c in "speedm"
            Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent(c))
        end

        @test Squelch.text(m.pending_rule_name) == "speedm"
        @test m.mode == Squelch.CONFIGURE  # 'm' did not switch to MONITOR
    end

    @testset "tab cycles focus log -> name -> unit -> pattern -> log" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs), mode=Squelch.CONFIGURE)

        expected = [:name, :unit, :pattern, :log]
        for want in expected
            Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent(:tab))
            @test m.configure_focus == want
        end
    end

    @testset "escape from a field returns focus to log; from log goes to monitor" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs), mode=Squelch.CONFIGURE)
        m.configure_focus = :unit

        Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent(:escape))
        @test m.configure_focus == :log
        @test m.mode == Squelch.CONFIGURE

        Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent(:escape))
        @test m.mode == Squelch.MONITOR
    end

    @testset "j/k move the log selection when log is focused" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs), mode=Squelch.CONFIGURE)
        append!(m.state.log_lines, ["a", "b", "c"])

        Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent('j'))
        @test m.configure_log_idx == 2
        Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent('k'))
        @test m.configure_log_idx == 1
        Squelch.update_screen!(m, Val(Squelch.CONFIGURE), Squelch.KeyEvent('k'))
        @test m.configure_log_idx == 1  # clamped at top
    end
end
