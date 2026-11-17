"""Room-by-room hunt for visual and audio differences between the port and the original.

  python tools/room_hunt.py expected [--out tests/hunt/expected_sounds.json]
      The sounds the Blitz code can play in each room: the asset strings of its FillRoom case and of every UpdateEvents case
      whose event InitEvents creates in that room. A static lead list: most of them are conditional.

  python tools/room_hunt.py capture --out DIR [--seconds 20] [--rooms room2,room3] [--shots] [--align FILE]
      Against a running dev server (python tools/dev.py start --seed N [--window]): for each room kind, teleport there (or to
      the spot FILE gives for it), record the sounds played for --seconds, and with --shots (needs --window) take a
      screenshot. Writes DIR/<room>.json (state, sounds) and DIR/<room>.png.
      FILE maps a room name to the numbers the original console's `status` prints there ({"x","y","z","yaw","pitch"}), so
      both cameras stand at the same spot; fill it while taking the original's screenshots (see the port-issue skill).

  python tools/room_hunt.py compare --port DIR [--original DIR] [--expected FILE] [--out DIR/report.md]
      Ranks the rooms: screenshots by mean difference against the original's DIR/<room>.png (a side-by-side picture
      DIR/<room>.diff.png per room), and sounds the original plays there (its DIR/<room>.json, or the expected list) that
      the port never played while captured.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)

import parity_audit  # noqa: E402
import parity_blocks  # noqa: E402


def _sound(asset):
    return asset.upper().startswith("SFX") and asset.lower().endswith((".ogg", ".wav"))


def expected(src):
    created = parity_blocks.created_events(src)
    rooms = {}

    def add(room, lines, first, last, origin):
        bucket = rooms.setdefault(room, {})
        for index in range(first, last + 1):
            line = lines[index]
            if line.lstrip().startswith(";"):
                continue
            for asset in filter(_sound, parity_audit.ASSET.findall(line)):
                bucket.setdefault(asset.replace("\\", "/"), "%s:%d" % (origin, index + 1))

    mapsys = parity_blocks.read(src, "MapSystem.bb")
    fill = next(i for i, line in enumerate(mapsys) if re.match(r"\s*Function\s+FillRoom\b", line, re.I))
    select = parity_blocks.select_lines(mapsys, r"\s*Select\s+r\\RoomTemplate\\Name", fill)[0]
    for label, first, last in parity_blocks.cases(mapsys, select):
        for room in parity_blocks.labels(label):
            add(room, mapsys, first, last, "MapSystem.bb")
    events = parity_blocks.read(src, "UpdateEvents.bb")
    for select in parity_blocks.select_lines(events, r"\s*Select\s+e\\EventName"):
        for label, first, last in parity_blocks.cases(events, select):
            for room in sorted(set().union(*(created.get(name, set()) for name in parity_blocks.labels(label)))):
                add(room, events, first, last, "UpdateEvents.bb")
    return {room: dict(sorted(found.items())) for room, found in sorted(rooms.items()) if found}


def capture(args):
    import dev
    port = args.dev_port
    rooms = dev.send({"cmd": "rooms"}, port)["rooms"]
    names = sorted({room["name"] for room in rooms})
    if args.rooms:
        wanted = set(args.rooms.split(","))
        names = [name for name in names if name in wanted]
    align = {}
    if args.align:
        with open(args.align) as handle:
            align = json.load(handle)
    os.makedirs(args.out, exist_ok=True)
    for line in ("godmode on", "disable173", "disable106"):
        dev.send({"cmd": "console", "line": line}, port)
    for name in names:
        reply = dev.send({"cmd": "teleport", "room": name}, port)
        if name in align:
            spot = dict(align[name], cmd="place")
            dev.send(spot, port)
        dev.send({"cmd": "advance", "seconds": 1.0}, port)
        dev.send({"cmd": "sounds", "on": True}, port)
        state = dev.send({"cmd": "advance", "seconds": args.seconds}, port, timeout=args.seconds + 120)
        sounds = dev.send({"cmd": "sounds", "on": False}, port)["sounds"]
        record = {"room": name, "teleport": reply.get("output"), "state": state.get("state"), "sounds": sounds}
        with open(os.path.join(args.out, name + ".json"), "w") as handle:
            json.dump(record, handle, indent=1)
        if args.shots:
            if name in align:
                dev.send(dict(align[name], cmd="place"), port)
            shot = dev.send({"cmd": "shot", "path": os.path.abspath(os.path.join(args.out, name + ".png"))}, port)
            if not shot.get("ok"):
                print("%s: no screenshot (%s)" % (name, shot.get("error")))
        print("%-20s %3d sounds" % (name, len(sounds)))


def _image_diff(port_png, original_png, out_png):
    from PIL import Image, ImageChops
    a = Image.open(port_png).convert("RGB")
    b = Image.open(original_png).convert("RGB").resize(a.size)
    diff = ImageChops.difference(a, b).convert("L")
    histogram = diff.histogram()
    mean = sum(value * count for value, count in enumerate(histogram)) / float(a.size[0] * a.size[1]) / 255.0
    side = Image.new("RGB", (a.size[0] * 3, a.size[1]))
    side.paste(a, (0, 0))
    side.paste(b, (a.size[0], 0))
    side.paste(ImageChops.invert(diff).convert("RGB"), (a.size[0] * 2, 0))
    side.save(out_png)
    return mean


def compare(args):
    expect = {}
    if args.expected and os.path.exists(args.expected):
        with open(args.expected) as handle:
            expect = json.load(handle)
    rows = []
    for name in sorted(os.listdir(args.port)):
        if not name.endswith(".json"):
            continue
        room = name[:-5]
        with open(os.path.join(args.port, name)) as handle:
            heard = {parity_audit.asset_stem(entry["sound"]) for entry in json.load(handle).get("sounds", [])}
        original_json = os.path.join(args.original, name) if args.original else ""
        if original_json and os.path.exists(original_json):
            with open(original_json) as handle:
                original_sounds = {entry["sound"]: "played" for entry in json.load(handle).get("sounds", [])}
            source = "original"
        else:
            original_sounds = expect.get(room, {})
            source = "expected"
        missing = sorted(sound for sound in original_sounds if parity_audit.asset_stem(sound) not in heard)
        diff = None
        port_png = os.path.join(args.port, room + ".png")
        original_png = os.path.join(args.original, room + ".png") if args.original else ""
        if os.path.exists(port_png) and original_png and os.path.exists(original_png):
            diff = _image_diff(port_png, original_png, os.path.join(args.port, room + ".diff.png"))
        rows.append({"room": room, "diff": diff, "missing": missing, "source": source, "heard": len(heard),
                     "refs": original_sounds})
    rows.sort(key=lambda row: (-(row["diff"] or 0.0), -len(row["missing"])))
    lines = ["# Room hunt", "", "| room | picture diff | sounds heard | not heard (the original's or the expected) |", "| --- | --- | --- | --- |"]
    for row in rows:
        diff = "%.3f" % row["diff"] if row["diff"] is not None else "-"
        missing = ", ".join("%s (%s)" % (parity_audit.asset_stem(sound), row["refs"][sound]) for sound in row["missing"][:8])
        if len(row["missing"]) > 8:
            missing += ", +%d" % (len(row["missing"]) - 8)
        lines.append("| %s | %s | %d | %s |" % (row["room"], diff, row["heard"], missing or "-"))
    out = args.out or os.path.join(args.port, "report.md")
    with open(out, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("\n".join(lines[:40]))
    print("report:", out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dev-port", type=int, default=int(os.environ.get("DEV_PORT", "7777")))
    sub = parser.add_subparsers(dest="action", required=True)
    e = sub.add_parser("expected")
    e.add_argument("--src", default=parity_audit.SRC)
    e.add_argument("--out", default=os.path.join(ROOT, "tests", "hunt", "expected_sounds.json"))
    c = sub.add_parser("capture")
    c.add_argument("--out", required=True)
    c.add_argument("--seconds", type=float, default=20.0)
    c.add_argument("--rooms", default="")
    c.add_argument("--shots", action="store_true")
    c.add_argument("--align", default="")
    m = sub.add_parser("compare")
    m.add_argument("--port", required=True)
    m.add_argument("--original", default="")
    m.add_argument("--expected", default=os.path.join(ROOT, "tests", "hunt", "expected_sounds.json"))
    m.add_argument("--out", default="")
    args = parser.parse_args()
    if args.action == "expected":
        result = expected(args.src)
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w") as handle:
            json.dump(result, handle, indent=1)
        print("%d rooms, %d sounds -> %s" % (len(result), sum(len(v) for v in result.values()), args.out))
    elif args.action == "capture":
        capture(args)
    else:
        compare(args)


if __name__ == "__main__":
    main()
