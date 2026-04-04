# AWS Glue Resources for Data Catalog and ETL
# Glue Catalog Database
resource "aws_glue_catalog_database" "data_platform" {
  #name         = "dataplatformcatalog${substr(md5(random_id.bucket_suffix.hex), 0, 8)}"
  name         = "data_platform_catalog"
  description  = "Data Platform Catalog Database with Iceberg support"

  tags = var.common_tags
}

# Glue Data Catalog Encryption
resource "aws_glue_data_catalog_encryption_settings" "data_platform" {
  data_catalog_encryption_settings {
    connection_password_encryption {
      return_connection_password_encrypted = true
      aws_kms_key_id                      = aws_kms_key.glue.arn
    }

    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id     = aws_kms_key.glue.arn
    }
  }
}

# Glue Security Configuration
resource "aws_glue_security_configuration" "data_platform" {
  name = "${var.project_name}-security-config"

  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "SSE-KMS"
      kms_key_arn                = aws_kms_key.glue.arn
    }

    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                  = aws_kms_key.glue.arn
    }

    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn       = aws_kms_key.glue.arn
    }
  }
}

# Glue Crawler for source data
# KMS Key for Glue encryption
resource "aws_kms_key" "glue" {
  description             = "KMS key for Glue encryption"
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "EnableGlueJobAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.glue_job_role.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-glue-kms-v2"
  })
}

resource "aws_kms_alias" "glue" {
  name          = "alias/${var.project_name}-glue-v2"
  target_key_id = aws_kms_key.glue.key_id
}

# Data source is defined in data.tf
