#!/usr/bin/env python3
"""Deterministic HOLLOW SURVEY frame metrics.

Stdlib + Pillow only; no network access and no external services. Memory use is
bounded by MAX_IMAGE_PIXELS and a single-pass scan over the decoded frame.

Exit codes:
  0  all requested thresholds pass
  1  metrics computed, but at least one threshold failed
  2  usage error or the image could not be read as a single deterministic frame
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterator

from PIL import Image, UnidentifiedImageError

# Bound memory: this tool only ever inspects small design frames (640x360).
# Anything larger is rejected by Pillow before decoding.
Image.MAX_IMAGE_PIXELS = 4_000_000

EXIT_OK = 0
EXIT_METRIC_FAIL = 1
EXIT_USAGE = 2


class MetricsError(Exception):
    """Raised when an image cannot be measured unambiguously."""


def _flatten_to_rgb(image: Image.Image) -> Image.Image:
    """Return an opaque RGB frame, compositing any alpha over black.

    Dropping alpha with a bare convert("RGB") would let fully transparent
    pixels contribute their hidden RGB values to the metrics, which makes the
    numbers depend on how the exporter filled invisible pixels.
    """
    if image.mode == "P" and "transparency" in image.info:
        image = image.convert("RGBA")
    if image.mode in ("RGBA", "LA", "PA", "La"):
        rgba = image.convert("RGBA")
        backdrop = Image.new("RGBA", rgba.size, (0, 0, 0, 255))
        return Image.alpha_composite(backdrop, rgba).convert("RGB")
    return image.convert("RGB")


def _iter_rgb(image: Image.Image) -> Iterator[tuple[int, int, int]]:
    """Yield (r, g, b) triples without the deprecated Image.getdata()."""
    expected = image.width * image.height * 3
    data = image.tobytes()
    if len(data) != expected:
        raise MetricsError(
            f"decoded {len(data)} bytes but expected {expected} for "
            f"{image.width}x{image.height} RGB data"
        )
    view = memoryview(data)
    for offset in range(0, expected, 3):
        yield view[offset], view[offset + 1], view[offset + 2]


def analyze(path: Path, threshold: int = 8) -> dict[str, object]:
    try:
        with Image.open(path) as opened:
            frames = getattr(opened, "n_frames", 1)
            if frames != 1:
                # Multi-frame inputs are ambiguous; always measure frame 0.
                opened.seek(0)
            opened.load()
            image = _flatten_to_rgb(opened)
    except FileNotFoundError:
        raise MetricsError(f"{path}: no such file") from None
    except IsADirectoryError:
        raise MetricsError(f"{path}: is a directory, not an image") from None
    except UnidentifiedImageError:
        raise MetricsError(f"{path}: not a readable image file") from None
    except (OSError, ValueError) as error:
        raise MetricsError(f"{path}: could not decode image ({error})") from None

    total = image.width * image.height
    if total <= 0:
        raise MetricsError(f"{path}: image has no pixels ({image.width}x{image.height})")

    nonblack = 0
    cyan = 0
    amber = 0
    for r, g, b in _iter_rgb(image):
        if r > threshold or g > threshold or b > threshold:
            nonblack += 1
        if g > r * 1.15 and b > r * 1.10 and g > threshold * 2:
            cyan += 1
        if r > b * 1.35 and g > b * 1.15 and r > threshold * 2:
            amber += 1

    # Unique colors can never exceed the pixel count, so getcolors() will not
    # bail out; the fallback only guards against future Pillow changes.
    colors = image.getcolors(maxcolors=total)
    return {
        "path": str(path),
        "width": image.width,
        "height": image.height,
        "unique_colors": len(colors) if colors is not None else total,
        "nonblack_ratio": round(nonblack / total, 6),
        "cyan_ratio": round(cyan / total, 6),
        "amber_ratio": round(amber / total, 6),
    }


def parse_size(value: str) -> tuple[int, int]:
    parts = value.strip().lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"expected WIDTHxHEIGHT, got {value!r}")
    try:
        width, height = (int(part) for part in parts)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected WIDTHxHEIGHT, got {value!r}") from None
    if width <= 0 or height <= 0:
        raise argparse.ArgumentTypeError(f"width and height must be positive, got {value!r}")
    return width, height


def parse_ratio(value: str) -> float:
    try:
        ratio = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected a number in [0, 1], got {value!r}") from None
    if not 0.0 <= ratio <= 1.0:
        raise argparse.ArgumentTypeError(f"expected a ratio in [0, 1], got {value!r}")
    return ratio


def parse_nonnegative_int(value: str) -> int:
    try:
        count = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"expected an integer >= 0, got {value!r}") from None
    if count < 0:
        raise argparse.ArgumentTypeError(f"expected an integer >= 0, got {value!r}")
    return count


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Deterministic HOLLOW SURVEY frame metrics")
    parser.add_argument("image", type=Path)
    parser.add_argument("--expect-size", type=parse_size, default="640x360")
    parser.add_argument("--min-colors", type=parse_nonnegative_int, default=1)
    parser.add_argument("--min-nonblack", type=parse_ratio, default=0.0)
    parser.add_argument("--max-nonblack", type=parse_ratio, default=1.0)
    parser.add_argument("--require-cyan", action="store_true")
    parser.add_argument("--require-amber", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    expect_size = args.expect_size
    if isinstance(expect_size, str):  # default value never passed through type=
        expect_size = parse_size(expect_size)
    if args.min_nonblack > args.max_nonblack:
        parser.error(
            f"--min-nonblack ({args.min_nonblack}) must not exceed "
            f"--max-nonblack ({args.max_nonblack})"
        )

    try:
        metrics = analyze(args.image)
    except MetricsError as error:
        print(f"VISUAL METRIC ERROR: {error}", file=sys.stderr)
        return EXIT_USAGE

    print(json.dumps(metrics, sort_keys=True))

    width, height = expect_size
    failures: list[str] = []
    if (metrics["width"], metrics["height"]) != (width, height):
        failures.append(f"size {(metrics['width'], metrics['height'])} != {(width, height)}")
    if metrics["unique_colors"] < args.min_colors:
        failures.append(f"colors {metrics['unique_colors']} < {args.min_colors}")
    if not args.min_nonblack <= metrics["nonblack_ratio"] <= args.max_nonblack:
        failures.append(
            f"nonblack ratio {metrics['nonblack_ratio']} outside "
            f"[{args.min_nonblack}, {args.max_nonblack}]"
        )
    if args.require_cyan and metrics["cyan_ratio"] <= 0:
        failures.append("cyan pixels missing")
    if args.require_amber and metrics["amber_ratio"] <= 0:
        failures.append("amber pixels missing")
    if failures:
        for failure in failures:
            print(f"VISUAL METRIC FAIL: {failure}")
        return EXIT_METRIC_FAIL
    print("VISUAL METRICS PASS")
    return EXIT_OK


if __name__ == "__main__":
    raise SystemExit(main())
