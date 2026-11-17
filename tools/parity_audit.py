"""Static parity audit: Blitz source symbols, asset strings, branches and constants that never show up in the port.

  python tools/parity_audit.py [--out tests/parity.json] [--kind functions|sounds|events|blocks|all]   (Blitz source: $SCP_BLITZ_SRC, required)

A lead list, not a verdict: a function may be ported under another name. Each row gives the Blitz file:line so the
agent can read the code and compare. Assets are matched by file stem (case-insensitive) anywhere in scripts/, data/ or autoload/.

`blocks` (parity_blocks.py) splits UpdateNPCs, UpdateEvents, the item use code and Use914 into their Case blocks, maps
each to the port files that handle it, and lists the block's number literals and nested Case branches that the port
files do not contain.
"""
import argparse
import json
import os
import re

import parity_blocks

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.environ.get("SCP_BLITZ_SRC")
if not SRC:
    raise SystemExit("set SCP_BLITZ_SRC to a checkout of https://github.com/Regalis11/scpcb")
ASSET = re.compile(r'"((?:SFX|GFX)[/\x5c][^"]+?\.(?:ogg|wav|mp3|jpg|png|b3d|x|rmesh))"', re.I)


def asset_stem(path):
    return re.split(r"[/\x5c]", path)[-1].rsplit(".", 1)[0].lower()
BB = ["Main.bb", "MapSystem.bb", "NPCs.bb", "UpdateEvents.bb", "Items.bb", "Particles.bb", "Update.bb", "Save.bb", "Achievements.bb", "Menu.bb"]


def port_text():
    chunks = []
    for folder in ("scripts", "autoload", "data"):
        for base, _, names in os.walk(os.path.join(ROOT, folder)):
            for name in names:
                if name.endswith((".gd", ".json", ".tscn", ".ini")):
                    with open(os.path.join(base, name), encoding="utf-8", errors="replace") as handle:
                        chunks.append(handle.read().lower())
    return "\n".join(chunks)


def snake(name):
    return re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()


def functions(text):
    rows = []
    for file in BB:
        path = os.path.join(SRC, file)
        with open(path, encoding="latin-1") as handle:
            for number, line in enumerate(handle, 1):
                match = re.match(r"\s*Function\s+(\w+)", line, re.I)
                if match:
                    name = match.group(1)
                    if snake(name) not in text and name.lower() not in text:
                        rows.append({"file": file, "line": number, "name": name})
    return rows


def sounds(text):
    rows, seen = [], set()
    for file in BB:
        with open(os.path.join(SRC, file), encoding="latin-1") as handle:
            for number, line in enumerate(handle, 1):
                if line.lstrip().startswith(";"):
                    continue
                for asset in ASSET.findall(line):
                    stem = asset_stem(asset)
                    if stem not in seen and stem not in text:
                        seen.add(stem)
                        rows.append({"file": file, "line": number, "asset": asset})
    return rows


def events(text):
    rows, seen = [], set()
    with open(os.path.join(SRC, "UpdateEvents.bb"), encoding="latin-1") as handle:
        for number, line in enumerate(handle, 1):
            match = re.match(r'\s*Case\s+"([\w\-]+)"', line, re.I)
            if match and match.group(1).lower() not in seen:
                seen.add(match.group(1).lower())
                if match.group(1).lower() not in text:
                    rows.append({"file": "UpdateEvents.bb", "line": number, "event": match.group(1)})
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(ROOT, "tests", "parity.json"))
    parser.add_argument("--kind", default="all")
    args = parser.parse_args()
    text = port_text()
    report = {}
    if args.kind in ("all", "functions"):
        report["functions"] = functions(text)
    if args.kind in ("all", "sounds"):
        report["assets"] = sounds(text)
    if args.kind in ("all", "events"):
        report["events"] = events(text)
    if args.kind in ("all", "blocks"):
        report["blocks"] = parity_blocks.audit(SRC, ROOT)
    with open(args.out, "w") as handle:
        json.dump(report, handle, indent=1)
    for key, rows in report.items():
        if key != "blocks":
            print("%s: %d not found in the port" % (key, len(rows)))
    if "blocks" in report:
        print(parity_blocks.summary(report["blocks"]))
    print("details:", args.out)


if __name__ == "__main__":
    main()
