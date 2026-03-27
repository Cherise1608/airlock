#!/usr/bin/env bash
# Airlock Governance Validator
# Validates governance.yaml against the DARMA specification.
# Exit 0 = valid, Exit 1 = invalid.
# No external dependencies. Pure bash + standard unix tools.

set -euo pipefail

GOVFILE="${1:-governance.yaml}"
ERRORS=0
WARNINGS=0

red()    { printf '\033[0;31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$1"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$1"; }

error()   { red   "  ERROR: $1"; ((ERRORS++)); }
warn()    { yellow "  WARN:  $1"; ((WARNINGS++)); }
ok()      { green  "  OK:    $1"; }

echo "Airlock Governance Validator"
echo "============================"
echo ""

# --- File existence ---
if [[ ! -f "$GOVFILE" ]]; then
    error "governance.yaml not found in current directory"
    exit 1
fi
ok "governance.yaml found"

# --- Helper: check that a YAML key exists (simple top-level or nested) ---
has_key() {
    grep -qE "^${1}:" "$GOVFILE" 2>/dev/null || grep -qE "^  ${1}:" "$GOVFILE" 2>/dev/null || grep -qE "^    ${1}:" "$GOVFILE" 2>/dev/null
}

get_value() {
    grep -E "^  ${1}:|^    ${1}:|^${1}:" "$GOVFILE" 2>/dev/null | head -1 | sed 's/^[^:]*: *//'
}

# ============================================================
# Layer 1: Delegation
# ============================================================
echo ""
echo "Layer 1: Delegation"
echo "--------------------"

if has_key "delegation"; then
    ok "delegation layer present"
else
    error "delegation layer missing"
fi

if has_key "max_autonomous_actions"; then
    val=$(get_value "max_autonomous_actions")
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        ok "max_autonomous_actions = $val"
    else
        error "max_autonomous_actions must be a positive integer (got: $val)"
    fi
else
    error "max_autonomous_actions not defined"
fi

if has_key "escalation"; then
    ok "escalation paths defined"
else
    error "escalation paths missing"
fi

# ============================================================
# Layer 2: Authorization
# ============================================================
echo ""
echo "Layer 2: Authorization"
echo "-----------------------"

if has_key "authorization"; then
    ok "authorization layer present"
else
    error "authorization layer missing"
fi

if has_key "protected_paths"; then
    ok "protected_paths defined"
else
    error "protected_paths not defined"
fi

if has_key "pii_fields"; then
    ok "pii_fields defined"
else
    warn "pii_fields not defined (recommended for data governance)"
fi

# ============================================================
# Layer 3: Runtime
# ============================================================
echo ""
echo "Layer 3: Runtime"
echo "------------------"

if has_key "runtime"; then
    ok "runtime layer present"
else
    error "runtime layer missing"
fi

if has_key "fail_mode"; then
    mode=$(get_value "fail_mode")
    if [[ "$mode" == "closed" ]]; then
        ok "fail_mode = closed (secure default)"
    elif [[ "$mode" == "open" ]]; then
        warn "fail_mode = open. In open mode, governance failures will NOT block execution. This is unsafe for production."
    else
        error "fail_mode must be 'open' or 'closed' (got: $mode)"
    fi
else
    error "fail_mode not defined"
fi

if has_key "hook_script"; then
    hook=$(get_value "hook_script")
    if [[ -f "$hook" ]]; then
        ok "hook_script found: $hook"
        if [[ -x "$hook" ]]; then
            ok "hook_script is executable"
        else
            error "hook_script exists but is not executable: $hook (run: chmod +x $hook)"
        fi
    else
        error "hook_script not found: $hook"
    fi
else
    warn "hook_script not defined (no runtime enforcement)"
fi

# ============================================================
# Layer 4: Model Integrity
# ============================================================
echo ""
echo "Layer 4: Model Integrity"
echo "-------------------------"

if has_key "model_integrity"; then
    ok "model_integrity layer present"
else
    error "model_integrity layer missing"
fi

if has_key "drift_detection"; then
    val=$(get_value "drift_detection")
    ok "drift_detection = $val"
else
    warn "drift_detection not defined"
fi

if has_key "baseline_interval"; then
    ok "baseline_interval = $(get_value 'baseline_interval')"
else
    warn "baseline_interval not defined (recommended when drift_detection is enabled)"
fi

# ============================================================
# Layer 5: Accountability
# ============================================================
echo ""
echo "Layer 5: Accountability"
echo "------------------------"

if has_key "accountability"; then
    ok "accountability layer present"
else
    error "accountability layer missing"
fi

if has_key "audit_ledger"; then
    val=$(get_value "audit_ledger")
    ok "audit_ledger = $val"
else
    error "audit_ledger not defined"
fi

if has_key "hash_algorithm"; then
    ok "hash_algorithm = $(get_value 'hash_algorithm')"
else
    warn "hash_algorithm not defined (recommended when audit_ledger is enabled)"
fi

if has_key "immutable"; then
    ok "immutable = $(get_value 'immutable')"
else
    warn "immutable flag not set on audit ledger"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================"
if [[ $ERRORS -gt 0 ]]; then
    red "FAILED: $ERRORS error(s), $WARNINGS warning(s)"
    exit 1
else
    if [[ $WARNINGS -gt 0 ]]; then
        yellow "PASSED with $WARNINGS warning(s)"
    else
        green "PASSED: All DARMA layers validated"
    fi
    exit 0
fi
