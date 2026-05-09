#!/bin/bash
# ============================================================
# 仅初始化MySQL数据库（在远程服务器上执行）
# 用法: ./init_mysql.sh [ddl|dml|supplement|verify|all]
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deploy.env"
source "$ENV_FILE"

MYSQL_CMD="mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER}"
export MYSQL_PWD="${MYSQL_PASSWORD}"

ACTION="${1:-all}"

run_ddl() {
    echo "[1/4] 执行DDL: ${DDL_DIR}/create_table.sql"
    $MYSQL_CMD < "${DDL_DIR}/create_table.sql"
    echo "      DDL完成 ✓"
}

run_dml() {
    echo "[2/4] 执行基础DML: ${DATA_DIR}/pingan_insurance_data.sql"
    $MYSQL_CMD < "${DATA_DIR}/pingan_insurance_data.sql"
    echo "      基础DML完成 ✓"
}

run_supplement() {
    echo "[3/4] 执行补充数据SQL ..."
    for f in $(ls "${DATA_DIR}/supplement_data/"0*.sql 2>/dev/null | sort); do
        echo "  执行: $(basename $f) ..."
        $MYSQL_CMD < "$f"
    done
    echo "      补充数据完成 ✓"
}

run_verify() {
    echo "[4/4] 执行验证SQL ..."
    for f in $(ls "${DATA_DIR}/verify_sql/"*.sql 2>/dev/null | sort); do
        echo ""
        echo "====== 验证: $(basename $f) ======"
        $MYSQL_CMD < "$f"
    done
    echo "      验证完成 ✓"
}

case "$ACTION" in
    ddl)        run_ddl ;;
    dml)        run_dml ;;
    supplement) run_supplement ;;
    verify)     run_verify ;;
    all)
        run_ddl
        run_dml
        run_supplement
        run_verify
        ;;
    *)
        echo "用法: $0 [ddl|dml|supplement|verify|all]"
        exit 1
        ;;
esac
