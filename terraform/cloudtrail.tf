# CloudTrail Audit Logging Configuration
# ==============================================================================

# CloudTrail用S3バケット（WORM設定、7日ライフサイクル）
resource "aws_s3_bucket" "cloudtrail_audit_logs" {
  bucket = "${var.project_name}-cloudtrail-audit-logs-${var.bucket_naming_suffix}"

  # Object Lock有効化のためにobject_lock_enabledを設定
  object_lock_enabled = true

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-cloudtrail-audit-logs"
    Description = "CloudTrail audit logs storage with WORM compliance"
    Purpose     = "audit-logging"
  })
}

# バケットのパブリックアクセス設定（完全にブロック）
resource "aws_s3_bucket_public_access_block" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バケットバージョニング設定（WORM要件）
resource "aws_s3_bucket_versioning" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Object Lock設定（WORM - Write Once Read Many）
resource "aws_s3_bucket_object_lock_configuration" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id

  # Complianceモードだとより強力で削除できません(ので、環境の削除時に困るのでGovernanceモードにしておきます)
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail_audit_logs]
}

# ライフサイクル設定（7日後削除）
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id

  rule {
    id     = "cloudtrail_audit_logs_lifecycle"
    status = "Enabled"

    # 現在のバージョンの削除
    expiration {
      days = 7
    }

    # 非現在バージョンの削除
    noncurrent_version_expiration {
      noncurrent_days = 7
    }

    # 不完全なマルチパートアップロードの削除
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.cloudtrail_audit_logs]
}

# バケット暗号化設定
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# CloudTrail用のバケットポリシー
resource "aws_s3_bucket_policy" "cloudtrail_audit_logs" {
  bucket = aws_s3_bucket.cloudtrail_audit_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_audit_logs.arn
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-audit-trail"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_audit_logs.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "AWS:SourceArn" = "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.project_name}-audit-trail"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_audit_logs]
}

# CloudTrail設定（データイベント有効、CloudWatch Logs統合）
resource "aws_cloudtrail" "audit_trail" {
  name           = "${var.project_name}-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_audit_logs.id

  # CloudWatch Logs設定
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail_log_group.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_logs_role.arn

  # 管理イベントとデータイベントを有効化
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  # データイベント設定
  event_selector {
    read_write_type                 = "All"
    include_management_events       = true

    # S3データイベント（全てのバケット）
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-audit-trail"
    Description = "Audit trail for data platform with data events enabled"
    Purpose     = "compliance-audit"
  })

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_audit_logs,
    aws_iam_role_policy.cloudtrail_logs_policy
  ]
}

# CloudWatch Logs Group for CloudTrail（オプション）
resource "aws_cloudwatch_log_group" "cloudtrail_log_group" {
  name              = "/aws/cloudtrail/${var.project_name}-audit-trail"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-cloudtrail-logs"
    Description = "CloudTrail logs in CloudWatch"
    Purpose     = "audit-logging"
  })
}

# CloudTrail用IAMロール（CloudWatch Logsへの送信用）
resource "aws_iam_role" "cloudtrail_logs_role" {
  name = "${var.project_name}-cloudtrail-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-cloudtrail-logs-role"
    Description = "IAM role for CloudTrail to send logs to CloudWatch"
  })
}

# CloudTrail用IAMポリシー
resource "aws_iam_role_policy" "cloudtrail_logs_policy" {
  name = "${var.project_name}-cloudtrail-logs-policy"
  role = aws_iam_role.cloudtrail_logs_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail_log_group.arn}:*"
      }
    ]
  })
}

# Outputs
output "cloudtrail_s3_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail_audit_logs.id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = aws_cloudtrail.audit_trail.arn
}

output "cloudtrail_logs_group_name" {
  description = "Name of the CloudTrail CloudWatch Logs group"
  value       = aws_cloudwatch_log_group.cloudtrail_log_group.name
}
