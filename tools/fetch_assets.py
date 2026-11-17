#!/usr/bin/env python3
"""Downloads the game files (see build_asset_pack.py) into ./assets, where the game and the editor find them.

  python3 tools/fetch_assets.py                     # into <project>/assets (ignored by git and by the Godot editor)
  python3 tools/fetch_assets.py --dest build/package/assets

The manifest URL can be changed with --manifest or SCP_ASSET_MANIFEST (a mirror, or a local file path).
"""
import argparse
import hashlib
import json
import os
import shutil
import sys
import urllib.request
import zipfile
from pathlib import Path

DEFAULT_MANIFEST = "https://github.com/dion-gionet/scp-cb-godot/releases/download/assets-v1/manifest.json"
STAMP = "installed.json"


def read(location: str) -> bytes:
    if "://" not in location:
        return Path(location).read_bytes()
    with urllib.request.urlopen(location, timeout=60) as response:
        return response.read()


def next_to(manifest: str, name: str) -> str:
    """`name` in the folder of the manifest, which is a URL or a file path."""
    if "://" in manifest:
        return manifest.rsplit("/", 1)[0] + "/" + name
    return str(Path(manifest).resolve().parent / name)


def installed_sha256(stamp: Path) -> str:
    try:
        return json.loads(stamp.read_text()).get("sha256", "")
    except (OSError, ValueError, AttributeError):    # missing or damaged: as if nothing was installed
        return ""


def download(url: str, target: Path) -> None:
    with urllib.request.urlopen(url, timeout=60) as response, target.open("wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while block := response.read(1 << 20):
            out.write(block)
            done += len(block)
            if total:
                print(f"\r  {done >> 20} / {total >> 20} MB", end="", flush=True)
    print()


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    default_dest = Path(__file__).resolve().parent.parent / "assets"
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest", type=Path, default=default_dest)
    parser.add_argument("--manifest", default=os.environ.get("SCP_ASSET_MANIFEST", DEFAULT_MANIFEST))
    parser.add_argument("--force", action="store_true", help="download again even if this version is installed")
    args = parser.parse_args()

    try:
        manifest = json.loads(read(args.manifest))
        archive = manifest["archive"]
        version, sha256, name = manifest["version"], archive["sha256"], archive["name"]
    except (OSError, ValueError, KeyError, TypeError) as error:     # URLError is an OSError
        print(f"could not read the manifest {args.manifest}: {error!r}", file=sys.stderr)
        return 1
    dest = args.dest.resolve()
    stamp = dest / STAMP
    if not args.force and installed_sha256(stamp) == sha256:
        print(f"{dest} is up to date (version {version})")
        return 0

    urls = archive.get("urls") or [next_to(args.manifest, name)]     # without urls: next to the manifest
    dest.mkdir(parents=True, exist_ok=True)
    temp = dest / "download.zip.part"
    for url in urls:
        print(f"downloading {url}")
        try:
            if "://" in url:
                download(url, temp)
            else:
                shutil.copyfile(url, temp)
        except OSError as error:
            print(f"  failed: {error}")
            continue
        if sha256_of(temp) == sha256:
            break
        print("  checksum mismatch")
    else:
        temp.unlink(missing_ok=True)
        print("could not download a valid copy", file=sys.stderr)
        return 1

    with zipfile.ZipFile(temp) as pack:
        pack.extractall(dest)       # zipfile drops absolute and ".." path components
    temp.unlink()
    (dest / ".gdignore").write_text("")     # keeps the Godot editor from importing thousands of files
    stamp.write_text(json.dumps({"version": version, "sha256": sha256}))
    print(f"installed {manifest['files']} files into {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
