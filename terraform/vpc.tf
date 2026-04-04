# VPC and Networking Resources
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  database_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false
  single_nat_gateway = true  # コスト削減のため1つのみ

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs - S3に直接出力（Parquet形式）
  enable_flow_log                      = false  # モジュールのデフォルトは無効化
  create_flow_log_cloudwatch_iam_role  = false
  create_flow_log_cloudwatch_log_group = false

  tags = var.common_tags
}

# Essential VPC Endpoints only (cost optimization)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

# Only essential Interface endpoints for core services
resource "aws_vpc_endpoint" "glue" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.glue"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-glue-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  private_dns_enabled = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-kms-endpoint"
  })
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-vpc-endpoints-"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-endpoints-sg"
  })
}

# VPC Flow Logs - S3にParquet形式で出力
resource "aws_s3_bucket" "vpc_flow_logs" {
  bucket = "${var.project_name}-vpc-flow-logs-${var.bucket_naming_suffix}"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-logs"
  })
}

# resource "aws_s3_bucket_versioning" "vpc_flow_logs" {
#   bucket = aws_s3_bucket.vpc_flow_logs.id
#   versioning_configuration {
#     status = "Enabled"
#   }
# }

resource "aws_s3_bucket_server_side_encryption_configuration" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "vpc_flow_logs" {
  bucket = aws_s3_bucket.vpc_flow_logs.id

  rule {
    id     = "transition_to_ia"
    status = "Enabled"

    filter {
      prefix = ""
    }

     # 最初からIntelligent-Tieringに移行(ディープアーカイブには行きません)
    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }

    #　アクセスパターンが予測可能であれば、チューニング項目として以下のように明示的にストレージの移動を指定することも可能
    # transition {
    #   days          = 30
    #   storage_class = "STANDARD_IA"
    # }

    # transition {
    #   days          = 60
    #   storage_class = "GLACIER_IR"
    # }

    expiration {
      days = 365
    }
  }
}

# VPC Flow Log設定（Parquet形式でS3に出力）
resource "aws_flow_log" "vpc_flow_log" {
  log_destination          = aws_s3_bucket.vpc_flow_logs.arn
  log_destination_type     = "s3"
  log_format              = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status}"
  max_aggregation_interval = 60
  traffic_type            = "ALL"
  vpc_id                  = module.vpc.vpc_id

  destination_options {
    file_format        = "parquet"
    hive_compatible_partitions = true
    per_hour_partition = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc-flow-log"
  })
}
