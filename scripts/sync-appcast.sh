#!/usr/bin/env bash
# ============================================================================
# scripts/sync-appcast.sh
# ============================================================================
# Build a Sparkle appcast.xml from a signed DMG and signing key.
#
# Inputs:
#   --dmg <path>      Path to the signed DMG (e.g. Token-King-2.13.0.dmg)
#   --version <x.y.z> Marketing version string (e.g. 2.13.0). If omitted, the
#                     script parses it out of the DMG filename.
#   --build <n>       Numeric build number. If omitted, read from
#                     Info.plist via PlistBuddy (post inject-version.sh).
#   --key  <path>     Sparkle ed25519 private key file (NOT the .pub). Same
#                     key whose public counterpart is in Info.plist
#                     SUPublicEDKey.
#   --out <path>      Where to write appcast.xml. Default:
#                     .private/appcast/appcast.xml
#   --download-url    Public URL where users fetch this DMG. Defaults to
#                     https://github.com/smy126988-ai/token-king/releases/download/<ver>/<dmg>
#   --min-os <x.y>    minimumSystemVersion in appcast <item>. Default: 13.0
#
# Outputs:
#   - Prints appcast.xml path on stdout (last line)
#   - Pretty-prints the file to stderr for the operator to inspect
#
# Why a separate script? The same appcast XML is uploaded to GitHub Pages
# (the SUFeedURL target) AND attached to GitHub Releases (as a copy for
# users who read release notes directly). This script produces ONE source of
# truth file; the deploy step is left to whichever channel is live.
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DMG=""
VERSION=""
BUILD=""
KEY=""
OUT="$REPO_ROOT/.private/appcast/appcast.xml"
DL_URL=""
MIN_OS="13.0"
TEMPLATE="$REPO_ROOT/.private/appcast/appcast-template.xml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) DMG="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --build) BUILD="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --download-url) DL_URL="$2"; shift 2 ;;
    --min-os) MIN_OS="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$DMG" ] || [ ! -f "$DMG" ]; then
  echo "ERROR: --dmg <path> required and file must exist" >&2
  exit 1
fi
if [ -z "$KEY" ] || [ ! -f "$KEY" ]; then
  echo "ERROR: --key <path> required (Sparkle ed private key)" >&2
  exit 1
fi
if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found: $TEMPLATE" >&2
  echo "       Did you accidentally commit .private/ to the repo?" >&2
  exit 1
fi

# Derive version from DMG filename if not given
if [ -z "$VERSION" ]; then
  if [[ "$(basename "$DMG")" =~ -v?([0-9]+\.[0-9]+\.[0-9]+)\.dmg$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
  else
    echo "ERROR: cannot derive version from DMG filename; pass --version" >&2
    exit 1
  fi
fi

# Read build from Info.plist if not given
if [ -z "$BUILD" ]; then
  PLIST="$REPO_ROOT/CopilotMonitor/CopilotMonitor/Info.plist"
  BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "0")
fi

# Default download URL
if [ -z "$DL_URL" ]; then
  DL_URL="https://github.com/smy126988-ai/token-king/releases/download/v${VERSION}/$(basename "$DMG")"
fi

# Find sign_update tool: prefer local sparkle/bin/, then PATH
SIGN_TOOL=""
for candidate in "$REPO_ROOT/sparkle/bin/sign_update" "./sparkle/bin/sign_update" "$(command -v sign_update 2>/dev/null)"; do
  if [ -x "$candidate" ]; then SIGN_TOOL="$candidate"; break; fi
done
if [ -z "$SIGN_TOOL" ]; then
  echo "ERROR: sign_update not found. Download Sparkle tools and place sign_update under sparkle/bin/" >&2
  exit 1
fi

# Sparkle sign_update output: sparkle:edSignature="<SIG>" length="<LEN>"
echo "==> Signing $DMG with $SIGN_TOOL"
FULL_OUTPUT="$("$SIGN_TOOL" "$DMG" --ed-key-file "$KEY")"
SIGNATURE=$(echo "$FULL_OUTPUT" | awk -F '"' '{print $2}')
if [ -z "$SIGNATURE" ]; then
  echo "ERROR: failed to parse Sparkle signature" >&2
  echo "$FULL_OUTPUT" >&2
  exit 1
fi
DMG_SIZE=$(stat -f%z "$DMG")
PUB_DATE=$(date -R)

# Build the <item> body and substitute placeholders into template
ITEM_BLOCK=$(
  cat <<ITEM
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
      <description><![CDATA[]]></description>
      <enclosure url="${DL_URL}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${DMG_SIZE}"
                 type="application/octet-stream"/>
    </item>
ITEM
)

mkdir -p "$(dirname "$OUT")"
{
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
  printf '%s\n' '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">'
  printf '%s\n' '  <channel>'
  printf '%s\n' '    <title>Token King Updates</title>'
  printf '%s\n' "    <link>${DL_URL%/$(basename "$DMG")}/appcast.xml</link>"
  printf '%s\n' '    <description>Token King release channel. Most recent changes with links to updates.</description>'
  printf '%s\n' '    <language>en</language>'
  printf '%s\n' "$ITEM_BLOCK"
  printf '%s\n' '  </channel>'
  printf '%s\n' '</rss>'
} > "$OUT"

echo "==> Wrote appcast to $OUT"
echo "    version=${VERSION} build=${BUILD} size=${DMG_SIZE}"
echo "    feed: ${DL_URL%/$(basename "$DMG")}/appcast.xml"
echo
echo "----- appcast.xml -----"
cat "$OUT"
