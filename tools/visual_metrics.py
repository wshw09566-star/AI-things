#!/usr/bin/env python3
from __future__ import annotations
import argparse
import json
from pathlib import Path
from PIL import Image


def analyze(path: Path, threshold: int = 8) -> dict[str, object]:
    image = Image.open(path).convert("RGB")
    pixels = list(image.getdata())
    total = len(pixels)
    nonblack = sum(max(pixel) > threshold for pixel in pixels)
    cyan = sum(g > r * 1.15 and b > r * 1.10 and g > threshold * 2 for r, g, b in pixels)
    amber = sum(r > b * 1.35 and g > b * 1.15 and r > threshold * 2 for r, g, b in pixels)
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministic HOLLOW SURVEY frame metrics")
    parser.add_argument("image", type=Path)
    parser.add_argument("--expect-size", default="640x360")
    parser.add_argument("--min-colors", type=int, default=1)
    parser.add_argument("--min-nonblack", type=float, default=0.0)
    parser.add_argument("--max-nonblack", type=float, default=1.0)
    parser.add_argument("--require-cyan", action="store_true")
    parser.add_argument("--require-amber", action="store_true")
    args = parser.parse_args()
    metrics = analyze(args.image)
    print(json.dumps(metrics, sort_keys=True))
    width, height = (int(value) for value in args.expect_size.lower().split("x", 1))
    failures: list[str] = []
    if (metrics["width"], metrics["height"]) != (width, height):
        failures.append(f"size {(metrics['width'], metrics['height'])} != {(width, height)}")
    if metrics["unique_colors"] < args.min_colors:
        failures.append(f"colors {metrics['unique_colors']} < {args.min_colors}")
    if not args.min_nonblack <= metrics["nonblack_ratio"] <= args.max_nonblack:
        failures.append(f"nonblack ratio {metrics['nonblack_ratio']} outside [{args.min_nonblack}, {args.max_nonblack}]")
    if args.require_cyan and metrics["cyan_ratio"] <= 0:
        failures.append("cyan pixels missing")
    if args.require_amber and metrics["amber_ratio"] <= 0:
        failures.append("amber pixels missing")
    if failures:
        for failure in failures:
            print(f"VISUAL METRIC FAIL: {failure}")
        return 1
    print("VISUAL METRICS PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
