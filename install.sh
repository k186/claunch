#!/bin/zsh
#
# install.sh — claunch installer
#
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/k186/claunch/main/install.sh)
#
# Author:  k186
# License: MIT
# Repo:    https://github.com/k186/claunch

set -e

REPO_RAW="https://raw.githubusercontent.com/k186/claunch/main"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/claunch.sh"
ZSHRC="$HOME/.zshrc"

# ── Detect local vs remote ────────────────────────────────────────────────────
SCRIPT_DIR="${0:A:h}"
if [[ -f "$SCRIPT_DIR/claunch.sh" ]]; then
  MODE=local
else
  MODE=remote
fi

# ── Dependencies ──────────────────────────────────────────────────────────────
for _dep in jq fzf; do
  if ! command -v "$_dep" &>/dev/null; then
    echo "Installing $_dep..."
    brew install "$_dep"
  fi
done

mkdir -p "$CLAUDE_DIR"

# ── Install claunch.sh ────────────────────────────────────────────────────────
if [[ $MODE == local ]]; then
  cp "$SCRIPT_DIR/claunch.sh" "$TARGET"
else
  curl -fsSL "$REPO_RAW/claunch.sh" -o "$TARGET"
fi
chmod +x "$TARGET"
echo "Installed: $TARGET"

# ── Seed models.json (never overwrite existing config) ───────────────────────
if [[ -f "$CLAUDE_DIR/models.json" ]]; then
  echo "Skipped:   $CLAUDE_DIR/models.json already exists — not modified"
else
  if [[ $MODE == local ]]; then
    cp "$SCRIPT_DIR/models.example.json" "$CLAUDE_DIR/models.json"
  else
    curl -fsSL "$REPO_RAW/models.example.json" -o "$CLAUDE_DIR/models.json"
  fi
  echo "Created:   $CLAUDE_DIR/models.json (fill in your API keys)"
fi

# ── Wire up ca() in .zshrc ────────────────────────────────────────────────────
if ! grep -q 'claunch.sh' "$ZSHRC" 2>/dev/null; then
  cat >> "$ZSHRC" <<'EOF'

# claunch — Claude Code smart launcher
unalias ca 2>/dev/null
function ca {
  source "$HOME/.claude/claunch.sh" "$@"
  if (( $+functions[p10k] )); then
    p10k reload 2>/dev/null
  else
    for _ca_f in "${precmd_functions[@]}"; do "$_ca_f" 2>/dev/null; done
    unset _ca_f
  fi
}
EOF
  echo "Added ca() function to $ZSHRC"
  echo "Run: source ~/.zshrc"
else
  echo "ca() already configured in $ZSHRC — skipped"
fi
