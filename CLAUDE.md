# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`claunch` is a zsh shell launcher for Claude Code that lets you switch between AI providers (Claude, MiniMax, DeepSeek, any Anthropic-compatible API) on the fly via fzf. It's a single shell script (`claunch.sh`) sourced as a zsh function.

## Install / test cycle

There are no build steps or test suites. To verify changes:

```zsh
# Re-run the installer after editing claunch.sh
zsh install.sh && source ~/.zshrc

# Exercise the launcher
ca                  # launch with last-used model
ca --new            # open fzf model picker
ca --continue       # resume last Claude session
```

The installer copies `claunch.sh` → `~/.claude/claunch.sh` and wires up the `ca()` function in `~/.zshrc`. Re-running it is safe (idempotent for the zshrc block).

## Architecture

**`claunch.sh`** — sourced (not executed) as a zsh function. Key design constraints:
- Must be `source`d, not run as a subprocess, so environment changes (vars, opts) affect the calling shell.
- Uses `setopt KSH_ARRAYS` locally for 0-indexed arrays to match `jq`'s 0-based indexing; saves/restores the option via `_ca_restore_opts`.
- `build_model_env` reads `~/.claude/models.json` (or `$CLAUNCH_MODELS_CFG`) and populates `MODEL_FLAG` (passed as `--model`) and `MODEL_ENV_EXPORTS` (injected via `env …`).
- `launch_claude` always passes `--dangerously-skip-permissions`, then `--model` if set, then all remaining `$@` args. After claude exits it emits escape sequences to restore terminal state (alternate screen, mouse, colors, cursor, bracketed paste).
- Terminal restore runs inline after `claude` returns — it cannot use a `trap` because the script is sourced and traps would persist in the parent shell.
- Prompt refresh after exit lives in the `ca()` wrapper (in `.zshrc`), not in `claunch.sh`: uses `p10k reload` if available, otherwise iterates `precmd_functions` (works with Starship, Pure, and other frameworks).

**`~/.claude/models.json`** (not in repo; created from `models.example.json` on install):
- Array of model entries: `name` (shown in fzf), `model` (passed as `--model`; `""` = omit flag, let env vars drive), `env` (key/value pairs exported before launching).
- For non-Anthropic providers, set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, plus the three `ANTHROPIC_DEFAULT_*_MODEL` vars and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

**`install.sh`** — copies `claunch.sh` to `~/.claude/`, optionally seeds `models.json`, appends `ca()` to `~/.zshrc` (guarded by grep so it's idempotent).

## Editing guidelines

- The script must remain `source`-safe: no `exit` (use `return`), no persistent side effects (traps, global aliases).
- `--new` is the only flag claunch intercepts; everything else passes through to `claude` verbatim.
- `CLAUNCH_MODELS_CFG` env var overrides the models file path — useful for testing without touching `~/.claude/models.json`.
