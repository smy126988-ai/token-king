#!/usr/bin/env bash
# refresh-pricing-snapshot.sh
#
# Helper script for refreshing PricingSnapshot data in
# CopilotMonitor/CopilotMonitorTests/Helpers/PricingSnapshotTests.swift.
#
# This is a manual workflow — the agent (human or AI) must:
#   1. Open each snapshot's source URL in a browser
#   2. Compare the public price with the snapshot's stored value
#   3. If the public price changed, update the snapshot AND the
#      corresponding PricingTable.swift entry
#   4. Update capturedAt to the current date
#   5. Re-run the test suite: `xcodebuild test -only-testing:CopilotMonitorTests/PricingSnapshotTests`
#
# This script just prints the URLs and current snapshot dates so the
# refresher doesn't have to dig through the test file. Edit the snapshot
# array in PricingSnapshotTests.swift manually (the script does not
# auto-edit Swift source — that's a structural change that needs human review).
#
# Usage: ./scripts/refresh-pricing-snapshot.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_FILE="$REPO_ROOT/CopilotMonitor/CopilotMonitorTests/Helpers/PricingSnapshotTests.swift"

if [ ! -f "$TEST_FILE" ]; then
    echo "ERROR: $TEST_FILE not found" >&2
    exit 1
fi

echo "=== Pricing Snapshot Refresh Helper ==="
echo
echo "Source file: $TEST_FILE"
echo
echo "Snapshot URLs to re-fetch (in order of appearance):"
echo

# Extract URL and model name from the test file. Pattern matches:
#   URL(string: "https://...")!,
# Captured 2026-07-13 ...
# Approximate parse — outputs the next 5 lines after the URL for context.
awk '
    /URL\(string: "https:/ {
        match($0, /"https:\/\/[^"]+"/)
        url = substr($0, RSTART+1, RLENGTH-2)
        # Look back for the model name in the same record.
        getline model_line
        getline provider_line
        getline input_line
        getline output_line
        getline cache_line
        # Model name is the 2nd token (after the var name).
        model = model_line
        sub(/.*"/, "", model)
        sub(/".*/, "", model)
        printf "  • %-25s %s\n", model, url
    }
' "$TEST_FILE"

echo
echo "PricingTable.swift locations for matching rate entries:"
echo "  - rate(for: ProviderIdentifier)         ~lines 50-170"
echo "  - modelRate(for: model)                 ~lines 220-450"
echo "  - modelRate(for: model, provider:)      ~lines 480-500"
echo
echo "Stale check: snapshots older than 90 days will fail"
echo "  testSnapshotsAreRecent. Update capturedAt when you refresh."
echo
echo "After updating, verify with:"
echo "  xcodebuild test -only-testing:CopilotMonitorTests/PricingSnapshotTests \\"
echo "    -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor \\"
echo "    -destination 'platform=macOS'"
