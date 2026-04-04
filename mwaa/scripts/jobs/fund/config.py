import os
import argparse

class FundConfig:
    def __init__(self, source_bucket_name=None):
        # AWS Glue環境用の設定
        self.CATALOG_NAME = "data_platform_catalog"
        
        # Namespace名
        self.BRONZE_NAMESPACE = "brz_ingestion"
        # self.SILVER_NAMESPACE = "slv_analytics"
        # self.GOLD_NAMESPACE = "gld_presentation"
        # self.GLD_FUND_NAMESPACE = "gld_fund"
        
        # テーブル名（Glue Catalog + Iceberg用）
        self.TABLE_FUND_NAV = f"glue_catalog.{self.BRONZE_NAMESPACE}.fund_nav"
        self.TABLE_FUND_MASTER = f"glue_catalog.{self.BRONZE_NAMESPACE}.fund_master"
        # self.TABLE_DIM_FUND = f"glue_catalog.{self.GLD_FUND_NAMESPACE}.dim_fund"
        # self.TABLE_DIM_DATE = f"glue_catalog.{self.GLD_FUND_NAMESPACE}.dim_date"

        # self.TABLE_FCT_FUND_PERFORMANCE = f"glue_catalog.{self.GLD_FUND_NAMESPACE}.fct_fund_performance"
        # self.TABLE_FUND_DAILY_WIDE = f"glue_catalog.{self.SILVER_NAMESPACE}.fund_daily_wide"

        # AWS S3パス（AWS Glue用）
        # source_bucket_nameが提供されている場合はそれを使用、そうでなければ環境変数から取得
        self.FUND_MASTER_S3_SOURCE = f"s3://{source_bucket_name}/fund/fund_master"
        self.FUND_NAV_S3_SOURCE = f"s3://{source_bucket_name}/fund/fund_nav"

        self.ICEBERG_TABLES = [
            self.TABLE_FUND_NAV,
            self.TABLE_FUND_MASTER,
            # self.TABLE_FUND_DAILY_WIDE,
            # self.TABLE_DIM_FUND,
            # self.TABLE_DIM_DATE,
            # self.TABLE_FCT_FUND_PERFORMANCE
        ]
    
    @staticmethod
    def parse_args():
        """AWS Glue Job用の引数パーサー"""
        parser = argparse.ArgumentParser()
        parser.add_argument('--ingest-date', required=True)
        parser.add_argument('--run-id', required=True)
        parser.add_argument('--env', default='main')
        parser.add_argument('--master-data', default='v1')
        parser.add_argument('--wap-enabled', default='false')
        return parser.parse_args()