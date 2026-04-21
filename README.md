# DevSecOps Pipeline - Case Study

Demo repo xây dựng **DevSecOps pipeline** theo mô hình: **IaC scan → SAST → Build/Test + SCA → Build image → Container scan → Push → Deploy → DAST → (DAST fail) Rollback**.

- **CI/CD chính**: GitHub Actions (`.github/workflows/devsecops.yml`) chạy trên **self-hosted runner**.
- **Chạy local để demo/test tools**: `docker-compose.security.yml` (scan) + `docker-compose.yml` (deploy app + dashboard).

## Quick Start

### Chạy app + dashboard local

```bash
docker compose up -d app dashboard --build
# App:       http://localhost:3000
# Dashboard: http://localhost:8080
```

### Chạy full security pipeline local (demo)

```bash
docker compose -f docker-compose.security.yml up --abort-on-container-exit pipeline-runner
```

### Chạy pipeline CI/CD (GitHub Actions)

Pipeline tự chạy khi `push` vào `main`/`develop` hoặc tạo `pull_request` vào `main`.

## Architecture

```
┌─────────┐  ┌────────┐  ┌──────────────┐  ┌──────────────────┐  ┌───────────┐  ┌────────┐  ┌──────────┐  ┌──────────┐
│ IaC     │→ │ SAST   │→ │ Build & Test │→ │ SCA (deps)       │→ │ Build IMG │→ │ Scan   │→ │ Push IMG │→ │ Deploy   │
│ Trivy   │  │ GL+SG  │  │ npm ci/jest  │  │ Trivy fs         │  │ Docker    │  │ Trivy  │  │ GHCR     │  │ Compose  │
└─────────┘  └────────┘  └──────────────┘  └──────────────────┘  └───────────┘  └────────┘  └──────────┘  └──────────┘
                                                                                                                      │
                                                                                                                      v
                                                                                                               ┌──────────┐
                                                                                                               │ DAST     │
                                                                                                               │ ZAP      │
                                                                                                               └──────────┘
                                                                                                                      │
                                                                                                                      │
                                                                                                                      v
                                                                                                               ┌──────────┐
                                                                                                               │ Rollback │
                                                                                                               └──────────┘
```

## Project Structure

```
├── .github/workflows/devsecops.yml     # GitHub Actions pipeline (self-hosted runner)
├── app/                               # Node.js/Express demo app
│   ├── src/
│   ├── tests/
│   ├── Dockerfile                     # Image build (Alpine base)
│   └── Dockerfile.secure              # Bản hardening tham khảo
├── infra/terraform/                   # IaC (Terraform AWS) + Trivy config
│   └── trivy.yaml
├── pipeline/scripts/                  # Helper scripts (scan/deploy/rollback)
├── security/semgrep/.semgrep.yml      # Custom Semgrep rules
├── docker-compose.yml                 # Deploy app + dashboard local
├── docker-compose.security.yml        # Run scanners local (demo)
├── .pre-commit-config.yaml            # Local secret scanning + basic checks
├── .trivyignore                       # Trivy ignore (CVE/GHSA + IaC misconfig IDs)
├── dashboard/                         # HTML dashboard (static)
├── threat-model/                      # Threat model notes
└── DevSecOps_CaseStudy_Report.md      # Report (tài liệu chấm điểm)
```

## Local Commands (Docker Compose)

```bash
# App + dashboard
docker compose up -d app dashboard --build

# Full security run (local demo)
docker compose -f docker-compose.security.yml up --abort-on-container-exit pipeline-runner

# Individual stages (local demo)
docker compose -f docker-compose.security.yml up --abort-on-container-exit trivy-iac-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit gitleaks-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit semgrep-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit dependency-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit trivy-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit zap-scan
```

## Security Tools

| Tool | Purpose | Where it runs |
|------|---------|---------------|
| **Gitleaks** | Secrets scanning | Pre-commit + CI job (SAST) |
| **Semgrep** | SAST (custom + `p/ci`) | CI job (SAST) |
| **Trivy fs** | SCA (dependencies) | CI job (Build/Test & Dependency Scan) |
| **Trivy image** | Container vuln scan | CI job (Container Scan) |
| **Trivy config** | IaC misconfiguration scan (Terraform) | CI job (IaC Scan) |
| **OWASP ZAP** | DAST baseline scan | CI job (DAST) |

## Reports

### GitHub Actions artifacts

Trong mỗi run của GitHub Actions, bạn có thể tải artifacts để xem findings chi tiết:

- `iac-scan-report.json`
- `gitleaks-report.json`
- `sast-report.json` (Semgrep)
- `dependency-scan-report.json` (Trivy fs)
- `container-scan-report.json` (Trivy image)
- `dast-report.json` + `dast-report.html` (ZAP)

### Local output

Khi chạy `docker-compose.security.yml`, output được ghi vào `./reports/` tương tự.
