@testset "Serial layer" begin
    @testset "FakeLineSource read_line returns lines then nothing" begin
        src = Squelch.FakeLineSource(["a", "b"])
        @test Squelch.read_line(src) == "a"
        @test Squelch.read_line(src) == "b"
        @test Squelch.read_line(src) === nothing
    end

    @testset "start_reader_task streams lines into channel then closes it" begin
        src = Squelch.FakeLineSource(["line1", "line2", "line3"])
        ch = Channel{String}(10)
        task = Squelch.start_reader_task(src, ch)
        wait(task)

        received = String[]
        while isready(ch)
            push!(received, take!(ch))
        end
        @test received == ["line1", "line2", "line3"]
        @test !isopen(ch)
    end

    @testset "close_source! on FakeLineSource is a no-op that doesn't error" begin
        src = Squelch.FakeLineSource(["x"])
        @test Squelch.close_source!(src) === nothing
    end
end
