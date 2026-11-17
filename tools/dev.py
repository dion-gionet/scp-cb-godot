"""Driver for the in-game dev server (scripts/debug/dev_server.gd).

  python tools/dev.py start [--seed N] [--window] [--port 7777] [--intro]   (the port defaults to $DEV_PORT, or 7777)
  python tools/dev.py cmd state
  python tools/dev.py cmd teleport room=room2
  python tools/dev.py cmd advance seconds=2
  python tools/dev.py cmd console line="spawn 049"
  python tools/dev.py cmd shot path=C:/x.png
  python tools/dev.py stop

`start` launches Godot detached (headless unless --window, which screenshots need), waits until the
server answers and the facility is active, and prints the first state. Every `cmd` prints the JSON reply.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time

PROJECT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.environ.get("GODOT", "godot")
PIDFILE = os.path.join(PROJECT, "tests", "dev_server.pid")


def send(request, port=7777, timeout=120.0):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
        sock.settimeout(timeout)
        sock.sendall((json.dumps(request) + "\n").encode())
        data = b""
        while not data.endswith(b"\n"):
            chunk = sock.recv(65536)
            if not chunk:
                break
            data += chunk
    return json.loads(data)


def start(args):
    env = dict(os.environ, SCP_BOT="1", SCP_DEV="1", SCP_DEV_PORT=str(args.port))
    if args.seed is not None:
        env["SCP_SEED"] = str(args.seed)
    if args.intro:
        env["SCP_INTRO"] = "1"
    if args.window:
        env["SCP_SHOT"] = "1"
    command = [GODOT, "--path", PROJECT]
    if not args.window:
        command.insert(1, "--headless")
    if args.fixed_fps:
        command += ["--fixed-fps", "70"]
    log = open(os.path.join(PROJECT, "tests", "dev_server.log"), "w")
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, creationflags=flags)
    with open(PIDFILE, "w") as handle:
        handle.write(str(process.pid))
    deadline = time.time() + args.wait
    while time.time() < deadline:
        if process.poll() is not None:
            sys.exit("godot exited early; see tests/dev_server.log")
        try:
            reply = send({"cmd": "state"}, args.port, 10)
            if reply.get("ok") and reply["state"].get("facility_active"):
                print(json.dumps(reply))
                return
        except (OSError, ValueError):
            pass
        time.sleep(1.0)
    sys.exit("timed out waiting for the dev server; see tests/dev_server.log")


def stop(args):
    try:
        send({"cmd": "quit"}, args.port, 5)
    except (OSError, ValueError):
        pass
    if os.path.exists(PIDFILE):
        pid = int(open(PIDFILE).read())
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
        else:
            try:
                os.kill(pid, 9)
            except OSError:
                pass
        os.remove(PIDFILE)


def command(args):
    request = {"cmd": args.name}
    for pair in args.pairs:
        key, _, value = pair.partition("=")
        try:
            request[key] = json.loads(value)
        except ValueError:
            request[key] = value
    print(json.dumps(send(request, args.port)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=int(os.environ.get("DEV_PORT", "7777")))
    sub = parser.add_subparsers(dest="action", required=True)
    s = sub.add_parser("start")
    s.add_argument("--seed", type=int)
    s.add_argument("--window", action="store_true")
    s.add_argument("--intro", action="store_true")
    s.add_argument("--fixed-fps", action="store_true")
    s.add_argument("--wait", type=float, default=90.0)
    sub.add_parser("stop")
    c = sub.add_parser("cmd")
    c.add_argument("name")
    c.add_argument("pairs", nargs="*")
    args = parser.parse_args()
    {"start": start, "stop": stop, "cmd": command}[args.action](args)


if __name__ == "__main__":
    main()
