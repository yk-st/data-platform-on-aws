import os
import argparse

class LegacyConfig:
    def __init__(self, source_bucket_name=None):
        # AWS Glue環境用の設定
        self.CATALOG_NAME = "data_platform_catalog"
        
        # Namespace名
        self.BRONZE_NAMESPACE = "brz_ingestion"
        # self.SILVER_NAMESPACE = "slv_analytics"
        # self.GOLD_NAMESPACE = "gld_presentation"
        # self.GLD_LEGACY_NAMESPACE = "gld_legacy"
        
        # テーブル名（Glue Catalog + Iceberg用）
        self.TABLE_LEGACY_FUND_MASTER = f"glue_catalog.{self.BRONZE_NAMESPACE}.legacy_fund_master"

        # AWS S3パス（AWS Glue用）
        # source_bucket_nameが提供されている場合はそれを使用、そうでなければ環境変数から取得
        self.LEGACY_FUND_MASTER_S3_SOURCE = f"s3://{source_bucket_name}/legacy/legacy_fund_master"

        self.ICEBERG_TABLES = [
            self.TABLE_LEGACY_FUND_MASTER
        ]
    
    @staticmethod
    def parse_args():
        """AWS Glue Job用の引数パーサー"""
        parser = argparse.ArgumentParser()
        parser.add_argument('--ingest-date', required=True)
        parser.add_argument('--run-id', required=True)
        parser.add_argument('--env', default='main')
        parser.add_argument('--wap-enabled', default='false')
        return parser.parse_args()
