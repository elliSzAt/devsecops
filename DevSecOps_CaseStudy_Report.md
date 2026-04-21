# DevSecOps Case Study Report

**Repo:** demo webapp (Node.js/Express) + CI/CD pipeline GitHub Actions self-hosted runner
**Scope:** tài liệu này dùng để chấm điểm; giải thích cách chạy, thiết kế, tư duy bảo mật, hạn chế.

---

## 1) Tổng quan hệ thống

Kiến trúc đơn giản gồm 3 lớp:

- **App**: Node.js/Express (`app/`), expose REST API, UI EJS, SQLite (chạy local), được đóng gói Docker.
- **Pipeline CI/CD**: GitHub Actions (`.github/workflows/devsecops.yml`) chạy trên **self-hosted runner**, thực thi toàn bộ các bước từ IaC → SAST → Build/Test → SCA → Image build → Image scan → Push → Deploy → DAST → Rollback.
- **Infra (demo)**: Terraform tối thiểu cho AWS trong `infra/terraform/` (VPC, subnet public, SG, S3 SSE-KMS) — dùng để minh họa IaC scan, không thực sự áp dụng production.

Mục tiêu: minh họa một pipeline **fail-fast theo severity**, áp dụng security controls ở mỗi stage, báo cáo qua artifacts + dashboard.

---

## 2) Cách chạy

### 2.1 Yêu cầu

- Self-hosted runner đã cài **Docker Engine + compose v2**, có `bash`, `curl`, `python3`.
- Repo có Settings:
  - GitHub Actions enabled
  - (Nếu muốn push image) `packages: write` đã được khai báo trong workflow (đã có).

### 2.2 Chạy tự động qua GitHub

Pipeline chạy tự động khi:

- `push` vào `main` / `develop`
- `pull_request` nhắm vào `main`

Không cần chạy tay. Mỗi lần chạy tạo artifacts cho từng scan trong tab **Actions → Artifacts**.

### 2.3 Chạy local để debug/demo

Chạy toàn bộ scan local bằng Docker Compose (không cần GitHub):

```bash
docker compose -f docker-compose.security.yml up --abort-on-container-exit pipeline-runner
# Hoặc chỉ 1 stage:
docker compose -f docker-compose.security.yml up --abort-on-container-exit trivy-iac-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit gitleaks-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit semgrep-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit dependency-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit trivy-scan
docker compose -f docker-compose.security.yml up --abort-on-container-exit zap-scan
```

### 2.4 Pre-commit (secrets + format cơ bản)

File `.pre-commit-config.yaml` gồm **Gitleaks** + hook chung (trailing whitespace, YAML, JSON). Cài:

```bash
pip install pre-commit
pre-commit install
pre-commit run --all-files
```

### 2.5 Kết quả & artifacts

Artifacts upload theo mỗi job:

- IaC: `iac-scan-report.json`
- SAST: `gitleaks-report.json`, `sast-report.json`
- SCA: `dependency-scan-report.json`
- Container: `container-scan-report.json`
- DAST: `dast-report.json`, `dast-report.html`

---

## 3) Thiết kế pipeline chi tiết

### 3.1 Sơ đồ stage (đúng `devsecops.yml`)

```
iac-scan  ─► sast  ─► build-and-test  ─► build-image  ─► scan-image ─► push-image ─► deploy ─► dast
                                                                                           │
                                                                                           └─► rollback (nếu dast fail)
```

Mỗi stage là 1 **job riêng**, ràng buộc bằng `needs:`, đảm bảo:

- **Fail-fast**: stage sau chỉ chạy khi stage trước pass → tiết kiệm thời gian khi có lỗi nghiêm trọng.
- **Artifact tách biệt**: dev chỉ cần mở artifact tương ứng để đọc finding.
- **Phân vùng trách nhiệm**: mỗi job có 1 mục đích rõ ràng, dễ bảo trì.

### 3.2 Vì sao sắp đặt theo thứ tự này?

| Stage | Lý do đặt tại vị trí này |
|------:|--------------------------|
| **IaC** | Trivy config scan Terraform nhanh (~giây) và không cần build → đặt đầu giúp fail sớm nếu infra-as-code sai chính sách. |
| **SAST** | Chỉ phụ thuộc source code → không cần npm install. Chạy Gitleaks (secrets) trước, Semgrep (patterns) sau. |
| **Build & Test + SCA** | Cần `node_modules` đã cài để Trivy fs phân tích dependency. Kết hợp build/test + SCA để tận dụng cache npm. |
| **Build image** | Chỉ build khi code, test, SCA đều ổn. |
| **Container scan** | Scan image sau khi build → bắt CVE OS/deps lẫn phần app đã “cứng hóa”. |
| **Push image** | Chỉ push khi scan image đạt chính sách. Tránh đẩy image vulnerable lên registry. |
| **Deploy** | Chạy `pipeline/scripts/deploy.sh` trên runner tự host; trước deploy lưu lại image cũ để có thể rollback. |
| **DAST** | Chạy OWASP ZAP baseline lên app đang chạy; fail nếu có **High** risk → trigger rollback. |
| **Rollback** | Chỉ chạy khi `dast.result == 'failure'`; kéo lại image trước đó, redeploy. |

### 3.3 Quy tắc fail/severity theo stage

Tất cả thresholds đều cấu hình trong workflow:

| Stage | Tool | Điều kiện fail |
|------:|------|----------------|
| IaC | Trivy `config` | bất kỳ finding **CRITICAL/HIGH** (sau `trivy.yaml` + `.trivyignore`) |
| Secrets | Gitleaks | tìm thấy secret → exit 1 |
| SAST | Semgrep | ≥ 1 finding **severity = ERROR** (rule custom + `p/ci`) |
| SCA | Trivy `fs` | bất kỳ finding **CRITICAL/HIGH** (sau `.trivyignore`) |
| Container | Trivy `image` | CRITICAL/HIGH, có `--ignore-unfixed`, `--scanners vuln`, sau `.trivyignore` |
| DAST | ZAP baseline | ≥ 1 alert **High** |

Tất cả scanner được **pin version cụ thể** qua ENV trong workflow:

```
GITLEAKS_VERSION: v8.18.2
SEMGREP_VERSION: 1.90.0
TRIVY_VERSION: 0.62.1      # fs + image
TRIVY_IAC_VERSION: 0.70.0  # config
ZAP_VERSION: 2.16.0
```

### 3.4 Ignore/waiver policies (tại sao lại tồn tại)

- **`.trivyignore` ở root** (CVE/GHSA + AVD IaC) là **file duy nhất** mang “exception” cho cả vuln lẫn IaC → dễ review, dễ audit, tránh bị rải khắp repo.
- **`security/semgrep/.semgrep.yml`**: rule custom, merge cùng rule pack `p/ci` để có cả **domain-specific** (app này) và **generic security**.

### 3.5 Báo cáo & dashboard

- Artifacts tải về xem trực tiếp từ GitHub Actions.
- `dashboard/index.html` là dashboard tĩnh minh họa (không phải production).
- Với production thực tế, nên **chuyển report** vào hệ thống quản trị vuln (DefectDojo/Dependency-Track) để theo dõi MTTR, exception, SLA.

---

## 4) Tư duy bảo mật (Security thinking)

Phần này trình bày vì sao từng control được chọn, không phải chỉ liệt kê công cụ.

### 4.1 “Shift-left” có chọn lọc, không dồn toàn bộ vào dev

- **Pre-commit (Gitleaks + hooks)**: bắt secret ngay trên máy dev trước khi đẩy lên remote. Lý do: secret là rủi ro **không thể rollback** sau khi đã lộ — phải chặn càng sớm càng tốt.
- **SAST + SCA chạy sớm trong CI**: đẩy feedback “trong phút” cho PR. Không delegate cho CLI chạy tay vì hành vi không ổn định.
- **IaC scan trước mọi thứ khác**: sai infra khiến app dù secure cũng “trần” ra internet. Đặt đầu để fail rẻ nhất.

### 4.2 Defense-in-depth theo từng loại vuln

Mỗi loại vuln nên được **nhiều layer** kiểm tra — không tin 1 tool đơn lẻ:

- **Code vuln (SQLi, SSRF, CMDi, XSS…)**: SAST (Semgrep custom + `p/ci`) **+** DAST (ZAP).
- **Dependency vuln**: SCA (Trivy fs) **+** container scan (Trivy image) — vì image có thể kéo theo lib khác từ base image/runtime.
- **Container/OS vuln**: Trivy image + policy `--ignore-unfixed` để tránh noise khi chưa có bản vá.
- **IaC misconfig**: Trivy config cho Terraform; `trivy.yaml` cấu hình severity, `.trivyignore` cho exception có chủ đích.
- **Secrets**: Gitleaks ở pre-commit **và** CI.
- **Runtime**: ZAP baseline trước khi vào prod; rollback tự động nếu High.

### 4.3 Fail-fast + rollback: giảm thiệt hại khi dính lỗi

- Pipeline **fail-fast** tại stage rẻ nhất (IaC → Secrets → SAST) trước khi chạy build/test tốn tài nguyên.
- **DAST fail → rollback ngay** về image trước đó: ưu tiên keep-the-app-up và tránh rơi vào trạng thái deploy dở.
- **Health check** sau deploy: nếu app không trả `/` trong 60s → fail, tránh cho DAST chạy trên app hỏng.

### 4.4 Supply chain: không tin “latest”

- **Scanner images pin version cụ thể** (Gitleaks v8.18.2, Semgrep 1.90.0, Trivy 0.62.1/0.70.0, ZAP 2.16.0). `latest` dễ bị tag hijack.
- Khuyến nghị nâng cấp kế tiếp: **pin theo digest** (`@sha256:...`) cho cả scanner image lẫn base image của app.
- **GitHub Actions** đang pin theo major tag (`@v4`); nên pin theo commit SHA trong môi trường enterprise.

### 4.5 Least privilege + separation

- Workflow khai báo `permissions:` cấp workflow; cấp thấp hơn là nhiều chỗ còn có thể siết (chỉ `packages: write` ở job `push-image`).
- **GHCR**: dùng `GITHUB_TOKEN` runtime thay vì tạo PAT cá nhân → token ngắn hạn, scoped vào job.
- **Self-hosted runner** chỉ cần network ra Docker Hub/GHCR + GitHub; không nên có quyền sang mạng production.

### 4.6 Threat model (tóm tắt) và mapping control

Xem chi tiết trong `threat-model/threat-model.md`. Tóm lược 3 mối đe doạ lớn của app và stage CI/CD bắt được:

| Threat | Layer | Control trong pipeline |
|-------|-------|--------------------------|
| JWT manipulation | App | Semgrep custom rule (jwt-no-expiry, hardcoded-secret), DAST (auth flow) |
| SQL injection | App | Semgrep custom rule `sql-injection-raw-query`, DAST payload test |
| SSRF / payment MITM | App + infra | Semgrep custom rule `ssrf-vulnerability`, IaC check (egress), DAST baseline |

---

## 5) Task 4 — Security of the pipeline

Rủi ro của chính pipeline và cách xử lý đã hoặc **nên** áp dụng.

### 5.1 Secrets leakage (ngay trong CI)

- **Rủi ro**: biến secret lộ qua log, artifact hoặc commit.
- **Đã làm**: Gitleaks pre-commit + CI; `.gitignore` loại `.env` rõ ràng; không có secret trong code.
- **Cần làm thêm**: enable **“Secret Scanning”** trên GitHub; mask biến qua `echo ::add-mask::`.

### 5.2 Compromised self-hosted runner

- **Rủi ro**: runner bị chiếm quyền → exfil secret, dùng để attack nội bộ.
- **Đã làm**: runner tách khỏi máy dev, dùng Docker isolation cho mỗi scan.
- **Cần làm thêm**:
  - Ephemeral runner (1 job = 1 VM, dọn sạch sau job)
  - Hạn chế outbound network chỉ tới GHCR/Docker Hub/GitHub
  - Patch OS định kỳ, monitor `/var/run/docker.sock`.

### 5.3 Malicious pipeline modification

- **Rủi ro**: PR đổi workflow để tắt scan / push image độc.
- **Đã làm**: pipeline runner self-hosted; review PR qua Git.
- **Cần làm thêm**:
  - Branch protection trên `main`, yêu cầu reviewer
  - **CODEOWNERS** cho `.github/workflows/**`, `infra/terraform/**`, `security/**`
  - Yêu cầu signed commits.

### 5.4 Over-permissioned service account

- **Đã làm**: `permissions: contents: read, packages: write` ở workflow-level; dùng `GITHUB_TOKEN` tự động.
- **Cần làm thêm**: tách `packages: write` xuống **job `push-image`**; các job scan chỉ cần `contents: read`.

### 5.5 Supply chain attack (tool/action/image)

- **Đã làm**: pin version scanner images; không dùng `latest`; pin `actions/*@v4`.
- **Cần làm thêm**:
  - Pin theo digest: `aquasec/trivy@sha256:...`
  - Dùng `dependabot` hoặc `renovate` để cập nhật digest.

---

## 6) Hạn chế đã biết

Trung thực về hạn chế cũng là một dạng tư duy bảo mật.

### 6.1 Hạn chế về **chính xác kết quả scan**

- **SAST custom rule (Semgrep)** có thể miss pattern không viết rõ ràng trong rule; nhiều rule “pseudo-pattern” cần test thêm trên codebase thật.
- **DAST baseline (ZAP)** chỉ làm spider + passive scan → bỏ sót injection sâu (cần active scan/context + auth → tốn thời gian).
- **Trivy image** có thể cho nhiều noise khi dùng base image lớn; `--ignore-unfixed` giảm noise nhưng có thể che lỗ hổng chưa vá quan trọng.

### 6.2 Hạn chế về **ignore/exception**

- `.trivyignore` gom cả CVE và AVD IaC → tiện quản lý, nhưng **không có expiry date** bắt buộc; exception dễ thành vĩnh viễn.
- `trivy.yaml` ở `infra/terraform` chỉ giới hạn severity; nhiều rule nhỏ chưa có comment “vì sao bỏ qua”.

### 6.3 Hạn chế về **self-hosted runner**

- Runner hiện là 1 máy duy nhất, không ephemeral.
- Cache Docker image, cache Trivy (`/root/.cache/trivy`), cache npm đều dùng volume trên runner → nếu runner bị chiếm, cache này là bề mặt tấn công.
- Quyền Docker socket = quyền root trên host → cần hạn chế ai có quyền sửa workflow.

### 6.4 Hạn chế về **registry/deploy**

- GHCR pull public, nhưng nếu repo private thì image cũng private → deploy target cần token riêng.
- Deploy đang là `docker compose` trên cùng host, không phải Kubernetes → thiếu các kiểm soát như NetworkPolicy, PodSecurityAdmission, RBAC thật sự.

### 6.5 Hạn chế về **báo cáo**

- Chỉ có artifact JSON; chưa push tới hệ thống quản trị vuln (DefectDojo/Dependency-Track).
- Không theo dõi MTTR / SLA theo thời gian.
- Dashboard là HTML tĩnh, demo only.

---

## 7) Lộ trình cải tiến đề xuất

Thứ tự ưu tiên theo tỉ lệ chi phí / lợi ích:

1. **Siết permissions theo job**, pin action theo commit SHA, pin scanner image theo digest.
2. **Branch protection + CODEOWNERS** cho `.github/workflows/**`.
3. **Ephemeral runner** + restrict outbound network.
4. Gửi artifacts vào **DefectDojo/Dependency-Track**, bật metric MTTR.
5. Mở rộng **DAST** sang active scan + context login (khi app thực sự có login).
6. Thêm **SBOM** (`trivy image ... --format cyclonedx`) và ký image (cosign/sigstore).
7. Viết **runbook** rollback và **tabletop drill** supply chain attack.

---

## 8) Tham chiếu file trong repo

- Pipeline: `.github/workflows/devsecops.yml`
- IaC: `infra/terraform/*.tf`, `infra/terraform/trivy.yaml`, `.trivyignore`
- SAST rule: `security/semgrep/.semgrep.yml`
- Dockerfiles: `app/Dockerfile`, `app/Dockerfile.secure` (tham khảo hardening)
- Local scan: `docker-compose.security.yml`
- Threat model: `threat-model/threat-model.md`
- Pre-commit: `.pre-commit-config.yaml`
- Deploy/rollback scripts: `pipeline/scripts/deploy.sh`, `pipeline/scripts/rollback.sh`
