"""
probabilistic_scoring_refactored.py – MinHashLSH (Spark ML) 構造化版
====================================================================
* fund_name と mgmt_company の **両方を比較** するよう改訂。
  正規化済み `fund_name_norm` + `company_norm` を連結 → Tokenizer → LSH。
* fee_diff を保持しつつ S3 Tables に保存。
* ML要素を関数分けして構造化。
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F, types as T
from pyspark.ml.feature import RegexTokenizer, HashingTF, MinHashLSH
from jobs.name_collection.config import NameCollectionConfig
from typing import Tuple

# =============================================================================
# パラメータ定数
# =============================================================================
class MLParams:
    """機械学習/前処理パラメータ（要チューニング）"""

    # 日本語トークナイザー用正規表現（語の“かたまり”）
    TOKENIZER_PATTERN = r"[\p{IsHan}]+|[\p{IsHiragana}]+|[\p{IsKatakana}]+|[A-Za-z0-9]+"

    # HashingTF の次元数（大きいほど衝突↓だがメモリ/シャッフル↑）
    TF_NUM_FEATURES = 512     # 実運用は 16384〜32768 推奨（目安）

    # MinHashLSH のハッシュ表の数（再現率↔コストのツマミ）
    LSH_NUM_HASH_TABLES = 8

    # Jaccard「距離」のしきい値（0=完全一致、1=完全不一致）
    # 1.0 は “バケツ一致した候補をほぼ全件” 拾う設定
    SIMILARITY_THRESHOLD = 1.0


class ProbabilisticScoringProcessor:
    def __init__(self, config, args, glue_context=None, s3tables_catalog_name=None):
        self.config = config
        self.args = args
        self.glue_context = glue_context
        self.s3tables_catalog_name = s3tables_catalog_name

    def load_and_preprocess_data(self, spark) -> Tuple:
        """
        データ読み込みと前処理
        
        Returns:
            Tuple: (v2_processed, legacy_processed)
        """
        # Namespace設定
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"
        
        # 1. 特徴量テーブル読み込み
        v2 = spark.table(f"s3tables.{namespace}.det_features_v2")
        legacy = spark.table(f"s3tables.{namespace}.det_features_legacy")
        
        # 2. 決定論ペアを除外
        pairs = (
            v2.select(F.col("fund_id").alias("v2_id"), "det_key")
                  .join(
                      legacy.select(F.col("fund_id").alias("lg_id"), "det_key"),
                      on="det_key",
                      how="inner")
        )
        
        v2_un = v2.join(pairs, v2.fund_id == pairs.v2_id, "left_anti")
        legacy_un = legacy.join(pairs, legacy.fund_id == pairs.lg_id, "left_anti")
        
        # 3. テキスト特徴量作成（fund_name + company + nickname）
        def create_text_features(df):
            return (df
                    .withColumn("nickname_norm", F.coalesce(F.col("nickname_norm"), F.lit("")))
                    .withColumn("text", F.concat_ws(" ", "fund_name_norm", "company_norm", "nickname_norm")))
        
        v2_processed = create_text_features(v2_un)
        legacy_processed = create_text_features(legacy_un)
        
        return v2_processed, legacy_processed

    def create_feature_transformers(self):
        """
        特徴量変換パイプラインの作成
        
        Returns:
            Tuple: (tokenizer, hashing_tf)
        """
        # 日本語用トークナイザー
        tokenizer = RegexTokenizer(
            inputCol="text",
            outputCol="tokens",
            pattern=MLParams.TOKENIZER_PATTERN,
            gaps=False,
            toLowercase=False
        )
        
        # ハッシュTF
        hashing_tf = HashingTF(
            inputCol="tokens", 
            outputCol="tf", 
            numFeatures=MLParams.TF_NUM_FEATURES
        )
        
        return tokenizer, hashing_tf

    def transform_features(self, df, tokenizer, hashing_tf):
        """
        データフレームに特徴量変換を適用
        
        Args:
            df: 入力データフレーム
            tokenizer: トークナイザー
            hashing_tf: ハッシュTF変換器
            
        Returns:
            変換済みデータフレーム
        """
        return hashing_tf.transform(tokenizer.transform(df))

    def train_lsh_model(self, v2_tf, legacy_tf):
        """
        MinHashLSHモデルの学習
        
        Args:
            v2_tf: v2特徴量データフレーム
            legacy_tf: legacy特徴量データフレーム
            
        Returns:
            学習済みLSHモデル
        """
        # 両方のデータを結合してモデル学習
        combined = v2_tf.select("tf").unionByName(legacy_tf.select("tf"))
        
        lsh_model = MinHashLSH(
            inputCol="tf", 
            outputCol="hashes", 
            numHashTables=MLParams.LSH_NUM_HASH_TABLES
        ).fit(combined)
        
        return lsh_model

    def predict_similarity(self, lsh_model, v2_tf, legacy_tf):
        """
        類似度予測とマッチング
        
        Args:
            lsh_model: 学習済みLSHモデル
            v2_tf: v2特徴量データフレーム
            legacy_tf: legacy特徴量データフレーム
            
        Returns:
            類似度マッチング結果
        """
        # LSH変換適用
        v2_vec = lsh_model.transform(v2_tf)
        legacy_vec = lsh_model.transform(legacy_tf)
        
        # 類似度計算（Jaccard距離）
        matches = (
            lsh_model.approxSimilarityJoin(
                v2_vec, legacy_vec, 
                MLParams.SIMILARITY_THRESHOLD, 
                distCol="jaccard_dist"
            )
            .select(
                F.col("datasetA.fund_id").alias("fund_id_v2"),
                F.col("datasetB.fund_id").alias("fund_id_legacy"),
                "jaccard_dist"
            )
        )
        
        return matches

    def add_fee_difference(self, matches, v2_processed, legacy_processed):
        """
        手数料差分を追加
        
        Args:
            matches: マッチング結果
            v2_processed: v2処理済みデータ
            legacy_processed: legacy処理済みデータ
            
        Returns:
            手数料差分付きマッチング結果
        """
        return (
            matches
            .join(
                v2_processed.select(
                    F.col("fund_id").alias("fid_v2"),
                    F.col("trust_fee_rate").alias("trust_fee_rate_v2")
                ),
                matches.fund_id_v2 == F.col("fid_v2")
            )
            .join(
                legacy_processed.select(
                    F.col("fund_id").alias("fid_lg"),
                    F.col("trust_fee_rate").alias("trust_fee_rate_lg")
                ),
                matches.fund_id_legacy == F.col("fid_lg")
            )
            .withColumn("fee_diff", F.abs(F.col("trust_fee_rate_v2") - F.col("trust_fee_rate_lg")))
            .drop("trust_fee_rate_v2", "trust_fee_rate_lg", "fid_v2", "fid_lg")
        )

    def process(self, spark):
        """
        確率的マッチング処理のメイン関数
        
        Args:
            spark: SparkSession
            
        Returns:
            最終的なマッチング結果
        """
        print("=" * 50)
        print("🚀 確率的スコアリング処理開始")
        print("=" * 50)
        
        # 1. データ前処理
        print("📊 データ読み込みと前処理...")
        v2_processed, legacy_processed = self.load_and_preprocess_data(spark)
        
        # 2. 特徴量変換器作成
        print("🔧 特徴量変換器作成...")
        tokenizer, hashing_tf = self.create_feature_transformers()
        
        # 3. 特徴量変換
        print("🔄 特徴量変換実行...")
        v2_tf = self.transform_features(v2_processed, tokenizer, hashing_tf)
        legacy_tf = self.transform_features(legacy_processed, tokenizer, hashing_tf)
        
        # 4. モデル学習
        print("🎯 LSHモデル学習...")
        lsh_model = self.train_lsh_model(v2_tf, legacy_tf)
        
        # 5. 類似度予測
        print("🔍 類似度予測...")
        matches = self.predict_similarity(lsh_model, v2_tf, legacy_tf)
        
        # 6. 手数料差分追加
        print("💰 手数料差分計算...")
        final_matches = self.add_fee_difference(matches, v2_processed, legacy_processed)
        
        print("✅ 確率的スコアリング処理完了!")
        return final_matches
        
    def save_results(self, spark, results):
        """結果をS3 Tablesに保存"""
        # Namespace設定
        namespace = "brz_ingestion" if self.args.env == "main" else f"brz_ingestion_{self.args.env}"

        # マッチング結果テーブル保存
        match_table = f"s3tables.{namespace}.probabilistic_match_scores"
        print(f"Saving probabilistic match scores to {match_table}")
        results.write.mode("overwrite").format("iceberg").saveAsTable(match_table)
        
        print("✅ Probabilistic match scores saved successfully")

    def run(self):
        """メイン処理実行"""
        spark = self.glue_context.spark_session if self.glue_context else None
        if not spark:
            raise ValueError("Spark session not available")
            
        results = self.process(spark)
        self.save_results(spark, results)
        
        # 結果サマリー表示
        print(f"\n� 総マッチング数: {results.count()}")
        print("\n� マッチング結果サンプル:")
        results.show(10, truncate=False)
        print("\n🎯 Jaccard距離分布:")
        results.select("jaccard_dist").describe().show()

def process_probabilistic_scoring(config, args, glue_context=None, s3tables_catalog_name=None):
    processor = ProbabilisticScoringProcessor(config, args, glue_context, s3tables_catalog_name)
    processor.run()

if __name__ == "__main__":
    from jobs.utils.glue_job_utils import GlueJobUtils, GlueJobConfig
    
    # 共通ユーティリティを使用してGlue Jobをセットアップ
    glueContext, spark, job, glue_args, args = GlueJobUtils.setup_glue_job()
    
    # 設定オブジェクトを作成
    config = NameCollectionConfig(glue_args.get('source_bucket_name') or glue_args.get('source-bucket-name'))
    
    try:
        process_probabilistic_scoring(config, args, glueContext, "s3tables")
        job.commit()
    except Exception as e:
        print(f"Job failed: {e}")
        raise e
