# claunch

<img src="logo/claunch-logo.png" alt="claunch" width="600"/>

支持 fzf 模型切换的 Claude Code 智能启动器。

**每个终端窗口运行不同的 AI 模型 — 同时并行，互不干扰。**  
一个窗口用 Claude Opus，另一个用 MiniMax，再开一个用 DeepSeek，完全隔离。

[English](README.md)

---

## 为什么用 claunch

通常只能全局设置一个模型。claunch 让你同时打开多个终端窗口，每个窗口运行不同的服务商或模型 —— 无需手动切换配置，环境变量不会在窗口间泄漏。

**实现原理：** claunch 通过进程级环境变量注入模型凭证（`env KEY=VAL claude ...`）。每个终端进程拥有独立的环境，在一个窗口切换模型不会影响其他窗口。按窗口、按任务、按场景自由选模型。

## 功能

- **窗口级模型隔离** — 每个终端会话独立运行各自的模型，完全不冲突
- `ca --new` — 启动前通过 fzf 选择任意模型
- `ca` — 使用当前窗口上次选择的模型启动
- `ca --list` — 交互式浏览模型：**Enter** 启动，**e** 编辑，**Del** 删除
- 模型管理：无需手动编辑 JSON，直接增删改模型
- 后台版本检测 — 有新版本时自动提示
- 中英双语界面（`ca --lang zh`）
- 所有 `claude` 参数透传（如 `ca --continue`、`ca --resume <id>`）
- 退出后自动恢复终端状态，兼容 p10k、Starship、Pure 等 prompt 框架

## 依赖

- [Claude Code](https://claude.ai/code)（`claude` CLI）
- [Homebrew](https://brew.sh/)（用于自动安装 `jq` 和 `fzf`）
- zsh

## 安装

```zsh
bash <(curl -fsSL https://raw.githubusercontent.com/k186/claunch/main/install.sh)
source ~/.zshrc
```

若缺少 `jq` 或 `fzf`，安装脚本会自动通过 Homebrew 安装。

或手动克隆安装：

```zsh
git clone https://github.com/k186/claunch ~/claunch
zsh ~/claunch/install.sh
source ~/.zshrc
```

## 用法

```zsh
ca                      # 使用当前模型启动
ca --new                # fzf 选择模型后启动
ca --continue           # 继续上次会话
ca --new --resume <id>  # 选择模型并恢复指定会话
```

`ca` 之后的所有参数都会原样透传给 `claude`。

## 模型管理

```zsh
ca --list               # 交互式浏览模型（Enter 启动，e 编辑，Del 删除）
ca --add                # 交互式添加新模型
ca --remove             # 通过 fzf 删除模型
ca --current            # 查看当前窗口使用的模型
```

`ca --list` 会打开带实时预览的 fzf 面板，显示每个模型的完整配置。按 **Enter** 启动，按 **e** 编辑，按 **Del** 删除（需确认）。

## 其他命令

```zsh
ca --update            # 升级 claunch（不会修改 models.json）
ca --lang [en|zh]       # 查看或切换界面语言
ca --help               # 显示所有命令
```

每次启动时 claunch 会在后台静默检测新版本，有更新时会在终端提示。

## 配置

首次安装时会从 `models.example.json` 生成 `~/.claude/models.json`。也可以通过 `ca --add`、`ca --remove`、`ca --list` 交互式管理模型。

```json
{
  "name": "claunch",
  "lang": "zh",
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

**字段说明：**

| 字段 | 说明 |
|------|------|
| `name` | fzf 中显示的名称 |
| `model` | 作为 `--model` 传给 claude，留空 `""` 则由环境变量驱动 |
| `env` | 每次启动时注入的环境变量（API Key、Base URL 等） |

**接入第三方服务商**（MiniMax、DeepSeek 等）需设置：
- `ANTHROPIC_BASE_URL` — 服务商的 Anthropic 兼容 API 地址
- `ANTHROPIC_AUTH_TOKEN` — 你的 API Key
- `ANTHROPIC_MODEL` — 服务商要求的模型名称
- `CLAUDE_MAX_CONTEXT_WINDOW` — 可选，如 `"1000000"` 表示 1M 上下文
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — 第三方服务商设为 `"1"`

## License

MIT
