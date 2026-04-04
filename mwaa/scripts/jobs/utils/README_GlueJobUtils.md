"""
GlueJobUtils使用例とドキュメント

このユーティリティを使用することで、BranchGlueJobOperatorと連携したGlue Jobの
引数解析、Spark設定、S3 Tables設定を大幅に簡素化できます。

## 基本的な使用方法

### 1. 最もシンプルな使用方法（デフォルト設定）

```python
if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = MyJobConfig(glue_args.get('source_bucket_name'))
    
    try:
        my_job_function(config, args, glueContext)
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
```

### 2. カスタム引数を追加したい場合

```python
if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # カスタム引数を定義
    config = GlueJobConfig(
        additional_required_args=['custom-required-arg'],
        additional_optional_args=['custom-optional-arg', 'another-arg']
    )
    
    # セットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job(config)
    
    # カスタム引数にアクセス
    custom_value = glue_args.get('custom_required_arg')
    optional_value = glue_args.get('custom_optional_arg', 'default_value')
    
    try:
        my_job_function(glue_args, args, glueContext)
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
```

### 3. 段階的なセットアップが必要な場合

```python
if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 引数解析のみ
    config = GlueJobConfig()
    glue_args = GlueJobUtils.parse_arguments(config)
    
    # Glue Context初期化
    glueContext, spark, job = GlueJobUtils.initialize_glue_context(glue_args)
    
    # AWS情報取得
    account_id, aws_region = GlueJobUtils.get_aws_account_info(glue_args)
    
    # S3 Tables設定
    bucket_name = GlueJobUtils.configure_s3_tables(spark, glue_args, account_id, aws_region)
    
    # WAP設定
    GlueJobUtils.configure_wap(spark, glue_args)
    
    # 引数オブジェクト作成
    args = GlueJobArgs(glue_args)
    
    try:
        my_job_function(args, glueContext)
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
```

## 利用可能な引数

### 必須引数（デフォルト）
- JOB_NAME: Glue Job名
- source_bucket_name: ソースデータのS3バケット名
- catalog_database: カタログデータベース名
- table_bucket_name: テーブル用S3バケット名

### オプショナル引数（デフォルト）
- ingest-date: データ取り込み日（YYYY-MM-DD形式）
- env: 環境名（main, dev, staging等）
- master-data: マスターデータバージョン（v1, v2等）
- run-id: 実行ID
- extract-mode: 抽出モード（logical_date等）
- wap-enabled: WAP有効化フラグ（true/false）
- catalog: カタログ名
- warehouse: ウェアハウスパス
- openlineage-namespace: OpenLineage名前空間
- openlineage-job-name: OpenLineageジョブ名
- openlineage-run-id: OpenLineage実行ID
- aws-account-id: AWSアカウントID
- aws-region: AWSリージョン

## BranchGlueJobOperatorとの連携

このユーティリティは、BranchGlueJobOperatorから送信される以下の動的引数を自動処理します：
- --ingest-date: 論理日付
- --run-id: Airflow実行ID
- --env: ブランチ環境
- --e2e-mode: エンドツーエンドモード
- --extract-mode: 抽出モード
- --master-data: マスターデータバージョン
- --wap-enabled: WAP有効化
- --wap-branch: WAPブランチ名
- --openlineage-*: OpenLineage関連設定

## 設定される内容

### Spark設定
- S3 Tables Icebergカタログの設定
- デフォルトカタログをs3tablesに設定
- REST API設定（SigV4認証付き）

### WAP設定
- wap-enabled=trueの場合、WAP機能を有効化
- ブランチ名の設定

### 引数オブジェクト（GlueJobArgs）
- ingest_date: データ取り込み日
- env: 環境名
- master_data: マスターデータバージョン
- run_id: 実行ID
- extract_mode: 抽出モード
- wap_enabled: WAP有効化フラグ

## 従来コードからの移行

### Before（従来のコード）
```python
# 100行以上のボイラープレートコード
required_args = ['JOB_NAME', 'source_bucket_name', ...]
glue_args = getResolvedOptions(sys.argv, required_args)
# ... 引数解析 ...
# ... Glue Context初期化 ...
# ... S3 Tables設定 ...
# ... WAP設定 ...
```

### After（GlueJobUtils使用）
```python
# 1行でセットアップ完了
glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
```

これにより、コードの可読性が向上し、メンテナンス性が大幅に改善されます。
"""
