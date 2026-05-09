#!/bin/bash
# =====================================================================
# spark-submit参数模板
# 用途：提交Spark SQL作业到YARN集群
# 用法：bash spark_submit_template.sh <sql_file> <database> [queue] [priority]
# =====================================================================

SQL_FILE="${1:?错误：请提供SQL文件路径}"
DATABASE="${2:-cx_dws_safe}"
QUEUE="${3:-default}"
PRIORITY="${4:-P2}"
CATALOG="paimon"

# 根据优先级设置资源参数
case "${PRIORITY}" in
    P0)
        EXECUTOR_MEMORY="8g"
        EXECUTOR_CORES=4
        NUM_EXECUTORS=8
        SHUFFLE_PARTITIONS=200
        ;;
    P1)
        EXECUTOR_MEMORY="6g"
        EXECUTOR_CORES=3
        NUM_EXECUTORS=6
        SHUFFLE_PARTITIONS=100
        ;;
    P2)
        EXECUTOR_MEMORY="4g"
        EXECUTOR_CORES=2
        NUM_EXECUTORS=4
        SHUFFLE_PARTITIONS=50
        ;;
    P3)
        EXECUTOR_MEMORY="2g"
        EXECUTOR_CORES=1
        NUM_EXECUTORS=2
        SHUFFLE_PARTITIONS=20
        ;;
    *)
        EXECUTOR_MEMORY="4g"
        EXECUTOR_CORES=2
        NUM_EXECUTORS=4
        SHUFFLE_PARTITIONS=50
        ;;
esac

echo "========================================"
echo "spark-submit: ${SQL_FILE}"
echo "数据库: ${CATALOG}.${DATABASE}"
echo "队列: ${QUEUE} | 优先级: ${PRIORITY}"
echo "资源: ${NUM_EXECUTORS}x(${EXECUTOR_CORES}核,${EXECUTOR_MEMORY})"
echo "========================================"

spark-sql \
    --master yarn \
    --deploy-mode client \
    --queue "${QUEUE}" \
    --executor-memory "${EXECUTOR_MEMORY}" \
    --executor-cores "${EXECUTOR_CORES}" \
    --num-executors "${NUM_EXECUTORS}" \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon_warehouse \
    --conf spark.sql.adaptive.enabled=true \
    --conf spark.sql.adaptive.coalescePartitions.enabled=true \
    --conf spark.sql.shuffle.partitions="${SHUFFLE_PARTITIONS}" \
    --conf spark.sql.autoBroadcastJoinThreshold=50m \
    -e "USE ${CATALOG}.${DATABASE}" -f "${SQL_FILE}"

EXIT_CODE=$?
if [ ${EXIT_CODE} -eq 0 ]; then
    echo "[OK] 执行成功"
else
    echo "[ERROR] 执行失败，退出码: ${EXIT_CODE}"
fi
exit ${EXIT_CODE}
