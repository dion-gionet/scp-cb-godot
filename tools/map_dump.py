"""Dump the generated facility map of one or more seeds to tests/maps/seed_<n>.json (via the dev server).

  python tools/map_dump.py --seed 9 [--seed 12345]

Rows are {name, pos (Blitz x,y,z), grid, angle}. Compare against what MapSystem.bb CreateMap would produce for the seed.
"""
import argparse
import json
import os
import types

import dev

PROJECT = dev.PROJECT


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, action="append", required=True)
    parser.add_argument("--port", type=int, default=int(os.environ.get("DEV_PORT", "7791")))
    args = parser.parse_args()
    out = os.path.join(PROJECT, "tests", "maps")
    os.makedirs(out, exist_ok=True)
    for seed in args.seed:
        dev.start(types.SimpleNamespace(seed=seed, window=False, intro=False, fixed_fps=True, port=args.port, wait=90.0))
        try:
            rooms = dev.send({"cmd": "rooms"}, args.port)["rooms"]
        finally:
            dev.stop(types.SimpleNamespace(port=args.port))
        with open(os.path.join(out, "seed_%d.json" % seed), "w") as handle:
            json.dump(rooms, handle, indent=1)
        print("seed %d: %d rooms -> tests/maps/seed_%d.json" % (seed, len(rooms), seed))


if __name__ == "__main__":
    main()
