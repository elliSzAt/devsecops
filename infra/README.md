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
  aquasec/trivy:0.64.1 \
  config \
  --format json \
  --output /output/iac-scan-report.json \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  /tf
```

**Không** dùng `--skip-check-update` cho bước `config`: flag đó khiến Trivy cần cache sẵn trong image; container sạch sẽ lỗi nếu không có policy đã tải.

Pipeline CI chạy job `iac-scan` đầu tiên với cùng logic (volume Docker `trivy-iac-cache` trên self-hosted runner).
