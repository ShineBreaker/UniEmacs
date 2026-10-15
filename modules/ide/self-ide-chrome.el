;;; self-ide-chrome.el --- IDE 档外观层：对齐 Zed 的面包屑、标签装饰与字体 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-theme（行号）、self-tabline（`tab-line-tab-face-functions'）、
;;           self-modeline（`self/modeline--vc-state-cache' 等诊断缓存）
;; Packages: colorful-mode
;;
;; Zed 的编辑器界面可以拆成几条正交横带：顶部标签栏、标签下方一条
;; 「路径面包屑」工具行、行号列、当前行高亮、右缘缩略图、底部状态行。
;; UniEmacs 里标签栏（self-tabline）与状态行（self-modeline +
;; minibuffer-line）已具备，本模块补齐剩下的外观差异：
;;
;;   1. 字体分轨：编辑区用等宽编程字体（Zed buffer font），框架 UI 元素
;;      ——标签、面包屑、状态行——用界面字体（Zed ui font）并稍加重字重。
;;   2. 绝对行号：full 档用相对行号服务 Evil 习惯，ide 档面向非 Vim 用户，
;;      回到绝对行号。
;;   3. 面包屑行：header-line 显示「项目相对路径 › 当前函数名」，由
;;      `which-function-mode' 提供符号部分。
;;   4. 标签语义着色：Zed 会把 Git 状态与诊断标到标签上。tab-line 只能改
;;      face，约定优先级：错误诊断 > Git 修改 > 未跟踪/警告。
;;   5. frame 标题：「项目名 — 分支 — 文件」，对齐 Zed 标题栏信息。
;;   6. colorful-mode：十六进制/RGB 字面量就地渲染色块，对应 Zed 的
;;      colorizer 扩展。
;;
;; 刻意不做的：配色主题不动（用户指定只对齐界面结构与操作习惯）；
;; Zed 面包屑右侧的「快速操作」图标区无对应物，不造。

;;; Code:

(require 'self-lib)

(defgroup self-ide nil
  "IDE 档：full 之上的 Zed 对齐界面与行为层。"
  :group 'self)

(defvar which-func-table)
(defvar which-func-unknown)
(defvar self/modeline--vc-state-cache)
(defvar self/modeline--flymake-counts)

;; ─── 字体：编辑区等宽 / 界面区 UI 字体 ──────────────────────────────

(defcustom self:ide-buffer-font "Maple Mono NF CN"
  "ide 档编辑区字体族；Zed 的 buffer font 对应物。"
  :type 'string
  :group 'self-ide)

(defcustom self:ide-ui-font "Sarasa UI SC"
  "ide 档界面字体族；Zed 的 ui font 对应物，用于标签、面包屑、状态行等。"
  :type 'string
  :group 'self-ide)

(defconst self--ide-ui-faces
  '(mode-line mode-line-inactive minibuffer-prompt
    header-line header-line-inactive
    tab-line tab-line-tab-current tab-line-tab-inactive)
  "随 `self:ide-ui-font' 走的中等字重 UI face 清单。")

(defun self/ide--apply-frame-faces (&optional frame)
  "在 FRAME（缺省当前帧）上应用 ide 档字体分轨。
字体族名不可靠时静默跳过（如用户换了机器没装字体）；TTY 帧天然忽略
family，无需特判。self-theme 的 `self/restore-theme-presentation' 只覆写
光标与线条颜色，不碰 family，两套定制可在同一 face 上共存。"
  (when (display-graphic-p frame)
    (with-selected-frame (or frame (selected-frame))
      (let ((families (font-family-list)))
        (when (member self:ide-buffer-font families)
          (set-face-attribute 'default nil :family self:ide-buffer-font))
        (when (member self:ide-ui-font families)
          (dolist (face self--ide-ui-faces)
            (set-face-attribute face nil
                                :family self:ide-ui-font
                                :weight 'medium)))))))

;; daemon 预热期无 GUI 帧，每个 client 帧建好时各刷一次；standalone
;; 的初始帧不走 after-make-frame-functions，加载期显式补一次。
(add-hook 'after-make-frame-functions #'self/ide--apply-frame-faces)
(self/ide--apply-frame-faces (selected-frame))

;; ─── 行号 / 帧标题 / 顶部 chrome / 子进程 EDITOR ────────────────────

;; Zed 的 absolute 行号：ide 档不要求 Evil，回退 full 档的 relative。
(setq display-line-numbers-type t)

;; Zed 窗口顶部没有菜单栏与工具栏：ide 档把这两条 GTK chrome 裁掉，
;; 让 tab-line（标签栏）直接顶到窗口上缘，空间利用与观感对齐。
;; minimal/full 档保留菜单栏（学习档需要可探索的菜单）。
(menu-bar-mode -1)
(tool-bar-mode -1)

(defun self/ide--frame-title ()
  "帧标题：项目名 — 分支 — 缓冲区名，对齐 Zed 标题栏的项目/分支提示。"
  (let* ((project (project-current nil))
         (proj-name (and project (file-name-nondirectory
                                  (directory-file-name
                                   (project-root project)))))
         (branch (and vc-mode
                      (string-match "\\` ?Git[:-]\\(.+\\)\\'" vc-mode)
                      (match-string 1 vc-mode)))
         (name (buffer-name)))
    (mapconcat #'identity
               (delq nil (list proj-name branch name))
               " — ")))

;; defvar 而非 setq：vc-mode 是 mode-line 格式段，作为普通文本拼进
;; frame-title 也能用（变量在求值处取选中窗口缓冲的值）。
(setq frame-title-format '((:eval (self/ide--frame-title))))

;; 对齐 Zed 的 terminal.env EDITOR=zeditor --wait：从 Emacs 拉的终端
;; 子进程（Ghostel、编译缓冲区等）里跑 git commit / crontab -e 时，
;; 编辑器都交回当前 Emacs 实例。server-mode 由 self-daemon 保证。
(setenv "EDITOR" "emacsclient")
(setenv "VISUAL" "emacsclient")

;; ─── 面包屑：header-line 上的「相对路径 › 函数」 ────────────────────

;; Zed 标签栏下面那行：左端是项目相对路径，光标所在符号以 › 续在后面。
;; which-function-mode 以 imenu/semantic 求当前符号，多数 prog buffer 有
;; imenu 支持；结果按窗口缓存进 `which-func-table'（Emacs 32 起
;; `which-func-current' 本身是 :eval 格式段而非字符串，不能直接
;; propertize——真名字符串要 gethash 取）。
(which-function-mode 1)

(defvar-local self/ide--breadcrumb-path nil
  "面包屑路径段缓存：项目相对路径，非项目文件为文件名。
在 `self/ide--breadcrumb-install' 里一次性算好，redisplay 零 I/O。")

;; 给 header-line 上的函数名一个和 Zed 面包屑一致的形态：路径用界面
;; 字体继承 header-line，函数名换 function-name 配色提示层级切换。
(defun self/ide--breadcrumb ()
  "当前缓冲的 Zed 式面包屑字符串；无内容时返回空串。
路径段在 find-file 时缓存进 `self/ide--breadcrumb-path'，渲染只读变量，
不做 I/O——header-line 每次 redisplay 都会求值，这里必须是纯计算。"
  (let ((path self/ide--breadcrumb-path)
        (func (and (bound-and-true-p which-func-mode)
                   (gethash (selected-window) which-func-table))))
    (when (and path (not (string-empty-p path)))
      (concat " " path
              (and func
                   (not (equal func which-func-unknown))
                   (concat "  ›  "
                           (propertize func
                                       'face 'font-lock-function-name-face)))))))

(defun self/ide--breadcrumb-install ()
  "给文件缓冲区安装面包屑 header-line。
在 `find-file-hook' 上跑，此时 `buffer-file-name' 已定；项目识别只做
这一次并缓存结果，之后 redisplay 不碰项目扫描。"
  (when buffer-file-name
    (let ((project (project-current nil)))
      (setq-local self/ide--breadcrumb-path
                  (if project
                      (file-relative-name buffer-file-name
                                          (project-root project))
                    (file-name-nondirectory buffer-file-name)))
      (setq-local header-line-format
                  '((:eval (self/ide--breadcrumb)))))))

(add-hook 'find-file-hook #'self/ide--breadcrumb-install)

;; ─── 标签语义着色：诊断 > Git 修改 > 未跟踪 ─────────────────────────

;; Zed 的 tabs 显示 Git 状态色与诊断标记。Emacs tab-line 标签只能整体换
;; face，约定一条通道走优先级最高的信息：有错误诊断染 error 红，无错误
;; 但 Git 有改动染 warning 黄，未跟踪文件用 success 绿提示是新文件。
;; 数据全部取自 self-modeline 已缓存的 buffer-local 变量，零 I/O。

(defun self/ide--tab-buffer-state (buffer)
  "返回 BUFFER 的标签着色等级：'error、'modified、'untracked 或 nil。"
  (let ((diag (buffer-local-value 'self/modeline--flymake-counts buffer))
        (vc (buffer-local-value 'self/modeline--vc-state-cache buffer)))
    (cond
     ((and diag (> (or (car diag) 0) 0)) 'error)
     ((memq vc '(edited added removed needs-merge needs-update
                        conflict missing ignored unregistered-changes))
      'modified)
     ((eq vc 'unregistered) 'untracked)
     (t nil))))

(defun self/ide--tab-face (tab _tabs face buffer-p _selected-p)
  "tab-line 标签 face 链末端：按 `self/ide--tab-buffer-state' 补前景色。
签名是 `tab-line-tab-face-functions' 约定的五参固定式；只往链上已有的
FACE 再包一层 `:inherit'，不动既有选中态底色逻辑。"
  (if (not buffer-p)
      face
    ;; buffer-p 为真时 TAB 本身就是 buffer 对象（不是 alist），
    ;; 对它 assq 会 listp 报错——self/tab-line-tabs 产出的正是裸 buffer。
    (let ((buffer tab))
      (pcase (and buffer (self/ide--tab-buffer-state buffer))
        ('error (list face '(:inherit error)))
        ('modified (list face '(:inherit warning)))
        ('untracked (list face '(:inherit success)))
        (_ face)))))

;; 追加而非替换：保留 self-tabline 的选中/非选中 face 链，只在其结果上
;; 叠加语义前景色。
(add-hook 'tab-line-tab-face-functions #'self/ide--tab-face 'append)

;; ─── 颜色字面量就地渲染（Zed colorizer 扩展对应物）──────────────────

(use-package colorful-mode
  :defer t
  :hook ((prog-mode text-mode) . colorful-mode))

(provide 'self-ide-chrome)
;;; self-ide-chrome.el ends here
