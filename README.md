# claunch

<img src="logo/claunch-logo.png" alt="claunch" width="600"/>

Claude Code smart launcher with fzf model switcher.

**Run a different AI model in every terminal window — simultaneously, without conflicts.**  
One window on Claude Opus, another on MiniMax, another on DeepSeek. Each session is fully isolated.

[中文文档](README.zh.md)

---

## Why claunch

Most setups force you to pick one model globally. claunch lets you open multiple terminal windows, each running a different provider or model at the same time — no config files to swap, no environment leaking between sessions. Switch models per-window, per-task, per-context.

## Features

- **Per-window model isolation** — each terminal session runs its own model, completely independent
- `ca --new` — pick any model via fzf before launching
- `ca` — launch with the last-used model in this window
- All `claude` flags pass through (e.g. `ca --continue`, `ca --resume <id>`)
- Restores terminal state (p10k, Starship, and other prompt frameworks) cleanly after exit

<img src="screenshots/fzf-picker.png" alt="fzf model picker" width="600"/>

## Requirements

- [Claude Code](https://claude.ai/code) (`claude` CLI)
- [Homebrew](https://brew.sh/) (for auto-installing `jq` and `fzf`)
- zsh

## Install

```zsh
bash <(curl -fsSL https://raw.githubusercontent.com/k186/claunch/main/install.sh)
source ~/.zshrc
```

`jq` and `fzf` are installed automatically via Homebrew if missing.

Or clone and install manually:

```zsh
git clone https://github.com/k186/claunch ~/github/claunch
zsh ~/github/claunch/install.sh
source ~/.zshrc
```

## Configuration

`~/.claude/models.json` is created from `models.example.json` on first install. Edit it to add your API keys and models:

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
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "ANTHROPIC_MODEL": "MiniMax-M2.7"
      }
    }
  ]
}
```

- `model` — passed as `--model` to claude. Leave empty `""` to use the provider default via env vars.
- `env` — environment variables injected when launching claude (API keys, base URLs, etc).

For third-party providers, set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_MODEL`. Use `CLAUDE_MAX_CONTEXT_WINDOW` to override context size (e.g. `"1000000"` for 1M).

## Usage

```zsh
ca                      # launch with current model
ca --new                # pick model with fzf
ca --continue           # resume last session
ca --new --resume <id>  # pick model + resume session
```
