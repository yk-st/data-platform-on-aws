# S3 Buckets for Data Platform
# Source data bucket (simulating different account)
module "source_data_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket = "${var.project_name}-source-${var.bucket_naming_suffix}"

  # Intelligent Tiering
  # intelligent_tiering = {
  #   general = {
  #     status = "Enabled"
  #     tiering = {
  #       ARCHIVE_ACCESS = {
  #         days = 90
  #       }
  #       DEEP_ARCHIVE_ACCESS = {
  #         days = 180
  #       }
  #     }
  #   }
  # }

  # versioning = {
  #   enabled = false
  # }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = var.common_tags
}

# MWAA Management Bucket for DAGs, scripts, and requirements
module "mwaa_management_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${var.project_name}-mwaa-management-${var.bucket_naming_suffix}"

  # versioning = {
  #   enabled = false
  # }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  tags = var.common_tags
}
