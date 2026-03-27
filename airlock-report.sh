#!/usr/bin/env bash
# ============================================================
# Airlock Compliance Report CLI
# ============================================================
# Standalone governance reporting tool. Reads governance-report.json
# (the audit ledger) and outputs summaries, compliance mappings,
# and chain integrity verification.
#
# No dependencies. No Python. No npm. Pure bash.
#
# For production-grade runtime enforcement with drift detection,
# real-time monitoring, and multi-agent scanning, see Agent Shield:
# https://github.com/FluxAI/agent-shield
# ============================================================

set -uo pipefail

VERSION="1.0.0"
LEDGER="${AIRLOCK_LEDGER:-governance-report.json}"

# ── Colors ──────────────────────────────────────────────────

red()    { printf '\033[0;31m%s\033[0m' "$1"; }
green()  { printf '\033[0;32m%s\033[0m' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m' "$1"; }
bold()   { printf '\033[1m%s\033[0m' "$1"; }

# ── JSON helpers (no jq required) ───────────────────────────

# Count occurrences of a pattern in the ledger
_count() {
    grep -c "$1" "$LEDGER" 2>/dev/null || echo "0"
}

# Extract all values for a given key
_extract_values() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$LEDGER" 2>/dev/null | \
        sed 's/.*: *"//' | sed 's/"$//'
}

# Extract all boolean values for a given key
_extract_bools() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[a-z]*" "$LEDGER" 2>/dev/null | \
        sed 's/.*: *//'
}

# Extract all numeric values for a given key
_extract_numbers() {
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9.]*" "$LEDGER" 2>/dev/null | \
        sed 's/.*: *//'
}

# Count entries (each entry has exactly one timestamp)
_entry_count() {
    _count '"timestamp"'
}

# ── Commands ────────────────────────────────────────────────

cmd_report() {
    local last_hours=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --last) last_hours="$2"; shift 2 ;;
            --ledger) LEDGER="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$LEDGER" ]]; then
        echo "airlock report"
        echo "===================================================="
        echo "  Ledger: $LEDGER (not found)"
        echo "  Governance status: $(red 'UNMONITORED')"
        echo "===================================================="
        return 0
    fi

    local total blocked allowed drift_events escalations

    total=$(_entry_count)
    blocked=$(_count '"result"[[:space:]]*:[[:space:]]*"BLOCKED"')
    allowed=$(_count '"result"[[:space:]]*:[[:space:]]*"ALLOWED"')
    escalations=$(_count '"escalation"[[:space:]]*:[[:space:]]*true')

    # Count drift events (drift_score > 0.3)
    drift_events=0
    while IFS= read -r score; do
        [[ -z "$score" ]] && continue
        # Compare as string: anything starting with 0.0, 0.1, 0.2, 0.3 is not drift
        case "$score" in
            0|0.0|0.0*) ;;
            0.1*|0.2*|0.3) ;;
            *) ((drift_events++)) ;;
        esac
    done <<< "$(_extract_numbers 'drift_score')"

    # Determine governance status
    local status
    if [[ "$total" -eq 0 ]]; then
        status="UNMONITORED"
    else
        # Check for unescalated drift
        local has_unescalated_drift=false
        if [[ "$drift_events" -gt 0 ]]; then
            # Simple heuristic: if drift events > escalations, some are unescalated
            if [[ "$drift_events" -gt "$escalations" ]]; then
                has_unescalated_drift=true
            fi
        fi

        if [[ "$has_unescalated_drift" == "true" ]]; then
            status="DEGRADED"
        else
            status="ENFORCED"
        fi
    fi

    local status_detail
    case "$status" in
        ENFORCED)    status_detail="$(green 'ENFORCED') — governance active and blocking violations" ;;
        DEGRADED)    status_detail="$(yellow 'DEGRADED') — drift detected without escalation" ;;
        UNMONITORED) status_detail="$(red 'UNMONITORED') — no governance entries found" ;;
    esac

    echo "airlock report"
    echo "===================================================="
    echo "  Ledger:                    $LEDGER"
    echo "  Total actions evaluated:   $total"
    echo "  Actions blocked:           $blocked"
    echo "  Actions allowed:           $allowed"
    echo "  Drift events (>0.3):       $drift_events"
    echo "  Escalations triggered:     $escalations"
    echo "===================================================="
    echo -e "  Governance status:         $status_detail"
}

cmd_compliance() {
    local framework=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --framework) framework="$2"; shift 2 ;;
            --ledger) LEDGER="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -z "$framework" ]]; then
        echo "Usage: airlock-report.sh compliance --framework <eu-ai-act|gdpr>"
        return 1
    fi

    if [[ ! -f "$LEDGER" ]]; then
        echo "airlock compliance  |  $framework"
        echo "===================================================="
        echo "  Ledger not found: $LEDGER"
        echo "===================================================="
        return 0
    fi

    local total
    total=$(_entry_count)

    case "$framework" in
        eu-ai-act)
            # Art. 12: entries with audit trail (eu_ai_act_article_12: true)
            local art12_count art12_pct
            art12_count=$(_count '"eu_ai_act_article_12"[[:space:]]*:[[:space:]]*true')
            if [[ "$total" -gt 0 ]]; then
                art12_pct=$(( (art12_count * 1000 / total + 5) / 10 ))
            else
                art12_pct=0
            fi

            # Art. 14: check if all entries have human oversight
            local art14_count art14_compliant
            art14_count=$(_count '"eu_ai_act_article_14"[[:space:]]*:[[:space:]]*true')
            if [[ "$art14_count" -eq "$total" ]] && [[ "$total" -gt 0 ]]; then
                art14_compliant="Yes"
            else
                art14_compliant="NO"
            fi

            local escalations
            escalations=$(_count '"escalation"[[:space:]]*:[[:space:]]*true')

            echo "airlock compliance  |  EU AI Act"
            echo "===================================================="
            echo "  Entries evaluated:   $total"
            echo "  Art. 12 coverage:    ${art12_pct}% ($art12_count/$total actions with audit trail)"
            echo "  Art. 14 compliant:   $art14_compliant ($escalations escalations triggered)"
            echo "===================================================="
            ;;

        gdpr)
            # Art. 22: automated decisions without human review
            local art22_flags
            art22_flags=$(_count '"gdpr_article_22"[[:space:]]*:[[:space:]]*true')

            # Art. 35: DPIA-relevant actions
            local art35_flags
            art35_flags=$(_count '"gdpr_article_35"[[:space:]]*:[[:space:]]*true')

            echo "airlock compliance  |  GDPR"
            echo "===================================================="
            echo "  Entries evaluated:   $total"
            echo "  Art. 22 flags:       $art22_flags (automated decisions without human review)"
            echo "  Art. 35 flags:       $art35_flags (actions touching PII-classified data)"
            echo "===================================================="
            ;;

        *)
            echo "Unknown framework: $framework"
            echo "Available: eu-ai-act, gdpr"
            return 1
            ;;
    esac
}

cmd_verify() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ledger) LEDGER="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ ! -f "$LEDGER" ]]; then
        echo "Chain verification: $(yellow 'SKIP')"
        echo "  Ledger not found: $LEDGER"
        return 0
    fi

    local total
    total=$(_entry_count)

    if [[ "$total" -eq 0 ]]; then
        echo "Chain verification: $(green 'PASS')"
        echo "  Empty ledger."
        return 0
    fi

    # Verify that entry_hash fields exist and are sequential
    local hashes prev_hash current_hash i=0 valid=true
    while IFS= read -r hash; do
        [[ -z "$hash" ]] && continue
        if [[ ${#hash} -ne 64 ]]; then
            valid=false
            echo "Chain verification: $(red 'FAIL')"
            echo "  Invalid hash length at entry $i: ${hash:0:16}..."
            return 1
        fi
        ((i++))
    done <<< "$(_extract_values 'entry_hash')"

    # Check previous_hash chain: each entry's previous_hash should match prior entry_hash
    local entry_hashes=() prev_hashes=()
    while IFS= read -r h; do
        [[ -n "$h" ]] && entry_hashes+=("$h")
    done <<< "$(_extract_values 'entry_hash')"

    while IFS= read -r h; do
        [[ -n "$h" ]] && prev_hashes+=("$h")
    done <<< "$(_extract_values 'previous_hash')"

    for ((j=1; j<${#entry_hashes[@]}; j++)); do
        if [[ "${prev_hashes[$j]}" != "${entry_hashes[$((j-1))]}" ]]; then
            echo "Chain verification: $(red 'FAIL')"
            echo "  Chain broken at entry $j"
            echo "  Expected previous_hash: ${entry_hashes[$((j-1))]:0:16}..."
            echo "  Got:                    ${prev_hashes[$j]:0:16}..."
            return 1
        fi
    done

    echo "Chain verification: $(green 'PASS')"
    echo "  Chain intact. $total entries verified."
    return 0
}

# ── Usage ───────────────────────────────────────────────────

cmd_help() {
    cat << 'EOF'
Airlock Compliance Report CLI

Usage:
  airlock-report.sh <command> [options]

Commands:
  report                  Show governance summary from audit ledger
  compliance              Show compliance status for a regulatory framework
  verify                  Verify hash chain integrity of the audit ledger
  version                 Show version

Options:
  --ledger <path>         Path to governance-report.json (default: ./governance-report.json)
  --framework <name>      Regulatory framework: eu-ai-act, gdpr
  --last <duration>       Filter to last N hours/days (e.g. 24h, 7d)

Examples:
  airlock-report.sh report
  airlock-report.sh report --last 24h
  airlock-report.sh compliance --framework eu-ai-act
  airlock-report.sh compliance --framework gdpr
  airlock-report.sh verify

Environment:
  AIRLOCK_LEDGER          Override default ledger path

Standalone tool. No dependencies. Works without Agent Shield.
For production-grade enforcement: https://fluxai.dk/agent-shield
EOF
}

# ── Main ────────────────────────────────────────────────────

case "${1:-help}" in
    report)     shift; cmd_report "$@" ;;
    compliance) shift; cmd_compliance "$@" ;;
    verify)     shift; cmd_verify "$@" ;;
    version)    echo "airlock-report $VERSION" ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1"
        echo "Run 'airlock-report.sh help' for usage."
        exit 1
        ;;
esac
