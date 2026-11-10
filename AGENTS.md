# AGENTS.md — UniEmacs 项目规范与工作手册

本文件是本仓库下 AI Agent 的唯一操作规范。改代码前先读本文件、README.md 与 `docs/architecture.md`。

## 0. 项目概述

UniEmacs 是一份跨桌面与手机的统一 Emacs 配置：单一代码库、四档 profile（`minimal` 底座 / `portable` 移动端 / `desktop` 桌面全量——增强的完整 Emacs 体验，重点是学习与掌握 Emacs 独有特性 / `ide` 完整复刻 Zed/VSCode/JetBrains 的 IDE 体验，含鼠标交互增强），四档共享 `core/` 与 `modules/`，差异仅在各自 manifest 加载哪些模块。

**绝对禁令：禁止在任何受 git 跟踪的文件中提及 `reference/` 目录或以任何形式引用它的路径**——它只是本地参考资料夹，需要其中代码时直接复制进正式目录。

## 1. 环境管理（direnv / Guix）

- 一律使用 direnv 管理开发环境；`manifest.scm` 是环境的唯一声明源，新增工具/依赖先改 manifest。
- `.envrc` 由 denv 托管（`use guix`），不要手工改写其托管区块。
- 新克隆仓库先 `direnv allow`（或 `denv load`）再工作。

## 2. 架构契约

```
early-init.el    通用启动优化 + 平台常量 + profile 解析（UNI_EMACS_PROFILE env → profile.el → 平台推断 → 默认 ide）
init.el          引导：定位仓库根 → 配 load-path → require self-lib → self/load-profile
core/self-lib.el      平台谓词、路径常量、加载辅助（四档共享）
core/self-package.el  包后端抽象（guix | elpaca）与包清单装/验（四档共享）
modules/<域>/self-*.el 全部功能模块，按域归档（base/ui/touch/org/prog/desktop/ide）；一个文件一个内聚功能单元，provide 'self-<名>；跨模块共享变量唯一定义在 core/self-lib.el 或首个消费模块，其余处一律不带值 defvar 声明
profiles/<档>.el      该档的加载契约：包清单 + 模块 require 序列 + 档内覆写
data/                 静态数据（翻译表、图标资产）；只允许字面量 setq / defconst 与注释
scripts/              运维脚本（验证脚本）
docs/                 设计文档；docs/mobile/ 手机部署指南
justfile              本机命令入口（verify / compile / 配置依赖）
```

启动调用链：`emacs → early-init.el → init.el → self-lib → self-package → profiles/<档>.el → 按序 require modules/`。

### Profile 解析（优先级从高到低）

1. 环境变量 `UNI_EMACS_PROFILE`（`minimal` / `portable` / `desktop` / `ide`）
2. 家目录 `profile.el`：`M-x self/set-profile` 写入，下次启动生效
3. 平台推断：`system-type = android` → `portable`
4. 默认 `ide`

### 加载契约（硬约束）

- **`profiles/<档>.el` 中的 require 序列是模块依赖的唯一契约**，不得随意调换顺序；跨档共享的模块一律进 `modules/`，档私有代码直接写在 profile 文件内或 `modules/` 中带 `:profiles` 声明的独立文件。
- 模块文件头的 `;;; Commentary:` 下方必须标注两行元信息：`;; Profiles: <使用该模块的档>` 与 `;; Requires: <依赖的 self-* 模块>`。
- **跨模块引用必须显式声明**：函数用 `declare-function`，变量用 `defvar` 就近声明；禁止用 `boundp` 防御性访问他模块变量（模块由 manifest 保证已加载）。
- 同一仓库内部的函数互调不加 `fboundp`/`boundp` 守卫；守卫仅用于第三方延迟加载包与跨构建变量。
- 平台差异与档位差异是**两个正交维度**：平台差异用 `self:android-p` / `self:gui-p` 等谓词在模块内部守卫；档位差异只能通过 manifest 勾选模块实现，模块内禁止 `when (eq self:profile ...)` 式自我裁剪。

### 用户可改路径（Org 重定位）

Org 路径族里只有根目录 `self:org-directory` 允许在 Emacs 内改：`M-x self/org-relocate`（`C-c o d`）写 `self:org-config-file`（状态目录下 `org-locations.el`，启动时在派生路径之前读回），并重算 Roam/收件箱/知识库派生值、运行 `self/org-relocate-hook`。各 Org 模块（self-org / self-roam / self-agenote）在钩子上注册刷新函数，把各自持有的第三方包变量（org-directory / org-roam-directory / agenote-*）同步到新路径。派生路径不单独可配；持久化文件按机器落在状态目录，不入仓库。机制与取舍见 `docs/architecture.md` §8。

### 手机基建（Termux 同签名重签）

Android 需要与 Emacs 同签名的 Termux（`sharedUserId` 机制），APK 重签流水线已剥离到独立仓库 [termux-emacs](https://github.com/ShineBreaker/termux-emacs)：密钥、脚本、CI 与机制文档都在那边（覆盖主程序与官方插件）；本仓库只保留手机部署指南（`docs/mobile/README.md`）。`early-init.el` 的 Android 分支负责把 Termux bin 注入 `exec-path`/`PATH`。

## 3. 命名与代码规范

### 命名空间

`self` 是本配置的唯一命名空间：

| 形式               | 用途                   | 示例                     |
| ------------------ | ---------------------- | ------------------------ |
| `self:` 前缀       | 配置变量与常量         | `self:org-directory`     |
| `self/` 前缀       | 交互命令与普通函数     | `self/compile-modules`   |
| `self--` 前缀      | 跨模块共享的内部实现   | `self--startup-handlers` |
| `self/<mod>--`     | 模块私有实现           | `self/org--parse-title`  |

禁止 `intern`/`format` 动态拼接符号名。注意避开 Emacs 内建 `custom-*` / `self-insert-*` 命名空间，不复用旧配置的 `custom:` 前缀。

### 文件格式硬要求（每个 .el）

- 首行：`;;; <名>.el --- <一句话描述> -*- lexical-binding: t; -*-`
- `;;; Commentary:` 段（含 Profiles/Requires 两行）+ `;;; Code:` 分隔
- 末尾 `(provide '<feature>)` + `;;; <名>.el ends here`
- 所有公开函数/变量带 docstring；交互命令注明触发方式

### 可读性公约（目标读者：Elisp 入门者，最高优先级）

代码第一属性是**可读、可学、可改**——省几行的高阶写法若抬高阅读门槛，一律不用。读这份代码的人可能只认识 `defun`/`setq`/`let`/`dolist`/`use-package`、刚接触反引号；每处写法都按这个标准验收。

- **函数体预算 ~40 行**：超过就拆成具名辅助函数（每个可 `C-h f` 跳转、出错时栈里有名字），而不是继续堆嵌套；嵌套深度尽量 ≤3 层，更深就提前 `let`/`cond` 分派。
- **不为少量重复引入宏或高阶封装**：2~3 处同构命令直接平铺 `defun`；禁止 `intern`/`format` 动态拼符号名。
- **数据表可留，派生链要平铺**：plist/alist 作单一事实源保留；派生逻辑写成 `dolist` + 具名函数 + `push`/`nreverse`，禁止多层 `seq-*`/lambda/`mapcar` 混嵌成单表达式。
- **高阶解构降级**：`cl-loop` 解构、`pcase-let` 反引号解构、`cl-flet`/`cl-labels`、`cl-remove-if-not` 等方言一律降级为 `dolist` + `let` 逐项取 + `car`/`cdr`/`nth`；`pcase` 只允许「按形状分派」的扁平 switch 用法（每条 pattern 单行字面量或简单 `,var`），禁止嵌套反引号。**降级陷阱**：`cl-loop` 的 `collect ... into` 是尾追加（`nconc`）语义，换成 `push` 是逆序累加——改写后 `nreverse` 的条件要跟着翻转，务必用输入对照验证。
- **必要技巧就地解释**：`advice-add`、overlay 差集、`setf (alist-get ...)`、`run-with-idle-timer` 防抖等无法平铺的机制，保留时就近补 3~8 行「为什么需要它 + 取舍」注释。
- **命名即文档**：变量/函数名说清所存数据的形状（如 `self:binding-spec` 条目形状写进 docstring）；跨模块共享变量的唯一定义归 `core/self-lib.el` 或首个消费模块。
- **教读者自助**：引入新机制时在注释里给 `C-h f` / `C-h v` / `M-x customize-group` / `(info ...)` 自助查询路径，克制不写教程。
- 机制解释、设计取舍写进 `;;; Commentary:` 或 `docs/`，代码块内只留 docstring 与必要的就地注释。
- **简化不等于删功能**：按本节降级重写时行为必须等价，验收走 §5.4 等价性证据流程；发现疑似 bug 只记录上报，不顺手修。

### 精简与防御边界

- 只用一次的辅助函数直接内联，禁止纯转发包装。边界澄清：本条针对「一行调用另一个具名函数」的转发壳；为打散多层嵌套而抽出的实质逻辑函数（哪怕只被调一次）不属于本条，属于可读性公约的拆分手段。
- `condition-case` 仅包裹文件 I/O、外部子进程或 D-Bus；对返回 nil 的查询型 API 不加包裹。
- 存活检查（`frame-live-p`/`buffer-live-p`）仅在异步回调（Timer、D-Bus、Process Sentinel）中保留。

### 包管理纪律

- 模块体内的 `use-package` **永不写 `:ensure` / `:straight` / `:elpaca`**——装包是 profile manifest 的职责。
- 每个 profile 文件顶部以 `self:profile-packages` 声明本档第三方包清单；`self-package` 按后端执行：Guix 环境验证 `locate-library` 缺失即警告，其余环境经 elpaca 安装（含 lockfile pin 与镜像配置）。
- 新增或删除第三方包须**三处同步**：
  1. profile 清单（各档 `self:profile-packages`）；
  2. `manifest.scm`（direnv 开发环境的 Guix 侧登记，供 `just verify` / `just compile`）；
  3. `Guix-configs/source/config.org` 里的 emacs 包列表（Guix home 运行时包，决定 `~/.guix-home/profile` 实际装什么）。

  只改前两处的典型症状：`just verify` 报「以下包在 Guix 环境中找不到」，或代码写成后 `locate-library` 永远返回 nil。`source/config.org` 在父仓库（Guix-configs），改完需 `blue home` 重新部署才生效。

### 内建优先

引入第三方包或自己写实现前，先确认当前 Emacs 是否已经提供同等能力——尤其是最近两个大版本新增的功能。查证顺序：

1. `M-x view-emacs-news`（`C-h n`）读当前版本的 NEWS；历史版本看 `etc/NEWS.31`、`NEWS.30` 等；
2. `C-h f` / `C-h v` 查命令与变量是否已内建；`featurep` / `locate-library` 实测比文档可靠；
3. 只有内建（含少量 `setopt` / hook 组合）确实满足不了，才引入第三方包。

反向同样成立：每次升级 Emacs 后主动复查已装包，内建已覆盖的就删包，删除仍走上面的三处同步。

判据是「需求是否已被覆盖」，不是「内建是不是更好」：内建覆盖不到（如 vertico 的垂直补全 UI、magit 的交互式暂存），该装就装；内建能覆盖却另装一份，就是白养一条维护面。同理适用于手写实现——`delete-trailing-whitespace-mode`、`treesit-enabled-modes` 这类新内建已经做掉的事，不要再自己写一遍。

### 性能硬约束

1. 优先级：交互延迟 > 长时运行稳定性 > 启动时间。
2. 热路径禁令：mode-line / tab-line / redisplay / post-command 等高频回调中禁止文件 I/O、同步子进程、重复 `require`。
3. 昂贵计算用 buffer-local / frame-local 缓存，在 save/revert/major-mode 切换时精准失效。
4. UI 交互绝不同步等待外部 CLI，统一 `make-process` 异步。
5. minimal 档额外约束：**不得声明任何第三方包**（纯内建，对标 nano / 未配置 nvim 的功能水平与可调试性）。

## 4. 标准工作流

1. **定位**：改模块先读文件头 Profiles/Requires 元信息；新增功能先判断属于哪个模块或是否该新建。
2. **就地修改**：编辑对应模块；跨模块 API 变更要同步所有 Requires 它的文件。
3. **登记**：新增包 → profile 清单 + `manifest.scm` + `Guix-configs/source/config.org` 三处同步；新增模块 → 文件头元信息 + 相关 profile 清单。
4. **验证**：跑 `just verify`（见 §5）；改动部署/启动链路还须真机或沙箱端到端验证。

## 5. 验收标准

### 5.1 一键验证

```bash
just verify    # = 启动后路径探针（portable 档）+ 图标字形覆盖 + 四档沙箱冒烟
just compile   # = 全模块 byte-compile 零警告（单独目标）
```

### 5.2 沙箱冒烟（每档）

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=<minimal|portable|desktop|ide> \
  emacs --batch -q -l early-init.el -l init.el </dev/null
```

沙箱 `HOME` 隔离持久化状态，禁止污染真实 `~/`。`-q` 保留 site-start（Guix profile 的 autoloads 需要它），不用 `-Q`。所有 batch 调用点 stdin 固定 `</dev/null`：交互提示（如 `org-agenda-files` 缺文件询问）在 batch 无可答话界面，开着的 stdin 会永久阻塞，EOF 让提示走 Abort 分支跑完——配套地，`initial-buffer-choice` 等 UI 入口安装处必须 `(unless noninteractive ...)` 守卫（`command-line-1` 在 batch 下也会求值它，实测触发过冒烟假死）。

### 5.3 Byte-compile

所有 `core/`、`modules/`、`profiles/` 下 `.el` 必须 batch byte-compile **零警告**（先加载完整配置再编译单文件，否则误报未定义符号）。

### 5.4 等价性证据（移植/重构类改动）

平铺、改名、拆分等不改行为的改动，禁止「看起来一样」式结论，必须给出证据：改动前后在 batch Emacs 中对典型输入（含边界值）比对返回值与副作用；键位系统改动须比对 `self:binding-spec` 条目数。多表达式验证写成 `.el` 用 `-l` 加载——`--eval` 只读第一个 sexp。

## 6. Commit 规范

- Conventional Commits：`feat(scope):` / `fix` / `docs` / `chore` / `refactor` / `test`；scope 用模块名或 `core`/`profiles`/`env`/`docs`。
- **细粒度优先**：一个模块移植 = 一个 commit；规矩文档、环境、脚手架、各模块各自独立成 commit；保持每个 commit 可独立审阅与 revert。
- 移植类 commit message 注明「移植自哪份配置的哪个部分」，不写源路径。
- 提交前跑 `git diff --check` 与相关验证。

## 7. 多 agent 协作约定

本仓库由主 agent 编排、经 herdr 分派执行：

- **pi** → 核心/后端实现（core、包后端、loader、manifest 机制）
- **claude** → 量大且边界清晰的杂活（批量移植、改名、数据搬移）
- **hermes** → 测试与验证（justfile 管线、沙箱冒烟、回归比对）

主 agent 负责设计文档、规矩、审阅 diff 与 commit。任务书放 `.agents/tasks/`（不入 git）。
