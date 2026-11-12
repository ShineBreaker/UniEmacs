# UniEmacs

跨桌面与手机的统一 Emacs 配置：单一代码库，四档 profile。

## 快速开始

**Linux / macOS / Android(Termux)**——装好 `git` 与 `emacs` 后，一条命令：

```sh
curl -fsSL https://raw.githubusercontent.com/ShineBreaker/UniEmacs/main/install.sh | sh
```

**Windows**——PowerShell（Emacs 安装见 [Windows 指南](docs/windows/README.md)）：

```powershell
git clone https://github.com/ShineBreaker/UniEmacs "$env:APPDATA\.emacs.d"
```

然后启动 `emacs`。首次启动会自动安装全部依赖（约 60 个包与字体，15–35 分钟，期间无输出属正常，详见[首次启动](#首次启动)），装完即用。

### 三件事上手就够了

| 想做什么 | 怎么做 |
| --- | --- |
| 换一档体验 | `M-x self/set-profile` 选 `minimal` / `standard`（默认）/ `ide`，重启生效 |
| 装坏了/没反应 | `M-x self/deploy-diagnose` 给出诊断结论；或重跑上面的安装命令（幂等） |
| 改笔记目录 | `M-x self/org-relocate`（`C-c o d`），Roam / 收件箱 / agenda 自动跟随 |

### 四档 profile

| 档位       | 场景                                                                                            | 选择方式                    |
| ---------- | ----------------------------------------------------------------------------------------------- | --------------------------- |
| `minimal`  | 底座：纯内建、可调试、秒开                                                                      | `UNI_EMACS_PROFILE=minimal` |
| `portable` | Android 原生 Emacs 触屏                                                                         | Android 上自动；可 env 强制 |
| `standard` | 桌面全量：增强的完整 Emacs 体验，重点是掌握 Emacs 独有特性（窄化/寄存器/宏/Ediff…）             | 默认档                      |
| `ide`      | standard 超集：复刻 Zed/VSCode/JetBrains 的 IDE 体验（文件树/命令面板/面包屑/blame + 鼠标增强） | `UNI_EMACS_PROFILE=ide`     |

> 两个桌面档是不同目标体验：standard 档把 Emacs 独有机制做成可学习的一等公民（含 `self-discover` 发现层）；ide 档是给「从 Zed/现代 IDE 直接迁移」的用户的承接层，在 standard 之上做 IDE 化覆写与鼠标平权。

## 安装细则

安装器（`install.sh`）做的事：仓库 clone 到 `~/.config/emacs`（桌面标准落点，入口即仓库文件、**零副本零配置**），Android 上另放 Termux 惯例位置并复制入口到 Emacs 应用家目录，最后跑一次首启验证。幂等，重复运行安全；已 clone 过则改为 `git pull` 更新。

- **Android**：需要与 Emacs 同签名的 Termux 重签版（[termux-emacs](https://github.com/ShineBreaker/termux-emacs) Releases 直接下载），完整流程见 [docs/mobile/README.md](docs/mobile/README.md)。
- **Guix 用户**：包与字体走 Guix 声明（安装器与 Guix 共存，后端自动检测不冲突）——Emacs 包走 Guix profile，字体走 `font-maple-mono-nf-cn`；自举在 Guix 环境只提示不下载（`UNI_EMACS_FONT_DOWNLOAD=1` 可强制）。
- **高级选项**（一般用不到）：仓库放别处时设 `UNI_EMACS_REPO` 环境变量，或在家目录放 `repo-location.el`（`(setq self:repo "...")`）——二者优先级均高于默认位置。

## 首次启动

桌面档（standard/ide）首次启动会经 elpaca 从 MELPA/GNU ELPA 安装约 60 个包并逐包 byte-compile，实测 15–20 分钟（ide 约 35 分钟；机器与网络而异），期间无输出属正常；包装完落在状态目录，之后启动秒开。**中途断网/断电不怕——重跑启动会接着装。**

字体（Maple Mono NF CN；仓库自带 `data/fonts/` TTF 时——如便携包——离线安装）与 Windows 预编译 tree-sitter 语法库同样在首次启动后台自动补全（`modules/base/self-bootstrap.el`，不阻塞启动，装完重启 Emacs 生效）；失败 24 小时内不自动重试，可随时 `M-x self/bootstrap-fonts` / `M-x self/bootstrap-grammars` 手动补。

## 日常操作

- **切换档位**：`M-x self/set-profile` 选档，写入家目录 `profile.el`，重启生效（daemon 用 `herd restart emacs-daemon`）。环境变量 `UNI_EMACS_PROFILE` 优先级更高；删掉文件即回默认档 `standard`。
- **改笔记目录**：`M-x self/org-relocate`（`C-c o d`），前缀 `C-u` 连同旧内容一起搬。改动写入状态目录 `org-locations.el`（下次启动自动读回），Roam / 收件箱 / agenda / 知识库随即跟随，无需重启（机制见 `docs/architecture.md` §8）。

## 结构速览

- `early-init.el` / `init.el` — 入口
- `core/` — 四档共享基础设施（平台谓词、路径、包后端）
- `modules/` — 全部功能模块（`self-*.el`，含 `ide/` 档专属层）
- `profiles/` — 四档的模块清单与包声明
- `data/` — 翻译表、图标资产、便携包字体
- `docs/architecture.md` — 设计文档；`docs/platform-matrix.md` — 平台分支矩阵；`docs/mobile/` — 手机安装指南；`docs/windows/` — Windows 使用与便携包指南
- `install.sh` — 一键安装器；`scripts/` / `justfile` — 验证与运维命令

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

## 规范

AI agent 与贡献者工作前先读 `AGENTS.md`。
