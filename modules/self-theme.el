;;; self-theme.el --- 主题与字体：Modus 深浅色同步、终端透明外观、平滑滚动 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, portable
;; Requires: 无
;; Packages: modus-themes（Emacs 28+ 内建，仅声明语义归属）
;;
;; 移植自桌面端配置的三个部分：「Frame 生命周期与 daemon」、
;; 「主题与字体」（含 GUI/TTY 混合 daemon 约束）与
;; 「颜色方案（Modus 主题）」。
;;
;; * daemon 下 frame 外观必须挂 after-make-frame-functions*
;;   守护进程启动时后台没有显示器屏幕，此时设置窗口大小、字体或透明度
;;   都会报错。所以本文件里所有 display-dependent 的外观设置都只在
;;   `after-make-frame-functions' 里应用：每有 client 连上来创建新窗口
;;   才按需应用一次（`self/theme--apply-frame-appearance' 与
;;   `self/color-scheme--apply-for-frame'）；非守护进程独立启动时，
;;   直接对当前首个窗口各调用一次。
;;
;; * GUI / TTY 混合 daemon 约束*
;;   同一个 daemon 可能同时被图形窗口（GUI）与 `emacsclient -t' 的终端
;;   窗口连接，两者显示机制差别很大：GUI 支持像素级透明度、矢量字体缩放
;;   与细条光标，并在 `default-frame-alist' 里彻底关掉菜单栏/工具栏/
;;   滚动条；终端模拟器（如 Foot）自身已配透明背景，Emacs 若给所有文本
;;   强绘背景色就会遮盖它、形成实色色块。所以：
;;   - 光标类型用 `set-frame-parameter' 而非 `setq-default'（后者是全局
;;     副作用，后创建的 TTY frame 会污染 GUI 的设置）。
;;   - 像素滚动无条件启用（GUI client 需要）。
;;   - 宽度类参数一律按 per-frame 参数写，不碰全局 `window-divider-mode'
;;     （那是全局的，TTY 连接时会误清空 GUI 分隔线）。
;;   - Modus 主题不能靠 `(display-graphic-p)' 判断是否加载——daemon 期它
;;     永远返回 nil；改用 `self/color-scheme--supports-themes-p'（图形
;;     frame，或 ≥256 色的真实终端）。
;;   - TTY 无 alpha 通道：清掉 face 背景与反色，但不覆盖主题前景色。
;;
;; * 颜色方案状态机*
;;   浅色用 `modus-operandi-tinted'、深色用 `modus-vivendi-tinted'。
;;   系统若运行 Darkman 并通过 D-Bus 广播事件，Emacs 注册监听器后
;;   深浅色自动无缝切换，GUI 与终端窗口同步刷新。D-Bus 不可用时回退
;;   深色主题。
;;
;; 移植说明：调色板取色（`self/terminal-theme-color'）保留了源配置里对
;; Modus 的 `fboundp' 守卫——`self/theme--apply-frame-appearance' 在文件
;; 前段注册时就会对首个窗口派发，而主题库要到本文件末尾的 `load-theme'
;; 才加载；这类对第三方延迟加载包的守卫是允许的。
;;
;; 分组说明：`defcustom' 目前挂在 `self-theme' 分组下，若 core 后续提供
;; 全局定制分组，应统一改指过去。

;;; Code:

(require 'dbus)

;; 行号显示与像素滚动所在的两个内建库在 Emacs 30 后不再随启动预载，
;; 但本模块要直接读写它们的变量、调用它们的 mode，故显式 require
;; （都是纯定义、无副作用的加载）。
(require 'display-line-numbers)
(require 'pixel-scroll)


;;; ─── 定制分组与平台谓词 ──────────────────────────────────────────────

(defgroup self-theme nil
  "主题与字体：外观可定制项。
用 M-x customize-group RET self-theme 浏览。
父分组暂挂在内建的 custom 下；编排者若在 core 提供统一的 self 伞形
分组，应把这里的 :group 改指过去。" :group 'custom)

;; 平台谓词由 core/self-lib.el 定义，这里只声明不赋值：Emacs 的 defvar
;; 遇到已绑定的变量就不改，带值声明等于白写（而 `defconst' 会把 self-lib
;; 的定义顶掉，让本模块的取值反过来决定全配置）。移动端（Android）与桌面端
;; 的差异一律经它守卫。
(defvar self:android-p)


;;; ─── 基础尺寸与行号策略 ──────────────────────────────────────────────

(defcustom self:frame-background-opacity 88
  "GUI frame 背景透明度(0~100,100 = 不透明)。"
  :type 'integer
  :group 'self-theme)

(defcustom self:default-font-height 110
  "默认字体大小(1/10 pt)。"
  :type 'integer
  :group 'self-theme)

(defconst self:terminal-frame-parameters
  '((background-color . "unspecified-bg")
    (foreground-color . "unspecified-fg")
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil))
  "TTY frame 在 face 初始化前应用的无色显示参数。
注入 `window-system-default-frame-alist' 的 t 条目由 early-init.el 在
main.el 之前完成(standalone 首帧也要生效);此处仅供
`self/theme--apply-terminal-faces' 对已创建的 TTY frame 逐个应用。")

(setopt xterm-update-cursor t)

(dolist (hook '(prog-mode-hook text-mode-hook))
  (add-hook hook #'prettify-special-glyphs-mode))

(dolist (param '((menu-bar-lines . 0)
                 (tool-bar-lines . 0)
                 (vertical-scroll-bars)
                 (horizontal-scroll-bars)))
  (unless (assq (car param) default-frame-alist)
    (push param default-frame-alist)))

(setq display-line-numbers-type 'relative
      display-line-numbers-width-start t)
(global-display-line-numbers-mode 1)

(defcustom self:large-file-size-threshold (* 2 1024 1024)
  "关闭高成本显示功能的文件大小阈值（字节）。"
  :type 'integer
  :group 'self-theme)

(defun self/theme--setup-file-line-numbers ()
  "大型文件直接关闭行号，避免扫描完整 buffer。
行号宽度由 `display-line-numbers-width-start' 按需计算，无需手动预设。"
  (when (> (buffer-size) self:large-file-size-threshold)
    (display-line-numbers-mode -1)))

(add-hook 'find-file-hook #'self/theme--setup-file-line-numbers)

(defun self/theme--disable-file-line-numbers ()
  "为当前 buffer 关闭行号显示（非编辑型 mode 的阅读视图）。"
  (display-line-numbers-mode -1))

(dolist (hook '(org-mode-hook ghostel-mode-hook term-mode-hook
                              eshell-mode-hook shell-mode-hook
                              dashboard-mode-hook special-mode-hook
                              agent-shell-mode-hook))
  (add-hook hook #'self/theme--disable-file-line-numbers))

(use-package mouse
  :demand t
  ;; `context-menu-mode' 定义在内建库 mouse.el（不存在 context-menu.el，
  ;; 不能按包名 require）；右键菜单只在桌面图形端有入口，TTY 与
  ;; Android 触屏都用不上，故按平台守卫。
  :if (not self:android-p)
  :config
  (context-menu-mode 1))

(global-hl-line-mode 1)


;;; ─── TTY 修饰方向键解码 ──────────────────────────────────────────────

;; 终端模拟器按 xterm 惯例把修饰方向键编码为 `ESC [ 1 ; <mod> <dir>'
;; 形式的 CSI 序列（<mod> = 1 + Shift(1) + Alt(2) + Ctrl(4)，方向码
;; A/B/C/D = 上下右左）。Emacs 只在 TERM 被识别为 xterm 系时才预装这些
;; 解码项；tmux/screen 等 TERM 下序列会以 `M-[ 1 ; 3 D' 这样的原始字节流
;; 到达——M-方向键（切窗口）、C-M-方向键（多光标）等绑定全部落空。
;;
;; `input-decode-map' 是按终端隔离的，daemon 下挂到 `tty-setup-hook' 上，
;; 保证每个新建 TTY client 都拿到解码表；已识别的 xterm 系终端重复定义
;; 无害。

(defun self/theme--tty-decode-modified-arrows ()
  "给当前 TTY 终端补全 xterm 风格修饰方向键解码(input-decode-map)。
覆盖修饰位 Shift/Alt/Ctrl 的全部组合与四个方向。"
  (let ((mods '((2 . "S") (3 . "M") (4 . "M-S") (5 . "C")
                (6 . "C-S") (7 . "C-M") (8 . "C-M-S")))
        (dirs '((?A . "up") (?B . "down") (?C . "right") (?D . "left"))))
    (dolist (dir dirs)
      (dolist (mod mods)
        (define-key input-decode-map
                    (format "\e[1;%d%c" (car mod) (car dir))
                    (kbd (format "%s-<%s>" (cdr mod) (cdr dir))))))))

(add-hook 'tty-setup-hook #'self/theme--tty-decode-modified-arrows)


;;; ─── 终端透明与 Face 样式清洗 ────────────────────────────────────────

;; 终端客户端连接时，清除各个 face 的背景底色（设为 unspecified），让终端
;; 原生透明效果直接透出。样式表的设计要点：
;;
;; - 补充非颜色交互语义：通过粗体与下划线增强选区、高亮行与搜索匹配的
;;   醒目度（终端没有像素级透明度可依赖）。
;; - 负宽边框异常防御：透明背景下清除 `ghostel-fake-cursor' 与
;;   `org-modern-label' 的 `:box' 边框，防止底层重绘时因背景色非法报错。
;; - `self:terminal-block-faces' 给 Org 代码块恢复底色：Modus 主题与
;;   Org 9.8 都不给 `org-block' 族设背景，GUI 靠 org-modern 的 fringe
;;   边框区分代码块，TTY 无 fringe，故用 palette 的 bg-inactive 给整块
;;   一个中性面板；`org-quote' / `org-verse' 继承 `org-block' 自动随之
;;   着色。

(defconst self:terminal-face-emphasis
  '((highlight :underline t)
    (region :underline t :extend nil)
    (secondary-selection :underline t)
    (match :underline t)
    (show-paren-match :weight bold :underline t)
    (show-paren-mismatch :weight bold :underline t)
    (lazy-highlight :underline t)
    (isearch :weight bold :underline t)
    (isearch-fail :weight bold :underline t)
    (line-number-current-line :weight bold)
    (mode-line :box nil :overline t)
    (mode-line-inactive :box nil)
    (tab-line :height 0.95 :box nil)
    (tab-line-tab-current :underline t :weight semi-bold :box nil)
    (tab-line-tab-inactive :box nil)
    (header-line :box nil :underline t)
    (completions-highlight :weight bold :underline t)
    (ghostel-fake-cursor :box nil)
    (org-modern-label :box nil)
    (org-modern-habit :box nil))
  "TTY 透明背景下补充的非颜色交互语义。")

(defconst self:terminal-block-faces
  '(org-block org-block-begin-line org-block-end-line)
  "TTY 上恢复主题底色的代码块 face。")

(defun self/terminal-theme-color (key)
  "返回当前 Modus 主题 palette 中 KEY 对应的颜色,失败时返回 nil。
`modus-themes-get-color-value' 对未知键返回 unspecified 而非抛错，
故只需判 nil/unspecified。"
  (when (fboundp 'modus-themes-get-color-value)
    (let ((color (modus-themes-get-color-value key)))
      (unless (memq color '(nil unspecified))
        color))))

(defun self/theme--apply-terminal-faces (&optional frame)
  "让 TTY FRAME 的所有命名 face 使用终端透明背景(仅真实终端生效,GUI 为 no-op)。
先清 face 背景与反色，再为 `hl-line' 恢复主题柔和背景、为代码块恢复
bg-inactive 面板、按 `self:terminal-face-emphasis' 补非颜色语义；前景色
继续由主题提供（Foot 需 alpha-mode=all 才能让 hl-line 背景半透明）。
仅在真实终端 frame 下生效，GUI 为 no-op；无色能力的终端（daemon 初始帧，
`display-color-cells' 为 0）同样要处理，否则主题彩色 face 无法实现、
redisplay 会报「Invalid face reference」。"
  (condition-case err
      (when (and (not noninteractive)
                 (not (display-graphic-p frame)))
        (let ((tty (or frame (selected-frame)))
              (hl-line-background (self/terminal-theme-color 'bg-dim)))
          (with-selected-frame tty
            (dolist (parameter self:terminal-frame-parameters)
              (unless (eq (car parameter) 'foreground-color)
                (set-frame-parameter tty (car parameter) (cdr parameter))))
            (dolist (face (face-list))
              (set-face-attribute face tty
                                  :background 'unspecified
                                  :inverse-video nil))
            (dolist (entry self:terminal-face-emphasis)
              (when (facep (car entry))
                (apply #'set-face-attribute
                       (car entry) tty (cdr entry))))
            (when (and hl-line-background (facep 'hl-line))
              (set-face-attribute 'hl-line tty
                                  :background hl-line-background
                                  :underline nil
                                  :extend t))
            (when-let* ((block-background
                         (self/terminal-theme-color 'bg-inactive)))
              (dolist (face self:terminal-block-faces)
                (when (facep face)
                  (set-face-attribute face tty
                                      :background block-background
                                      :extend t)))))))
    (error
     (message "self/theme--apply-terminal-faces: %s" (error-message-string err)))))

;; 两个刷新入口按 hook 语义分开：enable-theme-functions 走无条件全量重刷，
;; after-load-functions 走 face 计数门禁——多数 load / require 不定义 face，
;; 计数不变就跳过。两者不能合并：把主题切换也关进门禁会导致换主题后不重刷。

(defvar self/theme--tty-face-count 0
  "上次 TTY 刷新时的 face 总数;只有加载了定义新 face 的文件后才需要重刷。")

(defun self/theme--refresh-terminal-faces (&rest _)
  "重新对所有存活 TTY frame 应用透明背景策略。"
  (unless noninteractive
    (setq self/theme--tty-face-count (length (face-list)))
    (dolist (frame (frame-list))
      (unless (display-graphic-p frame)
        (self/theme--apply-terminal-faces frame)))))

(defun self/theme--refresh-terminal-faces-after-load (_file)
  "包加载引入新 face 时刷新所有 TTY frame。
多数 `load'/`require' 不定义 face,用 face 计数避免每次全量重刷。"
  (when (< self/theme--tty-face-count (length (face-list)))
    (self/theme--refresh-terminal-faces)))

(add-hook 'enable-theme-functions #'self/theme--refresh-terminal-faces)
(add-hook 'after-load-functions #'self/theme--refresh-terminal-faces-after-load)

;; 状态行日志清洗。显示一段 face 属性指向未定义（或当前 frame 实现不了）
;; 的文本时，xfaces.c 的 add_to_log 会经 message 打
;; "Invalid face reference: %s"；状态行的 minibuffer-line 文本正是最容易
;; 碰上的一处（daemon 启动首帧、包刚加载或 face 未实现时），配置侧的非
;; 彩色终端归一化已把成因收窄。`inhibit-message-regexps' 只静音回显、
;; 消息照样写进 *Messages*，所以这里按「格式串 + 参数」双重匹配丢弃；
;; 只认 minibuffer-line 这一个 face 名，其它 Invalid face reference
;; 照常记录。

(defun self/theme--drop-statusline-face-log (orig fmt &rest args)
  "丢弃状态行 face 显示期解析不出来时由 C 层打出的日志(只认 minibuffer-line)。"
  (unless (and (equal fmt "Invalid face reference: %s")
               (eq (car args) 'minibuffer-line))
    (apply orig fmt args)))

(advice-add 'message :around #'self/theme--drop-statusline-face-log)


;;; ─── 窗口分隔线与 Frame 外观 ────────────────────────────────────────

;; 分屏窗口之间的物理细线：GUI 下上下、左右相邻的编辑窗口之间由 1 px 细线
;; 分隔，终端下分隔线宽为 0。
;;
;; 颜色取主题 border 与背景色按 0.65 比例插值重算，与标签栏下缘的横线
;; （0.5）落在同一档浅色上。纯色 border 与正文明度差太大、横贯窗口会很
;; 扎眼；之所以预先加深到 0.65，是因为 1 px 宽度在分数缩放下会被抗锯齿
;; 摊到约 1.75 设备像素、平均覆盖度约八成，颜色相应被冲淡两成。重算挂在
;; enable-theme-functions 上，明暗主题切换后随之更新。

(defun self--hex-channel (hex start)
  "取 #RRGGBB 字符串中 START 起两位十六进制的通道值(0-255)。
self-tabline 的标签下缘横线复用同一对插值函数，故按 AGENTS.md §3
「self-- 是跨模块共享的内部实现」命名，标签栏侧只 declare-function。"
  (string-to-number (substring hex start (+ start 2)) 16))

(defun self--mix-color (front back weight)
  "把颜色 FRONT 按 WEIGHT 混入 BACK(0=纯 BACK)后返回 #RRGGBB。"
  (let (channels)
    (dolist (start '(1 3 5))
      (push (/ (+ (* (self--hex-channel front start) weight)
                  (* (self--hex-channel back start) (- 1 weight)))
               255.0)
            channels))
    (apply #'color-rgb-to-hex (append (nreverse channels) '(2)))))

(defun self/theme--apply-frame-appearance (&optional frame)
  "为 FRAME 应用所有 display-dependent 外观设置。
+ GUI: 字体高度、透明度、buffer 之间分隔线的宽度
+ TTY: 背景透明（清遮挡终端背景的 face 背景）、分隔线宽度清零。
  真彩 TTY 的前景色继续使用当前主题 palette。

只在 `after-make-frame-functions' 中调用（daemon 启动期没有可用屏幕），
非守护进程时由本文件末尾对首个窗口直接调用一次。"
  (condition-case err
      (with-selected-frame (or frame (selected-frame))
        (let ((graphic-p (display-graphic-p)))
          (set-frame-parameter nil 'cursor-type (if graphic-p 'bar 'box))
          (cond (graphic-p
                 (set-face-attribute 'default nil :height self:default-font-height)
                 (set-frame-parameter nil 'alpha-background self:frame-background-opacity)
                 (set-frame-parameter nil 'right-divider-width 1)
                 (set-frame-parameter nil 'bottom-divider-width 1))
                (t
                 (set-frame-parameter nil 'right-divider-width 0)
                 (set-frame-parameter nil 'bottom-divider-width 0)
                 (self/theme--apply-terminal-faces)
                 (xterm-mouse-mode 1)))
          (force-mode-line-update t)))
    (error
     (message "self/theme--apply-frame-appearance: %s" (error-message-string err)))))

(add-hook 'after-make-frame-functions #'self/theme--apply-frame-appearance)
(unless (daemonp)
  (funcall #'self/theme--apply-frame-appearance (selected-frame)))

(setopt window-divider-default-places t
        window-divider-default-right-width 1
        window-divider-default-bottom-width 1)

(defun self/theme--apply-window-divider (&rest _)
  "按当前主题重算 buffer 之间分隔线的颜色(挂在 `enable-theme-functions' 上)。
palette 取不到色时保留既有属性,不改 face。"
  (when-let* ((border (self/terminal-theme-color 'border))
              (bg (self/terminal-theme-color 'bg-main)))
    (set-face-attribute 'window-divider nil
                        :foreground (self--mix-color border bg 0.65))))

(add-hook 'enable-theme-functions #'self/theme--apply-window-divider)


;;; ─── 像素级平滑滚动 ──────────────────────────────────────────────────

;; 启用 Emacs 31 内置的 pixel-scroll-precision-mode 与动能惯性，在触控板与
;; 高精度鼠标滑动时提供丝滑的滚动体验。TTY 下退化为行级滚动，但 GUI client
;; 需要它，故无条件启用。

(setq scroll-conservatively 101
      pixel-scroll-precision-interpolate-page t
      pixel-scroll-precision-use-momentum t)
(pixel-scroll-precision-mode 1)


;;; ─── 颜色方案（Modus 主题）状态与主题应用 ────────────────────────────

;; 浅色主题 modus-operandi-tinted（米白色调温和背景），深色主题
;; modus-vivendi-tinted（柔和舒适的暗色调背景）。
;;
;; 调色板覆盖（Palette Overrides）的理由：
;; - 边缘与行号底色融入：原生 Modus 将 fringe 与未激活行号底色映射为
;;   bg-dim，在 GUI 半透明与背景模糊下这 8 px 宽度会被放大成两侧可见的灰带；
;;   改映射为 bg-main 与正文融为一体。
;; - 代码块底色降噪：bg-prose-block-contents 与 bg-prose-block-delimiter
;;   同样映射到 bg-main。GUI 侧的代码块分组已由缩进竖线与边框清晰表达，
;;   去除多余底色可消除半透明下的噪点；TTY 侧不受影响，由终端透明策略独立
;;   处理。
;; - D-Bus 动态同步：读取 Darkman 暴露在 D-Bus 上的 Mode 属性，并在系统模式
;;   变动时按需切换。

(defcustom self:color-scheme-light-theme 'modus-operandi-tinted
  "浅色模式下加载的主题。"
  :type 'symbol
  :group 'self-theme)

(defcustom self:color-scheme-dark-theme 'modus-vivendi-tinted
  "深色模式下加载的主题。"
  :type 'symbol
  :group 'self-theme)

(defvar self/color-scheme--current-mode nil
  "当前颜色方案模式（`light' 或 `dark'）。")

(defvar self/color-scheme--initialized nil
  "颜色方案模块是否已完成初始化。")

(defconst self:modus-palette-overrides
  '((fringe bg-main)
    (bg-line-number-inactive bg-main)
    (bg-prose-block-contents bg-main)
    (bg-prose-block-delimiter bg-main))
  "四个 Modus 变体共用的 palette 覆盖(单一事实源,理由见上方注释)。")

;; 下面四个变量由 modus-themes 包 defcustom 定义，这里只声明名称供
;; byte-compiler 认识（值在紧随其后的 setq 处赋）。包未安装时 setq 会
;; 自建这些变量，不影响本模块其余部分。
(defvar modus-operandi-palette-overrides)
(defvar modus-operandi-tinted-palette-overrides)
(defvar modus-vivendi-palette-overrides)
(defvar modus-vivendi-tinted-palette-overrides)

(setq modus-operandi-palette-overrides self:modus-palette-overrides
      modus-operandi-tinted-palette-overrides self:modus-palette-overrides
      modus-vivendi-palette-overrides self:modus-palette-overrides
      modus-vivendi-tinted-palette-overrides self:modus-palette-overrides)

(defconst self:color-scheme-dbus-path "/nl/whynothugo/darkman"
  "Darkman D-Bus 对象路径。")

;; 主题应用：加载前先同步 frame-background-mode 并刷新现有 frame——face 的
;; light/dark 变体选择由它驱动，必须赶在 load-theme 求值 face spec 之前；
;; 刷新只在确实要加载主题时做，模式变化会重算 face，随后的 load-theme 经
;; enable-theme-functions 重新套用终端透明等 per-frame 样式。

(defun self/color-scheme--parse-mode (string)
  "把 Darkman 的 \"light\"/\"dark\" 字符串映射为 `light'/`dark' 符号,其余返回 nil。"
  (cond ((equal string "light") 'light)
        ((equal string "dark") 'dark)
        (t nil)))

(defun self/color-scheme--get-from-dbus ()
  "通过 D-Bus 获取当前 Darkman 模式。返回 `light'、`dark' 或 nil。"
  (condition-case err
      (self/color-scheme--parse-mode
       (dbus-get-property
        :session
        "nl.whynothugo.darkman"
        self:color-scheme-dbus-path
        "nl.whynothugo.darkman"
        "Mode"))
    (error
     (message "[color-scheme] D-Bus 获取失败: %s" (error-message-string err))
     nil)))

(defun self/color-scheme--theme-for-mode (mode)
  "返回 MODE(`light' 或 `dark')对应的主题符号,未知 MODE 返回 nil。"
  (cond ((eq mode 'dark) self:color-scheme-dark-theme)
        ((eq mode 'light) self:color-scheme-light-theme)
        (t nil)))

(defun self/color-scheme--load-theme-if-needed (theme)
  "THEME 非 nil 且未启用时加载它,已启用时是 no-op。
先禁用已启用主题再加载,避免主题 face 叠加。"
  (when (and theme
             (not (eq (car custom-enabled-themes) theme)))
    (mapc #'disable-theme custom-enabled-themes)
    (load-theme theme t)
    (message "[color-scheme] 已同步主题: %s" theme)))

(defun self/color-scheme--apply-theme (mode)
  "根据 MODE(`light' 或 `dark')加载对应的主题。
独立实例在 GUI 或至少 256 色的 TTY frame 中加载;daemon 无 frame 时也预载。"
  (setq self/color-scheme--current-mode mode
        frame-background-mode mode)
  (when (or (daemonp) (self/color-scheme--supports-themes-p))
    (mapc #'frame-set-background-mode (frame-list))
    (self/color-scheme--load-theme-if-needed
     (self/color-scheme--theme-for-mode mode))))


;;; ─── D-Bus 监听 ──────────────────────────────────────────────────────

(defvar self/color-scheme--dbus-handler nil
  "D-Bus 信号监听器的注册 ID。")

(defun self/color-scheme--on-darkman-mode-change (mode)
  "Darkman `ModeChanged' 信号回调：MODE 变化时应用对应主题。"
  (let ((new-mode (self/color-scheme--parse-mode mode)))
    (when (and new-mode
               (not (eq new-mode self/color-scheme--current-mode)))
      (message "[color-scheme] Darkman 模式变化: %s" mode)
      (self/color-scheme--apply-theme new-mode))))

(defun self/color-scheme--register-listener ()
  "注册 D-Bus 信号监听器，响应 Darkman 模式变化。"
  (condition-case err
      (unless self/color-scheme--dbus-handler
        (setq self/color-scheme--dbus-handler
              (dbus-register-signal
               :session
               "nl.whynothugo.darkman"
               self:color-scheme-dbus-path
               "nl.whynothugo.darkman"
               "ModeChanged"
               #'self/color-scheme--on-darkman-mode-change))
        (message "[color-scheme] 已注册 D-Bus 监听器"))
    (error
     (message "[color-scheme] 无法注册 D-Bus 信号监听器: %s" (error-message-string err))
     nil)))


;;; ─── Frame 初始化 ────────────────────────────────────────────────────

;; 主题初始化时机按运行模式分流：
;; - daemon：在 daemon 启动阶段初始化。启动时间不敏感，提前支付主题加载与
;;   D-Bus 注册成本。
;; - 独立 Emacs：立即初始化。启动时 selected-frame 已存在。

(defun self/color-scheme--supports-themes-p (&optional frame)
  "FRAME（默认 selected-frame）是否可呈现主题的完整前景 palette。"
  (with-selected-frame (or frame (selected-frame))
    (or (display-graphic-p)
        (and (not noninteractive)
             (>= (display-color-cells) 256)))))

(defun self/color-scheme--init ()
  "初始化颜色方案适配：读取 Darkman D-Bus 模式并应用主题、注册监听器。
D-Bus 不可用时回退 `dark';后续 Darkman 模式变化经信号自动同步。
Android 无会话 D-Bus，跳过读取与监听注册（否则每次启动打一条错误消息）。"
  (let ((initial-mode (if self:android-p
                          'dark
                        (or (self/color-scheme--get-from-dbus)
                            'dark))))
    (self/color-scheme--apply-theme initial-mode)
    (setq self/color-scheme--initialized t)
    (unless self:android-p
      (self/color-scheme--register-listener))))

(defun self/color-scheme--apply-for-frame (&optional frame)
  "在 FRAME 可用时补齐与主题相关的 frame 初始化。
主题是全局状态，不能在每个新 frame 上重复 `load-theme'，否则多 client
几乎同时创建 frame 时容易在 PGTK/GTK 初始化路径中崩溃。"
  (with-selected-frame (or frame (selected-frame))
    (when (self/color-scheme--supports-themes-p)
      (if (not self/color-scheme--initialized)
          (self/color-scheme--init)
        (self/color-scheme--load-theme-if-needed
         (self/color-scheme--theme-for-mode
          self/color-scheme--current-mode))))))

(self/color-scheme--init)
(add-hook 'after-make-frame-functions #'self/color-scheme--apply-for-frame)
(unless (daemonp)
  (funcall #'self/color-scheme--apply-for-frame (selected-frame)))

;; 主题切换后的级联刷新由 enable-theme-functions 驱动（见文件 Commentary
;; 的「GUI / TTY 混合 daemon 约束」一节与上面的 TTY face 刷新入口）。

(provide 'self-theme)
;;; self-theme.el ends here
