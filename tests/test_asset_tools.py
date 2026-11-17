#!/usr/bin/env python3
"""Offline check of tools/build_asset_pack.py and tools/fetch_assets.py: builds a pack from a made-up game folder, then
fetches it through a local manifest (no network).

  python3 tests/test_asset_tools.py
"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent / "tools"


def run(script: str, *args: str, cwd: Path, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, "-I", str(TOOLS / script), *args], cwd=cwd, capture_output=True, text=True, env=env)


class AssetToolsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.root = Path(self._temp.name)
        game = self.game = self.root / "game"
        files = {
            "GFX/menu/back.jpg": b"jpg",
            "GFX/menu/startup_TSS.avi": b"video",     # excluded (--no-videos: not re-encoded either)
            "SFX/Music/Intro.ogg": b"ogg",
            "Data/rooms.ini": b"[room]",
            "Loadingscreens/title.jpg": b"jpg",
            "Data/Thumbs.db": b"junk",                # excluded
            "Launcher.dll": b"dll",                   # outside the folders that are packed
            "Credits.txt": b"credits",
        }
        for name, content in files.items():
            (game / name).parent.mkdir(parents=True, exist_ok=True)
            (game / name).write_bytes(content)
        self.out = self.root / "out"
        built = run("build_asset_pack.py", "--source", str(game), "--out", str(self.out), "--version", "t1", "--no-videos", cwd=self.root)
        self.assertEqual(built.returncode, 0, built.stderr)
        self.dest = self.root / "assets"

    def fetch(self, *args: str) -> subprocess.CompletedProcess:
        return run("fetch_assets.py", "--dest", str(self.dest), *args, cwd=self.out)

    def test_fetch_through_a_bare_manifest_name(self) -> None:
        # the archive is found next to the manifest even when the manifest is named without a folder
        result = self.fetch("--manifest", "manifest.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.dest / "GFX/menu/back.jpg").is_file())
        self.assertTrue((self.dest / "SFX/Music/Intro.ogg").is_file())
        self.assertTrue((self.dest / "Data/rooms.ini").is_file())
        self.assertTrue((self.dest / "CREDITS.txt").is_file())
        notice = (self.dest / "NOTICE.txt").read_text()
        self.assertIn("creativecommons.org/licenses/by-sa/3.0", notice)
        self.assertIn("173", notice)
        self.assertTrue((self.dest / ".gdignore").is_file())
        for left_out in ("GFX/menu/startup_TSS.avi", "Data/Thumbs.db", "Launcher.dll"):
            self.assertFalse((self.dest / left_out).exists(), left_out)

    def test_videos_without_ffmpeg_is_a_message_not_a_traceback(self) -> None:
        result = run("build_asset_pack.py", "--source", str(self.game), "--out", str(self.root / "out2"), "--version", "t2",
                     cwd=self.root, env={"PATH": str(self.root / "no-tools")})
        self.assertEqual(result.returncode, 1)
        self.assertIn("ffmpeg is needed", result.stderr)
        self.assertIn("--no-videos", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_second_fetch_is_a_no_op(self) -> None:
        self.assertEqual(self.fetch("--manifest", "manifest.json").returncode, 0)
        again = self.fetch("--manifest", "manifest.json")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIn("up to date", again.stdout)

    def test_damaged_stamp_downloads_again(self) -> None:
        self.assertEqual(self.fetch("--manifest", "manifest.json").returncode, 0)
        (self.dest / "installed.json").write_text("{not json")
        again = self.fetch("--manifest", "manifest.json")
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertNotIn("up to date", again.stdout)

    def test_checksum_mismatch_is_refused(self) -> None:
        archive = next(self.out.glob("*.zip"))
        archive.write_bytes(archive.read_bytes() + b"tampered")
        result = self.fetch("--manifest", str(self.out / "manifest.json"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("checksum mismatch", result.stdout)
        self.assertFalse((self.dest / "GFX").exists())

    def test_missing_manifest_is_a_message_not_a_traceback(self) -> None:
        result = self.fetch("--manifest", str(self.root / "nowhere.json"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("could not read the manifest", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_incomplete_manifest_is_a_message_not_a_traceback(self) -> None:
        broken = self.root / "broken.json"
        broken.write_text(json.dumps({"version": "x", "archive": {"name": "a.zip"}}))
        result = self.fetch("--manifest", str(broken))
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()
