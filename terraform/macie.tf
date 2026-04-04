# Amazon Macie Configuration for PII Detection
# ==============================================================================

# Macie用KMSキー
resource "aws_kms_key" "macie" {
  description             = "KMS key for Macie classification export encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Macie to use the key"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-macie-key"
    Description = "KMS key for Macie classification export"
    Purpose     = "macie-encryption"
  })
}

# KMSキーエイリアス
resource "aws_kms_alias" "macie" {
  name          = "alias/${var.project_name}-macie"
  target_key_id = aws_kms_key.macie.key_id
}

# # Macie サービスの有効化
# resource "aws_macie2_account" "main" {
#   finding_publishing_frequency = "FIFTEEN_MINUTES"
#   status                       = "ENABLED"
# }

# Macie検知結果保存用S3バケット
resource "aws_s3_bucket" "macie_results" {
  bucket = "${var.project_name}-macie-results-${var.bucket_naming_suffix}"

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-macie-results"
    Description = "Macie classification job results storage"
    Purpose     = "macie-results"
  })
}

# バケットのパブリックアクセス設定（完全にブロック）
resource "aws_s3_bucket_public_access_block" "macie_results" {
  bucket = aws_s3_bucket.macie_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# バケット暗号化設定
resource "aws_s3_bucket_server_side_encryption_configuration" "macie_results" {
  bucket = aws_s3_bucket.macie_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Macie結果保存設定
resource "aws_macie2_classification_export_configuration" "main" {
  s3_destination {
    bucket_name   = aws_s3_bucket.macie_results.id
    key_prefix    = "classification-results/"
    kms_key_arn   = aws_kms_key.macie.arn
  }

  depends_on = [
    aws_s3_bucket.macie_results,
    aws_s3_bucket_public_access_block.macie_results,
    aws_s3_bucket_policy.macie_results,
    aws_s3_bucket_server_side_encryption_configuration.macie_results,
    aws_kms_key.macie,
    # time_sleep.wait_for_macie_service_role
  ]
}

# Macieサービスリンクロールの伝播を待つためのリソース
# resource "time_sleep" "wait_for_macie_service_role" {
#   depends_on = [aws_macie2_account.main]

#   create_duration = "120s"  # 2分に延長
# }

# カスタム戦略コード検知用のデータ識別子
resource "aws_macie2_custom_data_identifier" "strategy_code" {
  name        = "${var.project_name}-strategy-code-detector"
  description = "Custom identifier for detecting strategy codes in legacy fund master data"

  # 戦略コード用正規表現パターン (STRAT-XXX-## 形式)
  # STRAT-GQA-01, STRAT-EQT-12, STRAT-FIU-05 などの形式に対応
  regex = "STRAT-[A-Z]{3}-[0-9]{2}"

  # キーワード（戦略コードに関連する用語）
  keywords = [
    "内部戦略コード",
    "戦略コード"
  ]

  # 最大一致距離（キーワードと正規表現パターンの近接度）
  maximum_match_distance = 300

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-strategy-code-detector"
    Description = "Custom data identifier for strategy codes"
    DataType    = "strategy-code"
  })

  # depends_on = [
  #   aws_macie2_account.main,
  #   time_sleep.wait_for_macie_service_role
  # ]
}

# v3: fund_master用の分類ジョブ（メールアドレス検知）
resource "aws_macie2_classification_job" "fund_master_email_detection_v5" {
  job_type = "ONE_TIME"
  name     = "${var.project_name}-fund-master-email-detection-v5"

  description = "v3: Enhanced email detection in fund_master data"

  # S3バケットとオブジェクトの指定
  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [module.source_data_bucket.s3_bucket_id]
    }

    # fund_masterファイルのみを対象
    scoping {
      includes {
        and {
          simple_scope_term {
            comparator = "STARTS_WITH"
            key        = "OBJECT_KEY"
            values     = ["fund"]
          }
        }
      }
    }
  }

  # 組み込みのメールアドレス検知を使用
  custom_data_identifier_ids = []

  # サンプリング設定（v3では効率化のため75%に調整）
  sampling_percentage = 75

  # ライフサイクル設定：すべての変更を無視（完了ジョブ対応）
  lifecycle {
    ignore_changes = all
    prevent_destroy = false
  }

  # depends_on = [
  #   aws_macie2_account.main,
  #   time_sleep.wait_for_macie_service_role
  # ]
}

# v3: legacy_fund_master用の分類ジョブ（戦略コード検知）
resource "aws_macie2_classification_job" "legacy_fund_master_strategy_detection_v5" {
  job_type = "ONE_TIME"
  name     = "${var.project_name}-legacy-fund-master-strategy-detection-v5"

  description = "v3: Enhanced strategy code detection in legacy_fund_master data"

  # S3バケットとオブジェクトの指定
  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = [module.source_data_bucket.s3_bucket_id]
    }

    # legacy_fund_masterファイルのみを対象
    scoping {
      includes {
        and {
          simple_scope_term {
            comparator = "STARTS_WITH"
            key        = "OBJECT_KEY"
            values     = ["legacy"]
          }
        }
      }
    }
  }

  # カスタム戦略コード検知器を使用
  custom_data_identifier_ids = [aws_macie2_custom_data_identifier.strategy_code.id]

  # サンプリング設定（v3では効率化のため75%に調整）
  sampling_percentage = 75

  # ライフサイクル設定：すべての変更を無視（完了ジョブ対応）
  lifecycle {
    ignore_changes = all
    prevent_destroy = false
  }

  # depends_on = [
  #   aws_macie2_account.main,
  #   aws_macie2_custom_data_identifier.strategy_code,
  #   time_sleep.wait_for_macie_service_role
  # ]
}

# Outputs
# output "macie_account_status" {
#   description = "Status of the Macie account"
#   value       = aws_macie2_account.main.status
# }

output "macie_results_bucket_name" {
  description = "Name of the Macie results S3 bucket"
  value       = aws_s3_bucket.macie_results.id
}

output "macie_kms_key_arn" {
  description = "ARN of the KMS key used for Macie classification export"
  value       = aws_kms_key.macie.arn
}

output "strategy_code_detector_id" {
  description = "ID of the custom strategy code detector"
  value       = aws_macie2_custom_data_identifier.strategy_code.id
}

# Macie結果バケットのポリシー
resource "aws_s3_bucket_policy" "macie_results" {
  bucket = aws_s3_bucket.macie_results.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMacieExport"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.macie_results.arn,
          "${aws_s3_bucket.macie_results.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
