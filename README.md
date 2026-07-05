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
   history as a chart. Press `c` to go back to Configure to add more
   rules without disconnecting.

A ready-made profile for garmin-ftms-sync-esp32 ships at
`profiles/garmin-ftms.toml` — copy it to
`~/.config/squelch/profiles/` to have it available for reuse.

## Development

    julia --project=. -e 'using Pkg; Pkg.test()'

The parsing core (extractors, rulesets, variable history, line dispatch)
and the serial reader loop (against a fake in-memory source) are unit
tested. The Tachikoma TUI itself was verified headlessly using
`Tachikoma.TestBackend`/`buffer_to_text` to render each screen to plain
text and check it for correctness — see the Task 8-10 commit messages
for what was checked.
