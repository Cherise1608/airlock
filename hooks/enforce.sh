#!/usr/bin/env bash
# ============================================================
# Airlock Runtime Enforcement Hook (PreToolUse)
# ============================================================
# This is a reference implementation. For production-grade runtime
# enforcement with drift detection, audit logging, and multi-agent
# scanning, see Agent Shield: https://github.com/FluxAI/agent-shield
# ============================================================
#
# Exit codes:
#   0 = allow the tool call
#   2 = block the tool call
#
# This hook reads protected_paths from governance.yaml and blocks
# any tool call whose arguments reference a protected path.
# Works standalone with no external dependencies.
# ============================================================

set -uo pipefail

GOVFILE="${AIRLOCK_GOVERNANCE:-governance.yaml}"

# Find governance.yaml: check current dir, then walk up to repo root
find_governance() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$GOVFILE" ]]; then
            echo "$dir/$GOVFILE"
            return 0
        fi
        # Also check if GOVFILE is an absolute path
        if [[ -f "$GOVFILE" ]]; then
            echo "$GOVFILE"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

GOV_PATH=$(find_governance)
if [[ $? -ne 0 ]] || [[ -z "$GOV_PATH" ]]; then
    # No governance file found — check fail mode default
    echo "AIRLOCK: No governance.yaml found. Defaulting to fail-closed." >&2
    exit 2
fi

# Read fail_mode
FAIL_MODE=$(grep -E '^\s+fail_mode:' "$GOV_PATH" 2>/dev/null | head -1 | sed 's/^[^:]*: *//')
FAIL_MODE="${FAIL_MODE:-closed}"

# Extract protected paths from governance.yaml
# Reads lines under protected_paths: that start with "    - "
extract_protected_paths() {
    local in_section=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+protected_paths: ]]; then
            in_section=1
            continue
        fi
        if [[ $in_section -eq 1 ]]; then
            if [[ "$line" =~ ^[[:space:]]+- ]]; then
                # Extract the path value after "- "
                local path
                path=$(echo "$line" | sed 's/^[[:space:]]*- *//' | sed 's/[[:space:]]*$//')
                echo "$path"
            else
                # End of list
                break
            fi
        fi
    done < "$GOV_PATH"
}

# Read the tool call from stdin (JSON from the agent framework)
TOOL_INPUT=$(cat)

# Extract the tool name and file path from the input
# Supports common patterns: tool_name, file_path, path, command fields
TOOL_NAME=$(echo "$TOOL_INPUT" | grep -o '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')
FILE_PATH=$(echo "$TOOL_INPUT" | grep -oE '"(file_path|path|file)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')
COMMAND=$(echo "$TOOL_INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"//' | sed 's/"$//')

# Combine all references to check
REFERENCES="$FILE_PATH $COMMAND"

# Check each protected path against the tool call
while IFS= read -r protected; do
    [[ -z "$protected" ]] && continue

    for ref in $REFERENCES; do
        [[ -z "$ref" ]] && continue

        # Check if the reference contains the protected path
        if [[ "$ref" == *"$protected"* ]]; then
            echo "AIRLOCK BLOCKED: Tool '$TOOL_NAME' references protected path '$protected'" >&2
            echo "  Governance policy: $GOV_PATH" >&2
            echo "  To modify protected paths, update the authorization.protected_paths section." >&2
            exit 2
        fi
    done
done <<< "$(extract_protected_paths)"

# No violations found
exit 0
