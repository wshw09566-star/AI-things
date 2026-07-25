#!/usr/bin/env python3
"""Regression tests for tools/visual_metrics.py.

Run with: python3 tests/fuzz/visual_metrics_test.py
Every child process runs with -W error::DeprecationWarning so any future use of
a deprecated Pillow API fails the suite instead of printing a warning.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools" / "visual_metrics.py"
EXPECTED_KEYS = {
    "amber_ratio",
    "cyan_ratio",
    "height",
    "nonblack_ratio",
    "path",
    "unique_colors",
    "width",
}


def run_tool(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-W", "error::DeprecationWarning", str(TOOL), *args],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )


class VisualMetricsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def write_frame(self, name: str, size=(640, 360), mode: str = "RGB") -> Path:
        image = Image.new(mode, size, (0, 0, 0) if mode == "RGB" else (0, 0, 0, 255))
        for x in range(0, size[0] // 4):
            for y in range(0, size[1] // 4):
                image.putpixel((x, y), (20, 200, 210) + ((255,) if mode == "RGBA" else ()))
                image.putpixel(
                    (size[0] - 1 - x, y),
                    (220, 150, 40) + ((255,) if mode == "RGBA" else ()),
                )
        path = self.tmp / name
        image.save(path)
        return path

    def test_pass_reports_stable_json_and_zero_exit(self) -> None:
        frame = self.write_frame("ok.png")
        result = run_tool(str(frame), "--expect-size", "640x360", "--require-cyan", "--require-amber")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout.splitlines()[0])
        self.assertEqual(set(payload), EXPECTED_KEYS)
        self.assertEqual((payload["width"], payload["height"]), (640, 360))
        self.assertGreater(payload["cyan_ratio"], 0)
        self.assertGreater(payload["amber_ratio"], 0)
        self.assertIn("VISUAL METRICS PASS", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_metrics_are_deterministic(self) -> None:
        frame = self.write_frame("determinism.png")
        first = run_tool(str(frame)).stdout.splitlines()[0]
        second = run_tool(str(frame)).stdout.splitlines()[0]
        self.assertEqual(first, second)

    def test_transparent_pixels_are_composited_over_black(self) -> None:
        image = Image.new("RGBA", (4, 4), (255, 255, 255, 0))
        path = self.tmp / "transparent.png"
        image.save(path)
        result = run_tool(str(path), "--expect-size", "4x4")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout.splitlines()[0])
        self.assertEqual(payload["nonblack_ratio"], 0.0)

    def test_size_mismatch_exits_one(self) -> None:
        frame = self.write_frame("small.png", size=(320, 180))
        result = run_tool(str(frame), "--expect-size", "640x360")
        self.assertEqual(result.returncode, 1)
        self.assertIn("VISUAL METRIC FAIL: size", result.stdout)

    def test_missing_color_requirement_exits_one(self) -> None:
        image = Image.new("RGB", (8, 8), (0, 0, 0))
        path = self.tmp / "black.png"
        image.save(path)
        result = run_tool(str(path), "--expect-size", "8x8", "--require-cyan", "--min-nonblack", "0.5")
        self.assertEqual(result.returncode, 1)
        self.assertIn("cyan pixels missing", result.stdout)
        self.assertIn("nonblack ratio", result.stdout)

    def test_single_pixel_image_has_no_division_error(self) -> None:
        image = Image.new("RGB", (1, 1), (0, 0, 0))
        path = self.tmp / "one.png"
        image.save(path)
        result = run_tool(str(path), "--expect-size", "1x1")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_malformed_image_exits_two_without_traceback(self) -> None:
        path = self.tmp / "broken.png"
        path.write_bytes(b"not a png at all")
        result = run_tool(str(path))
        self.assertEqual(result.returncode, 2)
        self.assertIn("VISUAL METRIC ERROR", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_file_exits_two(self) -> None:
        result = run_tool(str(self.tmp / "nope.png"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("no such file", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_bad_expect_size_is_usage_error(self) -> None:
        frame = self.write_frame("args.png")
        for bad in ("bogus", "640", "640x360x1", "0x360", "-640x360"):
            with self.subTest(expect_size=bad):
                result = run_tool(str(frame), "--expect-size", bad)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertNotIn("Traceback", result.stderr)

    def test_inverted_nonblack_bounds_are_usage_error(self) -> None:
        frame = self.write_frame("bounds.png")
        result = run_tool(str(frame), "--min-nonblack", "0.9", "--max-nonblack", "0.1")
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
