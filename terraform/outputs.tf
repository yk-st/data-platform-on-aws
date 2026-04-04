# Outputs for Data Platform
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "source_data_bucket_name" {
  description = "Source Data S3 bucket name"
  value       = module.source_data_bucket.s3_bucket_id
}

output "glue_catalog_database_name" {
  description = "Glue Catalog database name"
  value       = aws_glue_catalog_database.data_platform.name
}

output "glue_job_names" {
  description = "List of Glue job names for MWAA orchestration"
  value = {
    extract_fund_master            = aws_glue_job.extract_fund_master.name
    # extract_fund_nav               = aws_glue_job.extract_fund_nav.name
    extract_legacy_fund_master     = aws_glue_job.extract_legacy_fund_master.name
    # aggregate_performance          = aws_glue_job.aggregate_performance.name
    process_deterministic_features = aws_glue_job.process_deterministic_features.name
  }
}

output "athena_workgroup_name" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.data_platform.name
}

output "athena_workgroup_arn" {
  description = "Athena workgroup ARN"
  value       = aws_athena_workgroup.data_platform.arn
}

# MWAA outputs temporarily disabled
/*
output "mwaa_environment_name" {
  description = "MWAA environment name"
  value       = module.mwaa.mwaa_arn
}

output "mwaa_webserver_url" {
  description = "MWAA webserver URL"
  value       = module.mwaa.mwaa_webserver_url
}

output "mwaa_execution_role_arn" {
  description = "MWAA execution role ARN"
  value       = module.mwaa.mwaa_execution_role_arn
}
*/

# output "cloudwatch_dashboard_url" {
#   description = "CloudWatch dashboard URL"
#   value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.data_platform.dashboard_name}"
# }

# MWAA file outputs temporarily disabled
output "uploaded_dag_files" {
  description = "List of uploaded DAG files"
  value       = keys(aws_s3_object.mwaa_dags)
}

output "uploaded_script_files" {
  description = "List of uploaded script files"
  value       = keys(aws_s3_object.mwaa_scripts)
}

output "uploaded_data_files" {
  description = "List of uploaded initial data files"
  value       = keys(aws_s3_object.initial_data)
}

output "uploaded_legacy_data_files" {
  description = "List of uploaded legacy data files (in source bucket)"
  value       = keys(aws_s3_object.legacy_data)
}

output "uploaded_fund_data_files" {
  description = "List of uploaded fund data files"
  value       = keys(aws_s3_object.fund_data)
}
