"""
Airflow DAG: bi_policy_premium_daily
自动生成于: 2026-04-26T12:12:24Z
需求来源: REQ-2026-Q1-042
"""

from airflow import DAG
from airflow.providers.apache.spark.operators.spark_submit import SparkSubmitOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'bi-team',
    'depends_on_past': False,
    'email_on_failure': True,
    'email': ['bi-team@company.com'],
    'retries': 2,
    'retry_delay': timedelta(minutes=10),
}

with DAG(
    dag_id='bi_policy_premium_daily',
    default_args=default_args,
    description='渠道保费日汇总ETL链路',
    schedule_interval='0 2 * * *',
    start_date=datetime(2026, 4, 1),
    catchup=False,
    tags=['bi', 'DWS'],
) as dag:

    dim_channel_etl = SparkSubmitOperator(
        task_id='dim_channel_etl',
        application='hdfs:///cx_dim_safe/dim/dim_channel.sql',
        conn_id='spark_default',
        conf={
            'spark.sql.catalog.paimon': 'org.apache.paimon.spark.SparkCatalog',
            'spark.sql.catalog.paimon.warehouse': 'hdfs:///paimon_warehouse',
            'spark.sql.adaptive.enabled': 'true',
            'spark.sql.shuffle.partitions': '50',
        },
        executor_memory='4g',
        executor_cores=2,
        num_executors=4,
        queue='default',
    )

    dwd_policy_premium_daily_etl = SparkSubmitOperator(
        task_id='dwd_policy_premium_daily_etl',
        application='hdfs:///cx_dwd_safe/dwd/dwd_policy_premium_daily.sql',
        conn_id='spark_default',
        conf={
            'spark.sql.catalog.paimon': 'org.apache.paimon.spark.SparkCatalog',
            'spark.sql.catalog.paimon.warehouse': 'hdfs:///paimon_warehouse',
            'spark.sql.adaptive.enabled': 'true',
            'spark.sql.shuffle.partitions': '50',
        },
        executor_memory='4g',
        executor_cores=2,
        num_executors=4,
        queue='default',
    )

    dws_policy_premium_daily_etl = SparkSubmitOperator(
        task_id='dws_policy_premium_daily_etl',
        application='hdfs:///cx_dws_safe/dws/dws_policy_premium_daily.sql',
        conn_id='spark_default',
        conf={
            'spark.sql.catalog.paimon': 'org.apache.paimon.spark.SparkCatalog',
            'spark.sql.catalog.paimon.warehouse': 'hdfs:///paimon_warehouse',
            'spark.sql.adaptive.enabled': 'true',
            'spark.sql.shuffle.partitions': '50',
        },
        executor_memory='4g',
        executor_cores=2,
        num_executors=4,
        queue='default',
    )

    ads_channel_premium_report_etl = SparkSubmitOperator(
        task_id='ads_channel_premium_report_etl',
        application='hdfs:///cx_ads_safe/ads/ads_channel_premium_report.sql',
        conn_id='spark_default',
        conf={
            'spark.sql.catalog.paimon': 'org.apache.paimon.spark.SparkCatalog',
            'spark.sql.catalog.paimon.warehouse': 'hdfs:///paimon_warehouse',
            'spark.sql.adaptive.enabled': 'true',
            'spark.sql.shuffle.partitions': '50',
        },
        executor_memory='4g',
        executor_cores=2,
        num_executors=4,
        queue='default',
    )

    # 显式依赖链
    dim_channel_etl >> dwd_policy_premium_daily_etl >> dws_policy_premium_daily_etl >> ads_channel_premium_report_etl
