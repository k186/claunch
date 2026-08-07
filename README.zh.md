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
- `ca` — 纯透传，使用 Claude 默认模型启动
- `ca --continue` / `ca --resume <id>` — 恢复会话时自动还原该对话原本使用的模型/服务商（会话记录，或从会话转录中解析）
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
ca                       # 纯透传：使用 Claude 默认模型启动
ca --new                 # fzf 选择模型后启动新会话
ca --continue            # 继续上次会话，并还原该会话的模型/服务商
ca --resume <id>         # 恢复指定会话，并还原该会话的模型/服务商
ca --resume              # 打开 Claude 交互式恢复列表（纯透传）
ca --new --resume <id>   # 显式选择模型后恢复指定会话
```

`ca` 之后的所有参数都会原样透传给 `claude`。

### 恢复会话时如何还原模型

每次启动结束后，claunch 都会记录会话：检测 `~/.claude/projects` 下本次运行期间写入的最新转录（优先当前项目目录），并从转录中读取该会话实际使用的模型。每个会话保存一份小文件：

```
~/.config/claunch/sessions/<会话id>.json  →  {"model":"<模型串>"}
```

`ca --continue` 和 `ca --resume <id>` 按以下顺序还原模型：

1. 会话记录（`sessions/<id>.json`）；
2. 直接解析会话转录；
3. 都没有则纯透传（交给 Claude 自己处理）。

模型串会与 `models.json` 中的条目匹配（按 `name`、`model` 或 `env.ANTHROPIC_MODEL`），命中后注入完整 env 与 `--model`，保证恢复的会话使用原来的服务商和凭证。`ca` 无参数和 `ca --resume`（列表选择）完全透传；列表选择的会话会在运行结束后记录，供下次恢复使用。

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
ca --update            # 升级 claunch（不会覆盖你的模型配置）
ca --lang [en|zh]       # 查看或切换界面语言
ca --help               # 显示所有命令
```

每次启动时 claunch 会在后台静默检测新版本，有更新时会在终端提示。

## 配置

claunch 的所有数据都存放在 `~/.config/claunch/` 下：

```
~/.config/claunch/
├── models.json     # 模型条目 + last_model / last_session
└── sessions/       # 每个会话 id 一份小 JSON（只保留最近 100 个）
```

首次安装时会从 `models.example.json` 生成 `models.json`，升级不会覆盖它。旧路径 `~/.claude/models.json` 仍然兼容，`install.sh` 会自动迁移；设置 `CLAUNCH_MODELS_CFG` 可改用其他配置路径。也可以通过 `ca --add`、`ca --remove`、`ca --list` 交互式管理模型。

`last_session` 记录最近一次会话 id；`last_model` 记录最近一次选择的模型供参考。恢复命令优先用该会话自己的记录还原模型与服务商，其次解析会话转录，最后纯透传。

```json
{
  "name": "claunch",
  "lang": "zh",
  "last_model": "",
  "last_session": "",
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
