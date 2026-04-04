resource "aws_lakeformation_data_lake_settings" "default" {
  # LF-Tag作成に必要な管理者: ルート + 現在の実行ロール/ユーザー
  admins = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root",
    data.aws_caller_identity.current.arn
  ]

  # 何も書かない = create_table_default_permissions 空
  # （IAM_ALLOWED_PRINCIPALS が自動付与されない）
}

# -----------------------------------------------------------------------------
# LF-Tags 定義 (ProjectA=true, ProjectB=true)
# -----------------------------------------------------------------------------
resource "aws_lakeformation_lf_tag" "project_a" {
  key       = "ProjectA"
  values    = ["true"]
  depends_on = [aws_lakeformation_data_lake_settings.default]
}

resource "aws_lakeformation_lf_tag" "project_b" {
  key       = "ProjectB"
  values    = ["true"]
  depends_on = [aws_lakeformation_data_lake_settings.default]
}

resource "aws_lakeformation_lf_tag" "pii" {
  key       = "PII"
  values    = ["true"]
  depends_on = [aws_lakeformation_data_lake_settings.default]
}

# （参考）後でDBやテーブルへ付与する場合の例
# resource "aws_lakeformation_lf_tag_assignment" "fund_master_project_a" {
#   lf_tag_key    = aws_lakeformation_lf_tag.project_a.key
#   lf_tag_values = ["true"]
#   resource {
#     table {
#       database_name = aws_glue_catalog_database.data_platform.name
#       name          = "fund_master"
#     }
#   }
# }

# ABAC ユーザーに Lake Formation 権限 (SELECT のみ)
# ユーザへDatabase レベルでの基本権限(DatabaseはDescribeのみ)
resource "aws_lakeformation_permissions" "athena_user_ld_databases" {
  principal   = aws_iam_user.athena_user_with_access.arn
  permissions = ["DESCRIBE"]

  database {
    name = aws_glue_catalog_database.data_platform.name
  }
}

# ユーザへLF-Tag A ベースのテーブル権限 (SELECT + DESCRIBE)
resource "aws_lakeformation_permissions" "athena_user_lf_tables_proj_a" {
  # roleやgroupにも付与可能
  principal   = aws_iam_user.athena_user_with_access.arn
  permissions = ["SELECT", "DESCRIBE"]

  lf_tag_policy {
    # Databaseにも付与可能
    resource_type = "TABLE"
    expression {
      key    = aws_lakeformation_lf_tag.project_a.key
      values = ["true"]
    }
    expression {
      key    = aws_lakeformation_lf_tag.pii.key
      values = ["true"]
    }
  }
}

resource "aws_lakeformation_permissions" "athena_user_lf_tables_proj_b" {
  # roleやgroupにも付与可能
  principal   = aws_iam_user.athena_user_with_access.arn
  permissions = ["SELECT", "DESCRIBE"]

  lf_tag_policy {
    # Databaseにも付与可能
    resource_type = "TABLE"
    expression {
      key    = aws_lakeformation_lf_tag.project_b.key
      values = ["true"]
    }
    expression {
      key    = aws_lakeformation_lf_tag.pii.key
      values = ["true"]
    }
  }
}

# タグをデータベースに付与する
resource "aws_lakeformation_resource_lf_tags" "data_platform_database_add_ftag" {
  database {
    name = aws_glue_catalog_database.data_platform.name
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.project_a.key
    value = "true"
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.project_b.key
    value = "true"
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.pii.key
    value = "true"
  }

  depends_on = [aws_lakeformation_lf_tag.project_a, aws_lakeformation_lf_tag.project_b]
}


# タグをテーブルに付与する
resource "aws_lakeformation_resource_lf_tags" "cloudtrail_audit_logs_add_ftag" {
  table {
    database_name = aws_glue_catalog_database.data_platform.name
    # ワイルドカードでの指定も可能です。
    name          = aws_glue_catalog_table.cloudtrail_audit_logs.name
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.project_a.key
    value = "true"
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.project_b.key
    value = "true"
  }

  lf_tag {
    key   = aws_lakeformation_lf_tag.pii.key
    value = "true"
  }

  depends_on = [aws_lakeformation_lf_tag.project_a, aws_lakeformation_lf_tag.project_b, aws_glue_catalog_table.cloudtrail_audit_logs]
}


# （参考）ロールへ LF-Tag ベースの権限を付与する例
# resource "aws_lakeformation_permissions" "athena_role_project_a" {
#   principal   = aws_iam_role.athena_tag_based_access.arn
#   permissions = ["DESCRIBE", "SELECT"]
#   lf_tag_policy {
#     resource_type = "TABLE"
#     expression {
#       key    = aws_lakeformation_lf_tag.project_a.key
#       values = ["true"]
#     }
#   }
# }

# # fund_master テーブルに ProjectA タグを付与
# resource "aws_lakeformation_lf_tag_assignment" "fund_master_project_a" {
#   lf_tag_key    = aws_lakeformation_lf_tag.project_a.key
#   lf_tag_values = ["true"]
  
#   resource {
#     table {
#       database_name = aws_glue_catalog_database.data_platform.name
#       name          = "fund_master"
#     }
#   }
  
#   depends_on = [aws_lakeformation_lf_tag.project_a]
# }