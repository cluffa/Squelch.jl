using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    rs = Ruleset("garmin-ftms", 115200, [
        VariableRule("speed", "km/h", JSONField(["speed"])),
        VariableRule("incline", "%", JSONField(["incline"])),
        VariableRule("gap", "s", RegexCapture(r"gap (\d+\.\d+) s", 1)),
    ])
    profile_path = tempname() * ".toml"

    @compile_workload begin
        state = MonitorState(rs)
        process_line!(state, "I (1234) machine_ftms: CCCD enabled")
        process_line!(state, "{\"cmd\":\"status\",\"speed\":6.4,\"incline\":2.0}")
        process_line!(state, "I (1234) machine_ifit: gap 12.3 s")

        save_ruleset(rs, profile_path)
        load_ruleset(profile_path)
        rm(profile_path; force=true)

        rect = Rect(0, 0, 80, 24)

        m_connect = SquelchModel()
        m_connect.ports = ["/dev/cu.example"]
        buf1 = Buffer(rect)
        frame1 = Frame(buf1, rect, GraphicsRegion[], Tuple{Int,Int,Matrix}[])
        view_connect(m_connect, frame1)

        m_configure = SquelchModel(state=deepcopy(state), mode=CONFIGURE)
        buf2 = Buffer(rect)
        frame2 = Frame(buf2, rect, GraphicsRegion[], Tuple{Int,Int,Matrix}[])
        view_screen(m_configure, Val(CONFIGURE), frame2)

        m_monitor = SquelchModel(state=deepcopy(state), mode=MONITOR)
        buf3 = Buffer(rect)
        frame3 = Frame(buf3, rect, GraphicsRegion[], Tuple{Int,Int,Matrix}[])
        view_screen(m_monitor, Val(MONITOR), frame3)

        m_chart = SquelchModel(state=deepcopy(state), mode=MONITOR, show_chart=true)
        buf4 = Buffer(rect)
        frame4 = Frame(buf4, rect, GraphicsRegion[], Tuple{Int,Int,Matrix}[])
        view_screen(m_chart, Val(MONITOR), frame4)

        update!(m_monitor, KeyEvent(:down))
        update!(m_monitor, TaskEvent(:poll, nothing))
        update!(m_connect, KeyEvent(:down))
        update!(m_configure, KeyEvent(:tab))
    end
end
