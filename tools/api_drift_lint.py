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

# Directory names that are excluded RELATIVE TO THE LINT ROOT. Matching against
# absolute path parts would silently disable the whole lint whenever the
# checkout itself lives under a directory called e.g. "addons" (fail-open).
EXCLUDED_PARTS = {".git", ".godot", "addons", "__pycache__"}

_STRING_LITERAL = re.compile(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'")


def strip_noncode(line: str) -> str:
    """Blank out string contents and trailing comments.

    Prose such as `# Reference: see the Spatial audio notes` is not API drift;
    scanning raw lines made the lint (and therefore doctor.sh) fail closed on
    perfectly valid Godot 4 files. String bodies are replaced by a single-char
    placeholder so the legacy `connect("sig", self, "cb")` pattern still fires.
    """
    line = _STRING_LITERAL.sub('"S"', line)
    hash_index = line.find("#")
    if hash_index != -1:
        line = line[:hash_index]
    return line


def scan_line(line: str) -> list[str]:
    code = strip_noncode(line)
    return [label for label, pattern in PATTERNS.items() if pattern.search(code)]


def lint(root: Path) -> list[str]:
    root = root.resolve()
    findings: list[str] = []
    for path in sorted(root.rglob("*.gd")):
        relative = path.relative_to(root)
        if any(part in EXCLUDED_PARTS for part in relative.parts):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line_number, line in enumerate(text.splitlines(), 1):
            for label in scan_line(line):
                findings.append(f"{path}:{line_number}: Godot 3 API `{label}`: {line.strip()}")
    return findings


# Exactly one positive fixture per mandated pattern, keyed by label, so a broken
# regex cannot hide behind another pattern matching the same sample.
POSITIVE_FIXTURES = {
    "KinematicBody": "extends KinematicBody2D",
    "Spatial": "extends Spatial",
    "Reference": "extends Reference",
    "PoolVector3Array": "var p = PoolVector3Array()",
    "yield(": "yield(node, 1)",
    "export(": "export(int) var speed",
    "onready var": "onready var camera = $Camera",
    ".instance()": "var n = scene.instance()",
    "Directory.new()": "var d = Directory.new()",
    "File.new()": "var f = File.new()",
    "legacy connect": 'button.connect("pressed", self, "_on_pressed")',
    "get_tree().set_input_as_handled()": "get_tree().set_input_as_handled()",
}

# Valid Godot 4 code (and prose) that must never be reported.
NEGATIVE_FIXTURES = [
    "# Reference: see the Spatial audio notes for KinematicBody history",
    'var label := "Spatial survey (legacy Reference build)"',
    "extends Node3D",
    "@export var speed: int = 3",
    "var p := PackedVector3Array()",
    "var n := scene.instantiate()",
    'button.connect("pressed", _on_pressed)',
    "await get_tree().process_frame",
    'var d := DirAccess.open("res://")',
    'var f := FileAccess.open("res://x", FileAccess.READ)',
    "get_viewport().set_input_as_handled()",
]


def self_test() -> None:
    missing = sorted(set(PATTERNS) - set(POSITIVE_FIXTURES))
    if missing:
        raise SystemExit(f"LINT SELF-TEST FAILED: no fixture for pattern(s): {missing}")
    for label, sample in POSITIVE_FIXTURES.items():
        if label not in PATTERNS:
            raise SystemExit(f"LINT SELF-TEST FAILED: fixture for unknown pattern {label}")
        if not PATTERNS[label].search(strip_noncode(sample)):
            raise SystemExit(f"LINT SELF-TEST FAILED: pattern `{label}` did not match {sample!r}")
    for sample in NEGATIVE_FIXTURES:
        hits = scan_line(sample)
        if hits:
            raise SystemExit(f"LINT SELF-TEST FAILED: false positive {hits} on {sample!r}")
    print(
        "API DRIFT SELF-TEST OK (%d per-pattern fixtures, %d negative fixtures)"
        % (len(POSITIVE_FIXTURES), len(NEGATIVE_FIXTURES))
    )


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
