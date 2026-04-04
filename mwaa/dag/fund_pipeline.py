"""
Fund Pipeline for AWS Glue Jobs
MWAA環境でAWS Glue Jobsを使用したファンドデータパイプライン
"""

import os
import sys
from datetime import datetime, timedelta
from airflow import Dataset
from airflow.decorators import dag, task
from airflow.models.param import Param

# MWAA環境でのカスタムモジュールインポート（ローカル環境と同じパターン）
from utils.BranchGlueJobOperator import BranchGlueJobOperator

# MWAA環境では環境変数から設定を取得
ENV = os.environ.get('MWAA_ENV', 'prod')
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'data-platform')
BUCKET_SUFFIX = os.environ.get('BUCKET_SUFFIX', 'yuki-sample')
# AWSリージョンとアカウントIDはTerraformのGlue Job定義から自動的に渡される

# Dataset helper functions (MWAA用に簡素化)
def create_dataset(table_name: str, env: str = "main") -> Dataset:
    """S3 Tables用のDataset URIを生成"""
    namespace = "brz_raw" if "master" in table_name or "nav" in table_name else "gld_fund"
    return Dataset(f"s3tables://data-platform-iceberg-managed-{BUCKET_SUFFIX}/{namespace}/{table_name}")

def create_s3_dataset(s3_path: str, env: str = "main") -> Dataset:
    """S3 Dataset URIを生成"""
    return Dataset(f"s3://{s3_path}")

# Configuration (MWAA用に簡素化)
class SimpleConfig:
    def __init__(self):
        self.FUND_MASTER_S3_SOURCE = f"data-platform-source-{BUCKET_SUFFIX}/fund/fund_master"
        self.FUND_NAV_S3_SOURCE = f"data-platform-source-{BUCKET_SUFFIX}/fund/fund_nav"
        
        # Table names (英語名)
        self.TABLE_FUND_MASTER = "fund_master"
        self.TABLE_FUND_NAV = "fund_nav"
        self.TABLE_FUND_DAILY_WIDE = "fund_daily_wide"
        self.TABLE_DIM_DATE = "dim_date"
        self.TABLE_DIM_FUND = "dim_fund"
        self.TABLE_FCT_FUND_PERFORMANCE = "fct_fund_performance"

# DAG 定義
@dag(
    dag_id="fund_pipeline",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["fund", "glue", "s3tables"],
    max_active_runs=1,
    default_args={
        "owner": "data-team",
        "retries": 0,
        "retry_delay": timedelta(minutes=5),
        "sla": timedelta(hours=2),
    },
    params={
        "master_data": Param(default="v1", type="string"),
    },
    doc_md="""
    # Fund Pipeline (AWS Glue版)
    ファンドデータの抽出・変換・集計パイプライン
    
    ## データフロー
    1. Fund Master/NAV データ抽出
    2. ワイドテーブル変換
    3. ディメンション・ファクトテーブル集計
    """,
    render_template_as_native_obj=True
)
def fund_pipeline():
    config = SimpleConfig()

    # Dataset 定義（参照用）
    fund_daily_wide_ds = create_dataset(config.TABLE_FUND_DAILY_WIDE, ENV)
    fund_master_ds = create_dataset(config.TABLE_FUND_MASTER, ENV)
    fund_nav_ds = create_dataset(config.TABLE_FUND_NAV, ENV)
    fund_dim_date_ds = create_dataset(config.TABLE_DIM_DATE, ENV)
    fund_dim_fund_ds = create_dataset(config.TABLE_DIM_FUND, ENV)
    fund_fct_fund_performance_ds = create_dataset(config.TABLE_FCT_FUND_PERFORMANCE, ENV)

    fund_master = create_s3_dataset(config.FUND_MASTER_S3_SOURCE, ENV)
    fund_nav = create_s3_dataset(config.FUND_NAV_S3_SOURCE, ENV)

    # Fund Master Data 抽出
    t_extract_fund_master = BranchGlueJobOperator.submit(
        task_id="extract_fund_master",
        job_name=f"data-platform-extract-fund-master-{BUCKET_SUFFIX}",
        inlets=[fund_master],
        outlets=[fund_master_ds],
        script_args={
            # 静的引数（Terraformから来る）
            "--source-bucket-name": f"data-platform-source-{BUCKET_SUFFIX}",
            "--catalog-database": "data_platform_catalog",
            # --table-bucket-name, --aws-region, --aws-account-id はTerraformのdefault_argumentsから自動設定
            
            # BranchGlueJobOperatorで動的に追加される引数:
            # "--ingest-date", "--run-id", "--env", "--e2e-mode", 
            # "--extract-mode", "--master-data", "--catalog", "--warehouse"
        }
    )

    # Fund NAV Data 抽出
    # t_extract_fund_nav = BranchGlueJobOperator.submit(
    #     task_id="extract_fund_nav",
    #     job_name=f"data-platform-extract-fund-nav-{BUCKET_SUFFIX}",
    #     inlets=[fund_nav],
    #     outlets=[fund_nav_ds],
    #     script_args={
    #         # 静的引数（Terraformから来る）
    #         "--source-bucket-name": f"data-platform-source-{BUCKET_SUFFIX}",
    #         "--catalog-database": "data_platform_catalog",
    #         # --table-bucket-name, --aws-region, --aws-account-id はTerraformのdefault_argumentsから自動設定
    #     }
    # )

    # # パフォーマンス集計（スタースキーマ作成）
    # t_aggregate_performance = BranchGlueJobOperator.submit(
    #     task_id="aggregate_performance",
    #     job_name=f"data-platform-aggregate-performance-{BUCKET_SUFFIX}",
    #     inlets=[fund_master_ds, fund_nav_ds],
    #     outlets=[fund_dim_date_ds, fund_dim_fund_ds, fund_fct_fund_performance_ds],
    #     script_args={
    #         # 静的引数（Terraformから来る）
    #         "--source-bucket-name": f"data-platform-source-{BUCKET_SUFFIX}",
    #         "--catalog-database": "data_platform_catalog",
    #         # --table-bucket-name, --aws-region, --aws-account-id はTerraformのdefault_argumentsから自動設定
    #     }
    # )

    # タスク依存関係の連結（ワイドテーブル変換をスキップ）
    [t_extract_fund_master]

# DAG登録
fund_pipeline()
