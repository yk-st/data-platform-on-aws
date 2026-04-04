from pyspark.sql import functions as F
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import current_date
from jobs.base_extractor import BaseExtractor
from jobs.fund.config import FundConfig

class FundNavExtractor(BaseExtractor):
    def __init__(self, config, args, glue_context=None, s3tables_catalog_name=None):
        super().__init__(config, args)
        self.glue_context = glue_context
        self.s3tables_catalog_name = s3tables_catalog_name
        
    def extract(self, spark):
        # パス構築のデバッグ情報
        source_path = f"{self.config.FUND_NAV_S3_SOURCE}_{self.args.master_data}.csv"
        
        df = (
            spark.read
                .option("header", "true")
                .option("inferSchema", "true")
                .csv(source_path)
        )
        
        # カラム名をS3 Tables用に英語名に変換
        # column_mapping = {
        #     "基準日": "base_date",
        #     "基準価格": "nav_price"
        # }
        
        # for old_col, new_col in column_mapping.items():
        #     if old_col in df.columns:
        #         df = df.withColumnRenamed(old_col, new_col)
        
        # reference_dateをdate型に変換
        df = df.withColumn(
            "base_date",
            F.to_date(F.col("base_date"), "yyyy-MM-dd")
        )
        
        # ingest_dateをdate型で追加
        ingest_date = self.args.ingest_date
        df = df.withColumn("ingest_date", F.lit(ingest_date).cast("date"))
        
        return df

    def target_table(self) -> str: 
        # S3 Tables統合で推奨される形式
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"
        return f"{namespace}.fund_nav"

def extract_fund_nav(config, args, glue_context=None, s3tables_catalog_name=None):
    extractor = FundNavExtractor(config, args, glue_context, s3tables_catalog_name)
    extractor.run("base_date")

if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = FundConfig(glue_args.get('source_bucket_name') or glue_args.get('source-bucket-name'))  # 両方の形式に対応
    
    try:
        extract_fund_nav(config, args, glueContext, "s3tables")
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
