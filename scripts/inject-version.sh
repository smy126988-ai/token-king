#!/usr/bin/env bash
# ============================================================================
# scripts/inject-version.sh
# ============================================================================
# Single source of truth for app version. Writes git-derived values into the
# target Info.plist without modifying the source working tree when the target
# is a build artifact (e.g. $TARGET_BUILD_DIR/$INFOPLIST_PATH).
#
# Injected keys:
#   - CFBundleShortVersionString: tag portion (e.g. "2.13.0")
#   - CFBundleVersion:            commit count since tag (e.g. "5")
#   - GitCommitHash:              short SHA (e.g. "a1b2c3d")
#
# Usage:
#   scripts/inject-version.sh [TARGET_PLIST] [--check]
#   scripts/inject-version.sh --info-plist PATH [--check]
#
#   Xcode build phase example:
#     bash "$SRCROOT/scripts/inject-version.sh" "$TARGET_BUILD_DIR/$INFOPLIST_PATH"
#
# --check: only verify the target values match git; do not modify the plist.
#          Exits 0 if matched, 1 otherwise (for CI gating).
#
# Environment overrides (used by tests):
#   GIT_DESCRIBE  - skip `git describe` and use this string verbatim
#   GIT_SHORT_SHA - skip `git rev-parse --short HEAD` and use this string
#
# The script intentionally does NOT touch SUFeedURL, CFBundleDisplayName,
# or CFBundleIdentifier (those are project-wide fixed values).
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_PLIST="$REPO_ROOT/CopilotMonitor/CopilotMonitor/Info.plist"
MODE="write"

# Default target: build artifact when Xcode env vars are present, otherwise the
# source Info.plist. Callers (e.g. the Xcode build phase) should pass the
# artifact path explicitly to avoid relying on defaults.
if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${INFOPLIST_PATH:-}" ]; then
  INFO_PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
else
  INFO_PLIST="$SOURCE_PLIST"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --info-plist) INFO_PLIST="$2"; shift 2 ;;
    --check) MODE="check"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    --*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *)
      # Positional argument is the target plist path. Accept it even if the
      # file does not exist yet; the fallback below will seed it from source.
      INFO_PLIST="$1"
      shift
      ;;
  esac
done

if [ ! -f "$INFO_PLIST" ]; then
  # The build artifact Info.plist may not have been processed yet (e.g. when
  # this script runs as an early build phase). Seed it from the source plist
  # so version injection can proceed without failing the build.
  if [ -f "$SOURCE_PLIST" ]; then
    mkdir -p "$(dirname "$INFO_PLIST")"
    cp "$SOURCE_PLIST" "$INFO_PLIST"
  else
    echo "ERROR: Info.plist not found at $INFO_PLIST and source plist missing at $SOURCE_PLIST" >&2
    exit 1
  fi
fi

# Source git values (with override points for testing)
if [ -n "${GIT_DESCRIBE:-}" ]; then
  DESCRIBE="$GIT_DESCRIBE"
else
  DESCRIBE="$(cd "$REPO_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo "0.0.0-unknown")"
fi

if [ -n "${GIT_SHORT_SHA:-}" ]; then
  SHORT_SHA="$GIT_SHORT_SHA"
else
  SHORT_SHA="$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi

# Parse `git describe` output formats:
#   "v2.13.0"                  -> tag only
#   "v2.13.0-5-gabcdef0"       -> tag + N commits ahead + short SHA
#   "v2.13.0-5-gabcdef0-dirty" -> same with -dirty suffix
#   "a1b2c3d"                  -> no tag, fall back to commit-count 0
MARKETING_VERSION=""
BUILD_NUMBER="0"
if [[ "$DESCRIBE" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-(.+)-g[0-9a-f]+)?(-dirty)?$ ]]; then
  MARKETING_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  if [ -n "${BASH_REMATCH[5]:-}" ]; then
    BUILD_NUMBER="${BASH_REMATCH[5]}"
  fi
elif [[ "$DESCRIBE" =~ ^[0-9a-f]+(-dirty)?$ ]]; then
  # Pre-tag commits only — use 0.0.0 as marketing version until a tag is cut
  MARKETING_VERSION="0.0.0"
  BUILD_NUMBER="0"
else
  echo "WARN: unrecognized git describe output: $DESCRIBE" >&2
  MARKETING_VERSION="0.0.0"
  BUILD_NUMBER="0"
fi

# Read current values (for --check mode)
CURRENT_SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "")
CURRENT_HASH=$(/usr/libexec/PlistBuddy -c "Print :GitCommitHash" "$INFO_PLIST" 2>/dev/null || echo "")

if [ "$MODE" = "check" ]; then
  if [ "$CURRENT_SHORT" = "$MARKETING_VERSION" ] && [ "$CURRENT_BUILD" = "$BUILD_NUMBER" ] && [ "$CURRENT_HASH" = "$SHORT_SHA" ]; then
    echo "OK: Info.plist matches git ($MARKETING_VERSION / $BUILD_NUMBER / $SHORT_SHA)"
    exit 0
  else
    {
      echo "MISMATCH:"
      echo "  expected: $MARKETING_VERSION / $BUILD_NUMBER / $SHORT_SHA"
      echo "  actual:   $CURRENT_SHORT / $CURRENT_BUILD / $CURRENT_HASH"
      echo "Run 'make version' to update Info.plist."
    } >&2
    exit 1
  fi
fi

# Inject via PlistBuddy (adds key if missing, updates if present)
set_plist_value() {
  local key="$1" value="$2"
  if /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$INFO_PLIST"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$INFO_PLIST"
  fi
}

set_plist_value "CFBundleShortVersionString" "$MARKETING_VERSION"
set_plist_value "CFBundleVersion" "$BUILD_NUMBER"
set_plist_value "GitCommitHash" "$SHORT_SHA"

echo "Injected version: $MARKETING_VERSION ($BUILD_NUMBER) sha=$SHORT_SHA"
