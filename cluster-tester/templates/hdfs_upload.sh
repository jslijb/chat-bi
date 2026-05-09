#!/bin/bash
# =====================================================================
# HDFS上传脚本模板
# 用途：将本地SQL文件上传到HDFS指定目录
# 用法：bash hdfs_upload.sh <local_file> <hdfs_dir> [layer]
# =====================================================================

LOCAL_FILE="${1:?错误：请提供本地文件路径}"
HDFS_DIR="${2:?错误：请提供HDFS目标目录}"
LAYER="${3:-dws}"

# HDFS命令
HDFS_CMD="hdfs dfs"

echo "========================================"
echo "HDFS上传: ${LOCAL_FILE} → ${HDFS_DIR}"
echo "分层: ${LAYER}"
echo "========================================"

# 1. 确保目标目录存在
echo "创建HDFS目录: ${HDFS_DIR}"
${HDFS_CMD} -mkdir -p "${HDFS_DIR}"

# 2. 检查本地文件是否存在
if [ ! -f "${LOCAL_FILE}" ]; then
    echo "[ERROR] 本地文件不存在: ${LOCAL_FILE}"
    exit 1
fi

# 3. 上传文件（覆盖已存在的文件）
echo "上传文件..."
${HDFS_CMD} -put -f "${LOCAL_FILE}" "${HDFS_DIR}/"

if [ $? -eq 0 ]; then
    echo "[OK] 上传成功: ${HDFS_DIR}/$(basename ${LOCAL_FILE})"
    # 验证文件
    ${HDFS_CMD} -ls "${HDFS_DIR}/$(basename ${LOCAL_FILE})"
else
    echo "[ERROR] 上传失败"
    exit 1
fi
