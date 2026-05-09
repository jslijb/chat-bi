#!/bin/bash
# ==============================================================================
# run_py.sh — OpenClaw 服务器 Python 执行入口
# 用法: ~/.openclaw/bin/run_py.sh <脚本> [参数...]
# 虚拟环境: ~/.openclaw/workspace/.venv（可通过 OPENCLAW_VENV 自定义）
# ==============================================================================

set -euo pipefail

OPENCLAW_DIR="${HOME}/.openclaw"
VENV_PATH="${OPENCLAW_VENV:-${HOME}/.openclaw/workspace/.venv}"
WORKSPACE="${HOME}/.openclaw/workspace"
BIN_DIR="${OPENCLAW_DIR}/bin"

# 检查参数
[ $# -lt 1 ] && { echo "用法: $0 <python脚本> [参数...]"; exit 1; }

TARGET="$1"; shift

# 查找脚本
for dir in "${BIN_DIR}" "${WORKSPACE}" "."; do
    [ -f "${dir}/${TARGET}" ] && SCRIPT="${dir}/${TARGET}" && break
done
[ -z "${SCRIPT:-}" ] && { echo "[ERROR] 找不到: ${TARGET}"; exit 1; }

# 激活虚拟环境
if [ -d "${VENV_PATH}" ]; then
    source "${VENV_PATH}/bin/activate"
else
    echo "[ERROR] 虚拟环境不存在: ${VENV_PATH}"
    echo "请先创建: python3 -m venv ${VENV_PATH}"
    echo "然后安装依赖: ${VENV_PATH}/bin/pip install faiss-cpu numpy pyyaml sentence-transformers modelscope"
    exit 1
fi

# 运行
export PYTHONPATH="${WORKSPACE}:${PYTHONPATH:-}"
exec python3 "${SCRIPT}" "$@"
