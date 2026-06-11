# AI CLI 开发者工具箱

管理 Claude Code / Gemini CLI / Codex CLI 的 API 配置，以及远程服务器 SSHFS 挂载。交互式终端菜单操作。适合Macos/Linux环境

## 前置：安装 AI CLI

```bash
# Claude Code
npm install -g @anthropic-ai/claude-code

# Codex CLI
npm install -g @openai/codex

# Gemini CLI
npm install -g @google/gemini-cli
```

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/Victor-Arno/ai-cli/main/install.sh | bash
```

安装后 `source ~/.zshrc`，输入 `ai` 即可。首次启动自动检测已安装的 CLI 并导入当前 API 配置。

## 目录

```
~/.ai-cli/
├── ai.sh                       # 唯一脚本，零外部依赖
├── claude-code/                # Claude CLI API 配置
├── gemini/                     # Gemini CLI API 配置
├── codex/                      # Codex CLI API 配置
└── servers/                    # 远程服务器配置（所有 CLI 通用）
```

## 工作原理

每个 CLI 配置目录下是一个或多个 JSON profile 文件：

```
~/.ai-cli/claude-code/
├── deepseek.json    ← 一个 profile = 一个完整的 API 配置
└── anthropic.json   ← 切换 = 把这个文件复制到 CLI 的配置文件路径
```

- **添加** → 从当前生效配置克隆，填入新 API 信息，保存为新 JSON 文件
- **切换** → 把 profile JSON 的内容写入 CLI 实际读取的配置文件
- **修改** → 直接更新 profile JSON 的字段，如果正在使用则同步到实际配置
- **删除** → `rm` 掉对应的 JSON 文件
- **分享** → 把 JSON 文件发给别人，放入对应目录即可

首次启动时，如果某个 CLI 目录为空，工具会自动把当前 CLI 的 API 配置导出为一个初始 profile。

## 主菜单

菜单完全动态，只显示已安装的 CLI：

```
  开发者工具

  ~/.ai-cli/
  ├── ai.sh          # 菜单逻辑
  ├── claude-code/   # Claude CLI
  ├── codex/         # Codex CLI
  ├── gemini/        # Gemini CLI
  └── servers/       # 远程服务器

  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  功能：

  [1] 远程服务器
  [2] Claude CLI
  [3] Codex CLI
  [4] Gemini CLI
  [q] 退出
```

---

## API 管理

每个 CLI 的子菜单一致：

```
  使用：
  [1] 切换 API         [2] 查看当前

  配置：
  [3] 添加 API         [4] 修改 API
  [5] 删除 API

  其他：
  [6] 测试连接
```

| CLI | 配置文件 | 切换原理 |
|-----|---------|---------|
| Claude Code | `~/.claude/settings.json` | `cp` 完整替换 |
| Gemini CLI | `~/.gemini/.env` | 写 `GOOGLE_GEMINI_BASE_URL` / `GEMINI_API_KEY` / `GEMINI_MODEL` |
| Codex CLI | `~/.codex/auth.json` + `~/.codex/config.toml` | 写 auth.json + 更新 config.toml |

**添加 API** — 从当前配置克隆，保留权限和主题，仅替换 API 字段。

**修改 API** — 点选模式，选一个字段改一个字段。改动自动同步到当前生效的配置。

**测试连接** — 发送真实 API 请求验证 Key。继电器服务返回 404 时明确告知。

**分享 profile** — JSON 文件发给对方，放入对应目录即可。

---

## 远程服务器

通过 SSHFS 将远程目录挂载到本地。所有 CLI 通用。

```
  连接：
  [1] 挂载         [2] 断开

  配置：
  [3] 添加         [4] 删除

  其他：
  [5] 查看全部     [6] 使用说明     [7] 测试连接
```

**流程：** `[3] 添加` → `[1] 挂载` → 写代码/跑模型 → `[2] 断开`（配置保留）

**前置：**
```bash
# 1. 传公钥到服务器（一次性，之后免密码）
ssh-copy-id -p 端口 用户@地址

# 2. 安装 SSHFS
# macOS
brew install --cask macfuse && brew install sshfs
# Linux
sudo apt install sshfs
```

**配置文件：**
```json
{
  "name": "GPU服务器",
  "host": "user@10.0.0.1",
  "remote_path": "/home/user/cuda-project",
  "port": "22"
}
```

挂载点自动生成 `~/remote-projects/<名称>/`。

---

## 卸载

```bash
ai uninstall
```

---

## 扩展

在 `ai.sh` 注册表中添加新 CLI，照 `ai_claude()` 模式实现管理菜单。系统安装对应二进制后自动识别。
