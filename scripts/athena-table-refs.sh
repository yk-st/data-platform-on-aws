#!/usr/bin/env bash
# athena-table-refs.sh — Athenaのクエリ本文をAPIから取得し、FROM/JOINに出たテーブルを日別集計
# 依存: awscli v2, jq 1.6
set -euo pipefail

WG="${WG:-data-platform-workgroup}"             # 対象Athenaワークグループ
LIMIT="${LIMIT:-1000}"          # 取得最大クエリ数（50件/ページ）
REGION="${AWS_REGION:-ap-northeast-1}"

echo "[INFO] WorkGroup=${WG}  Limit=${LIMIT}  Region=${REGION}" >&2

# 1) QueryExecutionId を集める
ids=()
next=""
while :; do
  if [[ -z "${next}" ]]; then
    page=$(aws athena list-query-executions --region "$REGION" --work-group "$WG" --max-results 50)
  else
    page=$(aws athena list-query-executions --region "$REGION" --work-group "$WG" --max-results 50 --next-token "$next")
  fi
  mapfile -t page_ids < <(jq -r '.QueryExecutionIds[]?' <<<"$page")
  if [[ ${#page_ids[@]} -gt 0 ]]; then
    ids+=( "${page_ids[@]}" )
  fi
  next=$(jq -r '.NextToken // empty' <<<"$page")
  [[ ${#ids[@]} -ge $LIMIT || -z "$next" ]] && break
done
ids=( "${ids[@]:0:$LIMIT}" )

if [[ ${#ids[@]} -eq 0 ]]; then
  echo "[WARN] No queries found in workgroup: $WG" >&2
  exit 0
fi

# 2) jqフィルタを一時ファイルへ（クォート崩れ回避）
jq_filter_file=$(mktemp)
cat > "$jq_filter_file" <<'JQ'
# 入力: batch-get-query-execution の JSON
# 出力: "qid<TAB>normalized_db.table<TAB>day"

def norm_tbl(t):
  (t | gsub("[`\"]"; "")) as $t
  | ($t | split(".")) as $p
  | if   ($p|length)==3 then ($p[1]+"."+ $p[2])   # catalog.db.table -> db.table
    elif ($p|length)==2 then ($p[0]+"."+ $p[1])   # db.table
    else $t end;

# 識別子: 各セグメントごとの引用符を許可（"db"."table" / `db`.`table` / db.table / table）
def ident:     "(?:[`\"]?[a-z0-9_\\$]+[`\"]?)";
def tbl_full:  ident + "(?:\\." + ident + "){0,2}";

.QueryExecutions[]
| select(.Query != null)
| .QueryExecutionId as $qid
| (.Status.SubmissionDateTime|split("T")[0]) as $day
| (.Query|ascii_downcase) as $sql
| [ $qid, $day,
    ( $sql
      # FROM/JOIN 直後。サブクエリ (FROM (SELECT ...)) は弾く
      | match("(?i)\\b(?:from|join)\\s+(?!\\()(" + tbl_full + ")"; "g")?
      | .captures[]?.string
    )
  ]
| select(.[2] != null)
| . as [$qid, $day, $raw]
| select($raw|startswith("unnest")|not)
| select($raw|startswith("json_table")|not)
| select($raw|test("^(\"?information_schema\"?|\"?sys\"?|\"?pg_catalog\"?)\\.")|not)
| "\($qid)\t\(norm_tbl($raw))\t\($day)"
JQ

# 3) 50件ずつ詳細を取得して抽出
out_lines=$(mktemp)
cleanup() { rm -f "$jq_filter_file" "$out_lines"; }
trap cleanup EXIT

# Bash 4.2互換のチャンク関数（配列の中身をそのまま受け取る）
chunk() {
  local arr=( "$@" )
  local size=${#arr[@]}
  local start=0
  while (( start < size )); do
    local end=$(( start + 50 ))
    (( end > size )) && end=$size
    printf '%s ' "${arr[@]:start:end-start}"
    echo
    start=$end
  done
}

while read -r line; do
  read -r -a batch <<<"$line"
  json=$(aws athena batch-get-query-execution --region "$REGION" --query-execution-ids "${batch[@]}")
  jq -r -f "$jq_filter_file" <<<"$json" >> "$out_lines"
done < <(chunk "${ids[@]}")

# 4) qid×table×dayでユニーク化 → table×dayでカウント
if [[ ! -s "$out_lines" ]]; then
  echo "[WARN] No table references found (FROM/JOIN not matched in fetched queries)." >&2
  exit 0
fi

# フォーマット: COUNT  DB.TABLE  DAY
sort -u -k1,1 -k2,2 -k3,3 "$out_lines" \
| awk -F'\t' '{print $2"\t"$3}' \
| sort \
| uniq -c \
| sort -nr \
| awk 'BEGIN{printf("%8s  %-40s  %s\n","COUNT","DB.TABLE","DAY")}
           {printf("%8d  %-40s  %s\n",$1,$2,$3)}'
