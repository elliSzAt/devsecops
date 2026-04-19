output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

output "web_security_group_id" {
  description = "Security group for web tier"
  value       = aws_security_group.web.id
}

output "app_assets_bucket_name" {
  description = "S3 bucket for application static assets / artifacts"
  value       = aws_s3_bucket.app_assets.id
}
