from abc import ABC, abstractmethod
from pyspark.sql import functions as F
from pyspark.sql import DataFrame


class BaseExtractor(ABC):
    """
    Glue対応のBase Extractor
    ・extract() で取得した DF に適切なスキーマが含まれていること
    ・S3 Tables (Iceberg) テーブルは PARTITIONED BY でパーティション対応
    """

    def __init__(self, config, args=None, glue_context=None):
        self.config = config
        self.args = args
        self.glue_context = glue_context

    def build(self, pal_key, subquery, fetch_size=1000, lower_bound="1", upper_bound="10000", num_partitions=4) -> dict[str, str]:
        """Return the dict you can hand to `.options()`."""

        # subquery の None チェック
        if subquery is None:
            raise ValueError("subquery cannot be None. Please provide a valid SQL subquery.")
        
        if not isinstance(subquery, str) or not subquery.strip():
            raise ValueError("subquery must be a non-empty string.")
        
        return {
            # connection
            "url":      self.config.POSTGRES_URL,
            "user":     self.config.POSTGRES_USER,
            "password": self.config.POSTGRES_PASSWORD,
            # SELECT * FROM public.orders WHERE logical_date > DATE '{wm}'のようなSQLを想定する
            "dbtable":  subquery,                  # push-down + watermark

            # chunking
            "fetchsize":        fetch_size,
            # parallel ingestion
            "partitionColumn":  pal_key,
            "lowerBound":       str(lower_bound),
            "upperBound":       str(upper_bound),
            "numPartitions":    num_partitions,

            # consistency (READ_COMMITTED is default – no need to set)
            # "isolationLevel": "READ_COMMITTED",
        }


    # ------- サブクラス実装 ---------------------------------
    @abstractmethod
    def extract(self, spark) -> DataFrame: ...
    @abstractmethod
    def target_table(self) -> str: ...
    # -------------------------------------------------------

    def run(self, part_col="ingest_date") -> None:
        # AWS Glue環境では既にsparkが利用可能
        if self.glue_context:
            spark = self.glue_context.spark_session
        else:
            # AWS Glue以外の環境ではエラー
            raise RuntimeError("AWS Glue環境でのみ実行可能です")

        df = self.extract(spark)

        # パーティションカラムの確認
        if part_col not in df.columns:
            raise ValueError(f"DataFrame に '{part_col}' 列がありません。")

        # S3 Tables (Iceberg) テーブルへパーティション単位で書き込み
        df.writeTo(self.target_table()) \
          .overwritePartitions()

        # Glue環境ではsparkを手動停止しない
        if not self.glue_context:
            spark.stop()

    def run_overwrite(self) -> None:
        # AWS Glue環境では既にsparkが利用可能
        if self.glue_context:
            spark = self.glue_context.spark_session
        else:
            # AWS Glue以外の環境ではエラー
            raise RuntimeError("AWS Glue環境でのみ実行可能です")

        df_raw = self.extract(spark)

        # S3 Tables (Iceberg) テーブルへ完全上書き
        df_raw.writeTo(self.target_table()) \
          .overwritePartitions()

        # AWS Glue環境ではsparkを手動停止しない
