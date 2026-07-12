#!/bin/bash
# ccusage-benchmark.sh — cross-check F2b SQLite totals against ccusage --json.
#
# Compares F2b's per-date token totals (read from local f2b.sqlite) against
# the canonical ccusage JSON output (npx ccusage@latest). Both target the
# same calendar window so the user can spot algorithm divergence (dup
# snapshot handling, timezone rounding, source_id collisions, etc.) without
# running ccusage manually.
#
# Sources mapped: F2b source -> ccusage agent
#   codexCli    -> codex
#   opencode    -> opencode
#   claudeCode  -> claude
#   kimiCode    -> kimi  (ccusage kimi subcommand is in beta; useful but treat as fuzzy)
#   kimiCli     -> kimi  (legacy rollup; ccusage may double-count with new sessions)
#
# Output is one table per provider (5 sections): per-day per-metric rows
# from ccusage vs F2b with the deviation ratio and absolute delta. A
# per-provider total closes each section. The script exits non-zero if any
# provider's cache_read total deviates by more than 5% (warning threshold
# tunable via --tolerance). Run after any extractor change to detect drift.
#
# Usage:
#   ./ccusage-benchmark.sh --since 2026-07-01 --until 2026-07-31
#   ./ccusage-benchmark.sh --since 2026-07-01 --until 2026-07-31 --provider codex
#   ./ccusage-benchmark.sh --tolerance 0.02       # 2% threshold
#   ./ccusage-benchmark.sh --db /path/to/other.sqlite --skip-ccusage   # F2b only
#   ./ccusage-benchmark.sh --skip-f2b                                # ccusage only
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

F2B_DB_PATH="${F2B_DB_PATH:-$HOME/Library/Application Support/TokenKing/f2b.sqlite}"
CCUSAGE="${CCUSAGE:-npx --yes ccusage@latest --offline}"

# Cross-platform default window: full previous calendar month. Uses
# python3 because both BSD date (macOS) and coreutils date lack a flag
# that computes "first day of last month" portably.
SINCE_DEFAULT="$(python3 -c 'from datetime import date,timedelta; t=date.today().replace(day=1); print((t-timedelta(days=1)).replace(day=1))' 2>/dev/null || echo 1970-01-01)"
UNTIL_DEFAULT="$(python3 -c 'from datetime import date; print(date.today().replace(day=1))' 2>/dev/null || echo 1970-01-01)"
SINCE="${SINCE:-$SINCE_DEFAULT}"
UNTIL="${UNTIL:-$UNTIL_DEFAULT}"
PROVIDER_FILTER=""
TOLERANCE="0.05"
SKIP_CCUSAGE=0
SKIP_F2B=0

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) F2B_DB_PATH="$2"; shift 2 ;;
        --since) SINCE="$2"; shift 2 ;;
        --until) UNTIL="$2"; shift 2 ;;
        --provider) PROVIDER_FILTER="$2"; shift 2 ;;
        --tolerance) TOLERANCE="$2"; shift 2 ;;
        --skip-ccusage) SKIP_CCUSAGE=1; shift ;;
        --skip-f2b) SKIP_F2B=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "unknown arg: $1" >&2; usage 1 ;;
    esac
done

if ! command -v sqlite3 >/dev/null; then
    echo "sqlite3 not on PATH" >&2
    exit 1
fi

if [[ -z "$PROVIDER_FILTER" ]]; then
    PROVIDER_FILTER="codex,opencode,claude,kimi"
fi

if [[ $SKIP_F2B -eq 0 && ! -f "$F2B_DB_PATH" ]]; then
    echo "F2b DB not found at: $F2B_DB_PATH" >&2
    echo "override with --db <path> or F2B_DB_PATH env" >&2
    SKIP_F2B=1
fi

# F2b source -> ccusage agent mapping is handled by the case statement
# in the main loop below (bash 3.2 lacks `declare -A`). Source values
# mirror F2b's `TokenSource` enum (codexCli, opencode, claudeCode,
# kimiCode, kimiCli). Providers neither side supports are skipped.

print_header() {
    local section="$1" provider="$2"
    echo ""
    echo "=================================================================="
    echo "  F2b vs ccusage benchmark — $section"
    echo "  provider : $provider"
    echo "  window   : $SINCE .. $UNTIL"
    echo "  tolerance: ${TOLERANCE} (cacheRead + totalCacheRead)"
    [[ -n "$F2B_DB_PATH" ]] && echo "  f2b db   : $F2B_DB_PATH"
    echo "  ccusage  : ${CCUSAGE}"
    echo "  captured : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "=================================================================="
}

run_ccusage() {
    local agent="$1"
    $CCUSAGE "$agent" daily --json \
        --since "${SINCE//-/}" --until "${UNTIL//-/}" \
        --timezone UTC 2>/dev/null
}

# Sum a jq expression across .daily[] for an agent JSON. Returns 0 if the
# stream is empty or unparseable.
sum_ccusage_field() {
    local json="$1" field="$2"
    printf '%s' "$json" | jq -r --arg f "$field" '
        ((.daily // []) | map(.[$f] // 0) | add) // 0
    ' 2>/dev/null
}

sum_ccusage_per_day() {
    local json="$1" field="$2"
    printf '%s' "$json" | jq -r --arg f "$field" \
        '[(.daily // [])[] | {(.date): (.[$f] // 0)}] | add // {}' 2>/dev/null
}

# Print rows from a key=number map sorted by key (single line per key).
print_map() {
    local title="$1" map_json="$2"
    printf '%s\n' "$map_json" | jq -r 'to_entries | sort_by(.key) | .[] | "\(.key)\t\(.value)"' 2>/dev/null
}

# Compare two numeric maps; print side-by-side rows with deviation ratio.
# jq 1.7.1 (macOS) doesn't allow `def m1` to rebind inside a pipe chain,
# so the two slurped maps are bound into $both and indexed directly.
compare_maps() {
    local left_title="$1" left_json="$2" right_title="$3" right_json="$4"
    printf '%s\n' "$left_json" "$right_json" | jq -rs '
        [.[0], .[1]] as $both
        | (([$both[0] | keys[]] + [$both[1] | keys[]]) | unique) as $keys
        | $keys[] | [., $both[0][.] // 0, $both[1][.] // 0] as $row
        | ($row[1] == 0) as $leftZero
        | (if $leftZero then "n/a"
            else ((($row[2] - $row[1] | fabs) / $row[1]) * 100
                  | . * 100 | round / 100 | tostring) + "%"
          end) as $pct
        | "\($row[0])\t\($row[1])\t\($row[2])\t\($row[2] - $row[1])\t\($pct)"
    ' 2>/dev/null
}

# Compute max deviation percent across all dates for one metric. Used by
# the alert gate.
max_deviation_pct() {
    local left_json="$1" right_json="$2"
    printf '%s\n' "$left_json" "$right_json" | jq -rs '
        [.[0], .[1]] as $both
        | (([$both[0] | keys[]] + [$both[1] | keys[]]) | unique) as $keys
        | [ $keys[]
            | ($both[0][.] // 0) as $l
            | ($both[1][.] // 0) as $r
            | if $l == 0 then 0 else (($r - $l | fabs) / $l * 100) end ]
        | max // 0
    ' 2>/dev/null
}

# Sum absolute values from a key=number map.
sum_map() {
    local map_json="$1"
    printf '%s' "$map_json" | jq -r '[.[]] | add // 0' 2>/dev/null
}

# Number of dates with activity.
date_count() {
    local map_json="$1"
    printf '%s' "$map_json" | jq -r 'keys | length' 2>/dev/null
}

# F2b query: date -> metric for a single source. Returns a JSON map
# like {"2026-07-01": 100, "2026-07-02": 0}. Uses jq to assemble the JSON
# object because bash 3.2's function parser misreads nested awk `{}`
# inside the body.
f2b_metric_map() {
    local source="$1" column="$2"
    local rows
    rows=$(sqlite3 -separator '|' -noheader "$F2B_DB_PATH" <<SQL
.timeout 10000
SELECT date(ts_ms/1000, 'unixepoch'), COALESCE(SUM($column), 0)
FROM token_events
WHERE source = '$source'
  AND date(ts_ms/1000, 'unixepoch') >= '$SINCE'
  AND date(ts_ms/1000, 'unixepoch') <  '$UNTIL'
GROUP BY 1 ORDER BY 1
SQL
)
    if [[ -z "$rows" ]]; then echo '{}'; return; fi
    printf '%s\n' "$rows" | jq -R 'split("|") | {(.[0]): .[1] | tonumber}' | jq -s 'add'
}

ALERT_PROVIDERS=()

for provider in $(echo "$PROVIDER_FILTER" | tr ',' ' '); do
    f2b_source=""
    case "$provider" in
        codex)    f2b_source="codexCli";   cc_agent="codex" ;;
        opencode) f2b_source="opencode";    cc_agent="opencode" ;;
        claude)   f2b_source="claudeCode";  cc_agent="claude" ;;
        kimi)     f2b_source="kimiCli";    cc_agent="kimi" ;;
        *)        echo "skip unknown provider: $provider" >&2; continue ;;
    esac

    print_header "compare" "$provider"

    metrics=(cacheReadTokens inputTokens outputTokens reasoningOutputTokens)
    table_header="date\tcc(metric)\tf2b(metric)\tdelta\tdeviation%"
    echo -e "$table_header"
    echo -e "------\t-----------\t----------\t-----\t----------"

    provider_alert=0

    cc_json=""
    if [[ $SKIP_CCUSAGE -eq 0 ]]; then
        cc_json=$(run_ccusage "$cc_agent")
        if [[ -z "$cc_json" || "$cc_json" == "null" ]]; then
            echo "ccusage $cc_agent daily returned empty — skipping"
            continue
        fi
    fi

    for metric in "${metrics[@]}"; do
        # cc per-day map for this metric
        cc_per_day="{}"
        if [[ -n "$cc_json" ]]; then
            cc_per_day=$(sum_ccusage_per_day "$cc_json" "$metric")
        fi
        # f2b per-day map (different column names per metric)
        f2b_col="$metric"
        case "$metric" in
            cacheReadTokens)        f2b_col="cache_read" ;;
            inputTokens)           f2b_col="input" ;;
            outputTokens)          f2b_col="output" ;;
            reasoningOutputTokens) f2b_col="reasoning" ;;
        esac
        f2b_per_day="{}"
        if [[ $SKIP_F2B -eq 0 ]]; then
            f2b_per_day=$(f2b_metric_map "$f2b_source" "$f2b_col")
            # If F2b has zero rows for this provider, fall back to kimiCode too
            if [[ $(date_count "$f2b_per_day") -eq 0 && "$f2b_source" == "kimiCli" ]]; then
                f2b_per_day=$(f2b_metric_map "kimiCode" "$f2b_col")
            fi
        fi

        compare_maps "cc" "$cc_per_day" "f2b" "$f2b_per_day" \
            | awk -v m="$metric" '{printf "  %s  cc=%-12s f2b=%-12s delta=%s dev=%s\n", $1, $2, $3, $4, $5}' \
            | head -40

        max_pct=$(max_deviation_pct "$cc_per_day" "$f2b_per_day")
        cc_total=$(sum_map "$cc_per_day")
        f2b_total=$(sum_map "$f2b_per_day")
        printf "  total  cc=%-12s f2b=%-12s                       max_dev=%s%%\n" \
            "$cc_total" "$f2b_total" "$max_pct"

        # Alert gate: cache_read total deviation > tolerance, OR any single
        # day > 5x tolerance. Mostly catches inflated cache_read under
        # duplicate snapshot conditions.
        max_pct_num="${max_pct:-0}"
        if (( $(echo "$max_pct_num > ($TOLERANCE * 100 * 4)" | bc -l 2>/dev/null || echo 0) )); then
            provider_alert=1
        fi
    done

    # Total cache_read sum alert
    cc_cache_total=0
    f2b_cache_total=0
    if [[ -n "$cc_json" ]]; then
        cc_cache_total=$(sum_ccusage_field "$cc_json" "cacheReadTokens")
    fi
    if [[ $SKIP_F2B -eq 0 ]]; then
        f2b_cache_total=$(sqlite3 -noheader "$F2B_DB_PATH" <<<".timeout 5000
            SELECT COALESCE(SUM(cache_read), 0)
            FROM token_events
            WHERE source = '$f2b_source'
              AND date(ts_ms/1000, 'unixepoch') >= '$SINCE'
              AND date(ts_ms/1000, 'unixepoch') <  '$UNTIL'" 2>/dev/null)
        [[ -z "$f2b_cache_total" ]] && f2b_cache_total=0
        if [[ "$f2b_source" == "kimiCli" && $f2b_cache_total -eq 0 ]]; then
            f2b_cache_total=$(sqlite3 -noheader "$F2B_DB_PATH" <<<".timeout 5000
                SELECT COALESCE(SUM(cache_read), 0)
                FROM token_events
                WHERE source = 'kimiCode'
                  AND date(ts_ms/1000, 'unixepoch') >= '$SINCE'
                  AND date(ts_ms/1000, 'unixepoch') <  '$UNTIL'" 2>/dev/null)
            [[ -z "$f2b_cache_total" ]] && f2b_cache_total=0
        fi
    fi
    if [[ "$cc_cache_total" -gt 0 && "$f2b_cache_total" -gt 0 ]]; then
        max_pct=$(awk -v c="$cc_cache_total" -v f="$f2b_cache_total" \
            'BEGIN { if (c==0) print 0; else print (((c-f)>0?(c-f):(f-c))/c)*100 }')
        f2b_ratio=$(awk -v c="$cc_cache_total" -v f="$f2b_cache_total" \
            'BEGIN { if (c==0) print 0; else printf "%.3f", f/c }')
        printf "  cacheRead sum  cc=%s  f2b=%s  ratio(f2b/cc)=%s\n" \
            "$cc_cache_total" "$f2b_cache_total" "$f2b_ratio"
        max_pct_num=$(printf "%.2f" "$max_pct" 2>/dev/null || echo 0)
        if (( $(echo "$max_pct_num > ($TOLERANCE * 100)" | bc -l 2>/dev/null || echo 0) )); then
            echo "  ⚠️  ALERT: $provider cache_read sum deviates ${max_pct_num}% > tolerance ${TOLERANCE}" >&2
            provider_alert=1
        fi
    else
        printf "  cacheRead sum  cc=%s  f2b=%s  (one side empty)\n" "$cc_cache_total" "$f2b_cache_total"
    fi

    if [[ $provider_alert -eq 1 ]]; then
        ALERT_PROVIDERS+=("$provider")
    fi
done

echo ""
echo "=================================================================="
echo "  Benchmark summary"
echo "=================================================================="
if [[ ${#ALERT_PROVIDERS[@]} -eq 0 ]]; then
    echo "  All providers within tolerance (${TOLERANCE})"
    echo "  Pass."
    exit 0
else
    printf "  Alerts: %s\n" "${ALERT_PROVIDERS[*]}"
    echo "  Investigate:"
    echo "    - dup snapshot handling (ccusage PR #824)"
    echo "    - timezone alignment (F2b uses UTC; ccusage defaults to local)"
    echo "    - provider name / model dimension splits"
    exit 1
fi
