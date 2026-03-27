# Airlock

**A declarative, framework-agnostic governance specification for AI agents.**

Airlock defines what an agent is *not allowed to do*, enforced at the execution boundary.

Other tools define what an agent is (personality, rules, duties) or what it does (tasks, loops). Nothing defines what an agent is **not allowed to do** at runtime, enforced deterministically. Airlock is that missing layer.

Think of it as an actual airlock: a boundary that separates the agent from the system, allowing controlled passage without contamination.

---

## The DARMA Framework

Airlock governance is structured in five layers:

| Layer | Purpose |
|---|---|
| **D**elegation | How many autonomous actions before human review. Escalation paths. |
| **A**uthorization | Protected paths, data classification, PII field definitions. |
| **R**untime | Fail mode (open/closed), hook scripts, tool restrictions. |
| **M**odel Integrity | Drift detection, baseline comparison intervals. |
| **A**ccountability | Immutable audit ledger, hash algorithm, tamper detection. |

Full framework description: [fluxai.dk/darma](https://fluxai.dk/darma)

---

## Quick Start

### 1. Add governance.yaml to your repo

```yaml
delegation:
  max_autonomous_actions: 10
  escalation:
    - channel: human_review
      trigger: threshold_reached

authorization:
  protected_paths:
    - .env
    - secrets/
  pii_fields:
    - email
    - name

runtime:
  fail_mode: closed
  hook_script: hooks/enforce.sh

model_integrity:
  drift_detection: true
  baseline_interval: 24h

accountability:
  audit_ledger: true
  hash_algorithm: sha256
  immutable: true
```

### 2. Validate

```bash
./validate-governance.sh
```

All five DARMA layers are checked. Required fields are enforced. Referenced hook scripts are verified to exist and be executable. `fail_mode: open` produces a warning.

### 3. Configure your agent to use the hook

The included `hooks/enforce.sh` is a PreToolUse hook. It reads `protected_paths` from `governance.yaml` and blocks tool calls that reference protected directories.

```bash
# Example: pipe a tool call through the hook
echo '{"tool_name":"Write","file_path":".env"}' | ./hooks/enforce.sh
# Output: AIRLOCK BLOCKED: Tool 'Write' references protected path '.env'
# Exit code: 2 (blocked)
```

---

## How It Complements Other Tools

GitAgent defines the agent. Airlock defines the boundaries.

| Tool | Defines |
|---|---|
| GitAgent | What the agent **is** (personality, rules, duties) |
| RALPH.md | What the agent **does** (tasks in a loop) |
| **Airlock** | What the agent **is not allowed to do** (enforced at runtime) |

Airlock without Agent Shield is a policy document. With Agent Shield, it is a firewall.

---

## Production Enforcement

`governance.yaml` defines the rules. `enforce.sh` demonstrates enforcement as a reference implementation.

For production use, [Agent Shield](https://github.com/FluxAI/agent-shield) provides:

- **Immutable audit trails** — tamper-proof logging of every governance decision
- **Drift detection** — continuous comparison against behavioral baselines
- **Multi-agent runtime scanning** — enforcement across agent fleets
- **Real-time monitoring** — live dashboards and alerting

Links:
- GitHub: [github.com/FluxAI/agent-shield](https://github.com/FluxAI/agent-shield)
- Product: [fluxai.dk/agent-shield](https://fluxai.dk/agent-shield)

---

## Files

```
airlock/
  governance.yaml        # The governance specification
  validate-governance.sh # Validator (bash, no dependencies)
  hooks/
    enforce.sh           # PreToolUse enforcement hook
  README.md
  LICENSE
```

---

## Commercial Use

Airlock is free to use, modify, and distribute under the terms of the BSL 1.1 + Commons Clause license.

**Selling Airlock as a product, embedding it in a commercial service, or offering hosted governance validation requires a commercial license.**

Contact: [info@fluxai.dk](mailto:info@fluxai.dk)

---

## License

Business Source License 1.1 + Commons Clause. See [LICENSE](LICENSE).

Changes to Apache 2.0 on 2030-03-27.
