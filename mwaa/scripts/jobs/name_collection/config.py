import os
import argparse

class NameCollectionConfig:
    def __init__(self, source_bucket_name=None):
        # AWS Glue環境用の設定
        self.CATALOG_NAME = "data_platform_catalog"
        
        # Namespace名
        self.BRONZE_NAMESPACE = "brz_ingestion"
        # self.SILVER_NAMESPACE = "slv_analytics"
        # self.GOLD_NAMESPACE = "gld_presentation"
        self.REF_NAMESPACE = "ref"
        
        # テーブル名（S3 Tables用）
        self.TABLE_FUND_MASTER = f"s3tables.{self.BRONZE_NAMESPACE}.fund_master"
        self.TABLE_LEGACY_FUND_MASTER = f"s3tables.{self.BRONZE_NAMESPACE}.legacy_fund_master"
        self.TABLE_COLUMN_ALIAS_MAP = f"s3tables.{self.REF_NAMESPACE}.column_alias_map"
        
        # 決定論的特徴量テーブル
        self.TABLE_DET_FEATURES_V2 = f"s3tables.{self.BRONZE_NAMESPACE}.det_features_v2"
        self.TABLE_DET_FEATURES_LEGACY = f"s3tables.{self.BRONZE_NAMESPACE}.det_features_legacy"
        self.TABLE_DETERMINISTIC_PAIRS = f"s3tables.{self.BRONZE_NAMESPACE}.deterministic_pairs"

        self.ICEBERG_TABLES = [
            self.TABLE_FUND_MASTER,
            self.TABLE_LEGACY_FUND_MASTER,
            self.TABLE_COLUMN_ALIAS_MAP,
            self.TABLE_DET_FEATURES_V2,
            self.TABLE_DET_FEATURES_LEGACY,
            self.TABLE_DETERMINISTIC_PAIRS
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
