# AWS Glue Jobs for Data Processing
# 
# This configuration creates Glue jobs that process data and write to S3 Tables.
# Glue jobs are serverless and automatically scale based on workload.

# IAM Role for Glue Jobs
resource "aws_iam_role" "glue_job_role" {
  name = "${var.project_name}-glue-job-role-${var.bucket_naming_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Glue Jobs
resource "aws_iam_role_policy" "glue_job_policy" {
  name = "${var.project_name}-glue-job-policy-${var.bucket_naming_suffix}"
  role = aws_iam_role.glue_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.source_data_bucket.s3_bucket_arn,
          "${module.source_data_bucket.s3_bucket_arn}/*",
          module.mwaa_management_bucket.s3_bucket_arn,
          "${module.mwaa_management_bucket.s3_bucket_arn}/*",
          aws_s3tables_table_bucket.iceberg_managed.arn,
          "${aws_s3tables_table_bucket.iceberg_managed.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3tables:GetTable",
          "s3tables:CreateTable",
          "s3tables:DeleteTable",
          "s3tables:ListTables",
          "s3tables:PutTableData",
          "s3tables:GetTableData",
          "s3tables:CreateNamespace",
          "s3tables:GetNamespace",
          "s3tables:ListNamespaces",
          "s3tables:GetTableMetadataLocation",
          "s3tables:UpdateTableMetadataLocation",
          "s3tables:GetTableBucket",
          "s3tables:ListTableBuckets",
        ]
        Resource = [
          aws_s3tables_table_bucket.iceberg_managed.arn,
          "${aws_s3tables_table_bucket.iceberg_managed.arn}/namespace/*",
          "${aws_s3tables_table_bucket.iceberg_managed.arn}/namespace/*/table/*",
          "${aws_s3tables_table_bucket.iceberg_managed.arn}/table/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3tables:GetTableBucket",
          "s3tables:ListTableBuckets"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:/aws-glue/*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:BatchCreatePartition",
          "glue:BatchUpdatePartition",
          "glue:BatchDeletePartition",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",
          "glue:GetTables"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:CreateTags",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = [
          aws_kms_key.glue.arn
        ]
      }
    ]
  })
}

# Security Group for Glue Jobs
resource "aws_security_group" "glue_job" {
  name_prefix = "${var.project_name}-glue-job-"
  vpc_id      = module.vpc.vpc_id
  description = "Security group for Glue jobs"

  # 自分自身への通信を許可（Glueジョブ間通信）
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # 自分自身へのアウトバウンド通信を許可（Glueジョブ間通信）
  egress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  # 全てのアウトバウンド通信を許可（AWS要件）
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-glue-job-sg"
  })
}

# Glue Connection for VPC
resource "aws_glue_connection" "vpc_connection" {
  name = "${var.project_name}-vpc-connection-${var.bucket_naming_suffix}"
  
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = module.vpc.azs[0]
    security_group_id_list = [aws_security_group.glue_job.id]
    subnet_id              = module.vpc.private_subnets[0]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-connection"
  })
}

# Attach AWS managed policy for Glue service role
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Glue Job: Extract Fund Master
resource "aws_glue_job" "extract_fund_master" {
  name         = "${var.project_name}-extract-fund-master-${var.bucket_naming_suffix}"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "5.0"

  command {
    script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/fund/extract_fund_master.py"
    python_version  = "3"
  }

  # VPC設定
  connections = [aws_glue_connection.vpc_connection.name]

  default_arguments = {
    "--enable-metrics"                = "true"
    "--enable-spark-ui"              = "true"
    "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
    "--enable-job-insights"          = "true"
    "--enable-observability-metrics" = "true"
    "--job-language"                 = "python"
    "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
    "--additional-python-modules"    = "boto3,pendulum"
    
    # S3 Tables用のJARファイル（AWSドキュメント推奨）
    "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
    # S3 Tables + Iceberg Spark拡張の設定
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
    # Python files for dependencies
    "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    # Glue Job用のデフォルト引数
    "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
    "--catalog_database"   = aws_glue_catalog_database.data_platform.name
    "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
    "--aws_region"         = data.aws_region.current.id
    "--aws_account_id"     = data.aws_caller_identity.current.account_id
  }

  max_retries       = 0
  timeout           = 60
  worker_type       = "G.1X"
  number_of_workers = 2

  depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
}

# Glue Job: Extract Fund NAV
# resource "aws_glue_job" "extract_fund_nav" {
#   name         = "${var.project_name}-extract-fund-nav-${var.bucket_naming_suffix}"
#   role_arn     = aws_iam_role.glue_job_role.arn
#   glue_version = "5.0"

#   command {
#     script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/fund/extract_fund_nav.py"
#     python_version  = "3"
#   }

#   # VPC設定
#   connections = [aws_glue_connection.vpc_connection.name]

#   default_arguments = {
#     "--enable-metrics"                = "true"
#     "--enable-spark-ui"              = "true"
#     "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
#     "--enable-job-insights"          = "true"
#     "--enable-observability-metrics" = "true"
#     "--job-language"                 = "python"
#     "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
#     "--additional-python-modules"    = "boto3,pendulum"
    
#     # S3 Tables用のJARファイル（AWSドキュメント推奨）
#     "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
#     # S3 Tables + Iceberg Spark拡張の設定
#     "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
#     # Python files for dependencies
#     "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
#     "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    
#     # Glue Job用のデフォルト引数
#     "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
#     "--catalog_database"   = aws_glue_catalog_database.data_platform.name
#     "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
#     "--aws_region"         = data.aws_region.current.id
#     "--aws_account_id"     = data.aws_caller_identity.current.account_id
#   }

#   max_retries       = 0
#   timeout           = 60
#   worker_type       = "G.1X"
#   number_of_workers = 2

#   depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
# }

# Glue Job: Extract Legacy Fund Master
resource "aws_glue_job" "extract_legacy_fund_master" {
  name         = "${var.project_name}-extract-legacy-fund-master-${var.bucket_naming_suffix}"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "5.0"

  command {
    script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/legacy/extract_legacy_fund_master.py"
    python_version  = "3"
  }

  # VPC設定
  connections = [aws_glue_connection.vpc_connection.name]

  default_arguments = {
    "--enable-metrics"                = "true"
    "--enable-spark-ui"              = "true"
    "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
    "--enable-job-insights"          = "true"
    "--enable-observability-metrics" = "true"
    "--job-language"                 = "python"
    "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
    "--additional-python-modules"    = "boto3,pendulum"
    
    # S3 Tables用のJARファイル（AWSドキュメント推奨）
    "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
    # S3 Tables + Iceberg Spark拡張の設定
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
    # Python files for dependencies
    "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    
    # Glue Job用のデフォルト引数
    "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
    "--catalog_database"   = aws_glue_catalog_database.data_platform.name
    "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
    "--aws_region"         = data.aws_region.current.id
    "--aws_account_id"     = data.aws_caller_identity.current.account_id
  }

  max_retries       = 0
  timeout           = 60
  worker_type       = "G.1X"
  number_of_workers = 2

  depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
}

# # Glue Job: Aggregate Performance
# resource "aws_glue_job" "aggregate_performance" {
#   name         = "${var.project_name}-aggregate-performance-${var.bucket_naming_suffix}"
#   role_arn     = aws_iam_role.glue_job_role.arn
#   glue_version = "5.0"

#   command {
#     script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/fund/aggregate_performance.py"
#     python_version  = "3"
#   }

#   # VPC設定
#   connections = [aws_glue_connection.vpc_connection.name]

#   default_arguments = {
#     "--enable-metrics"                = "true"
#     "--enable-spark-ui"              = "true"
#     "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
#     "--enable-job-insights"          = "true"
#     "--enable-observability-metrics" = "true"
#     "--job-language"                 = "python"
#     "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
#     "--additional-python-modules"    = "boto3,pendulum"
    
#     # S3 Tables用のJARファイル（AWSドキュメント推奨）
#     "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
#     # S3 Tables + Iceberg Spark拡張の設定
#     "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
#     # Python files for dependencies
#     "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
#     "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"

#     # Glue Job用のデフォルト引数
#     "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
#     "--catalog_database"   = aws_glue_catalog_database.data_platform.name
#     "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
#     "--aws_region"         = data.aws_region.current.id
#     "--aws_account_id"     = data.aws_caller_identity.current.account_id
#   }

#   max_retries       = 0
#   timeout           = 120
#   worker_type       = "G.1X"
#   number_of_workers = 2

#   depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
# }

# S3 Tables JAR用のS3オブジェクト
resource "aws_s3_object" "s3_tables_jar" {
  bucket = module.mwaa_management_bucket.s3_bucket_id
  key    = "jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar"
  source = "${path.module}/jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar"
  etag   = filemd5("${path.module}/jars/s3-tables-catalog-for-iceberg-runtime-0.1.5.jar")

  tags = {
    Name        = "${var.project_name}-s3tables-jar-${var.bucket_naming_suffix}"
    Purpose     = "S3TablesIntegration"
    Component   = "GlueJobs"
  }
}

# Glue Job: Process Deterministic Features
resource "aws_glue_job" "process_deterministic_features" {
  name         = "${var.project_name}-process-deterministic-features-${var.bucket_naming_suffix}"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "5.0"

  command {
    script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/name_collection/deterministic.py"
    python_version  = "3"
  }

  # VPC設定
  connections = [aws_glue_connection.vpc_connection.name]

  default_arguments = {
    "--enable-metrics"                = "true"
    "--enable-spark-ui"              = "true"
    "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
    "--enable-job-insights"          = "true"
    "--enable-observability-metrics" = "true"
    "--job-language"                 = "python"
    "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
    "--additional-python-modules"    = "boto3,pendulum"
    
    # S3 Tables用のJARファイル（AWSドキュメント推奨）
    "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
    # S3 Tables + Iceberg Spark拡張の設定
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
    # Python files for dependencies
    "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"

    # Glue Job用のデフォルト引数
    "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
    "--catalog_database"   = aws_glue_catalog_database.data_platform.name
    "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
    "--aws_region"         = data.aws_region.current.id
    "--aws_account_id"     = data.aws_caller_identity.current.account_id
  }

  max_retries       = 0
  timeout           = 60
  worker_type       = "G.1X"
  number_of_workers = 2

  depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
}

# Outputs
output "glue_job_role_arn" {
  description = "ARN of the Glue job execution role"
  value       = aws_iam_role.glue_job_role.arn
}

output "glue_jobs" {
  description = "Names of created Glue jobs"
  value = {
    extract_fund_master            = aws_glue_job.extract_fund_master.name
    # extract_fund_nav               = aws_glue_job.extract_fund_nav.name
    extract_legacy_fund_master     = aws_glue_job.extract_legacy_fund_master.name
    # aggregate_performance          = aws_glue_job.aggregate_performance.name
    process_deterministic_features = aws_glue_job.process_deterministic_features.name
    process_probabilistic_scoring  = aws_glue_job.process_probabilistic_scoring.name
  }
}

# Glue Job: Process Probabilistic Scoring
resource "aws_glue_job" "process_probabilistic_scoring" {
  name         = "${var.project_name}-process-probabilistic-scoring-${var.bucket_naming_suffix}"
  role_arn     = aws_iam_role.glue_job_role.arn
  glue_version = "5.0"

  command {
    script_location = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs/name_collection/probabilistic_scoring_refactored.py"
    python_version  = "3"
  }

  # VPC設定
  connections = [aws_glue_connection.vpc_connection.name]

  default_arguments = {
    "--enable-metrics"                = "true"
    "--enable-spark-ui"              = "true"
    "--spark-event-logs-path"        = "s3://${module.mwaa_management_bucket.s3_bucket_id}/logs/spark-ui/"
    "--enable-job-insights"          = "true"
    "--enable-observability-metrics" = "true"
    "--job-language"                 = "python"
    "--TempDir"                      = "s3://${module.mwaa_management_bucket.s3_bucket_id}/temporary/"
    "--additional-python-modules"    = "boto3,pendulum"
    
    # S3 Tables用のJARファイル（AWSドキュメント推奨）
    "--extra-jars" = "s3://${aws_s3_object.s3_tables_jar.bucket}/${aws_s3_object.s3_tables_jar.key}"
    
    # S3 Tables + Iceberg Spark拡張の設定
    "--conf" = "spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    
    # Python files for dependencies
    "--py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"
    "--extra-py-files" = "s3://${module.mwaa_management_bucket.s3_bucket_id}/scripts/jobs.zip"

    # Glue Job用のデフォルト引数
    "--source_bucket_name" = module.source_data_bucket.s3_bucket_id
    "--catalog_database"   = aws_glue_catalog_database.data_platform.name
    "--table_bucket_name"  = aws_s3tables_table_bucket.iceberg_managed.name
    "--aws_region"         = data.aws_region.current.id
    "--aws_account_id"     = data.aws_caller_identity.current.account_id
  }

  max_retries       = 0
  timeout           = 2880
  number_of_workers = 2
  worker_type       = "G.1X"

  # カスタムタグ - このジョブのみTenantId=tenant-002に設定
  tags = merge(var.common_tags, {
    TenantId = "tenant-002"
  })

  depends_on = [aws_iam_role_policy.glue_job_policy, aws_s3_object.s3_tables_jar, aws_glue_connection.vpc_connection]
}
