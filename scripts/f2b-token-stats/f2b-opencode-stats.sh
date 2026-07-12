#!/bin/bash
# f2b-opencode-stats.sh — canonical OpenCode token usage report.
#
# Reads the local F2b SQLite at $F2B_DB_PATH (default: macOS app support),
# queries the `token_events` table for rows with `source='opencode'`, and
# prints a consistent three-section report:
#
#   1. Totals          (single row, all-time)
#   2. By month        (one row per YYYY-MM)
#   3. By day          (one row per YYYY-MM-DD, last 31 days by default)
#   4. By provider     (one row per F2b Provider enum case)
#   5. By provider+model (top-N by billable, default N=20)
#
# Every section exposes the same five token columns so the rows can be
# diffed against an earlier run to detect data drift:
#
#   input       — fresh prompt tokens per turn (billed)
#   output      — generation tokens per turn (billed)
#   reasoning   — thinking/reasoning tokens per turn (billed)
#   cache_read  — tokens served from cache (billed at a discounted rate,
#                 NOT free — see Harness note in docs)
#   cache_write — tokens written into the cache (billed)
#   billable    — input + output + reasoning (the strict subscription cost)
#
# Usage:
#   ./f2b-opencode-stats.sh                 # default: last 31 days, all-time totals
#   ./f2b-opencode-stats.sh --since 2026-07 # scope the day table
#   ./f2b-opencode-stats.sh --provider minimaxCN  # filter to a single provider
#   ./f2b-opencode-stats.sh --top-models 30
#   ./f2b-opencode-stats.sh --db /path/to/other.sqlite
#
# Designed to be the canonical regression oracle for F2b OpenCode data:
# after any extractor change, rerun this and diff the output against the
# last commit's snapshot. Any delta should map to a documented change.
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

F2B_DB_PATH="${F2B_DB_PATH:-$HOME/Library/Application Support/TokenKing/f2b.sqlite}"
SOURCE_FILTER="opencode"
SINCE=""
PROVIDER_FILTER=""
TOP_MODELS=20
TIMEZONE="UTC"   # F2b stores ts_ms epoch; render in UTC for consistency

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)        F2B_DB_PATH="$2"; shift 2 ;;
        --source)    SOURCE_FILTER="$2"; shift 2 ;;
        --since)     SINCE="$2"; shift 2 ;;
        --provider)  PROVIDER_FILTER="$2"; shift 2 ;;
        --top-models) TOP_MODELS="$2"; shift 2 ;;
        --tz)        TIMEZONE="$2"; shift 2 ;;
        -h|--help)   usage 0 ;;
        *)           echo "unknown arg: $1" >&2; usage 1 ;;
    esac
done

if [[ ! -f "$F2B_DB_PATH" ]]; then
    echo "F2b DB not found at: $F2B_DB_PATH" >&2
    echo "override with --db <path> or F2B_DB_PATH env" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null; then
    echo "sqlite3 not on PATH" >&2
    exit 1
fi

# Reject any filter value containing characters that could break out of the
# single-quote SQL interpolation. The script is single-user/local but it costs
# nothing to be strict, and quoting-error-prone callers (CI reruns etc.) won't
# accidentally inject. The character class puts `-` at the end so POSIX BRE
# can't mis-read it as a range start.
validate_filter() {
    local name="$1" value="$2"
    if [[ -z "$value" ]]; then return 0; fi
    if [[ "$value" =~ [^a-zA-Z0-9_./:_-] ]]; then
        echo "rejecting $name=\"$value\": contains characters outside [a-zA-Z0-9_./:_-]" >&2
        exit 1
    fi
    return 0
}

validate_filter --source     "$SOURCE_FILTER"
validate_filter --provider   "$PROVIDER_FILTER"
validate_filter --since      "$SINCE"

# ---------------------------------------------------------------------------
# SQL fragments
# ---------------------------------------------------------------------------

# `source = 'opencode'` is hard-coded in the FROM/WHERE; provider filter and
# since filter are layered on top.

WHERE_BASE="source = '$SOURCE_FILTER'"
[[ -n "$PROVIDER_FILTER" ]] && WHERE_BASE="$WHERE_BASE AND provider = '$PROVIDER_FILTER'"
[[ -n "$SINCE" ]] && WHERE_BASE="$WHERE_BASE AND date(ts_ms/1000, 'unixepoch') >= '$SINCE'"

# Human-friendly formatting helpers (M = 1e6 input/output/reasoning,
# B = 1e9 cache_read, K = 1e3 cache_write). Same shell command in every
# section so columns line up.
fmt_tokens() {
    local col="$1" agg="$2"  # col=input, agg=SUM(col)
    case "$col" in
        cache_read) printf "%.2f B" "$(echo "$agg" | bc -l)/1000000000" ;;
        cache_write) printf "%.2f K" "$(echo "$agg" | bc -l)/1000" ;;
        *)           printf "%.2f M" "$(echo "$agg" | bc -l)/1000000" ;;
    esac
}

# Inline printf-style formatting done in SQL so we can compare rows
# by eye without arithmetic.
SQL_FMT_INPUT="printf('%.2f M', SUM(input)/1e6)"
SQL_FMT_OUTPUT="printf('%.2f M', SUM(output)/1e6)"
SQL_FMT_REASON="printf('%.2f K', SUM(reasoning)/1e3)"
SQL_FMT_CACHERD="printf('%.2f B', SUM(cache_read)/1e9)"
SQL_FMT_CACHEWR="printf('%.2f K', SUM(cache_write)/1e3)"
SQL_FMT_BILLABLE="printf('%.2f M', SUM(input+output+reasoning)/1e6)"

run_sql() {
    # Set up the sqlite session with a stable display. Columns always render
    # the same way so successive runs diff cleanly.
    sqlite3 -separator '|' \
            -header -column \
            "$F2B_DB_PATH" <<<".timeout 5000
.headers on
.mode column
$1"
}

# ---------------------------------------------------------------------------
# Output sections
# ---------------------------------------------------------------------------

print_header() {
    local section="$1"
    echo ""
    echo "=================================================================="
    echo "  F2b OpenCode stats — $section"
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

# Day section always shows the last 31 days regardless of --since,
# so the script's "shape" is stable across runs.
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
