"""Branch and constant coverage of the big Blitz dispatch blocks, used by parity_audit.py --kind blocks.

Each top-level Case of UpdateNPCs' `Select n\\NPCtype`, UpdateEvents' `Select e\\EventName`, the in-hand item code
(Main.bb `Select SelectedItem\\itemtemplate\\tempname` after the inventory) and Use914's `Select item\\itemtemplate\\name`
becomes a block. A block is matched to port files (an explicit table for NPCs, otherwise every script that holds the
case name as a string, `_ev_<name>` or in its file name). Then:

- literals: number literals of the block that no port file of it contains. A literal counts as found in any of its
  usual conversions: as is, /70 (frames to seconds), *70, *RoomScale (raw FillRoom units), /100 and *100.
- branches: the nested Cases (state machines, item settings) whose own literals are all missing, which is how an
  unported branch usually looks.

Literals 0-3, 0.5 and the angles 90/180/270/360 are skipped: they appear everywhere and prove nothing.
"""
import bisect
import os
import re

ROOM_SCALE = 8.0 / 2048.0
TRIVIAL = {0.0, 1.0, 2.0, 3.0, 0.5, 90.0, 180.0, 270.0, 360.0}
NUMBER = re.compile(r"(?<![\w.#$%])(\d+\.\d*|\.\d+|\d+)(?![\w.])")
STRING = re.compile(r'"[^"]*"')

NPC_FILES = {
    "NPCtype173": ["npc/scp_173.gd"],
    "NPCtypeOldMan": ["npc/scp_106.gd"],
    "NPCtype096": ["npc/scp_096.gd"],
    "NPCtype049": ["npc/scp_049.gd"],
    "NPCtypeZombie": ["npc/scp_049_2.gd"],
    "NPCtypeGuard": ["npc/human_npc.gd", "npc/gunfire.gd"],
    "NPCtypeMTF": ["npc/mtf_unit.gd", "npc/gunfire.gd", "world/mtf_director.gd"],
    "NPCtypeD": ["npc/human_npc.gd"],
    "NPCtype5131": ["npc/scp_513_1.gd"],
    "NPCtype372": ["npc/scp_372.gd"],
    "NPCtypeApache": ["npc/apache.gd"],
    "NPCtypeTentacle": ["npc/scp_tentacle.gd"],
    "NPCtype860": ["npc/scp_860.gd", "world/forest.gd"],
    "NPCtype939": ["npc/scp_939.gd"],
    "NPCtype066": ["npc/scp_066.gd"],
    "NPCtype966": ["npc/scp_966.gd"],
    "NPCtype1048a": [],
    "NPCtype1499": ["npc/scp_1499.gd", "world/dimension_1499.gd"],
    "NPCtype008": ["npc/scp_008_zombie.gd"],
}
ALWAYS = {"item": ["items/item_use.gd"], "914": ["items/scp914_recipes.gd", "world/scp914_room.gd"]}


def _code(line):
    """The line without its comment and string literals."""
    line = STRING.sub('""', line)
    line = re.sub(r"\bChr\s*\(\s*\d+\s*\)", '""', line, flags=re.I)
    return line.split(";", 1)[0]


def labels(label):
    """The lowercase names of a Case label such as `"room2sl", "room2sl2"`."""
    return [name for name in (token.strip().strip('"').lower() for token in label.split(",")) if name]


def read(src, name):
    with open(os.path.join(src, name), encoding="latin-1") as handle:
        return handle.read().split("\n")


def cases(lines, select_line):
    """[(label, first, last)] of the Cases directly under the Select at 0-based index select_line."""
    out, depth, label, start = [], 0, None, None
    for index in range(select_line + 1, len(lines)):
        code = _code(lines[index]).strip()
        lower = code.lower()
        if re.match(r"select\b", lower):
            depth += 1
        elif re.match(r"end\s*select\b", lower):
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and re.match(r"case\b", lower):
            if label is not None:
                out.append((label, start, index - 1))
            label, start = lines[index].split(";", 1)[0].strip()[4:].strip(), index
        elif depth == 0 and re.match(r"default\b", lower):
            if label is not None:
                out.append((label, start, index - 1))
            label, start = "Default", index
    if label is not None:
        out.append((label, start, index - 1))
    return out


def _numbers(code):
    return [float(text) for text in NUMBER.findall(code)]


def _file_numbers(text):
    found = set()
    for line in text.split("\n"):
        for value in _numbers(STRING.sub('""', line.split("#", 1)[0])):
            found.add(round(value, 4))
    return found


class _Port:
    """The number literals of a block's port files, sorted, for lookups within a 1e-3 relative tolerance."""

    def __init__(self, sets):
        self.values = sorted(set().union(*sets)) if sets else []
        self.exact = set(self.values)
        self.memo = {}

    def near(self, candidate):
        if round(candidate, 4) in self.exact:
            return True
        if not candidate:
            return False
        reach = abs(candidate) * 1e-3
        at = bisect.bisect_left(self.values, candidate - reach)
        return at < len(self.values) and self.values[at] <= candidate + reach

    def found(self, value):
        if value not in self.memo:
            self.memo[value] = any(self.near(candidate) for candidate in
                                   (value, value / 70.0, value * 70.0, value * ROOM_SCALE, value / 100.0, value * 100.0))
        return self.memo[value]


def _scripts(root):
    """{path under scripts/: (lowercase text, its number literals)} of every port script outside the tests."""
    out = {}
    for base, _, names in os.walk(os.path.join(root, "scripts")):
        if os.sep + "tests" in base:
            continue
        for name in names:
            if name.endswith(".gd"):
                path = os.path.join(base, name)
                rel = os.path.relpath(path, os.path.join(root, "scripts")).replace(os.sep, "/")
                with open(path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
                out[rel] = (text.lower(), _file_numbers(text))
    return out


def _files_for(kind, label, scripts):
    if kind == "npc":
        names = []
        for token in re.split(r"\s*,\s*", label):
            names += NPC_FILES.get(token, [])
        return sorted(set(name for name in names if name in scripts))
    keys = labels(label)
    hits = []
    for rel, (lower, _) in scripts.items():
        stem = rel.rsplit("/", 1)[-1][:-3].lower()
        for key in keys:
            if '"%s"' % key in lower or "_ev_%s" % key in lower or stem.startswith(key):
                hits.append(rel)
                break
    hits += [name for name in ALWAYS.get(kind, []) if name in scripts]
    return sorted(set(hits))


def _block(kind, file, lines, label, first, last, scripts):
    files = _files_for(kind, label, scripts)
    port = _Port([scripts[name][1] for name in files])
    missing, total = [], 0
    for index in range(first, last + 1):
        for value in _numbers(_code(lines[index])):
            if value in TRIVIAL:
                continue
            total += 1
            if not port.found(value):
                missing.append({"line": index + 1, "value": value})
    branches = []
    for sub_select in range(first, last + 1):
        if not re.match(r"\s*select\b", _code(lines[sub_select]), re.I):
            continue
        for sub_label, sub_first, sub_last in cases(lines, sub_select):
            values = [value for index in range(sub_first, sub_last + 1) for value in _numbers(_code(lines[index]))
                      if value not in TRIVIAL]
            if len(values) >= 3 and not any(port.found(value) for value in values):
                branches.append({"line": sub_first + 1, "case": sub_label, "select": lines[sub_select].strip()[:60],
                                 "literals": len(values)})
    return {
        "kind": kind, "case": label, "file": file, "lines": [first + 1, last + 1], "port_files": files,
        "literals": total, "missing": len(missing),
        "coverage": round(1.0 - len(missing) / total, 3) if total else 1.0,
        "missing_literals": missing, "unported_branches": branches,
    }


def select_lines(lines, pattern, start=0):
    return [index for index in range(start, len(lines)) if re.match(pattern, _code(lines[index]), re.I)]


def created_events(src):
    """{event name: the room names given as a string} of every live (uncommented) CreateEvent call."""
    events = {}
    for name in os.listdir(src):
        if name.lower().endswith(".bb"):
            for line in read(src, name):
                code = line.split(";", 1)[0]
                for match in re.finditer(r'CreateEvent\s*\(\s*"([^"]+)"(?:\s*,\s*"([^"]*)")?', code, re.I):
                    rooms = events.setdefault(match.group(1).lower(), set())
                    if match.group(2):
                        rooms.add(match.group(2).lower())
    return events


def audit(src, root):
    scripts = _scripts(root)
    created = created_events(src)
    rows = []
    npcs = read(src, "NPCs.bb")
    begin = next(i for i, line in enumerate(npcs) if re.match(r"\s*Function\s+UpdateNPCs\b", line, re.I))
    select = select_lines(npcs, r"\s*Select\s+n\\NPCtype", begin)[0]
    for label, first, last in cases(npcs, select):
        rows.append(_block("npc", "NPCs.bb", npcs, label, first, last, scripts))
    events = read(src, "UpdateEvents.bb")
    for select in select_lines(events, r"\s*Select\s+e\\EventName"):
        for label, first, last in cases(events, select):
            row = _block("event", "UpdateEvents.bb", events, label, first, last, scripts)
            if not any(name in created for name in labels(label)):
                row["never_created"] = True
                row["missing"] = 0
            rows.append(row)
    main = read(src, "Main.bb")
    held = [i for i in select_lines(main, r"\s*Select\s+SelectedItem\\itemtemplate\\tempname")
            if any(re.match(r'\s*Case\s+"nvgoggles"', main[j], re.I) for j in range(i + 1, min(i + 4, len(main))))]
    for select in held[:1]:
        for label, first, last in cases(main, select):
            rows.append(_block("item", "Main.bb", main, label, first, last, scripts))
    use914 = next(i for i, line in enumerate(main) if re.match(r"\s*Function\s+Use914\b", line, re.I))
    select = select_lines(main, r"\s*Select\s+item\\itemtemplate\\name", use914)[0]
    for label, first, last in cases(main, select):
        rows.append(_block("914", "Main.bb", main, label, first, last, scripts))
    rows.sort(key=lambda row: (-row["missing"], row["file"], row["lines"][0]))
    return rows


def summary(rows, top=25):
    lines = ["%-6s %-28s %5s %6s %6s  %s" % ("kind", "case", "miss", "of", "cover", "Blitz lines / port files")]
    for row in rows[:top]:
        lines.append("%-6s %-28s %5d %6d %5.0f%%  %s:%d-%d -> %s" % (
            row["kind"], row["case"][:28], row["missing"], row["literals"], row["coverage"] * 100, row["file"],
            row["lines"][0], row["lines"][1], ", ".join(row["port_files"]) or "(no port file)"))
    branches = sum(len(row["unported_branches"]) for row in rows)
    lines.append("%d blocks, %d nested branches with none of their literals in the port" % (len(rows), branches))
    dead = [row["case"] for row in rows if row.get("never_created")]
    if dead:
        lines.append("never created by any CreateEvent (skipped): " + ", ".join(dead))
    return "\n".join(lines)
