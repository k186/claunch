#!/bin/zsh
#
# claunch.sh — Claude Code smart launcher with fzf model switcher
#
# Usage (add to .zshrc):
#   function ca { source "$HOME/.claude/claunch.sh" "$@"; (( $+functions[p10k] )) && p10k reload 2>/dev/null; }
#
# ca              — launch Claude with the last-used model
# ca --new        — pick a model with fzf, then launch Claude
# ca --continue   — resume last session (pass-through to claude)

MODELS_CFG="${CLAUNCH_MODELS_CFG:-$HOME/.claude/models.json}"

# Save KSH_ARRAYS state and enable locally (0-indexed to match jq)
[[ -o ksharrays ]] && _ca_had_ksharrays=1 || _ca_had_ksharrays=0
setopt KSH_ARRAYS

_ca_restore_opts() {
  (( _ca_had_ksharrays )) || unsetopt KSH_ARRAYS
  unset _ca_had_ksharrays
}

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

MODEL_ENV_EXPORTS=()
MODEL_FLAG=""
SELECTED_IDX=-1

if [[ "$1" == "--new" ]]; then
  select_model || { _ca_restore_opts; return 0 2>/dev/null || exit 0; }
  build_model_env "$SELECTED_IDX"
  shift
  launch_claude "$@"
else
  launch_claude "$@"
fi

_ca_restore_opts
