# Tag-Based Access Control for Athena
# 既存ロールにタグ条件を追加してテーブルアクセス制御
# ==============================================================================

# Athena用のタグベースアクセス制御ロール
# resource "aws_iam_role" "athena_tag_based_access" {
#   name = "${var.project_name}-athena-tag-based"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#         }
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })

#   tags = merge(var.common_tags, {
#     Name        = "${var.project_name}-athena-tag-based"
#     Description = "Tag-based access control for Athena queries"
#   })
# }

# resource "aws_iam_role_policy" "athena_tag_based_access" {
#   name = "${var.project_name}-athena-tag-based-policy"
#   role = aws_iam_role.athena_tag_based_access.id

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         # Athena基本権限
#         Effect = "Allow"
#         Action = [
#           "athena:StartQueryExecution",
#           "athena:GetQueryExecution",
#           "athena:GetQueryResults",
#           "athena:StopQueryExecution",
#           "athena:GetWorkGroup",
#           "athena:ListWorkGroups"
#         ]
#         Resource = "*"
#       },
#       {
#         # Glue Catalog基本権限
#         Effect = "Allow"
#         Action = [
#           "glue:GetDatabase",
#           "glue:GetDatabases",
#           "glue:GetTables",
#           "glue:GetPartitions",
#           "glue:ListTables",
#           "glue:GetCatalogImportStatus"
#         ]
#         Resource = "*"
#       },
#       {
#         # Athena一般権限（ワークグループに依存しない）
#         Effect = "Allow"
#         Action = [
#           "athena:ListWorkGroups",
#           "athena:GetDataCatalog",
#           "athena:ListDataCatalogs"
#         ]
#         Resource = "*"
#       },
#       {
#         # タグ条件付きテーブルアクセス - fund_masterのみアクセス可能
#         Effect = "Allow"
#         Action = [
#           "glue:GetTable",
#           "glue:GetTables"
#         ]
#         Resource = [
#           "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.data_platform.name}/*"
#         ]
#         Condition = {
#           StringEquals = {
#             "aws:PrincipalTag/FundMasterAccess" = "allowed"
#           }
#         }
#       },
#       {
#         # S3 Tables読み取り権限（タグ条件付き）
#         Effect = "Allow"
#         Action = [
#           "s3tables:GetTable",
#           "s3tables:GetTableMetadata",
#           "s3tables:ListTables",
#           "s3tables:GetNamespace"
#         ]
#         Resource = [
#           aws_s3tables_table.fund_master.arn
#         ]
#         Condition = {
#           StringEquals = {
#             "aws:PrincipalTag/FundMasterAccess" = "allowed"
#           }
#         }
#       },
#       {
#         # S3 Tables基本権限
#         Effect = "Allow"
#         Action = [
#           "s3tables:ListTableBuckets",
#           "s3tables:ListNamespaces"
#         ]
#         Resource = "*"
#       },
#       {
#         # Athena結果保存権限
#         Effect = "Allow"
#         Action = [
#           "s3:GetObject",
#           "s3:PutObject",
#           "s3:DeleteObject"
#         ]
#         Resource = [
#           "${module.source_data_bucket.s3_bucket_arn}/athena-results/*"
#         ]
#       },
#       {
#         # S3バケット一覧権限
#         Effect = "Allow"
#         Action = [
#           "s3:ListBucket",
#           "s3:GetBucketLocation"
#         ]
#         Resource = [
#           module.source_data_bucket.s3_bucket_arn
#         ]
#       }
#     ]
#   })
# }

# テストユーザー1: fund_masterアクセス許可タグ付き
resource "aws_iam_user" "athena_user_with_access" {
  name = "${var.project_name}-athena-user-with-access"

  tags = merge(var.common_tags, {
    Name               = "${var.project_name}-athena-user-with-access"
    Description        = "User with fund_master access tag"
    # FundMasterAccess   = "allowed"  # 🔑 アクセス許可タグ
  })
}

# # ユーザー1にロール割り当て
# resource "aws_iam_user_policy" "athena_user_with_access_assume_role" {
#   name = "${var.project_name}-athena-user-with-access-policy"
#   user = aws_iam_user.athena_user_with_access.name

#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = "sts:AssumeRole"
#         Resource = aws_iam_role.athena_tag_based_access.arn
#       }
#     ]
#   })
# }

# ユーザー1にAdmin権限追加(他の権限で邪魔されていないか確認するため)
resource "aws_iam_user_policy_attachment" "athena_user_admin_access" {
  user       = aws_iam_user.athena_user_with_access.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# # Outputs
# output "athena_tag_based_abac" {
#   description = "Tag-based ABAC for Athena"
#   value = {
#     role_arn           = aws_iam_role.athena_tag_based_access.arn
#     user_with_access   = aws_iam_user.athena_user_with_access.name
#     test_instruction   = "User with 'FundMasterAccess=allowed' tag can access fund_master table, user has Admin access for testing"
#   }
# }
