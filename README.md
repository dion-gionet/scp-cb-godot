# SCP - Containment Breach (Godot port)

A port of [SCP: Containment Breach](https://github.com/Regalis11/scpcb) 1.3.11 from Blitz3D to Godot 4.7. The aim is to match the original: the same map
generator, rooms, events, NPCs, items, timings and numbers, read from the Blitz source rather than guessed.

The game's data (models, textures, sounds, rooms) is not in this repository. Releases include it in an `assets/` folder
next to the executable. These are the original game's `GFX`, `SFX`, `Data` and `Loadingscreens` folders (CC BY-SA 3.0, see `CREDITS.md`).

To run from source, fetch the same files once (about 210 MB, checked against a sha256) from this repository's
`assets-v1` release into `assets/`, which git and the Godot editor ignore:

```
python3 tools/fetch_assets.py          # or, on Windows without Python:  .\tools\fetch_assets.ps1
```

`SCP_ASSET_MANIFEST` or `--manifest` points the fetch at another manifest, such as a mirror or a local file.
The pack itself is built from a checkout of the original game with `tools/build_asset_pack.py` and published as the
`assets-v1` release of this repository.

## Requirements

- [Godot 4.7.x](https://godotengine.org/) (Forward Plus renderer)
- The game files, in `assets/` (above)

## Running

Open the folder in Godot and run the project, or from a terminal: `godot --path .`

| Key / button | Action |
| --- | --- |
| W A S D | move |
| Shift / Ctrl | sprint / crouch |
| Space | blink (hold to keep the eyes shut) |
| Left mouse | interact, pick up, use the selected item |
| Tab | inventory |
| Esc | pause menu |
| F5 | quick save |
| F3 | developer console (enable it in the options if it is off) |

The console takes the original's commands (`help` lists them, three pages), plus a few additions such as `culling`.
Its debug menu and overlay show the player, NPCs, rooms and events.

## What is ported

The facility generator and all three zones, rooms with their doors, items, lifts, levers and cameras, and the room events
(the 74 event names of the original's `UpdateEvents.bb`; the one unused event is not ported). SCP-173, 106, 049 (and
049-2), 096, 008's zombies, 066, 372, 513-1, 860, 939, 966, 1048-A, 1499 and the tentacles of 035; the Nine-Tailed
Fox; the intro, the endings and the pocket and 1499 dimensions; the inventory, item uses, SCP-294, SCP-914, health,
infection, sanity and the blink system; saving and loading.

## Layout

| Folder | Contents |
| --- | --- |
| `autoload/` | `ContentPaths` (finds the original files, input map) and `GameState` (run state) |
| `scripts/world/` | map generator, rooms, doors, events, the facility |
| `scripts/npc/` | SCPs and human NPCs |
| `scripts/player/`, `scripts/items/`, `scripts/ui/`, `scripts/audio/`, `scripts/game/`, `scripts/intro/` | the rest of the game |
| `scripts/io/` | readers for the original formats (`.rmesh`, `.b3d`, `.x`) |
| `scripts/debug/` | the developer console |
| `data/room_fill.json` | what each room's FillRoom builds (doors, items, objects), extracted from the source |
| `tools/extract_fill_room.gd` | regenerates that file from `MapSystem.bb`: `godot --headless --path . -s tools/extract_fill_room.gd` |
| `shaders/` | room lightmap, glow and sky shaders |
| `scripts/tests/`, `tests/` | the playtest bot and its runners, and the checks that need no game files |

## Tests

To package a build: `godot --headless --path . --export-release "Windows Desktop" build/scp-cb.exe`, then
`python3 tools/validate_package.py build --copy-assets` copies `assets/` next to the executable and checks the build (the pck
must not embed the game files, which the preset's `exclude_filter` keeps out).

These need no game files, and run in CI on every pull request (`.github/workflows/check.yml`):

```
godot --headless --import                              # once, on a fresh checkout
godot --headless --path . -s tests/check_scripts.gd    # every script and scene compiles
godot --headless --path . -s tests/test_units.gd       # the inflate decoder, ini files, saves
python3 tests/test_asset_tools.py                      # the asset pack tools, offline
```

A bot plays the game headless and checks what it sees (it needs the game files). It writes a report, and a result line per scenario.

```powershell
# one scenario, in the background (no window focus), on one seed
.\tests\run_bot.ps1 -Seed 9 -Only room035

# several seeds at once, as fast as possible; -Only takes `fast`, `full` or a comma list of scenarios
.\tests\run_seeds.ps1 -Seeds 9,12345,777 -Only full -FixedFps
```

Reports go to `tests/reports/`, and `-Shots` on `run_bot.ps1` saves screenshots to `tests/shots/` (both ignored by git).
The scripts use the Godot named by `$env:GODOT`, or `godot` on the PATH; pass `-Godot <path>` to change that. Environment variables the bot reads: `SCP_BOT`, `SCP_SEED`, `SCP_BOT_ONLY`, `SCP_REPORT`, `SCP_SHOT`.

A scenario is a `_scn_<name>` function in `scripts/tests/`, listed in `scripts/tests/bot_base.gd`. If a script of the
bot does not compile, the bot stops with exit code 2, and a run in which no check ran reports FAIL;
`tests/check_scripts.gd` lists the scripts at fault (`godot --headless --path . --check-only --script res://<file>`
shows the errors of one script, with some harmless autoload messages).

## Licence

This is a non-commercial fan project. The code and the game files are licensed under CC BY-SA 3.0
(SPDX: `CC-BY-SA-3.0`; see `LICENSE` and
`CREDITS.md`), with one exception: the SCP-173 statue model and textures are not covered by that licence. They resemble
*Untitled 2004* by Izumi Kato and may be used for non-commercial purposes only.

## Disclaimer

This is an unofficial fan project, not affiliated with or endorsed by Regalis, Undertow Games or the SCP Foundation wiki.
