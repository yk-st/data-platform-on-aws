#!/bin/bash

# S3バケット操作用の簡単なコマンド集
# 使用法: SUFFIX=yuki-sample ./s3-cleanup-commands.sh

# サフィックスの設定（デフォルト: yuki-sample）
SUFFIX=${SUFFIX:-yuki-sample}

echo "使用するサフィックス: $SUFFIX"
echo ""
echo "=== 利用可能なコマンド ==="
echo ""

# バケット名の定義
SOURCE_BUCKET="data-platform-source-$SUFFIX"
MWAA_BUCKET="data-platform-mwaa-management-$SUFFIX"
CLOUDTRAIL_BUCKET="data-platform-cloudtrail-audit-logs-$SUFFIX"
MACIE_BUCKET="data-platform-macie-results-$SUFFIX"
VPC_FLOW_LOGS_BUCKET="data-platform-vpc-flow-logs-$SUFFIX"

echo "1. バケット一覧確認:"
echo "aws s3 ls | grep data-platform"
echo ""

echo "2. 各バケットの内容とサイズ確認:"
echo "aws s3 ls s3://$SOURCE_BUCKET --recursive --human-readable --summarize"
echo "aws s3 ls s3://$MWAA_BUCKET --recursive --human-readable --summarize"
echo "aws s3 ls s3://$CLOUDTRAIL_BUCKET --recursive --human-readable --summarize"
echo "aws s3 ls s3://$MACIE_BUCKET --recursive --human-readable --summarize"
echo "aws s3 ls s3://$VPC_FLOW_LOGS_BUCKET --recursive --human-readable --summarize"
echo ""

echo "3. バケットを空にする:"
echo "aws s3 rm s3://$SOURCE_BUCKET --recursive"
echo "aws s3 rm s3://$MWAA_BUCKET --recursive"
echo "aws s3 rm s3://$CLOUDTRAIL_BUCKET --recursive"
echo "aws s3 rm s3://$MACIE_BUCKET --recursive"
echo "aws s3 rm s3://$VPC_FLOW_LOGS_BUCKET --recursive"
echo ""

echo "3b. バージョン付きオブジェクトの削除（バージョニング有効なバケット用）:"
cat << 'EOF'
# バージョン付きオブジェクトを削除（必要に応じて実行）
for bucket in SOURCE_BUCKET MWAA_BUCKET CLOUDTRAIL_BUCKET MACIE_BUCKET VPC_FLOW_LOGS_BUCKET; do
  echo "Deleting versions in $bucket..."
  aws s3api list-object-versions --bucket $bucket --output json | \
  jq -r '.Versions[]?, .DeleteMarkers[]? | select(.Key != null) | "\(.Key)\t\(.VersionId)"' | \
  while IFS=$'\t' read -r key version_id; do
    if [ -n "$key" ] && [ -n "$version_id" ]; then
      aws s3api delete-object --bucket $bucket --key "$key" --version-id "$version_id"
    fi
  done
done
EOF
echo ""

echo "4. バケットを削除する:"
echo "aws s3api delete-bucket --bucket $SOURCE_BUCKET"
echo "aws s3api delete-bucket --bucket $MWAA_BUCKET"
echo "aws s3api delete-bucket --bucket $CLOUDTRAIL_BUCKET"
echo "aws s3api delete-bucket --bucket $MACIE_BUCKET"
echo "aws s3api delete-bucket --bucket $VPC_FLOW_LOGS_BUCKET"
echo ""

echo "5. 一括操作用スクリプト:"
echo ""
echo "=== 全バケットチェック ==="
cat << EOF
for bucket in $SOURCE_BUCKET $MWAA_BUCKET $CLOUDTRAIL_BUCKET $MACIE_BUCKET $VPC_FLOW_LOGS_BUCKET; do
  echo "=== \$bucket ==="
  aws s3 ls s3://\$bucket --recursive --summarize | tail -2
  echo ""
done
EOF
echo ""

echo "=== 全バケット削除（実行前に内容確認必須！） ==="
cat << EOF
# ステップ1: 全バケットを空にする
aws s3 rm s3://$SOURCE_BUCKET --recursive
aws s3 rm s3://$MWAA_BUCKET --recursive
aws s3 rm s3://$CLOUDTRAIL_BUCKET --recursive
aws s3 rm s3://$MACIE_BUCKET --recursive
aws s3 rm s3://$VPC_FLOW_LOGS_BUCKET --recursive

# ステップ1b: バージョン付きオブジェクトの削除（バージョニング有効な場合）
for bucket in $SOURCE_BUCKET $MWAA_BUCKET $CLOUDTRAIL_BUCKET $MACIE_BUCKET $VPC_FLOW_LOGS_BUCKET; do
  echo "Deleting versions in \$bucket..."
  aws s3api list-object-versions --bucket \$bucket --output json | \\
  jq -r '.Versions[]?, .DeleteMarkers[]? | select(.Key != null) | "\\(.Key)\\t\\(.VersionId)"' | \\
  while IFS=\$'\\t' read -r key version_id; do
    if [ -n "\$key" ] && [ -n "\$version_id" ]; then
      aws s3api delete-object --bucket \$bucket --key "\$key" --version-id "\$version_id"
    fi
  done
done

# ステップ2: 全バケットを削除
aws s3api delete-bucket --bucket $SOURCE_BUCKET
aws s3api delete-bucket --bucket $MWAA_BUCKET
aws s3api delete-bucket --bucket $CLOUDTRAIL_BUCKET
aws s3api delete-bucket --bucket $MACIE_BUCKET
aws s3api delete-bucket --bucket $VPC_FLOW_LOGS_BUCKET
EOF
echo ""

echo "使用例:"
echo "  SUFFIX=test-env $0           # test-env サフィックスで実行"
echo "  SUFFIX=prod $0               # prod サフィックスで実行"
echo "  $0                           # デフォルト（yuki-sample）で実行"
