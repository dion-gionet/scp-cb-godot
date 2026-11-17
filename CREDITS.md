# Credits

This project is a port of **SCP - Containment Breach** (v1.3.11) from Blitz3D to Godot. The game's design, code,
models, textures, sounds and music were made by the original team and contributors, and the SCP Foundation content it
is based on was written by the SCP Wiki's authors.

- Original game: [Regalis11/scpcb](https://github.com/Regalis11/scpcb), by Joonas Rikkonen ("Regalis") and Undertow Games,
  with the contributors listed in [`CREDITS-ORIGINAL.txt`](CREDITS-ORIGINAL.txt) (the original's `Credits.txt`, unmodified;
  the downloaded game files also ship it as `CREDITS.txt`).
- SCP Foundation content (SCP-173 by Moto42, SCP-106 by Dr Gears, SCP-049 by Gabriel Jade and the others named in
  `CREDITS.txt`): [scp-wiki.net](https://scp-wiki.net), licensed CC BY-SA 3.0 by their authors.
- Music includes tracks by Kevin MacLeod; see `CREDITS.txt` for the other composers and sound designers.

## Licence

The original game, its source and (as far as its README states) its assets are licensed under
[Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/). This port is a
derivative of that work and is released under the same licence (see `LICENSE`).

## Changes

The source code here is a new implementation in GDScript, written by reading the original Blitz3D source.
`data/room_fill.json` is extracted from the original `MapSystem.bb`. The game files that releases bundle (and `tools/fetch_assets.py` fetches) are the original
`GFX`, `SFX` and `Data` folders (upstream commit `edb8fe0`), unmodified except that the startup videos are re-encoded to Ogg Theora, minus the files listed in `tools/build_asset_pack.py` (`EXCLUDE`).

## Restrictions

The SCP-173 statue model and textures (`GFX/npcs/173*`, `GFX/menu/173back.*`) are an exception to the CC BY-SA licence of
this work. They resemble *Untitled 2004* by Izumi Kato and may be used for non-commercial purposes only. Remove or
replace them before any commercial use.

## Not included

The original DLLs and executables, and the game's startup videos, are not redistributed.
