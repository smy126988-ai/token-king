#!/bin/bash
# f2b-codex-stats.sh — canonical Codex token usage report.
#
# Reads the local F2b SQLite at $F2B_DB_PATH (default: macOS app support)
# and prints a consistent three-section report for rows with
# `source='codexCli'` (Codex CLI / Codex Desktop rollout files):
#
#   1. Totals          (single row, all-time)
#   2. By month        (one row per YYYY-MM)
#   3. By day          (last 31 days, fixed shape)
#   4. By provider     (one row per F2b Provider enum case)
#   5. By provider+model (top-N by billable, default N=20)
#
# Schema warning: Codex's `last_token_usage.{input_tokens, cached_input_tokens}`
# are CUMULATIVE per session (not per-turn), which previously inflated
# aggregate totals by 10-30× depending on session length. The fix landed
# in Helpers/TokenExtractor/CodexExtractor.swift (per-session delta
# conversion). After the fix, this script's output reflects the actual
# per-turn token consumption.
#
# Token columns match f2b-opencode-stats.sh so rows can be diffed directly:
#   input/output/reasoning — billed at full rate (when applicable)
#   cache_read  — billed at a discounted rate (NOT free, NOT zero-cost)
#   cache_write — billed at higher rate on Anthropic-style APIs (typically 0 here)
#   billable    — input + output + reasoning (the strict subscription cost)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

F2B_DB_PATH="${F2B_DB_PATH:-$HOME/Library/Application Support/TokenKing/f2b.sqlite}"
SOURCE_FILTER="codexCli"
SINCE=""
PROVIDER_FILTER=""
TOP_MODELS=20

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)        F2B_DB_PATH="$2"; shift 2 ;;
        --source)    SOURCE_FILTER="$2"; shift 2 ;;
        --since)     SINCE="$2"; shift 2 ;;
        --provider)  PROVIDER_FILTER="$2"; shift 2 ;;
        --top-models) TOP_MODELS="$2"; shift 2 ;;
        -h|--help)   usage 0 ;;
        *)           echo "unknown arg: $1" >&2; usage 1 ;;
    esac
done

if [[ ! -f "$F2B_DB_PATH" ]]; then
    echo "F2b DB not found at: $F2B_DB_PATH" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null; then
    echo "sqlite3 not on PATH" >&2
    exit 1
fi

validate_filter() {
    local name="$1" value="$2"
    if [[ -z "$value" ]]; then return 0; fi
    if [[ "$value" =~ [^a-zA-Z0-9_./:_-] ]]; then
        echo "rejecting $name=\"$value\": contains characters outside [a-zA-Z0-9_./:_-]" >&2
        exit 1
    fi
}

validate_filter --source     "$SOURCE_FILTER"
validate_filter --provider   "$PROVIDER_FILTER"
validate_filter --since      "$SINCE"

WHERE_BASE="source = '$SOURCE_FILTER'"
[[ -n "$PROVIDER_FILTER" ]] && WHERE_BASE="$WHERE_BASE AND provider = '$PROVIDER_FILTER'"
[[ -n "$SINCE" ]] && WHERE_BASE="$WHERE_BASE AND date(ts_ms/1000, 'unixepoch') >= '$SINCE'"

SQL_FMT_INPUT="printf('%.2f M', SUM(input)/1e6)"
SQL_FMT_OUTPUT="printf('%.2f M', SUM(output)/1e6)"
SQL_FMT_REASON="printf('%.2f K', SUM(reasoning)/1e3)"
SQL_FMT_CACHERD="printf('%.2f B', SUM(cache_read)/1e9)"
SQL_FMT_CACHEWR="printf('%.2f K', SUM(cache_write)/1e3)"
SQL_FMT_BILLABLE="printf('%.2f M', SUM(input+output+reasoning)/1e6)"

run_sql() {
    sqlite3 -separator '|' -header -column "$F2B_DB_PATH" <<<".timeout 5000
.headers on
.mode column
$1"
}

print_header() {
    local section="$1"
    echo ""
    echo "=================================================================="
    echo "  F2b Codex stats — $section"
    echo "  source   : $SOURCE_FILTER"
    [[ -n "$PROVIDER_FILTER" ]] && echo "  provider : $PROVIDER_FILTER"
    [[ -n "$SINCE" ]] && echo "  since    : $SINCE"
    echo "  db       : $F2B_DB_PATH"
    echo "  captured : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "=================================================================="
}

print_header "1/5 Totals (all-time)"

run_sql "
SELECT
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(*) AS events,
  $SQL_FMT_INPUT AS input_M,
  $SQL_FMT_OUTPUT AS output_M,
  $SQL_FMT_REASON AS reasoning_K,
  $SQL_FMT_CACHERD AS cache_read_B,
  $SQL_FMT_CACHEWR AS cache_write_K,
  $SQL_FMT_BILLABLE AS billable_M
FROM token_events
WHERE $WHERE_BASE
"

print_header "2/5 By month"

run_sql "
SELECT
  strftime('%Y-%m', ts_ms/1000, 'unixepoch') AS month,
  COUNT(*) AS events,
  $SQL_FMT_INPUT AS input_M,
  $SQL_FMT_OUTPUT AS output_M,
  $SQL_FMT_REASON AS reasoning_K,
  $SQL_FMT_CACHERD AS cache_read_B,
  $SQL_FMT_CACHEWR AS cache_write_K,
  $SQL_FMT_BILLABLE AS billable_M
FROM token_events
WHERE $WHERE_BASE
GROUP BY month
ORDER BY month
"

print_header "3/5 By day (last 31 days from now)"

run_sql "
SELECT
  date(ts_ms/1000, 'unixepoch') AS day,
  COUNT(*) AS events,
  $SQL_FMT_INPUT AS input_M,
  $SQL_FMT_OUTPUT AS output_M,
  $SQL_FMT_REASON AS reasoning_K,
  $SQL_FMT_CACHERD AS cache_read_B,
  $SQL_FMT_CACHEWR AS cache_write_K,
  $SQL_FMT_BILLABLE AS billable_M
FROM token_events
WHERE $WHERE_BASE
  AND date(ts_ms/1000, 'unixepoch') >= date('now', '-31 days')
GROUP BY day
ORDER BY day DESC
"

print_header "4/5 By provider"

run_sql "
SELECT
  provider,
  COUNT(*) AS events,
  $SQL_FMT_INPUT AS input_M,
  $SQL_FMT_OUTPUT AS output_M,
  $SQL_FMT_REASON AS reasoning_K,
  $SQL_FMT_CACHERD AS cache_read_B,
  $SQL_FMT_CACHEWR AS cache_write_K,
  $SQL_FMT_BILLABLE AS billable_M
FROM token_events
WHERE $WHERE_BASE
GROUP BY provider
ORDER BY (SUM(input)+SUM(output)+SUM(reasoning)+SUM(cache_read)) DESC
"

print_header "5/5 By provider × model (top $TOP_MODELS by billable)"

run_sql "
SELECT
  provider,
  model,
  COUNT(*) AS events,
  $SQL_FMT_INPUT AS input_M,
  $SQL_FMT_CACHERD AS cache_read_B,
  $SQL_FMT_BILLABLE AS billable_M
FROM token_events
WHERE $WHERE_BASE
GROUP BY provider, model
ORDER BY SUM(input+output+reasoning) DESC
LIMIT $TOP_MODELS
"

echo ""
echo "=================================================================="
echo "  End of report"
echo "=================================================================="
