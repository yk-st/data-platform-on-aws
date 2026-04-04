import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from jobs.base_extractor import BaseExtractor
from jobs.legacy.config import LegacyConfig

class LegacyFundMasterExtractor(BaseExtractor):
    def __init__(self, config, args, glue_context=None, s3tables_catalog_name=None):
        super().__init__(config, args)
        self.glue_context = glue_context
        self.s3tables_catalog_name = s3tables_catalog_name
    
    def extract(self, spark):
        # パス構築のデバッグ情報
        source_path = f"{self.config.LEGACY_FUND_MASTER_S3_SOURCE}.csv"
        print("=" * 50)
        print("🔍 DEBUG: Legacy File Path Construction")
        print("=" * 50)
        print(f"  config.LEGACY_FUND_MASTER_S3_SOURCE: {self.config.LEGACY_FUND_MASTER_S3_SOURCE}")
        print(f"  Final path: {source_path}")
        print("=" * 50)
        
        # S3 TablesのIcebergカタログを使用
        df = (
            spark.read
                .option("header", "true")
                .option("inferSchema", "true")
                .csv(source_path)
        )
        
        # カラム名をS3 Tables用に英語名に変換
        column_mapping = {
            "投資信託_分類": "fund_category",
            "信託報酬_率": "trust_fee_rate", 
            "有効レコード": "is_active",
            "ファンド名": "fund_name",
            "愛称": "alias_name",
            "運用会社": "management_company",
            "隠れコスト": "hidden_cost",
            "内部戦略コード": "internal_strategy_code"
        }
        
        for old_col, new_col in column_mapping.items():
            if old_col in df.columns:
                df = df.withColumnRenamed(old_col, new_col)
        
        # データ型変換
        df = df.withColumn("trust_fee_rate", F.col("trust_fee_rate").cast("decimal(5,2)"))
        df = df.withColumn("hidden_cost", F.col("hidden_cost").cast("decimal(5,2)"))
        df = df.withColumn("is_active", 
                          F.when(F.col("is_active") == "True", True)
                           .when(F.col("is_active") == "False", False)
                           .otherwise(F.col("is_active").cast("boolean")))
        
        # ingest_dateをdate型で追加
        ingest_date = self.args.ingest_date
        df = df.withColumn("ingest_date", F.lit(ingest_date).cast("date"))
        
        print("=" * 50)
        print("🔍 DEBUG: Legacy Data Schema")
        print("=" * 50)
        df.printSchema()
        print(f"Row count: {df.count()}")
        print("=" * 50)
        
        return df

    def target_table(self) -> str: 
        # S3 Tables統合で推奨される形式
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"
        return f"s3tables.{namespace}.legacy_fund_master"

def extract_legacy_fund_master(config, args, glue_context=None, s3tables_catalog_name=None):
    extractor = LegacyFundMasterExtractor(config, args, glue_context, s3tables_catalog_name)
    extractor.run()

if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = LegacyConfig(glue_args.get('source_bucket_name') or glue_args.get('source-bucket-name'))
    
    try:
        extract_legacy_fund_master(config, args, glueContext, "s3tables")
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
