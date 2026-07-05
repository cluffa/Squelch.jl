# Squelch.jl — Design

**Date:** 2026-07-05
**Status:** Approved for planning

## Purpose

A general-purpose serial monitor for embedded devices, written in pure(-ish)
Julia, driven initially by the needs of
[garmin-ftms-sync-esp32](https://github.com/cluffa/garmin-ftms-sync-esp32) but
usable with any device that talks line-oriented text/JSON over a serial port.
It should let the user watch raw log output, extract named variables from
that output, and plot/tabulate them live — all configured from within the
running app, with no code required per device.

## Non-goals

- Not a full logic analyzer or protocol decoder (no binary framing, no
  checksums/CRC awareness beyond what a user-supplied regex can express).
- Not a registered Julia package. Installed only via git URL through Julia's
  Pkg Apps mechanism.
- Not a web UI. Runs entirely as a terminal application.

## Architecture

Three layers, one Julia package.

### 1. Serial layer

Uses [LibSerialPort.jl](https://github.com/JuliaIO/LibSerialPort.jl) for port
listing, opening, and reading. Note this wraps the compiled C
`libserialport` via `ccall` — it is not a from-scratch Julia serial
implementation, but it is the standard, maintained way to do serial I/O in
Julia and was specified directly as acceptable.

- `get_port_list()` to enumerate ports for the Connect screen.
- `LibSerialPort.open(port, baud)` to open.
- A background task reads with `readline(sp)` in a loop and posts each line
  as a Tachikoma `TaskEvent` via `spawn_task!`/a repeating read loop, so the
  UI never blocks on serial I/O.
- Reconnect-on-error: if the read loop errors (device unplugged), the task
  posts a `TaskEvent(:disconnected, ...)` and the UI returns to the Connect
  screen rather than crashing.

### 2. Parsing / configuration layer

Core type: a `Ruleset` — the saved, reloadable definition of how to talk to
one device.

```julia
struct VariableRule
    name::String
    unit::String
    extractor::Extractor   # JSONField(path) | RegexCapture(pattern, group)
end

struct Ruleset
    device_name::String
    baud::Int
    rules::Vector{VariableRule}
end
```

Every incoming line is run through the ruleset:

1. Try parsing the line as JSON. If it parses, try each `JSONField` rule
   against it.
2. Try each `RegexCapture` rule against the raw line regardless of (1).
3. If any rule matched, update that variable's value/history — the line
   still also goes to the raw log buffer (nothing is hidden, matching
   lines are just *also* summarized in the variable table).
4. If nothing matched, the line goes to the raw log buffer only.

Rulesets serialize to/from TOML at `~/.config/squelch/profiles/<name>.toml`.
A `profiles/garmin-ftms.toml` ships in the repo as a ready-to-load example
matching `ctrl_dispatch`'s JSON shape (`{"cmd":...}` responses), loadable
from the Connect screen — not hardcoded into the app logic.

### 3. UI layer (Tachikoma.jl)

A single Tachikoma `Model` with a `mode` field driving three screens:

- **Connect** — list of ports (from `get_port_list()`) + baud rate input +
  "load saved profile" list (scanned from the config dir). Selecting a port
  and confirming opens it and moves to Monitor (with an empty/default
  ruleset) or Configure.
- **Configure** — live incoming lines stream in a `ScrollPane`; selecting one
  offers "extract from this line" — if it parsed as JSON, a list of its
  fields to pick from; otherwise a regex text input with live match
  preview. Naming a field + unit adds a `VariableRule` to the in-progress
  `Ruleset` immediately (visible in a running list), and "Save profile"
  writes the TOML.
- **Monitor** — default split layout: log `ScrollPane` (top), variable
  `Table` (bottom) showing name/value/unit updated live. Selecting a
  variable row and pressing a key (e.g. `Enter`) opens a `Chart`/`Sparkline`
  overlay for that variable's history ring buffer. `c` returns to Configure
  to add more rules without disconnecting.

State updates flow through `update!(m::SquelchModel, evt::TaskEvent)` for
serial data and `update!(m::SquelchModel, evt::KeyEvent)` for navigation,
per Tachikoma's Elm-style Model/update!/view pattern.

## Data flow summary

```
serial port --readline--> background task --TaskEvent--> update!
                                                             |
                                        +--------------------+--------------------+
                                        |                                         |
                                matched a VariableRule?                    always
                                        |                                         |
                                update variable history                   append to log buffer
                                        |                                         |
                                        +--------------------+--------------------+
                                                             |
                                                          view (Frame)
```

## Packaging

`Project.toml` includes:

```toml
[apps]
squelch = {}
```

with a `(@main)(ARGS)::Cint` entrypoint in the package module (Julia's
[Pkg Apps](https://pkgdocs.julialang.org/dev/apps/) feature — experimental,
requires `~/.julia/bin` on `PATH`). Installed with:

```
pkg> app add https://github.com/<user>/Squelch.jl
```

Not registered in the General registry or any other registry.

## Testing

- Ruleset TOML round-trip (save → load → equal).
- `Extractor` matching: JSON field extraction and regex capture against a
  table of sample lines (including real garmin-ftms-sync-esp32 log/JSON
  samples).
- Variable history ring buffer (push, overflow eviction, latest-value
  query).
- The TUI itself (Tachikoma `view`/rendering, live serial interaction) is
  not meaningfully unit-testable — verified manually by running against a
  real or simulated serial device. This is a known/accepted gap, not
  something the plan should fake coverage for.

## Open questions / explicitly deferred

- Multiple simultaneous device connections (currently: one port at a time).
- Exporting variable history (CSV/plot export) — not requested, can be
  added later without architecture changes (history ring buffers already
  hold the data).
