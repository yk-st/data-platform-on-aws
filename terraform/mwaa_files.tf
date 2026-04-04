# MWAA DAG and Scripts Upload
locals {
  mwaa_dag_files = fileset("${path.module}/../mwaa/dag", "**/*")
  mwaa_script_files = fileset("${path.module}/../mwaa/scripts", "**/*")
  data_files = fileset("${path.module}/../data", "**/*")
  
  # Legacy and Fund data files
  legacy_data_files = fileset("${path.module}/../data/legacy", "**/*")
  fund_data_files = fileset("${path.module}/../data/fund", "**/*")
}


# Upload MWAA DAG files
resource "aws_s3_object" "mwaa_dags" {
  for_each = local.mwaa_dag_files

  bucket = module.mwaa_management_bucket.s3_bucket_id
  key    = "dags/${each.value}"
  source = "${path.module}/../mwaa/dag/${each.value}"
  etag   = filemd5("${path.module}/../mwaa/dag/${each.value}")

  tags = var.common_tags
}

# Upload MWAA script files
resource "aws_s3_object" "mwaa_scripts" {
  for_each = { for file in local.mwaa_script_files : file => file if !strcontains(file, "__pycache__") }

  bucket = module.mwaa_management_bucket.s3_bucket_id
  key    = "scripts/${each.value}"
  source = "${path.module}/../mwaa/scripts/${each.value}"
  etag   = filemd5("${path.module}/../mwaa/scripts/${each.value}")

  tags = var.common_tags
}

# Upload initial data files
resource "aws_s3_object" "initial_data" {
  for_each = local.data_files

  bucket = module.source_data_bucket.s3_bucket_id
  key    = each.value
  source = "${path.module}/../data/${each.value}"
  etag   = filemd5("${path.module}/../data/${each.value}")

  tags = var.common_tags
}

# Upload Legacy data files to legacy bucket
resource "aws_s3_object" "legacy_data" {
  for_each = local.legacy_data_files

  bucket = module.source_data_bucket.s3_bucket_id
  key    = "legacy/${each.value}"
  source = "${path.module}/../data/legacy/${each.value}"
  etag   = filemd5("${path.module}/../data/legacy/${each.value}")

  tags = merge(var.common_tags, {
    DataType = "Legacy"
    Source   = "Historical System"
  })
}

# Upload Fund data files to fund bucket
resource "aws_s3_object" "fund_data" {
  for_each = local.fund_data_files

  bucket = module.source_data_bucket.s3_bucket_id
  key    = "fund/${each.value}"
  source = "${path.module}/../data/fund/${each.value}"
  etag   = filemd5("${path.module}/../data/fund/${each.value}")

  tags = merge(var.common_tags, {
    DataType = "Fund"
    Source   = "Investment System"
  })
}
