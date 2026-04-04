"""
Glue Job共通ユーティリティ
BranchGlueJobOperatorと連携した引数解析、Spark設定、S3 Tables設定の共通化
"""
import sys
import boto3
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from datetime import datetime
from typing import Dict, List, Any, Optional


class GlueJobConfig:
    """Glue Job設定クラス"""
    
    # 共通の必須引数
    REQUIRED_ARGS = [
        'JOB_NAME',
        'source_bucket_name', 
        'catalog_database',
        'table_bucket_name'
    ]
    
    # 共通のオプショナル引数
    OPTIONAL_ARGS = [
        'ingest-date',
        'env',
        'master-data',
        'run-id',
        'extract-mode',
        'wap-enabled',
        'catalog',
        'warehouse',
        'openlineage-namespace',
        'openlineage-job-name',
        'openlineage-run-id',
        'aws-account-id',
        'aws-region'
    ]

    def __init__(self, additional_required_args: List[str] = None, additional_optional_args: List[str] = None):
        """
        Args:
            additional_required_args: 追加の必須引数
            additional_optional_args: 追加のオプショナル引数
        """
        self.required_args = self.REQUIRED_ARGS.copy()
        self.optional_args = self.OPTIONAL_ARGS.copy()
        
        if additional_required_args:
            self.required_args.extend(additional_required_args)
        if additional_optional_args:
            self.optional_args.extend(additional_optional_args)


class GlueJobArgs:
    """Glue Job引数オブジェクト"""
    
    def __init__(self, glue_args: Dict[str, Any]):
        self.ingest_date = glue_args.get('ingest_date') or glue_args.get('ingest-date', datetime.now().strftime('%Y-%m-%d'))
        self.env = glue_args.get('env', 'main')
        self.master_data = glue_args.get('master_data') or glue_args.get('master-data', 'v1')
        self.run_id = glue_args.get('run_id') or glue_args.get('run-id', 'unknown')
        self.extract_mode = glue_args.get('extract_mode') or glue_args.get('extract-mode', 'logical_date')
        self.wap_enabled = glue_args.get('wap_enabled') or glue_args.get('wap-enabled', 'false')


class GlueJobUtils:
    """Glue Job共通ユーティリティ"""
    
    @staticmethod
    def parse_arguments(config: GlueJobConfig) -> Dict[str, Any]:
        """
        Glue Job引数を解析する
        
        Args:
            config: GlueJobConfig インスタンス
            
        Returns:
            解析された引数辞書
        """
        try:
            # 必須引数のみをgetResolvedOptionsで取得
            glue_args = getResolvedOptions(sys.argv, config.required_args)
            
            # オプショナル引数を手動で解析
            all_args = {}
            all_args.update(glue_args)
            
            # sys.argvからオプショナル引数を抽出
            for i, arg in enumerate(sys.argv):
                if arg.startswith('--'):
                    key = arg[2:]  # '--'を削除
                    # ハイフンをアンダースコアに変換してキーを統一
                    normalized_key = key.replace('-', '_')
                    if normalized_key in [opt.replace('-', '_') for opt in config.optional_args]:
                        # 次の引数が値
                        if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                            all_args[normalized_key] = sys.argv[i + 1]
                        else:
                            all_args[normalized_key] = 'true'  # フラグとして扱う
            
            glue_args = all_args
            
            print("=" * 50)
            print("🔧 GLUE JOB RECEIVED ARGUMENTS:")
            print("=" * 50)
            for key, value in glue_args.items():
                print(f"  {key}: {value}")
            print("=" * 50)
            
            return glue_args
            
        except Exception as e:
            print(f"Error parsing arguments: {e}")
            print("Available sys.argv:", sys.argv)
            sys.exit(1)

    @staticmethod
    def initialize_glue_context(glue_args: Dict[str, Any]) -> tuple:
        """
        Glue Context を初期化する
        
        Args:
            glue_args: 解析されたGlue引数
            
        Returns:
            (glueContext, spark, job) のタプル
        """
        sc = SparkContext()
        glueContext = GlueContext(sc)
        spark = glueContext.spark_session
        job = Job(glueContext)
        job.init(glue_args['JOB_NAME'], glue_args)
        
        return glueContext, spark, job

    @staticmethod
    def get_aws_account_info(glue_args: Dict[str, Any]) -> tuple:
        """
        AWSアカウント情報を取得する
        
        Args:
            glue_args: 解析されたGlue引数
            
        Returns:
            (account_id, aws_region) のタプル
        """
        # AWSアカウントIDとリージョン情報をGlue引数から取得
        account_id = glue_args.get('aws_account_id')
        aws_region = glue_args.get('aws_region', 'ap-northeast-1')  # デフォルトはap-northeast-1
        
        if not account_id:
            print("⚠️ aws_account_id not found in Glue arguments, trying STS...")
            try:
                sts = boto3.client('sts')
                account_id = sts.get_caller_identity()['Account']
                print(f"✅ Account ID retrieved from STS: {account_id}")
            except Exception as e:
                print(f"❌ Failed to get account ID from STS: {e}")
                raise ValueError("aws_account_id is required but not available")
        else:
            print(f"✅ Account ID from Glue args: {account_id}")
        
        print(f"✅ AWS Region from Glue args: {aws_region}")
        
        return account_id, aws_region

    @staticmethod
    def configure_s3_tables(spark, glue_args: Dict[str, Any], account_id: str, aws_region: str) -> str:
        """
        S3 Tables用のカタログ設定を行う
        
        Args:
            spark: Spark Session
            glue_args: 解析されたGlue引数
            account_id: AWSアカウントID
            aws_region: AWSリージョン
            
        Returns:
            S3 Tables バケット名
        """
        raw_bucket_name = glue_args.get('table_bucket_name', 'data-platform-iceberg-managed-yuki-sample')
        
        # ARNの場合はバケット名部分のみを抽出
        if raw_bucket_name.startswith('arn:aws:s3tables:'):
            s3tables_bucket_name = raw_bucket_name.split('/')[-1]
        else:
            s3tables_bucket_name = raw_bucket_name
        
        print("🔍 DEBUG: S3 Tables Configuration:")
        print(f"  Raw table_bucket_name: {raw_bucket_name}")
        print(f"  Extracted bucket name: {s3tables_bucket_name}")
        print(f"  Account ID: {account_id}")
        print(f"  AWS Region: {aws_region}")
        print("=" * 50)
        
        # AWS Analytics Services Integration形式でカタログ設定
        spark.conf.set("spark.sql.defaultCatalog", "s3tables")
        spark.conf.set("spark.sql.catalog.s3tables", "org.apache.iceberg.spark.SparkCatalog")
        spark.conf.set("spark.sql.catalog.s3tables.type", "rest")
        spark.conf.set("spark.sql.catalog.s3tables.uri", f"https://s3tables.{aws_region}.amazonaws.com/iceberg")
        spark.conf.set("spark.sql.catalog.s3tables.warehouse", f"arn:aws:s3tables:{aws_region}:{account_id}:bucket/{s3tables_bucket_name}")
        spark.conf.set("spark.sql.catalog.s3tables.rest.sigv4-enabled", "true")
        spark.conf.set("spark.sql.catalog.s3tables.rest.signing-name", "s3tables")
        spark.conf.set("spark.sql.catalog.s3tables.rest.signing-region", aws_region)
        spark.conf.set("spark.sql.catalog.s3tables.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        spark.conf.set('spark.sql.catalog.s3tables.rest-metrics-reporting-enabled','false')
        
        print("📋 S3 Tables Catalog Configuration:")
        print(f"  S3Tables Catalog: s3tables")
        print(f"  Region: {aws_region}")
        print(f"  Warehouse: arn:aws:s3tables:{aws_region}:{account_id}:bucket/{s3tables_bucket_name}")
        print(f"  Glue ID: {account_id}:s3tablescatalog/{s3tables_bucket_name}")
        
        return s3tables_bucket_name

    @staticmethod
    def configure_wap(spark, glue_args: Dict[str, Any]) -> None:
        """
        WAP (Write-Audit-Publish) 設定を行う
        
        Args:
            spark: Spark Session
            glue_args: 解析されたGlue引数
        """
        wap_enabled = glue_args.get('wap-enabled') or glue_args.get('wap_enabled')
        if wap_enabled == 'true':
            spark.conf.set("spark.wap.enabled", "true")
            wap_branch = glue_args.get('wap-branch') or glue_args.get('wap_branch', 'main')
            spark.conf.set("spark.wap.branch", wap_branch)
            print(f"✅ WAP enabled with branch: {wap_branch}")

    @staticmethod
    def setup_glue_job(config: GlueJobConfig = None) -> tuple:
        """
        Glue Job の完全セットアップを行う
        
        Args:
            config: GlueJobConfig インスタンス（デフォルト設定を使用する場合はNone）
            
        Returns:
            (glueContext, spark, job, glue_args, args) のタプル
        """
        if config is None:
            config = GlueJobConfig()
        
        # 引数解析
        glue_args = GlueJobUtils.parse_arguments(config)
        
        # Glue Context 初期化
        glueContext, spark, job = GlueJobUtils.initialize_glue_context(glue_args)
        
        # AWS情報取得
        account_id, aws_region = GlueJobUtils.get_aws_account_info(glue_args)
        
        # S3 Tables設定
        s3tables_bucket_name = GlueJobUtils.configure_s3_tables(spark, glue_args, account_id, aws_region)
        
        # WAP設定
        GlueJobUtils.configure_wap(spark, glue_args)
        
        # カタログ名をGlue引数に追加
        glue_args['s3tables_catalog_name'] = "s3tables"
        
        # 引数オブジェクト作成
        args = GlueJobArgs(glue_args)
        
        return glueContext, spark, job, glue_args, args
