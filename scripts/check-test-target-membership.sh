#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="${CHECK_TEST_MEMBERSHIP_ROOT:-$(cd "$script_dir/.." && pwd)}"

python3 - "$repository_root" <<'PY'
from __future__ import annotations

import json
import subprocess
import sys
from collections import Counter
from pathlib import Path, PurePosixPath
from typing import Any


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def string_list(obj: dict[str, Any], key: str, label: str) -> list[str]:
    value = obj.get(key)
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        fail(f"{label} does not contain a valid {key} list")
    return value


def relative_parts(value: str, label: str) -> tuple[str, ...]:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        fail(f"{label} is outside CopilotMonitorTests: {value}")
    return tuple(part for part in path.parts if part not in ("", "."))


root = Path(sys.argv[1]).resolve()
test_directory = root / "CopilotMonitor" / "CopilotMonitorTests"
project_file = root / "CopilotMonitor" / "CopilotMonitor.xcodeproj" / "project.pbxproj"
if not test_directory.is_dir():
    fail(f"Test directory not found: {test_directory}")
if not project_file.is_file():
    fail(f"Xcode project file not found: {project_file}")

result = subprocess.run(
    ["/usr/bin/plutil", "-convert", "json", "-o", "-", str(project_file)],
    check=False,
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    fail(f"plutil could not parse Xcode project: {result.stderr.strip()}")
try:
    objects = json.loads(result.stdout)["objects"]
except (json.JSONDecodeError, KeyError, TypeError) as error:
    fail(f"Could not read Xcode project objects: {error}")
if not isinstance(objects, dict) or not all(isinstance(value, dict) for value in objects.values()):
    fail("Xcode project objects dictionary contains invalid entries")

targets = [
    (object_id, obj)
    for object_id, obj in objects.items()
    if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "CopilotMonitorTests"
]
if len(targets) != 1:
    fail(f"Expected exactly one PBXNativeTarget named CopilotMonitorTests, found {len(targets)}")
source_phase_ids = [
    phase_id
    for phase_id in string_list(targets[0][1], "buildPhases", "CopilotMonitorTests target")
    if phase_id in objects and objects[phase_id].get("isa") == "PBXSourcesBuildPhase"
]
if len(source_phase_ids) != 1:
    fail(f"Expected exactly one PBXSourcesBuildPhase in CopilotMonitorTests, found {len(source_phase_ids)}")
active_build_file_ids = string_list(
    objects[source_phase_ids[0]], "files", "CopilotMonitorTests Sources phase"
)

groups = [
    (object_id, obj)
    for object_id, obj in objects.items()
    if obj.get("isa") == "PBXGroup" and obj.get("path") == "CopilotMonitorTests"
]
if len(groups) != 1:
    fail(f"Expected exactly one PBXGroup with path CopilotMonitorTests, found {len(groups)}")

resolved_file_paths: dict[str, str] = {}
visited_groups: set[str] = set()


def walk_group(group_id: str, prefix: tuple[str, ...], chain: tuple[str, ...]) -> None:
    if group_id in visited_groups:
        fail(f"PBXGroup cycle or duplicate group reference: {group_id}")
    visited_groups.add(group_id)
    group = objects[group_id]
    if group.get("sourceTree") != "<group>":
        fail(f"Unsupported PBXGroup sourceTree along {' -> '.join(chain)}: {group.get('sourceTree') or '<missing>'}")
    for child_id in string_list(group, "children", f"PBXGroup {group_id}"):
        child = objects.get(child_id)
        if child is None:
            continue
        if child.get("isa") == "PBXGroup":
            child_prefix = prefix
            if isinstance(child.get("path"), str):
                child_prefix += relative_parts(child["path"], f"PBXGroup {child_id} path")
            walk_group(child_id, child_prefix, chain + (child_id,))
        elif child.get("isa") == "PBXFileReference":
            path = child.get("path") or child.get("name")
            if not isinstance(path, str):
                fail(f"PBXFileReference {child_id} has no path or name")
            resolved_file_paths[child_id] = PurePosixPath(
                *(prefix + relative_parts(path, f"PBXFileReference {child_id} path"))
            ).as_posix()


walk_group(groups[0][0], (), (groups[0][0],))
unresolved_build_files: list[str] = []
unresolved_file_references: list[str] = []
unsupported_source_trees: list[str] = []
outside_test_group: list[str] = []
active_paths: list[str] = []

for build_file_id in active_build_file_ids:
    build_file = objects.get(build_file_id)
    if build_file is None or build_file.get("isa") != "PBXBuildFile":
        unresolved_build_files.append(build_file_id)
        continue
    file_reference_id = build_file.get("fileRef")
    if not isinstance(file_reference_id, str):
        unresolved_file_references.append(f"{build_file_id} -> <missing fileRef>")
        continue
    file_reference = objects.get(file_reference_id)
    if file_reference is None or file_reference.get("isa") != "PBXFileReference":
        unresolved_file_references.append(f"{build_file_id} -> {file_reference_id}")
        continue
    if file_reference.get("sourceTree") != "<group>":
        unsupported_source_trees.append(f"{build_file_id} -> {file_reference_id}: {file_reference.get('sourceTree') or '<missing>'}")
        continue
    resolved_path = resolved_file_paths.get(file_reference_id)
    if resolved_path is None:
        outside_test_group.append(f"{build_file_id} -> {file_reference_id}")
        continue
    active_paths.append(resolved_path)

for heading, values in (
    ("Unresolved PBXBuildFile references", unresolved_build_files),
    ("Unresolved PBXFileReference references", unresolved_file_references),
    ("Unsupported PBXFileReference sourceTree values", unsupported_source_trees),
    ("PBXFileReferences outside CopilotMonitorTests group", outside_test_group),
):
    if values:
        print(f"{heading}:", file=sys.stderr)
        for value in sorted(values):
            print(f"  - {value}", file=sys.stderr)
if unresolved_build_files or unresolved_file_references or unsupported_source_trees or outside_test_group:
    raise SystemExit(1)

duplicates = sorted(path for path, count in Counter(active_paths).items() if count > 1)
if duplicates:
    print("Duplicate paths in CopilotMonitorTests Sources:", file=sys.stderr)
    for path in duplicates:
        print(f"  - {path}", file=sys.stderr)
    raise SystemExit(1)

disk_paths = sorted(test_directory.rglob("*.swift"))
disk_relative_paths = {path.relative_to(test_directory).as_posix() for path in disk_paths}
active_path_set = set(active_paths)
missing_paths = sorted(disk_relative_paths - active_path_set)
extra_paths = sorted(active_path_set - disk_relative_paths)
print(f"Test target membership: {len(disk_paths)} test files on disk, {len(active_paths)} active test sources")
if missing_paths:
    print("Missing from CopilotMonitorTests Sources:", file=sys.stderr)
    for path in missing_paths:
        print(f"  - {path}", file=sys.stderr)
if extra_paths:
    print("Active Sources without a test file:", file=sys.stderr)
    for path in extra_paths:
        print(f"  - {path}", file=sys.stderr)
if missing_paths or extra_paths:
    raise SystemExit(1)
print("PASS: CopilotMonitorTests Sources matches all Swift files on disk")
PY
