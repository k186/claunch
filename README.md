# claunch

<img src="logo/claunch-logo.png" alt="claunch" width="600"/>

Claude Code smart launcher with fzf model switcher.

**Run a different AI model in every terminal window — simultaneously, without conflicts.**  
One window on Claude Opus, another on MiniMax, another on DeepSeek. Each session is fully isolated.

[中文文档](README.zh.md)

---

## Why claunch

Most setups force you to pick one model globally. claunch lets you open multiple terminal windows, each running a different provider or model at the same time — no config files to swap, no environment leaking between sessions.

**How it works:** claunch injects model credentials as process-level environment variables (`env KEY=VAL claude ...`). Each terminal process has its own environment, so switching models in one window never affects another. Switch models per-window, per-task, per-context.

## Features

- **Per-window model isolation** — each terminal session runs its own model, completely independent
- `ca --new` — pick any model via fzf before launching
- `ca` — launch with the last-used model in this window
- `ca --list` — browse models interactively: **Enter** launch, **e** edit, **Del** delete
- Model management: add, remove, edit models without touching JSON files
- Background version check — notifies when an upgrade is available
- Bilingual UI: English and Chinese (`ca --lang zh`)
- All `claude` flags pass through (e.g. `ca --continue`, `ca --resume <id>`)
- Restores terminal state (p10k, Starship, Pure, and other prompt frameworks) cleanly after exit

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

Or clone and install locally:

```zsh
git clone https://github.com/k186/claunch ~/claunch
zsh ~/claunch/install.sh
source ~/.zshrc
```

## Usage

```zsh
ca                      # launch with current model
ca --new                # pick model with fzf, then launch
ca --continue           # resume last session
ca --new --resume <id>  # pick model + resume session
```

All `claude` flags pass through verbatim after `ca`.

## Model management

```zsh
ca --list               # browse models (Enter=launch, e=edit, Del=delete)
ca --add                # add a new model (interactive wizard)
ca --remove             # remove a model (fzf picker)
ca --current            # show which model is active in this window
```

`ca --list` opens an interactive fzf panel with a live preview of each model's configuration. Press **Enter** to launch, **e** to edit, **Del** to delete (with confirmation).

## Other commands

```zsh
ca --update            # upgrade claunch (models.json is never modified)
ca --lang [en|zh]       # show or set the UI language
ca --help               # show all commands
```

claunch checks for updates in the background on every launch and prints a notice if a newer version is available.

## Configuration

`~/.claude/models.json` is created from `models.example.json` on first install. You can also manage models interactively with `ca --add`, `ca --remove`, and `ca --list`.

```json
{
  "name": "claunch",
  "lang": "en",
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
    },
    {
      "name": "DeepSeek V4 Pro (1M)",
      "model": "",
      "env": {
        "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
        "ANTHROPIC_AUTH_TOKEN": "your-api-key",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "CLAUDE_MAX_CONTEXT_WINDOW": "1000000",
        "ANTHROPIC_MODEL": "deepseek-v4-pro[1m]"
      }
    }
  ]
}
```

**Field reference:**

| Field | Description |
|-------|-------------|
| `name` | Display name shown in fzf |
| `model` | Passed as `--model` to claude. Leave `""` to use the provider's default via env vars |
| `env` | Environment variables injected per-session (API keys, base URLs, etc.) |

**For third-party providers** (MiniMax, DeepSeek, etc.), set:
- `ANTHROPIC_BASE_URL` — provider's Anthropic-compatible API endpoint
- `ANTHROPIC_AUTH_TOKEN` — your API key
- `ANTHROPIC_MODEL` — model name as the provider expects it
- `CLAUDE_MAX_CONTEXT_WINDOW` — optional, e.g. `"1000000"` for 1M context
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — set to `"1"` for third-party providers

## License

MIT
