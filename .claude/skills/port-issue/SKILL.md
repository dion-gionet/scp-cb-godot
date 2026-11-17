---
name: port-issue
description: Work one port-vs-original difference from report to verified fix - reproduce, spec from the Blitz source, regression test, fix, verify. Use when asked to fix a gap between the port and SCP:CB 1.3.11, or when a parity hunt finds one.
---

# Working a port-vs-original difference

The goal is always to match the original (the Blitz source of 1.3.11, a checkout of https://github.com/Regalis11/scpcb at `$SCP_BLITZ_SRC`, see CLAUDE.md, is the authority), not "looks fine". Do the cheap steps first; the full suite runs once at the end, never per edit.

## 1. Reproduce
Use the dev server, not a new scenario: `python tools/dev.py start --seed N [--window]`, then `cmd teleport room=<name>`, `cmd advance seconds=..`, `cmd state`, `cmd console line=".."`, `cmd shot path=..`, `cmd trace path=..`. `--window` is needed for screenshots. Keep the "before" state and shots. Always `python tools/dev.py stop` when done.

If the Blitz source shows the port already matches the original, it is not a gap: do not invent a fix, say what you compared.

## 2. Spec
Find the code in the Blitz source. Write down the exact conditions, constants, timers (70 Hz), order of operations, sounds and textures with `File.bb:line` references, and what the port does differently.

## 3. Regression test
Add `_scn_<name>` to the matching `scripts/tests/bot_*.gd`, register it in `bot_base.gd`, and see it fail on the unfixed code:
`SCP_BOT=1 SCP_SEED=9 SCP_BOT_ONLY=<name> SCP_REPORT=<file> timeout 200 <godot> --headless --path . --fixed-fps 70`.
Place the player near the room (`place_player`) and allow for random effects. Skip only for trivial fixes with no sensible test.

## 4. Fix
Match the Blitz code (constants, order, conditions) even where it looks odd, and follow the conventions in CLAUDE.md. If you add or rename a `class_name` script, run `<godot> --headless --path . --import` once so the class cache sees it.

## 5. Verify
The scenario passes, the neighbouring scenarios pass, and "after" shots show the difference gone. At the end run the full suite: `tests/run_seeds.ps1 -Seeds 9,12345,777,3682601521,4242,99,2024 -Only full -FixedFps` must show 0 failures.

## Comparing with the running original
If you can run the original (Blitz3D build of 1.3.11), compare at the same seed and place: the same seed gives the same facility and event rolls, because the port replays Blitz's CreateMap, FillRoom draws and InitEvents. Still random in the port: doors' and FillRoom items after a conditional draw, the AccessCode, and seeds whose first draw picks the CWM loading screen. Align the cameras with `python tools/dev.py cmd place x=.. z=.. yaw=.. pitch=..` using the numbers from the original's `status` console command, then `cmd shot path=..`.

- **Room hunt**: `python tools/room_hunt.py capture --out <dir> --shots --align <file>` walks every room kind in the port (sound log and screenshot); `room_hunt.py compare --port <dir> --original <orig>` ranks rooms against screenshots of the original; without the original, `room_hunt.py expected` gives the Blitz code's sound list per room.
- **The original's numbers**: when you pin one down (from the source or by measuring the original), add it to `tests/fixtures/original.json` and measure it in the `golden` scenario.
- Without the original, do not guess: say it could not be run and give any conclusion as low confidence.
