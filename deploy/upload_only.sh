#!/bin/bash
# ============================================================
# 仅上传文件到远程服务器（不初始化MySQL）
# 用法: ./upload_only.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deploy.env"
source "$ENV_FILE"

echo "============================================================"
echo "  上传文件到 ${REMOTE_USER}@${REMOTE_HOST}"
echo "============================================================"

# 创建目录
ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<EOF
mkdir -p "$SKILLS_DIR" "$BIN_DIR" "$DDL_DIR" "$DWD_DIR" "$DWS_DIR"
mkdir -p "$DATA_DIR/supplement_data" "$DATA_DIR/verify_sql"
EOF

# 上传skills
echo "[1/5] 上传skills模块 ..."
rsync -avz -e "ssh -p $REMOTE_PORT" \
    --exclude='deploy/' --exclude='__pycache__/' --exclude='*.pyc' \
    "${SCRIPT_DIR}/../" "${REMOTE_USER}@${REMOTE_HOST}:${SKILLS_DIR}/"

# 上传bin脚本
echo "[2/5] 上传脚本到bin ..."
tmp_list=$(mktemp)
find "${SCRIPT_DIR}/../" -name "*.py" -not -path "*/deploy/*" -not -path "*/__pycache__/*" > "$tmp_list"
find "${SCRIPT_DIR}/../" -name "*.sh" -not -path "*/deploy/*" >> "$tmp_list"
rsync -avz -e "ssh -p $REMOTE_PORT" --files-from="$tmp_list" \
    "${SCRIPT_DIR}/../" "${REMOTE_USER}@${REMOTE_HOST}:${BIN_DIR}/"
rm -f "$tmp_list"

# 上传DDL
echo "[3/5] 上传DDL ..."
rsync -avz -e "ssh -p $REMOTE_PORT" \
    "${SCRIPT_DIR}/../create_table.sql" "${REMOTE_USER}@${REMOTE_HOST}:${DDL_DIR}/"

# 上传DML+补充数据
echo "[4/5] 上传数据SQL ..."
rsync -avz -e "ssh -p $REMOTE_PORT" \
    "${SCRIPT_DIR}/../pingan_insurance_data.sql" "${REMOTE_USER}@${REMOTE_HOST}:${DATA_DIR}/"
rsync -avz -e "ssh -p $REMOTE_PORT" \
    "${SCRIPT_DIR}/../supplement_data/" "${REMOTE_USER}@${REMOTE_HOST}:${DATA_DIR}/supplement_data/"

# 上传验证SQL
echo "[5/5] 上传验证SQL ..."
rsync -avz -e "ssh -p $REMOTE_PORT" \
    "${SCRIPT_DIR}/../verify_sql/" "${REMOTE_USER}@${REMOTE_HOST}:${DATA_DIR}/verify_sql/"

# 设置权限
ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" \
    "find '${BIN_DIR}' '${SKILLS_DIR}' -name '*.sh' -exec chmod +x {} \; 2>/dev/null; echo '权限设置完成'"

echo "上传完成！"
