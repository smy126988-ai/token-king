#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
checker="$repository_root/scripts/check-offline-test-boundaries.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  [[ "$output" == *"$expected"* ]] || fail "Expected output to contain '$expected', got: $output"
}

write_clean_fixture() {
  local root="$1"
  mkdir -p "$root/CopilotMonitor/CopilotMonitorTests"
  mkdir -p "$root/CopilotMonitor/CopilotMonitorLiveTests"
  cat > "$root/CopilotMonitor/CopilotMonitorTests/OfflineProviderTests.swift" <<'SWIFT'
import XCTest

final class OfflineProviderTests: XCTestCase {
    func testOfflineFixture() {
        XCTAssertTrue(true)
    }
}

// URLSession.shared, session: .shared, XCTSkip, and RUN_LIVE_PROVIDER_TESTS
// are documentation here and must not trigger the checker.
SWIFT
  cat > "$root/CopilotMonitor/CopilotMonitorLiveTests/SampleLiveIntegrationTests.swift" <<'SWIFT'
import XCTest

final class SampleLiveIntegrationTests: XCTestCase {
    func testRealProvider() async throws {
        try LiveProviderTestGate.requireEnabled()
        guard ProcessInfo.processInfo.environment["RUN_LIVE_PROVIDER_TESTS"] == "1" else {
            throw XCTSkip("Live provider tests are disabled")
        }
        _ = URLSession.shared
        _ = Provider(session: .shared)
    }
}
SWIFT
}

run_checker() {
  local root="$1"
  CHECK_OFFLINE_BOUNDARY_ROOT="$root" "$checker" 2>&1
}

[[ -x "$checker" ]] || fail "Checker is missing or not executable: $checker"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

clean="$fixture_root/clean"
write_clean_fixture "$clean"
clean_output="$(run_checker "$clean")" || fail "Clean fixture should pass: $clean_output"
assert_contains "$clean_output" "offline test boundary checks passed"

for token in \
  'throw XCTSkip("forbidden")' \
  'let value = "RUN_LIVE_PROVIDER_TESTS"' \
  '_ = URLSession.shared' \
  '_ = Provider(session: .shared)' \
  'final class BadLiveIntegrationTests: XCTestCase {}'
do
  bad="$fixture_root/bad-$(printf '%s' "$token" | cksum | cut -d' ' -f1)"
  write_clean_fixture "$bad"
  printf '\n%s\n' "$token" >> "$bad/CopilotMonitor/CopilotMonitorTests/OfflineProviderTests.swift"
  set +e
  bad_output="$(run_checker "$bad")"
  bad_status=$?
  set -e
  [[ $bad_status -ne 0 ]] || fail "Forbidden unit token should fail: $token"
  assert_contains "$bad_output" "CopilotMonitorTests/OfflineProviderTests.swift"
done

missing_gate="$fixture_root/missing-gate"
write_clean_fixture "$missing_gate"
python3 - "$missing_gate/CopilotMonitor/CopilotMonitorLiveTests/SampleLiveIntegrationTests.swift" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
contents = path.read_text(encoding="utf-8")
path.write_text(
    contents.replace(
        "        try LiveProviderTestGate.requireEnabled()\n",
        "        let startedWithoutGate = true\n        try LiveProviderTestGate.requireEnabled()\n",
        1,
    ),
    encoding="utf-8",
)
PY
set +e
missing_gate_output="$(run_checker "$missing_gate")"
missing_gate_status=$?
set -e
[[ $missing_gate_status -ne 0 ]] || fail "A late live gate should fail"
assert_contains "$missing_gate_output" "first executable statement"

echo "PASS: offline test boundary checker fixtures"
