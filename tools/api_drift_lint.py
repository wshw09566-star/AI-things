#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys

PATTERNS = {
    "KinematicBody": re.compile(r"\bKinematicBody(?:2D)?\b"),
    "Spatial": re.compile(r"\bSpatial\b"),
    "Reference": re.compile(r"\bReference\b"),
    "PoolVector3Array": re.compile(r"\bPoolVector3Array\b"),
    "yield(": re.compile(r"\byield\s*\("),
    "export(": re.compile(r"(?<!@)\bexport\s*\("),
    "onready var": re.compile(r"\bonready\s+var\b"),
    ".instance()": re.compile(r"\.instance\s*\("),
    "Directory.new()": re.compile(r"\bDirectory\.new\s*\("),
    "File.new()": re.compile(r"\bFile\.new\s*\("),
    "legacy connect": re.compile(r"\.connect\s*\(\s*[\"'][^\"']+[\"']\s*,\s*self\s*,"),
    "get_tree().set_input_as_handled()": re.compile(r"get_tree\s*\(\s*\)\.set_input_as_handled\s*\("),
}

EXCLUDED_PARTS = {".git", ".godot", "addons"}

def lint(root: Path) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*.gd")):
        if any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(text.splitlines(), 1):
            for label, pattern in PATTERNS.items():
                if pattern.search(line):
                    findings.append(f"{path}:{line_number}: Godot 3 API `{label}`: {line.strip()}")
    return findings

def self_test() -> None:
    samples = [
        "extends KinematicBody", "extends KinematicBody2D", "extends Spatial",
        "extends Reference", "var p = PoolVector3Array()", "yield(node, \"done\")",
        "export(int) var speed", "onready var camera = $Camera", "scene.instance()",
        "Directory.new()", "File.new()", "signal.connect(\"x\", self, \"_y\")",
        "get_tree().set_input_as_handled()",
    ]
    for sample in samples:
        if not any(pattern.search(sample) for pattern in PATTERNS.values()):
            raise SystemExit(f"LINT SELF-TEST FAILED: {sample}")
    print(f"API DRIFT SELF-TEST OK ({len(samples)} fixtures)")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    findings = lint(Path(args.root).resolve())
    if findings:
        print("API DRIFT LINT FAILED", file=sys.stderr)
        print("\n".join(findings), file=sys.stderr)
        return 1
    print("API DRIFT LINT OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
