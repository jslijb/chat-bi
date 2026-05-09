#!/bin/bash
# =====================================================================
# EXPLAIN执行脚本模板
# 用途：对SQL文件执行EXPLAIN验证，检查语法和执行计划
# 用法：bash explain_template.sh <sql_file> <database> [timeout_seconds]
# =====================================================================

SQL_FILE="${1:?错误：请提供SQL文件路径}"
DATABASE="${2:-cx_dws_safe}"
TIMEOUT="${3:-30}"
CATALOG="paimon"

# Spark配置
SPARK_HOME="${SPARK_HOME:-/opt/spark}"
SPARK_SQL="${SPARK_HOME}/bin/spark-sql"

echo "========================================"
echo "EXPLAIN验证: ${SQL_FILE}"
echo "数据库: ${CATALOG}.${DATABASE}"
echo "超时: ${TIMEOUT}秒"
echo "========================================"

# 读取SQL内容
EXPLAIN_FILE=$(mktemp /tmp/explain_XXXXXX.sql)
echo "USE ${CATALOG}.${DATABASE};" > "${EXPLAIN_FILE}"
echo "EXPLAIN $(cat "${SQL_FILE}")" >> "${EXPLAIN_FILE}"

echo "执行EXPLAIN..."
timeout "${TIMEOUT}" "${SPARK_SQL}" \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon_warehouse \
    -f "${EXPLAIN_FILE}" 2>&1

EXIT_CODE=$?
rm -f "${EXPLAIN_FILE}"

if [ ${EXIT_CODE} -eq 124 ]; then
    echo "[ERROR] EXPLAIN执行超时（${TIMEOUT}秒）"
    exit 1
elif [ ${EXIT_CODE} -ne 0 ]; then
    echo "[ERROR] EXPLAIN执行失败，退出码: ${EXIT_CODE}"
    exit ${EXIT_CODE}
else
    echo "[OK] EXPLAIN验证通过"
    exit 0
fi
