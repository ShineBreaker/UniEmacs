# 平台分支矩阵

UniEmacs 用同一套代码跑 Android 触屏、Windows / Linux 桌面与 TTY。平台差异
**不拆文件**，而是在模块内部用谓词守卫（见 [AGENTS.md](../AGENTS.md) §2 的
正交性约定）。本文把全部分支点登记成矩阵，配合源码里的 `;; Platform:` 标记，
让「哪段代码为哪个平台而写」一眼可查。

新增或修改平台分支时：先在本矩阵登记，再在源码加标记（见 §6 流程）。

## 1. 三个正交维度

平台不是单一开关，而是三条独立的轴，一个分支可能只动其中一条：

| 维度 | 取值 | 判定方式 | 标记词 |
|------|------|----------|--------|
| 操作系统 | android / windows / linux | `system-type`；`self:android-p` 是加载期常量 | `android` `windows` `linux` |
| 显示类型 | gui / tty | `display-graphic-p`（逐帧、运行期）；`self:gui-p` / `self:tty-p`（加载期常量） | `gui` `tty` |
| 包环境 | guix / elpaca | `self/package--guix-emacs-p`（core/self-package.el） | `guix` |

- **OS 与显示独立**：Android 恒 gui；桌面可 gui 可 tty。主题、字体、字形
  分支往往同时看两条轴（如 `gui, tty`）。
- **包环境与 OS 独立**：Guix 只出现在 Linux，但「是不是 Guix」决定的是依赖
  从哪来（profile 注入 vs elpaca 下载），不是系统调用差异。
- **逐帧 vs 加载期**：`display-graphic-p` 用于多帧混合场景（同一 Emacs 既有
  图形帧又有终端帧，emacsclient 在两种端口各开一帧）；`self:gui-p` 等加载期
  常量用于一次性安装决策。取舍理由见 core/self-lib.el 平台谓词节注释。

## 2. 标记公约

源码里每个分支点上方一行：

```elisp
;; Platform: android, windows
(defun self/color-scheme--init () ...)
```

- 标记紧贴在分支形式（`defun` / `defconst` / `setq` / `use-package` /
  `when` / `if` / `let`）上方；已有注释块的，并入为最后一行；整节同属一个
  平台的，打在节标题下、覆盖全节（如 self-package 的后端检测节）。
- 标记词只用 §1 的六个值，多个用 `, ` 分隔，表示「这段为这些平台而分支」。
- **本文按 文件 + 符号名 锚定，不记行号**——标记随代码增删移位，符号名稳定。
- 全量定位：

  ```sh
  grep -rn ";; Platform:" early-init.el init.el core modules
  ```

## 3. 启动链路（early-init → init → core）

| 文件 | 符号 / 位置 | 平台 | 分支内容 |
|------|-------------|------|----------|
| early-init.el | Android 重定向 `if`（self:repo 判定后） | android | Termux 部署把 `user-emacs-directory` 重定向到应用私有目录 |
| early-init.el | Termux PATH `when` | android | 注入 `/data/data/com.termux/files/usr/bin` |
| early-init.el | tty-params `let` | tty | 终端帧背景/前景设 unspecified，配色交给终端 |
| early-init.el | profile 解析 `setq` | android | 缺省档 android→portable，其余→standard |
| init.el | 兜底 `setq self:profile` | android | 同上兜底（early-init 未跑时） |
| init.el | `self/deploy--conclusion` | android | 部署诊断结论按 Android 链路给文案 |
| init.el | `self/deploy-diagnose` | android | 诊断 buffer 的 Android 专项 |
| init.el | 入口转发 `if` | android | Android 走转发入口，其余走本体 |
| core/self-lib.el | 平台谓词节（`self:android-p` / `self:gui-p` / `self:tty-p`） | android, gui, tty | 定义三轴加载期常量 |
| core/self-lib.el | `self:data-home` | android | 数据根：Android 应用私有 vs XDG |
| core/self-lib.el | `self:var-directory` | android | 状态目录派生 |
| core/self-lib.el | `self:cache-directory` | android | 缓存目录派生 |
| core/self-lib.el | `self:org-default-directory` | android | 笔记默认落点 |
| core/self-lib.el | exec-path `let*`（guix-profile） | guix | Guix profile 的 bin 注入 `exec-path` |
| core/self-package.el | 后端检测节（`self/package--guix-emacs-p` / `self/package-backend`） | guix | 探测顺序：/gnu/store exe 真实路径 → `guix-emacs` 库可 locate → EMACSLOADPATH 弱兜底 |
| core/self-package.el | guix 后端节（`self/package--spec-prefixes` 起） | guix | Guix 只校验不下载 |

## 4. 各域模块

### base

| 文件 | 符号 | 平台 | 分支内容 |
|------|------|------|----------|
| self-editing.el | 物理折行 `if` | android | 触屏任何 buffer 都 `visual-line`，桌面按模式 |
| self-editing.el | `self--maybe-enable-indent-bars` | gui | 仅图形帧开 `indent-bars` |
| self-completion.el | `completion-styles` `setq` | android | 触屏 orderless，桌面 flex |
| self-completion.el | vertico 栈 `when` | android | 触屏 vertico 平铺，桌面默认 |
| self-bootstrap.el | `self:bootstrap-font-directory` | android, windows, linux | 字体落点三平台各异（Android 应用 fonts/、Windows per-user 目录、Linux fontconfig 用户目录） |
| self-bootstrap.el | `self:bootstrap-tar-program` | windows | 钉死 System32 bsdtar，避开 Git Bash GNU tar 的 colon 陷阱与 zip 不支持 |
| self-bootstrap.el | `self/bootstrap--font-needed-p` | guix | 归 Guix 声明管理的字体跳过下载（`UNI_EMACS_FONT_DOWNLOAD=1` 可强制） |
| self-bootstrap.el | `self/bootstrap--grammars-needed-p` | windows | 语法库自动补全仅 Windows（json 库作哨兵） |
| self-bootstrap.el | `self/bootstrap--font-steps` | windows | Windows 用 bsdtar 解 zip 并追加注册表步，其余平台 unzip |
| self-bootstrap.el | `self/bootstrap--reg-steps` | windows | HKCU per-user 字体注册（无需管理员） |
| self-bootstrap.el | `self/bootstrap-grammars` | windows | 非 Windows 直接跳过 |

### ui

| 文件 | 符号 | 平台 | 分支内容 |
|------|------|------|----------|
| self-theme.el | dbus require `unless` | windows, linux | Windows 不 require dbus（无 D-Bus） |
| self-theme.el | `use-package mouse` | android | 触屏不启用右键 `context-menu-mode` |
| self-theme.el | `self/theme--apply-terminal-faces` | tty | 终端透明背景 |
| self-theme.el | `self/theme--refresh-terminal-faces` | tty | 终端 face 刷新 |
| self-theme.el | `self/theme--apply-frame-appearance` | gui, tty | 逐帧外观分轨 |
| self-theme.el | `self/color-scheme--get-from-dbus` | linux | Darkman D-Bus 取深浅色 |
| self-theme.el | `self/color-scheme--get-from-registry` | windows | 注册表取深浅色 |
| self-theme.el | `self/color-scheme--register-listener` | linux | D-Bus 信号跟随 |
| self-theme.el | `self/color-scheme--supports-themes-p` | gui, tty | 终端能否呈现完整 palette 的降级判定 |
| self-theme.el | `self/color-scheme--init` | android, windows, linux | 三平台各自的初始模式与跟随入口 |
| self-modeline.el | `self/modeline-refresh` | gui | 图形帧状态行 |
| self-modeline.el | `self/modeline--tooltip-hide` | tty | 终端 tooltip 清理特化 |
| self-help-zh.el | which-key 触屏覆盖 `when` | android | 触屏 which-key 布局 |
| self-dashboard.el | `self/dashboard--icon` | gui | 图形 NF 图标，tty 空串 |
| self-dashboard.el | `self/dashboard--nav-buttons` | gui, android | 导航按钮按显示/触屏取舍 |
| self-dashboard.el | `self/dashboard-insert-permission-notice` | android | 存储权限未授予时的警示行 |
| self-dashboard.el | `self/dashboard--line-width` | gui, tty | 像素量法 vs 终端列宽校正 |
| self-dashboard.el | `self/dashboard--decorate-headings` | android | 触屏标题装饰 |
| self-dashboard.el | 视觉层 `if` | android | 触屏整块视觉重排 |

### touch

| 文件 | 符号 | 平台 | 分支内容 |
|------|------|------|----------|
| self-ui-touch.el | 字体 `let`（font-spec） | gui | 图形帧才设 Maple Mono NF CN |
| self-ui-touch.el | auto-save-visited `when` | android | 触屏定期真保存（FUSE 直写、无 #file# 垃圾） |
| self-touch.el | Android 触屏特化 `when` | android | 默认落点共享存储根等 |
| self-misc.el | server-start `when` | android | Android 起 emacsclient server |
| self-glyph.el | `self/glyph-nf-p` | gui, tty | NF 字形降级判定（tty 由 `UNI_EMACS_NF_TTY=1` 开） |
| self-bar.el | tool-bar 安装 `when` | android | 触屏工具栏 + 套主题后整条重装 |

### org

| 文件 | 符号 | 平台 | 分支内容 |
|------|------|------|----------|
| self-org.el | `self/org--toggle-link-previews` | gui | 逐帧链接预览开关 |
| self-org.el | `self/org-capture--roam-file` | android | 触屏 capture 落点 |
| self-org.el | org-protocol `when` | android | 空闲加载 + server 侧 advice |
| self-org.el | `self/org-modern--apply-display` | tty | 终端 org-modern 星号/表格降级 |
| self-org.el | 触屏面板 `when` | android | 确认面板整块按平台守卫 |
| self-roam.el | SQLite 后端警示 `when` | android | 缺 sqlite 时提示 Termux 装包 |
| self-roam.el | `use-package org-roam` | android | `:init` 选连接器 + 清孤儿 sqlite3 进程；`:config` 关全量 autosync |

### prog / desktop / ide

prog 域**没有平台谓词分支**——它的适配是环境探测型（§5）。desktop 域
除 Guix 工具走 profile 门控（§6）外，self-daemon 有一处 Windows 自愈
分支；ide 域两处逐帧分支：

| 文件 | 符号 | 平台 | 分支内容 |
|------|------|------|----------|
| self-daemon.el | `self/daemon--heal-server-auth-dir` | windows | 开 server-mode 前自愈认证目录所有权（管理员启动留下的 RID 544 quirk） |
| self-ide-chrome.el | `self/ide--apply-frame-faces` | gui | 图形帧字体分轨 |
| self-ide-panel.el | `self/ide--startup-layout` | gui | 图形帧才摆 Zed 式三槽布局 |

## 5. 环境探测型适配（不打标记）

有一类适配**不按平台谓词分支**，而是探测「能力/资源在不在」，在不在都走同一
逻辑、缺则降级。它们天然跨平台，不需要 `;; Platform:` 标记：

| 文件 | 探测 | 行为 |
|------|------|------|
| prog/self-prog.el | `file-directory-p` 缓存区 `tree-sitter/` | 目录在就注册进 `treesit-extra-load-path`；Guix 走 `TREE_SITTER_GRAMMAR_PATH` 注入，不经这里 |
| prog/self-langs.el | `treesit-ready-p` | 语法库就绪才把后缀覆盖到硬 ts-mode，否则保留内建兜底映射 |
| ui/self-theme.el | `find-font` `self:font-family` | 主字体装了才应用（GUI 分支），缺则保留系统默认；家族名唯一真相源在 core/self-lib.el |
| touch/self-ui-touch.el | `find-font` `self:font-family` | 同上，触屏档另覆写加大字号 |
| base/self-bootstrap.el | `data/fonts/` 三个 TTF 齐全 | 仓库自带字体（便携包）走离线拷贝+注册，缺则回退下载 |
| core/self-package.el | 后端探测 | 探测本身打了 `guix` 标记（§3），因为结果决定走哪条后端 |

区分原则：**「为某平台写不同代码」打标记；「探测资源在不在、不在就降级」不打**。
后者是能力守卫，不是平台分支。语法库的来源（self-bootstrap 首次启动自动下载、
`just grammars` batch 薄包装、Guix profile 注入）见
[windows/README.md](windows/README.md) 与 architecture.md。

## 6. 平台边界（什么不分支）

- **profile 差异不在这张矩阵里**：minimal / portable / standard / ide 的取舍
  由 manifest（`profiles/<档>.el`）决定，模块用 `Profiles:` 头声明归属，不用
  平台谓词。平台 × 档位是两条正交轴（AGENTS.md §2）。
- **Guix 专属工具靠 profile 门控，不靠平台谓词**：desktop/self-apps.el 的
  `guix.el` 只是 `use-package guix :defer t`，进 standard/ide 档清单；非 Guix
  机器上包照装、命令闲置，模块内没有 `guix` 谓词分支。这是档位取舍，不是平台
  分支——别给它打标记。
- **包版本差异不分支**：用 `fboundp` / `boundp` 能力守卫（如 org-roam 2.2 vs
  2.3 的连接器变量），不是平台分支。
- **新增平台分支的流程**：① 在本矩阵对应域表登记一行（文件 + 符号 + 平台 +
  内容）；② 在源码分支形式上方加 `;; Platform:` 标记；③ 确认分支落在模块内部
  而非新拆文件（AGENTS.md §2 / §4）。