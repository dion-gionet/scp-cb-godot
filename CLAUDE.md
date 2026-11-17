# Guidelines for Claude

## Comments

- Do not add comments for obvious or self-explanatory logic. Clear names and simple control flow should speak for themselves.
- Only leave comments for complex logic, such as non-obvious algorithms, tricky invariants, workarounds for engine or game quirks, or code whose intent cannot be read from the code alone.

## Project

A faithful port of SCP: Containment Breach 1.3.11 from Blitz3D to Godot 4.7. Match the original (map generator, rooms, events, NPCs, items, timings, numbers), reading the Blitz source rather than guessing.

This folder is the git repository. Not in git:

- The directory `SCP_BLITZ_SRC` points to (a checkout of https://github.com/Regalis11/scpcb, kept outside this folder; the tools that read it require the variable) - the 1.3.11 Blitz3D source (`Main.bb`, `MapSystem.bb`, `NPCs.bb`, `UpdateEvents.bb`, ...). The authority for behaviour.
- `assets/` (ignored by git; `tools/fetch_assets.py` fills it) - the game's `GFX`, `SFX` and `Data`. `ContentPaths` reads all models, textures, sounds and INI data from it at run time. Never copy assets into `res://`.

## Setup

A fresh checkout has neither Godot, the assets nor the Blitz source. Put them outside the repo:

```bash
# Godot 4.7 (then: chmod +x, and use it wherever <godot> appears below)
curl -sSL -o g.zip https://github.com/godotengine/godot-builds/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip && unzip -qo g.zip

# Blitz3D source, the authority for behaviour (any location; point SCP_BLITZ_SRC at it)
git clone --depth 1 https://github.com/Regalis11/scpcb "$SCP_BLITZ_SRC"

python3 tools/fetch_assets.py     # the game files into assets/
<godot> --headless --import       # once, before the first run
```

## Conventions

- Blitz to Godot: z is negated, yaw numbers carry over (`rotation.y = deg_to_rad(yaw)`), Blitz pitch p becomes `rotation.x = -p`. RoomScale is 8/2048, and raw FillRoom numbers are in the room's scaled space. Logic runs at 70 Hz (`fps = delta * 70`).
- `data/room_fill.json` is generated from `MapSystem.bb` by `tools/extract_fill_room.gd`.
- Room events are `scripts/world/room*_event.gd`, registered in the `ROOM_EXTRAS` table in `scripts/world/facility_room.gd`. Their state is `facility.events.<group>.<field>` (`scripts/world/event_states.gd`). Ambient events are `_ev_<name>` in `scripts/world/ambient_events*.gd`; their state is `facility.ambient.state_of(room_key)`.
- Scripts used from several files have a `class_name`; use it instead of a `const X = preload(...)`. Type the facility as `FacilityMap` and a room as `FacilityRoom`.

## Structure

`FacilityMap` (`facility_map.gd`) is the world root and a thin facade; it was once 1300 lines of everything. Keep good code hygiene and keep it lean. These are defaults, not hard rules: when something is really unavoidable, do the pragmatic thing and say why in the commit message:

- Every room is built once at load (`rooms.build_all`), doors between rooms and point-to-room lookups: `facility.rooms` (`room_registry.gd`; `facility.room_name_at/room_at/record_at/doors_near` forward to it). The room drawing rule: `facility.drawing`. The MTF squad, announcements and camera check: `facility.mtf`. NPC gravity (NPCs.bb 5003-5096): `NpcGravity.apply` / `falls`; an NPC that moves on collision calls it instead of its own ground check.
- State a room event shares with other code or has to save goes in a group in `event_states.gd` rather than as a new `var` on `FacilityMap`. A group's `reset()` restores its defaults, and the bot's world reset calls `facility.events.reset()`. Anything saved needs a matching entry in `save_game.gd`; keep existing save keys unchanged.
- A new room event: a script in `scripts/world/`, an entry in `ROOM_EXTRAS`, a group in `event_states.gd` if it keeps state, and a bot scenario.
- Prefer splitting by responsibility when a file or function grows past about 600 or 100 lines. Exception: straight-line ports of a Blitz routine or table (`assign_all`, `refine`, `parse_rmesh`) keep the original's order, which matters (RNG draws), so they are fine whole.
- Next candidate if it grows again: the NPC spawn/remove helpers and lists (`spawn_*`, `humans`, `zombies008`, `scp966s`) still live on `FacilityMap`.
- Room scripts built for a non-grid chamber (`security_cam.gd`, `start_scene.gd`, `room2sl_scene.gd`, `dimension_1499.gd`) hold their `room` as `Node3D`; typing it `FacilityRoom` breaks them.

## Testing

- The bot plays the game headless; scenarios are `_scn_<name>` in `scripts/tests/bot_*.gd`, registered in `scripts/tests/bot_base.gd`. The files form one inheritance chain (`bot_base` -> `bot_world` -> `bot_173` -> `bot_items_ui` -> `bot_npcs` -> `bot_events` -> `bot_systems` -> `bot_tools` -> `playtest_bot`); put a new scenario in the file of its theme and keep each file reviewable. Tests reach internals as `facility.rooms.built`, `facility.events.*`, `facility.mtf.*`.
- Iterate on one scenario under a `timeout`:
  `SCP_BOT=1 SCP_SEED=9 SCP_BOT_ONLY=<name> SCP_REPORT=/tmp/x.txt timeout 200 <godot> --headless --path . --fixed-fps 70`
- Run the full suite once at the end: `tests/run_seeds.ps1 -Seeds 9,12345,777,3682601521,4242,99,2024 -Only full -FixedFps` (0 failures on all seven with the `assets-v1` pack). Without PowerShell, run one game per seed in parallel (at most one per core, about 2 GB each) with `SCP_BOT=1 SCP_SEED=<n> SCP_BOT_ONLY=full SCP_REPORT=<file> <godot> --headless --path . --fixed-fps 70` and read the `RESULT` and `FAIL` lines. Some random checks flake once; rerun before blaming a change.
- Asset packs are immutable releases; a fixed pack gets a new `assets-vN` tag. File names are matched case-insensitively (`ContentPaths`), so Linux needs nothing else.
- To keep a baseline while you edit, run it from a `git worktree` of the unchanged commit, with the game files hard-linked into its `assets/` (`cp -al assets/* <worktree>/assets/`): that folder already exists there (its `.gdignore` is tracked), so `ln -s` would nest the link inside it and the baseline would run without assets.
- Physics ticks at 60 Hz while the logic counts 70 Hz frames (`delta * 70`): measure durations in `delta * 70` sums, not in ticks or wall-clock timers (`golden` has a helper).
- Every room exists, but only the player's room and two rings of neighbours are solid (UpdateRooms' HideEntity rule): place the player in or next to the room under test with `place_player` (it calls `facility.after_teleport()`) before probing floors or walls, and allow for random effects.
- A parse error can make a scenario report a pass with no checks. `godot --headless --path . -s tests/check_scripts.gd` loads every script and scene with the autoloads in place and lists the broken ones (`--check-only --script` cannot see the autoloads). After adding a file with a `class_name`, run `godot --headless --import` first or other scripts report the class as not declared.
- Unknown members on a typed variable (`facility.nope`) still compile and fail only when run. After moving or renaming a member, grep the whole repo (scripts, `tests/`, strings such as the console's `EVENT_VARS`) for the old name.
- Review means matching gaps against the original, not console polish.

## Dev toolkit

- `python tools/dev.py start --seed N [--window]` starts the game with a JSON-lines control server (`scripts/debug/dev_server.gd`); then `dev.py cmd state|teleport room=..|advance seconds=..|console line=".."|shot path=..|trace path=..|rooms`, and `dev.py stop`. Screenshots need `--window`. The port defaults to `$DEV_PORT`.
- The `port-issue` skill (`.claude/skills/port-issue`) is the workflow: reproduce, spec, regression test, fix, verify.
- Hunters: `tools/parity_audit.py` (Blitz symbols/assets missing from the port; `--kind blocks` (`parity_blocks.py`) ranks every NPC, event, held-item and 914 Case block by the number literals and nested branches its port files lack), `tools/map_dump.py` (generated map per seed), `tools/room_hunt.py` (per room kind: the sounds the port plays against the Blitz code's list or the original's, and screenshot diffs against the original's at the same spot), the `soak` scenario (every room kind; `run_seeds.ps1` also prints engine errors), the `hitchhunt` tool (frames over 25 ms on each room kind's first visit, and the models and sounds still read during play; anything loaded on the spot belongs in the room's `build()` or `FacilityMap.PREWARM_MODELS`).
- `tests/fixtures/original.json` holds the original's numbers (derived from the Blitz code with a file:line, or measured in the running original) and the `golden` scenario measures the port against them in 70 Hz frames. Add a row when a number is pinned down; a measured value replaces a derived one.
- A screenshot that comes out too dark (the pocket dimension, most rooms) tells you nothing: turn on the debug menu's **Disable lighting** option (F4: every material unlit, no lightmaps) before judging textures, geometry or flicker. From the dev server: `dev.py cmd unlit on` (`off` to undo). `dev.py cmd pocket` sends the player into the pocket dimension, `teleport room=..` brings them out. The player's camera rolls in the pocket, so two frames of it are never equal.
- Screenshots in a cloud container: start `Xvfb :99 &`, then `DISPLAY=:99 python tools/dev.py start --window` (Godot falls back to OpenGL on llvmpipe). A windowed game takes about 2 GB, so do not run it beside four suite games. Start it with `setsid` so it outlives the shell.
- Deferred idea: an instrumented build of the original (the source compiles with a Blitz3D compiler such as the Blitz3D TSS fork) that writes a per-frame trace in the dev server's `trace` format, for numeric comparison.

## Refactoring

- Before a structural change, run the full suite on the unchanged code and keep the result; compare against it afterwards, check by check.
- Do renames with a script (regex over `scripts/` and `tests/`), commit in small steps, run the touched scenarios after each, and push each step.
- The structure is meant to make big refactors unnecessary: put new code where the Structure section says, and tidy as you go instead of letting it pile up.
