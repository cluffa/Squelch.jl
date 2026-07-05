@testset "Monitor screen logic" begin
    @testset "sorted_variable_names is alphabetical and stable" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        m.state.variables["speed"] = Squelch.VariableHistory("speed", "km/h")
        m.state.variables["incline"] = Squelch.VariableHistory("incline", "%")
        @test Squelch.sorted_variable_names(m) == ["incline", "speed"]
    end

    @testset "sorted_variable_names empty when no variables" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs))
        @test Squelch.sorted_variable_names(m) == String[]
    end

    @testset "selected_var_idx clamps within bounds via update_screen!" begin
        rs = Squelch.Ruleset("d", 115200, Squelch.VariableRule[])
        m = Squelch.SquelchModel(state=Squelch.MonitorState(rs), mode=Squelch.MONITOR)
        m.state.variables["a"] = Squelch.VariableHistory("a", "")
        m.selected_var_idx = 1
        Squelch.update_screen!(m, Val(Squelch.MONITOR), Squelch.KeyEvent(:down))
        @test m.selected_var_idx == 1  # only one variable, stays at 1
    end
end
