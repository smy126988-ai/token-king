#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
checker="$repository_root/scripts/check-test-target-membership.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "Expected output to contain '$expected', got: $output"
}

write_project() {
  local root="$1"
  shift
  local source_entries=""
  local build_file_entries=""
  local file_reference_entries=""
  local group_entries=""
  local index=1

  for relative_path in "$@"; do
    local file_name="${relative_path##*/}"
    source_entries+="        BUILD${index} /* ${file_name} in Sources */,"$'\n'
    build_file_entries+="    BUILD${index} /* ${file_name} in Sources */ = {isa = PBXBuildFile; fileRef = FILEREF${index} /* ${file_name} */; };"$'\n'
    file_reference_entries+="    FILEREF${index} /* ${file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${relative_path}; sourceTree = \"<group>\"; };"$'\n'
    group_entries+="        FILEREF${index} /* ${file_name} */,"$'\n'
    index=$((index + 1))
  done

  mkdir -p "$root/CopilotMonitor/CopilotMonitor.xcodeproj"
  mkdir -p "$root/CopilotMonitor/CopilotMonitorTests"

  {
    printf '%s\n' '// !$*UTF8*$!'
    printf '%s\n' '{'
    printf '%s\n' '  objects = {'
    printf '%s' "$build_file_entries"
    printf '%s' "$file_reference_entries"
    printf '%s\n' '    TESTTARGET /* CopilotMonitorTests */ = {'
    printf '%s\n' '      isa = PBXNativeTarget;'
    printf '%s\n' '      buildPhases = (TESTSOURCES /* Sources */,);'
    printf '%s\n' '      name = CopilotMonitorTests;'
    printf '%s\n' '    };'
    printf '%s\n' '    TESTGROUP /* CopilotMonitorTests */ = {'
    printf '%s\n' '      isa = PBXGroup;'
    printf '%s\n' '      children = ('
    printf '%s' "$group_entries"
    printf '%s\n' '      );'
    printf '%s\n' '      path = CopilotMonitorTests;'
    printf '%s\n' '      sourceTree = "<group>";'
    printf '%s\n' '    };'
    printf '%s\n' '    TESTSOURCES /* Sources */ = {'
    printf '%s\n' '      isa = PBXSourcesBuildPhase;'
    printf '%s\n' '      files = ('
    printf '%s' "$source_entries"
    printf '%s\n' '      );'
    printf '%s\n' '    };'
    printf '%s\n' '  };'
    printf '%s\n' '}'
  } > "$root/CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj"
}

run_checker() {
  local root="$1"
  set +e
  CHECK_TEST_MEMBERSHIP_ROOT="$root" "$checker" 2>&1
  local status=$?
  set -e
  return "$status"
}

[[ -x "$checker" ]] || fail "Checker is missing or not executable: $checker"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

complete="$fixture_root/complete"
write_project "$complete" "AlphaTests.swift" "Nested/BetaTests.swift"
touch "$complete/CopilotMonitor/CopilotMonitorTests/AlphaTests.swift"
mkdir -p "$complete/CopilotMonitor/CopilotMonitorTests/Nested"
touch "$complete/CopilotMonitor/CopilotMonitorTests/Nested/BetaTests.swift"
complete_output="$(run_checker "$complete")" || fail "Complete fixture should pass: $complete_output"
assert_contains "$complete_output" "2 test files on disk, 2 active test sources"

missing="$fixture_root/missing"
write_project "$missing" "AlphaTests.swift"
touch "$missing/CopilotMonitor/CopilotMonitorTests/AlphaTests.swift"
touch "$missing/CopilotMonitor/CopilotMonitorTests/MissingTests.swift"
set +e
missing_output="$(run_checker "$missing")"
missing_status=$?
set -e
[[ $missing_status -ne 0 ]] || fail "Missing source fixture should fail"
assert_contains "$missing_output" "MissingTests.swift"
assert_contains "$missing_output" "Missing from CopilotMonitorTests Sources"

extra="$fixture_root/extra"
write_project "$extra" "AlphaTests.swift" "RemovedTests.swift"
touch "$extra/CopilotMonitor/CopilotMonitorTests/AlphaTests.swift"
set +e
extra_output="$(run_checker "$extra")"
extra_status=$?
set -e
[[ $extra_status -ne 0 ]] || fail "Extra source fixture should fail"
assert_contains "$extra_output" "RemovedTests.swift"
assert_contains "$extra_output" "Active Sources without a test file"

duplicate="$fixture_root/duplicate"
write_project "$duplicate" "One/SameTests.swift" "Two/SameTests.swift"
mkdir -p "$duplicate/CopilotMonitor/CopilotMonitorTests/One"
mkdir -p "$duplicate/CopilotMonitor/CopilotMonitorTests/Two"
touch "$duplicate/CopilotMonitor/CopilotMonitorTests/One/SameTests.swift"
touch "$duplicate/CopilotMonitor/CopilotMonitorTests/Two/SameTests.swift"
if ! duplicate_output="$(run_checker "$duplicate")"; then
  fail "Distinct paths with duplicate basenames should pass: $duplicate_output"
fi
assert_contains "$duplicate_output" "2 test files on disk, 2 active test sources"

echo "PASS: test target membership checker fixtures"
