#!/usr/bin/env python3
"""Builds the asset pack the game downloads on first run.

Reads a checkout of the original game (https://github.com/Regalis11/scpcb, licensed CC BY-SA 3.0) and writes
  <out>/scpcb-assets-<version>.zip   GFX/, SFX/, Data/, Loadingscreens/, CREDITS.txt and NOTICE.txt, without the files in EXCLUDE
  <out>/manifest.json                version, upstream commit, size, sha256 and download URLs

The original's .avi videos (MPEG-4, which Godot cannot play) are not copied; GFX/menu/startup_*.avi is re-encoded to
Ogg Theora (.ogv, no audio: the .ogg next to it is the soundtrack) with ffmpeg, which has to be on PATH.

Upload both files as assets of the `assets-v1` release of this repository. tools/fetch_assets.py (and
tools/fetch_assets.ps1) read manifest.json, download the zip, check the sha256 and unpack it into ./assets.

  python3 tools/build_asset_pack.py --source "$SCP_BLITZ_SRC" --out build/assets --version 1 \
      --base-url https://github.com/dion-gionet/scp-cb-godot/releases/download/assets-v1
"""
import argparse
import fnmatch
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

INCLUDE_DIRS = ["GFX", "SFX", "Data", "Loadingscreens"]
INCLUDE_FILES = {"Credits.txt": "CREDITS.txt"}

# Not covered by CC BY-SA 3.0 (see notice_text)
EXCEPTIONS = {
    "paths": ["GFX/npcs/173*", "GFX/map/173_2*", "GFX/menu/173back.*"],
    "terms": "non-commercial use only; resembles \"Untitled 2004\" by Izumi Kato",
}

# Videos the game plays, re-encoded for Godot: source .avi -> the same path with .ogv
CONVERT_VIDEOS = ["GFX/menu/startup_*.avi"]
THEORA_QUALITY = "8"

# Not redistributed. Patterns are matched against the path inside the pack, case-insensitively.
EXCLUDE = [
    # unused by the port, large
    "*.avi",
    # binaries with their own licences, and thumbnail caches
    "*.dll", "*.exe", "*/Thumbs.db", "*/.DS_Store",
]


def notice_text(commit: str, videos: bool) -> str:
    return """These files are the GFX, SFX, Data and Loadingscreens folders of SCP - Containment Breach v1.3.11
(https://github.com/Regalis11/scpcb, commit {commit}), by Regalis and the contributors listed in CREDITS.txt.

License: Creative Commons Attribution-ShareAlike 3.0 Unported, https://creativecommons.org/licenses/by-sa/3.0/

Changes: {changes}
Left out: {excluded} (the original .avi videos, binaries with their own licences,
thumbnail caches).

Exception: the SCP-173 statue models and textures (GFX/npcs/173*, GFX/map/173_2*, GFX/menu/173back.*) are not covered by that
license. They resemble "Untitled 2004" by Izumi Kato and may be used for non-commercial purposes only.

Used by https://github.com/dion-gionet/scp-cb-godot, a port of the game to Godot.
""".format(commit=commit, excluded=", ".join(EXCLUDE), changes=(
        "the startup videos (GFX/menu/startup_*.avi) are re-encoded to Ogg Theora (.ogv) so Godot can play them;\nthe other files are unchanged."
        if videos else "none; the files are unchanged."))


def excluded(relative: str) -> bool:
    return any(fnmatch.fnmatch(relative.lower(), pattern.lower()) for pattern in EXCLUDE)


def converted_videos(source: Path, work: Path) -> dict[str, Path]:
    """Maps the pack path of each re-encoded video to the file ffmpeg wrote."""
    out: dict[str, Path] = {}
    for path in sorted((source / "GFX").rglob("*.avi")):
        relative = path.relative_to(source).as_posix()
        if not any(fnmatch.fnmatch(relative.lower(), pattern.lower()) for pattern in CONVERT_VIDEOS):
            continue
        if shutil.which("ffmpeg") is None:
            raise SystemExit("ffmpeg is needed to convert " + relative + " (install it, or build without the startup videos: --no-videos)")
        target = work / (path.stem + ".ogv")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-an", "-c:v", "libtheora", "-q:v", THEORA_QUALITY, str(target)], check=True)
        out[relative[:-4] + ".ogv"] = target
    return out


def git_commit(source: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", required=True, type=Path, help="checkout of the original game")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--version", required=True, help="pack version, e.g. 1")
    parser.add_argument("--base-url", action="append", default=[], help="where the zip will be published (repeat for mirrors)")
    parser.add_argument("--commit", help="upstream commit to record when --source is not a git checkout")
    parser.add_argument("--no-videos", action="store_true", help="leave the startup videos out instead of re-encoding them (no ffmpeg needed; the game skips them)")
    args = parser.parse_args()

    source: Path = args.source
    if not all((source / folder).is_dir() for folder in INCLUDE_DIRS):
        print(f"{source} does not look like the original game (missing {', '.join(INCLUDE_DIRS)})", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    name = f"scpcb-assets-{args.version}.zip"
    archive = args.out / name

    commit = git_commit(source)
    if commit == "unknown" and args.commit:
        commit = args.commit
    count = 0
    skipped = []
    with tempfile.TemporaryDirectory() as work, zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as pack:
        videos = {} if args.no_videos else converted_videos(source, Path(work))
        for stored, converted in videos.items():
            pack.write(converted, stored)
            count += 1
        for folder in INCLUDE_DIRS:
            for path in sorted((source / folder).rglob("*")):
                if not path.is_file():
                    continue
                relative = path.relative_to(source).as_posix()
                if excluded(relative):
                    skipped.append(relative)
                    continue
                pack.write(path, relative)
                count += 1
        for original, stored in INCLUDE_FILES.items():
            if (source / original).is_file():
                pack.write(source / original, stored)
                count += 1
        pack.writestr("NOTICE.txt", notice_text(commit, bool(videos)))
        count += 1

    manifest = {
        "version": args.version,
        "license": "CC BY-SA 3.0",
        "license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
        "upstream": {"repository": "https://github.com/Regalis11/scpcb", "commit": commit},
        "exceptions": EXCEPTIONS,
        "files": count,
        "archive": {
            "name": name,
            "size": archive.stat().st_size,
            "sha256": sha256_of(archive),
            "urls": [f"{base.rstrip('/')}/{name}" for base in args.base_url],
        },
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"{count} files, {archive.stat().st_size / 1e6:.1f} MB -> {archive}")
    print(f"excluded {len(skipped)}: {', '.join(skipped[:12])}{' ...' if len(skipped) > 12 else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
