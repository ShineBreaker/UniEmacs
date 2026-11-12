# UniEmacs

跨桌面与手机的统一 Emacs 配置：单一代码库，四档 profile。

| 档位       | 场景                                                                                            | 选择方式                    |
| ---------- | ----------------------------------------------------------------------------------------------- | --------------------------- |
| `minimal`  | 底座：纯内建、可调试、秒开                                                                      | `UNI_EMACS_PROFILE=minimal` |
| `portable` | Android 原生 Emacs 触屏                                                                         | Android 上自动；可 env 强制 |
| `standard` | 桌面全量：增强的完整 Emacs 体验，重点是掌握 Emacs 独有特性（窄化/寄存器/宏/Ediff…）             | 默认档                      |
| `ide`      | standard 超集：复刻 Zed/VSCode/JetBrains 的 IDE 体验（文件树/命令面板/面包屑/blame + 鼠标增强） | `UNI_EMACS_PROFILE=ide`     |

> 两个桌面档是不同目标体验：standard 档把 Emacs 独有机制做成可学习的一等公民（含 `self-discover` 发现层）；ide 档是给「从 Zed/现代 IDE 直接迁移」的用户的承接层，在 standard 之上做 IDE 化覆写与鼠标平权。

## 结构速览

- `early-init.el` / `init.el` — 入口
- `core/` — 四档共享基础设施（平台谓词、路径、包后端）
- `modules/` — 全部功能模块（`self-*.el`，含 `ide/` 档专属层）
- `profiles/` — 四档的模块清单与包声明
- `data/` — 翻译表、图标资产
- `docs/architecture.md` — 设计文档；`docs/platform-matrix.md` — 平台分支矩阵；`docs/mobile/` — 手机安装指南；`docs/windows/` — Windows 使用与便携包指南
- `scripts/` / `justfile` — 验证与运维命令

## 开发

设计原则：**可读性优先**——代码按 Emacs 初学者能读懂、能写、能调的标准组织（直白平铺 > 高阶压缩，函数体 ~40 行预算，详见 `docs/architecture.md` §1 与 `AGENTS.md` §3）；**单一真相源**——同一概念只允许一处定义。

```bash
direnv allow       # 或 denv load；环境由 manifest.scm 声明
just verify        # 启动后路径探针 + 图标字形覆盖 + 四档沙箱冒烟
just compile       # 全模块 byte-compile 零警告
```

手动冒烟某档：

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=minimal \
  emacs --batch -q -l early-init.el -l init.el
```

## 部署

- Windows：使用指南见 [docs/windows/README.md](docs/windows/README.md)（家目录 `%APPDATA%` 坑、字体注册表安装、语法库与终端的 Windows 机制）；U 盘便携包组装见 [docs/windows/portable.md](docs/windows/portable.md)。
- 桌面：入口两文件（`early-init.el`、`init.el`）放 `~/.config/emacs/`，仓库 clone 到任意位置，再用 `UNI_EMACS_REPO` 环境变量或 `~/.config/emacs/repo-location.el`（一行 `(setq self:repo "...")`，二选一）告诉入口仓库在哪。代码经 load-path 从仓库加载，`user-emacs-directory` 保持家目录不变——重定向只发生在 Android 分支；状态落在 HOME 下的隔离目录，仓库目录保持只读。
- Android：入口两文件复制到 Emacs 应用家目录的 `.emacs.d`（`/data/data/org.gnu.emacs/files/.emacs.d/`），仓库本体 clone 到 Termux home 的 `~/.config/emacs`；Termux 需为与 Emacs 同签名的重签版（[termux-emacs](https://github.com/ShineBreaker/termux-emacs) Releases 直接下载），完整安装流程见 `docs/mobile/README.md`。

首次启动说明：桌面档（standard/ide）首次启动会经 elpaca 从 MELPA/GNU ELPA 安装约 60 个包并逐包 byte-compile，实测约 15–20 分钟（机器与网络而异），期间无输出属正常；包装完落在状态目录，之后启动秒开。中途断网/断电不怕——重跑启动会接着装。字体（Maple Mono NF CN，仓库自带 `data/fonts/` TTF 时——如便携包——离线安装）与 Windows 预编译 tree-sitter 语法库同样在首次启动时后台自动补全（`modules/base/self-bootstrap.el`，不阻塞启动，装完重启生效）；失败 24 小时内不自动重试，可随时 `M-x self/bootstrap-fonts` / `M-x self/bootstrap-grammars` 手动补。

依赖由谁提供（包与字体同一原则）：**有 Guix 就交给 Guix**——Emacs 包走 Guix profile（`just` 只校验不安装），字体走系统/guix home 声明（`font-maple-mono-nf-cn`），自举与 `just font` 在 Guix 环境只提示不下载（`UNI_EMACS_FONT_DOWNLOAD=1` 可强制）；**没有 Guix** 时由首次启动自举 / elpaca 自动安装补齐，`just font` / `just grammars` 是同一份实现的手动入口。

详见 `docs/architecture.md` §6。

## 日常操作

- **切换档位**：`M-x self/set-profile` 选档，写入家目录 `profile.el`，重启 Emacs 生效（daemon 用 `herd restart emacs-daemon`）。环境变量 `UNI_EMACS_PROFILE` 优先级更高，设了会盖过它；删掉文件即回默认档 `standard`。
- **在 Emacs 内改笔记目录**：`M-x self/org-relocate`（`C-c o d`），前缀 `C-u` 连同旧内容一起搬。改动写入状态目录的 `org-locations.el`（下次启动自动读回），Roam / 收件箱 / agenda / 知识库随即跟随，无需重启。机制与取舍见 `docs/architecture.md` §8。

## 规范

AI agent 与贡献者工作前先读 `AGENTS.md`。
