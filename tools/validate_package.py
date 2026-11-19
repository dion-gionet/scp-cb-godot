#!/usr/bin/env python3
"""Checks an exported Windows build: the executable and pck exist, the pck holds the project data (room_fill.json) and
does not embed the game files, and an `assets` folder with GFX, SFX and Data sits next to the executable
(ContentPaths looks there). Pass --copy-assets to copy ./assets next to the build first.

  godot --headless --path . --export-release "Windows Desktop" build/scp-cb-godot-port.exe
  python3 tools/validate_package.py build --copy-assets
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

REQUIRED_DIRS = ["GFX", "SFX", "Data"]
REQUIRED_FILES = ["Data/rooms.ini", "Data/materials.ini", "Data/NPCs.ini", "GFX/menu/back.jpg"]


def check(build: Path) -> list[str]:
    problems = []
    exes = list(build.glob("*.exe"))
    if not exes:
        return [f"no .exe in {build}"]
    for exe in exes:
        pck = exe.with_suffix(".pck")
        if not pck.is_file():
            problems.append(f"missing {pck.name} next to {exe.name}")
            continue
        text = pck.read_bytes()
        if b"room_fill.json" not in text:
            problems.append(f"{pck.name} does not contain data/room_fill.json")
        if b"res://assets/" in text:
            problems.append(f"{pck.name} embeds the assets folder (add assets/* to the preset's exclude_filter)")
        imported = {m.decode("utf-8", "replace") for m in re.findall(rb"\.godot/imported/([^\x00]+)", text)}
        stray = sorted(n for n in imported if not n.startswith(("icon.svg", "logo.png")))
        if stray:
            problems.append(f"{pck.name} holds {len(stray)} imported copies of the game files, e.g. {stray[0]} (assets/.gdignore keeps the editor from importing them)")
    assets = build / "assets"
    for name in REQUIRED_DIRS:
        if not (assets / name).is_dir():
            problems.append(f"missing assets/{name} next to the executable")
    if all((assets / name).is_dir() for name in REQUIRED_DIRS):
        lower = {p.relative_to(assets).as_posix().lower() for p in assets.rglob("*") if p.is_file()}
        problems += [f"missing assets/{f}" for f in REQUIRED_FILES if f.lower() not in lower]
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build", type=Path)
    parser.add_argument("--copy-assets", action="store_true")
    args = parser.parse_args()
    if args.copy_assets:
        source = Path(__file__).resolve().parent.parent / "assets"
        if not source.is_dir():
            print(f"{source} not found; run tools/fetch_assets.py", file=sys.stderr)
            return 1
        shutil.copytree(source, args.build / "assets", dirs_exist_ok=True)
    problems = check(args.build)
    for problem in problems:
        print("FAIL", problem)
    if not problems:
        print(f"{args.build}: package ok")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
