# Technical Architecture Document: Airlock

**Version:** 2.0.0
**Dato:** 2026-03-27
**Forfatter:** Jesca Martaeng, FluxAI
**Repo:** https://github.com/Cherise1608/airlock

---

## 1. Formål

Airlock er en deklarativ, framework-agnostisk governance-specifikation for AI-agenter. Den definerer hvad en agent **ikke må gøre** ved runtime — håndhævet deterministisk ved eksekveringsgrænsen.

Airlock udfylder et hul i økosystemet:

| Værktøj | Definerer |
|---------|-----------|
| GitAgent | Hvad en agent **er** (personlighed, regler) |
| RALPH.md | Hvad en agent **gør** (opgaver i loop) |
| **Airlock** | Hvad en agent **ikke må** (governance-grænser) |

---

## 2. Arkitekturoverblik

```
┌─────────────────────────────────────┐
│           AI Agent Runtime          │
│                                     │
│   ┌───────────┐   ┌─────────────┐  │
│   │ Agent Core│──▶│ Tool Call    │  │
│   └───────────┘   └──────┬──────┘  │
│                          │         │
│                    ┌─────▼──────┐  │
│                    │  AIRLOCK   │  │
│                    │ enforce.sh │  │
│                    └─────┬──────┘  │
│                          │         │
│              ┌───────────▼───────┐ │
│              │ governance.yaml   │ │
│              │ (DARMA policy)    │ │
│              └───────────────────┘ │
│                          │         │
│              ┌───────────▼───────┐ │
│              │  exit 0 = allow   │ │
│              │  exit 2 = block   │ │
│              └───────────────────┘ │
└─────────────────────────────────────┘
```

---

## 3. DARMA-lagene

Governance.yaml er struktureret i fem lag:

### 3.1 Delegation
Styrer hvornår agenten skal eskalere til et menneske.

- `max_autonomous_actions`: Maks antal handlinger før human review
- `escalation`: Liste af eskaleringskanaler og triggers

### 3.2 Authorization
Definerer hvad agenten ikke har adgang til.

- `protected_paths`: Filer/mapper der er blokeret (f.eks. `.env`, `secrets/`)
- `data_classification`: Klassifikationsniveau (f.eks. `confidential`)
- `pii_fields`: Specifikke PII-felter der skal beskyttes

### 3.3 Runtime
Kontrollerer eksekveringsadfærd ved policy-brud.

- `fail_mode`: `closed` (blokér ved tvivl) eller `open` (tillad ved tvivl)
- `hook_script`: Sti til enforcement-hook (PreToolUse)
- `tool_restrictions`: Mønster-baserede blokeringer af farlige kommandoer

### 3.4 Model Integrity
Overvåger om agentens adfærd afviger over tid.

- `drift_detection`: Toggle for drift-overvågning
- `baseline_interval`: Hvor ofte baseline sammenlignes (f.eks. `24h`)

### 3.5 Accountability
Sikrer sporbarhed og revisionsmulighed.

- `audit_ledger`: Toggle for audit-log
- `hash_algorithm`: Hash til integritetsverifikation (f.eks. `sha256`)
- `immutable`: Om audit-loggen er uforanderlig

---

## 4. Filstruktur

```
airlock/
├── governance.yaml          # Policy-definition (DARMA)
├── validate-governance.sh   # Validator (bash, ingen deps)
├── airlock-report.sh        # Standalone compliance CLI
├── airlock-status.sh        # Standalone emergency status CLI
├── hooks/
│   └── enforce.sh           # PreToolUse runtime-hook
├── docs/
│   └── TAD.md               # Denne fil
├── LICENSE                  # BSL 1.1 + Commons Clause
└── README.md                # Dokumentation
```

| Fil | Formål |
|-----|--------|
| `governance.yaml` | Deklarativ policy (DARMA) |
| `validate-governance.sh` | Validering af alle DARMA-lag |
| `hooks/enforce.sh` | Runtime-blokering med path traversal-beskyttelse |
| `airlock-report.sh` | Compliance reporting: report, compliance, verify (standalone) |
| `airlock-status.sh` | Emergency status: escalation channel health checks (standalone) |
| `LICENSE` | BSL 1.1 + Commons Clause |
| `README.md` | Brugervejledning |

### Produktarkitektur

```
Airlock (spec + CLI)            → Gratis, standalone, ren bash
  governance.yaml                 Definer reglerne
  enforce.sh                      Håndhæv ved runtime
  airlock-report.sh               Compliance rapportering
  airlock-status.sh               Emergency kanal-check

Agent Shield (runtime)          → Kommerciel, binder det hele sammen
  Real-time scanning              Multi-agent overvågning
  Drift detection                 Adfærds-baselines
  Immutable audit trails          Tamper-proof ledger
```

Tre indgange til samme kunde. Alle gratis at prøve. Alle peger mod Agent Shield for produktion.

---

## 5. Dataflow

### 5.1 Validering (statisk)
```
$ ./validate-governance.sh
        │
        ▼
  Læs governance.yaml
        │
        ▼
  Check alle 5 DARMA-lag
        │
        ├── Fejl → exit 1
        └── OK   → exit 0
```

### 5.2 Runtime enforcement (dynamisk)
```
Agent vil kalde tool
        │
        ▼
  PreToolUse hook → hooks/enforce.sh
        │
        ▼
  Læs protected_paths fra governance.yaml
        │
        ▼
  Ekstraher path-referencer fra tool call
  (file_path, path, file felter + path-tokens fra command)
        │
        ▼
  Normaliser BEGGE sider med realpath -m
  (resolver ../../, ./, symlinks — kræver ikke at filen eksisterer)
        │
        ▼
  Prefix-match: starter normalized path med protected path?
  (med /-guard mod false positives: /secrets-public ≠ /secrets)
        │
        ├── Match  → exit 2 (BLOKERET)
        └── Ingen  → exit 0 (TILLADT)
```

---

## 6. Designprincipper

| Princip | Implementering |
|---------|---------------|
| **Fail closed** | Default fail_mode blokerer ved tvivl |
| **Zero dependencies** | Ren bash + YAML, ingen npm/pip/build |
| **Deklarativ** | Policy i YAML, ikke i kode |
| **Framework-agnostisk** | Virker med enhver agent der støtter hooks |
| **Læsbar på 5 min** | 5 filer, simpel struktur |

---

## 7. Sikkerhedsmodel

- **Protected paths** forhindrer adgang til `.env`, `secrets/`, og andre sensitive stier
- **Path traversal-beskyttelse** via `realpath -m` normalisering — blokerer `../../.env`, `foo/../../../secrets/key`, og lignende omgåelsesforsøg
- **Prefix-match med `/`-guard** forhindrer false positives (f.eks. `/secrets-public` matcher ikke `/secrets`)
- **PII-felter** er eksplicit defineret for compliance-synlighed
- **Immutable audit ledger** sikrer at loggen ikke kan ændres retroaktivt
- **Drift detection** fanger adfærdsændringer over tid
- **Hook-baseret enforcement** kører deterministisk — ikke probabilistisk

### 7.1 Path Traversal Prevention

Enforce.sh bruger `realpath -m` til at normalisere stier før sammenligning:

```
Angreb                              → Normaliseret            → Resultat
../../.env                          → /abs/path/.env          → BLOKERET
foo/../../../secrets/key            → /abs/path/secrets/key   → BLOKERET
./secrets/../.env                   → /abs/path/.env          → BLOKERET
/secrets-public/readme.md           → /secrets-public/...     → TILLADT (/-guard)
```

Normalisering sker på begge sider (requested path OG protected path) for konsistens. `-m` flaget sikrer at stier til ikke-eksisterende filer stadig kan resolves — vigtigt for write-operationer hvor agenten forsøger at oprette nye filer i beskyttede mapper.

---

## 8. Skaleringssti

Airlock er en specifikation, ikke et produkt. Skaleringsstien:

```
governance.yaml (spec)
       │
       ▼
enforce.sh (reference-implementation)
       │
       ▼
Agent Shield (production-grade enforcement)
  - Immutable audit trails
  - Drift detection
  - Multi-agent runtime scanning
  - https://github.com/FluxAI/agent-shield
  - https://fluxai.dk/agent-shield
```

---

## 9. Licens

- **Open source** til brug, modifikation og distribution
- **Commons Clause** forhindrer videresalg som produkt
- **BSL 1.1** konverterer til Apache 2.0 den 2030-03-27
- Kommerciel licens: info@fluxai.dk

---

## 10. Relaterede ressourcer

- DARMA framework: https://fluxai.dk/darma
- Agent Shield: https://fluxai.dk/agent-shield
- Repo: https://github.com/Cherise1608/airlock
