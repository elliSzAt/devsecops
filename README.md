# DevSecOps Pipeline - Case Study

A complete DevSecOps pipeline demonstration featuring CI/CD security integration with SAST, SCA, container scanning, IaC scanning, and policy enforcement.

## Quick Start

```bash
# Run the full pipeline
docker compose up pipeline-runner --build

# Or use Makefile
make pipeline
```

## Architecture

```
┌─────────┐   ┌──────┐   ┌──────────────────────────────────┐   ┌────────┐   ┌────────┐
│  BUILD   │──▶│ TEST │──▶│  SECURITY (parallel)             │──▶│ POLICY │──▶│ DEPLOY │
│ npm ci   │   │ jest │   │  SAST │ SCA │ Container │ IaC    │   │  GATE  │   │ (mock) │
└─────────┘   └──────┘   └──────────────────────────────────┘   └────────┘   └────────┘
```

## Project Structure

```
├── app/                          # Vulnerable Node.js application
│   ├── src/                      # Application source code
│   ├── tests/                    # Unit tests
│   ├── Dockerfile                # Container (with intentional issues)
│   └── Dockerfile.secure         # Hardened container
├── pipeline/
│   ├── scripts/                  # Pipeline stage scripts
│   │   ├── run-pipeline.sh       # Full pipeline orchestrator
│   │   ├── sast-scan.sh          # Semgrep SAST
│   │   ├── sca-scan.sh           # Trivy SCA
│   │   ├── container-scan.sh     # Trivy container
│   │   ├── iac-scan.sh           # Trivy IaC
│   │   ├── policy-check.sh       # Policy enforcement
│   │   └── pipeline-security-check.sh  # Pipeline security audit
│   └── policies/
│       └── security-policy.json  # Security gate policy
├── security/
│   └── semgrep/.semgrep.yml      # Custom SAST rules
├── reports/                      # Scan output (generated)
├── dashboard/                    # Security dashboard (HTML)
├── threat-model/                 # DFD + threat analysis
├── .gitlab-ci.yml                # GitLab CI pipeline config
├── docker-compose.yml            # Orchestration
└── Makefile                      # Convenience commands
```

## Available Commands

| Command | Description |
|---------|-------------|
| `make pipeline` | Run full pipeline |
| `make sast` | SAST scan only |
| `make sca` | SCA scan only |
| `make container-scan` | Container scan only |
| `make iac-scan` | IaC scan only |
| `make scan` | All scans in parallel |
| `make policy` | Policy enforcement |
| `make dashboard` | Start dashboard at :8080 |
| `make app` | Start app at :3000 |
| `make pipeline-security` | Audit pipeline security |
| `make clean` | Clean up |

## Security Tools

| Tool | Purpose | Stage |
|------|---------|-------|
| **Semgrep** | SAST - Static code analysis | Security |
| **Trivy** | SCA, Container, IaC scanning | Security |
| **Custom Policy Engine** | Enforce pass/fail criteria | Policy Gate |

## Reports

After running the pipeline, reports are saved to `reports/`:
- `sast-report.json` - SAST findings
- `sca-report.json` - Dependency vulnerabilities
- `container-scan-report.json` - Container image issues
- `iac-scan-report.json` - Infrastructure misconfigs
- `policy-report.json` - Aggregated policy decision
