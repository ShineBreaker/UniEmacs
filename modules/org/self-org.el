;;; self-org.el --- Org 栈：目录骨架、Capture 模板、现代排版与触屏操作面板 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable, full, ide
;; Requires: self-lib（路径常量）、self-keys（self/bind、self/declare-binding-group）、
;;           self-ui-touch + self-touch（仅 Android 分支用到：mode-line 按钮与键盘面板）
;; Packages: org-appear, org-modern, org-modern-indent, olivetti
;;
;; 移植自移动端配置（从桌面配置简化而来）并按桌面端的三段设计补齐：
;; 基础编辑体验设置 + 目录骨架 + Capture 模板装配 + org-appear /
;; org-modern / org-modern-indent 视觉现代化（GUI 下启用，tty 自动降级）+
;; Olivetti 沉浸写作 + 触屏 org 操作面板 + appt 议程提醒。
;; 双链笔记（org-roam）与知识库适配（agenote）按功能内聚拆到
;; self-roam.el 与 self-agenote.el。
;;
;; 版本约束（保留理由，版本 pin 本身属 core 的包后端）：
;; · org 用 Emacs 内置版：31.1 内置 org 9.8 满足全部依赖（org-roam
;;   要求 9.6+）；装 git 版 org 会因其 build 缺 org-loaddefs.el 且与
;;   内置版并存而版本错乱（Org version mismatch）。
;;
;; ─── 目录骨架 ──────────────────────────────────────────────────────
;;
;; 所有笔记统一存放在 `self:org-directory' 下（常量在 core/self-lib.el）：
;;   inbox.org   —— 灵感收件箱，快速记录未分类的零散想法；
;;   agenda/     —— 日程规划与任务清单（带具体执行日期的 TODO）；
;;   roam/       —— org-roam 长期双链笔记（见 self-roam.el）；
;;   experiences/—— 知识库经验卡片（见 self-agenote.el）；
;;   babel/、tangle/ —— literate 配置自身的求值与 tangle 产物落盘处。
;; 首次加载时自动补齐，缺失目录会让 agenda 列表与 capture 写入直接报错。
;;
;; ─── Capture 模板为什么长这样（原始设计的 noweb 双块机制）──────────
;;
;; 桌面端配置是 literate 的，一条模板原本拆成两块：`emacs-lisp` 块只持有按键、
;; 模板类型与目标文件，模板体以顶格 `<<模板名>>` 占位；紧随其后的 `#+name`
;; 文本块就是模板原文。这么拆是因为模板体里大量 `*`、`#+` 开头的 Org 语法行，
;; 直接写成 Lisp 字符串就得层层转义，拆成独立文本块后原文直书，只在行首以逗号
;; 转义（`,*`）保字面。本文件已把全部 noweb 引用**就地展开**成字面量模板。
;; 展开后模板体一律顶格——这是原引用行顶格带来的必然结果：noweb 会把引用行的
;; 行首前缀复制到展开后的每一行，而这里前缀为空。**不要给模板体加缩进**：首行
;; 一旦缩进，`* TODO %?` 就不再被 Org 解析为标题，capture 会写出无法折叠的
;; 普通段落。
;;
;; ─── 目标文件的三类求值时机（读模板时先分清目标属于哪一类）──────────
;;
;;   · 常量路径在**定义时**展开（inbox 用反引号 `,self:org-inbox-file`）；
;;   · agenda 与 roam 的目标传入**函数**，由 org-capture 在每次采集时调用
;;     （`self/org-capture--agenda-file' / `self/org-capture--roam-file'）——
;;     运行时目录可能刚被建好，且 agenda 的取值来源是 `org-agenda-files'
;;     而非写死的路径；
;;   · 需要人机交互的（Roam 标题、经验卡路径、经验卡类别）同样传函数，
;;     交互答案写入 `self/org-capture--*' 变量，模板体读走，finalize 钩子
;;     清空。三个环节闭环，缺一则属性退化为默认值（`未命名笔记` / `general`）。
;;     改模板前先确认没删掉这些变量引用。
;;
;; ─── 模板装配与加载顺序 ────────────────────────────────────────────
;;
;; `self/org--install-capture-templates' 走 setq 整表赋值（幂等），把本模块的
;; 通用模板放在前面、self-agenote 的经验卡模板接在后面——org-capture 的模板
;; 选择菜单按表序显示、用字母键选，顺序即语义。它在 org-capture 加载时跑一次；
;; self-agenote 在本模块之后加载，装配完自己那三张卡会**再调一次**同一个函数
;; 刷新整表（幂等，故不会重复累加）。
;;
;; ─── TTY 降级与异常防御（两处）─────────────────────────────────────
;;
;; · `self--skip-uncolorable-org-modern-border'：包在 `org-modern--update-faces'
;;   外面的 advice。背景色不可用时跳过 label 边框重算。org-modern-mode 由
;;   org-mode-hook 启用，重算抛出的 "Invalid face box" 会打断模式初始化并被上层
;;   报成 "File mode specification error"——不只是日志噪音；而 box 在终端本就不
;;   绘制。可用性以 default 背景值直接判定：xfaces.c 只接受 nil 或非空字符串作
;;   `:box` 的 `:color`，而 TTY 透明策略把背景清成符号 `unspecified` 会被判为非法；
;;   `org-modern--update-faces' 正用这个返回值当 label/habit 边框色。
;; · `self/org-modern--apply-display'：挂在 org-mode-hook 深度 -90，先于
;;   org-modern-mode 运行，使按 buffer 构建的星号缓存取自正确取值。org-modern 用
;;   内联 `:inverse-video` 画表格竖线、用 Nerd 字形替换星号，二者都是 font-lock
;;   阶段写入的内联 display/face 规格，晚于命名 face 的透明化，透明 TTY 上会变成
;;   实心/反色块。故 TTY 退回纯 ASCII 表格与 Unicode 子弹，前导星号交给
;;   org-indent-mode 隐藏；GUI 保留像素级细线与 Nerd 子弹。跨 GUI/TTY 共享的
;;   buffer 保留首次启用该 mode 的 frame 设置——org-modern 的缓存为 buffer-local，
;;   无法 per-frame。

;;; Code:

;; ─── 路径常量（core/self-lib.el 定义，这里只声明不赋值）────────────
;;
;; 带值声明会把 self-lib 的 defconst 顶掉（Emacs 的 defvar 遇到已绑定的变量
;; 就不改），所以一律只声明。
(defvar self:org-directory)
(defvar self:org-roam-directory)
(defvar self:org-inbox-file)
(defvar self:org-knowledge-directory)
(defvar self:cache-directory)

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))
(declare-function self/touch-show-keyboard "self-touch"
                  "触屏上拉起系统软键盘。")
(declare-function org-src-for-each-block "org-src" (function &optional lang))

;; Android 分支（org 操作面板 + appt 提醒）的定义整段包在
;; `(when self:android-p …)' 里：面板的父模式 self/touch-confirm-mode 与
;; self-touch 的键盘面板只在 portable 档加载，full 档引用它们是 void。
;; 代价是 byte-compile 时这一块被跳过（加载期条件为假），编译器看不到里面
;; 的定义，块内的交叉引用会误报「函数未定义」——故在此逐个显式声明。
(declare-function self/org-actions-mode "self-org")
(declare-function self/org-actions--run "self-org")
(declare-function self/org-actions-panel "self-org")
(declare-function self/org--mode-line-buttons "self-org")
(declare-function self/org--setup-mode-line "self-org")
(declare-function self/appt-notify "self-org")

;; 操作面板的源 buffer 标记：buffer-local，故在顶层声明 + 显式标记
;; buffer-local（`defvar-local' 展开出的 make-variable-buffer-local 必须
;; 出现在顶层，否则 byte-compile 报警）。
(defvar self/org-actions--source nil
  "唤出本操作面板的 org buffer（动作执行的目标），仅在面板 buffer 内有效。")
(make-variable-buffer-local 'self/org-actions--source)

(defvar org-capture-templates)  ; org-capture.el（模板在其加载后设置）
(declare-function org-agenda-files "org-agenda")

;; self-agenote 在本模块之后加载（见 Commentary「模板装配与加载顺序」），
;; 它把经验卡模板放进这个变量，本模块装配总表时接在通用模板之后。
(defvar self/agenote-capture-templates
  "agenote 经验卡 capture 模板表（由 self-agenote.el 赋值）。")

;; ─── 目录骨架 ──────────────────────────────────────────────────────

(defun self/org--ensure-directories ()
  "确保所有 Org 相关目录存在（骨架六目录，见 Commentary）。"
  (dolist (dir (list self:org-directory
                     (expand-file-name "agenda" self:org-directory)
                     self:org-roam-directory
                     self:org-knowledge-directory
                     (expand-file-name "babel" self:org-directory)
                     (expand-file-name "tangle" self:org-directory)))
    (unless (file-exists-p dir)
      (make-directory dir t))))

(defun self/org--ensure-agenda-file ()
  "确保 agenda 目录下至少有一个 org 文件（空目录时 agenda 无内容可列）。"
  (self/org--ensure-directories)
  (let ((dir (expand-file-name "agenda" self:org-directory)))
    (unless (directory-files dir nil "\\`[^.#].*\\.org\\'")
      (with-temp-file (expand-file-name "index.org" dir)
        (insert "#+title: 议程\n\n* 任务\n")))))

;; 推迟到空闲：Android 上 org 根在 FUSE 共享存储，启动期同步 stat/列目录会
;; 阻塞首屏；议程与 capture 入口各自已调用 ensure，用户抢先操作也不缺目录。
(run-with-idle-timer 1 nil #'self/org--ensure-agenda-file)

;; ─── Org 排版基础设置 ──────────────────────────────────────────────
;;
;; org 用 Emacs 内置版（版本理由见 Commentary），此处不装 git 版。
(use-package org
  :defer t
  :custom
  (org-directory self:org-directory)
  (org-agenda-files (list (expand-file-name "agenda" self:org-directory)))
  (org-agenda-window-setup 'current-window)  ; 单窗口议程
  (org-hide-emphasis-markers t)
  (org-startup-indented t)
  (org-hide-leading-stars t)
  (org-ellipsis "...")
  (org-auto-align-tags nil)
  (org-tags-column 0)
  (org-catch-invisible-edits 'show-and-error)
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  (org-pretty-entities t)
  (org-use-sub-superscripts '{})
  (org-cycle-separator-lines 2)
  (org-startup-folded 'overview)
  (org-blank-before-new-entry '((heading . t) (plain-list-item . auto)))
  (org-fontify-whole-heading-line t)
  (org-fontify-done-headline t)
  (org-fontify-quote-and-verse-blocks t)
  (org-src-fontify-natively t)
  (org-src-tab-acts-natively t)
  (org-src-preserve-indentation t)
  (org-src-window-setup 'current-window)  ; 手机单窗口
  (org-edit-src-content-indentation 0)
  (org-image-actual-width '(300)))  ; 内联图片显示宽度（px），真机可调

;; 链接预览只在图形 frame 里开：TTY 没有可点的链接，开着只是闪烁的噪声。
;; 判据用运行期的 `display-graphic-p'：org buffer 常在 GUI 与 TTY 之间共享
;; （emacsclient 在两种端口上各开一帧），加载期常量 `self:gui-p' 分不出来。
(defun self/org--toggle-link-previews ()
  "按当前 frame 是否图形化设置本 buffer 的链接预览开关。"
  (setq-local org-startup-with-link-previews (display-graphic-p)))

(add-hook 'org-mode-hook #'self/org--toggle-link-previews)

;; ─── Capture 模板 ──────────────────────────────────────────────────
;;
;; 模板表：ki 收件箱草稿、kd 带日期任务、ke 日程事件、kr Roam 长期笔记
;; （通用四条）+ kq 剪贴板速存、kp 协议分享（触屏两条，见下）。
;; 移动端原有的 kt（不带日期的 agenda 任务）被 kd 覆盖，故不再保留。
;;
;; 全部模板体已把桌面端配置的 `<<...>>' noweb 引用就地展开：
;;   org-capture-tpl-inbox  → 下方 self:org-capture-tpl-inbox
;;   org-capture-tpl-roam   → 下方 self:org-capture-tpl-roam
;;   org-capture-tpl-task-date / org-capture-tpl-event
;;                            → 下方 self/org--install-capture-templates
;;                              里的 kd / ke 两条
;;   org-capture-tpl-experience-head / note / mistake / ascended
;;                            → self-agenote.el 的三条经验卡模板

(defvar self/org-capture--roam-title nil
  "本次 capture 的 Roam 笔记标题，由目标文件函数写入、模板体读走。")

;; ki：最小阻力收集，一句话 TODO + CREATED 时间戳，留待 inbox 分流。
;; 目标文件是常量路径，故用反引号在定义时展开。
(defconst self:org-capture-tpl-inbox
  `("ki" "Inbox 草稿" entry
    (file ,self:org-inbox-file)
    "
* TODO %?
:PROPERTIES:
:CREATED: %U
:END:
%i
")
  "一句话草稿、待分流事项。")

;; kr：文件级条目，标题取自交互输入，ID 由 org-id-new 生成，落入 roam 目录。
;; 模板值不以换行结尾，故末尾不补 \n。
(defconst self:org-capture-tpl-roam
  '("kr" "Roam 长期笔记" plain
    (file self/org-capture--roam-file)
    "
#+title: %(or self/org-capture--roam-title \"未命名笔记\")
:PROPERTIES:
:ID:      %(org-id-new)
:CREATED: %U
:END:

%?")
  "长期笔记与双向关联知识。")

;; 隐藏模板（抓笔记面板过滤）：不弹 buffer 不等输入，直接完成。
(defconst self:org-capture-tpl-clip
  '("kq" "剪贴板速存" entry
    (file self:org-inbox-file)
    "* %(self/org-capture--clip-heading)
:PROPERTIES:
:CREATED: %U
:END:
%(self/org-capture--clip-body)
"
    :prepend t :immediate-finish t)
  "剪贴板速存：一次点按把剪贴板全文写进 inbox。")

;; org-protocol 分享入库：描述/链接/正文由协议参数填充。
(defconst self:org-capture-tpl-protocol
  '("kp" "协议分享" entry
    (file self:org-inbox-file)
    "* %(self/org-capture--protocol-heading)
:PROPERTIES:
:CREATED: %U
:END:
%:link

%:initial
"
    :prepend t :immediate-finish t)
  "org-protocol://capture 分享入库模板。")

(defun self/org-capture--agenda-file ()
  "返回本次 capture 的目标 agenda 文件（取 `org-agenda-files' 首项）。
每次采集现取：目录与文件都可能在本次会话中才被建好/改名。"
  (self/org--ensure-directories)
  (car (org-agenda-files)))

(defun self/org-capture--roam-file ()
  "返回本次长期笔记的 Roam 文件路径（文件名用当前时间戳）。
交互读到的标题写入 `self/org-capture--roam-title' 供模板体取值。
Android 上先拉起软键盘：触屏没有物理键盘，read-string 不主动弹键盘
等于让用户对着一个不存在的输入界面打字。"
  (self/org--ensure-directories)
  (when self:android-p
    (self/touch-show-keyboard))
  (setq self/org-capture--roam-title
        (read-string "长期笔记标题: "))
  (expand-file-name
   (format "%s.org" (format-time-string "%Y%m%d-%H%M%S"))
   self:org-roam-directory))

(defun self/org-capture--clear-state ()
  "`org-capture-after-finalize-hook' 回调：清理本次 capture 的临时状态。"
  (setq self/org-capture--roam-title nil))

(defun self/org--install-capture-templates ()
  "把本模块与 self-agenote 的模板装配进 `org-capture-templates'。
通用模板在前、经验卡模板在后，org-capture 的模板选择菜单按此顺序显示。
整表赋值（而非逐条 add-to-list）故本函数幂等：self-agenote 在本模块之后
加载，装配完自己的三张卡会再调一次刷新整表，顺序依旧、条目不重复。"
  (self/org--ensure-directories)
  (setq org-capture-templates
        (append
         (list self:org-capture-tpl-inbox
               ;; kd / ke 的目标在每次采集时求值（目录可能刚被建好），
               ;; 故传函数而非定义时的常量路径。
               '("kd" "带日期任务 (agenda)" entry
                 (file self/org-capture--agenda-file)
                 "
* TODO %?
SCHEDULED: %^t
:PROPERTIES:
:CREATED: %U
:END:
%i
")
               '("ke" "日程事件 (agenda)" entry
                 (file self/org-capture--agenda-file)
                 "
* %?
:PROPERTIES:
:CREATED: %U
:END:
%i
")
               self:org-capture-tpl-roam
               self:org-capture-tpl-clip
               self:org-capture-tpl-protocol)
         self/agenote-capture-templates))
  (add-hook 'org-capture-after-finalize-hook
            #'self/org-capture--clear-state))

(with-eval-after-load 'org-capture
  (self/org--install-capture-templates))

;; ─── 剪贴板速存：一键入库（mode-line「速」钮 / 工具栏），不弹模板面板 ──

(defvar self/org-capture--clip-text nil
  "本次速存的剪贴板内容（模板函数在动态作用域内读取）。")

(defun self/clipboard-content ()
  "系统剪贴板文本（GUI selection 不可用时回退 kill-ring 头）。"
  (or (ignore-errors (gui-get-selection 'CLIPBOARD 'STRING))
      (car kill-ring)))

(defun self/org-capture--clip-heading ()
  "速存条目标题：剪贴板首个非空行截 30 列。"
  (let* ((text (string-trim (or self/org-capture--clip-text "")))
         (head (truncate-string-to-width
                (or (car (split-string text "[\r\n]+")) "")
                30 nil nil "…")))
    (if (string-empty-p head) "（剪贴板内容）" head)))

(defun self/org-capture--clip-body ()
  "速存条目正文：剪贴板全文。"
  (or self/org-capture--clip-text ""))

(defun self/inbox-quick-capture ()
  "剪贴板一键速存为 inbox TODO 条目。
交互命令：M-x self/inbox-quick-capture；剪贴板为空时只报消息不动文件。"
  (interactive)
  (let ((clip (self/clipboard-content)))
    (if (or (null clip) (string-empty-p (string-trim clip)))
        (message "剪贴板为空，未速存")
      (require 'org-capture)
      (let ((self/org-capture--clip-text clip))
        (org-capture nil "kq")
        (message "已速存：%s" (self/org-capture--clip-heading))))))

;; ─── org-protocol：其他 App 分享入库（org-protocol://capture） ─────
;; Android 端口把 emacsclient wrapper 注册为 org-protocol handler，
;; 链接经 server-visit-files 转交 org-protocol-capture（server 见
;; self-misc.el）。默认模板必须显式指定：nil 会让 org-capture 弹
;; org-mks *Org Select* 键盘面板，触屏不可选（见 self-dashboard.el）。

(declare-function org-capture-get "org-capture")
(defvar org-protocol-default-template-key)

(defun self/org-capture--protocol-heading ()
  "协议分享条目标题：链接描述为空时取正文首行截 30 列。"
  (let ((desc (org-capture-get :description)))
    (if (and desc (not (string-empty-p (string-trim desc))))
        desc
      (let ((head (truncate-string-to-width
                   (or (car (split-string
                             (or (org-capture-get :initial) "") "[\r\n]+"))
                       "")
                   30 nil nil "…")))
        (if (string-empty-p (string-trim head)) "（分享内容）" head)))))

(when self:android-p
  ;; 空闲加载不占启动；server 侧 advice 在 require 后即刻生效
  (run-with-idle-timer
   5 nil (lambda ()
           (require 'org-protocol)
           (setq org-protocol-default-template-key "kp"))))

;; ─── 现代排版与标记展开 ────────────────────────────────────────────
;; org-appear：平时隐藏强调标记（粗体、下划线、代码字面量），光标移入时
;; 自动展开底层标记，兼顾排版美观与编辑便利。
(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :custom
  (org-appear-autoemphasis t)
  (org-appear-autolinks t)
  (org-appear-autosubmarkers t)
  (org-appear-autoentities t))

;; org-modern：把默认朴素的标题星号、细线表格、复选框和标签美化成
;; 现代化外观。
(use-package org-modern
  :hook (org-mode . org-modern-mode)
  :custom
  (org-modern-label-border 0.12)
  (org-modern-star 'replace)
  (org-modern-replace-stars '( "" "" "󰜋" "󰜌" "" "" ""))
  (org-modern-list
   '((?- . "")
     (?* . "")
     (?+ . "")))
  (org-modern-hide-stars 'leading)
  (org-modern-table t)
  (org-modern-table-vertical 2)
  (org-modern-table-horizontal 0.12)
  (org-modern-keyword t)
  (org-modern-todo t)
  (org-modern-tag t)
  (org-modern-block-name t)
  (org-modern-block-fringe 4))

;; 机制说明见 Commentary「TTY 降级与异常防御」。
;; advice-add 包住 org-modern 的 face 重算：背景色不可用时直接跳过，
;; 否则交给原函数。
(defun self--skip-uncolorable-org-modern-border (orig &rest args)
  "背景色不可用时跳过 org-modern 的 label 边框重算，否则交给 ORIG。
ORIG 与 ARGS 是被 advice 的 `org-modern--update-faces' 及其参数。"
  (let ((bg (face-attribute 'default :background nil t)))
    (when (or (null bg) (stringp bg))
      (apply orig args))))

(with-eval-after-load 'org-modern
  (advice-add 'org-modern--update-faces :around
              #'self--skip-uncolorable-org-modern-border))

;; 深度 -90：必须早于 org-modern-mode（org-mode-hook 默认深度）运行，
;; 让 org-modern 按 buffer 构建的星号缓存取到降级后的取值。
(defun self/org-modern--apply-display ()
  "按当前 frame 类型降级 `org-modern' 的星号与表格渲染。
TTY 退回 ASCII 表格与 Unicode 子弹；GUI 保留像素细线与 Nerd 子弹。
`display-color-cells' 为 8 是「单色终端」判据：再低就只剩 ASCII 了。"
  (when (and (not noninteractive)
             (not (display-graphic-p))
             (>= (display-color-cells) 8))
    (setq-local org-modern-table nil
                org-modern-table-vertical nil
                org-modern-table-horizontal nil
                org-modern-star 'replace
                org-modern-hide-stars 'leading)))

(add-hook 'org-mode-hook #'self/org-modern--apply-display -90)

(use-package org-modern-indent
  :defer t
  :commands (org-modern-indent-mode)
  :config
  ;; 默认用的是 default face，在透明 TTY 上会露出边框
  (face-spec-set 'org-modern-indent-bracket-line '((t :inherit (shadow)))))

(add-hook 'org-mode-hook #'org-modern-indent-mode 90)

;; ─── 沉浸写作（Olivetti） ───────────────────────────────────────────
;; C-c o o 开启 Olivetti 模式，把文本版心居中定宽，屏蔽行号等杂扰。
(use-package olivetti
  :defer t
  :commands (olivetti-mode)
  :custom
  (olivetti-body-width 100))

;; ─── 键位（C-c o 前缀下属本模块的部分） ────────────────────────────
;; 这几个 Org 命令上游没有 autoload 标记，此处全局绑定需要手工声明，
;; 否则在 Org 尚未加载的会话里按键会报 commandp 错误。
(autoload 'org-insert-structure-template "org" nil t)
(autoload 'org-clock-in "org-clock" nil t)
(autoload 'org-clock-out "org-clock" nil t)
(autoload 'org-clock-goto "org-clock" nil t)

(defun self/format-org-src-blocks ()
  "重新格式化当前 buffer 里全部 Org 代码块。
full 档走 Apheleia 的异步格式化协议（`org-src-blocks' formatter 由
self-prog 注册）；没有 Apheleia 的环境（portable 等）退回按各语言
缩进规则 `indent-region'。`org-src-for-each-block' 跳过 begin/end
标记行、只遍历块体，故缩进不会污染结构行。
交互命令：M-x self/format-org-src-blocks，也绑在 C-c o f。"
  (interactive)
  (if (fboundp 'apheleia-format-buffer)
      (apheleia-format-buffer 'org-src-blocks)
    (save-restriction
      (org-src-for-each-block
       (lambda (_lang start end)
         (indent-region start end))))))

(self/bind "C-c o a" #'org-agenda "议程视图" "Org 与知识库")
(self/bind "C-c o f" #'self/format-org-src-blocks "格式化全部代码块" "Org 与知识库")
(self/bind "C-c o i" #'org-insert-structure-template "插入代码块" "Org 与知识库")
(self/bind "C-c o o" #'olivetti-mode "专注写作" "Org 与知识库")

(self/declare-binding-group "C-c o c" "Capture 与计时")
(self/bind "C-c o c c" #'org-capture "统一 Capture 入口" "Org 与知识库")
(self/bind "C-c o c i" #'org-clock-in "开始计时" "Org 与知识库")
(self/bind "C-c o c o" #'org-clock-out "停止计时" "Org 与知识库")
(self/bind "C-c o c g" #'org-clock-goto "跳到当前计时" "Org 与知识库")

;; ─── 触屏：org 操作面板与议程提醒（Android 分支）────────────────────
;; org 高频动作（TODO/排程/折叠/移动/clock）在纯触屏下无键位可达，
;; 复用抓笔记面板模式集中触达。面板同窗替换 org buffer，唤出时记录
;; 源 buffer；动作埋掉面板显式切回再执行命令（不靠 buffer-list 顺序）。
;;
;; 整块按平台守卫：这两节依赖 self-ui-touch 的 mode-line 按钮表与
;; self-touch 的键盘面板，都是触屏专属设施；桌面档不加载那两个模块。

(when self:android-p
  (declare-function self/mode-line--button "self-ui-touch")
  (declare-function self/mode-line--add-local-buttons "self-ui-touch")
  (declare-function org-todo "org")
  (declare-function org-schedule "org")
  (declare-function org-deadline "org")
  (declare-function org-insert-heading "org")
  (declare-function org-metaup "org")
  (declare-function org-metadown "org")
  (declare-function org-metaleft "org")
  (declare-function org-metaright "org")
  (declare-function org-cycle "org")
  (declare-function org-cycle-global "org")
  (declare-function org-set-tags-command "org")
  (declare-function org-insert-link "org")
  (declare-function consult-org-heading "consult")
  (declare-function self/touch-confirm-mode "self-touch")
  (defvar self/expreg--buttons)  ; self-touch（「选」钮与 org 共用规格）

  ;; 面板键图/键盘抑制与确认面板一致，直接派生复用（self-touch 先加载）
  (define-derived-mode self/org-actions-mode self/touch-confirm-mode
    "Org操作" "org 上下文操作面板。")

  (defconst self/org-actions--layout
    '((("TODO 循环" . org-todo) ("排程" . org-schedule) ("截止" . org-deadline))
      (("插同级标题" . org-insert-heading)
       ("上移" . org-metaup) ("下移" . org-metadown))
      (("升级" . org-metaleft) ("降级" . org-metaright)
       ("折叠/展开" . org-cycle))
      (("全局折叠" . org-cycle-global))
      (("跳转标题" . consult-org-heading)
       ("加标签" . org-set-tags-command) ("插链接" . org-insert-link)))
    "操作面板按钮矩阵：行 →（标签 . 命令）。")

  (defun self/org-actions--run (command)
    "返回面板钮 action：埋掉面板切回源 org buffer，再交互执行 COMMAND。"
    (lambda (&rest _)
      (let ((src self/org-actions--source))
        (kill-buffer)
        (when (buffer-live-p src)
          (switch-to-buffer src))
        (call-interactively command))))

  (defun self/org-actions-panel ()
    "弹 org 上下文操作面板（mode-line「作」钮）。
交互命令：M-x self/org-actions-panel。"
    (interactive)
    (let ((src (current-buffer)))
      (switch-to-buffer (get-buffer-create "*Org 操作*"))
      (self/org-actions-mode)
      (setq self/org-actions--source src))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (propertize "  Org 操作\n\n" 'face 'bold))
      (dolist (row self/org-actions--layout)
        (insert "  ")
        (dolist (cell row)
          (widget-create 'item
                         :tag (concat " " (car cell) " ")
                         :action (self/org-actions--run (cdr cell))
                         :mouse-face 'highlight
                         :button-prefix " " :button-suffix " "
                         :format "%[%t%]")
          (insert "  "))
        (insert "\n\n"))
      (goto-char (point-min))))

  (defconst self/org--mode-line-buttons
    `(("" "作" "Org 操作面板（TODO/排程/折叠/移动…）"
       self/org-actions-panel)
      ,@self/expreg--buttons)
    "org-mode mode-line 局部钮表：(NF 字形 tty 回退 帮助 命令)。
「选」钮规格复用 self-touch 的 expreg 钮表（org 经 outline←text 链
也会跑 text-mode-hook，那里对 org 跳过防重复）。")

  (defun self/org--mode-line-buttons ()
    "org 钮串。"
    (mapconcat #'self/mode-line--button self/org--mode-line-buttons nil))

  (defun self/org--setup-mode-line ()
    "org buffer：右端钮组前插入「作」「选」钮。"
    (self/mode-line--add-local-buttons #'self/org--mode-line-buttons))

  (add-hook 'org-mode-hook #'self/org--setup-mode-line)

  ;; ─── appt 议程提醒：Android 走系统通知 ──────────────────────────
  ;; 常规 App 语义：到点弹系统通知栏（Emacs 前台/后台都触达，点击回
  ;; Emacs），而非只在 frame 内弹窗。进程被杀则提醒随之消失——端口靠
  ;; 常驻通知保命，存活率尚可但不保证。
  (declare-function android-notifications-notify "androidselect.c")
  (declare-function appt-activate "appt")
  (declare-function appt-disp-window "appt")
  (declare-function org-agenda-to-appt "org-agenda")
  ;; appt-disp-window-function 的实参签名是
  ;; (TIME-LEFT MIN-TO-APP NEW-TIME MSG)，键名写清楚比按位置记牢更省心。
  (defvar appt-disp-window-function)

  (defun self/appt-notify (min-to-app new-time msg)
    "appt 提醒出口：Android 发系统通知，其余平台回退内置弹窗。
MIN-TO-APP/NEW-TIME/MSG 任一可为 list（多条议程同时到点）。"
    (if (fboundp 'android-notifications-notify)
        (android-notifications-notify
         :title "议程提醒"
         :body (format "%s 分钟后：%s"
                       (if (listp min-to-app)
                           (mapconcat #'identity min-to-app ", ")
                         min-to-app)
                       (if (listp msg) (mapconcat #'identity msg "\n") msg))
         :group "Org Agenda"
         :urgency 'normal)
      (appt-disp-window min-to-app new-time msg)))

  ;; agenda 加载后接管提醒出口并建首次提醒表；org-agenda-to-appt 挂在
  ;; finalize 上，agenda 每次刷新重建（deadline/scheduled/timestamp）
  (with-eval-after-load 'org-agenda
    (require 'appt)
    (setq appt-disp-window-function #'self/appt-notify)
    (appt-activate 1)
    (add-hook 'org-agenda-finalize-hook #'org-agenda-to-appt)
    (org-agenda-to-appt))
  ;; 不挂绝对计时兜底：org-agenda 加载重（数秒），绝对计时会抢占
  ;; 输入；提醒是尽力而为的增强，让位交互流畅度
  (run-with-idle-timer 90 nil (lambda () (require 'org-agenda))))

(provide 'self-org)
;;; self-org.el ends here
