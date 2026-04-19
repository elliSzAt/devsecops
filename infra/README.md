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

## Scan IaC (Trivy config)

Cùng image `aquasec/trivy` với bước container/dependency scan — **không cần API key**.

Từ thư mục gốc repo:

```bash
mkdir -p reports
docker run --rm \
  -v "$(pwd)/infra/terraform:/tf:ro" \
  -v "$(pwd)/reports:/output" \
  aquasec/trivy:0.58.0 \
  config \
  --format json \
  --output /output/iac-scan-report.json \
  --severity CRITICAL,HIGH \
  --exit-code 1 \
  /tf
```

Pipeline CI chạy bước này tự động (job `iac-scan` đầu tiên). Phát hiện misconfiguration Terraform mức **Critical/High** sẽ **fail** job.
