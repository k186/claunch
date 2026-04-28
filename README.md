# claunch

Claude Code smart launcher with fzf model switcher.  
Switch between Claude, MiniMax, DeepSeek and any Anthropic-compatible provider on the fly.

## Features

- `ca` — launch Claude with the current model
- `ca --new` — pick a model via fzf, then launch
- All `claude` flags pass through (e.g. `ca --continue`, `ca --resume <id>`)
- Restores terminal state (P10k, mouse, colors) cleanly after exit

## Requirements

- [Claude Code](https://claude.ai/code) (`claude` CLI)
- [`jq`](https://jqlang.github.io/jq/)
- [`fzf`](https://github.com/junegunn/fzf)
- zsh

## Install

```zsh
git clone https://github.com/yourname/claunch ~/github/claunch
cd ~/github/claunch
zsh install.sh
source ~/.zshrc
```

## Configuration

Edit `~/.claude/models.json` (created from `models.example.json` on first install):

```json
{
  "models": [
    {
      "name": "Claude Opus 4.7",
      "model": "claude-opus-4-7",
      "env": {}
    },
    {
      "name": "MiniMax-M2.7",
      "model": "",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.minimaxi.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "your-api-key",
        "ANTHROPIC_MODEL": "MiniMax-M2.7"
      }
    }
  ]
}
```

- `model` — passed as `--model` to claude. Leave empty `""` to use the provider default via env vars.
- `env` — environment variables injected when launching claude (API keys, base URLs, etc).

## Usage

```zsh
ca                  # launch with current model
ca --new            # pick model with fzf
ca --continue       # resume last session
ca --new --resume <id>  # pick model + resume session
```
