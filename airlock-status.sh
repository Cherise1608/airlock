#!/usr/bin/env bash
# ============================================================
# Airlock Emergency Status CLI
# ============================================================
# Checks whether governance prerequisites are intact.
# If escalation channels are unreachable, agents are operating
# without human oversight — a direct EU AI Act Art. 14 violation.
#
# No dependencies. No Python. No npm. Pure bash.
#
# For production-grade runtime enforcement with drift detection,
# real-time monitoring, and multi-agent scanning, see Agent Shield:
# https://github.com/FluxAI/agent-shield
# ============================================================
#
# Exit codes:
#   0 = NOMINAL   — all oversight channels operational
#   1 = DEGRADED  — some channels down, oversight still possible
#   2 = EMERGENCY — all human oversight channels unreachable
# ============================================================

set -uo pipefail

VERSION="1.0.0"
GOVFILE="${AIRLOCK_GOVERNANCE:-governance.yaml}"
TIMEOUT=5

# ── Colors ──────────────────────────────────────────────────

red()    { printf '\033[0;31m%s\033[0m' "$1"; }
green()  { printf '\033[0;32m%s\033[0m' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m' "$1"; }

# ── Governance parser ───────────────────────────────────────

# Extract escalation channels from governance.yaml
# Returns lines in format: channel|trigger|endpoint
extract_channels() {
    local in_escalation=0
    local channel="" trigger="" endpoint=""

    while IFS= read -r line; do
        # Detect escalation section
        if [[ "$line" =~ ^[[:space:]]+escalation: ]]; then
            in_escalation=1
            continue
        fi

        # Exit if we hit a non-indented line or a new top-level section
        if [[ $in_escalation -eq 1 ]]; then
            # New list item
            if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
                # Flush previous channel
                if [[ -n "$channel" ]]; then
                    echo "${channel}|${trigger}|${endpoint}"
                fi
                channel=""
                trigger=""
                endpoint=""

                # Extract inline key
                local rest
                rest=$(echo "$line" | sed 's/^[[:space:]]*- *//')
                if [[ "$rest" =~ ^channel: ]]; then
                    channel=$(echo "$rest" | sed 's/^channel: *//')
                fi
            elif [[ "$line" =~ ^[[:space:]]+channel: ]]; then
                channel=$(echo "$line" | sed 's/^.*channel: *//')
            elif [[ "$line" =~ ^[[:space:]]+trigger: ]]; then
                trigger=$(echo "$line" | sed 's/^.*trigger: *//')
            elif [[ "$line" =~ ^[[:space:]]+endpoint: ]]; then
                endpoint=$(echo "$line" | sed 's/^.*endpoint: *//')
            elif [[ ! "$line" =~ ^[[:space:]] ]]; then
                # New top-level section — done
                break
            elif [[ "$line" =~ ^[[:space:]]{1,2}[a-z] ]] && [[ ! "$line" =~ ^[[:space:]]+- ]] && [[ ! "$line" =~ channel: ]] && [[ ! "$line" =~ trigger: ]] && [[ ! "$line" =~ endpoint: ]]; then
                # New second-level key — done with escalation
                break
            fi
        fi
    done < "$GOVFILE"

    # Flush last channel
    if [[ -n "$channel" ]]; then
        echo "${channel}|${trigger}|${endpoint}"
    fi
}

# Extract fail_mode from governance.yaml
get_fail_mode() {
    grep -E '^\s+fail_mode:' "$GOVFILE" 2>/dev/null | head -1 | sed 's/^.*fail_mode: *//'
}

# ── Health checks ───────────────────────────────────────────

check_http() {
    local url="$1"
    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" -I "$url" 2>/dev/null)
    if [[ "$http_code" =~ ^[23] ]]; then
        echo "UP|HTTP $http_code"
    else
        echo "DOWN|HTTP $http_code (unreachable)"
    fi
}

check_tcp() {
    local host="$1" port="$2"
    if timeout "$TIMEOUT" bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "UP|TCP $host:$port open"
    else
        echo "DOWN|TCP $host:$port closed"
    fi
}

check_process() {
    local name="$1"
    if pgrep -f "$name" >/dev/null 2>&1; then
        local pid
        pid=$(pgrep -f "$name" | head -1)
        echo "UP|Process '$name' running (PID: $pid)"
    else
        echo "DOWN|Process '$name' not found"
    fi
}

check_file() {
    local path="$1"
    if [[ -e "$path" ]]; then
        if [[ -S "$path" ]] || [[ -p "$path" ]]; then
            echo "UP|Socket/pipe exists: $path"
        elif [[ -w "$path" ]]; then
            echo "UP|File writable: $path"
        else
            echo "DOWN|File not writable: $path"
        fi
    else
        echo "DOWN|Path not found: $path"
    fi
}

check_endpoint() {
    local endpoint="$1"

    if [[ -z "$endpoint" ]]; then
        echo "DOWN|No endpoint configured"
        return
    fi

    case "$endpoint" in
        http://*|https://*)
            check_http "$endpoint"
            ;;
        tcp://*)
            local hostport="${endpoint#tcp://}"
            local host="${hostport%%:*}"
            local port="${hostport##*:}"
            [[ "$port" == "$host" ]] && port=443
            check_tcp "$host" "$port"
            ;;
        process://*)
            check_process "${endpoint#process://}"
            ;;
        file://*)
            check_file "${endpoint#file://}"
            ;;
        *)
            echo "DOWN|Unknown scheme: $endpoint"
            ;;
    esac
}

# ── Main ────────────────────────────────────────────────────

cmd_emergency() {
    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --governance) GOVFILE="$2"; shift 2 ;;
            --timeout) TIMEOUT="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")

    echo "airlock status --emergency"
    echo "========================================================"
    echo "  Timestamp:    $timestamp"
    echo "  Governance:   $GOVFILE"

    # Check governance file exists
    if [[ ! -f "$GOVFILE" ]]; then
        echo "  Fail mode:    unknown"
        echo ""
        echo "  $(red '[X]') governance.yaml not found"
        echo ""
        echo "  Assessment"
        echo "  ----------------------------------------"
        echo "  Human oversight available:  NO"
        echo "  Governance intact:          NO"
        echo -e "  Action: $(red 'HALT') — no governance.yaml found"
        echo ""
        echo "  Regulatory Impact"
        echo "  ----------------------------------------"
        echo "  EU AI Act Art. 9:  $(red 'VIOLATION') — no risk management system"
        echo "  EU AI Act Art. 14: $(red 'VIOLATION') — no human oversight mechanism"
        echo "========================================================"
        exit 2
    fi

    local fail_mode
    fail_mode=$(get_fail_mode)
    fail_mode="${fail_mode:-closed}"
    echo "  Fail mode:    $fail_mode"
    echo ""
    echo "  Escalation Channels"
    echo "  ----------------------------------------"

    local human_total=0 human_reachable=0
    local channels_output=""

    while IFS='|' read -r channel trigger endpoint; do
        [[ -z "$channel" ]] && continue

        # abort is a built-in action, always available
        if [[ "$channel" == "abort" ]]; then
            echo "  $(green '[+]') $(printf '%-20s' "$channel") $(green 'UP')"
            echo "      trigger:  $trigger"
            echo "      detail:   Built-in action, always available"
            continue
        fi

        ((human_total++))

        local check_result status detail icon
        check_result=$(check_endpoint "$endpoint")
        status="${check_result%%|*}"
        detail="${check_result#*|}"

        if [[ "$status" == "UP" ]]; then
            ((human_reachable++))
            icon="$(green '[+]')"
            echo "  $icon $(printf '%-20s' "$channel") $(green 'UP')"
        else
            icon="$(red '[X]')"
            echo "  $icon $(printf '%-20s' "$channel") $(red 'DOWN')"
        fi
        echo "      endpoint: ${endpoint:-(not configured)}"
        echo "      detail:   $detail"

    done <<< "$(extract_channels)"

    if [[ "$human_total" -eq 0 ]]; then
        echo "  (no human oversight channels configured)"
    fi

    echo ""
    echo "  Assessment"
    echo "  ----------------------------------------"

    local oversight_available governance_intact action
    local art9_status art14_status

    if [[ "$human_total" -eq 0 ]]; then
        oversight_available="NO"
        governance_intact="NO"
        action="$(red 'HALT') — no human oversight channels defined"
        art9_status="$(red 'VIOLATION') — no risk management system"
        art14_status="$(red 'VIOLATION') — no escalation path to human reviewer"
    elif [[ "$human_reachable" -eq 0 ]]; then
        oversight_available="NO"
        governance_intact="NO"
        action="$(red 'EMERGENCY') — all human oversight channels unreachable. Switch to fail-closed. Halt all autonomous agents until communication is restored."
        art9_status="$(red 'AT RISK') — governance prerequisites degraded"
        art14_status="$(red 'VIOLATION') — human oversight unreachable"
    elif [[ "$human_reachable" -lt "$human_total" ]]; then
        oversight_available="YES"
        governance_intact="NO"
        action="$(yellow 'DEGRADED') — $human_reachable/$human_total oversight channels reachable. Monitor closely. Reduce max_autonomous_actions."
        art9_status="$(yellow 'AT RISK') — governance prerequisites degraded"
        art14_status="$(yellow 'PARTIAL') — oversight available via $human_reachable/$human_total channels"
    else
        oversight_available="YES"
        governance_intact="YES"
        action="$(green 'NOMINAL') — all oversight channels operational"
        art9_status="$(green 'COMPLIANT')"
        art14_status="$(green 'COMPLIANT')"
    fi

    echo "  Human oversight available:  $oversight_available"
    echo "  Governance intact:          $governance_intact"
    echo -e "  Action: $action"

    echo ""
    echo "  Regulatory Impact"
    echo "  ----------------------------------------"
    echo -e "  EU AI Act Art. 9:  $art9_status"
    echo -e "  EU AI Act Art. 14: $art14_status"
    echo "========================================================"

    # Exit code
    if [[ "$governance_intact" == "YES" ]]; then
        exit 0
    elif [[ "$oversight_available" == "YES" ]]; then
        exit 1
    else
        exit 2
    fi
}

cmd_help() {
    cat << 'EOF'
Airlock Emergency Status CLI

Usage:
  airlock-status.sh [options]

Checks whether escalation channels defined in governance.yaml are
reachable. If human oversight is unavailable, agents are operating
in violation of EU AI Act Art. 14.

Options:
  --governance <path>     Path to governance.yaml (default: ./governance.yaml)
  --timeout <seconds>     Connection timeout per channel (default: 5)

Endpoint types supported in governance.yaml:
  https://...             HTTP/HTTPS endpoint (HEAD request)
  tcp://host:port         TCP socket connection
  process://name          Check if process is running (pgrep)
  file:///path            File/socket/pipe existence

Exit codes:
  0 = NOMINAL    — all oversight channels operational
  1 = DEGRADED   — some channels down, oversight still possible
  2 = EMERGENCY  — all human oversight channels unreachable

Environment:
  AIRLOCK_GOVERNANCE      Override default governance.yaml path

Examples:
  airlock-status.sh
  airlock-status.sh --governance /path/to/governance.yaml
  airlock-status.sh --timeout 10

Standalone tool. No dependencies. Works without Agent Shield.
For production-grade enforcement: https://fluxai.dk/agent-shield
EOF
}

case "${1:-}" in
    help|--help|-h) cmd_help ;;
    version|--version) echo "airlock-status $VERSION" ;;
    *) cmd_emergency "$@" ;;
esac
