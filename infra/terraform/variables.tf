variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "ap-southeast-1"
}

variable "project_name" {
  type        = string
  description = "Prefix for resource names"
  default     = "devsecops-webapp"
}

variable "environment" {
  type        = string
  description = "Deployment stage (e.g. staging, prod)"
  default     = "staging"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR for the VPC"
  default     = "10.0.0.0/16"
}
