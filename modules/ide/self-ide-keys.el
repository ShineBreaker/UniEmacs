;;; self-ide-keys.el --- IDE 档键位：IntelliJ IDEA Windows 默认键图 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-keys、self-keys-desktop、self-ide-panel（`self/ide--rebind'）、
;;           self-editing、self-prog、self-terminal、self-ide-completion
;; Packages: consult, magit, eglot, dape, apheleia, multiple-cursors,
;;           expand-region, eldoc-box
;;
;; 键图选用 IntelliJ IDEA 的 Windows / Linux 默认键图（两套相同；macOS
;; 那套把 Ctrl 换成 Command，和本仓库桌面档的 Ctrl 习惯对不上）。
;; 本文件必须在 self-keys-desktop、self-ide-panel、self-ide-completion
;; 之后加载：那些文件先声明或改过一批键，这里再用 `self/ide--rebind'
;; 收成 IDEA 的日常操作。standard 档不加载本文件。
;;
;; 做不到、因而没有装成同键的几件事：
;;
;;   · 双击 Shift（Search Everywhere）。Shift 是修饰键，Emacs 收不到
;;     「按下再松开」。替代键是 Ctrl+Shift+P（`self/ide-search-everywhere'，
;;     缓冲 / 文件 / 命令）。只搜命令仍是 Ctrl+Shift+A。
;;   · Ctrl+G 跳行。C-g 是 Emacs 的 keyboard-quit，让出会使所有「取消」
;;     失效。跳行用 Ctrl+Shift+G，原来的 M-g g 也还在。
;;   · Ctrl+C / Ctrl+X 始终当复制 / 剪切。它们是 Emacs 的前缀，C-c c、
;;     C-x C-f 这一整棵树都挂在上面。cua-mode 的规则是：有选区时
;;     Ctrl+C / Ctrl+X 复制 / 剪切，没有选区时仍是前缀；按住约 0.2 秒
;;     也会回到前缀。无选区复制当前行用原来的 Ctrl+Shift+C。
;;   · Ctrl+H 类型层次。本档 C-h 是左移（帮助在 <f1>），没有可靠的
;;     跨语言类型层次命令。
;;   · 左侧竖排工具窗按钮。Emacs 没有这条窗口原语，按钮在顶栏，
;;     快捷键仍是 Alt+1 … Alt+9、Alt+0、Alt+F12。
;;
;; 迷你缓冲里 C-a / C-e / C-f / C-n 等改回行编辑，避免在补全框里
;; 触发「跳转到类」。vertico / corfu 自己的 minor-mode 键优先于这里。

;;; Code:

(require 'cua-base)
(require 'subr-x)

(defvar self:binding-spec)
(defvar recentf-list)
(defvar compile-command)
(defvar eglot--managed-mode)
(defvar cua-enable-cua-keys)
(defvar cua-keep-region-after-copy)
(defvar cua-prefix-override-inhibit-delay)

(declare-function self/ide--rebind "self-ide-panel"
                  (key command description &optional group))
(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/ide-panel-toggle "self-ide-panel")
(declare-function self/ide-panel-reveal "self-ide-panel")
(declare-function self/open-terminal "self-terminal" (&optional arg))
(declare-function self--terminal-existing-buffer "self-terminal")
(declare-function self/flymake-list-errors-dwim "self-prog")
(declare-function self/isearch-forward-dwim "self-completion")
(declare-function self/code-move-line-up "self-editing")
(declare-function self/code-move-line-down "self-editing")
(declare-function self/open-line-below "self-editing")
(declare-function self/rename-dwim "self-editing")
(declare-function self/mc-add-cursor-on-click "self-editing" (event))
(declare-function self/tabs-next "self-tabline")
(declare-function self/tabs-previous "self-tabline")
(declare-function self/workspace-symbol "self-prog")
(declare-function consult-recent-file "consult")
(declare-function consult-imenu "consult")
(declare-function consult-imenu-multi "consult")
(declare-function consult-ripgrep "consult" (&optional dir initial))
(declare-function consult-global-mark "consult")
(declare-function project-files "project" (project &optional dirs))
(declare-function project-root "project" (project))
(declare-function project-current "project" (&optional maybe-prompt directory))
(declare-function eglot-code-actions "eglot" (&optional beg end))
(declare-function eglot-code-action-organize-imports "eglot" (&optional beg end))
(declare-function eldoc-print-current-symbol-info "eldoc" ())
(declare-function eldoc-box-help-at-point "eldoc-box")
(declare-function apheleia-format-buffer "apheleia" (&optional formatter))
(declare-function magit-commit "magit-commit" (&optional args))
(declare-function magit-pull-from-upstream "magit-pull" (&optional args))
(declare-function magit-pull "magit-pull" (&optional args))
(declare-function magit-push-current-to-pushremote "magit-push" (&optional args))
(declare-function magit-push "magit-push" (&optional args))
(declare-function magit-status "magit-status" (&optional directory cache))
(defvar dape-active-mode)
(declare-function dape "dape" (&optional config))
(declare-function dape-continue "dape" (conn))
(declare-function dape-next "dape" (conn))
(declare-function dape-step-in "dape" (conn))
(declare-function dape-step-out "dape" (conn))
(declare-function dape-quit "dape" ())
(declare-function dape-breakpoint-toggle "dape" ())
(declare-function recompile "compile" (&optional edit-command))
(declare-function kill-compilation "compile" ())
(declare-function project-compile "project" ())
(declare-function mc/mark-next-like-this "multiple-cursors" (arg))
(declare-function mc/mark-all-like-this "multiple-cursors" (&optional arg))
(declare-function mc/unmark-next-like-this "multiple-cursors" ())
(declare-function mc/mark-previous-like-this "multiple-cursors" (arg))

(defconst self:ide-keymap-group "IDEA 键位"
  "本文件声明的键在帮助页里的分组名。")

(defvar self/ide--last-tool #'self/ide-tool-project
  "F12 要再次调用的工具窗命令。每个工具窗命令在执行前写上自己。")

(defvar self/ide--command-rows nil
  "Search Everywhere 的命令候选缓存。每条是 (显示串 . (command . 符号))。")

;; ─── 编辑与导航 ──────────────────────────────────────────────────

(defun self/ide-save-all ()
  "保存全部已修改的文件缓冲，不逐个询问（IDEA Ctrl+S）。
只保存当前文件用 `C-x C-s'。
交互命令：M-x self/ide-save-all，也绑在 C-s。"
  (interactive)
  (save-some-buffers t))

(defun self/ide-comment-block (beg end)
  "切换 BEG 到 END 的块注释（IDEA Ctrl+Shift+/）。
无选区时作用于当前行。语言没有块注释结尾符时退回逐行注释。
交互命令：M-x self/ide-comment-block，也绑在 C-S-/。"
  (interactive
   (if (use-region-p)
       (list (region-beginning) (region-end))
     (list (line-beginning-position) (line-end-position))))
  (let ((comment-style
         (if (and (stringp comment-end) (not (string-blank-p comment-end)))
             'extra-line
           'indent)))
    (comment-or-uncomment-region beg end)))

(defun self/ide-reformat ()
  "重新格式化当前缓冲（IDEA Ctrl+Alt+L）。
有 apheleia 时按 major mode 选格式化器，否则缩进整个缓冲。
交互命令：M-x self/ide-reformat，也绑在 C-M-l。"
  (interactive)
  (if (fboundp 'apheleia-format-buffer)
      (call-interactively #'apheleia-format-buffer)
    (indent-region (point-min) (point-max))))

(defun self/ide-optimize-imports ()
  "优化导入（IDEA Ctrl+Alt+O）。当前缓冲需由 Eglot 托管。
交互命令：M-x self/ide-optimize-imports，也绑在 C-M-o。"
  (interactive)
  (cond
   ((not (bound-and-true-p eglot--managed-mode))
    (user-error "当前缓冲没有语言服务器，无法优化导入"))
   ((not (fboundp 'eglot-code-action-organize-imports))
    (user-error "当前 Eglot 没有「优化导入」这个代码操作"))
   (t (call-interactively #'eglot-code-action-organize-imports))))

(defun self/ide-parameter-info ()
  "显示光标处的参数信息（IDEA Ctrl+P）。
装了 eldoc-box 时用浮窗，否则写到 echo area。
交互命令：M-x self/ide-parameter-info，也绑在 C-p。"
  (interactive)
  (cond
   ((fboundp 'eldoc-box-help-at-point) (eldoc-box-help-at-point))
   ((fboundp 'eldoc-print-current-symbol-info)
    (eldoc-print-current-symbol-info))
   (t (message "没有可用的参数信息"))))

(defun self/ide-quick-documentation ()
  "打开光标符号的快速文档（IDEA Ctrl+Q）。
交互命令：M-x self/ide-quick-documentation，也绑在 C-q。"
  (interactive)
  (eldoc-doc-buffer))

(defun self/ide-intention ()
  "显示意图操作（IDEA Alt+Enter）。交给 Eglot 的 code action。
交互命令：M-x self/ide-intention，也绑在 M-<return>。
Org 缓冲里 Alt+Enter 仍是 org 自己的标题命令，那边用 C-. 。"
  (interactive)
  (call-interactively #'eglot-code-actions))

(defun self/ide-goto-class ()
  "按项目内的定义名跳转（IDEA Ctrl+N Go to Class）。
多语言没有单独的「类」索引，用 `consult-imenu-multi' 搜项目里的 imenu。
交互命令：M-x self/ide-goto-class，也绑在 C-n。"
  (interactive)
  (consult-imenu-multi))

(defun self/ide-refresh ()
  "重新从磁盘读入当前文件（IDEA 项目视图里的 F5）。
交互命令：M-x self/ide-refresh，也绑在 <f5>。"
  (interactive)
  (if buffer-file-name
      (revert-buffer t t t)
    (message "当前缓冲没有文件可刷新")))

(defun self/ide--mark-symbol-if-needed ()
  "没有选区时，把光标所在符号设成选区。没有符号则什么都不做。"
  (unless (use-region-p)
    (let ((bounds (bounds-of-thing-at-point 'symbol)))
      (when bounds
        (goto-char (car bounds))
        (set-mark (cdr bounds))))))

(defun self/ide-select-next-occurrence ()
  "把下一处相同文本加入多光标（IDEA Alt+J）。
无选区时先取当前符号。
交互命令：M-x self/ide-select-next-occurrence，也绑在 M-j。"
  (interactive)
  (require 'multiple-cursors)
  (self/ide--mark-symbol-if-needed)
  (mc/mark-next-like-this 1))

(defun self/ide-unselect-occurrence ()
  "取消最近加入的一处多光标（IDEA Alt+Shift+J）。
交互命令：M-x self/ide-unselect-occurrence，也绑在 M-S-j。"
  (interactive)
  (require 'multiple-cursors)
  (if (fboundp 'mc/unmark-next-like-this)
      (mc/unmark-next-like-this)
    (mc/mark-previous-like-this 1)))

(defun self/ide-select-all-occurrences ()
  "把所有相同文本都收成多光标（IDEA Ctrl+Alt+Shift+J）。
交互命令：M-x self/ide-select-all-occurrences，也绑在 C-M-S-j。"
  (interactive)
  (require 'multiple-cursors)
  (self/ide--mark-symbol-if-needed)
  (mc/mark-all-like-this))

;; ─── 运行、调试、Git ─────────────────────────────────────────────

(defun self/ide--call-dape (command idle-message)
  "调用 dape 命令 COMMAND。没有活动会话时提示 IDLE-MESSAGE。
会话在不在看 `dape-active-mode'：dape 没有稳定的公开「当前连接」函数，
这个 minor mode 在最后一条会话结束时关掉。"
  (unless (require 'dape nil t)
    (user-error "dape 未加载"))
  (if (bound-and-true-p dape-active-mode)
      (call-interactively command)
    (user-error "%s" idle-message)))

(defun self/ide-run ()
  "运行项目（IDEA Shift+F10）。
已经有过编译命令就 `recompile'，否则询问 `project-compile'。
交互命令：M-x self/ide-run，也绑在 S-<f10>。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-run)
  (if (and (bound-and-true-p compile-command) (get-buffer "*compilation*"))
      (recompile)
    (call-interactively #'project-compile)))

(defun self/ide-build ()
  "构建项目（IDEA Ctrl+F9）。总是询问编译命令。
交互命令：M-x self/ide-build，也绑在 C-<f9>。"
  (interactive)
  (call-interactively #'project-compile))

(defun self/ide-debug ()
  "开始调试；已有会话则继续（IDEA Shift+F9）。
交互命令：M-x self/ide-debug，也绑在 S-<f9>。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-debug)
  (unless (require 'dape nil t)
    (user-error "dape 未加载"))
  (if (and (bound-and-true-p dape-active-mode)
           (fboundp 'dape-continue))
      (call-interactively #'dape-continue)
    (call-interactively #'dape)))

(defun self/ide-resume ()
  "继续当前调试（IDEA F9）。没有会话时不新开一个。
交互命令：M-x self/ide-resume，也绑在 <f9>。"
  (interactive)
  (self/ide--call-dape #'dape-continue "没有调试会话可继续"))

(defun self/ide-step-over ()
  "单步跳过（IDEA F8）。
交互命令：M-x self/ide-step-over，也绑在 <f8>。"
  (interactive)
  (self/ide--call-dape #'dape-next "没有调试会话"))

(defun self/ide-step-into ()
  "单步进入（IDEA F7）。
交互命令：M-x self/ide-step-into，也绑在 <f7>。"
  (interactive)
  (self/ide--call-dape #'dape-step-in "没有调试会话"))

(defun self/ide-step-out ()
  "单步跳出（IDEA Shift+F8）。
交互命令：M-x self/ide-step-out，也绑在 S-<f8>。"
  (interactive)
  (self/ide--call-dape #'dape-step-out "没有调试会话"))

(defun self/ide-stop ()
  "停止调试或编译（IDEA Ctrl+F2）。
交互命令：M-x self/ide-stop，也绑在 C-<f2>。"
  (interactive)
  (cond
   ((and (require 'dape nil t)
         (bound-and-true-p dape-active-mode)
         (fboundp 'dape-quit))
    (call-interactively #'dape-quit))
   ((get-buffer-process "*compilation*")
    (kill-compilation))
   (t (user-error "没有正在运行的构建或调试"))))

(defun self/ide-toggle-breakpoint ()
  "在当前行切换断点（IDEA Ctrl+F8）。
交互命令：M-x self/ide-toggle-breakpoint，也绑在 C-<f8>。"
  (interactive)
  (unless (require 'dape nil t)
    (user-error "dape 未加载"))
  (call-interactively #'dape-breakpoint-toggle))

(defun self/ide--require-magit ()
  "加载 magit。失败时用中文说明，而不是 void-function。"
  (unless (require 'magit nil t)
    (user-error "magit 未加载")))

(defun self/ide-commit ()
  "打开 Git 提交（IDEA Ctrl+K）。
交互命令：M-x self/ide-commit，也绑在 C-k 与 Alt+0。"
  (interactive)
  (self/ide--require-magit)
  (call-interactively #'magit-commit))

(defun self/ide-update-project ()
  "从上游更新当前仓库（IDEA Ctrl+T Update Project）。
交互命令：M-x self/ide-update-project，也绑在 C-t。"
  (interactive)
  (self/ide--require-magit)
  (cond
   ((fboundp 'magit-pull-from-upstream)
    (call-interactively #'magit-pull-from-upstream))
   ((fboundp 'magit-pull)
    (call-interactively #'magit-pull))
   (t (user-error "magit 未加载"))))

(defun self/ide-push ()
  "推送当前分支（IDEA Ctrl+Shift+K）。
优先推到 pushRemote；没有这条命令时打开 Magit 的推送菜单。
交互命令：M-x self/ide-push，也绑在 C-S-k。"
  (interactive)
  (self/ide--require-magit)
  (cond
   ((fboundp 'magit-push-current-to-pushremote)
    (call-interactively #'magit-push-current-to-pushremote))
   ((fboundp 'magit-push)
    (call-interactively #'magit-push))
   (t (user-error "magit 未加载"))))

(defun self/ide-settings ()
  "打开 IDE 设置（IDEA Ctrl+Alt+S）。
打开 `self-ide' 定制组。仓库里的配置文件仍用 C-, 。
交互命令：M-x self/ide-settings，也绑在 C-M-s。"
  (interactive)
  (customize-group 'self-ide))

;; ─── 工具窗 ──────────────────────────────────────────────────────

(defun self/ide-last-tool ()
  "再次调用上一个工具窗命令（IDEA F12）。
交互命令：M-x self/ide-last-tool，也绑在 <f12>。"
  (interactive)
  (funcall self/ide--last-tool))

(defun self/ide-tool-project ()
  "开关项目树（IDEA Alt+1）。
交互命令：M-x self/ide-tool-project，也绑在 M-1。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-project)
  (self/ide-panel-toggle))

(defun self/ide-select-in-project ()
  "在项目树里定位当前文件（IDEA Alt+F1）。
交互命令：M-x self/ide-select-in-project，也绑在 M-<f1>。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-select-in-project)
  (self/ide-panel-reveal))

(defun self/ide--toggle-named-buffer (name show)
  "名为 NAME 的缓冲已显示则关闭它的窗口，否则调用无参函数 SHOW。"
  (let ((buf (get-buffer name)))
    (if (and buf (get-buffer-window buf))
        (delete-window (get-buffer-window buf))
      (funcall show))))

(defun self/ide-tool-bookmarks ()
  "开关书签列表（IDEA Alt+2）。
交互命令：M-x self/ide-tool-bookmarks，也绑在 M-2。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-bookmarks)
  (self/ide--toggle-named-buffer "*Bookmark List*" #'bookmark-bmenu-list))

(defun self/ide-tool-find ()
  "开关查找结果；没有结果窗时开始项目搜索（IDEA Alt+3）。
交互命令：M-x self/ide-tool-find，也绑在 M-3。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-find)
  (let ((win nil)
        (names '("*xref*" "*grep*" "*ripgrep*" "*rg*")))
    (dolist (name names)
      (let ((buf (get-buffer name)))
        (when (and (not win) buf (get-buffer-window buf))
          (setq win (get-buffer-window buf)))))
    (if win
        (delete-window win)
      (consult-ripgrep))))

(defun self/ide-tool-run ()
  "开关运行窗；没有编译缓冲时开始运行（IDEA Alt+4）。
交互命令：M-x self/ide-tool-run，也绑在 M-4。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-run)
  (let ((buf (get-buffer "*compilation*")))
    (cond
     ((and buf (get-buffer-window buf))
      (delete-window (get-buffer-window buf)))
     (buf (display-buffer buf))
     (t (self/ide-run)))))

(defun self/ide-tool-debug ()
  "调试工具窗（IDEA Alt+5）：有会话就继续，否则开始调试。
交互命令：M-x self/ide-tool-debug，也绑在 M-5。"
  (interactive)
  (self/ide-debug))

(defun self/ide-tool-problems ()
  "开关问题窗（IDEA Alt+6）。
交互命令：M-x self/ide-tool-problems，也绑在 M-6。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-problems)
  (self/flymake-list-errors-dwim))

(defun self/ide-tool-structure ()
  "打开文件结构（IDEA Alt+7）。
Emacs 里这是补全弹出，不是常驻侧栏。Ctrl+F12 同一条命令。
交互命令：M-x self/ide-tool-structure，也绑在 M-7。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-structure)
  (consult-imenu))

(defun self/ide-tool-services ()
  "开关进程列表（IDEA Alt+8 Services 的近似）。
交互命令：M-x self/ide-tool-services，也绑在 M-8。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-services)
  (self/ide--toggle-named-buffer "*Process List*" #'list-processes))

(defun self/ide--magit-status-window ()
  "返回当前帧上 magit-status 的窗口，没有则 nil。"
  (let ((windows (window-list))
        (found nil))
    (while (and windows (not found))
      (when (with-current-buffer (window-buffer (car windows))
              (derived-mode-p 'magit-status-mode))
        (setq found (car windows)))
      (setq windows (cdr windows)))
    found))

(defun self/ide-tool-git ()
  "开关 Git 状态（IDEA Alt+9）。
交互命令：M-x self/ide-tool-git，也绑在 M-9。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-git)
  (self/ide--require-magit)
  (let ((win (self/ide--magit-status-window)))
    (if win
        (delete-window win)
      (magit-status))))

(defun self/ide-tool-commit ()
  "提交工具窗（IDEA Alt+0）。
交互命令：M-x self/ide-tool-commit，也绑在 M-0。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-commit)
  (self/ide-commit))

(defun self/ide-tool-terminal ()
  "开关终端（IDEA Alt+F12）。
交互命令：M-x self/ide-tool-terminal，也绑在 M-<f12>。"
  (interactive)
  (setq self/ide--last-tool #'self/ide-tool-terminal)
  (let ((buf (self--terminal-existing-buffer)))
    (cond
     ((and buf (get-buffer-window buf))
      (delete-window (get-buffer-window buf)))
     (buf (display-buffer buf))
     (t (self/open-terminal)))))

;; ─── Search Everywhere ───────────────────────────────────────────

(defun self/ide--command-rows ()
  "返回命令候选。第一次扫 `obarray'，之后复用缓存。"
  (unless self/ide--command-rows
    (let (rows)
      (mapatoms
       (lambda (sym)
         (when (commandp sym)
           (push (cons (format "命令  %s" sym) (cons 'command sym)) rows))))
      (setq self/ide--command-rows (nreverse rows))))
  self/ide--command-rows)

(defun self/ide--search-buffers ()
  "返回已打开缓冲的候选。内部缓冲（空格前缀）不列入。"
  (let (rows)
    (dolist (buf (buffer-list))
      (when (buffer-live-p buf)
        (let ((name (buffer-name buf)))
          (unless (string-prefix-p " " name)
            (push (cons (format "缓冲  %s" name) (cons 'buffer buf)) rows)))))
    (nreverse rows)))

(defun self/ide--search-files ()
  "返回 recentf 与当前项目文件的候选。同一路径只出现一次。"
  (let ((rows nil)
        (seen (make-hash-table :test #'equal))
        (project (project-current nil)))
    (dolist (file (and (boundp 'recentf-list) recentf-list))
      (when (and (stringp file) (not (gethash file seen)) (file-exists-p file))
        (puthash file t seen)
        (push (cons (format "文件  %s" file) (cons 'file file)) rows)))
    (when project
      (dolist (file (project-files project))
        (unless (gethash file seen)
          (puthash file t seen)
          (push (cons (format "项目  %s"
                              (file-relative-name file (project-root project)))
                      (cons 'file file))
                rows))))
    (nreverse rows)))

(defun self/ide--search-everywhere-rows ()
  "缓冲、文件、命令三类候选接成一张表。"
  (append (self/ide--search-buffers)
          (self/ide--search-files)
          (self/ide--command-rows)))

(defun self/ide--search-everywhere-open (action)
  "按 ACTION 打开缓冲、文件或执行命令。ACTION 是 (kind . payload)。"
  (when action
    (let ((kind (car action))
          (payload (cdr action)))
      (cond
       ((eq kind 'buffer) (switch-to-buffer payload))
       ((eq kind 'file) (find-file payload))
       ((eq kind 'command) (call-interactively payload))))))

(defun self/ide-search-everywhere ()
  "搜索缓冲、文件与命令（IDEA 双击 Shift 的替代）。
双击 Shift 在 Emacs 里发不出按键，本命令绑在 Ctrl+Shift+P。
只搜命令用 Ctrl+Shift+A。
交互命令：M-x self/ide-search-everywhere，也绑在 C-S-p。"
  (interactive)
  (let* ((rows (self/ide--search-everywhere-rows))
         (choice (completing-read "Search Everywhere: "
                                  (mapcar #'car rows) nil t)))
    (self/ide--search-everywhere-open (cdr (assoc choice rows)))))

;; ─── 装到全局键图上 ──────────────────────────────────────────────
;;
;; 已经在 `self:binding-spec' 里的键走 rebind，否则 self/bind 会因
;; 重复声明直接报错。新键才用 self/bind。分组一律写 IDEA 键位。

(defconst self:ide-keymap-rebinds
  '(("C-s" self/ide-save-all "保存全部")
    ("C-p" self/ide-parameter-info "参数信息")
    ("C-b" xref-find-definitions "跳转到声明")
    ("C-k" self/ide-commit "Git 提交")
    ("C-d" duplicate-dwim "复制当前行")
    ("C-t" self/ide-update-project "更新项目")
    ("C-S-k" self/ide-push "Git 推送")
    ("C-S-f" consult-ripgrep "在路径中查找")
    ("C-S-r" project-query-replace-regexp "在路径中替换")
    ("C-S-a" execute-extended-command "查找操作")
    ("C-S-p" self/ide-search-everywhere "随处搜索")
    ("C-S-n" project-find-file "跳转到文件")
    ("C-S-e" consult-global-mark "最近位置")
    ("C-S-g" goto-line "跳转到行")
    ("C-S-w" er/contract-region "缩小选区")
    ("C-S-/" self/ide-comment-block "块注释")
    ("C-S-v" yank-from-kill-ring "从剪贴板历史粘贴")
    ("C-<f12>" consult-imenu "文件结构")
    ("<f12>" self/ide-last-tool "上一个工具窗")
    ("<f2>" flymake-goto-next-error "下一处错误")
    ("<f5>" self/ide-refresh "重新加载文件")
    ("<f8>" self/ide-step-over "单步跳过")
    ("S-<f8>" self/ide-step-out "单步跳出")
    ("<f9>" self/ide-resume "继续运行")
    ("<f11>" bookmark-set "切换书签")
    ("S-<f10>" self/ide-run "运行")
    ("M-<left>" self/tabs-previous "上一个标签")
    ("M-<right>" self/tabs-next "下一个标签")
    ("M-<up>" beginning-of-defun "上一个方法")
    ("M-<down>" end-of-defun "下一个方法"))
  "覆盖已有声明的 IDEA 键。每条是 (键 命令 说明)。")

(defconst self:ide-keymap-binds
  '(("C-n" self/ide-goto-class "跳转到类")
    ("C-M-S-n" self/workspace-symbol "跳转到符号")
    ("C-e" consult-recent-file "最近文件")
    ("C-f" self/isearch-forward-dwim "在文件中查找")
    ("C-r" query-replace "在文件中替换")
    ("C-y" kill-whole-line "删除当前行")
    ("C-w" er/expand-region "扩展选区")
    ("C-q" self/ide-quick-documentation "快速文档")
    ("C-v" yank "粘贴")
    ("C-M-l" self/ide-reformat "重新格式化")
    ("C-M-o" self/ide-optimize-imports "优化导入")
    ("C-M-s" self/ide-settings "设置")
    ("C-M-<left>" xref-go-back "后退")
    ("C-M-<right>" xref-go-forward "前进")
    ("M-<f7>" xref-find-references "查找用法")
    ("S-<f6>" self/rename-dwim "重命名")
    ("M-S-<up>" self/code-move-line-up "上移当前行")
    ("M-S-<down>" self/code-move-line-down "下移当前行")
    ("M-j" self/ide-select-next-occurrence "选中下一处")
    ("M-S-j" self/ide-unselect-occurrence "取消一处多光标")
    ("C-M-S-j" self/ide-select-all-occurrences "选中全部出现")
    ("M-<return>" self/ide-intention "意图操作")
    ("M-S-<down-mouse-1>" self/mc-add-cursor-on-click "Alt+Shift+点击加光标")
    ("S-<return>" self/open-line-below "下方新开一行")
    ("S-<f2>" flymake-goto-prev-error "上一处错误")
    ("<f7>" self/ide-step-into "单步进入")
    ("S-<f9>" self/ide-debug "调试")
    ("C-<f2>" self/ide-stop "停止")
    ("C-<f4>" kill-current-buffer "关闭标签")
    ("C-<f8>" self/ide-toggle-breakpoint "切换断点")
    ("C-<f9>" self/ide-build "构建")
    ("M-1" self/ide-tool-project "项目工具窗")
    ("M-2" self/ide-tool-bookmarks "书签工具窗")
    ("M-3" self/ide-tool-find "查找工具窗")
    ("M-4" self/ide-tool-run "运行工具窗")
    ("M-5" self/ide-tool-debug "调试工具窗")
    ("M-6" self/ide-tool-problems "问题工具窗")
    ("M-7" self/ide-tool-structure "结构工具窗")
    ("M-8" self/ide-tool-services "服务工具窗")
    ("M-9" self/ide-tool-git "Git 工具窗")
    ("M-0" self/ide-tool-commit "提交工具窗")
    ("M-<f12>" self/ide-tool-terminal "终端")
    ("M-<f1>" self/ide-select-in-project "在项目树中定位"))
  "IDEA 键图里原先没有声明过的键。每条是 (键 命令 说明)。")

(defun self/ide--install-keymap ()
  "把 IDEA Windows 键图装到全局，并改写帮助表。"
  (dolist (item self:ide-keymap-rebinds)
    (self/ide--rebind (nth 0 item) (nth 1 item) (nth 2 item)
                      self:ide-keymap-group))
  (dolist (item self:ide-keymap-binds)
    (self/bind (nth 0 item) (nth 1 item) (nth 2 item)
               self:ide-keymap-group)))

(defun self/ide--keep-minibuffer-edit-keys ()
  "迷你缓冲保留行编辑键，不继承编辑区的 IDEA 全局绑定。
补全框的 C-n / C-p 由 vertico 的 minor mode 覆盖本表，仍然是上下移动候选。"
  (dolist (pair '(("C-a" . move-beginning-of-line)
                  ("C-b" . backward-char)
                  ("C-d" . delete-char)
                  ("C-e" . move-end-of-line)
                  ("C-f" . forward-char)
                  ("C-k" . kill-line)
                  ("C-n" . next-line)
                  ("C-p" . previous-line)
                  ("C-q" . quoted-insert)
                  ("C-r" . previous-matching-history-element)
                  ("C-s" . next-matching-history-element)
                  ("C-t" . transpose-chars)
                  ("C-w" . backward-kill-word)
                  ("C-y" . yank)
                  ("C-v" . yank)))
    (define-key minibuffer-local-map (kbd (car pair)) (cdr pair))))

(self/ide--install-keymap)
(self/ide--keep-minibuffer-edit-keys)

;; cua：有选区时 C-c / C-x 是复制 / 剪切，没有选区时仍是前缀。
;; C-v 始终粘贴，C-z 始终撤销。0.2 秒内不再按后续键才当复制，
;; 按住则回到 C-c / C-x 前缀（见 `cua-prefix-override-inhibit-delay'）。
(setq cua-enable-cua-keys t
      cua-keep-region-after-copy t
      cua-prefix-override-inhibit-delay 0.2)
(cua-mode 1)
(delete-selection-mode 1)

(provide 'self-ide-keys)
;;; self-ide-keys.el ends here
