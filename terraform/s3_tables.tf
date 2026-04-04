# S3 Tables for managed Iceberg support
# 
# This configuration creates S3 Tables structure (buckets, namespaces, and table metadata).
# Actual table schemas are defined in SQL DDL files under sql/s3tables/ directory.
# 
# Setup process:
# 1. Apply Terraform to create table structure
# 2. Enable AWS Analytics Services integration via console 
# 3. Execute DDL files in Athena to create tables with proper schemas
#
resource "aws_s3tables_table_bucket" "iceberg_managed" {
  name = "${var.project_name}-iceberg-managed-${var.bucket_naming_suffix}"
}

# Namespaces for each layer
resource "aws_s3tables_namespace" "bronze" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = "brz_ingestion"
}

# resource "aws_s3tables_namespace" "slv_fund" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = "slv_fund"
# }

# resource "aws_s3tables_namespace" "silver" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = "slv_analytics"
# }

resource "aws_s3tables_namespace" "reference" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = "ref"
}

# Fund Master Table in Bronze layer
# Schema: fund_id(string), fund_category(string)[投資信託_分類], trust_fee_rate(decimal(5,2))[信託報酬_率], 
#         is_active(boolean)[有効レコード], fund_name(string)[ファンド名], nickname(string)[ニックネーム], 
#         management_company(string)[運用会社], manager_name(string)[担当者氏名], manager_email(string)[担当者メール], 
#         ingest_date(date)
# Partitioned by: days(ingest_date)
resource "aws_s3tables_table" "fund_master" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = aws_s3tables_namespace.bronze.namespace
  name             = "fund_master"

  format = "ICEBERG"
  
  metadata {
    iceberg {
      schema {
        field {
          name     = "fund_id"
          type     = "string"
          required = true
        }
        field {
          name     = "fund_category"
          type     = "string"
          required = false
        }
        field {
          name     = "trust_fee_rate"
          type     = "decimal(5,2)"
          required = false
        }
        field {
          name     = "is_active"
          type     = "boolean"
          required = false
        }
        field {
          name     = "fund_name"
          type     = "string"
          required = false
        }
        field {
          name     = "nickname"
          type     = "string"
          required = false
        }
        field {
          name     = "management_company"
          type     = "string"
          required = false
        }
        field {
          name     = "manager_name"
          type     = "string"
          required = false
        }
        field {
          name     = "manager_email"
          type     = "string"
          required = false
        }
        field {
          name     = "ingest_date"
          type     = "date"
          required = true
        }
      }
    }
  }
  
  maintenance_configuration = {
    iceberg_compaction = {
      settings = {
        target_file_size_mb = 512
      }
      status = "enabled"
    }
    iceberg_snapshot_management = {
      settings = {
        max_snapshot_age_hours = 120
        min_snapshots_to_keep  = 1
      }
      status = "enabled"
    }
  }
  
  depends_on = [aws_s3tables_namespace.bronze]
}

# Fund NAV Table in Bronze layer  
# Schema: base_date(date)[基準日], fund_id(string), nav_price(decimal(18,4))[基準価格], ingest_date(date)
# Partitioned by: months(base_date)
# resource "aws_s3tables_table" "fund_nav" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = aws_s3tables_namespace.bronze.namespace
#   name             = "fund_nav"

#   format = "ICEBERG"
  
#   metadata {
#     iceberg {
#       schema {
#         field {
#           name     = "base_date"
#           type     = "date"
#           required = true
#         }
#         field {
#           name     = "fund_id"
#           type     = "string"
#           required = true
#         }
#         field {
#           name     = "nav_price"
#           type     = "decimal(18,4)"
#           required = false
#         }
#         field {
#           name     = "ingest_date"
#           type     = "date"
#           required = true
#         }
#       }
#     }
#   }
  
#   maintenance_configuration = {
#     iceberg_compaction = {
#       settings = {
#         target_file_size_mb = 512
#       }
#       status = "enabled"
#     }
#     iceberg_snapshot_management = {
#       settings = {
#         max_snapshot_age_hours = 120
#         min_snapshots_to_keep  = 1
#       }
#       status = "enabled"
#     }
#   }
  
#   depends_on = [aws_s3tables_namespace.bronze]
# }

# Fund Dimension Table in Gold layer (SCD2対応)
# Schema: fund_sk(bigint)[ファンドSK], fund_id(string)[ファンドID], fund_category(string)[投資信託_分類], 
#         trust_fee_rate(decimal(5,2))[信託報酬_率], active_flag(boolean)[有効フラグ], 
#         fund_name(string)[ファンド名], nickname(string)[ニックネーム], management_company(string)[運用会社],
#         manager_name(string)[担当者氏名], manager_email(string)[担当者メール],
#         effective_start_date(date)[効力開始日], effective_end_date(date)[効力終了日], current_flag(boolean)[現在フラグ]
# Business Key: fund_id
# resource "aws_s3tables_table" "dim_fund" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = aws_s3tables_namespace.gold.namespace
#   name             = "dim_fund"

#   format = "ICEBERG"
  
#   metadata {
#     iceberg {
#       schema {
#         field {
#           name     = "fund_sk"
#           type     = "long"
#           required = true
#         }
#         field {
#           name     = "fund_id"
#           type     = "string"
#           required = true
#         }
#         field {
#           name     = "fund_category"
#           type     = "string"
#           required = false
#         }
#         field {
#           name     = "trust_fee_rate"
#           type     = "decimal(5,2)"
#           required = false
#         }
#         field {
#           name     = "active_flag"
#           type     = "boolean"
#           required = false
#         }
#         field {
#           name     = "effective_start_date"
#           type     = "date"
#           required = true
#         }
#         field {
#           name     = "effective_end_date"
#           type     = "date"
#           required = true
#         }
#         field {
#           name     = "current_flag"
#           type     = "boolean"
#           required = true
#         }
#       }
#     }
#   }
  
#   maintenance_configuration = {
#     iceberg_compaction = {
#       settings = {
#         target_file_size_mb = 512
#       }
#       status = "enabled"
#     }
#     iceberg_snapshot_management = {
#       settings = {
#         max_snapshot_age_hours = 120
#         min_snapshots_to_keep  = 1
#       }
#       status = "enabled"
#     }
#   }
  
#   depends_on = [aws_s3tables_namespace.gold]
# }

# # Date Dimension Table in Gold layer
# # Schema: date_sk(int)[日付SK], date_value(date)[日付], year(smallint)[年], month(tinyint)[月], 
# #         day(tinyint)[日], day_of_week(smallint)[曜日], is_weekend(boolean)[週末フラグ],
# #         is_month_end(boolean)[月末フラグ], year_month(char(6))[年月], fiscal_year(smallint)[会計年度]
# # Business Key: date_value
# resource "aws_s3tables_table" "dim_date" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = aws_s3tables_namespace.gold.namespace
#   name             = "dim_date"

#   format = "ICEBERG"
  
#   metadata {
#     iceberg {
#       schema {
#         field {
#           name     = "date_sk"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "date_value"
#           type     = "date"
#           required = true
#         }
#         field {
#           name     = "year"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "month"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "day"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "day_of_week"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "is_weekend"
#           type     = "boolean"
#           required = false
#         }
#         field {
#           name     = "is_month_end"
#           type     = "boolean"
#           required = false
#         }
#         field {
#           name     = "year_month"
#           type     = "string"
#           required = false
#         }
#         field {
#           name     = "fiscal_year"
#           type     = "int"
#           required = false
#         }
#       }
#     }
#   }
  
#   maintenance_configuration = {
#     iceberg_compaction = {
#       settings = {
#         target_file_size_mb = 512
#       }
#       status = "enabled"
#     }
#     iceberg_snapshot_management = {
#       settings = {
#         max_snapshot_age_hours = 120
#         min_snapshots_to_keep  = 1
#       }
#       status = "enabled"
#     }
#   }
  
#   depends_on = [aws_s3tables_namespace.gold]
# }

# # Fund Performance Fact Table in Gold layer
# # Schema: date_sk(int)[日付SK], fund_sk(bigint)[ファンドSK], base_date(date)[基準日],
# #         nav_price_yen(decimal(18,4))[基準価額_円], price_change_yen(decimal(18,4))[騰落額_円], 
# #         price_change_rate_pct(decimal(10,6))[騰落率_%]
# # Partitioned by: months(base_date)
# # Foreign Keys: fund_sk -> dim_fund.fund_sk, date_sk -> dim_date.date_sk
# resource "aws_s3tables_table" "fct_fund_performance" {
#   table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
#   namespace        = aws_s3tables_namespace.gold.namespace
#   name             = "fct_fund_performance"

#   format = "ICEBERG"
  
#   metadata {
#     iceberg {
#       schema {
#         field {
#           name     = "date_sk"
#           type     = "int"
#           required = true
#         }
#         field {
#           name     = "fund_sk"
#           type     = "long"
#           required = true
#         }
#         field {
#           name     = "base_date"
#           type     = "date"
#           required = true
#         }
#         field {
#           name     = "nav_price_yen"
#           type     = "decimal(18,4)"
#           required = false
#         }
#         field {
#           name     = "price_change_yen"
#           type     = "decimal(18,4)"
#           required = false
#         }
#         field {
#           name     = "price_change_rate_pct"
#           type     = "decimal(10,6)"
#           required = false
#         }
#       }
#     }
#   }
  
#   maintenance_configuration = {
#     iceberg_compaction = {
#       settings = {
#         target_file_size_mb = 512
#       }
#       status = "enabled"
#     }
#     iceberg_snapshot_management = {
#       settings = {
#         max_snapshot_age_hours = 120
#         min_snapshots_to_keep  = 1
#       }
#       status = "enabled"
#     }
#   }
  
#   depends_on = [aws_s3tables_namespace.gold]
# }

# Legacy Fund Master Table in Bronze layer
# Schema: fund_id(string), fund_category(string)[投資信託_分類], trust_fee_rate(decimal(5,2))[信託報酬_率], 
#         is_active(boolean)[有効レコード], fund_name(string)[ファンド名], alias_name(string)[愛称], 
#         management_company(string)[運用会社], hidden_cost(decimal(5,2))[隠れコスト], 
#         internal_strategy_code(string)[内部戦略コード], ingest_date(date)
# Partitioned by: days(ingest_date)
resource "aws_s3tables_table" "legacy_fund_master" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = aws_s3tables_namespace.bronze.namespace
  name             = "legacy_fund_master"

  format = "ICEBERG"
  
  metadata {
    iceberg {
      schema {
        field {
          name     = "fund_id"
          type     = "string"
          required = true
        }
        field {
          name     = "fund_category"
          type     = "string"
          required = false
        }
        field {
          name     = "trust_fee_rate"
          type     = "decimal(5,2)"
          required = false
        }
        field {
          name     = "is_active"
          type     = "boolean"
          required = false
        }
        field {
          name     = "fund_name"
          type     = "string"
          required = false
        }
        field {
          name     = "alias_name"
          type     = "string"
          required = false
        }
        field {
          name     = "management_company"
          type     = "string"
          required = false
        }
        field {
          name     = "hidden_cost"
          type     = "decimal(5,2)"
          required = false
        }
        field {
          name     = "internal_strategy_code"
          type     = "string"
          required = false
        }
        field {
          name     = "ingest_date"
          type     = "date"
          required = true
        }
      }
    }
  }
  
  maintenance_configuration = {
    iceberg_compaction = {
      settings = {
        target_file_size_mb = 512
      }
      status = "enabled"
    }
    iceberg_snapshot_management = {
      settings = {
        max_snapshot_age_hours = 120
        min_snapshots_to_keep  = 1
      }
      status = "enabled"
    }
  }
  
  depends_on = [aws_s3tables_namespace.bronze]
}

# Deterministic Features V2 Table in Bronze layer
# Schema: fund_id(string), 投資信託_分類(string), fee_rate_pct(string), valid_flag(boolean),
#         fund_name(string)[ファンド名], nickname(string)[ニックネーム], mgmt_company(string)[運用会社],
#         ingest_date(date), fund_name_norm(string)[正規化ファンド名], 
#         company_norm(string)[正規化運用会社], nickname_norm(string)[正規化ニックネーム],
#         det_key(string)[決定的キー]
# Partitioned by: days(ingest_date)
resource "aws_s3tables_table" "det_features_v2" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = aws_s3tables_namespace.bronze.namespace
  name             = "det_features_v2"

  format = "ICEBERG"
  
  metadata {
    iceberg {
      schema {
        field {
          name     = "fund_id"
          type     = "string"
          required = true
        }
        field {
          name     = "fund_category"
          type     = "string"
          required = false
        }
        field {
          name     = "trust_fee_rate"
          type     = "string"
          required = false
        }
        field {
          name     = "is_active"
          type     = "boolean"
          required = false
        }
        field {
          name     = "fund_name"
          type     = "string"
          required = false
        }
        field {
          name     = "nickname"
          type     = "string"
          required = false
        }
        field {
          name     = "management_company"
          type     = "string"
          required = false
        }
        field {
          name     = "ingest_date"
          type     = "date"
          required = true
        }
        field {
          name     = "fund_name_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "company_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "nickname_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "det_key"
          type     = "string"
          required = false
        }
      }
    }
  }
  
  maintenance_configuration = {
    iceberg_compaction = {
      settings = {
        target_file_size_mb = 512
      }
      status = "enabled"
    }
    iceberg_snapshot_management = {
      settings = {
        max_snapshot_age_hours = 120
        min_snapshots_to_keep  = 1
      }
      status = "enabled"
    }
  }
  
  depends_on = [aws_s3tables_namespace.bronze]
}

# Deterministic Features Legacy Table in Bronze layer
# Schema: fund_id(string), 投資信託_分類(string), fee_rate_pct(string), valid_flag(boolean),
#         fund_name(string)[ファンド名], nickname(string)[ニックネーム/愛称], mgmt_company(string)[運用会社],
#         hidden_cost(string)[隠れコスト], ingest_date(date), fund_name_norm(string)[正規化ファンド名], 
#         company_norm(string)[正規化運用会社], nickname_norm(string)[正規化ニックネーム],
#         det_key(string)[決定的キー]
# Partitioned by: days(ingest_date)
resource "aws_s3tables_table" "det_features_legacy" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = aws_s3tables_namespace.bronze.namespace
  name             = "det_features_legacy"

  format = "ICEBERG"
  
  metadata {
    iceberg {
      schema {
        field {
          name     = "fund_id"
          type     = "string"
          required = true
        }
        field {
          name     = "fund_category"
          type     = "string"
          required = false
        }
        field {
          name     = "trust_fee_rate"
          type     = "string"
          required = false
        }
        field {
          name     = "is_active"
          type     = "boolean"
          required = false
        }
        field {
          name     = "fund_name"
          type     = "string"
          required = false
        }
        field {
          name     = "nickname"
          type     = "string"
          required = false
        }
        field {
          name     = "management_company"
          type     = "string"
          required = false
        }
        field {
          name     = "hidden_cost"
          type     = "string"
          required = false
        }
        field {
          name     = "ingest_date"
          type     = "date"
          required = true
        }
        field {
          name     = "fund_name_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "company_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "nickname_norm"
          type     = "string"
          required = false
        }
        field {
          name     = "det_key"
          type     = "string"
          required = false
        }
      }
    }
  }
  
  maintenance_configuration = {
    iceberg_compaction = {
      settings = {
        target_file_size_mb = 512
      }
      status = "enabled"
    }
    iceberg_snapshot_management = {
      settings = {
        max_snapshot_age_hours = 120
        min_snapshots_to_keep  = 1
      }
      status = "enabled"
    }
  }
  
  depends_on = [aws_s3tables_namespace.bronze]
}

# Probabilistic Match Scores Table in Bronze layer
# Schema: fund_id_v2(string)[V2ファンドID], fund_id_legacy(string)[レガシーファンドID], 
#         jaccard_dist(double)[Jaccard距離], fee_diff(double)[手数料差分]
# Business Key: fund_id_v2 + fund_id_legacy
resource "aws_s3tables_table" "probabilistic_match_scores" {
  table_bucket_arn = aws_s3tables_table_bucket.iceberg_managed.arn
  namespace        = aws_s3tables_namespace.bronze.namespace
  name             = "probabilistic_match_scores"

  format = "ICEBERG"
  
  metadata {
    iceberg {
      schema {
        field {
          name     = "fund_id_v2"
          type     = "string"
          required = true
        }
        field {
          name     = "fund_id_legacy"
          type     = "string"
          required = true
        }
        field {
          name     = "jaccard_dist"
          type     = "double"
          required = false
        }
        field {
          name     = "fee_diff"
          type     = "double"
          required = false
        }
      }
    }
  }
  
  maintenance_configuration = {
    iceberg_compaction = {
      settings = {
        target_file_size_mb = 512
      }
      status = "enabled"
    }
    iceberg_snapshot_management = {
      settings = {
        max_snapshot_age_hours = 120
        min_snapshots_to_keep  = 1
      }
      status = "enabled"
    }
  }
  
  depends_on = [aws_s3tables_namespace.bronze]
}
