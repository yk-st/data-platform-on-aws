# Variables for Data Platform
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "data-platform"
}

variable "tenant_id" {
  description = "Tenant ID for multi-tenancy"
  type        = string
  default     = "tenant-001"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "data-platform"
    Environment = "dev"
    Owner       = "data_engineering"
    CostCenter  = "engineering"
    TenantId    = "tenant-001"
    ManagedBy   = "terraform"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
  # default     = ["ap-northeast-3a", "ap-northeast-3c"]
}

variable "bucket_naming_suffix" {
  description = "Suffix for S3 bucket naming to avoid conflicts (required)"
  type        = string
  validation {
    condition     = length(var.bucket_naming_suffix) >= 6 && length(var.bucket_naming_suffix) <= 12
    error_message = "The bucket_naming_suffix must be between 6 and 12 characters long."
  }
}
