#!/bin/bash
# =====================================================================
# 集群测试示例：端到端ETL测试流程
# 用途：展示cluster-tester的完整测试流程
# =====================================================================

# 测试参数
BIZ_DATE="${BIZ_DATE:-2026-04-25}"
LAYER="dws"
TABLE="dws_policy_premium_daily"
CATALOG="paimon"
DATABASE="cx_dws_safe"

echo "========================================"
echo "集群测试: ${LAYER}.${TABLE}"
echo "业务日期: ${BIZ_DATE}"
echo "========================================"

# Step 1: 上传DDL到HDFS
echo "[Step 1] 上传DDL..."
hdfs dfs -mkdir -p /cx_dwd_safe/ddl
hdfs dfs -put -f ddl/${TABLE}_ddl.sql /cx_dwd_safe/ddl/

# Step 2: 执行DDL建表
echo "[Step 2] 执行DDL建表..."
spark-sql \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon_warehouse \
    -f ddl/${TABLE}_ddl.sql

# Step 3: 上传ETL到HDFS
echo "[Step 3] 上传ETL..."
hdfs dfs -put -f etl/etl_${TABLE}.sql /cx_dws_safe/dws/

# Step 4: 执行ETL
echo "[Step 4] 执行ETL..."
spark-sql \
    --master yarn --deploy-mode client \
    --queue default \
    --executor-memory 4g --executor-cores 2 --num-executors 4 \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon_warehouse \
    --conf spark.sql.adaptive.enabled=true \
    --conf spark.sql.shuffle.partitions=50 \
    -e "USE ${CATALOG}.${DATABASE}; SET biz_date=${BIZ_DATE}" -f "etl/etl_${TABLE}.sql"

# Step 5: 数据验证
echo "[Step 5] 数据验证..."
spark-sql \
    --conf spark.sql.catalog.paimon=org.apache.paimon.spark.SparkCatalog \
    --conf spark.sql.catalog.paimon.warehouse=hdfs:///paimon_warehouse \
    -e "USE ${CATALOG}.${DATABASE}; SELECT COUNT(*) FROM ${TABLE} WHERE dt='${BIZ_DATE}'"

echo "========================================"
echo "[OK] 集群测试完成"
echo "========================================"
