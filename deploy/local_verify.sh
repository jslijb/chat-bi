#!/bin/bash
# ============================================================
# 本地测试数据初始化（在本地MySQL验证大模型SQL正确性）
# 用法: ./local_verify.sh [ddl|dml|supplement|verify|all]
# 这不是部署步骤，是本地开发验证用
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deploy.env"
source "$ENV_FILE"

MYSQL_CMD="mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER}"
export MYSQL_PWD="${MYSQL_PASSWORD}"

# 测试数据路径（本地skills目录下）
DATA_DIR="$(dirname "$SCRIPT_DIR")"

ACTION="${1:-all}"

run_ddl() {
    echo "[DDL] 建表 ..."
    $MYSQL_CMD < "${DATA_DIR}/create_table.sql"
    echo "      完成 ✓"
}

run_dml() {
    echo "[DML] 基础数据 ..."
    $MYSQL_CMD < "${DATA_DIR}/pingan_insurance_data.sql"
    echo "      完成 ✓"
}

run_supplement() {
    echo "[补充] 测试数据 ..."
    for f in $(ls "${DATA_DIR}/supplement_data/"0*.sql 2>/dev/null | sort); do
        echo "  $(basename $f) ..."
        $MYSQL_CMD < "$f"
    done
    echo "      完成 ✓"
}

run_verify() {
    echo "[验证] 执行验证SQL ..."
    for f in $(ls "${DATA_DIR}/verify_sql/"*.sql 2>/dev/null | sort); do
        echo "====== $(basename $f) ======"
        $MYSQL_CMD < "$f"
    done
}

case "$ACTION" in
    ddl)        run_ddl ;;
    dml)        run_dml ;;
    supplement) run_supplement ;;
    verify)     run_verify ;;
    all)        run_ddl; run_dml; run_supplement; run_verify ;;
    *)          echo "用法: $0 [ddl|dml|supplement|verify|all]"; exit 1 ;;
esac
