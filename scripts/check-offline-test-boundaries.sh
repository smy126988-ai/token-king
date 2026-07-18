#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="${CHECK_OFFLINE_BOUNDARY_ROOT:-$(cd "$script_dir/.." && pwd)}"

python3 - "$repository_root" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def without_comments(source: str) -> str:
    result: list[str] = []
    index = 0
    block_depth = 0
    in_string = False
    in_multiline_string = False
    escaped = False

    while index < len(source):
        if block_depth:
            if source.startswith("/*", index):
                block_depth += 1
                index += 2
            elif source.startswith("*/", index):
                block_depth -= 1
                index += 2
            else:
                if source[index] == "\n":
                    result.append("\n")
                index += 1
            continue

        if in_multiline_string:
            if source.startswith('"""', index):
                result.append('"""')
                in_multiline_string = False
                index += 3
            else:
                result.append(source[index])
                index += 1
            continue

        if in_string:
            character = source[index]
            result.append(character)
            index += 1
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue

        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            if newline == -1:
                break
            result.append("\n")
            index = newline + 1
        elif source.startswith("/*", index):
            block_depth = 1
            index += 2
        elif source.startswith('"""', index):
            result.append('"""')
            in_multiline_string = True
            index += 3
        elif source[index] == '"':
            result.append('"')
            in_string = True
            index += 1
        else:
            result.append(source[index])
            index += 1

    return "".join(result)


root = Path(sys.argv[1]).resolve()
unit_directory = root / "CopilotMonitor" / "CopilotMonitorTests"
live_directory = root / "CopilotMonitor" / "CopilotMonitorLiveTests"

if not unit_directory.is_dir():
    fail(f"Offline unit test directory not found: {unit_directory}")
if not live_directory.is_dir():
    fail(f"Live provider test directory not found: {live_directory}")

forbidden_patterns = (
    ("XCTSkip", re.compile(r"\bXCTSkip\s*\(")),
    ("RUN_LIVE_PROVIDER_TESTS", re.compile(r"\bRUN_LIVE_PROVIDER_TESTS\b")),
    ("URLSession.shared", re.compile(r"\bURLSession\s*\.\s*shared\b")),
    ("session: .shared", re.compile(r"\bsession\s*:\s*\.shared\b")),
    ("LiveIntegrationTests", re.compile(r"\bclass\s+\w*LiveIntegrationTests\b")),
)

violations: list[str] = []
for path in sorted(unit_directory.rglob("*.swift")):
    source = without_comments(path.read_text(encoding="utf-8"))
    relative_path = path.relative_to(root).as_posix()
    for label, pattern in forbidden_patterns:
        if pattern.search(source):
            violations.append(f"{relative_path}: contains live-only boundary '{label}'")

if violations:
    print("Offline unit test boundary violations:", file=sys.stderr)
    for violation in violations:
        print(f"  - {violation}", file=sys.stderr)
    raise SystemExit(1)

live_files = sorted(live_directory.rglob("*.swift"))
live_source = "\n".join(
    without_comments(path.read_text(encoding="utf-8")) for path in live_files
)
required_live_patterns = (
    ("XCTSkip", re.compile(r"\bXCTSkip\s*\(")),
    ("RUN_LIVE_PROVIDER_TESTS", re.compile(r"\bRUN_LIVE_PROVIDER_TESTS\b")),
    ("shared live networking", re.compile(r"\bURLSession\s*\.\s*shared\b|\bsession\s*:\s*\.shared\b")),
    ("LiveIntegrationTests", re.compile(r"\bclass\s+\w*LiveIntegrationTests\b")),
)
for label, pattern in required_live_patterns:
    if not pattern.search(live_source):
        fail(f"Expected live-only boundary '{label}' in CopilotMonitorLiveTests")

expected_gate = "try LiveProviderTestGate.requireEnabled()"
integration_files = [
    path for path in live_files if path.name.endswith("LiveIntegrationTests.swift")
]
if not integration_files:
    fail("No *LiveIntegrationTests.swift files found in CopilotMonitorLiveTests")

for path in integration_files:
    lines = without_comments(path.read_text(encoding="utf-8")).splitlines()
    for line_number, line in enumerate(lines):
        if not re.match(r"^\s*func\s+test\w*\s*\(", line):
            continue
        body_line = line_number
        while body_line < len(lines) and "{" not in lines[body_line]:
            body_line += 1
        statement_line = body_line + 1
        while statement_line < len(lines) and not lines[statement_line].strip():
            statement_line += 1
        actual = lines[statement_line].strip() if statement_line < len(lines) else "<missing>"
        if actual != expected_gate:
            relative_path = path.relative_to(root).as_posix()
            fail(
                f"{relative_path}:{line_number + 1}: first executable statement "
                f"must be exactly '{expected_gate}', got '{actual}'"
            )

print(
    "PASS: offline test boundary checks passed "
    f"({len(list(unit_directory.rglob('*.swift')))} offline files, "
    f"{len(live_files)} live files)"
)
PY
