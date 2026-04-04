# ETL Scripts for Glue Jobs
# Note: All PySpark scripts are located in the mwaa/scripts/ folder and
# automatically uploaded to S3 via mwaa_files.tf
# 
# The following jobs are available for MWAA orchestration:
# 1. extract_fund_master.py - Fund master data extraction
# 2. extract_fund_nav.py - Fund NAV data extraction  
# 3. transform_wide_table.py - Data transformation to wide table format
# 4. aggregate_performance.py - Performance data aggregation
#
# Supporting utilities:
# - base_config.py - Configuration management
# - spark_utils.py - Spark utility functions
# - base_extractor.py - Base extraction functionality
#
# All scripts include:
# - Iceberg format support
# - Cuallee 0.15 data quality checks
# - CloudWatch logging
# - Job bookmarking for incremental processing

# Python jobs directory zip for Glue dependency management
data "archive_file" "jobs_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../mwaa/scripts/jobs"
  output_path = "${path.module}/../build/jobs.zip"
}

# Upload jobs.zip to S3 for Glue --py-files
resource "aws_s3_object" "jobs_zip" {
  bucket = module.mwaa_management_bucket.s3_bucket_id
  key    = "scripts/jobs.zip"
  source = data.archive_file.jobs_zip.output_path
  etag   = data.archive_file.jobs_zip.output_md5

  tags = var.common_tags
}
