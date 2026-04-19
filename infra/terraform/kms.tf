# Customer-managed key for S3 (AVD-AWS-0132 — SSE-KMS)
resource "aws_kms_key" "s3_app_assets" {
  description             = "${var.project_name} S3 app assets (${var.environment})"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_kms_alias" "s3_app_assets" {
  name          = "alias/${var.project_name}-s3-assets-${var.environment}"
  target_key_id = aws_kms_key.s3_app_assets.key_id
}
