# Infrastructure (AWS + Terraform)

Terraform mô tả tối thiểu cho webapp:

- **VPC** + 2 public subnet + Internet Gateway + route table
- **Security group** cho tier web (HTTP/HTTPS chỉ từ CIDR VPC — hạn chế mở `0.0.0.0/0`)
- **S3 bucket** cho static assets: versioning, SSE-S3, block public access

## Cách dùng local

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform validate
terraform plan
```

Cần AWS credentials (`aws configure` hoặc biến môi trường).

## Scan IaC (Trivy config — phiên bản riêng)

Pipeline dùng **`TRIVY_IAC_VERSION`** (khác `TRIVY_VERSION` cho fs/image) và **volume cache** `trivy-iac-cache` để policy misconfig không phải tải lại mỗi lần.

Từ thư mục gốc repo:

```bash
mkdir -p reports
docker volume create devsecops-trivy-iac-cache 2>/dev/null || true
docker run --rm \
  -v devsecops-trivy-iac-cache:/root/.cache/trivy \
  -v "$(pwd)/infra/terraform:/tf:ro" \
  -v "$(pwd)/reports:/output" \
  -v "$(pwd)/.trivyignore:/root/.trivyignore:ro" \
  aquasec/trivy:0.70.0 \
  config \
  --config /tf/trivy.yaml \
  --ignorefile /root/.trivyignore \
  --skip-version-check \
  --format json \
  --output /output/iac-scan-report.json \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  /tf
```

- **`TRIVY_IAC_VERSION`** (workflow) dùng image **0.70.0** cho IaC, khác **`TRIVY_VERSION`** (fs/image).
- **`--exit-code 1`**: job fail nếu còn finding CRITICAL/HIGH sau khi áp dụng `trivy.yaml` + `.trivyignore`.
- **KMS + SSE-KMS** trên S3 xử lý AVD-AWS-0132; các ID demo trong `.trivyignore` cần rà lại trước production.

Pipeline CI chạy job `iac-scan` đầu tiên với cùng logic (volume Docker `trivy-iac-cache` trên self-hosted runner).
