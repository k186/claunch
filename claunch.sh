#!/bin/zsh
#
# claunch.sh — Claude Code smart launcher with fzf model switcher
#
# Author:  k186
# License: MIT
# Repo:    https://github.com/k186/claunch
#
# Usage (add to .zshrc):
#   function ca {
#     source "$HOME/.claude/claunch.sh" "$@"
#     if (( $+functions[p10k] )); then p10k reload 2>/dev/null
#     else for _ca_f in "${precmd_functions[@]}"; do "$_ca_f" 2>/dev/null; done; unset _ca_f; fi
#   }
#
# ca              — pass-through; launches Claude with its default model
# ca --new        — pick a model with fzf, then launch Claude
# ca --list       — browse models (Enter=launch, e=edit, Del=delete)
# ca --add        — add a new model interactively
# ca --remove     — remove a model via fzf picker
# ca --current    — show the model active in this window
# ca --update     — update claunch to the latest version
# ca --lang       — show / set language (en / zh)
# ca --help       — show this help
# ca --continue   — resume the last session, restoring its recorded model
# ca --resume <id> — resume a specific session, restoring its recorded model

# Resolve config file: $CLAUNCH_MODELS_CFG override, then the new default
# ~/.config/claunch/models.json, then the legacy ~/.claude/models.json.
_ca_resolve_cfg() {
  local new_cfg="$HOME/.config/claunch/models.json"
  local legacy_cfg="$HOME/.claude/models.json"
  if [[ -n "$CLAUNCH_MODELS_CFG" ]]; then
    echo "$CLAUNCH_MODELS_CFG"
  elif [[ -f "$new_cfg" ]]; then
    echo "$new_cfg"
  elif [[ -f "$legacy_cfg" ]]; then
    echo "$legacy_cfg"
  else
    echo "$new_cfg"
  fi
}

MODELS_CFG=$(_ca_resolve_cfg)
# Each conversation id keeps its own tiny config under the config directory:
# ~/.config/claunch/sessions/<session-id>.json
SESSION_DIR="${MODELS_CFG:h}/sessions"
CLAUNCH_VERSION="2.0.0"
CLAUNCH_RAW="https://raw.githubusercontent.com/k186/claunch/main"

# Save KSH_ARRAYS state and enable locally (0-indexed to match jq)
[[ -o ksharrays ]] && _ca_had_ksharrays=1 || _ca_had_ksharrays=0
setopt KSH_ARRAYS

_ca_restore_opts() {
  (( _ca_had_ksharrays )) || unsetopt KSH_ARRAYS
  unset _ca_had_ksharrays
}

# ── i18n strings ──────────────────────────────────────────────────────────────

_CA_LANG=$(jq -r '.lang // "en"' "$MODELS_CFG" 2>/dev/null)
_CA_LANG="${_CA_LANG:-en}"

if [[ "$_CA_LANG" == "zh" ]]; then
  _S_LIST_HDR=$'  ↑ ↓  导航    Enter  启动    e  编辑    Del  删除    Esc  退出\n'
  _S_NEW_HDR="选择模型"
  _S_NEW_PROMPT="选择模型 > "
  _S_REMOVE_HDR="选择要删除的模型"
  _S_REMOVE_PROMPT="删除 > "
  _S_LAUNCHING="  正在启动: %s\n"
  _S_SWITCHED="  已切换至: %s\n"
  _S_CANCELLED="  已取消。"
  _S_CONFIRM_DEL='  删除模型 "%s"？此操作不可撤销。[Y/n]: '
  _S_DELETED="  已删除: %s\n"
  _S_EDIT_TITLE="  编辑: %s\n"
  _S_EDIT_HINT="  ─────────────── (回车保留当前值，- 清空)"
  _S_UPDATED="  已更新: %s\n"
  _S_ADD_TITLE="  添加模型"
  _S_ADD_SEP="  ─────────"
  _S_ADDED="  已添加: %s\n"
  _S_REMOVED="  已删除: %s\n"
  _S_CURR_MODEL="  模型:    %s\n"
  _S_CURR_PROV="  服务商: %s\n"
  _S_CURR_DEF="  模型:    默认（未通过 claunch 设置）"
  _S_UPGRADING="  正在升级 claunch..."
  _S_UPG_DONE="  完成。请重启终端或执行: source ~/.zshrc"
  _S_UPG_FAIL="  升级失败，请检查网络连接。"
  _S_UPD_AVAIL=$'\n  claunch %s 可用（当前: %s）\n  执行: ca --update\n'
  _S_UNKNOWN="  未知选项: %s\n"
  _S_LANG_SET="  语言已设置为: %s\n"
  _S_LANG_CURR="  当前语言: %s\n"
  _S_LANG_USAGE="  用法: ca --lang en | ca --lang zh"
  _S_LANG_ERR="  支持的语言: en, zh"
  _S_F_NAME="显示名称"
  _S_F_BASEURL="Base URL"
  _S_F_AUTH="Auth token"
  _S_F_MODEL="ANTHROPIC_MODEL"
  _S_F_CONTEXT="Context window"
  _S_F_MODELID="Model ID"
  _S_P_NAME="  显示名称: "
  _S_P_BASEURL="  Base URL（空 = Anthropic 默认）: "
  _S_P_AUTH="  Auth token: "
  _S_P_MODEL="  ANTHROPIC_MODEL: "
  _S_P_CONTEXT="  Context window（空则跳过，如 1000000）: "
  _S_P_MODELID="  Model ID（如 claude-opus-4-7）: "
else
  _S_LIST_HDR=$'  ↑ ↓  navigate    Enter  launch    e  edit    Del  delete    Esc  exit\n'
  _S_NEW_HDR="Select a Model"
  _S_NEW_PROMPT="Select a Model > "
  _S_REMOVE_HDR="Select model to remove"
  _S_REMOVE_PROMPT="Remove > "
  _S_LAUNCHING="  Launching: %s\n"
  _S_SWITCHED="  Switched to: %s\n"
  _S_CANCELLED="  Cancelled."
  _S_CONFIRM_DEL='  Delete model "%s"? This cannot be undone. [Y/n]: '
  _S_DELETED="  Deleted: %s\n"
  _S_EDIT_TITLE="  Edit: %s\n"
  _S_EDIT_HINT="  ─────────────── (Enter = keep current, - = clear)"
  _S_UPDATED="  Updated: %s\n"
  _S_ADD_TITLE="  Add model"
  _S_ADD_SEP="  ─────────"
  _S_ADDED="  Added: %s\n"
  _S_REMOVED="  Removed: %s\n"
  _S_CURR_MODEL="  Model:    %s\n"
  _S_CURR_PROV="  Provider: %s\n"
  _S_CURR_DEF="  Model:    default (not set via claunch in this window)"
  _S_UPGRADING="  Upgrading claunch..."
  _S_UPG_DONE="  Done. Restart your shell or run: source ~/.zshrc"
  _S_UPG_FAIL="  Upgrade failed. Check your connection."
  _S_UPD_AVAIL=$'\n  claunch %s available (current: %s)\n  Run: ca --update\n'
  _S_UNKNOWN="  Unknown option: %s\n"
  _S_LANG_SET="  Language set to: %s\n"
  _S_LANG_CURR="  Current language: %s\n"
  _S_LANG_USAGE="  Usage: ca --lang en | ca --lang zh"
  _S_LANG_ERR="  Supported languages: en, zh"
  _S_F_NAME="Display name"
  _S_F_BASEURL="Base URL"
  _S_F_AUTH="Auth token"
  _S_F_MODEL="ANTHROPIC_MODEL"
  _S_F_CONTEXT="Context window"
  _S_F_MODELID="Model ID"
  _S_P_NAME="  Display name: "
  _S_P_BASEURL="  Base URL (blank = Anthropic default): "
  _S_P_AUTH="  Auth token: "
  _S_P_MODEL="  ANTHROPIC_MODEL: "
  _S_P_CONTEXT="  Context window (blank to skip, e.g. 1000000): "
  _S_P_MODELID="  Model ID (e.g. claude-opus-4-7): "
fi

# ── Model env helpers ─────────────────────────────────────────────────────────

build_model_env() {
  local idx=$1
  MODEL_ENV_EXPORTS=()
  MODEL_FLAG=""

  local model_val
  model_val=$(jq -r --argjson i "$idx" '.models[$i].model // ""' "$MODELS_CFG")
  [[ -n "$model_val" ]] && MODEL_FLAG="$model_val"

  local env_json
  env_json=$(jq -c --argjson i "$idx" '.models[$i].env // {}' "$MODELS_CFG")
  if [[ "$env_json" != "{}" ]]; then
    local key val
    while IFS='=' read -r key val; do
      MODEL_ENV_EXPORTS+=("$key=$val")
    done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
  fi
}

select_model() {
  local names=()
  local count=0
  local line
  while IFS= read -r line; do
    names+=("$line")
    ((count++))
  done < <(jq -r '.models[].name' "$MODELS_CFG")

  local choice
  choice=$(printf '%s\n' "${names[@]}" | fzf \
    --height=~50% \
    --border=rounded \
    --margin=1,2 \
    --padding=1 \
    --reverse \
    --prompt="$_S_NEW_PROMPT" \
    --header="$_S_NEW_HDR" \
    --color=border:7 \
    --no-info 2>&1)
  local ret=$?

  if (( ret != 0 )) || [[ -z "$choice" ]]; then
    echo ""
    echo "  $_S_CANCELLED"
    return 1
  fi

  local idx=0 i
  for ((i=0; i<count; i++)); do
    if [[ "${names[$i]}" == "$choice" ]]; then
      idx=$i
      break
    fi
  done

  SELECTED_IDX=$idx
  SELECTED_NAME="$choice"
  printf "$_S_SWITCHED" "$choice"
  return 0
}

launch_claude() {
  local cmd_env=()
  for e in "${MODEL_ENV_EXPORTS[@]}"; do
    cmd_env+=("$e")
  done

  local claude_args=(--dangerously-skip-permissions)
  [[ -n "$MODEL_FLAG" ]] && claude_args+=(--model "$MODEL_FLAG")
  claude_args+=("$@")

  _ca_launch_start=$(date +%s)
  if (( ${#cmd_env[@]} > 0 )); then
    env "${cmd_env[@]}" claude "${claude_args[@]}"
  else
    claude "${claude_args[@]}"
  fi
  local _ca_rc=$?
  _ca_record_session "$_CA_MODEL_NAME"
  unset _ca_launch_start

  # Restore terminal state after claude exits
  # (must run here — not in a trap — because this script is sourced)
  printf '\033[?1049l'  # exit alternate screen
  printf '\033[?1000l\033[?1002l\033[?1006l'  # disable mouse tracking
  printf '\033[?2004l'  # disable bracketed paste
  printf '\033[?2026l'  # disable synchronized output (fixes p10k)
  printf '\033[?1l\033[?25h\033[0m\r'  # cursor keys / show cursor / reset colors
  stty sane 2>/dev/null
  return $_ca_rc
}

# ── Model / session persistence ──────────────────────────────────────────────

_ca_claude_dir() {
  echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
}

# Apply the model entry matching a model string (entry name, --model id, or
# env.ANTHROPIC_MODEL); sets MODEL_FLAG / MODEL_ENV_EXPORTS.
_ca_apply_model_by_string() {
  local target="$1" count i n m e
  [[ -z "$target" ]] && return 1
  count=$(jq '.models | length' "$MODELS_CFG" 2>/dev/null) || return 1
  for ((i=0; i<count; i++)); do
    n=$(jq -r --argjson i "$i" '.models[$i].name' "$MODELS_CFG")
    m=$(jq -r --argjson i "$i" '.models[$i].model // ""' "$MODELS_CFG")
    e=$(jq -r --argjson i "$i" '.models[$i].env.ANTHROPIC_MODEL // ""' "$MODELS_CFG")
    if [[ "$target" == "$n" || "$target" == "$m" || "$target" == "$e" ]]; then
      build_model_env "$i"
      _CA_MODEL_NAME="$n"
      return 0
    fi
  done
  return 1
}

_ca_save_last_model() {
  local name="$1" tmp
  tmp=$(mktemp)
  if jq --arg n "$name" '.last_model = $n' "$MODELS_CFG" > "$tmp" 2>/dev/null \
     && mv "$tmp" "$MODELS_CFG"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Each conversation id keeps its own tiny config file:
#   ~/.config/claunch/sessions/<session-id>.json  →  {"model":"<model string>"}
_ca_save_session() {
  local sid="$1" name="$2" tmp
  [[ -n "$sid" && -n "$name" ]] || return 1
  mkdir -p "$SESSION_DIR"
  tmp=$(mktemp)
  if jq -n --arg m "$name" '{model:$m}' > "$tmp" 2>/dev/null \
     && mv "$tmp" "$SESSION_DIR/$sid.json"; then
    _ca_prune_sessions
    return 0
  fi
  rm -f "$tmp"
  return 1
}

_ca_session_model() {
  local sid="$1"
  local f="$SESSION_DIR/$sid.json"
  [[ -f "$f" ]] || return 1
  jq -r '.model // ""' "$f" 2>/dev/null
}

# Locate a session transcript by id (prefer the current project's dir).
_ca_find_session_file() {
  local sid="$1" proj="$(_ca_claude_dir)/projects" enc="${PWD//[^A-Za-z0-9]/-}" f
  [[ -d "$proj" ]] || return 1
  f="$proj/$enc/$sid.jsonl"
  if [[ ! -f "$f" ]]; then
    f=$(find "$proj" -name "$sid.jsonl" -type f 2>/dev/null | head -1)
  fi
  [[ -f "$f" ]] && echo "$f" || return 1
}

# Read the model actually used by a session from its transcript.
_ca_session_file_model() {
  local f="$1" m
  [[ -f "$f" ]] || return 1
  m=$(jq -r 'select(.type == "assistant" and (.message.model // "") != "") | .message.model' "$f" 2>/dev/null | tail -1)
  if [[ -z "$m" ]]; then
    m=$(jq -r 'select(.type == "session_start" and (.model // "") != "") | .model' "$f" 2>/dev/null | tail -1)
  fi
  [[ -n "$m" ]] && echo "$m" || return 1
}

# Resume a session id with its recorded model, if any:
# session record → transcript parse → pass-through.
_ca_resume_session() {
  local sid="$1" m f
  [[ -z "$sid" ]] && return 1
  m=$(_ca_session_model "$sid") || m=""
  if [[ -n "$m" ]] && _ca_apply_model_by_string "$m"; then
    return 0
  fi
  f=$(_ca_find_session_file "$sid") || return 1
  m=$(_ca_session_file_model "$f") || return 1
  _ca_apply_model_by_string "$m"
}

# Last session id: newest history.jsonl entry, else our own last_session.
_ca_last_session_id() {
  local base="$(_ca_claude_dir)/history.jsonl" last
  if [[ -f "$base" ]]; then
    last=$(tail -1 "$base" 2>/dev/null | jq -r '.sessionId // .id // ""' 2>/dev/null)
    [[ -n "$last" ]] && { echo "$last"; return 0; }
  fi
  last=$(jq -r '.last_session // ""' "$MODELS_CFG" 2>/dev/null)
  [[ -n "$last" ]] && echo "$last"
}

# Keep only the most recent session files to bound disk usage.
_ca_prune_sessions() {
  local old files
  files=("$SESSION_DIR"/*.json(N))
  (( ${#files[@]} > 0 )) || return 0
  old=("${(@f)$(ls -t -- "${files[@]}" 2>/dev/null | tail -n +101)}")
  (( ${#old[@]} > 0 )) && rm -f -- "${old[@]}"
}

# After `claude` exits, detect the session id used (newest transcript under
# ~/.claude/projects written since launch) and record its model.
_ca_record_session() {
  local name="$1" proj="$(_ca_claude_dir)/projects"
  [[ -d "$proj" ]] || return 1
  local f mt newest=0 best=""
  local scope="$proj/${PWD//[^A-Za-z0-9]/-}"
  if [[ -d "$scope" ]]; then
    for f in "$scope"/*.jsonl(N); do
      mt=$(stat -f %m "$f" 2>/dev/null) || continue
      (( mt >= _ca_launch_start )) || continue
      (( mt >= newest )) || continue
      newest=$mt
      best=$f
    done
  fi
  if [[ -z "$best" ]]; then
  for f in "$proj"/*/*.jsonl(N); do
    mt=$(stat -f %m "$f" 2>/dev/null) || continue
    (( mt >= _ca_launch_start )) || continue
    (( mt >= newest )) || continue
    newest=$mt
    best=$f
  done
  fi
  [[ -n "$best" ]] || return 1

  local sid
  sid=$(basename "$best" .jsonl)
  [[ "$sid" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || return 1

  local m
  m=$(_ca_session_file_model "$best") || m="$name"
  [[ -n "$m" ]] || return 1
  _ca_save_session "$sid" "$m"

  local tmp
  tmp=$(mktemp)
  if jq --arg id "$sid" '.last_session = $id' "$MODELS_CFG" > "$tmp" 2>/dev/null \
     && mv "$tmp" "$MODELS_CFG"; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# ── Help ─────────────────────────────────────────────────────────────────────

_ca_cmd_help() {
  if [[ "$_CA_LANG" == "zh" ]]; then
    echo ""
    echo "  claunch $CLAUNCH_VERSION — Claude Code 智能启动器"
    echo "  https://github.com/k186/claunch"
    echo ""
    echo "  用法:"
    echo ""
    echo "    ca                      使用当前模型启动 Claude"
    echo "    ca --new                fzf 选择模型后启动"
    echo "    ca --continue           继续上次会话"
    echo "    ca --new --resume <id>  选择模型并恢复指定会话"
    echo ""
    echo "  模型管理:"
    echo ""
    echo "    ca --list               浏览模型（Enter 启动，e 编辑，Del 删除）"
    echo "    ca --add                交互式添加新模型"
    echo "    ca --remove             通过 fzf 删除模型"
    echo "    ca --current            查看当前窗口使用的模型"
    echo ""
    echo "  其他:"
    echo ""
    echo "    ca --update             升级 claunch 到最新版本"
    echo "    ca --lang [en|zh]       查看 / 切换语言"
    echo ""
    echo "  配置文件: $MODELS_CFG"
    echo ""
  else
    echo ""
    echo "  claunch $CLAUNCH_VERSION — Claude Code smart launcher"
    echo "  https://github.com/k186/claunch"
    echo ""
    echo "  Usage:"
    echo ""
    echo "    ca                      Launch Claude with the current model"
    echo "    ca --new                Pick a model via fzf, then launch"
    echo "    ca --continue           Resume last Claude session"
    echo "    ca --new --resume <id>  Pick model + resume session"
    echo ""
    echo "  Model management:"
    echo ""
    echo "    ca --list               Browse models (Enter=launch, e=edit, Del=delete)"
    echo "    ca --add                Add a new model (interactive)"
    echo "    ca --remove             Remove a model (fzf picker)"
    echo "    ca --current            Show active model in this window"
    echo ""
    echo "  Other:"
    echo ""
    echo "    ca --update             Update claunch to the latest version"
    echo "    ca --lang [en|zh]       Show / set language"
    echo ""
    echo "  Config: $MODELS_CFG"
    echo ""
  fi
}

# ── Version check ────────────────────────────────────────────────────────────

_ca_check_update() {
  local lang="$_CA_LANG"
  {
    local latest
    latest=$(curl -fsSL --max-time 3 "$CLAUNCH_RAW/version" 2>/dev/null)
    if [[ -n "$latest" && "$latest" != "$CLAUNCH_VERSION" ]]; then
      printf "$_S_UPD_AVAIL" "$latest" "$CLAUNCH_VERSION"
    fi
  } &!
}

_ca_cmd_update() {
  echo ""
  echo "  $_S_UPGRADING"
  curl -fsSL "$CLAUNCH_RAW/claunch.sh" -o "$HOME/.claude/claunch.sh" \
    && chmod +x "$HOME/.claude/claunch.sh" \
    && echo "  $_S_UPG_DONE" \
    || echo "  $_S_UPG_FAIL"
  echo ""
}

# ── Language ──────────────────────────────────────────────────────────────────

_ca_cmd_lang() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo ""
    printf "$_S_LANG_CURR" "$_CA_LANG"
    echo "  $_S_LANG_USAGE"
    echo ""
    return 0
  fi
  if [[ "$target" != "en" && "$target" != "zh" ]]; then
    echo "  $_S_LANG_ERR"
    return 1
  fi
  local tmp
  tmp=$(mktemp)
  jq --arg lang "$target" '.lang = $lang' "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"
  printf "$_S_LANG_SET" "$target"
}

# ── Management commands ───────────────────────────────────────────────────────

_ca_cmd_list() {
  local preview_cmd
  preview_cmd="jq -r --arg n {} '
    .models[] | select(.name == \$n) |
    \"\",
    \"  Name   : \" + .name,
    \"  Model  : \" + (if .model != \"\" then .model else \"(env-driven)\" end),
    \"\",
    \"  Env:\",
    (if (.env | length) > 0 then
      (.env | to_entries[] | \"    \" + .key + \" = \" + .value)
    else \"    (none)\" end),
    \"\"
  ' \"$MODELS_CFG\""

  local output key choice
  output=$(jq -r '.models[].name' "$MODELS_CFG" | fzf \
    --height=~80% \
    --border=rounded \
    --margin=1,2 \
    --padding=1 \
    --reverse \
    --prompt="  Model > " \
    --header="$_S_LIST_HDR" \
    --expect='e,del' \
    --preview="$preview_cmd" \
    --preview-window=right:55%:wrap \
    --color=border:7 \
    --no-info 2>&1)
  local ret=$?

  [[ $ret -ne 0 ]] && return 0
  key=$(echo "$output" | head -1)
  choice=$(echo "$output" | tail -1)
  [[ -z "$choice" ]] && return 0

  if [[ "$key" == "e" ]]; then
    _ca_cmd_edit "$choice"
  elif [[ "$key" == "del" ]]; then
    echo ""
    printf "$_S_CONFIRM_DEL" "$choice"
    read -r _c1
    if [[ "$_c1" == "n" || "$_c1" == "N" ]]; then
      echo "  $_S_CANCELLED"
      return 0
    fi
    local tmp
    tmp=$(mktemp)
    jq --arg name "$choice" '.models = [.models[] | select(.name != $name)]' \
      "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"
    printf "$_S_DELETED" "$choice"
    echo ""
  else
    local i count
    count=$(jq '.models | length' "$MODELS_CFG")
    for ((i=0; i<count; i++)); do
      local n
      n=$(jq -r --argjson i "$i" '.models[$i].name' "$MODELS_CFG")
      if [[ "$n" == "$choice" ]]; then
        build_model_env "$i"
        _CA_MODEL_NAME="$choice"
        SELECTED_NAME="$choice"
        _ca_save_last_model "$choice"
        break
      fi
    done
    printf "$_S_LAUNCHING" "$choice"
    launch_claude
  fi
}

_ca_cmd_edit() {
  local target="$1"

  local cur_name cur_model cur_base_url cur_auth_token cur_anthropic_model cur_context_window
  cur_name=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .name' "$MODELS_CFG")
  cur_model=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .model // ""' "$MODELS_CFG")
  cur_base_url=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .env.ANTHROPIC_BASE_URL // ""' "$MODELS_CFG")
  cur_auth_token=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .env.ANTHROPIC_AUTH_TOKEN // ""' "$MODELS_CFG")
  cur_anthropic_model=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .env.ANTHROPIC_MODEL // ""' "$MODELS_CFG")
  cur_context_window=$(jq -r --arg n "$target" '.models[] | select(.name == $n) | .env.CLAUDE_MAX_CONTEXT_WINDOW // ""' "$MODELS_CFG")

  echo ""
  printf "$_S_EDIT_TITLE" "$cur_name"
  echo "  $_S_EDIT_HINT"
  echo ""

  local name model base_url auth_token anthropic_model context_window

  _ca_read_field "$_S_F_NAME"    "$cur_name";           name="$REPLY"
  _ca_read_field "$_S_F_BASEURL" "$cur_base_url";       base_url="$REPLY"

  if [[ -n "$base_url" ]]; then
    _ca_read_field "$_S_F_AUTH"    "$cur_auth_token";      auth_token="$REPLY"
    _ca_read_field "$_S_F_MODEL"   "$cur_anthropic_model"; anthropic_model="$REPLY"
    _ca_read_field "$_S_F_CONTEXT" "$cur_context_window";  context_window="$REPLY"
    model=""
  else
    _ca_read_field "$_S_F_MODELID" "$cur_model";           model="$REPLY"
  fi

  local entry tmp
  entry=$(_ca_build_entry "$name" "$model" "$base_url" "$auth_token" "$anthropic_model" "$context_window")
  tmp=$(mktemp)
  jq --arg orig "$target" --argjson entry "$entry" \
    '.models = [.models[] | if .name == $orig then $entry else . end]' \
    "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"

  echo ""
  printf "$_S_UPDATED" "$name"
  echo ""
}

# Read a field with current value shown; Enter keeps it, - clears it
_ca_read_field() {
  local label="$1" current="$2" input
  printf "  %-18s [%s]: " "$label" "${current:--}"
  read -r input
  if [[ -z "$input" ]]; then
    REPLY="$current"
  elif [[ "$input" == "-" ]]; then
    REPLY=""
  else
    REPLY="$input"
  fi
}

# Build a model entry JSON safely (avoids zsh quoting issues with jq +)
_ca_build_entry() {
  local name="$1" model="$2" base_url="$3" auth_token="$4" anthropic_model="$5" context_window="$6"
  local env_json entry

  if [[ -n "$base_url" ]]; then
    env_json=$(jq -n \
      --arg u "$base_url" --arg t "$auth_token" --arg m "$anthropic_model" \
      '{ANTHROPIC_BASE_URL:$u, ANTHROPIC_AUTH_TOKEN:$t, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:"1", ANTHROPIC_MODEL:$m}')
    if [[ -n "$context_window" ]]; then
      env_json=$(echo "$env_json" | jq --arg cw "$context_window" '. + {CLAUDE_MAX_CONTEXT_WINDOW:$cw}')
    fi
    entry=$(jq -n --arg name "$name" --arg model "$model" --argjson env "$env_json" \
      '{name:$name, model:$model, env:$env}')
  else
    entry=$(jq -n --arg name "$name" --arg model "$model" \
      '{name:$name, model:$model, env:{}}')
  fi
  echo "$entry"
}

_ca_cmd_current() {
  echo ""
  if [[ -n "$ANTHROPIC_MODEL" ]]; then
    printf "$_S_CURR_MODEL" "$ANTHROPIC_MODEL"
    [[ -n "$ANTHROPIC_BASE_URL" ]] && printf "$_S_CURR_PROV" "$ANTHROPIC_BASE_URL"
  elif [[ -n "$MODEL_FLAG" ]]; then
    printf "$_S_CURR_MODEL" "$MODEL_FLAG"
  else
    echo "  $_S_CURR_DEF"
  fi
  echo ""
}

_ca_cmd_add() {
  echo ""
  echo "  $_S_ADD_TITLE"
  echo "  $_S_ADD_SEP"

  local name model base_url auth_token anthropic_model context_window

  printf "%s" "$_S_P_NAME"; read -r name
  [[ -z "$name" ]] && echo "  $_S_CANCELLED" && return 1

  printf "%s" "$_S_P_BASEURL"; read -r base_url

  if [[ -n "$base_url" ]]; then
    printf "%s" "$_S_P_AUTH";    read -r auth_token
    printf "%s" "$_S_P_MODEL";   read -r anthropic_model
    printf "%s" "$_S_P_CONTEXT"; read -r context_window
    model=""
  else
    printf "%s" "$_S_P_MODELID"; read -r model
  fi

  local entry tmp
  entry=$(_ca_build_entry "$name" "$model" "$base_url" "$auth_token" "$anthropic_model" "$context_window")
  tmp=$(mktemp)
  jq --argjson entry "$entry" '.models += [$entry]' "$MODELS_CFG" > "$tmp" \
    && mv "$tmp" "$MODELS_CFG"
  echo ""
  printf "$_S_ADDED" "$name"
  echo ""
}

_ca_cmd_remove() {
  local names=()
  local line
  while IFS= read -r line; do
    names+=("$line")
  done < <(jq -r '.models[].name' "$MODELS_CFG")

  local choice
  choice=$(printf '%s\n' "${names[@]}" | fzf \
    --height=~50% \
    --border=rounded \
    --margin=1,2 \
    --padding=1 \
    --reverse \
    --prompt="$_S_REMOVE_PROMPT" \
    --header="$_S_REMOVE_HDR" \
    --color=border:7 \
    --no-info 2>&1)

  if [[ -z "$choice" ]]; then
    echo "  $_S_CANCELLED"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg name "$choice" '.models = [.models[] | select(.name != $name)]' \
    "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"
  printf "$_S_REMOVED" "$choice"
}

# ── Main ──────────────────────────────────────────────────────────────────────

MODEL_ENV_EXPORTS=()
MODEL_FLAG=""
SELECTED_IDX=-1
SELECTED_NAME=""
_CA_MODEL_NAME=""
_ca_launch_start=0

case "$1" in
  --new)
    select_model || { _ca_restore_opts; return 0 2>/dev/null || exit 0; }
    build_model_env "$SELECTED_IDX"
    _CA_MODEL_NAME="$SELECTED_NAME"
    _ca_save_last_model "$SELECTED_NAME"
    shift
    _ca_check_update
    launch_claude "$@"
    ;;
  --list)    _ca_cmd_list        ;;
  --add)     _ca_cmd_add         ;;
  --remove)  _ca_cmd_remove      ;;
  --current) _ca_cmd_current     ;;
  --update)  _ca_cmd_update      ;;
  --lang)    _ca_cmd_lang "$2"   ;;
  --help)    _ca_cmd_help        ;;
  *)
    if [[ "$1" == "--resume" && -n "$2" ]]; then
      _ca_resume_session "$2"
    elif [[ "$1" == "--continue" ]]; then
      _ca_last_sid=$(_ca_last_session_id)
      [[ -n "$_ca_last_sid" ]] && _ca_resume_session "$_ca_last_sid"
    fi
    _ca_check_update
    launch_claude "$@"
    ;;
esac

_ca_restore_opts
