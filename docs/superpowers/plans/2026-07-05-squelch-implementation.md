# Squelch.jl Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Squelch.jl, a terminal-based, UI-configurable serial monitor for embedded devices (Tachikoma.jl UI, LibSerialPort.jl serial I/O), shippable as an unregistered installable Julia app.

**Architecture:** Three layers — (1) a pure-data parsing core (`Extractor`, `Ruleset`, `VariableHistory`, line dispatcher) with full unit test coverage, (2) a serial I/O layer wrapping LibSerialPort.jl behind a small protocol so it can be faked in tests, (3) a Tachikoma.jl `Model`/`update!`/`view` TUI wiring the two together across Connect/Configure/Monitor screens.

**Tech Stack:** Julia 1.12, Tachikoma.jl (TUI), LibSerialPort.jl (serial I/O, `ccall` wrapper around libserialport), JSON3.jl (JSON parsing), TOML (stdlib, profile persistence), Test (stdlib).

## Global Constraints

- Julia version: 1.12 (matches installed toolchain; see spec).
- Not registered in any Julia registry — installed via `pkg> app add <git url>` per spec's Packaging section.
- Package name: `Squelch`.
- Pure logic (extractors, rulesets, history, dispatch) must have unit tests; the TUI rendering itself is manually verified only (per spec's Testing section) — do not write fake/mocked rendering tests to pad coverage.
- Every non-JSON-matching AND every JSON-matching line still goes to the raw log buffer (spec section "Parsing/configuration layer", point 3) — matched lines are not removed from the log.

---

### Task 1: Package scaffolding

**Files:**
- Create: `Project.toml`
- Create: `src/Squelch.jl`
- Create: `test/runtests.jl`
- Create: `.gitignore`
- Create: `LICENSE`
- Create: `README.md`

**Interfaces:**
- Produces: module `Squelch` that later tasks add code to via `include(...)` from `src/Squelch.jl`.

- [ ] **Step 1: Create the package skeleton with Pkg**

```bash
cd /Users/alex/workspace/Squelch.jl
julia -e 'using Pkg; Pkg.generate(".")' 2>&1 | tail -5
```

This overwrites/creates `Project.toml` and `src/Squelch.jl` (Pkg.generate uses the directory name `Squelch.jl` -> module name is derived from the dir; verify the generated module name is `Squelch` and rename if Pkg picked `Squelch_jl` or similar).

- [ ] **Step 2: Verify/fix Project.toml name and set package metadata**

Read the generated `Project.toml`. It must contain:

```toml
name = "Squelch"
uuid = "<generated-uuid, keep as-is>"
authors = ["<keep as generated>"]
version = "0.1.0"
```

If `name` is not exactly `Squelch`, or `src/Squelch.jl` does not define `module Squelch`, fix both to match.

- [ ] **Step 3: Add dependencies**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/kahliburke/Tachikoma.jl")'
julia --project=. -e 'using Pkg; Pkg.add("JSON3")'
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/JuliaIO/LibSerialPort.jl")'
julia --project=. -e 'using Pkg; Pkg.add("Match")'
```

`TOML` and `Test` are stdlibs and don't need `Pkg.add`; add them to `Project.toml`'s `[deps]`/`[extras]` by hand if `Pkg` doesn't do it automatically for stdlibs used via `using TOML`.

- [ ] **Step 4: Write minimal module file**

`src/Squelch.jl`:

```julia
module Squelch

using TOML
using JSON3
using Match
using Tachikoma
using LibSerialPort

include("extractors.jl")
include("ruleset.jl")
include("history.jl")
include("dispatch.jl")
include("serial.jl")
include("ui.jl")
include("app.jl")

end # module Squelch
```

(The included files don't exist yet — later tasks create them. This step just establishes the include order: pure data types first, then serial, then UI, then app entrypoint.)

- [ ] **Step 5: Write `.gitignore`**

```
Manifest.toml
*.jl.cov
*.jl.mem
.vscode/
```

Note: `Manifest.toml` is gitignored deliberately — this is an app installed via `pkg> app add`, which regenerates its own manifest; committing one for a dependency pulled from an unregistered URL risks going stale. If you'd rather pin exact dependency commits, remove this line and commit the Manifest instead — but for this plan, ignore it.

- [ ] **Step 6: Write `LICENSE`**

Use MIT license text, copyright holder "the Squelch.jl contributors", current year 2026.

- [ ] **Step 7: Write stub `README.md`**

```markdown
# Squelch.jl

A terminal-based, UI-configurable serial monitor for embedded devices.
Not registered in any Julia registry.

## Install

    pkg> app add https://github.com/<you>/Squelch.jl

## Usage

    squelch
```

(Full usage docs land in Task 12.)

- [ ] **Step 8: Write empty test runner**

`test/runtests.jl`:

```julia
using Test
using Squelch

@testset "Squelch.jl" begin
    include("extractors_test.jl")
    include("ruleset_test.jl")
    include("history_test.jl")
    include("dispatch_test.jl")
    include("serial_test.jl")
end
```

- [ ] **Step 9: Verify the package loads**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'using Squelch; println("loaded ok")'
```

Expected: `loaded ok` (errors here mean a dependency or include is broken — fix before proceeding; the include list references files that don't exist yet, so **this step will fail until Task 2 creates the first included file** — create empty placeholder files `src/extractors.jl` through `src/app.jl` each containing just `# placeholder` right now so this step can pass, and delete the placeholder content in the task that implements each file).

- [ ] **Step 10: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add Project.toml Manifest.toml src/ test/ .gitignore LICENSE README.md
git commit -m "Scaffold Squelch.jl package"
```

(If `Manifest.toml` is gitignored per Step 5, it won't be added — that's fine, `git add` will just skip it silently.)

---

### Task 2: Extractor types and matching logic

**Files:**
- Create: `src/extractors.jl` (replacing the placeholder)
- Create: `test/extractors_test.jl`

**Interfaces:**
- Produces:
  - `abstract type Extractor end`
  - `struct JSONField <: Extractor; path::Vector{String}; end`
  - `struct RegexCapture <: Extractor; pattern::Regex; group::Int; end`
  - `extract(e::Extractor, line::AbstractString, parsed_json::Union{Nothing,JSON3.Object}) -> Union{Nothing,String}`
  - `try_parse_json(line::AbstractString) -> Union{Nothing,JSON3.Object}`

- [ ] **Step 1: Write failing tests**

`test/extractors_test.jl`:

```julia
@testset "Extractors" begin
    @testset "try_parse_json" begin
        @test Squelch.try_parse_json("{\"cmd\":\"status\",\"connected\":true}") !== nothing
        @test Squelch.try_parse_json("not json") === nothing
        @test Squelch.try_parse_json("I (1234) machine_ftms: CCCD enabled") === nothing
    end

    @testset "JSONField" begin
        obj = Squelch.try_parse_json("{\"cmd\":\"status\",\"speed\":6.4}")
        e = Squelch.JSONField(["speed"])
        @test Squelch.extract(e, "{\"cmd\":\"status\",\"speed\":6.4}", obj) == "6.4"

        e2 = Squelch.JSONField(["missing"])
        @test Squelch.extract(e2, "{\"cmd\":\"status\",\"speed\":6.4}", obj) === nothing
    end

    @testset "JSONField nested path" begin
        line = "{\"cmd\":\"status\",\"machine\":{\"speed\":6.4}}"
        obj = Squelch.try_parse_json(line)
        e = Squelch.JSONField(["machine", "speed"])
        @test Squelch.extract(e, line, obj) == "6.4"
    end

    @testset "RegexCapture" begin
        e = Squelch.RegexCapture(r"gap (\d+\.\d+) s", 1)
        line = "I (1234) machine_ifit: gap 12.3 s — distance reset"
        @test Squelch.extract(e, line, nothing) == "12.3"

        e2 = Squelch.RegexCapture(r"nomatch(\d+)", 1)
        @test Squelch.extract(e2, line, nothing) === nothing
    end

    @testset "RegexCapture applies even when line is JSON" begin
        e = Squelch.RegexCapture(r"\"speed\":(\d+\.\d+)", 1)
        line = "{\"cmd\":\"status\",\"speed\":6.4}"
        obj = Squelch.try_parse_json(line)
        @test Squelch.extract(e, line, obj) == "6.4"
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; include("test/extractors_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError` for `try_parse_json`/`JSONField`/etc, since `src/extractors.jl` is still the placeholder.

- [ ] **Step 3: Implement**

`src/extractors.jl`:

```julia
abstract type Extractor end

struct JSONField <: Extractor
    path::Vector{String}
end

struct RegexCapture <: Extractor
    pattern::Regex
    group::Int
end

function try_parse_json(line::AbstractString)
    try
        obj = JSON3.read(line)
        return obj isa JSON3.Object ? obj : nothing
    catch
        return nothing
    end
end

function extract(e::JSONField, ::AbstractString, parsed_json)
    parsed_json === nothing && return nothing
    current = parsed_json
    for key in e.path
        (current isa JSON3.Object) || return nothing
        haskey(current, Symbol(key)) || return nothing
        current = current[Symbol(key)]
    end
    return string(current)
end

function extract(e::RegexCapture, line::AbstractString, ::Union{Nothing,JSON3.Object})
    m = match(e.pattern, line)
    m === nothing && return nothing
    e.group > length(m.captures) && return nothing
    cap = m.captures[e.group]
    return cap === nothing ? nothing : String(cap)
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/extractors_test.jl")'
```

Expected: all `@test` pass, no errors.

- [ ] **Step 5: Wire into runtests and commit**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'using Pkg; Pkg.test()' 2>&1 | tail -30
git add src/extractors.jl test/extractors_test.jl
git commit -m "Add Extractor types (JSONField, RegexCapture) with tests"
```

Expected: test suite runs (other testsets still reference placeholders and will error — that's expected until their tasks land; if `Pkg.test()` aborts the whole run on the first broken testset, temporarily comment out the other `include(...)` lines in `test/runtests.jl` other than `extractors_test.jl`, run, restore the comments, then commit).

---

### Task 3: Variable history ring buffer

**Files:**
- Create: `src/history.jl` (replacing placeholder)
- Create: `test/history_test.jl`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces:
  - `mutable struct VariableHistory; name::String; unit::String; capacity::Int; values::Vector{Float64}; timestamps::Vector{Float64}; latest_raw::String; end`
  - `VariableHistory(name::String, unit::String; capacity::Int=200) -> VariableHistory`
  - `push_value!(h::VariableHistory, raw::AbstractString, t::Float64=time()) -> Nothing` — parses `raw` as `Float64` if possible (non-numeric values are still stored in `latest_raw` but not pushed into `values`/`timestamps`)
  - `latest(h::VariableHistory) -> Union{Nothing,Float64}`

- [ ] **Step 1: Write failing tests**

`test/history_test.jl`:

```julia
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/history_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError: VariableHistory not defined`.

- [ ] **Step 3: Implement**

`src/history.jl`:

```julia
mutable struct VariableHistory
    name::String
    unit::String
    capacity::Int
    values::Vector{Float64}
    timestamps::Vector{Float64}
    latest_raw::String
end

function VariableHistory(name::String, unit::String; capacity::Int=200)
    return VariableHistory(name, unit, capacity, Float64[], Float64[], "")
end

function push_value!(h::VariableHistory, raw::AbstractString, t::Float64=time())
    h.latest_raw = String(raw)
    parsed = tryparse(Float64, raw)
    if parsed !== nothing
        push!(h.values, parsed)
        push!(h.timestamps, t)
        while length(h.values) > h.capacity
            popfirst!(h.values)
            popfirst!(h.timestamps)
        end
    end
    return nothing
end

function latest(h::VariableHistory)
    isempty(h.values) && return nothing
    return h.values[end]
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/history_test.jl")'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/history.jl test/history_test.jl
git commit -m "Add VariableHistory ring buffer with tests"
```

---

### Task 4: Ruleset type and TOML round-trip

**Files:**
- Create: `src/ruleset.jl` (replacing placeholder)
- Create: `test/ruleset_test.jl`

**Interfaces:**
- Consumes: `Extractor`, `JSONField`, `RegexCapture` from Task 2 (`src/extractors.jl`).
- Produces:
  - `struct VariableRule; name::String; unit::String; extractor::Extractor; end`
  - `mutable struct Ruleset; device_name::String; baud::Int; rules::Vector{VariableRule}; end`
  - `to_dict(rs::Ruleset) -> Dict{String,Any}`
  - `ruleset_from_dict(d::AbstractDict) -> Ruleset`
  - `save_ruleset(rs::Ruleset, path::AbstractString) -> Nothing`
  - `load_ruleset(path::AbstractString) -> Ruleset`
  - `profiles_dir() -> String` (returns `joinpath(homedir(), ".config", "squelch", "profiles")`, creating it if missing)

- [ ] **Step 1: Write failing tests**

`test/ruleset_test.jl`:

```julia
@testset "Ruleset" begin
    @testset "to_dict / ruleset_from_dict round trip, JSONField" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
            Squelch.VariableRule("connected", "", Squelch.JSONField(["status", "connected"])),
        ])
        d = Squelch.to_dict(rs)
        rs2 = Squelch.ruleset_from_dict(d)
        @test rs2.device_name == "garmin-ftms"
        @test rs2.baud == 115200
        @test length(rs2.rules) == 2
        @test rs2.rules[1].name == "speed"
        @test rs2.rules[1].unit == "km/h"
        @test rs2.rules[1].extractor isa Squelch.JSONField
        @test rs2.rules[1].extractor.path == ["speed"]
        @test rs2.rules[2].extractor.path == ["status", "connected"]
    end

    @testset "to_dict / ruleset_from_dict round trip, RegexCapture" begin
        rs = Squelch.Ruleset("generic", 9600, [
            Squelch.VariableRule("gap", "s", Squelch.RegexCapture(r"gap (\d+\.\d+) s", 1)),
        ])
        d = Squelch.to_dict(rs)
        rs2 = Squelch.ruleset_from_dict(d)
        @test rs2.rules[1].extractor isa Squelch.RegexCapture
        @test rs2.rules[1].extractor.pattern == r"gap (\d+\.\d+) s"
        @test rs2.rules[1].extractor.group == 1
    end

    @testset "save_ruleset / load_ruleset file round trip" begin
        rs = Squelch.Ruleset("test-device", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
        ])
        path = tempname() * ".toml"
        Squelch.save_ruleset(rs, path)
        @test isfile(path)
        rs2 = Squelch.load_ruleset(path)
        @test rs2.device_name == "test-device"
        @test rs2.baud == 115200
        @test rs2.rules[1].name == "speed"
        rm(path)
    end

    @testset "profiles_dir creates directory" begin
        dir = Squelch.profiles_dir()
        @test isdir(dir)
    end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/ruleset_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError: Ruleset not defined`.

- [ ] **Step 3: Implement**

`src/ruleset.jl`:

```julia
struct VariableRule
    name::String
    unit::String
    extractor::Extractor
end

mutable struct Ruleset
    device_name::String
    baud::Int
    rules::Vector{VariableRule}
end

function extractor_to_dict(e::JSONField)
    return Dict{String,Any}("kind" => "json_field", "path" => e.path)
end

function extractor_to_dict(e::RegexCapture)
    return Dict{String,Any}(
        "kind" => "regex_capture",
        "pattern" => e.pattern.pattern,
        "group" => e.group,
    )
end

function extractor_from_dict(d::AbstractDict)
    kind = d["kind"]
    if kind == "json_field"
        return JSONField(Vector{String}(d["path"]))
    elseif kind == "regex_capture"
        return RegexCapture(Regex(d["pattern"]), Int(d["group"]))
    else
        error("Unknown extractor kind: $kind")
    end
end

function to_dict(rs::Ruleset)
    return Dict{String,Any}(
        "device_name" => rs.device_name,
        "baud" => rs.baud,
        "rules" => [
            Dict{String,Any}(
                "name" => r.name,
                "unit" => r.unit,
                "extractor" => extractor_to_dict(r.extractor),
            ) for r in rs.rules
        ],
    )
end

function ruleset_from_dict(d::AbstractDict)
    rules = VariableRule[
        VariableRule(rd["name"], rd["unit"], extractor_from_dict(rd["extractor"]))
        for rd in d["rules"]
    ]
    return Ruleset(d["device_name"], Int(d["baud"]), rules)
end

function profiles_dir()
    dir = joinpath(homedir(), ".config", "squelch", "profiles")
    mkpath(dir)
    return dir
end

function save_ruleset(rs::Ruleset, path::AbstractString)
    open(path, "w") do io
        TOML.print(io, to_dict(rs))
    end
    return nothing
end

function load_ruleset(path::AbstractString)
    d = TOML.parsefile(path)
    return ruleset_from_dict(d)
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/ruleset_test.jl")'
```

Expected: all tests pass. (`Regex` equality: two `Regex` built from the same pattern string compare equal in Julia because `==` for `Regex` compares `.pattern` — if this test fails on `==`, compare `.pattern` fields explicitly instead: `rs2.rules[1].extractor.pattern.pattern == "gap (\\d+\\.\\d+) s"`.)

- [ ] **Step 5: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/ruleset.jl test/ruleset_test.jl
git commit -m "Add Ruleset type with TOML persistence and tests"
```

---

### Task 5: Line dispatcher

**Files:**
- Create: `src/dispatch.jl` (replacing placeholder)
- Create: `test/dispatch_test.jl`

**Interfaces:**
- Consumes: `Ruleset`, `VariableRule`, `Extractor`, `try_parse_json` from Tasks 2/4; `VariableHistory`, `push_value!` from Task 3.
- Produces:
  - `mutable struct MonitorState; ruleset::Ruleset; log_lines::Vector{String}; log_capacity::Int; variables::Dict{String,VariableHistory}; end`
  - `MonitorState(rs::Ruleset; log_capacity::Int=500) -> MonitorState`
  - `process_line!(state::MonitorState, line::AbstractString, t::Float64=time()) -> Nothing`

- [ ] **Step 1: Write failing tests**

`test/dispatch_test.jl`:

```julia
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/dispatch_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError: MonitorState not defined`.

- [ ] **Step 3: Implement**

`src/dispatch.jl`:

```julia
mutable struct MonitorState
    ruleset::Ruleset
    log_lines::Vector{String}
    log_capacity::Int
    variables::Dict{String,VariableHistory}
end

function MonitorState(rs::Ruleset; log_capacity::Int=500)
    return MonitorState(rs, String[], log_capacity, Dict{String,VariableHistory}())
end

function process_line!(state::MonitorState, line::AbstractString, t::Float64=time())
    parsed_json = try_parse_json(line)

    for rule in state.ruleset.rules
        value = extract(rule.extractor, line, parsed_json)
        value === nothing && continue
        history = get!(state.variables, rule.name) do
            VariableHistory(rule.name, rule.unit)
        end
        push_value!(history, value, t)
    end

    push!(state.log_lines, String(line))
    while length(state.log_lines) > state.log_capacity
        popfirst!(state.log_lines)
    end
    return nothing
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/dispatch_test.jl")'
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/dispatch.jl test/dispatch_test.jl
git commit -m "Add line dispatcher wiring rulesets to variable history and log buffer"
```

---

### Task 6: Serial layer with fakeable source

**Files:**
- Create: `src/serial.jl` (replacing placeholder)
- Create: `test/serial_test.jl`

**Interfaces:**
- Consumes: nothing from other tasks (independent of parsing core).
- Produces:
  - `abstract type LineSource end`
  - `list_serial_ports() -> Vector{String}` (wraps `LibSerialPort.get_port_list()`)
  - `struct RealSerialSource <: LineSource; sp; end` (wraps an opened `LibSerialPort.SerialPort`)
  - `open_serial_source(port::AbstractString, baud::Int) -> RealSerialSource`
  - `read_line(src::LineSource) -> Union{String,Nothing}` — blocking read of one line, `nothing` on EOF/disconnect
  - `close_source!(src::LineSource) -> Nothing`
  - `struct FakeLineSource <: LineSource; lines::Vector{String}; idx::Ref{Int}; end` (test double)
  - `FakeLineSource(lines::Vector{String}) -> FakeLineSource`
  - `start_reader_task(src::LineSource, ch::Channel{String}) -> Task` — spawns a `Threads.@spawn` loop that calls `read_line` until it returns `nothing`, `put!`-ing each line onto `ch`, then closes `ch`

**Why a `FakeLineSource`:** hardware isn't available in CI/dev-loop, so `read_line`/`start_reader_task` are tested against an in-memory fake implementing the same small interface — this is the seam that keeps the serial layer testable per the spec's testing section (the spec accepts the TUI itself as untestable, but the reader-loop logic around it is not TUI and should be tested).

- [ ] **Step 1: Write failing tests**

`test/serial_test.jl`:

```julia
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/serial_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError: FakeLineSource not defined`.

- [ ] **Step 3: Implement**

`src/serial.jl`:

```julia
abstract type LineSource end

function list_serial_ports()
    return LibSerialPort.get_port_list()
end

struct RealSerialSource <: LineSource
    sp::LibSerialPort.SerialPort
end

function open_serial_source(port::AbstractString, baud::Int)
    sp = LibSerialPort.open(port, baud)
    return RealSerialSource(sp)
end

function read_line(src::RealSerialSource)
    try
        return readline(src.sp)
    catch
        return nothing
    end
end

function close_source!(src::RealSerialSource)
    close(src.sp)
    return nothing
end

mutable struct FakeLineSource <: LineSource
    lines::Vector{String}
    idx::Int
end

FakeLineSource(lines::Vector{String}) = FakeLineSource(lines, 0)

function read_line(src::FakeLineSource)
    src.idx += 1
    src.idx > length(src.lines) && return nothing
    return src.lines[src.idx]
end

close_source!(::FakeLineSource) = nothing

function start_reader_task(src::LineSource, ch::Channel{String})
    return Threads.@spawn begin
        while true
            line = read_line(src)
            line === nothing && break
            put!(ch, line)
        end
        close(ch)
    end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/serial_test.jl")'
```

Expected: all tests pass. If `start_reader_task` test hangs, run Julia with `JULIA_NUM_THREADS=2` (`JULIA_NUM_THREADS=2 julia --project=. ...`) — `Threads.@spawn` needs a worker thread to run on.

- [ ] **Step 5: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/serial.jl test/serial_test.jl
git commit -m "Add serial layer (LibSerialPort wrapper + fakeable LineSource) with tests"
```

---

### Task 7: Full test suite wiring and sanity pass

**Files:**
- Modify: `test/runtests.jl`

**Interfaces:**
- Consumes: all test files from Tasks 2-6.
- Produces: nothing new; this is a checkpoint task.

- [ ] **Step 1: Ensure runtests.jl includes every test file**

`test/runtests.jl`:

```julia
using Test
using Squelch

@testset "Squelch.jl" begin
    include("extractors_test.jl")
    include("ruleset_test.jl")
    include("history_test.jl")
    include("dispatch_test.jl")
    include("serial_test.jl")
end
```

- [ ] **Step 2: Run the full suite**

```bash
cd /Users/alex/workspace/Squelch.jl
JULIA_NUM_THREADS=2 julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all testsets pass, 0 failures, 0 errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add test/runtests.jl
git commit -m "Wire full test suite together"
```

---

### Task 8: Tachikoma Model skeleton, app entrypoint, and Pkg App registration

**Files:**
- Create: `src/app.jl` (replacing placeholder)
- Modify: `Project.toml` (add `[apps]` table)

**Interfaces:**
- Consumes: `MonitorState`, `Ruleset` (Task 4/5), `LineSource`/`list_serial_ports`/`open_serial_source`/`start_reader_task` (Task 6).
- Produces:
  - `@enum ScreenMode CONNECT CONFIGURE MONITOR`
  - `@kwdef mutable struct SquelchModel <: Model; ...; end` with fields: `tq::TaskQueue`, `mode::ScreenMode`, `quit::Bool`, `ports::Vector{String}`, `selected_port_idx::Int`, `baud::Int`, `state::Union{Nothing,MonitorState}`, `line_channel::Union{Nothing,Channel{String}}`, `reader_task::Union{Nothing,Task}`, `selected_var_idx::Int`, `show_chart::Bool`, `status_message::String`
  - `Squelch.main(args::Vector{String})::Cint` — the `(@main)` entrypoint

This task establishes the model and app wiring; Connect screen key handling and rendering are also written here since they're small and tightly coupled to the model's initial state. Configure/Monitor screens (Tasks 9-10) build on top.

- [ ] **Step 1: Write `src/app.jl` with model, Connect screen, and entrypoint**

```julia
@enum ScreenMode CONNECT CONFIGURE MONITOR

@kwdef mutable struct SquelchModel <: Model
    tq::TaskQueue = TaskQueue()
    mode::ScreenMode = CONNECT
    quit::Bool = false
    ports::Vector{String} = String[]
    selected_port_idx::Int = 1
    baud::Int = 115200
    state::Union{Nothing,MonitorState} = nothing
    line_channel::Union{Nothing,Channel{String}} = nothing
    reader_task::Union{Nothing,Task} = nothing
    selected_var_idx::Int = 1
    show_chart::Bool = false
    status_message::String = ""
end

task_queue(m::SquelchModel) = m.tq
should_quit(m::SquelchModel) = m.quit

function refresh_ports!(m::SquelchModel)
    m.ports = list_serial_ports()
    if isempty(m.ports)
        m.status_message = "No serial ports found"
    end
    return nothing
end

function connect!(m::SquelchModel)
    isempty(m.ports) && return
    port = m.ports[m.selected_port_idx]
    src = open_serial_source(port, m.baud)
    ch = Channel{String}(1000)
    m.line_channel = ch
    m.reader_task = start_reader_task(src, ch)
    rs = Ruleset(port, m.baud, VariableRule[])
    m.state = MonitorState(rs)
    m.mode = CONFIGURE
    m.status_message = "Connected to $port @ $(m.baud)"
    return nothing
end

function drain_channel!(m::SquelchModel)
    m.state === nothing && return
    ch = m.line_channel
    ch === nothing && return
    while isready(ch)
        line = take!(ch)
        process_line!(m.state, line)
    end
    return nothing
end

function update!(m::SquelchModel, evt::KeyEvent)
    if m.mode == CONNECT
        @match (evt.key, evt.char) begin
            (:char, 'q') || (:escape, _) => (m.quit = true)
            (:char, 'j') || (:down, _)   => (m.selected_port_idx = min(m.selected_port_idx + 1, max(length(m.ports), 1)))
            (:char, 'k') || (:up, _)     => (m.selected_port_idx = max(m.selected_port_idx - 1, 1))
            (:char, 'r')                 => refresh_ports!(m)
            (:enter, _)                  => connect!(m)
            _ => nothing
        end
    else
        update_screen!(m, m.mode, evt)
    end
end

function update!(m::SquelchModel, evt::TaskEvent)
    if evt.id == :poll
        drain_channel!(m)
    end
end

function view(m::SquelchModel, f::Frame)
    spawn_timer!(m.tq, :poll, 0.05; repeat=true)
    if m.mode == CONNECT
        view_connect(m, f)
    else
        view_screen(m, m.mode, f)
    end
end

function view_connect(m::SquelchModel, f::Frame)
    buf = f.buffer
    inner = render(Block(title="Squelch — Connect (r: refresh, enter: connect, q: quit)"), f.area, buf)
    isempty(m.ports) && refresh_ports!(m)
    rows = [i == m.selected_port_idx ? "> $p" : "  $p" for (i, p) in enumerate(m.ports)]
    render(Paragraph([Span(join(rows, "\n"))]), inner, buf)
end

function main(args::Vector{String})::Cint
    app(SquelchModel())
    return 0
end
```

- [ ] **Step 2: Add `[apps]` table to `Project.toml`**

Append to `Project.toml`:

```toml
[apps]
squelch = {}
```

- [ ] **Step 3: Manual verification (not automated — TUI)**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'using Squelch; Squelch.main(String[])'
```

Expected: terminal switches to the Squelch Connect screen listing available serial ports (or "No serial ports found" status if none are plugged in); `q` quits back to the shell cleanly. This step has no automated pass/fail — visually confirm it renders and `q` exits, then note the result in the task's commit message.

- [ ] **Step 4: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/app.jl Project.toml
git commit -m "Add Tachikoma Model skeleton, Connect screen, and app entrypoint

Manually verified: Connect screen renders port list, q quits cleanly."
```

---

### Task 9: Configure screen (interactive rule builder)

**Files:**
- Modify: `src/app.jl` (add `update_screen!`/`view_screen` dispatch for `CONFIGURE`, plus builder state)

**Interfaces:**
- Consumes: `SquelchModel`, `MonitorState`, `Ruleset`, `VariableRule`, `JSONField`, `RegexCapture`, `try_parse_json` (Tasks 2, 4, 5, 8).
- Produces:
  - Additional `SquelchModel` fields (add to the `@kwdef` struct from Task 8): `configure_log_idx::Int = 1`, `pending_rule_name::TextInput = TextInput(; label="Variable name:")`, `pending_rule_unit::TextInput = TextInput(; label="Unit:")`, `pending_pattern::TextInput = TextInput(; label="Regex (with 1 capture group):")`, `configure_focus::Symbol = :log` (`:log`, `:name`, `:unit`, `:pattern`)
  - `update_screen!(m::SquelchModel, ::Val{CONFIGURE}, evt::KeyEvent) -> Nothing`
  - `view_screen(m::SquelchModel, ::Val{CONFIGURE}, f::Frame) -> Nothing`
  - `add_rule_from_selected_line!(m::SquelchModel) -> Nothing` — pure logic, unit tested directly (doesn't touch `Frame`)

**Note on dispatch:** Task 8's `update_screen!(m, m.mode, evt)` call passes the plain `ScreenMode` enum value, not `Val`-wrapped — change that call site to `update_screen!(m, Val(m.mode), evt)` (and the `view` call similarly) so these `Val{CONFIGURE}`/`Val{MONITOR}` methods dispatch correctly. Make this one-line edit as part of this task's Step 1.

- [ ] **Step 1: Fix Task 8's dispatch call sites**

In `src/app.jl`, change:

```julia
        update_screen!(m, m.mode, evt)
```
to:
```julia
        update_screen!(m, Val(m.mode), evt)
```

and change:

```julia
    else
        view_screen(m, m.mode, f)
    end
```
to:
```julia
    else
        view_screen(m, Val(m.mode), f)
    end
```

- [ ] **Step 2: Write a failing unit test for the pure rule-building logic**

Create `test/configure_test.jl`:

```julia
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
```

Add `include("configure_test.jl")` to `test/runtests.jl`.

- [ ] **Step 3: Run to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/configure_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError` for the new `SquelchModel` fields or `add_rule_from_selected_line!`.

- [ ] **Step 4: Implement**

Add the new fields to the `SquelchModel` `@kwdef` struct in `src/app.jl` (append after `status_message`):

```julia
    configure_log_idx::Int = 1
    pending_rule_name::TextInput = TextInput(; label="Variable name:")
    pending_rule_unit::TextInput = TextInput(; label="Unit:")
    pending_pattern::TextInput = TextInput(; label="Regex (with 1 capture group):")
    configure_focus::Symbol = :log
```

Append to `src/app.jl`:

```julia
function add_rule_from_selected_line!(m::SquelchModel)
    m.state === nothing && return
    isempty(m.state.log_lines) && return
    name = strip(text(m.pending_rule_name))
    isempty(name) && return
    unit = strip(text(m.pending_rule_unit))
    line = m.state.log_lines[clamp(m.configure_log_idx, 1, length(m.state.log_lines))]
    pattern_str = strip(text(m.pending_pattern))

    extractor = if !isempty(pattern_str)
        RegexCapture(Regex(pattern_str), 1)
    elseif try_parse_json(line) !== nothing
        JSONField([name])
    else
        return
    end

    push!(m.state.ruleset.rules, VariableRule(String(name), String(unit), extractor))
    set_text!(m.pending_rule_name, "")
    set_text!(m.pending_rule_unit, "")
    set_text!(m.pending_pattern, "")
    return nothing
end

function update_screen!(m::SquelchModel, ::Val{CONFIGURE}, evt::KeyEvent)
    @match (evt.key, evt.char) begin
        (:escape, _) => (m.mode = MONITOR)
        (:char, 'm') => (m.mode = MONITOR)
        (:tab, _) => (m.configure_focus = m.configure_focus == :log ? :name :
                       m.configure_focus == :name ? :unit :
                       m.configure_focus == :unit ? :pattern : :log)
        (:down, _) => m.configure_focus == :log && m.state !== nothing && !isempty(m.state.log_lines) &&
                       (m.configure_log_idx = min(m.configure_log_idx + 1, length(m.state.log_lines)))
        (:up, _) => m.configure_focus == :log &&
                       (m.configure_log_idx = max(m.configure_log_idx - 1, 1))
        (:enter, _) => add_rule_from_selected_line!(m)
        (:char, 's') => (m.state !== nothing &&
                          save_ruleset(m.state.ruleset, joinpath(profiles_dir(), m.state.ruleset.device_name * ".toml")))
        _ => begin
            if m.configure_focus == :name
                handle_key!(m.pending_rule_name, evt)
            elseif m.configure_focus == :unit
                handle_key!(m.pending_rule_unit, evt)
            elseif m.configure_focus == :pattern
                handle_key!(m.pending_pattern, evt)
            end
        end
    end
    return nothing
end

function view_screen(m::SquelchModel, ::Val{CONFIGURE}, f::Frame)
    buf = f.buffer
    inner = render(Block(title="Configure (tab: switch field, enter: add rule, s: save, esc: monitor)"), f.area, buf)
    cols = split_layout(Layout(Horizontal, [Fill(), Fixed(40)]), inner)
    length(cols) < 2 && return
    log_area, form_area = cols[1], cols[2]

    lines = m.state === nothing ? String[] : m.state.log_lines
    rows = [i == m.configure_log_idx ? "> $l" : "  $l" for (i, l) in enumerate(lines)]
    render(ScrollPane(rows; following=false), log_area, buf)

    form_rows = split_layout(Layout(Vertical, [Fixed(3), Fixed(3), Fixed(3), Fill()]), form_area)
    if length(form_rows) >= 3
        render(m.pending_rule_name, form_rows[1], buf)
        render(m.pending_rule_unit, form_rows[2], buf)
        render(m.pending_pattern, form_rows[3], buf)
    end
    return nothing
end
```

- [ ] **Step 5: Run to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/configure_test.jl")'
```

Expected: all tests pass.

- [ ] **Step 6: Run full suite**

```bash
cd /Users/alex/workspace/Squelch.jl
JULIA_NUM_THREADS=2 julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/app.jl test/configure_test.jl test/runtests.jl
git commit -m "Add Configure screen: interactive rule builder over live log lines"
```

---

### Task 10: Monitor screen (log pane + variable table) and chart overlay

**Files:**
- Modify: `src/app.jl` (add `update_screen!`/`view_screen` for `MONITOR`)

**Interfaces:**
- Consumes: `SquelchModel`, `MonitorState`, `VariableHistory`, `latest` (Tasks 3, 5, 8, 9).
- Produces:
  - `update_screen!(m::SquelchModel, ::Val{MONITOR}, evt::KeyEvent) -> Nothing`
  - `view_screen(m::SquelchModel, ::Val{MONITOR}, f::Frame) -> Nothing`
  - `sorted_variable_names(m::SquelchModel) -> Vector{String}` — pure logic, unit tested (stable ordering for the table/selection so tests and rendering agree)

- [ ] **Step 1: Write a failing unit test for `sorted_variable_names`**

Create `test/monitor_test.jl`:

```julia
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
        Squelch.update_screen!(m, Val(Squelch.MONITOR), Squelch.KeyEvent(:down, nothing))
        @test m.selected_var_idx == 1  # only one variable, stays at 1
    end
end
```

Add `include("monitor_test.jl")` to `test/runtests.jl`.

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/monitor_test.jl")' 2>&1 | tail -20
```

Expected: `UndefVarError: sorted_variable_names not defined` (or `KeyEvent` constructor mismatch — if Tachikoma's `KeyEvent` takes different field names/order than `(:down, nothing)`, adjust the test to match Tachikoma's actual `KeyEvent` struct definition, which you can check with `fieldnames(KeyEvent)` in a REPL before finalizing this test).

- [ ] **Step 3: Implement**

Append to `src/app.jl`:

```julia
function sorted_variable_names(m::SquelchModel)
    m.state === nothing && return String[]
    return sort(collect(keys(m.state.variables)))
end

function update_screen!(m::SquelchModel, ::Val{MONITOR}, evt::KeyEvent)
    names = sorted_variable_names(m)
    @match (evt.key, evt.char) begin
        (:char, 'q') => (m.quit = true)
        (:char, 'c') => (m.mode = CONFIGURE)
        (:down, _) => (m.selected_var_idx = min(m.selected_var_idx + 1, max(length(names), 1)))
        (:up, _) => (m.selected_var_idx = max(m.selected_var_idx - 1, 1))
        (:enter, _) => (m.show_chart = !isempty(names))
        (:escape, _) => (m.show_chart = false)
        _ => nothing
    end
    return nothing
end

function view_screen(m::SquelchModel, ::Val{MONITOR}, f::Frame)
    buf = f.buffer
    inner = render(Block(title="Monitor (c: configure, enter: chart selected var, q: quit)"), f.area, buf)
    rows = split_layout(Layout(Vertical, [Fill(), Fixed(10)]), inner)
    length(rows) < 2 && return
    log_area, table_area = rows[1], rows[2]

    loglines = m.state === nothing ? String[] : m.state.log_lines
    render(ScrollPane(loglines; following=true), log_area, buf)

    names = sorted_variable_names(m)
    headers = ["Name", "Value", "Unit"]
    table_rows = [
        [n, string(something(latest(m.state.variables[n]), m.state.variables[n].latest_raw)), m.state.variables[n].unit]
        for n in names
    ]
    render(Table(headers, table_rows; block=Block(title="Variables")), table_area, buf)

    if m.show_chart && !isempty(names)
        selected = names[clamp(m.selected_var_idx, 1, length(names))]
        h = m.state.variables[selected]
        chart_area = f.area
        series = [DataSeries(h.values; label=selected)]
        render(Chart(series; block=Block(title="$selected ($(h.unit))")), chart_area, buf)
    end
    return nothing
end
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/monitor_test.jl")'
```

Expected: all tests pass (fix any `KeyEvent` construction mismatch found in Step 2 first).

- [ ] **Step 5: Run full suite**

```bash
cd /Users/alex/workspace/Squelch.jl
JULIA_NUM_THREADS=2 julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all pass.

- [ ] **Step 6: Manual verification of the full flow**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'using Squelch; Squelch.main(String[])'
```

Connect to a port (or verify Connect screen renders if none available), confirm Configure screen shows incoming lines and lets you add a rule, confirm `esc`/`m` moves to Monitor and the variable table shows the rule's values updating, confirm `enter` shows a chart, `q` quits. Note results in the commit message.

- [ ] **Step 7: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add src/app.jl test/monitor_test.jl test/runtests.jl
git commit -m "Add Monitor screen (log + variable table) and chart overlay

Manually verified: connect -> configure -> monitor -> chart -> quit flow."
```

---

### Task 11: Example garmin-ftms-sync-esp32 profile

**Files:**
- Create: `profiles/garmin-ftms.toml`
- Create: `test/example_profile_test.jl`

**Interfaces:**
- Consumes: `load_ruleset` (Task 4).
- Produces: a ready-to-load example `Ruleset` TOML file at `profiles/garmin-ftms.toml`, matching the JSON shape seen in `ctrl_dispatch.c` (`{"cmd":"status","connected":...}`, `{"cmd":"speed","ok":...}`, `{"cmd":"incline","ok":...}`, `{"cmd":"list","devices":[...]}`).

- [ ] **Step 1: Write failing test**

`test/example_profile_test.jl`:

```julia
@testset "Example garmin-ftms profile" begin
    path = joinpath(pkgdir(Squelch), "profiles", "garmin-ftms.toml")
    @test isfile(path)
    rs = Squelch.load_ruleset(path)
    @test rs.device_name == "garmin-ftms"
    @test rs.baud == 115200
    @test !isempty(rs.rules)

    state = Squelch.MonitorState(rs)
    Squelch.process_line!(state, "{\"cmd\":\"status\",\"connected\":true}")
    @test haskey(state.variables, "connected")
end
```

Add `include("example_profile_test.jl")` to `test/runtests.jl`.

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/example_profile_test.jl")' 2>&1 | tail -20
```

Expected: fails with "no such file" since `profiles/garmin-ftms.toml` doesn't exist yet.

- [ ] **Step 3: Create the profile**

`profiles/garmin-ftms.toml`:

```toml
device_name = "garmin-ftms"
baud = 115200

[[rules]]
name = "connected"
unit = ""

[rules.extractor]
kind = "json_field"
path = ["connected"]

[[rules]]
name = "cmd"
unit = ""

[rules.extractor]
kind = "json_field"
path = ["cmd"]
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd /Users/alex/workspace/Squelch.jl
julia --project=. -e 'include("src/Squelch.jl"); using .Squelch; using Test; include("test/example_profile_test.jl")'
```

Expected: passes. (`pkgdir(Squelch)` requires `Squelch` to be loaded as a proper package, not just `include`d — if `pkgdir` returns `nothing` in this ad-hoc invocation, run via `Pkg.test()` instead where the package is loaded normally, or hardcode the path relative to `@__DIR__` in the test as a fallback: `joinpath(@__DIR__, "..", "profiles", "garmin-ftms.toml")`.)

- [ ] **Step 5: Run full suite and commit**

```bash
cd /Users/alex/workspace/Squelch.jl
JULIA_NUM_THREADS=2 julia --project=. -e 'using Pkg; Pkg.test()'
git add profiles/garmin-ftms.toml test/example_profile_test.jl test/runtests.jl
git commit -m "Add example garmin-ftms-sync-esp32 profile"
```

---

### Task 12: Full README and final docs pass

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (docs only).

- [ ] **Step 1: Write full README**

`README.md`:

```markdown
# Squelch.jl

A terminal-based, UI-configurable serial monitor for embedded devices.
Built for [garmin-ftms-sync-esp32](https://github.com/cluffa/garmin-ftms-sync-esp32)
but works with any device that writes line-oriented text or JSON over serial.

Not registered in any Julia registry.

## Install

    pkg> app add https://github.com/<you>/Squelch.jl

Make sure `~/.julia/bin` is on your `PATH` (required by Julia's Pkg Apps
feature).

## Usage

    squelch

1. **Connect**: pick a serial port and baud rate, press Enter.
2. **Configure**: incoming lines stream in on the left. Select a line,
   type a variable name (and unit), optionally a regex with one capture
   group (leave blank to extract a same-named JSON field), press Enter to
   add the rule. Press `s` to save the ruleset as a reusable profile.
3. **Monitor**: press `esc` or `m` to switch here. Raw log on top, live
   variable table below. Select a variable and press Enter to see its
   history as a chart. Press `c` to go back to Configure and add more
   rules without disconnecting.

A ready-made profile for garmin-ftms-sync-esp32 ships at
`profiles/garmin-ftms.toml` — copy it to
`~/.config/squelch/profiles/` to have it available from the Connect
screen (loading saved profiles from the Connect screen list is wired to
the same `profiles_dir()` used for saving).

## Development

    julia --project=. -e 'using Pkg; Pkg.test()'

The parsing core (extractors, rulesets, variable history, line dispatch)
and the serial reader loop (against a fake in-memory source) are unit
tested. The Tachikoma TUI itself is verified manually — see commit
messages for Tasks 8-10 for what was checked.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/alex/workspace/Squelch.jl
git add README.md
git commit -m "Write full README with install and usage instructions"
```

---

## Post-plan check

After Task 12, run the full suite one more time as a final gate:

```bash
cd /Users/alex/workspace/Squelch.jl
JULIA_NUM_THREADS=2 julia --project=. -e 'using Pkg; Pkg.test()'
```

Expected: all pass, 0 failures, 0 errors. This is the deliverable's Definition of Done per the spec.
