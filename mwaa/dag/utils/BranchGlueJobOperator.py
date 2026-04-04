from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.datasets import Dataset
from airflow.operators.empty import EmptyOperator
from airflow.exceptions import AirflowSkipException
from airflow.utils.trigger_rule import TriggerRule
from pendulum import DateTime
import os, sys
from pathlib import Path
import inspect

SKIP_TASKS = ["bootstrap", "cleanup", "teardown"]

class BranchGlueJobOperator(GlueJobOperator):

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.env = None

    def get_ingest_date(self, context) -> str:
        """
        Asset-triggered Run でも一貫して YYYY-MM-DD を返す。
        1. 時間ベース Run なら logical_date
        2. Asset-triggered Run ならイベントの timestamp
        """
        # ① cron / timetable Run の場合
        logical_dt: DateTime | None = context.get("logical_date")
        if logical_dt:
            return logical_dt.format("YYYY-MM-DD")

        # ② asset-triggered Run の場合
        targ_events = context["triggering_asset_events"]
        # イベントを発行した Asset → AssetEvent の list が取れる
        for _, events in targ_events.items():
            if events: 
                ts: DateTime = events[0].timestamp
                return ts.strftime("YYYY-MM-DD")

    def pre_execute(self, context):
        # 環境変数からブランチ名を取得
        print("params.branch--->", context.get('params', {}).get('branch', 'main'))

        # 親の pre_execute を呼ぶ
        super().pre_execute(context)
        
        print("pre_execute context->:", context)

        ### BRANCH の設定 ###
        branch = None
        # 1) triggering_asset_events から優先的に取得
        events = context.get('triggering_asset_events', {})
        if events:
            for dataset, dataset_list in events.items():
                print("dataset_list[0]", dataset_list)
                branch = dataset_list[0].extra["branch"]
                break

        # 2) 上記で取れなければ DAG params から取得
        if not branch:
            print("Fallback to params for branch extraction")
            branch = context.get('params', {}).get('branch', 'main')

        # 3) 取得した branch を保持 or エラー
        if not branch:
            raise ValueError("Branch parameter is not provided in params or triggering_asset_events.")

        self.env = branch

        # mainの場合は、データのブランチなどを切る必要がないのでSkipする
        if self.env == "main" and any(k in self.task_id for k in SKIP_TASKS):
            self.log.info("Skipping %s in main environment", self.task_id)
            raise AirflowSkipException(f"{self.task_id} skipped in main")

        #### SCRIPT ARGS の設定 ####
        base_arguments = dict(self.script_args or {})

        # 2) コンテキストから動的に取り出す値
        logical_date = self.get_ingest_date(context)
        run_id = context["run_id"]
        dag_id = context["dag"].dag_id
        e2e_mode = context.get('params', {}).get('e2e_mode', 'BRANCH')
        extract_mode = context.get('params', {}).get('extract_mode', 'logical_date')
        master_data = context.get('params', {}).get('master_data', 'v1')

        # 3) 動的引数を作成して結合
        dyn_arguments = {
            "--ingest-date": logical_date,
            "--run-id": run_id,
            "--env": self.env,
            "--e2e-mode": e2e_mode,
            "--extract-mode": extract_mode,
            "--master-data": master_data,
            "--catalog": "s3tablescatalog",  # S3 Tables用カタログ
            "--warehouse": f"s3://data-platform-iceberg-managed-yuki-sample/",  # S3 Tables warehouse
        }
        
        # WAP (Write-Audit-Publish) の設定
        if self.env != 'main':
            dyn_arguments.update({
                "--wap-enabled": "true",
                "--wap-branch": self.env,
            })

        # OpenLineage の設定 (mainのみ)
        if self.env == "main":
            dyn_arguments.update({
                "--openlineage-namespace": dag_id,
                "--openlineage-job-name": self.task_id,
                "--openlineage-run-id": run_id,
            })

        self.script_args = {**base_arguments, **dyn_arguments}
        print("=" * 50)
        print(f"🔧 GLUE JOB ARGUMENTS DEBUG - Task: {self.task_id}")
        print("=" * 50)
        print("ブランチはこれです:", self.env)
        print("静的引数 (base_arguments):")
        for key, value in base_arguments.items():
            print(f"  {key}: {value}")
        print("動的引数 (dyn_arguments):")
        for key, value in dyn_arguments.items():
            print(f"  {key}: {value}")
        print("最終引数 (script_args):")
        for key, value in self.script_args.items():
            print(f"  {key}: {value}")
        print("=" * 50)

    def post_execute(self, context, result=None):
        super().post_execute(context, result)
        print("post_execute context->:", context)

        # 全てのoutletsに対してbranchを注入
        outlet_events = context.get("outlet_events", {})

        if self.outlets:
            for outlet in self.outlets:
                if outlet in outlet_events:
                    outlet_events[outlet].extra = {"branch": self.env}
                    print(f"inject ds name -> {outlet_events[outlet].extra}")

        print(f"branch_param injected into outlet events: {self.env}")

    @classmethod
    def submit(GlueOperatorClass,
               task_id,
               job_name,  # Glue Job名
               inlets: list[Dataset] = [],
               outlets: list[Dataset] = [],
               script_args: dict = {},
               **glue_kwargs
        ):
        print("task_id---->", task_id)

        return GlueOperatorClass(
            task_id=task_id,
            job_name=job_name,
            aws_conn_id="aws_default",
            script_args=script_args,
            inlets=inlets,
            outlets=outlets,
            trigger_rule=TriggerRule.NONE_FAILED,
            **glue_kwargs
        )
