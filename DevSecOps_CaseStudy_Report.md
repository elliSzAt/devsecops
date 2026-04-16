# DevSecOps Case Study Report

**Author:** DevSecOps Engineer  
**Date:** April 15, 2026  
**Repository:** [GitHub Link]

---

## 1. How to Run

### Prerequisites
- Docker & Docker Compose installed
- Git

### Quick Start
```bash
git clone <repo-url> && cd devsecops-case-study

# Option 1: Full pipeline (recommended)
docker compose up pipeline-runner --build

# Option 2: Using Makefile
make pipeline

# Option 3: Individual scans
make sast          # SAST only
make scan          # All scans in parallel
make policy        # Policy check only

# View dashboard
make dashboard     # → http://localhost:8080

# View app
make app           # → http://localhost:3000
```

### What Happens
1. **Build** → npm install + Docker image build
2. **Test** → Jest unit tests
3. **Security Scans** (parallel for speed):
   - SAST via Semgrep (custom + OWASP rules)
   - SCA via Trivy (dependency vulnerabilities)
   - Container scan via Trivy (OS + app vulns + misconfigs)
   - IaC scan via Trivy (Dockerfile + docker-compose)
4. **Policy Gate** → Aggregates all findings, applies pass/fail rules
5. **Deploy** → Only if policy passes (mock deployment)

**Reports** are output to `reports/` directory as JSON.

---

## 2. Pipeline Design

### Architecture
```
BUILD → TEST → [SAST | SCA | Container | IaC] → POLICY GATE → DEPLOY
                    (parallel scans)                  ↑
                                              security-policy.json
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Semgrep for SAST** | Fast (10-50x faster than SonarQube), runs without compilation, supports custom rules, SARIF output, free for CI |
| **Trivy for SCA/Container/IaC** | Single tool for 3 scan types → less complexity, fast scanning, comprehensive CVE database, JSON/SARIF output |
| **Parallel security scans** | Scans are independent → run simultaneously to minimize pipeline time (from ~2min sequential to ~30s parallel) |
| **SAST at Security stage (post-test)** | Code must compile and pass basic tests before security scan. Avoids wasting scan resources on broken code |
| **Policy as separate stage** | Decouples scan execution from pass/fail decision. Security team can update policy without modifying scan configs |

### What Blocks vs Warns

| Severity | Action | Rationale |
|----------|--------|-----------|
| CRITICAL | **BLOCK** | Actively exploitable, immediate risk. Zero tolerance. |
| HIGH (>3) | **BLOCK** | Too many high-risk issues indicates systemic problem |
| HIGH (1-3) | **WARN** | Allows merge with 7-day SLA. Balances security with velocity |
| MEDIUM | **WARN** | 30-day SLA. Tracked in backlog |
| LOW | **LOG** | Informational. Addressed opportunistically |

---

## 3. Security Analysis

### Task 1 – SAST Findings (Semgrep)
**12 findings**: 3 Critical, 4 High, 3 Medium, 2 Low

Top Critical findings:
1. **Hardcoded JWT secret** (CWE-798) → Use secrets manager
2. **SQL Injection** (CWE-89) → Parameterized queries
3. **Command Injection** (CWE-78) → Input validation + execFile()

Custom Semgrep rules in `security/semgrep/.semgrep.yml` target app-specific patterns beyond generic OWASP rules.

### Task 2 – SCA + Container + IaC

**SCA (Dependencies):** 8 vulnerable packages found  
- CRITICAL: lodash 4.17.20 (CVE-2021-23337), axios 0.21.1 (CVE-2020-28168)  
- Root cause: **Outdated dependencies** → Fix in `package.json`

**Container Scan:** 15 OS vulns + 5 misconfigurations  
- Root cause: Using `node:18` (full Debian) instead of Alpine  
- Fix: Use `Dockerfile.secure` (multi-stage, Alpine, non-root, HEALTHCHECK)

**IaC Scan:** 7 misconfigurations  
- Root cause: **Dockerfile misconfiguration** (root user, unpinned base, debug port)  
- Fix: In Dockerfile + docker-compose config

**Distinguishing vulnerability types:**

| Type | Example | Where to Fix |
|------|---------|-------------|
| Code vulnerability | SQL injection, XSS | Application source code |
| Dependency vulnerability | lodash CVE | package.json (upgrade) |
| Misconfiguration | Running as root | Dockerfile / docker-compose |

### Task 3 – Policy Enforcement

**Scenario:** Pipeline finds 1 Critical, 2 High, 2 Medium

**Policy decision:** BLOCKED (BLOCK-001 triggered: critical_count > 0)

**Exception process:**
1. Developer creates SEC-ticket in Jira with justification
2. Security Lead reviews risk and approves/denies
3. For Critical: requires Security Lead + Engineering Manager + CISO
4. Exception valid for max 30 days, must include remediation plan
5. Auto-expires → pipeline blocks again if not fixed

**Dashboard views:**
- **CISO/BOD:** KPIs (MTTR, fix rate, pipeline block rate, SLA compliance)
- **Dev Team:** Specific findings with file/line, remediation steps, SLA deadlines

**Process:**
- **Responsible:** Dev team that owns the code
- **SLA:** Critical=24h, High=7d, Medium=30d
- **Communication:** Jira ticket auto-created, Slack notification to team channel
- **Escalation:** Automated if SLA breached

### Task 4 – Security of the Pipeline

| Threat | Impact | Mitigation (Implemented) |
|--------|--------|--------------------------|
| Secrets leakage | CRITICAL | Semgrep detects hardcoded secrets; use CI masked variables |
| Compromised runner | CRITICAL | Ephemeral containers via docker-compose; network isolation |
| Malicious pipeline modification | HIGH | CODEOWNERS file; MR approval required for CI config |
| Supply chain attack | HIGH | SCA scans dependencies; recommendation to pin tool versions |
| Over-permissioned accounts | MEDIUM | Container scan checks USER directive; least-privilege approach |

Demo: `make pipeline-security` runs the audit and produces `reports/pipeline-security-report.json`.

### Task 5 – Threat Modeling (E-Commerce System)

**System:** Browser → API Gateway → Web App → DB + Payment Service

**3 Threats (STRIDE):**

1. **JWT Manipulation** (Spoofing) → Strong secrets + short expiry → SAST checks
2. **SQL Injection** (Tampering) → Parameterized queries → SAST + DAST checks  
3. **Payment SSRF/MITM** (Tampering) → URL allowlist + mTLS → SAST + IaC checks

Full DFD and mapping table in `threat-model/threat-model.md`.

**Key insight:** Every design control maps to at least one CI/CD security check, ensuring threats are caught automatically in the pipeline rather than relying on manual code review alone.

---

## 4. Limitations & Improvements

### Current Limitations
- Security tool reports fall back to pre-generated JSON if tools aren't available (documented in scripts)
- DAST scanning not included (would require running app + OWASP ZAP in pipeline)
- Dashboard is static HTML (production: Grafana + Prometheus metrics from pipeline)

### Future Improvements
- Add DAST stage with OWASP ZAP after deploy-staging
- Integrate with Defect Dojo for vulnerability management
- Add SBOM generation (CycloneDX/SPDX)
- Implement secret scanning with gitleaks as pre-commit hook
- Add compliance-as-code (OPA/Rego policies)
