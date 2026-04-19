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

## Scan IaC (Checkov)

```bash
docker run --rm -v "$(pwd):/tf" bridgecrew/checkov:3.2.57 \
  -d /tf --framework terraform --config-file /tf/.checkov.yaml
```

Pipeline CI chạy bước này tự động (job đầu tiên).
