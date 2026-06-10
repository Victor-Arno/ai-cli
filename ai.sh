# ─── AI CLI 管理 ───
AI_DIR="$HOME/.ai-cli"
CLAUDE_PROFILES="$AI_DIR/claude-code"
SERVER_PROFILES="$AI_DIR/servers"
REMOTE_BASE="$HOME/remote-projects"

# ─── 跨平台适配 ───
if [[ "$(uname)" == "Darwin" ]]; then
  _notify() { osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null; }
  _open()   { open "$1" 2>/dev/null; }
  _sedi()   { sed -i '' "$@"; }
else
  _notify() { notify-send "$1" "$2" 2>/dev/null || true; }
  _open()   { xdg-open "$1" 2>/dev/null || true; }
  _sedi()   { sed -i "$@"; }
fi

ai() {
  # CLI 模式
  case "$1" in
    uninstall) ai_uninstall; return ;;
  esac

  while true; do
    clear
    echo '\033[1;36m  开发者工具\033[0m'
    echo ''

    # 实时目录树
    python3 - "$AI_DIR" << 'PYEOF'
import os, sys

base = sys.argv[1]
try:
    entries = sorted(os.listdir(base))
except:
    entries = []

dirs, files = [], []
for e in entries:
    if e.startswith('.'): continue
    path = os.path.join(base, e)
    if os.path.isdir(path):
        dirs.append(e)
    else:
        files.append(e)

print("  \033[1;37m~/.ai-cli/\033[0m")

# 目录注释映射
dir_tags = {
    "claude-code": "  \033[2m# Claude CLI\033[0m",
    "servers": "  \033[2m# 远程服务器\033[0m",
    "gemini": "  \033[2m# Gemini CLI\033[0m",
    "codex": "  \033[2m# Codex CLI\033[0m",
}

all_items = dirs + files
for i, name in enumerate(all_items):
    is_last = (i == len(all_items) - 1)
    conn = "└── " if is_last else "├── "

    if name in dirs:
        tag = dir_tags.get(name, "")
        print(f"  {conn}\033[1;34m{name}/\033[0m{tag}")
    else:
        tag = ""
        if name == "ai.sh": tag = "  \033[2m# 菜单逻辑\033[0m"
        print(f"  {conn}\033[1;33m{name}\033[0m{tag}")

if not all_items:
    print("  \033[2m  (空)\033[0m")
PYEOF

    echo ''
    echo '  \033[1;30m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m'
    echo '  \033[1;37m  功能：\033[0m'
    echo ''

    # 自动检测系统已安装的 CLI → 创建目录 + 导入已有配置为初始 profile
    detect_cli() {
      which "$1" >/dev/null 2>&1 || return
      mkdir -p "$AI_DIR/$2"
      # 目录非空（已有 profile）则跳过导入
      [ "$(ls -A "$AI_DIR/$2" 2>/dev/null)" ] && return
      # 自动导入已有配置
      case "$2" in
        gemini)
          url=$(grep GOOGLE_GEMINI_BASE_URL "$HOME/.gemini/.env" 2>/dev/null | cut -d= -f2-)
          key=$(grep GEMINI_API_KEY "$HOME/.gemini/.env" 2>/dev/null | cut -d= -f2-)
          model=$(grep GEMINI_MODEL "$HOME/.gemini/.env" 2>/dev/null | cut -d= -f2-)
          [ -n "$url" ] && [ -n "$key" ] && python3 - "$url" "$key" "$model" "$AI_DIR/$2/initial.json" << 'IMPORT'
import json, sys
data = {"name": "默认配置", "base_url": sys.argv[1], "api_key": sys.argv[2], "model": sys.argv[3] or "gemini-3-pro-preview"}
json.dump(data, open(sys.argv[4], 'w'), indent=2, ensure_ascii=False)
IMPORT
          ;;
        codex)
          key=$(python3 -c "import json; print(json.load(open('$HOME/.codex/auth.json')).get('OPENAI_API_KEY',''))" 2>/dev/null)
          url=$(grep 'base_url' "$HOME/.codex/config.toml" 2>/dev/null | sed 's/.*= "\(.*\)"/\1/')
          model=$(grep '^model =' "$HOME/.codex/config.toml" 2>/dev/null | sed 's/.*= "\(.*\)"/\1/')
          provider=$(grep '^model_provider =' "$HOME/.codex/config.toml" 2>/dev/null | sed 's/.*= "\(.*\)"/\1/')
          [ -n "$key" ] && [ -n "$url" ] && python3 - "$key" "$url" "$model" "$provider" "$AI_DIR/$2/initial.json" << 'IMPORT'
import json, sys
data = {"name": "默认配置", "api_key": sys.argv[1], "base_url": sys.argv[2], "model": sys.argv[3] or "gpt-5.5", "provider_name": sys.argv[4] or "fox", "effort": "high"}
json.dump(data, open(sys.argv[5], 'w'), indent=2, ensure_ascii=False)
IMPORT
          ;;
      esac
    }
    detect_cli claude claude-code
    detect_cli codex  codex
    detect_cli gemini gemini
    unset -f detect_cli

    # 动态扫描已安装的 CLI（字母序，排除 servers）
    echo '  [1] 远程服务器'

    # 注册表：目录名 → (显示名, 函数名)
    typeset -A CLI_LABEL CLI_FUNC
    CLI_LABEL=(claude-code "Claude CLI" gemini "Gemini CLI" codex "Codex CLI")
    CLI_FUNC=(claude-code ai_claude gemini ai_gemini codex ai_codex)

    n=2
    clis=()
    for d in $(ls -1 "$AI_DIR" 2>/dev/null); do
      [ "$d" = "servers" ] && continue
      [ -d "$AI_DIR/$d" ] || continue

      label="${CLI_LABEL[$d]}"
      [ -z "$label" ] && label="$d"

      func="${CLI_FUNC[$d]}"
      [ -z "$func" ] && func="ai_$d"

      echo "  [$n] $label"
      clis+=("$func")
      ((n++))
    done

    echo '  [q] 退出'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "q" ] && break
    [ "$choice" = "1" ] && { ai_server; continue; }

    idx=$((choice - 1))
    if [ "$idx" -ge 1 ] && [ "$idx" -le "${#clis[@]}" ]; then
      func="${clis[$idx]}"
      if type "$func" >/dev/null 2>&1; then
        "$func"
      else
        echo ''
        echo "\033[1;33m  ${func#ai_} 已检测到，但管理功能尚未实现\033[0m"
        echo "\033[2m  请在 ai.sh 中添加 ${func}() 函数\033[0m"
        sleep 2
      fi
    else
      echo '无效'; sleep 1
    fi
  done
}

# ─── Gemini CLI ───
GEMINI_PROFILES="$AI_DIR/gemini"
GEMINI_ENV="$HOME/.gemini/.env"

ai_gemini() {
  while true; do
    clear
    echo '\033[1;35m  Gemini CLI · API 管理\033[0m'
    echo ''
    echo '  \033[1;37m使用：\033[0m'
    echo '  [1] 切换 API         [2] 查看当前'
    echo ''
    echo '  \033[1;37m配置：\033[0m'
    echo '  [3] 添加 API         [4] 修改 API'
    echo '  [5] 删除 API'
    echo ''
    echo '  \033[1;37m其他：\033[0m'
    echo '  [6] 测试连接'
    echo ''
    echo ''
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice
    case $choice in
      1) ai_gemini_switch ;;
      2) ai_gemini_status ;;
      3) ai_gemini_add ;;
      4) ai_gemini_edit ;;
      5) ai_gemini_delete ;;
      6) ai_gemini_test ;;
      0) return ;;
      *) echo '无效'; sleep 1 ;;
    esac
  done
}

ai_gemini_switch() {
  profiles=($(ls "$GEMINI_PROFILES"/*.json 2>/dev/null))
  if [ ${#profiles[@]} -eq 0 ]; then
    echo '还没有 Gemini API 配置，先添加一个。'; sleep 1
    ai_gemini_add; return
  fi
  while true; do
    clear; echo '\033[1;36m  切换 Gemini API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    python3 - "$profile" "$GEMINI_ENV" << 'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
env = f"GOOGLE_GEMINI_BASE_URL={p['base_url']}\nGEMINI_API_KEY={p['api_key']}\nGEMINI_MODEL={p['model']}\n"
open(sys.argv[2], 'w').write(env)
print(p['name'])
PYEOF
    echo ''
    echo "\033[1;35m已切换至 $name\033[0m"
    _notify "Gemini CLI" "Gemini 已切换至 $name"
    sleep 1; return
  done
}

ai_gemini_add() {
  clear; echo '\033[1;36m  添加 Gemini API\033[0m'; echo ''
  printf '名称（如 Google/FoxCode）: '; read name
  [ -z "$name" ] && { echo '名称不能为空'; sleep 1; return; }
  printf 'Base URL: '; read url
  [ -z "$url" ] && { echo 'URL 不能为空'; sleep 1; return; }
  printf 'API Key: '; read key
  [ -z "$key" ] && { echo 'Key 不能为空'; sleep 1; return; }
  printf 'Model（如 gemini-3-pro-preview）: '; read model
  [ -z "$model" ] && model="gemini-3-pro-preview"

  safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  file="$GEMINI_PROFILES/$safe.json"
  python3 - "$name" "$url" "$key" "$model" "$file" << 'PYEOF'
import json, sys
data = {"name": sys.argv[1], "base_url": sys.argv[2], "api_key": sys.argv[3], "model": sys.argv[4]}
json.dump(data, open(sys.argv[5], 'w'), indent=2, ensure_ascii=False)
PYEOF
  echo ''; echo "\033[1;32m已添加 $name\033[0m"
  printf '要立即切换过去吗？[y/N] '; read yn
  case $yn in
    [yY]*) python3 - "$file" "$GEMINI_ENV" << 'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
env = f"GOOGLE_GEMINI_BASE_URL={p['base_url']}\nGEMINI_API_KEY={p['api_key']}\nGEMINI_MODEL={p['model']}\n"
open(sys.argv[2], 'w').write(env)
PYEOF
      echo "\033[1;35m已切换至 $name\033[0m"
      _notify "Gemini CLI" "Gemini 已切换至 $name" ;;
  esac
  sleep 1
}

ai_gemini_delete() {
  while true; do
    profiles=($(ls "$GEMINI_PROFILES"/*.json 2>/dev/null))
    if [ ${#profiles[@]} -eq 0 ]; then echo '没有可删除的配置'; sleep 1; return; fi
    clear; echo '\033[1;36m  删除 Gemini API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }
    if [ ${#profiles[@]} -le 1 ]; then echo '至少保留一个 API'; sleep 1; continue; fi
    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    printf "\033[1;31m确认删除 $name ? [y/N] \033[0m"; read yn
    case $yn in
      [yY]*) rm "$profile"; echo "\033[1;33m已删除 $name\033[0m" ;;
      *) echo "已取消" ;;
    esac
    sleep 1
  done
}

ai_gemini_status() {
  clear
  python3 - "$GEMINI_ENV" "$GEMINI_PROFILES" << 'PYEOF'
import json, sys, os
cur_url = ""
try:
  for line in open(sys.argv[1]):
    if line.startswith("GOOGLE_GEMINI_BASE_URL="):
      cur_url = line.strip().split("=",1)[1]; break
except: pass
profiles = []
for f in sorted(os.listdir(sys.argv[2])):
  if not f.endswith(".json"): continue
  p = json.load(open(os.path.join(sys.argv[2], f)))
  active = " *" if p.get("base_url") == cur_url else ""
  profiles.append((p["name"], p.get("base_url","?"), p.get("model","-"), active))
print("\033[1;36m  Gemini API 列表\033[0m\n")
print(f"  {'名称':<14} {'URL':<45} {'Model':<24}")
print(f"  {'─'*14} {'─'*45} {'─'*24}")
for name, url, model, active in profiles:
  m = "\033[1;32m" + active.ljust(2) + "\033[0m" if active else "  "
  print(f"  {m} {name:<12} {url:<45} {model:<24}")
print(f"\n  \033[2m* = 当前使用中\033[0m  共 {len(profiles)} 个")
PYEOF
  echo ''; printf '按 Enter 返回...'; read dummy
}

ai_gemini_edit() {
  while true; do
    profiles=($(ls "$GEMINI_PROFILES"/*.json 2>/dev/null))
    [ ${#profiles[@]} -eq 0 ] && { echo '没有可修改的配置'; sleep 1; return; }
    clear; echo '\033[1;36m  修改 Gemini API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    while true; do
      clear
      read name url key model <<< $(python3 -c "
import json
p=json.load(open('$profile'))
print(p['name'], p.get('base_url',''), p.get('api_key',''), p.get('model',''))
")
      echo "\033[1;36m  修改: $name\033[0m"
      echo ''
      echo "  [1] 名称: $name"
      echo "  [2] URL:  $url"
      echo "  [3] Key:  ${key:0:16}..."
      echo "  [4] Model: $model"
      echo '  [0] 返回'
      echo ''
      printf '选择要修改的字段: '; read fld
      [ "$fld" = "0" ] && break

      field=""
      case $fld in
        1) printf '新名称: '; read v; field="name" ;;
        2) printf '新 URL: '; read v; field="base_url" ;;
        3) printf '新 Key: '; read v; field="api_key" ;;
        4) printf '新 Model: '; read v; field="model" ;;
        *) echo '无效'; sleep 1; continue ;;
      esac

      if [ -n "$v" ] && [ -n "$field" ]; then
        python3 - "$profile" "$field" "$v" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d[sys.argv[2]] = sys.argv[3]
json.dump(d, open(sys.argv[1], 'w'), indent=2, ensure_ascii=False)
PYEOF
        ok=$?
        [ $ok -eq 0 ] && echo "\033[1;32m已更新\033[0m" || echo "\033[1;31m失败\033[0m"
        if [ "$field" = "name" ] && [ $ok -eq 0 ]; then
          safe=$(echo "$v" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
          new_file="$(dirname "$profile")/$safe.json"
          [ "$new_file" != "$profile" ] && mv "$profile" "$new_file" && profile="$new_file"
        fi
        if [ $ok -eq 0 ]; then
          cur_url=$(grep GOOGLE_GEMINI_BASE_URL "$GEMINI_ENV" 2>/dev/null | cut -d= -f2-)
          p_url=$(python3 -c "import json; d=json.load(open('$profile')); print(d.get('base_url',''))" 2>/dev/null)
          if [ "$cur_url" = "$p_url" ]; then
            python3 - "$profile" "$GEMINI_ENV" << 'PYEOF'
import json, sys
p = json.load(open(sys.argv[1]))
env = f"GOOGLE_GEMINI_BASE_URL={p['base_url']}\nGEMINI_API_KEY={p['api_key']}\nGEMINI_MODEL={p['model']}\n"
open(sys.argv[2], 'w').write(env)
PYEOF
            echo "\033[1;35m  已同步到 .env\033[0m"
          fi
        fi
      fi
      sleep 1
    done
  done
}

ai_gemini_test() {
  clear; echo '\033[1;36m  测试 Gemini API...\033[0m'; echo ''
  cur_url=$(grep GOOGLE_GEMINI_BASE_URL "$GEMINI_ENV" 2>/dev/null | cut -d= -f2-)
  cur_key=$(grep GEMINI_API_KEY "$GEMINI_ENV" 2>/dev/null | cut -d= -f2-)
  [ -z "$cur_url" ] && { echo '  未配置 URL'; echo ''; printf '按 Enter 返回...'; read dummy; return; }

  name=""
  for f in "$GEMINI_PROFILES"/*.json; do
    [ -f "$f" ] || continue
    p_url=$(python3 -c "import json; print(json.load(open('$f')).get('base_url',''))" 2>/dev/null)
    [ "$p_url" = "$cur_url" ] && name=$(python3 -c "import json; print(json.load(open('$f'))['name'])") && break
  done
  [ -n "$name" ] && echo "  \033[1;37m目标: \033[1;35m$name\033[0m"
  echo "  URL:  \033[2m$cur_url\033[0m"; echo ''

  # 网络
  echo '  \033[1;37m测试网络...\033[0m'
  net=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$cur_url" 2>&1)
  [ "$net" = "000" ] && { echo '  \033[1;31m  ✗ 无法连接\033[0m'; echo ''; printf '按 Enter 返回...'; read dummy; return; }
  echo "  \033[1;32m  ✓ 服务器可达\033[0m"; echo ''

  # Key
  echo '  \033[1;37m测试 Key...\033[0m'
  result=$(curl -s -w "\n%{http_code}" --connect-timeout 15 \
    -H "x-goog-api-key: $cur_key" -H "Content-Type: application/json" \
    -d '{"contents":[{"parts":[{"text":"hi"}]}]}' "$cur_url" 2>&1)
  http_code=$(echo "$result" | tail -1)

  case $http_code in
    200|400|429) echo "  \033[1;32m  ✓ Key 有效 (HTTP $http_code)\033[0m" ;;
    401|403) echo "  \033[1;31m  ✗ Key 无效 (HTTP $http_code)\033[0m" ;;
    000) echo '  \033[1;31m  ✗ 请求超时\033[0m' ;;
    404) echo "  \033[1;33m  ⚠ 继电器务不暴露测试端点 (404)\033[0m"
         echo "  \033[2m  服务器可达，在 Gemini CLI 中能正常使用即说明 Key 有效\033[0m" ;;
    *)   echo "  \033[1;33m  ⚠ HTTP $http_code — 在 Gemini CLI 中实际测试即可\033[0m" ;;
  esac
  echo ''; printf '按 Enter 返回...'; read dummy
}

# ─── Codex CLI ───
CODEX_PROFILES="$AI_DIR/codex"
CODEX_AUTH="$HOME/.codex/auth.json"
CODEX_CONFIG="$HOME/.codex/config.toml"

ai_codex() {
  while true; do
    clear
    echo '\033[1;33m  Codex CLI · API 管理\033[0m'
    echo ''
    echo '  \033[1;37m使用：\033[0m'
    echo '  [1] 切换 API         [2] 查看当前'
    echo ''
    echo '  \033[1;37m配置：\033[0m'
    echo '  [3] 添加 API         [4] 修改 API'
    echo '  [5] 删除 API'
    echo ''
    echo '  \033[1;37m其他：\033[0m'
    echo '  [6] 测试连接'
    echo ''
    echo ''
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice
    case $choice in
      1) ai_codex_switch ;;
      2) ai_codex_status ;;
      3) ai_codex_add ;;
      4) ai_codex_edit ;;
      5) ai_codex_delete ;;
      6) ai_codex_test ;;
      0) return ;;
      *) echo '无效'; sleep 1 ;;
    esac
  done
}

ai_codex_switch() {
  profiles=($(ls "$CODEX_PROFILES"/*.json 2>/dev/null))
  if [ ${#profiles[@]} -eq 0 ]; then
    echo '还没有 Codex API 配置，先添加一个。'; sleep 1
    ai_codex_add; return
  fi
  while true; do
    clear; echo '\033[1;36m  切换 Codex API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    python3 - "$profile" "$CODEX_AUTH" "$CODEX_CONFIG" << 'PYEOF'
import json, sys, os
p = json.load(open(sys.argv[1]))

# 写 auth.json
auth = {"auth_mode": "apikey", "OPENAI_API_KEY": p["api_key"]}
json.dump(auth, open(sys.argv[2], 'w'), indent=2)

# 更新 config.toml 中的关键字段
toml = open(sys.argv[3]).read()
import re
toml = re.sub(r'^model_provider\s*=\s*".*"', f'model_provider = "{p.get("provider_name", "fox")}"', toml, flags=re.M)
toml = re.sub(r'^model\s*=\s*".*"', f'model = "{p["model"]}"', toml, flags=re.M)
toml = re.sub(r'^model_reasoning_effort\s*=\s*".*"', f'model_reasoning_effort = "{p.get("effort", "high")}"', toml, flags=re.M)
toml = re.sub(r'(base_url\s*=\s*)".*"', f'base_url = "{p["base_url"]}"', toml)
open(sys.argv[3], 'w').write(toml)
print(p['name'])
PYEOF
    echo ''
    echo "\033[1;33m已切换至 $name\033[0m"
    _notify "Codex CLI" "Codex 已切换至 $name"
    sleep 1; return
  done
}

ai_codex_add() {
  clear; echo '\033[1;36m  添加 Codex API\033[0m'; echo ''
  printf '名称（如 FoxCode/OpenAI）: '; read name
  [ -z "$name" ] && { echo '名称不能为空'; sleep 1; return; }
  printf 'API Key: '; read key
  [ -z "$key" ] && { echo 'Key 不能为空'; sleep 1; return; }
  printf 'Base URL: '; read url
  [ -z "$url" ] && { echo 'URL 不能为空'; sleep 1; return; }
  printf 'Model（如 gpt-5.5）: '; read model
  [ -z "$model" ] && model="gpt-5.5"
  printf 'Provider 名称（如 fox）: '; read provider
  [ -z "$provider" ] && provider="fox"

  safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  file="$CODEX_PROFILES/$safe.json"
  python3 - "$name" "$key" "$url" "$model" "$provider" "$file" << 'PYEOF'
import json, sys
data = {"name": sys.argv[1], "api_key": sys.argv[2], "base_url": sys.argv[3], "model": sys.argv[4], "provider_name": sys.argv[5], "effort": "high"}
json.dump(data, open(sys.argv[6], 'w'), indent=2, ensure_ascii=False)
PYEOF
  echo ''; echo "\033[1;32m已添加 $name\033[0m"
  printf '要立即切换过去吗？[y/N] '; read yn
  case $yn in
    [yY]*)
      python3 - "$file" "$CODEX_AUTH" "$CODEX_CONFIG" << 'PYEOF'
import json, sys, re
p = json.load(open(sys.argv[1]))
auth = {"auth_mode": "apikey", "OPENAI_API_KEY": p["api_key"]}
json.dump(auth, open(sys.argv[2], 'w'), indent=2)
toml = open(sys.argv[3]).read()
toml = re.sub(r'^model_provider\s*=\s*".*"', f'model_provider = "{p.get("provider_name", "fox")}"', toml, flags=re.M)
toml = re.sub(r'^model\s*=\s*".*"', f'model = "{p["model"]}"', toml, flags=re.M)
toml = re.sub(r'^model_reasoning_effort\s*=\s*".*"', f'model_reasoning_effort = "{p.get("effort", "high")}"', toml, flags=re.M)
toml = re.sub(r'(base_url\s*=\s*)".*"', f'base_url = "{p["base_url"]}"', toml)
open(sys.argv[3], 'w').write(toml)
PYEOF
      echo "\033[1;33m已切换至 $name\033[0m"
      _notify "Codex CLI" "Codex 已切换至 $name" ;;
  esac
  sleep 1
}

ai_codex_delete() {
  while true; do
    profiles=($(ls "$CODEX_PROFILES"/*.json 2>/dev/null))
    if [ ${#profiles[@]} -eq 0 ]; then echo '没有可删除的配置'; sleep 1; return; fi
    clear; echo '\033[1;36m  删除 Codex API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }
    if [ ${#profiles[@]} -le 1 ]; then echo '至少保留一个 API'; sleep 1; continue; fi
    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    printf "\033[1;31m确认删除 $name ? [y/N] \033[0m"; read yn
    case $yn in
      [yY]*) rm "$profile"; echo "\033[1;33m已删除 $name\033[0m" ;;
      *) echo "已取消" ;;
    esac
    sleep 1
  done
}

ai_codex_status() {
  clear
  python3 - "$CODEX_AUTH" "$CODEX_PROFILES" << 'PYEOF'
import json, sys, os
cur_key = ""
try:
  a = json.load(open(sys.argv[1]))
  cur_key = a.get("OPENAI_API_KEY", "")
except: pass
profiles = []
for f in sorted(os.listdir(sys.argv[2])):
  if not f.endswith(".json"): continue
  p = json.load(open(os.path.join(sys.argv[2], f)))
  active = " *" if p.get("api_key") == cur_key else ""
  profiles.append((p["name"], p.get("base_url","?"), p.get("model","-"), active))
print("\033[1;36m  Codex API 列表\033[0m\n")
print(f"  {'名称':<14} {'URL':<45} {'Model':<24}")
print(f"  {'─'*14} {'─'*45} {'─'*24}")
for name, url, model, active in profiles:
  m = "\033[1;32m" + active.ljust(2) + "\033[0m" if active else "  "
  print(f"  {m} {name:<12} {url:<45} {model:<24}")
print(f"\n  \033[2m* = 当前使用中\033[0m  共 {len(profiles)} 个")
PYEOF
  echo ''; printf '按 Enter 返回...'; read dummy
}

ai_codex_edit() {
  while true; do
    profiles=($(ls "$CODEX_PROFILES"/*.json 2>/dev/null))
    [ ${#profiles[@]} -eq 0 ] && { echo '没有可修改的配置'; sleep 1; return; }
    clear; echo '\033[1;36m  修改 Codex API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    while true; do
      clear
      read name key url model provider <<< $(python3 -c "
import json
p=json.load(open('$profile'))
print(p['name'], p.get('api_key',''), p.get('base_url',''), p.get('model',''), p.get('provider_name','fox'))
")
      echo "\033[1;36m  修改: $name\033[0m"
      echo ''
      echo "  [1] 名称:     $name"
      echo "  [2] Key:      ${key:0:16}..."
      echo "  [3] URL:      $url"
      echo "  [4] Model:    $model"
      echo "  [5] Provider: $provider"
      echo '  [0] 返回'
      echo ''
      printf '选择要修改的字段: '; read fld
      [ "$fld" = "0" ] && break

      field=""
      case $fld in
        1) printf '新名称: '; read v; field="name" ;;
        2) printf '新 Key: '; read v; field="api_key" ;;
        3) printf '新 URL: '; read v; field="base_url" ;;
        4) printf '新 Model: '; read v; field="model" ;;
        5) printf '新 Provider: '; read v; field="provider_name" ;;
        *) echo '无效'; sleep 1; continue ;;
      esac

      if [ -n "$v" ] && [ -n "$field" ]; then
        python3 - "$profile" "$field" "$v" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
d[sys.argv[2]] = sys.argv[3]
json.dump(d, open(sys.argv[1], 'w'), indent=2, ensure_ascii=False)
PYEOF
        ok=$?
        [ $ok -eq 0 ] && echo "\033[1;32m已更新\033[0m" || echo "\033[1;31m失败\033[0m"
        if [ "$field" = "name" ] && [ $ok -eq 0 ]; then
          safe=$(echo "$v" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
          new_file="$(dirname "$profile")/$safe.json"
          [ "$new_file" != "$profile" ] && mv "$profile" "$new_file" && profile="$new_file"
        fi
        if [ $ok -eq 0 ]; then
          cur_key=$(python3 -c "import json; d=json.load(open('$CODEX_AUTH')); print(d.get('OPENAI_API_KEY',''))" 2>/dev/null)
          p_key=$(python3 -c "import json; d=json.load(open('$profile')); print(d.get('api_key',''))" 2>/dev/null)
          if [ "$cur_key" = "$p_key" ]; then
            python3 - "$profile" "$CODEX_AUTH" "$CODEX_CONFIG" << 'PYEOF'
import json, sys, re
p = json.load(open(sys.argv[1]))
auth = {"auth_mode": "apikey", "OPENAI_API_KEY": p["api_key"]}
json.dump(auth, open(sys.argv[2], 'w'), indent=2)
toml = open(sys.argv[3]).read()
toml = re.sub(r'^model_provider\s*=\s*".*"', f'model_provider = "{p.get("provider_name", "fox")}"', toml, flags=re.M)
toml = re.sub(r'^model\s*=\s*".*"', f'model = "{p["model"]}"', toml, flags=re.M)
toml = re.sub(r'(base_url\s*=\s*)".*"', f'base_url = "{p["base_url"]}"', toml)
open(sys.argv[3], 'w').write(toml)
PYEOF
            echo "\033[1;33m  已同步到 Codex 配置\033[0m"
          fi
        fi
      fi
      sleep 1
    done
  done
}

ai_codex_test() {
  clear; echo '\033[1;36m  测试 Codex API...\033[0m'; echo ''
  cur_key=$(python3 -c "import json; print(json.load(open('$CODEX_AUTH')).get('OPENAI_API_KEY',''))" 2>/dev/null)
  [ -z "$cur_key" ] && { echo '  未配置 API Key'; echo ''; printf '按 Enter 返回...'; read dummy; return; }
  cur_url=$(grep 'base_url' "$CODEX_CONFIG" 2>/dev/null | sed 's/.*= "\(.*\)"/\1/')
  [ -z "$cur_url" ] && cur_url="https://api.openai.com/v1"

  name=""
  for f in "$CODEX_PROFILES"/*.json; do
    [ -f "$f" ] || continue
    p_key=$(python3 -c "import json; print(json.load(open('$f')).get('api_key',''))" 2>/dev/null)
    [ "$p_key" = "$cur_key" ] && name=$(python3 -c "import json; print(json.load(open('$f'))['name'])") && break
  done
  [ -n "$name" ] && echo "  \033[1;37m目标: \033[1;33m$name\033[0m"
  echo "  URL:  \033[2m$cur_url\033[0m"; echo ''

  # 网络
  echo '  \033[1;37m测试网络...\033[0m'
  net=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$cur_url" 2>&1)
  [ "$net" = "000" ] && { echo '  \033[1;31m  ✗ 无法连接\033[0m'; echo ''; printf '按 Enter 返回...'; read dummy; return; }
  echo "  \033[1;32m  ✓ 服务器可达\033[0m"; echo ''

  # Key
  echo '  \033[1;37m测试 Key...\033[0m'
  result=$(curl -s -w "\n%{http_code}" --connect-timeout 15 \
    -H "Authorization: Bearer $cur_key" -H "Content-Type: application/json" \
    -d '{"model":"gpt-4","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    "$cur_url" 2>&1)
  http_code=$(echo "$result" | tail -1)

  case $http_code in
    200|400|429) echo "  \033[1;32m  ✓ Key 有效 (HTTP $http_code)\033[0m" ;;
    401|403) echo "  \033[1;31m  ✗ Key 无效 (HTTP $http_code)\033[0m" ;;
    000) echo '  \033[1;31m  ✗ 请求超时\033[0m' ;;
    404) echo "  \033[1;33m  ⚠ 继电器务不暴露测试端点 (404)\033[0m"
         echo "  \033[2m  服务器可达，在 Codex CLI 中能正常使用即说明 Key 有效\033[0m" ;;
    *)   echo "  \033[1;33m  ⚠ HTTP $http_code — 在 Codex CLI 中实际测试即可\033[0m" ;;
  esac
  echo ''; printf '按 Enter 返回...'; read dummy
}

# ─── Claude Code ───
ai_claude() {
  while true; do
    clear
    echo '\033[1;34m  Claude CLI · API 管理\033[0m'
    echo ''
    echo '  \033[1;37m使用：\033[0m'
    echo '  [1] 切换 API         [2] 查看当前'
    echo ''
    echo '  \033[1;37m配置：\033[0m'
    echo '  [3] 添加 API         [4] 修改 API'
    echo '  [5] 删除 API'
    echo ''
    echo '  \033[1;37m其他：\033[0m'
    echo '  [6] 测试连接'
    echo ''
    echo ''
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice
    case $choice in
      1) ai_claude_switch ;;
      2) ai_claude_status ;;
      3) ai_claude_add ;;
      4) ai_claude_edit ;;
      5) ai_claude_delete ;;
      6) ai_claude_test ;;
      0) return ;;
      *) echo '无效'; sleep 1 ;;
    esac
  done
}

# 切换 API
ai_claude_switch() {
  profiles=($(ls "$CLAUDE_PROFILES"/*.json 2>/dev/null))
  if [ ${#profiles[@]} -eq 0 ]; then
    echo '还没有 API 配置，先添加一个。'
    sleep 1
    ai_claude_add
    return
  fi

  while true; do
    clear
    echo '\033[1;36m  选择 API：\033[0m'
    echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])" 2>/dev/null)
      echo "  [$i] $name"
      ((i++))
    done
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    cp "$profile" "$HOME/.claude/settings.json"
    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    echo ''
    echo "\033[1;34m已切换至 $name\033[0m"
    _notify "Claude Code" "已切换至 $name"
    sleep 1
    return
  done
}

# 添加 API
ai_claude_add() {
  clear
  echo '\033[1;36m  添加 API\033[0m'
  echo ''
  printf '名称（如 Anthropic/DeepSeek）: '
  read name
  [ -z "$name" ] && { echo '名称不能为空'; sleep 1; return; }

  printf 'Base URL: '
  read url
  [ -z "$url" ] && { echo 'URL 不能为空'; sleep 1; return; }

  printf 'API Key: '
  read key
  [ -z "$key" ] && { echo 'Key 不能为空'; sleep 1; return; }

  printf 'Model（可选）: '
  read model

  safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  file="$CLAUDE_PROFILES/$safe.json"

  python3 - "$name" "$url" "$key" "$model" "$file" "$HOME/.claude/settings.json" << 'PYEOF'
import json, sys
name, url, key, model, file, current = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

# 从当前 settings.json 克隆，然后覆盖 API 相关字段
try:
    data = json.load(open(current))
except:
    data = {"env": {}, "permissions": {}, "theme": ""}

data["name"] = name
data["env"]["ANTHROPIC_BASE_URL"] = url
data["env"]["ANTHROPIC_AUTH_TOKEN"] = key
if model:
    data["model"] = model

with open(file, 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("ok")
PYEOF

  echo ''
  echo "\033[1;32m已添加 $name\033[0m"
  echo ''
  printf '要立即切换过去吗？[y/N] '
  read yn
  case $yn in
    [yY]*) cp "$file" "$HOME/.claude/settings.json"
           echo "\033[1;34m已切换至 $name\033[0m"
           _notify "Claude Code" "已切换至 $name" ;;
  esac
  sleep 1
}

# 删除 API
ai_claude_delete() {
  while true; do
    profiles=($(ls "$CLAUDE_PROFILES"/*.json 2>/dev/null))
    if [ ${#profiles[@]} -eq 0 ]; then
      echo '没有可删除的 API'; sleep 1; return
    fi

    clear
    echo '\033[1;36m  删除 API：\033[0m'
    echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"
      ((i++))
    done
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    if [ ${#profiles[@]} -le 1 ]; then
      echo '至少保留一个 API，不能删除。'; sleep 1; continue
    fi

    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")

    printf "\033[1;31m确认删除 $name ? [y/N] \033[0m"
    read yn
    case $yn in
      [yY]*) rm "$profile"; echo "\033[1;33m已删除 $name\033[0m" ;;
      *) echo "已取消" ;;
    esac
    sleep 1
  done
}

# 查看全部 API
ai_claude_status() {
  clear
  python3 - "$HOME/.claude/settings.json" "$CLAUDE_PROFILES" << 'PYEOF'
import json, sys, os

# 读取当前生效的 URL
current_url = ""
current_model = ""
try:
    d = json.load(open(sys.argv[1]))
    current_url  = d.get("env", {}).get("ANTHROPIC_BASE_URL", "未知")
    current_model = d.get("model", "")
except: pass

# 收集所有 profile
profiles_dir = sys.argv[2]
profiles = []
for f in sorted(os.listdir(profiles_dir)):
    if not f.endswith(".json"): continue
    try:
        p = json.load(open(os.path.join(profiles_dir, f)))
        name = p.get("name", f)
        url  = p.get("env", {}).get("ANTHROPIC_BASE_URL", "?")
        model = p.get("model", "-")
        active = " *" if url == current_url else ""
        profiles.append((name, url, model, active))
    except: pass

print("\033[1;36m  API 列表\033[0m\n")
print(f"  {'名称':<14} {'URL':<50} {'Model':<24}")
print(f"  {'─'*14} {'─'*50} {'─'*24}")

for name, url, model, active in profiles:
    marker = "\033[1;32m" + active.ljust(2) + "\033[0m" if active else "  "
    print(f"  {marker} {name:<12} {url:<50} {model:<24}")

print(f"\n  \033[2m* = 当前使用中\033[0m")
print(f"  共 {len(profiles)} 个 API")
PYEOF
  echo ''
  printf '按 Enter 返回...'
  read dummy
}

# 测试 API 连接
ai_claude_edit() {
  while true; do
    profiles=($(ls "$CLAUDE_PROFILES"/*.json 2>/dev/null))
    [ ${#profiles[@]} -eq 0 ] && { echo '没有可修改的配置'; sleep 1; return; }
    clear; echo '\033[1;36m  修改 Claude API：\033[0m'; echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"; ((i++))
    done
    echo '  [0] 返回'; echo ''
    printf '输入: '; read choice
    [ "$choice" = "0" ] && return
    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    while true; do
      clear
      read name url key model <<< $(python3 -c "
import json
p=json.load(open('$profile'))
print(p['name'], p['env'].get('ANTHROPIC_BASE_URL',''), p['env'].get('ANTHROPIC_AUTH_TOKEN',''), p.get('model',''))
")
      echo "\033[1;36m  修改: $name\033[0m"
      echo ''
      echo "  [1] 名称: $name"
      echo "  [2] URL:  $url"
      echo "  [3] Key:  ${key:0:16}..."
      echo "  [4] Model: $model"
      echo '  [0] 返回'
      echo ''
      printf '选择要修改的字段: '; read fld
      [ "$fld" = "0" ] && break

      field=""
      case $fld in
        1) printf '新名称: '; read v; field="name" ;;
        2) printf '新 URL: '; read v; field="env.ANTHROPIC_BASE_URL" ;;
        3) printf '新 Key: '; read v; field="env.ANTHROPIC_AUTH_TOKEN" ;;
        4) printf '新 Model: '; read v; field="model" ;;
        *) echo '无效'; sleep 1; continue ;;
      esac

      if [ -n "$v" ] && [ -n "$field" ]; then
        python3 - "$profile" "$field" "$v" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
parts = sys.argv[2].split('.')
t = d
for p in parts[:-1]:
    t = t.setdefault(p, {})
t[parts[-1]] = sys.argv[3]
json.dump(d, open(sys.argv[1], 'w'), indent=2, ensure_ascii=False)
PYEOF
        ok=$?
        [ $ok -eq 0 ] && echo "\033[1;32m已更新\033[0m" || echo "\033[1;31m失败\033[0m"
        if [ "$field" = "name" ] && [ $ok -eq 0 ]; then
          safe=$(echo "$v" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
          new_file="$(dirname "$profile")/$safe.json"
          [ "$new_file" != "$profile" ] && mv "$profile" "$new_file" && profile="$new_file"
        fi
        # 如果编辑的是当前使用的 API，同步到 settings.json
        if [ $ok -eq 0 ]; then
          cur_url=$(python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
          p_url=$(python3 -c "import json; d=json.load(open('$profile')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
          [ "$cur_url" = "$p_url" ] && cp "$profile" "$HOME/.claude/settings.json" && echo "\033[1;34m  已同步到 settings.json\033[0m"
        fi
      fi
      sleep 1
    done
  done
}

ai_claude_test() {
  clear
  echo '\033[1;36m  测试 API 连接...\033[0m'
  echo ''

  url=$(python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print(d.get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
  key=$(python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print(d.get('env',{}).get('ANTHROPIC_AUTH_TOKEN',''))" 2>/dev/null)

  # 匹配当前 API 名称
  name=""
  for f in "$CLAUDE_PROFILES"/*.json; do
    [ -f "$f" ] || continue
    p_url=$(python3 -c "import json; print(json.load(open('$f')).get('env',{}).get('ANTHROPIC_BASE_URL',''))" 2>/dev/null)
    if [ "$p_url" = "$url" ]; then
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      break
    fi
  done

  if [ -z "$url" ]; then
    echo '  \033[1;31m未配置 API\033[0m'
    echo ''
    printf '按 Enter 返回...'
    read dummy
    return
  fi

  echo "  \033[1;37m目标: \033[1;34m$name\033[0m"
  echo "  URL:   \033[2m$url\033[0m"
  echo ''

  # 网络连通性
  echo '  \033[1;37m测试网络...\033[0m'
  net_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>&1)

  if [ "$net_code" = "000" ]; then
    echo '  \033[1;31m  ✗ 无法连接服务器（网络不通或 DNS 失败）\033[0m'
    echo ''
    printf '按 Enter 返回...'
    read dummy
    return
  fi
  echo "  \033[1;32m  ✓ 服务器可达\033[0m"
  echo ''

  # API Key 有效性
  echo '  \033[1;37m测试 Key...\033[0m'
  result=$(curl -s -w "\n%{http_code}" --connect-timeout 15 \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
    "${url}/messages" 2>&1)

  http_code=$(echo "$result" | tail -1)

  case $http_code in
    200|400|429) echo "  \033[1;32m  ✓ Key 有效 (HTTP $http_code)\033[0m" ;;
    401|403) echo "  \033[1;31m  ✗ Key 无效 (HTTP $http_code)\033[0m" ;;
    000) echo '  \033[1;31m  ✗ 请求超时\033[0m' ;;
    404) result2=$(curl -s -w "\n%{http_code}" --connect-timeout 15 \
           -H "Authorization: Bearer $key" -H "Content-Type: application/json" \
           -d '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
           "${url}/v1/messages" 2>&1)
         code2=$(echo "$result2" | tail -1)
         case $code2 in
           200|400|429) echo "  \033[1;32m  ✓ Key 有效 (HTTP $code2)\033[0m" ;;
           401|403) echo "  \033[1;31m  ✗ Key 无效 (HTTP $code2)\033[0m" ;;
           *) echo "  \033[1;33m  ⚠ 继电器务不暴露测试端点\033[0m"
              echo "  \033[2m  服务器可达，在 Claude Code 中能正常使用即说明 Key 有效\033[0m" ;;
         esac ;;
    *) echo "  \033[1;33m  ⚠ HTTP $http_code — 建议在 Claude Code 中实际测试\033[0m" ;;
  esac

  echo ''
  printf '按 Enter 返回...'
  read dummy
}

# ─── 远程服务器 ───
ai_server() {
  while true; do
    clear
    echo '\033[1;32m  远程服务器\033[0m'
    echo ''
    echo '  \033[1;37m连接：\033[0m'
    echo '  [1] 挂载         [2] 断开'
    echo ''
    echo '  \033[1;37m配置：\033[0m'
    echo '  [3] 添加         [4] 删除'
    echo ''
    echo '  \033[1;37m其他：\033[0m'
    echo '  [5] 查看全部     [6] 使用说明'
    echo '  [7] 测试连接'
    echo ''
    echo ''
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice
    case $choice in
      1) ai_server_mount ;;
      2) ai_server_umount ;;
      3) ai_server_add ;;
      4) ai_server_delete ;;
      5) ai_server_status ;;
      6) ai_server_help ;;
      7) ai_server_test ;;
      0) return ;;
      *) echo '无效'; sleep 1 ;;
    esac
  done
}

# 使用说明
ai_server_help() {
  clear
  python3 << 'PYEOF'
print("""\033[1;36m  远程服务器 ── 使用说明\033[0m

\033[1;37m原理\033[0m
  通过 SSHFS 将远程服务器目录挂载到本地，Claude Code
  等 AI 工具可直接读写远程文件，无需在服务器上安装任何东西。

\033[1;37m菜单结构\033[0m
  \033[2m连接：\033[0m  [1] 挂载    [2] 断开     ← 日常使用
  \033[2m配置：\033[0m  [3] 添加    [4] 删除     ← 一次性操作
  \033[2m其他：\033[0m  [5] 查看    [6] 说明

\033[1;37m典型流程\033[0m
  \033[1;33m[3]\033[0m 添加 → \033[1;33m[1]\033[0m 挂载 → 写代码/跑模型 → \033[1;33m[2]\033[0m 断开
         └── 一次性 ──┘   └────── 每天循环 ──────┘

  \033[1;33m[1]\033[0m 挂载成功后 Finder 自动打开该目录，Mac 上任何
      程序都能直接读写远程文件，跟本地文件夹一样
  \033[1;33m[2]\033[0m 断开连接，配置保留，下次再挂载即可
  \033[1;33m[4]\033[0m 彻底删除：自动断开 + 删配置 + 清目录

\033[1;37m完整流程\033[0m
  \033[1;33m1\033[0m  添加服务器 → 输入名称、SSH 地址、远程路径
  \033[1;33m2\033[0m  挂载服务器 → 选择服务器，一键挂载
  \033[1;33m3\033[0m  挂载成功后 Finder 自动打开该目录
     此时 Mac 上的任何程序（Claude Code、VSCode、
     终端）都能直接读写远程文件，跟本地文件夹一样
  \033[1;33m4\033[0m  在 Claude Code 中打开该目录，正常写代码
  \033[1;33m5\033[0m  需要运行 GPU 任务时，让 Claude 通过 SSH
     在服务器上执行：\033[2mssh user@host "python train.py"\033[0m
  \033[1;33m6\033[0m  用完后断开连接

\033[1;37mAI 编码场景\033[0m
  • Claude Code 在 Mac 本地读写挂载目录 → 文件自动
    通过 SSH 同步到服务器
  • 需要 GPU 时，让 Claude 通过 SSH 远程执行：
    \033[2mssh user@host "python train.py"\033[0m
  • 服务器只需有 SSH，不需要装 Claude Code

\033[1;37m前置条件\033[0m
  \033[2m  brew install --cask macfuse\033[0m
  \033[2m  brew install sshfs\033[0m
""")
PYEOF
  echo ''
  printf '按 Enter 返回...'
  read dummy
}

# 测试服务器连接
ai_server_test() {
  profiles=($(ls "$SERVER_PROFILES"/*.json 2>/dev/null))
  if [ ${#profiles[@]} -eq 0 ]; then
    echo '没有服务器配置。'; sleep 1; return
  fi

  while true; do
    clear
    echo '\033[1;36m  测试服务器连接\033[0m'
    echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"
      ((i++))
    done
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    host=$(python3 -c "import json; print(json.load(open('$profile'))['host'])")

    echo ''
    echo "  \033[1;37m目标: \033[1;32m$name\033[0m"
    echo "  SSH:   \033[2m$host\033[0m"
    echo ''
    echo "\033[1;34m  正在连接...\033[0m"
    echo ''

    result=$(ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$host" "echo ok && uname -a" 2>&1)

    if [ $? -eq 0 ]; then
      echo "  \033[1;32m✓ 连接成功\033[0m"
      echo "  \033[2m  $(echo "$result" | head -1)\033[0m"
    else
      echo "  \033[1;31m✗ 连接失败\033[0m"
      echo "  \033[2m  $(echo "$result" | tail -3)\033[0m"
    fi
    sleep 2
    return
  done
}

# 挂载服务器
ai_server_mount() {
  profiles=($(ls "$SERVER_PROFILES"/*.json 2>/dev/null))
  if [ ${#profiles[@]} -eq 0 ]; then
    echo '还没有服务器配置，先添加一个。'
    sleep 1
    ai_server_add
    return
  fi

  while true; do
    clear
    echo '\033[1;36m  挂载服务器\033[0m'
    echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
      if mount | grep -q "$REMOTE_BASE/$safe"; then
        echo "  [$i] $name  \033[1;32m● 已挂载\033[0m"
      else
        echo "  [$i] $name"
      fi
      ((i++))
    done
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    host=$(python3 -c "import json; print(json.load(open('$profile'))['host'])")
    remote_path=$(python3 -c "import json; print(json.load(open('$profile'))['remote_path'])")
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    mount_point="$REMOTE_BASE/$safe"

    if mount | grep -q "$mount_point"; then
      echo ''
      echo "\033[1;33m$name 已挂载在 $mount_point\033[0m"
      sleep 1
      continue
    fi

    mkdir -p "$mount_point" 2>/dev/null

    echo ''
    echo "\033[1;34m正在挂载 $name ...\033[0m"
    sshfs "$host:$remote_path" "$mount_point" -ovolname="$name" 2>&1

    if [ $? -eq 0 ]; then
      echo "\033[1;32m已挂载 → $mount_point\033[0m"
      _open "$mount_point"
    else
      echo "\033[1;31m挂载失败，请检查 SSH 连接和 sshfs 是否已安装\033[0m"
    fi
    sleep 2
    return
  done
}

# 卸载服务器
ai_server_umount() {
  while true; do
    profiles=($(ls "$SERVER_PROFILES"/*.json 2>/dev/null))
    if [ ${#profiles[@]} -eq 0 ]; then
      echo '没有服务器配置。'; sleep 1; return
    fi

    clear
    echo '\033[1;36m  卸载服务器\033[0m'
    echo ''

    i=1
    mounted_list=()
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
      mount_point="$REMOTE_BASE/$safe"
      if mount | grep -q "$mount_point"; then
        echo "  [$i] $name  → $mount_point"
        mounted_list+=("$f")
        ((i++))
      fi
    done

    if [ ${#mounted_list[@]} -eq 0 ]; then
      echo '  没有已挂载的服务器。'
      echo ''
      printf '按 Enter 返回...'
      read dummy
      return
    fi

    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${mounted_list[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    mount_point="$REMOTE_BASE/$safe"

    echo ''
    echo "\033[1;34m正在卸载 $name ...\033[0m"
    umount "$mount_point" 2>&1

    if [ $? -eq 0 ]; then
      echo "\033[1;32m$name 已卸载\033[0m"
      rmdir "$mount_point" 2>/dev/null
    else
      echo "\033[1;31m卸载失败，请确认没有程序正在使用该目录\033[0m"
    fi
    sleep 1
    return
  done
}

# 添加服务器
ai_server_add() {
  clear
  echo '\033[1;36m  添加服务器\033[0m'
  echo ''
  printf '名称（如 GPU服务器）: '
  read name
  [ -z "$name" ] && { echo '名称不能为空'; sleep 1; return; }

  printf 'SSH 连接（如 user@10.0.0.1）: '
  read host
  [ -z "$host" ] && { echo '连接地址不能为空'; sleep 1; return; }

  printf '远程路径（如 /home/user/project）: '
  read remote_path
  [ -z "$remote_path" ] && { echo '路径不能为空'; sleep 1; return; }

  safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  file="$SERVER_PROFILES/$safe.json"

  python3 - "$name" "$host" "$remote_path" "$file" << 'PYEOF'
import json, sys
data = {"name": sys.argv[1], "host": sys.argv[2], "remote_path": sys.argv[3]}
with open(sys.argv[4], 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
print("ok")
PYEOF

  echo ''
  echo "\033[1;32m已添加 $name\033[0m"
  echo "\033[2m   挂载点: $REMOTE_BASE/$safe\033[0m"
  echo ''
  printf '要立即挂载吗？[y/N] '
  read yn
  case $yn in
    [yY]*)
      mount_point="$REMOTE_BASE/$safe"
      mkdir -p "$mount_point" 2>/dev/null
      sshfs "$host:$remote_path" "$mount_point" -ovolname="$name" 2>&1
      if [ $? -eq 0 ]; then
        echo "\033[1;32m已挂载 → $mount_point\033[0m"
        _open "$mount_point"
      else
        echo "\033[1;31m挂载失败\033[0m"
      fi ;;
  esac
  sleep 1
}

# 删除服务器
ai_server_delete() {
  while true; do
    profiles=($(ls "$SERVER_PROFILES"/*.json 2>/dev/null))
    if [ ${#profiles[@]} -eq 0 ]; then
      echo '没有可删除的服务器'; sleep 1; return
    fi

    clear
    echo '\033[1;36m  删除服务器\033[0m'
    echo ''
    i=1
    for f in "${profiles[@]}"; do
      name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
      echo "  [$i] $name"
      ((i++))
    done
    echo '  [0] 返回'
    echo ''
    printf '输入: '
    read choice

    [ "$choice" = "0" ] && return

    profile="${profiles[$choice]}"
    [ -z "$profile" ] && { echo '无效'; sleep 1; continue; }

    name=$(python3 -c "import json; print(json.load(open('$profile'))['name'])")
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    mount_point="$REMOTE_BASE/$safe"

    extra=""
    if mount | grep -q "$mount_point"; then
      extra="\033[1;33m  ⚠ 该服务器已挂载，删除前将自动卸载\033[0m"
    fi

    printf "\033[1;31m确认删除 $name ? [y/N] \033[0m"
    echo "$extra"
    read yn
    case $yn in
      [yY]*)
        if mount | grep -q "$mount_point"; then
          umount "$mount_point" 2>/dev/null
        fi
        rmdir "$mount_point" 2>/dev/null
        rm "$profile"
        echo "\033[1;33m已删除 $name\033[0m" ;;
      *) echo "已取消" ;;
    esac
    sleep 1
  done
}

# 查看全部服务器
ai_server_status() {
  clear
  python3 - "$SERVER_PROFILES" "$REMOTE_BASE" << 'PYEOF'
import json, sys, os, subprocess

profiles_dir = sys.argv[1]
remote_base = sys.argv[2]

profiles = []
for f in sorted(os.listdir(profiles_dir)):
    if not f.endswith(".json"): continue
    try:
        p = json.load(open(os.path.join(profiles_dir, f)))
        name = p.get("name", f)
        host = p.get("host", "?")
        remote_path = p.get("remote_path", "?")

        safe = ''.join(c for c in name.lower().replace(' ', '-') if c.isalnum() or c == '-')
        mount_point = os.path.join(remote_base, safe)

        try:
            result = subprocess.run(["mount"], capture_output=True, text=True)
            mounted = mount_point in result.stdout
        except:
            mounted = False

        status = "\033[1;32m● 已挂载\033[0m" if mounted else "\033[2m○ 未挂载\033[0m"
        profiles.append((name, host, remote_path, mount_point, status, mounted))
    except:
        pass

print("\033[1;36m  服务器列表\033[0m\n")

for name, host, remote_path, mount_point, status, mounted in profiles:
    print(f"  \033[1m{name}\033[0m  {status}")
    print(f"    连接: \033[2m{host}\033[0m")
    print(f"    远程: \033[2m{remote_path}\033[0m")
    print(f"    本地: \033[2m{mount_point}\033[0m")
    print()

print(f"  共 {len(profiles)} 台服务器")
PYEOF
  echo ''
  printf '按 Enter 返回...'
  read dummy
}

# ─── 卸载 ───
ai_uninstall() {
  clear
  echo '\033[1;31m  卸载 AI CLI 工具箱\033[0m'
  echo ''
  echo '  将执行以下操作：'
  echo '  • 卸载所有已挂载的远程服务器'
  echo '  • 从 ~/.zshrc 移除 source 行'
  echo '  • 删除 ~/.ai-cli/ 整个目录'
  echo '  • 删除 ~/remote-projects/（如为空）'
  echo ''
  printf '\033[1;31m确认卸载？输入 yes 继续: \033[0m'
  read confirm

  if [ "$confirm" != "yes" ]; then
    echo '已取消'
    return
  fi

  echo ''
  echo '正在清理...'

  # 卸载所有服务器
  if [ -d "$SERVER_PROFILES" ]; then
    for f in "$SERVER_PROFILES"/*.json; do
      [ -f "$f" ] || continue
    name=$(python3 -c "import json; print(json.load(open('$f'))['name'])")
    safe=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
    mount_point="$REMOTE_BASE/$safe"
    if mount | grep -q "$mount_point"; then
      umount "$mount_point" 2>/dev/null
      echo "  已卸载 $name"
    fi
    rmdir "$mount_point" 2>/dev/null
    done
  fi

  # 从 .zshrc 移除 source 行
  if [ -f "$HOME/.zshrc" ]; then
    _sedi '/source.*ai-cli\/ai.sh/d' "$HOME/.zshrc"
    echo '  已从 .zshrc 移除'
  fi

  # 删除目录
  rm -rf "$AI_DIR"
  rmdir "$REMOTE_BASE" 2>/dev/null

  echo ''
  echo '\033[1;32m卸载完成。重开终端或 source ~/.zshrc 生效。\033[0m'
}

# ─── 启动提示 ───
echo ''
echo '\033[1;36m  ╔══════════════════════════════════════════════╗\033[0m'
echo '\033[1;36m  ║                                              ║\033[0m'
echo '\033[1;36m  ║\033[0m  \033[1;37mAI CLI 开发者工具箱                       \033[0m  \033[1;36m║\033[0m'
echo '\033[1;36m  ║\033[0m  \033[2mClaude Code · Gemini CLI · Codex CLI      \033[0m  \033[1;36m║\033[0m'
echo '\033[1;36m  ║\033[0m  \033[2mAPI 管理 · 远程服务器 · SSHFS 挂载        \033[0m  \033[1;36m║\033[0m'
echo '\033[1;36m  ║                                              ║\033[0m'
echo '\033[1;36m  ║\033[0m  \033[1;33m输入 ai 进入                              \033[0m  \033[1;36m║\033[0m'
echo '\033[1;36m  ╚══════════════════════════════════════════════╝\033[0m'
echo '\033[2m                                      by VictorArno\033[0m'
echo ''
