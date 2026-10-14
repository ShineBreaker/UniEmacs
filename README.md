# UniEmacs

跨桌面与手机的统一 Emacs 配置：单一代码库，三档 profile。

| 档位       | 场景                             | 选择方式                        |
| ---------- | -------------------------------- | ------------------------------- |
| `minimal`  | 底座：纯内建、可调试、秒开       | `UNI_EMACS_PROFILE=minimal`     |
| `portable` | Android 原生 Emacs 触屏          | Android 上自动；可 env 强制     |
| `full`     | 桌面全量，对标现代 IDE           | 默认档                          |

## 结构速览

- `early-init.el` / `init.el` — 入口
- `core/` — 三档共享基础设施（平台谓词、路径、包后端）
- `modules/` — 全部功能模块（`self-*.el`）
- `profiles/` — 三档的模块清单与包声明
- `data/` — 翻译表、图标资产
- `docs/architecture.md` — 设计文档

## 开发

```bash
direnv allow       # 或 denv load；环境由 manifest.scm 声明
just verify        # 三档沙箱冒烟 + byte-compile 零警告
```

手动冒烟某档：

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=minimal \
  emacs --batch -q -l early-init.el -l init.el
```

## 部署

- 桌面：入口两文件（`early-init.el`、`init.el`）放 `~/.config/emacs/`，`user-emacs-directory` 重定向到本仓库。
- Android：同上，入口放 Emacs 的 `~/.emacs.d`，仓库 clone 到 Termux home。

详见 `docs/architecture.md` §6。

## 规范

AI agent 与贡献者工作前先读 `AGENTS.md`。
