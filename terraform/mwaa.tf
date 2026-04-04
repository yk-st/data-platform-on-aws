# Amazon Managed Workflows for Apache Airflow (MWAA) using latest module
# Temporarily disabled - uncomment when needed

# module "mwaa" {
#   source  = "idealo/mwaa/aws"
#   version = "~> 3.2"

#   # Required basic configuration
#   environment_name = "${var.project_name}-airflow"
#   airflow_version  = "2.10.3"
#   environment_class = "mw1.micro"

#   # Account and region information
#   account_id = data.aws_caller_identity.current.account_id
#   region     = data.aws_region.current.id

#   # S3 configuration
#   source_bucket_arn = module.mwaa_management_bucket.s3_bucket_arn
#   dag_s3_path      = "dags/"
#   requirements_s3_path = "requirements.txt"

#   # VPC configuration - use existing VPC and networking
#   vpc_id = module.vpc.vpc_id
  
#   # Network configuration - use existing networking infrastructure
#   create_networking_config = false
#   private_subnet_ids = module.vpc.private_subnets

#   # Scaling configuration for mw1.micro (must be exactly 1 worker)
#   min_workers = "1"
#   max_workers = "1"

#   # Webserver access
#   webserver_access_mode = "PUBLIC_ONLY"

#   # Logging configuration with WARNING level for cost optimization
#   dag_processing_logs_enabled = true
#   dag_processing_logs_level   = "WARNING"
#   scheduler_logs_enabled      = true
#   scheduler_logs_level        = "WARNING"
#   task_logs_enabled          = true
#   task_logs_level            = "WARNING"
#   webserver_logs_enabled     = true
#   webserver_logs_level       = "WARNING"
#   worker_logs_enabled        = true
#   worker_logs_level          = "WARNING"

#   # Airflow configuration
#   airflow_configuration_options = {
#     "core.default_timezone"         = "Asia/Tokyo"
#     "core.dags_are_paused_at_creation" = "False"
#     "core.enable_xcom_pickling"     = "True"
#     "webserver.expose_config"       = "True"
#     "scheduler.catchup_by_default"  = "False"
#   }

#   # Additional IAM policy for S3 Tables and Glue access
#   additional_execution_role_policy_document_json = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "s3tables:GetTableMetadataLocation",
#           "s3tables:GetTableMaintenanceConfiguration", 
#           "s3tables:GetTable",
#           "s3tables:GetNamespace",
#           "s3tables:GetTablePolicy",
#           "s3tables:GetTableMaintenanceJobStatus",
#           "s3tables:GetTableBucket",
#           "s3tables:ListTables",
#           "s3tables:ListNamespaces",
#           "s3tables:ListTableBuckets",
#           "s3tables:PutObject",
#           "s3tables:DeleteObject",
#           "s3tables:GetObject",
#           "s3tables:UpdateTableMetadataLocation",
#           "s3tables:PutTableMaintenanceConfiguration",
#           "s3tables:CreateTable",
#           "s3tables:DeleteTable",
#           "s3tables:CreateNamespace",
#           "s3tables:DeleteNamespace",
#           "s3tables:RenameTable"
#         ]
#         Resource = [
#           "arn:aws:s3tables:*:*:bucket/iceberg-table-bucket-*",
#           "arn:aws:s3tables:*:*:bucket/iceberg-table-bucket-*/namespace/*",
#           "arn:aws:s3tables:*:*:bucket/iceberg-table-bucket-*/namespace/*/table/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:ListBucket",
#           "s3:GetBucketLocation"
#         ]
#         Resource = [
#           "${module.data_lake_bucket.s3_bucket_arn}",
#           "${module.data_lake_bucket.s3_bucket_arn}/*"
#         ]
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "glue:GetJob",
#           "glue:CreateJob",
#           "glue:UpdateJob",
#           "glue:StartJobRun",
#           "glue:GetJobRun", 
#           "glue:BatchStopJobRun",
#           "glue:GetJobRuns",
#           "glue:GetJobs"
#         ]
#         Resource = "*"
#       },
#       {
#         Effect = "Allow"
#         Action = [
#           "iam:PassRole"
#         ]
#         Resource = [
#           "${aws_iam_role.glue_job_role.arn}"
#         ]
#       }
#     ]
#   })

#   tags = var.common_tags

#   depends_on = [
#     aws_s3_object.mwaa_requirements,
#     aws_s3_object.mwaa_dags
#   ]
# }