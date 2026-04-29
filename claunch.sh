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
# ca              — launch Claude with the last-used model
# ca --new        — pick a model with fzf, then launch Claude
# ca --list       — list all configured models
# ca --add        — add a new model interactively
# ca --remove     — remove a model via fzf picker
# ca --current    — show the model active in this window
# ca --upgrade    — upgrade claunch to the latest version
# ca --help       — show this help
# ca --continue   — resume last session (pass-through to claude)

MODELS_CFG="${CLAUNCH_MODELS_CFG:-$HOME/.claude/models.json}"
CLAUNCH_VERSION="1.0.0"
CLAUNCH_RAW="https://raw.githubusercontent.com/k186/claunch/main"

# Save KSH_ARRAYS state and enable locally (0-indexed to match jq)
[[ -o ksharrays ]] && _ca_had_ksharrays=1 || _ca_had_ksharrays=0
setopt KSH_ARRAYS

_ca_restore_opts() {
  (( _ca_had_ksharrays )) || unsetopt KSH_ARRAYS
  unset _ca_had_ksharrays
}

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
    --prompt="Select a Model > " \
    --header="Select a Model" \
    --color=border:7 \
    --no-info 2>&1)
  local ret=$?

  if (( ret != 0 )) || [[ -z "$choice" ]]; then
    echo ""
    echo "  Cancelled."
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
  echo "  Switched to: $choice"
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

  if (( ${#cmd_env[@]} > 0 )); then
    env "${cmd_env[@]}" claude "${claude_args[@]}"
  else
    claude "${claude_args[@]}"
  fi

  # Restore terminal state after claude exits
  # (must run here — not in a trap — because this script is sourced)
  printf '\033[?1049l'  # exit alternate screen
  printf '\033[?1000l\033[?1002l\033[?1006l'  # disable mouse tracking
  printf '\033[?2004l'  # disable bracketed paste
  printf '\033[?2026l'  # disable synchronized output (fixes p10k)
  printf '\033[?1l\033[?25h\033[0m\r'  # cursor keys / show cursor / reset colors
  stty sane 2>/dev/null
}

# ── Help ─────────────────────────────────────────────────────────────────────

_ca_cmd_help() {
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
  echo "    ca --list               Browse models (e=edit, Esc=exit)"
  echo "    ca --add                Add a new model (interactive)"
  echo "    ca --remove             Remove a model (fzf picker)"
  echo "    ca --current            Show active model in this window"
  echo ""
  echo "  Updates:"
  echo ""
  echo "    ca --upgrade            Upgrade claunch to the latest version"
  echo ""
  echo "  Config: ${CLAUNCH_MODELS_CFG:-$HOME/.claude/models.json}"
  echo ""
}

# ── Version check ────────────────────────────────────────────────────────────

_ca_check_update() {
  # Run in background, non-blocking — print notice if a newer version exists
  {
    local latest
    latest=$(curl -fsSL --max-time 3 "$CLAUNCH_RAW/version" 2>/dev/null)
    if [[ -n "$latest" && "$latest" != "$CLAUNCH_VERSION" ]]; then
      echo ""
      echo "  claunch $latest available (current: $CLAUNCH_VERSION)"
      echo "  Run: ca --upgrade"
      echo ""
    fi
  } &!
}

_ca_cmd_upgrade() {
  echo ""
  echo "  Upgrading claunch..."
  # Only overwrites claunch.sh — never touches models.json
  curl -fsSL "$CLAUNCH_RAW/claunch.sh" -o "$HOME/.claude/claunch.sh" \
    && chmod +x "$HOME/.claude/claunch.sh" \
    && echo "  Done. Restart your shell or run: source ~/.zshrc" \
    || echo "  Upgrade failed. Check your connection."
  echo ""
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
    --header=$'  ↑ ↓  navigate    Enter  launch    e  edit    Del  delete    Esc  exit\n' \
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
    echo "  Delete: $choice"
    printf "  Confirm? [y/N]: "; read -r _c1
    [[ "$_c1" != "y" && "$_c1" != "Y" ]] && echo "  Cancelled." && return 0
    printf "  Are you sure? [y/N]: "; read -r _c2
    [[ "$_c2" != "y" && "$_c2" != "Y" ]] && echo "  Cancelled." && return 0
    local tmp
    tmp=$(mktemp)
    jq --arg name "$choice" '.models = [.models[] | select(.name != $name)]' \
      "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"
    echo "  Deleted: $choice"
    echo ""
  else
    # Enter — find index and launch
    local i count
    count=$(jq '.models | length' "$MODELS_CFG")
    for ((i=0; i<count; i++)); do
      local n
      n=$(jq -r --argjson i "$i" '.models[$i].name' "$MODELS_CFG")
      if [[ "$n" == "$choice" ]]; then
        build_model_env "$i"
        break
      fi
    done
    echo "  Launching: $choice"
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
  echo "  Edit: $cur_name"
  echo "  ─────────────── (Enter = keep current, - = clear)"
  echo ""

  local name model base_url auth_token anthropic_model context_window input

  _ca_read_field "Display name" "$cur_name";       name="$REPLY"
  _ca_read_field "Base URL"     "$cur_base_url";   base_url="$REPLY"

  if [[ -n "$base_url" ]]; then
    # Third-party provider
    _ca_read_field "Auth token"      "$cur_auth_token";      auth_token="$REPLY"
    _ca_read_field "ANTHROPIC_MODEL" "$cur_anthropic_model"; anthropic_model="$REPLY"
    _ca_read_field "Context window"  "$cur_context_window";  context_window="$REPLY"
    model=""
  else
    # Native Anthropic
    _ca_read_field "Model ID" "$cur_model"; model="$REPLY"
  fi

  local entry tmp
  entry=$(_ca_build_entry "$name" "$model" "$base_url" "$auth_token" "$anthropic_model" "$context_window")
  tmp=$(mktemp)
  jq --arg orig "$target" --argjson entry "$entry" \
    '.models = [.models[] | if .name == $orig then $entry else . end]' \
    "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"

  echo ""
  echo "  Updated: $name"
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
    echo "  Model:    $ANTHROPIC_MODEL"
    [[ -n "$ANTHROPIC_BASE_URL" ]] && echo "  Provider: $ANTHROPIC_BASE_URL"
  elif [[ -n "$MODEL_FLAG" ]]; then
    echo "  Model:    $MODEL_FLAG"
  else
    echo "  Model:    default (not set via claunch in this window)"
  fi
  echo ""
}

_ca_cmd_add() {
  echo ""
  echo "  Add model"
  echo "  ─────────"

  local name model base_url auth_token anthropic_model context_window

  printf "  Display name: "; read -r name
  [[ -z "$name" ]] && echo "  Cancelled." && return 1

  printf "  Base URL (blank = Anthropic default): "; read -r base_url

  if [[ -n "$base_url" ]]; then
    # Third-party provider — model driven by ANTHROPIC_MODEL env var
    printf "  Auth token: "; read -r auth_token
    printf "  ANTHROPIC_MODEL: "; read -r anthropic_model
    printf "  Context window (blank to skip, e.g. 1000000): "; read -r context_window
    model=""
  else
    # Native Anthropic — model passed as --model flag
    printf "  Model ID (e.g. claude-opus-4-7): "; read -r model
  fi

  local entry tmp
  entry=$(_ca_build_entry "$name" "$model" "$base_url" "$auth_token" "$anthropic_model" "$context_window")
  tmp=$(mktemp)
  jq --argjson entry "$entry" '.models += [$entry]' "$MODELS_CFG" > "$tmp" \
    && mv "$tmp" "$MODELS_CFG"
  echo ""
  echo "  Added: $name"
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
    --prompt="Remove > " \
    --header="Select model to remove" \
    --color=border:7 \
    --no-info 2>&1)

  if [[ -z "$choice" ]]; then
    echo "  Cancelled."
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  jq --arg name "$choice" '.models = [.models[] | select(.name != $name)]' \
    "$MODELS_CFG" > "$tmp" && mv "$tmp" "$MODELS_CFG"
  echo "  Removed: $choice"
}

# ── Main ──────────────────────────────────────────────────────────────────────

MODEL_ENV_EXPORTS=()
MODEL_FLAG=""
SELECTED_IDX=-1

case "$1" in
  --new)
    select_model || { _ca_restore_opts; return 0 2>/dev/null || exit 0; }
    build_model_env "$SELECTED_IDX"
    shift
    _ca_check_update
    launch_claude "$@"
    ;;
  --list)    _ca_cmd_list    ;;
  --add)     _ca_cmd_add     ;;
  --remove)  _ca_cmd_remove  ;;
  --current) _ca_cmd_current ;;
  --upgrade) _ca_cmd_upgrade ;;
  --help)    _ca_cmd_help    ;;
  --*)
    echo ""
    echo "  Unknown option: $1"
    _ca_cmd_help
    ;;
  *)
    _ca_check_update
    launch_claude "$@"
    ;;
esac

_ca_restore_opts
