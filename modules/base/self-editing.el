;;; self-editing.el --- 编辑体验：排版规范、DWIM 智能编辑、文本变换与编辑辅助 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: minimal, portable, full
;; Requires: self-keys（`self/bind'、`self/declare-binding-group'）、self-lib（`self:var-directory'、路径常量）
;; Packages: editorconfig, indent-bars, goto-chg, multiple-cursors,
;;           expand-region, vundo, idle-highlight-mode, tempel
;;
;; 移植自桌面端配置（literate Emacs 的「编辑与文本」整域；域内的
;; 「终端集成 ghostel」小节按边界拆去 self-terminal.el）。
;;
;; ─── 为什么 minimal 档能整份加载 ────────────────────────────────────
;;
;; 本模块刻意把「三档都要的基础编辑习惯」与「桌面端的第三方编辑增强」放进
;; 同一个文件：基础部分（缩进排版、软换行、覆盖选区、电配对、括号高亮、
;; DWIM 智能编辑、快速插入、关闭文件重开、C-c e 里指向内建命令的变换）
;; 全部是内建函数，minimal 档整份取用即对标 nano。
;;
;; 第三方包一律走**延迟形态**（`:commands' / `:hook' / `:mode'），minimal 档
;; 即使没装这些包也不会报错——用户按到某个键那一刻才尝试加载，失败也只是
;; 那一条键不可用。唯一做不到延迟的是全局 minor mode 类型的包（本文件的
;; editorconfig 与 diff-hl，后者已归 self-vcs），它们必须在本文件加载时
;; 就开启，故用 `(when (locate-library …))` 守卫并在注释里写明理由。
;;
;; ─── 机制说明 ──────────────────────────────────────────────────────
;;
;; · DWIM 函数的两种形状
;;   `self/copy-dwim' 与 `self/cut-dwim' 是同一骨架——`interactive'
;;   声明可交互调用，`cond' 先问 `use-region-p'（有选区的分支）再走
;;   `t'（无选区的兜底），读懂一个就能写下一个。
;;   `self/rename-dwim' 同样是 `cond' 分流，但条件换成「是否在 Eglot
;;   管辖下」：`eglot-managed-p' / `buffer-file-name'——骨架可复用，
;;   分流条件随意图而变。这里对 eglot 保留 `fboundp' 守卫是**允许的**：
;;   eglot 是第三方懒加载包，本仓库内部函数才禁止加守卫。
;;   `self/home-dwim' 则是另一形状：`let' 记住起点，
;;   `back-to-indentation' 跳到行首非空白字符，若光标本来就在那儿则退到
;;   绝对行首——「按一次换一个目标」的循环跳转，不需要选区判断。
;;
;; · `setq-default' 与 `setq' 的分工
;;   「基础缩进与排版规范」用 `setq-default' 设置 `tab-width' 这类
;;   「缓冲区局部变量」的默认值——之后某个 major mode 仍可局部覆盖，
;;   互不破坏。全局唯一的变量（如 `scroll-error-top-bottom'）则直接
;;   `setq`。
;;
;; · 辅助包声明即文档
;;   「编辑辅助包」里每个 `(use-package … :commands (…))' 列出的命令
;;   就是懒加载触发点——你在键位表里看到哪个命令，它被按到的那一刻包才
;;   会加载。想知道某插件提供什么入口，先看它的 `:commands' 列表。
;;
;; · 文本变换都是具名函数
;;   「文本变换与快捷键 (C-c e)」下每个变换（大小写、注释、重新缩进……）
;;   都是独立 `defun'，可以 `C-h f' 逐个查看再绑定。本模块刻意不用宏
;;   批量生成，为的就是每个命令都有名字、可跳转、错误栈可读。
;;
;; · 软换行是平台差异，不是档位差异
;;   触屏窗口窄且无横向滚动，org 长行必须物理折行，故全局开
;;   visual-line-mode；桌面按窗口宽度折行更合适，只对 org / markdown /
;;   text 三种阅读型模式开。故写成 `(if self:android-p …)' 平台分支。
;;
;; · `fullwidth-region' / `halfwidth-region' 来自 Emacs 内建库 `quail'，
;;   `upcase-dwim' / `downcase-dwim' / `capitalize-dwim' /
;;   `duplicate-dwim' / `replace-regexp-as-diff' /
;;   `multi-file-replace-regexp-as-diff' / `unix-word-rubout' /
;;   `project-current' 均是 Emacs 内建命令或函数（Emacs 31+），
;;   故不进 `;; Packages:' 清单。

;;; Code:

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))
(declare-function project-root "project" (project))

(declare-function eglot-managed-p "eglot" nil)
(declare-function eglot-rename "eglot" ())

;; 跨模块变量就近声明（AGENTS.md §2）。不带初值，只做 special 标记，
;; 实际取值由 core/self-lib.el 给出。
(defvar self:var-directory)
(defvar self:etc-directory)

;; ─── 基础缩进与排版规范 ─────────────────────────────────────────
;;
;; 默认 2 空格缩进、禁止插入 TAB（防跨平台缩进混乱）；按字符类别折行让
;; 中文在任意字符处自然断行；保存时清理行尾空格保持提交干净。
;; 位置保存与寄存器预览则是「回来还在原地」的编辑体感。
(setq-default indent-tabs-mode nil
              tab-width 2
              fill-column 100
              tab-always-indent nil
              truncate-lines t)

(setq word-wrap-by-category t)                ; Emacs 29+ 内建，中文按字折行

(global-so-long-mode 1)                       ; 超长行自动折叠段落

(show-paren-mode 1)
(save-place-mode 1)
(setopt save-place-autosave-interval 300)     ; 定期落盘光标位置
(repeat-mode 1)                               ; C-x / 重复上一条命令
(setq register-use-preview t)
(setq show-paren-context-when-offscreen 'child-frame)

;; editorconfig 是全局 minor mode，没有命令入口可挂 `:commands'，所以它是
;; 本文件唯一做不到纯延迟的第三方包：用 locate-library 守卫——包不存在时
;; 整段跳过，minimal 档因此不会因缺包报错，只是少了按项目 .editorconfig
;; 自动对齐的排版。
(when (locate-library "editorconfig")
  (require 'editorconfig)
  (setq editorconfig-trim-whitespaces-mode 'delete-trailing-whitespace-mode)
  (editorconfig-mode 1))

(add-hook 'text-mode-hook #'delete-trailing-whitespace-mode)

;; ─── 文本换行与编辑行为 ─────────────────────────────────────────
;;
;; 括号自动配对（有选区时输入括号直接包裹选区）。
;; `kill-region-dwim' 让无选区的 C-w 删掉整行而不是回杀一个词；
;; `kill-ring-deindent-mode' 让入环的多行文本去掉公共缩进。
;; 不开 `which-function-mode'：它的输出挂在 `mode-line-misc-info' 上，
;; 而底部状态栏只渲染 `global-mode-string'，开了也无处显示；且它会用空闲
;; 定时器反复跑 imenu 并强制刷新 mode-line，属不可见的热路径浪费。
;; 确需当前函数名时 M-x which-function-mode 临时开启。
(electric-pair-mode 1)

;; 软换行：触屏与桌面是两套策略（见 Commentary），故按平台分支。
(if self:android-p
    ;; 触屏：任何 buffer 都要物理折行，否则长 org 文件一行拉到屏幕外，
    ;; 用户既看不见也无从横向滚动。
    (global-visual-line-mode 1)
  ;; 桌面：只对阅读型的三种模式开折行；代码 buffer 保持 truncate-lines，
  ;; 免得长行被折成两半后行号对不上读代码。
  (dolist (hook '(org-mode-hook markdown-mode-hook text-mode-hook))
    (add-hook hook #'visual-line-mode)
    (add-hook hook #'visual-wrap-prefix-mode)))

(setq kill-region-dwim t)
(kill-ring-deindent-mode 1)
(setopt electric-indent-actions '(yank))

;; 翻页触底时把光标推到文件首/尾行而非报错，对齐 VSCode 持续滚动手感。
;; 左键拖拽移动选区；主选区（中键粘贴）对齐 Linux 编辑器惯例。
(setq scroll-error-top-bottom t
      mouse-drag-and-drop-region t
      select-enable-primary t)

(setq dired-filename-display-length 'window
      dired-movement-style 'cycle
      grep-use-headings t)

;; ─── DWIM 智能编辑核心（copy / cut / rename）─────────────────────
;;
;; 所谓 DWIM 即「按我的意图操作」（Do What I Mean）：根据当前是否有选区、
;; 光标所在上下文自动选最合适的操作。

(defun self/copy-dwim ()
  "智能复制：有选区时复制选区，否则复制当前行。
交互命令：M-x self/copy-dwim，也绑在 C-S-c。"
  (interactive)
  (cond
   ((use-region-p)
    (kill-ring-save (region-beginning) (region-end))
    (deactivate-mark)
    (message "已复制选区"))
   (t
    (kill-ring-save (line-beginning-position) (line-beginning-position 2))
    (message "已复制当前行"))))

;; 选中文字后输入任何字符或执行粘贴，自动覆盖替换选中的内容。
(delete-selection-mode 1)

(defun self/cut-dwim ()
  "智能剪切：有选区时剪切选区，否则剪切整行。
交互命令：M-x self/cut-dwim，也绑在 C-S-x。"
  (interactive)
  (cond
   ((use-region-p)
    (kill-region (region-beginning) (region-end)))
   (t
    (kill-whole-line))))

(defun self/rename-dwim ()
  "重命名符号或当前文件。

文件处于 Eglot 管辖下时走 LSP 的项目级重命名；否则重命名该文件本身；
两者都不满足时报错。交互命令：M-x self/rename-dwim，也绑在 <f2>。"
  (interactive)
  (cond
   ((and (fboundp 'eglot-managed-p)
         (eglot-managed-p)
         (fboundp 'eglot-rename))
    (call-interactively #'eglot-rename))
   (buffer-file-name
    (call-interactively #'rename-visited-file))
   (t
    (user-error "当前缓冲区不支持重命名"))))

;; ─── 行级 DWIM 命令（<backtab> 与 C-c i 之外的行操作）───────────
;;
;; `self/outdent-dwim' 的选区分支走 `indent-rigidly-left-to-tab-stop'
;; 逐行退到上一制表位，单行按 `tab-width' 退一级（`indent-line-to' 会把点
;; 一并带回行首缩进位）；选区分支显式置 `deactivate-mark' 为 nil，回缩后
;; 保留选区，可连按 Shift+Tab 逐层回缩（VSCode 行为）。

(defun self/outdent-dwim ()
  "向左回缩一个缩进层级：有选区回缩选区，否则回缩当前行（VSCode Shift+Tab）。
交互命令：M-x self/outdent-dwim，也绑在 <backtab>。"
  (interactive)
  (if (use-region-p)
      (progn
        (indent-rigidly-left-to-tab-stop (region-beginning) (region-end))
        (setq deactivate-mark nil))
    (indent-line-to (max 0 (- (current-indentation) tab-width)))))

(self/bind "<backtab>" #'self/outdent-dwim "反向缩进" "编辑变换")

(defun self/home-dwim ()
  "智能 Home 键：在行首非空白字符与绝对行首之间循环（VSCode Home 行为）。

`interactive' 的 \"^\" 码保持 Shift+Home 的选区扩张语义。
交互命令：M-x self/home-dwim，也绑在 <home>。"
  (interactive "^")
  (let ((pos (point)))
    (back-to-indentation)
    (when (= pos (point))
      (move-beginning-of-line 1))))

(defun self/open-line-below ()
  "在当前行下方开新行并移入（VSCode Ctrl+Enter）。
交互命令：M-x self/open-line-below，也绑在 C-<return>。"
  (interactive)
  (move-end-of-line 1)
  (newline-and-indent))

(defun self/open-line-above ()
  "在当前行上方开新行并移入（VSCode Ctrl+Shift+Enter）。
交互命令：M-x self/open-line-above，也绑在 C-S-<return>。"
  (interactive)
  (move-beginning-of-line 1)
  (open-line 1)
  (indent-for-tab-command))

;; ─── 快速插入（C-c i）───────────────────────────────────────────
;;
;; `C-c i f' 插入当前文件名；带前缀参数（`C-u C-c i f'）时插入相对项目
;; 根目录的相对路径，写文档或引用时无需手动抄路径。
;; `C-c i u' 直接调用 Emacs 原生 `insert-char'，按字符名或 Unicode 码点
;; 插入特殊符号。

(defun self/insert-file-name (&optional arg)
  "插入当前缓冲区的文件名。

ARG 非空（前缀参数）时插入相对项目根的路径，无项目时插入绝对路径。
交互命令：M-x self/insert-file-name，也绑在 C-c i f。"
  (interactive "P")
  (unless buffer-file-name
    (user-error "当前缓冲区未访问文件"))
  (let ((file buffer-file-name))
    (insert (if arg
                (if-let* ((proj (project-current nil (file-name-directory file)))
                          (root (project-root proj)))
                    (file-relative-name file root)
                  file)
              (file-name-nondirectory file)))))

(self/declare-binding-group "C-c i" "快速插入")
(self/bind "C-c i f" #'self/insert-file-name "插入文件名/路径" "插入")
(self/bind "C-c i u" #'insert-char "插入 Unicode 字符" "插入")

;; ─── 关闭文件历史（C-S-t）──────────────────────────────────────
;;
;; 浏览器「Ctrl+Shift+T」的 Emacs 版：记录最近关闭的 20 个本地文件路径，
;; 按 `C-S-t'（终端下的 `C-x T'）按倒序重开。自动忽略内部隐藏缓冲区与
;; 自动保存临时文件，守护进程常驻也不会累积垃圾。

(defconst self:closed-files-max 20
  "关闭文件历史长度上限。")

(defvar self--closed-files nil
  "最近关闭的文件名列表，最新在前。")

(defun self--on-kill-buffer ()
  "把刚关闭的文件缓冲区记入关闭历史。

排除内部 I/O 路径：库代码常以 `find-file-noselect' + `kill-buffer'
静默读写文件（如读 .dir-locals.el），只判 `buffer-file-name' 会把它们
收进历史。过滤规则：隐藏 buffer（名字以空格开头）、状态目录
（`self:var-directory'，备份与自动保存都落在那里）与备份/自动保存
文件（#...#、~ 结尾）一律不记。"
  (when-let* ((file (buffer-file-name)))
    (unless (or (string-prefix-p " " (buffer-name))
                (file-in-directory-p file self:var-directory)
                (string-match-p "\\`\\.?#\\|~\\'" (file-name-nondirectory file)))
      (setq self--closed-files
            (cons file (delete file self--closed-files)))
      (when (> (length self--closed-files) self:closed-files-max)
        (setq self--closed-files
              (seq-take self--closed-files self:closed-files-max))))))

(add-hook 'kill-buffer-hook #'self--on-kill-buffer)

(defun self/reopen-closed-file ()
  "重新打开最近关闭且仍存在的文件。

按最近在前顺序跳过已被删除的路径；全部失效时报错。
交互命令：M-x self/reopen-closed-file，也绑在 C-S-t 与 C-x T。"
  (interactive)
  (let ((file (seq-find #'file-exists-p self--closed-files)))
    (unless file
      (user-error "没有可重新打开的文件"))
    (setq self--closed-files (delete file self--closed-files))
    (find-file file)))

;; ─── 编辑辅助包（indent-bars, goto-chg, multiple-cursors,
;;     expand-region, vundo, idle-highlight-mode, tempel）────────
;;
;; · indent-bars：基于 Tree-sitter 语法树计算缩进，在代码左侧绘制淡色
;;   对齐竖线；仅在图形终端启用。
;; · goto-chg：快速在最近修改过代码的各个位置来回跳转。
;; · multiple-cursors：多光标编辑。支持多行光标以及标记所有同名匹配项。
;; · expand-region：语义选区扩展，按词、引号内容、括号表达式逐步扩大或
;;   收缩选区。
;; · vundo：可视化撤销树，以图形分支展现全部编辑撤销历史，按回车跳回
;;   目标历史状态。
;; · idle-highlight-mode：光标停驻 0.35s 后自动高亮当前符号在文件内的所有
;;   出现处（对齐 VSCode 的 occurrencesHighlight）。
;; · tempel：轻量代码模板展开，模板文件统一放在 etc/templates/*.eld，
;;   前置到补全函数链首优先匹配。

(defun self--maybe-enable-indent-bars ()
  "ts-mode hook 回调：仅图形 frame 开 `indent-bars-mode'。

竖线由 stipple（XBM 位图）绘制，终端 frame 没有位图可画；颜色也取自当前
frame 的主题背景，batch/哑终端 frame 上取不到值，只会退化成无效 face
spec。此处用运行期的 `display-graphic-p' 而非 core 的 `self:gui-p'
（后者是加载期求值的 defconst，分屏或新建 frame 后不更新）。

须先于下方 use-package 定义：`:hook' 展开时若目标非 fboundp，
use-package 会生成一个指向包内文件的 autoload 占位，顺序颠倒会留下重复
定义警告。"
  (when (display-graphic-p)
    (indent-bars-mode 1)))

(use-package indent-bars
  :defer t
  :hook ((c-ts-mode c++-ts-mode go-ts-mode java-ts-mode json-ts-mode
                    python-ts-mode rust-ts-mode typescript-ts-mode tsx-ts-mode
                    yaml-ts-mode) .
                    self--maybe-enable-indent-bars)
  :custom
  (indent-bars-color-by-depth nil)
  (indent-bars-pattern ".")
  (indent-bars-width-frac 0.15)
  (indent-bars-zigzag nil))

(use-package goto-chg
  :defer t
  :commands (goto-last-change goto-last-change-reverse))

(use-package multiple-cursors
  :defer t
  :commands (mc/edit-lines
             mc/mark-next-like-this mc/mark-previous-like-this
             mc/mark-all-like-this mc/mark-all-like-this-in-defun
             mc/mark-next-lines mc/mark-previous-lines
             mc/skip-to-next-like-this mc/create-fake-cursor-at-point))

(use-package expand-region
  :defer t
  :commands (er/expand-region er/contract-region))

(use-package vundo
  :defer t
  :commands (vundo))

(use-package idle-highlight-mode
  :defer t
  :if (locate-library "idle-highlight-mode")
  :hook (prog-mode . idle-highlight-mode)
  :custom (idle-highlight-idle-time 0.35))

(use-package tempel
  :defer t
  :commands (tempel-expand tempel-complete)
  :config
  ;; 模板目录归 `self:etc-directory'（core/self-lib.el 定义），不借道
  ;; no-littering 的函数——后者是 full 档才有的第三方包，在 minimal 档
  ;; 调用会直接报 void-function。放在 :config 里是因为 :init 会即时求值，
  ;; 那时 tempel 尚未加载，配置根本保存不住。
  (setq tempel-path
        (expand-file-name "templates/*.eld" self:etc-directory)))

(defun self/tempel--setup-capf ()
  "把 tempel-complete 前置到 buffer-local capf 链首。"
  (setq-local completion-at-point-functions
              (cons 'tempel-complete
                    (remq 'tempel-complete completion-at-point-functions))))

(dolist (hook '(prog-mode-hook text-mode-hook))
  (add-hook hook #'self/tempel--setup-capf))

;; ─── 文本变换与快捷键（C-c e）───────────────────────────────────
;;
;; 第一组：多光标、跳转与撤销、模板。
;; · 多光标：`C-c e l`（每行一个光标）、`C-c e n` / `p`（标记下一个/上一个
;;   匹配）、`C-c e a`（标记全部匹配）、`C-c e s`（跳过下一个匹配，对齐
;;   VSCode 的 Ctrl+K Ctrl+D）。
;; · 语义选区：`C-c e x` / `X`。
;; · 撤销与位置：`C-c e .` / `,`（上一个/下一个修改点）、`C-c e u`（Vundo）。

(self/bind "C-c e l" #'mc/edit-lines "每行一个多光标" "编辑变换")
(self/bind "C-c e n" #'mc/mark-next-like-this "标记下一个匹配" "编辑变换")
(self/bind "C-c e p" #'mc/mark-previous-like-this "标记上一个匹配" "编辑变换")
(self/bind "C-c e a" #'mc/mark-all-like-this "标记全部匹配" "编辑变换")
(self/bind "C-c e d" #'mc/mark-all-like-this-in-defun "函数内全部匹配" "编辑变换")
(self/bind "C-c e ." #'goto-last-change "上一处修改" "编辑变换")
(self/bind "C-c e ," #'goto-last-change-reverse "下一处修改" "编辑变换")
(self/bind "C-c e u" #'vundo "撤销树" "编辑变换")
(self/bind "C-c e t" #'tempel-expand "展开模板" "编辑变换")

(defun self/fullwidth-dwim ()
  "有选区时把选区转全角，无选区时转光标处词。
交互命令：M-x self/fullwidth-dwim，也绑在 C-c e F。"
  (interactive)
  (if (use-region-p)
      (call-interactively #'fullwidth-region)
    (call-interactively #'fullwidth-word)))

(defun self/halfwidth-dwim ()
  "有选区时把选区转半角，无选区时转光标处词。
交互命令：M-x self/halfwidth-dwim，也绑在 C-c e f。"
  (interactive)
  (if (use-region-p)
      (call-interactively #'halfwidth-region)
    (call-interactively #'halfwidth-word)))

;; 第二组：格式变换、选区扩展与多光标（含 `C-M-<down>' / `C-M-<up>' 的
;; GUI 键与 `C-c e' 前缀的终端备用键）。
;; · 格式变换：`C-c e q`（取消段落填充）、`C-c e r` / `R`（单文件/多文件
;;   正则替换预览，单文件替换可由 `C-S-h` 直达）、`C-c e F` / `f`
;;   （全半角转换）、`C-c e U` / `L` / `C`（大小写变换）。
;; · 选区与行操作：`C-c e k`（删除整行）、`C-c e D`（复制当前行/选区，
;;   `C-S-d' 的终端备用键）、`<backtab>'（反向缩进，见上方行级 DWIM）。
;; · GUI 下另可用 `M-S-<right>' / `M-S-<left>' 扩展/收缩选区。

(self/bind "C-c e q" #'unfill-paragraph "取消段落填充" "编辑变换")
(self/bind "C-c e r" #'replace-regexp-as-diff "正则替换预览" "编辑变换")
(self/bind "C-c e R" #'multi-file-replace-regexp-as-diff "多文件正则替换预览" "编辑变换")
(self/bind "C-c e C-w" #'unix-word-rubout "按词回杀" "编辑变换")
(self/bind "C-c e F" #'self/fullwidth-dwim "转全角" "编辑变换")
(self/bind "C-c e f" #'self/halfwidth-dwim "转半角" "编辑变换")
(self/bind "C-c e U" #'upcase-dwim "转大写" "编辑变换")
(self/bind "C-c e L" #'downcase-dwim "转小写" "编辑变换")
(self/bind "C-c e C" #'capitalize-dwim "首字母大写" "编辑变换")
(self/bind "C-c e k" #'kill-whole-line "删除整行" "编辑变换")
(self/bind "C-c e D" #'duplicate-dwim "复制当前行/选区" "编辑变换")
(self/bind "C-c e x" #'er/expand-region "扩展选区" "编辑变换")
(self/bind "C-c e X" #'er/contract-region "收缩选区" "编辑变换")
(self/bind "M-S-<right>" #'er/expand-region "扩展选区" "编辑变换")
(self/bind "M-S-<left>" #'er/contract-region "收缩选区" "编辑变换")
(self/bind "C-c e s" #'mc/skip-to-next-like-this "跳过下一个匹配" "编辑变换")
(self/bind "C-M-<down>" #'mc/mark-next-lines "下方行加光标" "编辑变换")
(self/bind "C-M-<up>" #'mc/mark-previous-lines "上方行加光标" "编辑变换")
(self/bind "C-c e <down>" #'mc/mark-next-lines "下方行加光标" "编辑变换")
(self/bind "C-c e <up>" #'mc/mark-previous-lines "上方行加光标" "编辑变换")

(defun self/mc-add-cursor-on-click (event)
  "在 EVENT 点击处追加一个 fake cursor（对齐 VSCode Alt+Click）。

`mc/create-fake-cursor-at-point' 只创建 overlay，下一条命令才随真实光标
同步执行，因此可连续多次点击铺出多个光标。
交互命令：以 \"e\" 接收鼠标事件，绑在 M-<down-mouse-1>。"
  (interactive "e")
  (require 'multiple-cursors)
  (mouse-set-point event)
  (mc/create-fake-cursor-at-point))

(self/bind "M-<down-mouse-1>" #'self/mc-add-cursor-on-click "点击加光标" "编辑变换")

;; ─── 通用 buffer 查询 ────────────────────────────────────────────
;;
;; 三面板总开关（self-keys-desktop）与终端面板都要按 mode 找已存在的
;; buffer，故这个「返回所有派生自 MODE 的存活 buffer」的小工具放这里，
;; 由两个调用方各自 declare-function。

(defun self--buffers-in-mode (mode)
  "返回所有派生自 MODE 的存活 buffer（`derived-mode-p'）。"
  (seq-filter (lambda (buf)
                (with-current-buffer buf (derived-mode-p mode)))
              (buffer-list)))

(provide 'self-editing)

;;; self-editing.el ends here
