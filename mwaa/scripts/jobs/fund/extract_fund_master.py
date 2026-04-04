import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from jobs.base_extractor import BaseExtractor
from jobs.fund.config import FundConfig

class FundMasterExtractor(BaseExtractor):
    def __init__(self, config, args, glue_context=None, s3tables_catalog_name=None):
        super().__init__(config, args)
        self.glue_context = glue_context
        self.s3tables_catalog_name = s3tables_catalog_name
    
    def extract(self, spark):
        # パス構築のデバッグ情報
        source_path = f"{self.config.FUND_MASTER_S3_SOURCE}_{self.args.master_data}.csv"
        print("=" * 50)
        print("🔍 DEBUG: File Path Construction")
        print("=" * 50)
        print(f"  config.FUND_MASTER_S3_SOURCE: {self.config.FUND_MASTER_S3_SOURCE}")
        print(f"  args.master_data: {self.args.master_data}")
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
        # column_mapping = {
        #     "投資信託_分類": "fund_category",
        #     "信託報酬_率": "trust_fee_rate", 
        #     "有効レコード": "is_active",
        #     "ファンド名": "fund_name",
        #     "ニックネーム": "nickname", 
        #     "運用会社": "management_company",
        #     "担当者氏名": "manager_name",
        #     "担当者メール": "manager_email"
        # }
        
        # for old_col, new_col in column_mapping.items():
        #     if old_col in df.columns:
        #         df = df.withColumnRenamed(old_col, new_col)
        
        # ingest_dateをdate型で追加（timestampではなくdate）
        ingest_date = self.args.ingest_date
        df = df.withColumn("ingest_date", F.lit(ingest_date).cast("date"))
        
        return df

    def target_table(self) -> str: 
        # S3 Tables統合で推奨される形式
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"
        return f"s3tables.{namespace}.fund_master"

def extract_fund_master(config, args, glue_context=None, s3tables_catalog_name=None):
    extractor = FundMasterExtractor(config, args, glue_context, s3tables_catalog_name)
    extractor.run()

if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = FundConfig(glue_args.get('source_bucket_name') or glue_args.get('source-bucket-name'))  # 両方の形式に対応
    
    try:
        extract_fund_master(config, args, glueContext, "s3tables")
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
