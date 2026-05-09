#!/bin/bash
# ============================================================
# 平安产险数据湖BI项目 - 一键部署脚本
# 部署内容：skills工具链 + workspace(DWD/DWS SQL) + RAG索引
# 测试数据不参与部署，仅用于本地验证大模型SQL正确性
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/deploy.env"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "[ERROR] 配置文件不存在: $ENV_FILE"
    exit 1
fi

source "$ENV_FILE"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# --- 1. 检查SSH ---
check_ssh() {
    log_info "检查SSH连接 ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PORT} ..."
    if ssh -o ConnectTimeout=5 -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" "echo OK" &>/dev/null; then
        log_info "SSH连接成功"
    else
        log_error "SSH连接失败"
        exit 1
    fi
}

# --- 2. 创建远程目录 ---
create_remote_dirs() {
    log_info "创建远程目录结构 ..."
    ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<EOF
mkdir -p "$SKILLS_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$DDL_DIR"
mkdir -p "$DWD_DIR"
mkdir -p "$DWS_DIR"
mkdir -p "$RAG_INDEX_DIR"
echo "目录创建完成"
EOF
}

# --- 3. 部署skills工具链（不含测试数据） ---
upload_skills() {
    log_info "部署skills工具链 ..."
    rsync -avz --progress \
        -e "ssh -p $REMOTE_PORT" \
        --exclude='deploy/' \
        --exclude='__pycache__/' \
        --exclude='*.pyc' \
        --exclude='.git/' \
        --exclude='pingan_insurance_data.sql' \
        --exclude='create_table.sql' \
        --exclude='supplement_data/' \
        --exclude='verify_sql/' \
        --exclude='rag/indices/' \
        "${SCRIPT_DIR}/../" \
        "${REMOTE_USER}@${REMOTE_HOST}:${SKILLS_DIR}/"
}

# --- 4. 部署脚本到bin ---
upload_bin_scripts() {
    log_info "部署Python/Shell脚本到 ${BIN_DIR} ..."
    local tmp_list=$(mktemp)
    find "${SCRIPT_DIR}/../" -name "*.py" -not -path "*/deploy/*" -not -path "*/__pycache__/*" > "$tmp_list"
    find "${SCRIPT_DIR}/../" -name "*.sh" -not -path "*/deploy/*" >> "$tmp_list"
    if [[ -s "$tmp_list" ]]; then
        rsync -avz --progress \
            -e "ssh -p $REMOTE_PORT" \
            --files-from="$tmp_list" \
            "${SCRIPT_DIR}/../" \
            "${REMOTE_USER}@${REMOTE_HOST}:${BIN_DIR}/"
    fi
    rm -f "$tmp_list"
}

# --- 5. 部署workspace SQL（DWD/DWS/ADS DDL + DWD/DWS ETL，由大模型生成） ---
upload_workspace_sql() {
    # DDL: DWD/DWS/ADS层建表SQL（ODS由flink-cdc自动创建，不属于项目范畴）
    if [[ -d "${SCRIPT_DIR}/../workspace/ddl" ]]; then
        log_info "部署DWD/DWS/ADS DDL ..."
        rsync -avz --progress \
            -e "ssh -p $REMOTE_PORT" \
            "${SCRIPT_DIR}/../workspace/ddl/" \
            "${REMOTE_USER}@${REMOTE_HOST}:${DDL_DIR}/"
    else
        log_warn "本地无workspace/ddl目录，跳过DDL部署（大模型生成DWD/DWS/ADS DDL后重新部署）"
    fi

    # DWD/DWS: 如果本地有生成，则上传
    if [[ -d "${SCRIPT_DIR}/../workspace/dwd" ]]; then
        log_info "部署DWD SQL ..."
        rsync -avz --progress \
            -e "ssh -p $REMOTE_PORT" \
            "${SCRIPT_DIR}/../workspace/dwd/" \
            "${REMOTE_USER}@${REMOTE_HOST}:${DWD_DIR}/"
    else
        log_warn "本地无workspace/dwd目录，跳过DWD部署（大模型生成后重新部署）"
    fi

    if [[ -d "${SCRIPT_DIR}/../workspace/dws" ]]; then
        log_info "部署DWS SQL ..."
        rsync -avz --progress \
            -e "ssh -p $REMOTE_PORT" \
            "${SCRIPT_DIR}/../workspace/dws/" \
            "${REMOTE_USER}@${REMOTE_HOST}:${DWS_DIR}/"
    else
        log_warn "本地无workspace/dws目录，跳过DWS部署（大模型生成后重新部署）"
    fi
}

# --- 6. 安装Python依赖 ---
install_deps() {
    log_info "安装Python依赖（远程） ..."
    ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<EOF
cd "${SKILLS_DIR}"
if [[ -f deploy/requirements.txt ]]; then
    ${PIP_BIN} install --user -r deploy/requirements.txt 2>&1 | tail -5
    echo "依赖安装完成"
else
    echo "requirements.txt不存在，跳过"
fi
EOF
}

# --- 7. 构建RAG向量索引 ---
build_rag_index() {
    log_info "构建RAG向量索引（远程）..."
    log_warn "此步骤需要下载embedding模型（~2.3GB），首次执行较慢"

    local YAML_PATH="${SKILLS_DIR}/bi-requirement-parser/dictionaries/data_dictionary.yaml"
    local DDL_PATH="${DDL_DIR}/create_table.sql"
    local SQL_DIR="${DWD_DIR}"
    local ER_PATH="${SKILLS_DIR}/bi-requirement-parser/dictionaries/ods_er.txt"

    ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<EOF
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
cd "${SKILLS_DIR}"

# 预下载模型到本地缓存
${PYTHON_BIN} -c "
import modelscope
modelscope.snapshot_download('AI-ModelScope/bge-large-zh-v1.5')
modelscope.snapshot_download('jinaai/jina-code-embeddings-0.5b')
print('模型下载完成')
" 2>&1 | tail -3

# 构建索引
${PYTHON_BIN} -c "
import sys
sys.path.insert(0, '${SKILLS_DIR}')
from rag.rag_gateway import RAGGateway
gw = RAGGateway()
gw.build(
    yaml_path='${YAML_PATH}',
    ddl_path='${DDL_PATH}',
    sql_dir='${SQL_DIR}',
    er_file='${ER_PATH}',
)
gw.save()
info = gw.stats()
for name, stat in info.items():
    print(f'  {name}: vectors={stat.get(\"vector_count\", 0)}')
print('RAG索引构建完成')
" 2>&1 | tail -10
EOF
}

# --- 8. 设置权限 ---
set_permissions() {
    log_info "设置文件权限 ..."
    ssh -p "$REMOTE_PORT" "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<EOF
find "${BIN_DIR}" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "${SKILLS_DIR}" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
echo "权限设置完成"
EOF
}

# --- 9. 汇总 ---
print_summary() {
    echo ""
    echo "============================================================"
    echo "  部署完成！远程服务器目录结构："
    echo "============================================================"
    echo ""
    echo "  ${SKILLS_DIR}/"
    echo "    ├── bi-requirement-parser/   ← 需求解析"
    echo "    ├── sql-code-generator/      ← SQL代码生成"
    echo "    ├── sql-validator/           ← SQL验证"
    echo "    ├── lineage-manager/         ← 血缘管理"
    echo "    ├── scheduler-updater/       ← 调度更新"
    echo "    ├── rag/                     ← RAG向量检索(升级版)"
    echo "    │   ├── indices/             ← FAISS索引(data_dict+ddl+sql)"
    echo "    │   └── *.py                 ← RAG代码"
    echo "    └── ...（其他skills模块）"
    echo ""
    echo "  ${BIN_DIR}/"
    echo "    ├── *.py                     ← Python脚本"
    echo "    └── *.sh                     ← Shell脚本"
    echo ""
    echo "  ${DDL_DIR}/                    ← DWD/DWS/ADS层DDL"
    echo "  ${DWD_DIR}/                    ← DWD层SQL"
    echo "  ${DWS_DIR}/                    ← DWS层SQL"
    echo ""
    echo "  RAG模型：BGE-large-zh-v1.5(自然语言) + jina-code-0.5b(SQL代码)"
    echo "  内存策略：LRU淘汰(容量=${RAG_MAX_CACHED_MODELS})，4GB可用"
    echo ""
    echo "  测试数据（不部署，仅本地验证用）："
    echo "    pingan_insurance_data.sql    ← 基础测试数据"
    echo "    supplement_data/01~10_*.sql  ← 补充测试数据"
    echo "    verify_sql/01~03_*.sql       ← 验证SQL"
    echo "============================================================"
}

main() {
    echo "============================================================"
    echo "  平安产险数据湖BI项目 - 部署"
    echo "  （仅部署工具链+SQL代码+RAG索引，测试数据不部署）"
    echo "============================================================"
    echo ""

    check_ssh
    create_remote_dirs
    upload_skills
    upload_bin_scripts
    upload_workspace_sql
    install_deps
    build_rag_index
    set_permissions
    print_summary

    log_info "部署完成！"
}

main "$@"
