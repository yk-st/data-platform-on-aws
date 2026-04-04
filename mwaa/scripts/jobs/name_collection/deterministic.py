"""
deterministic_features.py
-------------------------
* 列名ゆれを固定のalias mapで統一
* ファンド名+運用会社を正規化し det_key を生成
* Iceberg テーブルに保存
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F, types as T
from jobs.name_collection.config import NameCollectionConfig
import re
import unicodedata

class DeterministicFeaturesProcessor:
    def __init__(self, config, args, glue_context=None, s3tables_catalog_name=None):
        self.config = config
        self.args = args
        self.glue_context = glue_context
        self.s3tables_catalog_name = s3tables_catalog_name
    
    def process(self, spark):
        print("=" * 50)
        print("🔍 DEBUG: Deterministic Features Processing")
        print("=" * 50)
        
        # ── ① 固定のalias rules
        records = [
            # ファンド名の様々な表記
            ("^(ファンド名|fund(_)?name)$",                    "fund_name",      1),
            
            # 運用会社の様々な表記
            ("^(運用会社|マネジメント会社|management[_ ]?company|mgmt[_ ]?company)$", "management_company", 1),
            
            # ニックネーム/愛称の様々な表記
            ("^(愛称|ニックネーム|nickname|alias[_ ]?name)$",  "nickname",       1),
            
            # 信託報酬率の様々な表記
            ("^(信託報酬_?率?|management[_ ]?fee|fee[_ ]?rate[_ ]?pct)$", "trust_fee_rate", 1),
            
            # 隠れコストの様々な表記
            ("^(隠れコスト(率)?|hidden[_ ]?cost)$",            "hidden_cost",    1),
            
            # 有効フラグの様々な表記
            ("^(有効レコード|is[_ ]?active|valid[_ ]?flag)$",  "valid_flag",     1),
            
            # 投資信託分類の様々な表記
            ("^(投資信託[_ ]?分類|fund[_ ]?category|投信[_ ]?分類)$", "fund_category", 1),
            
            # 取込日付の様々な表記
            ("^(取込日|取込日付|ingest[_ ]?date)$",             "ingest_date",    1),
        ]

        schema = (
            T.StructType()
            .add("regex",          T.StringType())
            .add("canonical_name", T.StringType())
            .add("priority",       T.IntegerType())
        )
        
        # DataFrameから正規表現ルールを取得
        alias_df = spark.createDataFrame(records, schema)
        rules = [(re.compile(r.regex, re.I), r.canonical_name) for r in alias_df.collect()]
        bc_rules = spark.sparkContext.broadcast(rules)
        print(f"✅ Loaded {len(rules)} alias rules from fixed data")

        def rename_cols(df):
            cols = df.columns
            for pat, cannon in bc_rules.value:
                for c in cols:
                    if pat.match(c) and cannon not in cols:
                        df = df.withColumnRenamed(c, cannon)
                        cols.append(cannon)
                        print(f"  Renamed: {c} -> {cannon}")
            return df

        # ── ② 読み込み & リネーム
        print("Loading fund_master data...")
        v2 = rename_cols(spark.table("s3tables.brz_ingestion.fund_master"))
        print(f"V2 fund_master loaded: {v2.count()} rows")
        
        print("Loading legacy_fund_master data...")
        legacy = rename_cols(spark.table("s3tables.brz_ingestion.legacy_fund_master"))
        print(f"Legacy fund_master loaded: {legacy.count()} rows")

        # ── ③ 正規化 UDF
        @F.udf("string")
        def norm(s):
            if s is None: 
                return ""
            return re.sub(r"\s+", "", unicodedata.normalize("NFKC", s).lower())

        # V2データの正規化
        v2 = (v2.withColumn("fund_name_norm", norm("fund_name"))
                .withColumn("company_norm", norm("management_company"))
                .withColumn("nickname_norm", norm("nickname"))
                .withColumn("det_key", F.concat_ws("_", "fund_name_norm", "company_norm", "nickname_norm")))

        # Legacyデータの正規化
        legacy = (legacy.withColumn("fund_name_norm", norm("fund_name"))
                       .withColumn("company_norm", norm("management_company"))
                       .withColumn("nickname_norm", norm("nickname"))  # aliasもnicknameに統一
                       .withColumn("det_key", F.concat_ws("_", "fund_name_norm", "company_norm", "nickname_norm")))

        print("Data normalization completed")
        
        # デバッグ用出力
        print("\n=== V2 Sample Data ===")
        v2.select("fund_id", "fund_name", "management_company", "nickname", "det_key").show(5, truncate=False)
        
        print("\n=== Legacy Sample Data ===")
        legacy.select("fund_id", "fund_name", "management_company", "nickname", "det_key").show(5, truncate=False)
        
        return {"v2": v2, "legacy": legacy}
        
    def save_results(self, spark, results):
        """結果を複数のテーブルに保存"""
        v2_df = results["v2"]
        legacy_df = results["legacy"]
        
        # Namespace設定
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"
        
        # V2特徴量テーブル保存
        v2_table = f"s3tables.{namespace}.det_features_v2"
        print(f"Saving V2 features to {v2_table}")
        v2_df.write.mode("overwrite").format("iceberg").saveAsTable(v2_table)
        
        # Legacy特徴量テーブル保存
        legacy_table = f"s3tables.{namespace}.det_features_legacy"
        print(f"Saving Legacy features to {legacy_table}")
        legacy_df.write.mode("overwrite").format("iceberg").saveAsTable(legacy_table)
        
        print("✅ Deterministic feature tables saved successfully")

    def run(self):
        """メイン処理実行"""
        spark = self.glue_context.spark_session if self.glue_context else None
        if not spark:
            raise ValueError("Spark session not available")
            
        results = self.process(spark)
        self.save_results(spark, results)

def process_deterministic_features(config, args, glue_context=None, s3tables_catalog_name=None):
    processor = DeterministicFeaturesProcessor(config, args, glue_context, s3tables_catalog_name)
    processor.run()

if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = NameCollectionConfig(glue_args.get('source_bucket_name') or glue_args.get('source-bucket-name'))
    
    try:
        process_deterministic_features(config, args, glueContext, "s3tables")
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
