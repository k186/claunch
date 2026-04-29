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
  local count i name model anthropic_model label
  count=$(jq '.models | length' "$MODELS_CFG")
  echo ""
  printf "  %-4s %-32s %s\n" "No." "Name" "Model"
  printf "  %-4s %-32s %s\n" "----" "--------------------------------" "------------------------------"
  for ((i=0; i<count; i++)); do
    name=$(jq -r --argjson i "$i" '.models[$i].name' "$MODELS_CFG")
    model=$(jq -r --argjson i "$i" '.models[$i].model // ""' "$MODELS_CFG")
    if [[ -n "$model" ]]; then
      label="$model"
    else
      anthropic_model=$(jq -r --argjson i "$i" '.models[$i].env.ANTHROPIC_MODEL // ""' "$MODELS_CFG")
      label="${anthropic_model:-(env-driven)}"
    fi
    printf "  %-4s %-32s %s\n" "$((i+1))." "$name" "$label"
  done
  echo ""
  echo "  Config: $MODELS_CFG"
  echo ""
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

  printf "  Model ID (blank = env-driven, e.g. for 3rd-party): "; read -r model
  printf "  Base URL (blank = Anthropic default): "; read -r base_url

  if [[ -n "$base_url" ]]; then
    printf "  Auth token: "; read -r auth_token
    printf "  ANTHROPIC_MODEL (model name for provider): "; read -r anthropic_model
    printf "  Context window override (blank to skip, e.g. 1000000): "; read -r context_window
  fi

  # Build JSON entry
  local entry
  if [[ -n "$base_url" ]]; then
    entry=$(jq -n \
      --arg name "$name" \
      --arg model "$model" \
      --arg base_url "$base_url" \
      --arg auth_token "$auth_token" \
      --arg anthropic_model "$anthropic_model" \
      --arg context_window "$context_window" \
      '{
        name: $name,
        model: $model,
        env: {
          ANTHROPIC_BASE_URL: $base_url,
          ANTHROPIC_AUTH_TOKEN: $auth_token,
          CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
          ANTHROPIC_MODEL: $anthropic_model
        } + (if $context_window != "" then {CLAUDE_MAX_CONTEXT_WINDOW: $context_window} else {} end)
      }')
  else
    entry=$(jq -n \
      --arg name "$name" \
      --arg model "$model" \
      '{name: $name, model: $model, env: {}}')
  fi

  local tmp
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
  --list)
    _ca_cmd_list
    ;;
  --add)
    _ca_cmd_add
    ;;
  --remove)
    _ca_cmd_remove
    ;;
  --current)
    _ca_cmd_current
    ;;
  --upgrade)
    _ca_cmd_upgrade
    ;;
  *)
    _ca_check_update
    launch_claude "$@"
    ;;
esac

_ca_restore_opts
