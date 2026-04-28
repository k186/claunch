#!/bin/zsh
# Install claunch: copies script to ~/.claude/ and wires up the shell function

set -e

SCRIPT_DIR="${0:A:h}"
CLAUDE_DIR="$HOME/.claude"
TARGET="$CLAUDE_DIR/claunch.sh"
ZSHRC="$HOME/.zshrc"

# Copy script
mkdir -p "$CLAUDE_DIR"
cp "$SCRIPT_DIR/claunch.sh" "$TARGET"
chmod +x "$TARGET"
echo "Installed: $TARGET"

# Copy example models config if none exists
if [[ ! -f "$CLAUDE_DIR/models.json" ]]; then
  cp "$SCRIPT_DIR/models.example.json" "$CLAUDE_DIR/models.json"
  echo "Created:   $CLAUDE_DIR/models.json (fill in your API keys)"
fi

# Add shell function to .zshrc if not already present
if ! grep -q 'claunch.sh' "$ZSHRC" 2>/dev/null; then
  cat >> "$ZSHRC" <<'EOF'

# claunch — Claude Code smart launcher
unalias ca 2>/dev/null
function ca {
  source "$HOME/.claude/claunch.sh" "$@"
  (( $+functions[p10k] )) && p10k reload 2>/dev/null
}
EOF
  echo "Added ca() function to $ZSHRC"
  echo "Run: source $ZSHRC"
else
  echo "ca() already configured in $ZSHRC — skipped"
fi
