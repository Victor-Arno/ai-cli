#!/bin/bash
set -e

AI_DIR="$HOME/.ai-cli"
SCRIPT_URL="https://raw.githubusercontent.com/Victor-Arno/ai-cli/main/ai.sh"

echo "AI CLI 开发者工具箱 · 安装"
echo ""

# 目录
mkdir -p "$AI_DIR/claude-code" "$AI_DIR/servers" "$HOME/remote-projects"

# 下载
echo "下载 ai.sh ..."
curl -fsSL "$SCRIPT_URL" -o "$AI_DIR/ai.sh"

# zshrc
if ! grep -q "source.*ai-cli/ai.sh" "$HOME/.zshrc" 2>/dev/null; then
  echo "" >> "$HOME/.zshrc"
  echo 'source "$HOME/.ai-cli/ai.sh"' >> "$HOME/.zshrc"
fi

echo ""
echo "安装完成。执行 source ~/.zshrc 后输入 ai 即可使用。"
