# Amazon Athena Configuration
# Athena Workgroup
resource "aws_athena_workgroup" "data_platform" {
  name = "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    bytes_scanned_cutoff_per_query     = 100000000000 # 100GB limit
    
    result_configuration {
      output_location = "s3://${module.source_data_bucket.s3_bucket_id}/athena-results/"
      
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.common_tags
}

# Athena Data Catalog uses the Glue catalog database
# No separate aws_athena_database resource needed - Athena uses Glue catalog directly

# CloudTrail audit logs table for Athena
resource "aws_glue_catalog_table" "cloudtrail_audit_logs" {
  name          = "cloudtrail_audit_logs"
  database_name = aws_glue_catalog_database.data_platform.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "projection.enabled"          = "true"
    "projection.region.type"      = "enum"
    "projection.region.values"    = "ap-northeast-1,us-east-1,us-west-2,eu-west-1"
    "projection.year.type"        = "integer"
    "projection.year.range"       = "2020,2030"
    "projection.year.digits"      = "4"
    "projection.month.type"       = "integer"
    "projection.month.range"      = "01,12"
    "projection.month.digits"     = "2"
    "projection.day.type"         = "integer"
    "projection.day.range"        = "01,31"
    "projection.day.digits"       = "2"
    "storage.location.template"   = "s3://${aws_s3_bucket.cloudtrail_audit_logs.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudTrail/$${region}/$${year}/$${month}/$${day}/"
    "classification"              = "cloudtrail"
    "compressionType"            = "gzip"
    "typeOfData"                 = "file"
  }

  partition_keys {
    name = "region"
    type = "string"
  }

  partition_keys {
    name = "year"
    type = "string"
  }

  partition_keys {
    name = "month"
    type = "string"
  }

  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.cloudtrail_audit_logs.id}/AWSLogs/${data.aws_caller_identity.current.account_id}/CloudTrail/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "CloudTrailSerDe"
      serialization_library = "com.amazon.emr.hive.serde.CloudTrailSerde"
    }

    columns {
      name = "eventversion"
      type = "string"
    }

    columns {
      name = "useridentity"
      type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,userName:string,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalId:string,arn:string,accountId:string,userName:string>>>"
    }

    columns {
      name = "eventtime"
      type = "string"
    }

    columns {
      name = "eventsource"
      type = "string"
    }

    columns {
      name = "eventname"
      type = "string"
    }

    columns {
      name = "awsregion"
      type = "string"
    }

    columns {
      name = "sourceipaddress"
      type = "string"
    }

    columns {
      name = "useragent"
      type = "string"
    }

    columns {
      name = "errorcode"
      type = "string"
    }

    columns {
      name = "errormessage"
      type = "string"
    }

    columns {
      name = "requestparameters"
      type = "string"
    }

    columns {
      name = "responseelements"
      type = "string"
    }

    columns {
      name = "additionaleventdata"
      type = "string"
    }

    columns {
      name = "requestid"
      type = "string"
    }

    columns {
      name = "eventid"
      type = "string"
    }

    columns {
      name = "resources"
      type = "array<struct<accountid:string,type:string,arn:string>>"
    }

    columns {
      name = "eventtype"
      type = "string"
    }

    columns {
      name = "apiversion"
      type = "string"
    }

    columns {
      name = "readonly"
      type = "string"
    }

    columns {
      name = "recipientaccountid"
      type = "string"
    }

    columns {
      name = "serviceeventdetails"
      type = "string"
    }

    columns {
      name = "sharedeventid"
      type = "string"
    }

    columns {
      name = "vpcendpointid"
      type = "string"
    }
  }

}

# CloudWatch Dashboards for monitoring
# resource "aws_cloudwatch_dashboard" "data_platform" {
#   dashboard_name = "${var.project_name}-dashboard"

#   dashboard_body = jsonencode({
#     widgets = [
#       {
#         type   = "metric"
#         x      = 0
#         y      = 0
#         width  = 12
#         height = 6

#         properties = {
#           metrics = [
#             ["AWS/Athena", "QueryExecutionTime", "WorkGroup", aws_athena_workgroup.data_platform.name],
#             ["AWS/Athena", "ProcessedBytes", "WorkGroup", aws_athena_workgroup.data_platform.name],
#             ["AWS/Athena", "QueryQueueTime", "WorkGroup", aws_athena_workgroup.data_platform.name]
#           ]
#           view    = "timeSeries"
#           stacked = false
#           region  = var.aws_region
#           title   = "Athena Query Performance"
#           period  = 300
#         }
#       },
#       {
#         type   = "metric"
#         x      = 0
#         y      = 6
#         width  = 12
#         height = 6

#         properties = {
#           metrics = [
#             ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.extract_fund_master.name],
#             ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", aws_glue_job.extract_fund_master.name],
#             ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.extract_fund_nav.name],
#             ["AWS/Glue", "glue.driver.aggregate.numFailedTasks", "JobName", aws_glue_job.extract_fund_nav.name]
#           ]
#           view    = "timeSeries"
#           stacked = false
#           region  = var.aws_region
#           title   = "Glue Job Performance"
#           period  = 300
#         }
#       },
#       {
#         type   = "metric"
#         x      = 0
#         y      = 12
#         width  = 12
#         height = 6

#         properties = {
#           metrics = [
#             ["AWS/S3", "BucketSizeBytes", "BucketName", module.source_data_bucket.s3_bucket_id, "StorageType", "StandardStorage"]
#           ]
#           view    = "timeSeries"
#           stacked = false
#           region  = var.aws_region
#           title   = "S3 Storage Usage"
#           period  = 86400
#         }
#       },
#       {
#         type   = "metric"
#         x      = 0
#         y      = 18
#         width  = 12
#         height = 6

#         properties = {
#           metrics = [
#             ["AWS/CloudTrail", "ErrorCount", "TrailName", aws_cloudtrail.audit_trail.name],
#             ["AWS/CloudTrail", "TotalLogs", "TrailName", aws_cloudtrail.audit_trail.name]
#           ]
#           view    = "timeSeries"
#           stacked = false
#           region  = var.aws_region
#           title   = "CloudTrail Audit Logs"
#           period  = 300
#         }
#       }
#     ]
#   })
# }
