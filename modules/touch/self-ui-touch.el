;;; self-ui-touch.el --- 移动端 UI：字体/主题/极简 mode-line/失焦保存 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable
;; Requires: self-glyph, self-touch, self-completion, self-editing, self-session
;; Packages: ef-themes
;;
;; 移植自移动端配置（主题、mode-line 两段从桌面配置简化而来）：
;; · Maple Mono NF CN 主字体（中英等宽 + Nerd 图标字形）
;; · ef-themes + 简化版深浅色状态机（状态文件持久化、跟随系统主题）
;; · mode-line 极简档 + 右端按钮组——右端尾钮是对外发命令的固定出口
;;   （与 tool-bar、modifier-bar 构成触屏三件套），其余模块的
;;   buffer 局部钮表都靠 `self/mode-line--add-local-buttons' 插到它前面
;; · 去 frame 标题（信息由 mode-line 承担）
;; · 移动端数据保全兜底（失焦保存本体已上提 self-session）
;;
;; 与 self-touch / self-completion 的交叉引用都是 declare-function 级的
;; 惰性引用（mode-line 按钮表里的命令，只在用户点击时求值），两个模块
;; 谁先加载都成立，profile 的 require 顺序不必为它们让步。
;;
;; 文件中段「编辑行为」里的基础编辑开关（覆盖选区 / 电配对 / 括号高亮 /
;; CJK 类别折行）与软换行已归 self-editing 唯一声明，本模块只留移动端专属
;; 的行号与锁文件策略。
;;
;; 文件末段「会话持久化」从移动端配置的 misc 段并入——recentf /
;; savehist / saveplace 与上面的兜底手段同属一条数据保全链，拆开反而
;; 不内聚。桌面档的历史持久化归底座层的
;; self-session，两档不共载。

;;; Code:

;; ─── 主字体：Maple Mono NF CN（中英等宽 + Nerd 图标字形） ──────────
;; Android 装到 Emacs home 的 fonts/（sfnt-android 枚举），桌面走
;; fontconfig；未装时 find-font 返回 nil，自动跳过。
;; 字号加大可同步放大 modifier-bar 按钮（其尺寸随 frame 字体）。
(defcustom self/default-font-height 160
  "默认字号（1/10 pt）。加大可同步放大 modifier-bar 按钮。"
  :type 'integer
  :group 'self)

(let ((spec (font-spec :family "Maple Mono NF CN")))
  (when (and (display-graphic-p) (find-font spec))
    (set-face-attribute 'default nil :font spec
                        :height self/default-font-height)))

;; ─── 主题：ef-themes + 简化深浅色状态机 ─────────────────────────────

(defcustom self/color-scheme-light-theme 'ef-cyprus
  "浅色模式下加载的主题。"
  :type 'symbol
  :group 'self)

(defcustom self/color-scheme-dark-theme 'ef-owl
  "深色模式下加载的主题。"
  :type 'symbol
  :group 'self)

(defcustom self/color-scheme-default-mode 'light
  "无状态文件时的默认深浅色模式。"
  :type '(choice (const :tag "浅色" light)
                 (const :tag "深色" dark))
  :group 'self)

(defconst self/color-scheme-state-file
  (expand-file-name "color-scheme-state.el" self:var-directory)
  "颜色方案状态文件路径（目录由 init-basis 定义）。")

(defvar self/color-scheme-current-mode nil
  "当前颜色方案模式（\='light 或 \='dark）。")

(defun self/color-scheme-read-state ()
  "从状态文件读取当前模式，返回 \='light 或 \='dark，不可用时返回 nil。
读侧与 `self/color-scheme-save-state' 的写入格式对称：read 解析
`(setq ...)' 表单，精确取第二元素，不做子串匹配。"
  (condition-case err
      (when (file-exists-p self/color-scheme-state-file)
        (let ((form (with-temp-buffer
                      (insert-file-contents self/color-scheme-state-file)
                      (goto-char (point-min))
                      (read (current-buffer)))))
          ;; 写入侧（save-state）写的是变量**符号**本身，读取侧必须按
          ;; 同一个符号匹配：反引号里的裸符号会被求值成该变量的当前值，
          ;; 一旦 apply-theme 先跑过，两侧就再也对不上。这里把符号绑成
          ;; ,var 再用 eq 比对，读写严格对称且不依赖求值顺序。
          (pcase form
            (`(setq ,var (quote ,mode))
             (and (eq var 'self/color-scheme-current-mode) mode))
            (_ nil))))
    (error
     (message "[color-scheme] 无法读取状态文件: %s" (error-message-string err))
     nil)))

(defun self/color-scheme-save-state (mode)
  "将当前模式 MODE 持久化到状态文件。"
  (condition-case err
      (let ((dir (file-name-directory self/color-scheme-state-file)))
        (unless (file-exists-p dir)
          (make-directory dir t))
        (with-temp-buffer
          (insert ";; color-scheme-state.el -*- lexical-binding: t; -*-\n")
          (insert ";; 自动生成，勿手动修改\n")
          (insert (format "(setq self/color-scheme-current-mode '%s)\n" mode))
          (write-region (point-min) (point-max) self/color-scheme-state-file)))
    (error
     (message "[color-scheme] 无法保存状态文件: %s" (error-message-string err))
     nil)))

(defun self/color-scheme-apply-theme (mode)
  "加载 MODE（\='light 或 \='dark）对应的主题并持久化状态
（用内置 `load-theme'，ef-themes 仅提供主题定义文件）。"
  (setq self/color-scheme-current-mode mode)
  (self/color-scheme-save-state mode)
  (let ((theme (pcase mode
                 ('light self/color-scheme-light-theme)
                 ('dark self/color-scheme-dark-theme))))
    (when (and theme (not (memq theme custom-enabled-themes)))
      ;; custom-theme-p 不适用：ef-themes 加载后所有主题名都被注册
      (mapc #'disable-theme custom-enabled-themes)
      (load-theme theme t))))

(defun self/color-scheme-toggle ()
  "在浅色/深色主题间切换。"
  (interactive)
  (self/color-scheme-apply-theme
   (if (eq self/color-scheme-current-mode 'light) 'dark 'light)))

(defvar toolkit-theme)  ; 内置 frame.el（31+）

;; 系统深浅色跟随（31+，Android 在列）：系统主题应用时 Emacs 设
;; `toolkit-theme' 为 'light/'dark 并跑此 hook；触发时机真机待确认，
;; 不触发则退化为手动 toggle，无副作用
(add-hook 'toolkit-theme-set-functions
          (lambda (theme)
            (self/color-scheme-apply-theme
             (if (eq theme 'dark) 'dark 'light))))

(defun self/color-scheme-init ()
  "初始化：系统主题已报告则跟随，否则读状态文件 → 无则取默认。"
  (self/color-scheme-apply-theme
   (or toolkit-theme
       (self/color-scheme-read-state)
       self/color-scheme-default-mode)))

(use-package ef-themes
  :defer t
  :init
  ;; 主题加载放启动完成后，避免拖慢 init
  (add-hook 'after-init-hook #'self/color-scheme-init))

;; ─── frame 标题：去除（信息由 mode-line 承担） ─────────────────────

(setq frame-title-format '(""))

;; ─── mode-line：极简档 ─────────────────────────────────────────────

;; 触屏无新手引导，抑制启动屏
(setq inhibit-startup-screen t)

;; echo area 按需伸缩，避免底部空行残留
(setq resize-mini-windows 'grow-and-shrink)

(defun self/mode-line--percent ()
  "当前位置百分比（%p/%P 在顶底部会显示 Top/Bottom/All）。"
  (format "%d%%%%"
          (floor (* 100.0 (point)) (max (point-max) 1))))

;; 行首放关闭当前 buffer 按钮（tap=mouse-1，与工具栏同机制）。
;; 缓冲区切换也放 mode-line：点击时所属窗口被选中，目标窗口正确。
(declare-function consult-buffer "consult")

(defun self/mode-line-switch-buffer ()
  "在当前窗口切换缓冲区。"
  (interactive)
  (consult-buffer))

(declare-function self/which-key-next-page "self-completion")
(declare-function self/glyph "self-glyph")
(declare-function consult-org-heading "consult")
(declare-function consult-imenu "consult")
(declare-function consult-line "consult")
(declare-function self/touch-show-keyboard "self-touch")

(defun self/mode-line-navigate ()
  "当前文档内导航：org 大纲 / epub 章节 / 其余本页搜索。"
  (interactive)
  (cond
   ((derived-mode-p 'org-mode) (consult-org-heading))
   ((derived-mode-p 'nov-mode) (consult-imenu))
   (t (consult-line))))

(defun self/mode-line-execute-command ()
  "执行 M-x；触屏无物理键盘，先主动唤出虚拟键盘。"
  (interactive)
  (self/touch-show-keyboard)
  (call-interactively #'execute-extended-command))

;; ─── 右端按钮组：数据表驱动 ────────────────────────────────────────
;; 不用官方 `mode-line-format-right-align'：它以 right-fringe 为参照，
;; 右 fringe 非零时尾钮越出文本区右缘，落在 fringe 上的 tap 不派发
;; （真机 × 右侧约 1/4 不可点）。改自算弹性空格，宽度按当前宽度表
;; （GUI 的 NF 字形 advance 恰 1 列，仅 NF tty 校验模式置 2）。

(defconst self/mode-line--right-buttons
  '(("\uF120" "命" "执行所有命令 (M-x)" self/mode-line-execute-command)
    ("\uF002" "寻" "文档内导航（org 大纲 / epub 章节 / 本页搜索）"
     self/mode-line-navigate)
    ("\uF0A9" "»" "which-key 下一页" self/which-key-next-page)
    ("\uF0EC" "换" "切换缓冲区" self/mode-line-switch-buffer)
    ("\uF00D" "×" "关闭当前 buffer 及其窗口" kill-buffer-and-window))
  "右端按钮表：(NF 字形 tty 回退 帮助 命令)，从左到右。
首项 M-x 在 dired 下隐藏，见 `self/mode-line--buttons'。")

(defun self/mode-line--button (spec &optional pad)
  "按 SPEC（字形 回退 帮助 命令）构造单颗按钮，前导 PAD 列空格（默认 2）。"
  ;; SPEC 是 `self/mode-line--right-buttons' 表里的一项，四个位置固定：
  ;; 0 字形 / 1 tty 回退 / 2 help-echo / 3 命令。表是本文件里的字面量常量，
  ;; 缺项时 nil 会一路传下去（回退缺失、命令缺失），故不必再判长度。
  (let ((glyph (nth 0 spec))
        (fallback (nth 1 spec))
        (help (nth 2 spec))
        (command (nth 3 spec)))
    (propertize
     (concat (make-string (or pad 2) ?\s) (self/glyph glyph fallback))
     'local-map (make-mode-line-mouse-map 'mouse-1 command)
     'mouse-face 'highlight
     'help-echo help)))

(defun self/mode-line--add-local-buttons (fn)
  "buffer-local：在右端钮组前插入 (:eval (FN)) 按钮串（幂等，
mode 重复激活不会叠加同一钮组）。"
  (let* ((fmt (default-value 'mode-line-format))
         (pos (seq-position fmt '(:eval (self/mode-line--right-part)))))
    (when (and pos (not (member `(:eval (,fn)) mode-line-format)))
      (setq-local mode-line-format
                  (append (seq-take fmt pos)
                          (list `(:eval (,fn)))
                          (seq-drop fmt pos))))))

(defcustom self/mode-line-edge-padding 1
  "mode-line 左右两侧边距（列）。"
  :type 'integer
  :group 'self)

(defun self/mode-line--buttons ()
  "右端按钮组串。dired 下省去首项 M-x：该场景局部文件操作钮已占满
宽度（40 列下仅余 2 列），且文件管理时 M-x 需求低。"
  (mapconcat #'self/mode-line--button
             (if (derived-mode-p 'dired-mode)
                 (cdr self/mode-line--right-buttons)
               self/mode-line--right-buttons)
             nil))

(defun self/mode-line--right-part ()
  "mode-line 右端整体：弹性空格 + 按钮串。
一次构造按钮串并复用其宽度——弹性空格与按钮串原先是两个 :eval，
每次重绘会把整组按钮（含各自新建的 mouse-map keymap）构造两遍。

弹性空格的对齐说明：官方 `mode-line-format-right-align' 以 right-fringe
（fringe 外缘）为参照，右 fringe 非零的环境里按钮组整体多移一个 fringe
宽，尾钮单元越出文本区右缘、落在 fringe 上的 tap 不派发（真机 × 右侧
约 1/4 不可点）；改以 `right'（文本区右缘）为参照，宽度按当前宽度表
（GUI 与 advance 一致，NF 校验模式已同步置 2）。"
  (let ((btns (self/mode-line--buttons)))
    (concat
     (propertize
      " " 'display
      `(space . (:align-to
                 (- right ,(+ (string-width btns)
                              self/mode-line-edge-padding)))))
     btns)))

(defun self/mode-line--mode-name ()
  "mode-name，超 12 列截断（窄屏防挤出右端按钮）。"
  (truncate-string-to-width (format-mode-line mode-name)
                            12 nil nil "…"))

(defun self/mode-line-debug ()
  "弹出 mode-line 排版诊断（窗宽/列宽/字形像素），真机排障取证。"
  (interactive)
  (let ((buf (get-buffer-create "*mode-line 诊断*")))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format
        "window: %d 列 / %d px   frame-char-width: %d px\n\
fringe 左右(px): %S\n\
string-pixel-width: a=%d 中=%d ·=%d ●=%d F002=%d F00D=%d\n\
string-width: F002=%S F00D=%S ·=%S ●=%S\n\
右组串: %S\n\
右组串宽(列): %S\n\
mode-line 渲染串宽(列): %S"
        (window-total-width) (window-pixel-width) (frame-char-width)
        (butlast (window-fringes) 3)
        (string-pixel-width "a") (string-pixel-width "中")
        (string-pixel-width "·") (string-pixel-width "●")
        (string-pixel-width "\uF002") (string-pixel-width "\uF00D")
        (string-width "\uF002") (string-width "\uF00D")
        (string-width "·") (string-width "●")
        (self/mode-line--buttons)
        (string-width (self/mode-line--buttons))
        (string-width (format-mode-line mode-line-format))))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;; 左段：修改标记 mode-name 百分比；右端按钮组从左到右：
;; 寻 导航、» 翻页、换 切缓冲区、× 关闭
(setq-default mode-line-format
              '("%e"
                (:eval (make-string self/mode-line-edge-padding ?\s))
                (:eval (if (buffer-modified-p) "●" "·"))
                " "
                (:eval (self/mode-line--mode-name))
                "  "
                (:eval (self/mode-line--percent))
                (:eval (self/mode-line--right-part))))

;; ─── 编辑行为（自桌面配置移植）───────────────────────────────────────
;; 覆盖选区 / 电配对 / 括号高亮 / CJK 类别折行（word-wrap-by-category）
;; 四处基础编辑开关统一在 self-editing 声明——三档都要，本模块不再重复
;; 设点（否则两处取值漂移时无从判断哪份生效）。
;;
;; 长文档滚动更跟手（fast-but-imprecise-scrolling）属进程级环境变量，
;; 已上提到 core/self-lib.el，三档一次设好。
;;
;; org 目录在 Syncthing 共享存储上：.# 锁文件与 #file# auto-save 文件会
;; 被同步成各端垃圾；丢数据风险由失焦自动保存兜底（见下）
(setq create-lockfiles nil
      auto-save-default nil)

;; ─── 行号：编辑区小号行号 ───────────────────────────────────────────
;; 软换行（global-visual-line-mode）不在这里：它依赖平台——触屏全局长行
;; 必须物理折行，桌面则按窗口宽度折行，两套策略统一在 self-editing 的
;; `(if self:android-p …)' 分支里声明。

;; 行号只加在编辑类 buffer（prog/text/org）
(dolist (hook '(prog-mode-hook text-mode-hook org-mode-hook))
  (add-hook hook #'display-line-numbers-mode))
(setq-default display-line-numbers-width 2) ; 定宽 2 位，行号窄不挤
(set-face-attribute 'line-number nil :height 0.8)
(set-face-attribute 'line-number-current-line nil :height 0.8)

;; ─── 移动端数据保全兜底 ────────────────────────────────────────────
;;
;; 失焦保存的机制本体（空闲 1s 保存改过的本地文件 buffer）统一在
;; self-session 声明——三档共用，本模块只声明不重复定义。
;;
;; 下面两项是**移动端专属兜底**，不上提到共享模块：Android 后台随时可能
;; 被系统杀掉进程，kill-emacs-hook 不执行、after-focus-change-function 在
;; Android 端口的触发也未证实，故需要更「笨」的地板手段。

(declare-function self/user-file-buffer-p "self-session"
  "当前 buffer 是否为可保存的本地用户文件 buffer。")

(declare-function recentf-save-list "recentf")
;; 下面整个 Android 分支在 byte-compile 时被跳过，其中的 defun 不会被
;; 登记，故对分支内的互调显式声明。
(declare-function self/recentf-save "self-ui-touch")
(declare-function self/save-buffer-and-recentf "self-ui-touch")

(when self:android-p
  ;; 访问文件定期真保存：直写访问文件、无 #file# 垃圾。30s 定时器是 FUSE
  ;; 共享存储上写频率的保守取值，代价是被杀时最多丢 30s 编辑。
  (setq auto-save-visited-interval 30)
  (auto-save-visited-mode 1)

  ;; 持久化 recentf 列表：后台被杀前由显式保存点触发。
  (defun self/recentf-save ()
    "把 recentf 列表立即落盘。"
    (when (bound-and-true-p recentf-mode)
      (recentf-save-list)))

  (defun self/save-buffer-and-recentf ()
    "保存当前 buffer 并持久化 recentf 列表（tool-bar 保存按钮用）。
交互命令：M-x self/save-buffer-and-recentf，也被 tool-bar 的「存」钮绑定。"
    (interactive)
    (save-buffer)
    (self/recentf-save)))

;; ─── 会话持久化（从移动端配置的 misc 段并入本模块） ─────────────────
;; 与上面的失焦保存同属一条链：状态文件统一落 `self:var-directory'
;; （XDG state 语义，由 core 定义）。Android 后台被杀时 kill-emacs-hook
;; 不执行，故 recentf 除显式保存点外再叠加内置自动保存定时器兜底，
;; saveplace 同用定时器。
;; 桌面档的历史持久化归 self-session（底座层），本档由本模块承担，
;; 两档不共载，无重复设点。

(use-package recentf
  :config
  ;; 默认值 mode 会在 recentf-mode 开启时立即对全表逐条 file-readable-p；
  ;; 最近文件多在 FUSE 共享存储，启动期百次级系统调用阻塞首屏，改为空闲时清理
  (setq recentf-auto-cleanup 'never)
  (recentf-mode)
  (run-with-idle-timer 5 nil #'recentf-cleanup)
  :custom
  (recentf-save-file (expand-file-name "recentf" self:var-directory))
  (recentf-max-saved-items 100)
  (recentf-autosave-interval 300))

(use-package savehist
  :init
  (savehist-mode)
  :custom
  (savehist-file (expand-file-name "history" self:var-directory)))

(use-package saveplace
  :init
  (save-place-mode)
  :custom
  (save-place-file (expand-file-name "places" self:var-directory))
  (save-place-autosave-interval 300))

(provide 'self-ui-touch)
;;; self-ui-touch.el ends here
