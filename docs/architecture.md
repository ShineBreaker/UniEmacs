# UniEmacs 架构设计

> 版本 v0.2（2026-10-15）。改架构先改本文档与 AGENTS.md。

## 1. 目标与四档语义

UniEmacs 把桌面端与手机端两份独立配置统一为单一代码库。四档不是四套配置，而是同一份代码库上的四个**模块清单**：

| 档位      | 定位                       | 功能水平                                      | 第三方包          |
| --------- | -------------------------- | --------------------------------------------- | ----------------- |
| `minimal` | 全配置的底座，强调可调试性 | 对标 nano / 未大量配置的 nvim、helix          | **零**（纯内建）  |
| `portable`| Android 原生 Emacs 触屏    | 触屏交互、tool-bar、移动端 Org/Roam、阅读     | elpaca 管理       |
| `full`    | 桌面全量，可读性优先的学习档 | LSP/tree-sitter、项目管理、知识库、daemon   | Guix profile 管理 |
| `ide`     | full 超集：Zed 对齐的深度定制 | full 全部模块 + Treemacs 树/命令面板式补全栈/面包屑/行内 blame/minimap | Guix profile 管理 |

四档共享 `core/`（基础设施）与 `modules/`（全部功能模块）。档间差异只体现在 `profiles/<档>.el` 勾选了哪些模块、声明了哪些包。

`ide` 与 `full` 的关系刻意做成「清单超集 + 末尾覆写」而非继承机制：ide.el 的模块序列前半与 full.el 逐行同序，末端追加 `modules/ide/` 六个模块完成覆写（Treemacs 接管文件面板键位、三槽位 display-buffer 契约、corfu 栈接管行内补全、面包屑接管 header-line）。full 档保持语法可读优先——它是学习用桌面档；ide 档允许更复杂的实现，用来承接从 Zed/现代 IDE 直接迁移的用户。

### 设计原则（按优先级）

1. **可读性优先**：代码第一属性是易读、易写、易调试——目标读者是只认识 `defun`/`setq`/`let`/`dolist`/`use-package` 的 Elisp 入门者。省几行的高阶写法（`cl-loop` 解构、`pcase-let` 反引号、多层 lambda 嵌套、宏封装少量重复）一律降级为平铺直白写法；函数体预算 ~40 行，超了就拆具名辅助函数。规范全文见 `AGENTS.md` §3「可读性公约」，它是本仓库优先级最高的编码规范。
2. **单一真相源**：同一概念只允许一处定义；跨模块共享变量归 `core/self-lib.el` 或首个消费模块，其余文件一律不带值 `defvar` / `declare-function`。
3. **档位靠清单而非分支**：档间差异只在 `profiles/` 勾选模块；模块内用 `self:android-p` 等平台谓词守卫平台差异，禁止按 `self:profile` 自我裁剪。

## 2. 目录结构

```
UniEmacs/
├── early-init.el         # 入口①：启动期优化 + 平台常量 + profile 解析
├── init.el               # 入口②：引导加载
├── core/
│   ├── self-lib.el       #   平台谓词、路径常量、profile 解析结果、加载辅助
│   └── self-package.el   #   包后端抽象（guix 校验 / elpaca 安装）
├── modules/              # 功能模块按域归档（require 语义与目录无关）
│   ├── base/             #   三档共用底座：session / keys / editing / completion
│   ├── ui/               #   视觉层：theme / modeline / tabline / windowing / dashboard / help-zh
│   ├── touch/            #   触屏层：glyph / ui-touch / touch / bar / markdown / reading / misc
│   ├── org/              #   Org 知识栈：org / roam / agenote
│   ├── prog/             #   编程栈：compat / prog / langs / project / vcs / terminal
│   ├── desktop/          #   桌面运行环境：daemon / apps / keys-desktop
│   └── ide/              #   IDE 档层：chrome / panel / completion / blame / minimap
├── profiles/
│   ├── minimal.el        #   档清单 = 包声明 + require 序列 + 档内覆写
│   ├── portable.el
│   ├── full.el
│   └── ide.el
├── data/                 # 静态数据：翻译表、图标资产
├── scripts/              # 运维脚本（验证脚本 + Termux 重签脚本）
├── docs/                 # 设计文档（本文件等）
│   └── mobile/           #   手机部署与 Termux 重签专题
├── .github/workflows/    # CI：Termux 重签-发布流水线
├── assets/               # Emacs 官方公开构建密钥（重签 Termux 用）
├── justfile              # 本机命令入口
└── manifest.scm          # Guix 开发环境声明（direnv use guix）
```

## 3. 启动链路

```
emacs
 └─ early-init.el          ① 通用优化：GC 阈值拉高、file-name-handler-alist 置空、
   │                          frame 参数抑制、package-enable-at-startup=nil
   │                        ② 定义平台常量（不依赖 core）：self:android-p 等
   │                        ③ 解析 self:profile：UNI_EMACS_PROFILE → android→portable → full
   │                        ④ （Android 部署形态）user-emacs-directory 重定向到仓库
 └─ init.el
   ├─ load-path += core/ modules/<七域>/ profiles/
   ├─ (require 'self-lib)          路径常量、谓词、self/load-profile
   ├─ (require 'self-package)      检测后端；暂不安装
   └─ (self/load-profile self:profile)
       └─ load profiles/<档>.el    声明 self:profile-packages → self/package-ensure
                                   按序 require modules/
```

关键不变量：**任何一档都要求 core/ 先就绪，modules/ 只做被勾选的加载，profile 文件是唯一知道"本档要什么"的地方**。

## 4. 包后端抽象

```
self-package 检测顺序：
  EMACSLOADPATH 存在 / locate-library 命中 Guix site-lisp → backend=guix
    └─ 行为：逐个验证 profile 声明包可 locate，缺失 push 警告列表，启动末统一提示
  其余环境（Android/通用发行版）→ backend=elpaca
    └─ 行为：bootstrap elpaca（镜像可配）→ 对声明包排队安装 → elpaca-wait 收口
           版本 pin 走 elpaca lockfile（elpaca-write-lock-file 产物入库）
```

- 模块体内 `use-package` 永不写 `:ensure` 系关键字。
- 镜像配置沿用三层模型（ELPA 归档镜像 + recipe 仓库镜像 + 可选 GitHub 代理），变量名统一为 `self:elpa-mirror` / `self:github-proxy`。

## 5. 模块划分方案

移植原则是**功能内聚**：一份配置中的同一功能域尽量进同一个模块，平台差异在模块内用谓词守卫。`modules/` 按域分七个子目录归档——目录只是分类归属，`require 'self-<名>` 的语义与目录无关；**共享度优先**：同一概念只允许一处定义（变量真相源归 `core/self-lib.el` 或首个消费模块，其余文件一律不带值 `defvar` / `declare-function`），重复实现一经发现立即收敛。

### 5.1 `modules/base/` —— 三档共用底座（minimal 也加载）

| 模块             | 内容                                             | 来源域              |
| ---------------- | ------------------------------------------------ | ------------------- |
| `self-session`   | 持久化（recentf/savehist/saveplace）、失焦自动保存、auto-revert、备份策略 | startup/core-behavior |
| `self-editing`   | 基础编辑增强：缩进、DWIM、pair、内置补全默认值     | editing（基础子集） |
| `self-keys`      | `self/bind` 键位声明机制 + 顶层前缀声明          | keys-completion（机制层） |
| `self-completion`| 内置补全栈（桌面端全内建，vertico 栈在 Android 分支）| completion（两端合并）|

### 5.2 `modules/ui/` —— 视觉层

| 模块              | 档位           | 内容                                |
| ----------------- | -------------- | ----------------------------------- |
| `self-theme`      | full, portable | modus 主题 + D-Bus 深浅色 + 字体    |
| `self-modeline`   | full           | 桌面自研 modeline（缓存/分段/调度） |
| `self-tabline`    | full           | per-frame buffer 标签               |
| `self-windowing`  | full           | display-buffer 路由、窗口面板布局   |
| `self-dashboard`  | full, portable | 欢迎屏（两端合并，平台段守卫）      |
| `self-help-zh`    | full, portable | 帮助系统/右键菜单/which-key 中文化（含触屏分页） |

### 5.3 `modules/touch/` —— 触屏层（portable 为主）

| 模块              | 档位            | 内容                                |
| ----------------- | --------------- | ----------------------------------- |
| `self-glyph`      | portable, full  | 图标资产加载、NF 字形降级唯一入口   |
| `self-ui-touch`   | portable        | 移动端 UI（mode-line 按钮、配色状态、Android 落盘兜底） |
| `self-touch`      | portable        | 触屏交互（tap/选择/键盘联动、存储权限） |
| `self-bar`        | portable        | tool-bar / modifier-bar 按钮管线    |
| `self-markdown`   | portable        | 触屏 markdown UX（桌面由 self-langs 管 markdown-mode）|
| `self-reading`    | portable        | nov/阅读辅助                        |
| `self-misc`       | portable        | Android 杂项（分享入库、agenda 提醒等） |

### 5.4 `modules/org/` —— Org 知识栈

| 模块              | 档位            | 内容                                   |
| ----------------- | --------------- | -------------------------------------- |
| `self-org`        | full, portable  | org 基础、capture 模板装配、agenda 基线 |
| `self-roam`       | full, portable  | org-roam（Android 降额策略内守卫）     |
| `self-agenote`    | full            | agenote 知识库适配                     |

### 5.5 `modules/prog/` —— 编程与项目栈（full 为主）

| 模块              | 档位            | 内容                                   |
| ----------------- | --------------- | -------------------------------------- |
| `self-compat`     | full            | Emacs 31 兼容 shim（arei 兜底；唯一消费方 self-langs） |
| `self-prog`       | full            | tree-sitter、eglot、flymake、apheleia 格式化 |
| `self-langs`      | full            | 各语言 mode 注册（fish/kdl/nix/zig/gdscript/markdown 等） |
| `self-project`    | full            | project.el、目录树、项目导航           |
| `self-vcs`        | full            | magit/forge/diff-hl、git 状态展示      |
| `self-terminal`   | full            | ghostel 终端面板 + GIT_EDITOR 导出     |

### 5.6 `modules/desktop/` —— 桌面运行环境（full 为主）

| 模块              | 档位            | 内容                                   |
| ----------------- | --------------- | -------------------------------------- |
| `self-daemon`     | full            | server-mode、daemon 预热、client 帧行为 |
| `self-apps`       | full            | agent-shell / telega / guix / newsticker 等应用集成 |
| `self-keys-desktop` | full          | 桌面键位表（C-hjkl 移动、IDE 直达键、面板切换）；机制层在 self-keys |

### 5.7 `modules/ide/` —— ide 档专属层（full 之上的覆写/新增）

| 模块                  | 档位  | 内容                                       |
| --------------------- | ----- | ------------------------------------------ |
| `self-ide-chrome`     | ide   | 字体分轨（Maple Mono NF CN + Sarasa UI SC）、绝对行号、面包屑 header-line、标签 Git/诊断着色、裁 menu/tool-bar、frame 标题、colorful-mode |
| `self-ide-panel`      | ide   | Treemacs 左侧项目树（nerd-icons/deferred git/follow/tag-follow），接管 C-b/C-S-e/C-c w f/d/T |
| `self-ide-slots`      | ide   | 三槽位窗口契约（左树/底面板/编辑区）：display-buffer-alist 声明层+兜底层，未声明 buffer 一律进底槽 |
| `self-ide-completion` | ide   | vertico/orderless/marginalia/consult/embark 命令面板栈 + corfu/kind-icon/cape/eldoc-box 行内补全；关闭 completion-preview |
| `self-ide-blame`      | ide   | 行内 Git blame（idle 防抖 + 异步 porcelain + 行尾 overlay） |
| `self-ide-minimap`    | ide   | 右缘代码缩略图（prog/text/conf buffer）     |

模块清单是演进式的：移植时发现更合理的边界就拆/并，同步更新本表与目录归属。

## 6. 部署模型

- **桌面**：仓库 clone 到任意位置；`~/.config/emacs/`（或 `~/.emacs.d/`）放 `early-init.el` + `init.el` 两个入口副本（或软链），`early-init` 把 `user-emacs-directory` 重定向到仓库。Guix 继续管包。
- **Android**：入口两文件复制到 Emacs 的 `~/.emacs.d`，仓库 clone 在 Termux home，重定向后全部从仓库加载——沿用在真机上已验证的转发模型；Termux 需为与 Emacs 同签名的重签版，完整安装流程与真机验证清单见 `docs/mobile/README.md`。
- **状态隔离**：缓存/持久化统一进 `self:var-directory`（XDG state 语义），仓库目录保持只读源码身份。
- **手机基建**：仓库同时承载 Termux 重签流水线——`scripts/` 两条脚本（抓取上游预览版 + 重签并断言证书指纹）、`assets/emacs.keystore`（Emacs 官方公开密钥）、`.github/workflows/resign-termux.yml`（每周检查上游并发布重签 APK 到 Releases）；`early-init.el` 的 Android 分支把 Termux bin 注入 `exec-path`/`PATH`（Emacs 才能执行 Termux 内的 git/rg/sqlite3）。机制与教程见 `docs/mobile/`。

## 7. 移植阶段规划

| 阶段 | 内容                                              | 产出                     |
| ---- | ------------------------------------------------- | ------------------------ |
| P0   | 规矩与环境（本文档、AGENTS、manifest.scm）        | 可工作的开发环境         |
| P1   | core 脚手架（early-init/init/self-lib/self-package）+ 三 profile 骨架 | minimal 档冒烟可启动 |
| P2   | 底座模块移植（session/editing/keys/completion）   | minimal 档功能完整       |
| P3   | 移动端模块移植（glyph/ui-touch/touch/bar/org/roam/dashboard/reading/markdown） | portable 档全绿 |
| P4   | 桌面模块抽取（appearance/programming/projects/org-knowledge/system-tools 8 域） | full 档全绿 |
| P5   | 验证管线硬化 + 部署脚本 + 真机/真桌面验收         | 交付                     |

每阶段内的模块移植按依赖拓扑序逐个进行，一个模块一个 commit。
