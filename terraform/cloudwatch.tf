# Glue job log groups with 3-day retention
resource "aws_cloudwatch_log_group" "glue_extract_fund_master" {
  name              = "/aws-glue/jobs/data-platform-extract-fund-master"
  retention_in_days = 3

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "glue_extract_fund_nav" {
  name              = "/aws-glue/jobs/data-platform-extract-fund-nav"
  retention_in_days = 3

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "glue_aggregate_performance" {
  name              = "/aws-glue/jobs/data-platform-aggregate-performance"
  retention_in_days = 3

  tags = var.common_tags
}
