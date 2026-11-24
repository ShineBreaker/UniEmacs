;;; self-ide-chrome.el --- IDE 档外观层：IDEA New UI 与面包屑、标签装饰 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-theme（行号）、self-tabline（`tab-line-tab-face-functions'）、
;;           self-modeline（`self/modeline--vc-state-cache' 等诊断缓存）
;; Packages: colorful-mode
;;
;; ide 档的外观目标是 IntelliJ IDEA 2023+ New UI 的 Dark / Islands：
;; 深色编辑区浮在更暗的画布上，窗口之间留出缝，顶上一条紧凑主工具栏，
;; 编辑区顶部是标签，标签下是面包屑，底部 echo area 充当状态栏。
;; Emacs 窗口是直角的，做不到 Islands 的圆角卡片，缝隙用 internal-border
;; 加宽 window-divider 来近似。
;;
;;   1. 字体：不在本档换家族。编辑区、顶栏、状态栏和终端都沿用
;;      self-theme 按 `self:font-family'（Maple Mono NF CN）设的字体；
;;      没装 Maple 时留下系统默认，不改成别的等宽字体。
;;   2. 配色：覆盖 Modus 的 face，取 IDEA Dark 的编辑区 #1E1F22、
;;      工具窗 #2B2D30、画布 #131314、强调色 #3574F0。主题再切换时
;;      由 `enable-theme-functions' 重新盖上去。
;;   3. 绝对行号、面包屑、标签上的 Git/诊断色、frame 标题、colorful-mode
;;      仍保留（行内诊断由 self-prog 的 flymake 行尾提示负责）。
;;   4. 顶栏不是 Emacs 菜单栏：menu-bar 关掉，改用 tab-bar 画一条
;;      「菜单 / 项目 / 运行 / 调试 / 搜索 / 分支 / 设置」。左侧竖条工具窗
;;      按钮 Emacs 没有对应的窗口原语，同样收进这条顶栏，快捷键仍是 Alt+数字。
;;
;; 状态栏文案布局不在本文件算，只把 `self:modeline-layout' 设为 idea。

;;; Code:

(require 'self-lib)

(defgroup self-ide nil
  "IDE 档：IDEA New UI 外观与 Windows 键图。"
  :group 'self)

(defvar which-func-table)
(defvar which-func-unknown)
(defvar self/modeline--vc-state-cache)
(defvar self/modeline--flymake-counts)

;; ─── 行号 / 帧标题 / 顶部 chrome / 子进程 EDITOR ────────────────────

;; IDEA 编辑区用绝对行号。standard 档的相对行号是给 Emacs 自身导航的。
(setq display-line-numbers-type t)

;; IDEA New UI 把主菜单收进顶栏汉堡按钮，不留 GTK 菜单栏和工具栏。
;; 文件标签用 tab-line，紧挨在顶栏下面。minimal/standard 档保留菜单栏。
(menu-bar-mode -1)
(tool-bar-mode -1)

(defun self/ide--frame-title ()
  "帧标题：项目名 — 分支 — 缓冲区名。"
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

;; 从 Emacs 拉的终端
;; 子进程（Ghostel、编译缓冲区等）里跑 git commit / crontab -e 时，
;; 编辑器都交回当前 Emacs 实例。server-mode 由 self-daemon 保证。
(setenv "EDITOR" "emacsclient")
(setenv "VISUAL" "emacsclient")

;; ─── 面包屑：header-line 上的「相对路径 › 函数」 ────────────────────

;; 标签下面的面包屑：左端是项目相对路径，光标所在符号以 › 续在后面。
;; which-function-mode 以 imenu/semantic 求当前符号，多数 prog buffer 有
;; imenu 支持；结果按窗口缓存进 `which-func-table'（Emacs 32 起
;; `which-func-current' 本身是 :eval 格式段而非字符串，不能直接
;; propertize——真名字符串要 gethash 取）。
;; 只在代码缓冲里建 imenu。which-func-modes 为 t 时，文本和 Markdown
;; 也会跑索引，失败就把 "which-func-ff-hook error" 写进 echo area，
;; 盖住状态栏。函数名只对 prog-mode 有意义。
(defvar which-func-modes)
(setq which-func-modes '(prog-mode))
(which-function-mode 1)

(defvar-local self/ide--breadcrumb-path nil
  "面包屑路径段缓存：项目相对路径，非项目文件为文件名。
在 `self/ide--breadcrumb-install' 里一次性算好，redisplay 零 I/O。")

;; 路径继承 header-line 的字体，函数名换 function-name 配色。
(defun self/ide--breadcrumb ()
  "当前缓冲的面包屑字符串；无内容时返回空串。
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

;; 标签用前景色标出 Git 状态和诊断。Emacs tab-line 标签只能整体换
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

;; ─── IDEA New UI Dark / Islands ────────────────────────────────────
;;
;; 取色对齐 IDEA 2023+ 默认 Dark（不是经典 Darcula）：编辑区 #1E1F22，
;; 工具窗与顶栏 #2B2D30，Islands 画布 #131314，强调蓝 #3574F0。
;; face 表里的符号（editor、chrome、accent …）经 `self/ide-color' 换成
;; 色值；已经是字符串或别的属性（:box、:extend、:weight）原样传给
;; `set-face-attribute'。

(defvar self:modeline-layout)
(defvar self:modeline-padding)
(require 'subr-x)

(declare-function project-current "project" (&optional maybe-prompt directory))
(declare-function project-root "project" (project))

(defconst self:ide-newui-palette
  '((canvas . "#131314")
    (editor . "#1E1F22")
    (chrome . "#2B2D30")
    (hover . "#393B40")
    (fg . "#BCBEC4")
    (fg-strong . "#DFE1E5")
    (fg-dim . "#7A7E85")
    (accent . "#3574F0")
    (selection . "#214283")
    (line . "#26282E")
    (keyword . "#CF8E6D")
    (string . "#6AAB73")
    (number . "#2AACB8")
    (function . "#56A8F5")
    (constant . "#C77DBB")
    (comment . "#7A7E85")
    (doc . "#5F826B")
    (added . "#499C54")
    (modified . "#3574F0")
    (deleted . "#CC666E")
    (warning . "#D6B15A")
    (error . "#F75464")
    (border . "#393B40"))
  "IDEA New UI Dark 的角色色。键是角色名，值是 #RRGGBB。")

(defun self/ide-color (role)
  "返回调色板里 ROLE 的 #RRGGBB 字符串。未知角色返回 nil。"
  (cdr (assq role self:ide-newui-palette)))

(defconst self:ide-newui-faces
  '((default :background editor :foreground fg)
    (cursor :background fg-strong)
    (region :background selection :extend t)
    (hl-line :background line :extend t)
    (line-number :foreground fg-dim :background editor)
    (line-number-current-line :foreground fg-strong :background line :weight bold)
    (fringe :background editor)
    (internal-border :background canvas)
    (vertical-border :foreground canvas)
    (border :background canvas)
    (child-frame-border :background border)
    (window-divider :foreground canvas)
    (window-divider-first-pixel :foreground canvas)
    (window-divider-last-pixel :foreground canvas)
    (header-line :background editor :foreground fg-dim :box nil)
    (header-line-inactive :background editor :foreground fg-dim :box nil)
    (tab-line :background chrome :foreground fg-dim :box nil)
    (tab-line-tab :background chrome :foreground fg-dim :box nil)
    (tab-line-tab-current :background editor :foreground fg-strong :box nil)
    (tab-line-tab-inactive :background chrome :foreground fg-dim :box nil)
    (tab-line-highlight :background hover :foreground fg-strong)
    (tab-bar :background chrome :foreground fg :box nil)
    (tab-bar-tab :background chrome :foreground fg-strong :box nil)
    (tab-bar-tab-inactive :background chrome :foreground fg-dim :box nil)
    (minibuffer-line :background chrome :foreground fg :box nil)
    (mode-line :background chrome :foreground fg :box nil)
    (mode-line-inactive :background canvas :foreground fg-dim :box nil)
    (minibuffer-prompt :foreground accent)
    (show-paren-match :background hover :foreground fg-strong)
    (font-lock-keyword-face :foreground keyword)
    (font-lock-string-face :foreground string)
    (font-lock-comment-face :foreground comment)
    (font-lock-comment-delimiter-face :foreground comment)
    (font-lock-doc-face :foreground doc)
    (font-lock-function-name-face :foreground function)
    (font-lock-variable-name-face :foreground fg)
    (font-lock-type-face :foreground fg-strong)
    (font-lock-constant-face :foreground constant)
    (font-lock-builtin-face :foreground keyword)
    (font-lock-preprocessor-face :foreground constant)
    (font-lock-warning-face :foreground warning)
    (font-lock-negation-char-face :foreground keyword)
    (error :foreground error)
    (warning :foreground warning)
    (success :foreground added)
    (link :foreground accent)
    (highlight :background hover)
    (lazy-highlight :background hover)
    (isearch :background accent :foreground fg-strong)
    (match :background selection)
    (flymake-error :underline (:style wave :color "#F75464"))
    (flymake-warning :underline (:style wave :color "#D6B15A"))
    (flymake-note :underline (:style wave :color "#3574F0"))
    (diff-hl-insert :foreground added :background added)
    (diff-hl-change :foreground modified :background modified)
    (diff-hl-delete :foreground deleted :background deleted)
    (treemacs-default-face :foreground fg :background chrome)
    (treemacs-file-face :foreground fg)
    (treemacs-directory-face :foreground fg-strong)
    (treemacs-root-face :foreground fg-strong :weight bold)
    (treemacs-git-modified-face :foreground modified)
    (treemacs-git-added-face :foreground added)
    (treemacs-git-untracked-face :foreground added)
    (treemacs-git-ignored-face :foreground fg-dim)
    (treemacs-git-renamed-face :foreground function)
    (treemacs-git-conflict-face :foreground deleted)
    (treemacs-hl-line-face :background hover :extend t)
    (treemacs-window-background-face :background chrome)
    (vertico-current :background selection :extend t)
    (corfu-current :background selection)
    (corfu-default :background chrome :foreground fg)
    (corfu-border :background border))
  "IDEA New UI 要覆盖的 face。
每条是 (FACE :ATTR VALUE ...)。VALUE 若是调色板里的角色名，应用时换成色值。
包还没加载、face 尚不存在的条目会跳过，等对应库加载后再刷一次。")

(defface self-ide-toolbar
  '((t :inherit tab-bar))
  "IDEA 顶栏普通按钮。"
  :group 'self-ide)

(defface self-ide-toolbar-strong
  '((t :inherit tab-bar :weight bold))
  "IDEA 顶栏上的项目名。"
  :group 'self-ide)

(defface self-ide-toolbar-accent
  '((t :inherit tab-bar :weight bold))
  "IDEA 顶栏上的运行按钮。"
  :group 'self-ide)

(defun self/ide--resolve-face-attr (key value)
  "把 face 属性 VALUE 里的调色板角色换成色值。KEY 不是颜色属性时原样返回。"
  (if (and (memq key '(:foreground :background))
           (symbolp value)
           (assq value self:ide-newui-palette))
      (self/ide-color value)
    value))

(defun self/ide--apply-one-face (face attrs)
  "把 ATTRS（:key value 交替）设到 FACE 上。face 不存在则什么都不做。"
  (when (facep face)
    (let ((resolved nil)
          (rest attrs))
      (while rest
        (let ((key (car rest))
              (value (cadr rest)))
          (setq resolved
                (append resolved
                        (list key (self/ide--resolve-face-attr key value)))))
        (setq rest (cddr rest)))
      (apply #'set-face-attribute face nil resolved))))

(defun self/ide--apply-newui-faces ()
  "按 `self:ide-newui-faces' 覆盖当前主题的 face。"
  (dolist (spec self:ide-newui-faces)
    (self/ide--apply-one-face (car spec) (cdr spec)))
  (self/ide--apply-one-face 'self-ide-toolbar '(:foreground fg :background chrome))
  (self/ide--apply-one-face 'self-ide-toolbar-strong
                            '(:foreground fg-strong :background chrome :weight bold))
  (self/ide--apply-one-face 'self-ide-toolbar-accent
                            '(:foreground accent :background chrome :weight bold)))

;; Platform: gui
(defun self/ide--apply-island-geometry (&optional frame)
  "图形帧上加一圈内边距，窗口之间留出 Islands 式暗缝。
`window-divider-mode' 是全局的：ide 守护进程若再连一个 TTY client，
终端帧也会看到这条缝。宽度只在图形帧上写，避免把 TTY 的边框清掉。"
  (when (display-graphic-p (or frame (selected-frame)))
    (with-selected-frame (or frame (selected-frame))
      (set-frame-parameter nil 'internal-border-width 10))
    (setq window-divider-default-places t
          window-divider-default-bottom-width 8
          window-divider-default-right-width 8)
    (window-divider-mode 1)))

(defun self/ide--apply-newui (&rest _)
  "套用 New UI 配色和岛屿缝。字体留给 self-theme 的全局 Maple 设置。
主题切换后也走这里。"
  (self/ide--apply-newui-faces)
  (self/ide--apply-island-geometry (selected-frame))
  (setq-default cursor-type '(bar . 2)
                line-spacing 0.08
                left-fringe-width 12
                right-fringe-width 8)
  (setq self:modeline-layout 'idea
        self:modeline-padding 2))

;; ─── 顶栏：New UI 的紧凑主工具栏 ──────────────────────────────────
;;
;; tab-line 是每个编辑窗口自己的文件标签。tab-bar 在整个帧的最上缘，
;; 用来放 IDEA 主工具栏。self-tabline 关过 tab-bar-mode，这里按 ide 档
;; 重新打开，并且不放 Emacs 的 frame tab（文件标签已经在 tab-line）。

(defvar self/ide--project-label "无项目"
  "顶栏上的项目名缓存。只在换缓冲时重算，redisplay 不扫项目。")

(defun self/ide--refresh-project-label ()
  "把顶栏项目名缓存更新成当前项目的目录名。"
  (let ((project (project-current nil)))
    (setq self/ide--project-label
          (if project
              (file-name-nondirectory
               (directory-file-name (project-root project)))
            "无项目"))))

(defun self/ide--on-window-buffer-change (frame)
  "换缓冲时刷新顶栏项目名。FRAME 必须仍活着（异步回调才做存活检查）。"
  (when (frame-live-p frame)
    (with-selected-frame frame
      (with-current-buffer (window-buffer (frame-selected-window frame))
        (self/ide--refresh-project-label)))))

(defun self/ide--toolbar-branch-name ()
  "从 `vc-mode' 取出分支名。这个字符串是状态行已经算好的，不再查 git。
顶栏在 redisplay 里求值，`string-match' 必须包在 `save-match-data' 里，
否则会冲掉正在执行的搜索。"
  (save-match-data
    (and (stringp vc-mode)
         (string-match "\\(?:Git\\|Hg\\|SVN\\)[-:]\\(.+\\)" vc-mode)
         (string-trim (match-string 1 vc-mode)))))

(defun self/ide--toolbar-buttons (specs)
  "把 SPECS 收成 tab-bar 菜单项列表。
每条是 (KEY LABEL COMMAND HELP FACE)。LABEL 在这里盖上 FACE。"
  (let (items)
    (dolist (spec specs)
      (push (list (nth 0 spec)
                  'menu-item
                  (propertize (nth 1 spec) 'face (nth 4 spec))
                  (nth 2 spec)
                  :help (nth 3 spec))
            items))
    (nreverse items)))

(defun self/ide-toolbar-left ()
  "顶栏左段：菜单、项目、运行、调试、停止、搜索、终端。"
  (self/ide--toolbar-buttons
   `((ide-menu " ≡ " tmm-menubar "主菜单" self-ide-toolbar)
     (ide-project ,(format " %s " self/ide--project-label)
                  self/ide-panel-toggle
                  "项目工具窗 (Alt+1)" self-ide-toolbar-strong)
     (ide-run " 运行 " self/ide-run "运行 (Shift+F10)" self-ide-toolbar-accent)
     (ide-debug " 调试 " self/ide-debug "调试 (Shift+F9)" self-ide-toolbar)
     (ide-stop " 停止 " self/ide-stop "停止 (Ctrl+F2)" self-ide-toolbar)
     (ide-search " 搜索 " self/ide-search-everywhere
                 "Search Everywhere (Ctrl+Shift+P)" self-ide-toolbar)
     (ide-term " 终端 " self/ide-tool-terminal
               "终端 (Alt+F12)" self-ide-toolbar))))

(defun self/ide-toolbar-right ()
  "顶栏右段：分支与设置。"
  (let ((branch (self/ide--toolbar-branch-name)))
    (self/ide--toolbar-buttons
     `((ide-branch ,(if branch (format " %s " branch) " Git ")
                   self/ide-tool-git "Git (Alt+9)" self-ide-toolbar)
       (ide-settings " 设置 " self/ide-settings
                     "设置 (Ctrl+Alt+S)" self-ide-toolbar)))))

;; tab-bar-show 是数字时表示「帧标签个数超过它才显示」。
;; 平时只有一个帧标签，写成 1 会把整条工具栏藏掉。t 才是始终显示。
(setq tab-bar-show t
      tab-bar-format '(self/ide-toolbar-left
                       tab-bar-format-align-right
                       self/ide-toolbar-right)
      tab-bar-separator ""
      tab-bar-new-button nil
      tab-bar-close-button nil)
(tab-bar-mode 1)
(self/ide--refresh-project-label)
(add-hook 'find-file-hook #'self/ide--refresh-project-label)
(add-hook 'window-buffer-change-functions #'self/ide--on-window-buffer-change)

(add-hook 'enable-theme-functions #'self/ide--apply-newui 'append)
(dolist (lib '(treemacs diff-hl corfu vertico flymake))
  (with-eval-after-load lib
    (self/ide--apply-newui-faces)))
(self/ide--apply-newui)

;; ─── 颜色字面量就地渲染 ─────────────────────────────────────────────

(use-package colorful-mode
  :defer t
  :hook ((prog-mode text-mode) . colorful-mode))

(provide 'self-ide-chrome)
;;; self-ide-chrome.el ends here
