"""The maintenance tunnels' grid of UpdateEvents.bb 3170-3560, written independently of scripts/world/mt_grid.gd.

  python tools/mt_grid.py 9 12345 777            print the grids
  python tools/mt_grid.py --write 9 12345 777    write tests/fixtures/mt_grid.json (the `maintenance` scenario compares against it)

The argument is the number SeedRnd gets (GenerateSeedNumber of the seed text). Blitz3D's Rand(a, b) is int(next * (b - a + 1)) + a
on a Park-Miller stream, and every call advances it once. Reads outside the array count as 0.
"""
import json
import os
import sys

GRID = 19
CELLS = GRID * GRID


class Rng:
    def __init__(self, seed):
        seed &= 0x7FFFFFFF
        self.state = seed if seed else 1

    def next(self):
        self.state = 48271 * (self.state % 44488) - 3399 * (self.state // 44488)
        if self.state < 0:
            self.state += 2147483647
        return (self.state & 65535) / 65536.0 + 0.5 / 65536.0

    def rand(self, lo, hi=1):
        if hi < lo:
            lo, hi = hi, lo
        return int(self.next() * (hi - lo + 1)) + lo


def generate(seed):
    rng = Rng(seed)
    g = [0] * CELLS
    angles = [0] * CELLS

    def at(x, y):
        i = x + y * GRID
        return g[i] if 0 <= i < CELLS else 0

    d = rng.rand(0, 1) << 1
    x = GRID // 2 + rng.rand(-2, 2)
    y = GRID // 2 + rng.rand(-2, 2)
    g[x + y * GRID] = 1
    g[(x + 1) + y * GRID if d == 2 else (x - 1) + y * GRID] = 1
    count = 2
    while count < 100:
        a = rng.rand(1, 5)
        b = rng.rand(1, 2)
        steps = a << b
        for i in range(1, steps + 1):
            ok = True
            if d == 0:
                if x < GRID - 2 - (i % 2):
                    x += 1
                else:
                    ok = False
            elif d == 1:
                if y < GRID - 2 - (i % 2):
                    y += 1
                else:
                    ok = False
            elif d == 2:
                if x > 1 + (i % 2):
                    x -= 1
                else:
                    ok = False
            else:
                if y > 1 + (i % 2):
                    y -= 1
                else:
                    ok = False
            if not ok:
                break
            if g[x + y * GRID] == 0:
                g[x + y * GRID] = 1
                count += 1
        d += (rng.rand(0, 1) << 1) - 1
        while d < 0:
            d += 4
        while d > 3:
            d -= 4

    for y in range(GRID):
        for x in range(GRID):
            if g[x + y * GRID] > 0:
                g[x + y * GRID] = (at(x, y + 1) > 0) + (at(x, y - 1) > 0) + (at(x + 1, y) > 0) + (at(x - 1, y) > 0)

    max_x = GRID - 1
    retry = False
    x = 0
    while x <= max_x:
        for y in range(GRID):
            if at(x + 1, y) > 0:
                max_x = x
                if at(x + 1, y + 1) < 3 and at(x + 1, y - 1) < 3:
                    retry = True
                    if rng.rand(0, 1) == 1:
                        g[x + 1 + y * GRID] += 1
                        g[x + y * GRID] = 7
                        retry = False
                        break
        if retry:
            x -= 1
        x += 1

    fx, fy, lx, ly = -1, 0, 0, -1
    for y in range(GRID):
        for x in range(GRID):
            if at(x, y) != 2:
                continue
            if not ((at(x + 1, y) > 0 and at(x - 1, y) > 0) or (at(x, y + 1) > 0 and at(x, y - 1) > 0)):
                continue
            plain = at(x - 1, y) < 3 and at(x + 1, y) < 3 and at(x, y - 1) < 3 and at(x, y + 1) < 3
            clear = at(x - 1, y - 1) < 1 and at(x + 1, y - 1) < 1 and at(x - 1, y + 1) < 1
            if plain and clear:
                if fx == -1 or fy == -1:
                    fx, fy = x, y
                lx, ly = x, y
    if lx == fx and ly == fy:
        raise RuntimeError("The maintenance tunnels could not be generated properly!")

    item_yaws = []
    for y in range(GRID):
        for x in range(GRID):
            v = g[x + y * GRID]
            if v <= 0:
                continue
            ia, ib, ic, ie = at(x, y + 1), at(x, y - 1), at(x + 1, y), at(x - 1, y)
            if v in (1, 7):
                angle = 1 if ic > 0 else 3 if ie > 0 else 2 if ia > 0 else 0
            elif v == 2:
                if (x == fx and y == fy) or (x == lx and y == ly):
                    g[x + y * GRID] = 6
                if ic > 0 and ie > 0:
                    angle = rng.rand(0, 1) * 2 + 1
                elif ia > 0 and ib > 0:
                    angle = rng.rand(0, 1) * 2
                elif ia > 0 and ic > 0:
                    angle = 0
                elif ia > 0 and ie > 0:
                    angle = 1
                elif ib > 0 and ic > 0:
                    angle = 3
                else:
                    angle = 2
                if x == fx and y == fy:
                    g[x + y * GRID] = 5
            elif v == 3:
                if ia > 0 and ic > 0 and ie > 0:
                    angle = 1
                elif ib > 0 and ic > 0 and ie > 0:
                    angle = 3
                elif ic > 0 and ia > 0 and ib > 0:
                    angle = 0
                else:
                    angle = 2
            else:
                angle = rng.rand(0, 3)
            angles[x + y * GRID] = angle
            if g[x + y * GRID] == 7:
                item_yaws = [rng.rand(360), rng.rand(360)]
            if g[x + y * GRID] in (5, 6):
                rng.rand(8)
    return {
        "seed": seed,
        "cells": sum(1 for v in g if v > 0),
        "first": [fx, fy],
        "last": [lx, ly],
        "item_yaws": item_yaws,
        "rng_state": rng.state,
        "grid": g,
        "angles": angles,
    }


def main():
    args = sys.argv[1:]
    write = "--write" in args
    seeds = [int(a) for a in args if a != "--write"]
    out = [generate(s) for s in seeds]
    for entry in out:
        print(entry["seed"], "cells", entry["cells"], "first", entry["first"], "last", entry["last"], "items", entry["item_yaws"], "state", entry["rng_state"])
    if write:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "fixtures", "mt_grid.json")
        with open(path, "w") as handle:
            json.dump(out, handle)
            handle.write("\n")


if __name__ == "__main__":
    main()
