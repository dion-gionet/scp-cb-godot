#!/usr/bin/env python3
"""Splits the game files (./assets, see fetch_assets.py) into small zips for the web build.

  python3 tools/pack_web_assets.py --src assets --out build/web/web-assets

The browser downloads each part, extracts it into its own storage (scripts/io/web_assets.gd) and keeps it, so one part
is all that is ever held in memory. Writes part-000.zip, part-001.zip, ... and manifest.json next to them.
"""
import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

STORED = {".ogg", ".ogv", ".jpg", ".jpeg", ".png"}
SKIPPED = {"installed.json", ".gdignore"}


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def groups(files: list[Path], limit: int) -> list[list[Path]]:
    result: list[list[Path]] = [[]]
    size = 0
    for path in files:
        length = path.stat().st_size
        if result[-1] and size + length > limit:
            result.append([])
            size = 0
        result[-1].append(path)
        size += length
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--src", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--part-mb", type=int, default=40)
    args = parser.parse_args()

    src = args.src.resolve()
    files = sorted(p for p in src.rglob("*") if p.is_file() and p.name not in SKIPPED)
    if not any(p.relative_to(src).parts[0].lower() == "gfx" for p in files):
        print(f"{src} has no GFX folder: not the game files", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)

    parts = []
    for index, members in enumerate(groups(files, args.part_mb << 20)):
        name = f"part-{index:03d}.zip"
        target = args.out / name
        with zipfile.ZipFile(target, "w") as pack:
            for path in members:
                kind = zipfile.ZIP_STORED if path.suffix.lower() in STORED else zipfile.ZIP_DEFLATED
                pack.write(path, path.relative_to(src).as_posix(), compress_type=kind)
        parts.append({"name": name, "sha256": sha256_of(target), "size": target.stat().st_size, "files": len(members)})

    version = hashlib.sha256("".join(p["sha256"] for p in parts).encode()).hexdigest()[:16]
    manifest = {"version": version, "files": len(files), "parts": parts}
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    print(f"{len(files)} files in {len(parts)} parts, {sum(p['size'] for p in parts) >> 20} MB, version {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
