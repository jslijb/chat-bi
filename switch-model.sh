#!/bin/bash
# ==============================================================================
# switch-model.sh — 一键切换 OpenClaw 模型并重启
# ==============================================================================
# 用法：
#   ./switch-model.sh                          # 查看当前模型和可用模型列表
#   ./switch-model.sh deepseek/deepseek-chat    # 切换到指定模型并自动重启
#   ./switch-model.sh qwen/qwen-plus           # 切换到 qwen-plus 并重启
# ==============================================================================

set -e

OPENCLAW_DIR="$HOME/.openclaw"
CONFIG_FILE="$OPENCLAW_DIR/openclaw.json"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ============================================
# 常用模型参考（按性价比排序）
# ============================================
echo_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo_error "找不到 openclaw.json: $CONFIG_FILE"
    echo_error "请先运行 openclaw onboard 初始化"
    exit 1
fi

# 获取当前模型
CURRENT_MODEL=$(grep -o '"default_model"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1 | sed 's/.*"default_model"[[:space:]]*:[[:space:]]*"\([^]*\)".*/\1/')

if [ -z "$CURRENT_MODEL" ]; then
    CURRENT_MODEL="(未设置)"
fi

# 如果没有参数，显示当前状态和可用模型
if [ $# -eq 0 ]; then
    echo "========================================="
    echo "  OpenClaw 模型配置"
    echo "========================================="
    echo ""
    echo "当前模型: $CURRENT_MODEL"
    echo ""
    echo "可用模型（推荐）："
    echo ""
    echo "  [免费/低价]"
    echo "    qwen/qwen3.5-plus        — 通义千问 3.5（当前默认，有免费额度限制）"
    echo "    qwen/qwen-plus           — 千问 Plus（稳定）"
    echo "    qwen/qwen-turbo          — 千问 Turbo（快+便宜）"
    echo ""
    echo "  [付费-高性价比]"
    echo "    deepseek/deepseek-chat   — DeepSeek V3（中文强，便宜）"
    echo "    deepseek/deepseek-reasoner — DeepSeek R1（推理强）"
    echo ""
    echo "  [付费-高质量]"
    echo "    openai/gpt-4o            — GPT-4o（综合最强）"
    echo "    openai/gpt-4o-mini       — GPT-4o Mini（便宜）"
    echo ""
    echo "用法：$0 <model_name>"
    echo "示例：$0 deepseek/deepseek-chat"
    exit 0
fi

NEW_MODEL="$1"

echo "========================================="
echo "  切换模型: $CURRENT_MODEL → $NEW_MODEL"
echo "========================================="

# 备份原配置
BACKUP_FILE="$CONFIG_FILE.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo_info "已备份原配置到: $BACKUP_FILE"

# 使用 sed 替换 default_model（兼容多种 JSON 格式）
if grep -q '"default_model"' "$CONFIG_FILE"; then
    # 替换已有的 default_model
    sed -i "s|\"default_model\"[[:space:]]*:[[:space:]]*\"[^\"]*\"|\"default_model\": \"$NEW_MODEL\"|" "$CONFIG_FILE"
    echo_info "已更新 default_model = $NEW_MODEL"
else
    # 如果没有 default_model 字段，添加到合适位置（在 model 或 gateway 附近）
    # 简单处理：在文件末尾的 } 之前插入
    sed -i "s|}|, \"default_model\": \"$NEW_MODEL\"}|" "$CONFIG_FILE"
    echo_info "已添加 default_model = $NEW_MODEL"
fi

# 验证修改结果
VERIFY_MODEL=$(grep -o '"default_model"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | head -1)
echo_info "验证: $VERIFY_MODEL"

# 重启 OpenClaw
echo ""
echo_info "正在重启 OpenClaw..."

if command -v systemctl &> /dev/null && systemctl is-active --quiet openclaw 2>/dev/null; then
    sudo systemctl restart openclaw
    echo_info "OpenClaw 已通过 systemctl 重启"
elif command -v openclaw &> /dev/null; then
    openclaw daemon restart
    echo_info "OpenClaw 已通过 openclaw daemon restart 重启"
else
    echo_warn "无法自动重启 OpenClaw，请手动执行以下命令："
    echo "  sudo systemctl restart openclaw"
    echo "  或: openclaw daemon restart"
    exit 0
fi

# 等待服务启动
sleep 3

# 检查服务状态
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet openclaw 2>/dev/null; then
        echo_info "✅ OpenClaw 运行正常"
    else
        echo_error "❌ OpenClaw 启动失败，请检查日志："
        echo "  journalctl -u openclaw -n 50"
        echo ""
        echo "如需回滚："
        echo "  cp $BACKUP_FILE $CONFIG_FILE"
        echo "  sudo systemctl restart openclaw"
        exit 1
    fi
fi

echo ""
echo "========================================="
echo "✅ 模型切换完成！"
echo "========================================="
echo "新模型: $NEW_MODEL"
echo "备份  : $BACKUP_FILE"
echo ""
echo "现在可以开新对话测试："
echo "  @requirements.txt 处理 C-REQ-001"
