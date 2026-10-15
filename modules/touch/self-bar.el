;;; self-bar.el --- 官方 tool-bar：全局命令按钮（Papirus 图标，Android 底部） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable
;; Requires: self-glyph, self-ui-touch, self-touch, self-org
;; Packages: 无
;;
;; 移植自移动端配置。全局命令按钮由官方 tool-bar 承载：Android 底部
;; （thumb 区），按钮触控面积用 margin 放大。
;; 图标 = Papirus symbolic 矢量（data/icons/*.svg，GPL-3.0，`just
;; icons' 重建）：SVG 直渲任意缩放，加载时把 ColorScheme-Text 的 CSS
;; 色替换为当前主题色（深浅色各自 defcustom）；无 librsvg 的构建
;; 回退 72px 中灰 PNG。资产与按钮名的对照见 data/icons/README.md。
;;
;; 按钮管线：`self/bar--add-button' 逐颗写入 `tool-bar-map'，
;; `self/bar--install' 整体重建；主题切换时 advice 钩子按新色重装。

;;; Code:

(defcustom self/bar-icon-height 48
  "tool-bar 图标显示高度（像素）。SVG 矢量任意缩放；PNG 兜底资产为 2× 超采样。"
  :type 'integer
  :group 'self)

(defcustom self/bar-button-margin 6
  "tool-bar 按钮边距（触控 padding，像素）。"
  :type 'integer
  :group 'self)

(defcustom self/bar-icon-color-light "#3d3d3d"
  "浅色主题下的图标色（Papirus symbolic 重着色目标）。"
  :type 'string
  :group 'self)

(defcustom self/bar-icon-color-dark "#c8c8c8"
  "深色主题下的图标色（Papirus symbolic 重着色目标）。"
  :type 'string
  :group 'self)

(defvar self/color-scheme-current-mode)  ; 定义在 self-ui-touch
(defvar image-load-path)  ; image.el，未加载时 void，需先声明避免启动崩
(declare-function self/color-scheme-apply-theme "self-ui-touch")
(declare-function self/color-scheme-toggle "self-ui-touch")

(defun self/bar--icon-color ()
  "当前主题对应的图标色（主题未定时按浅色）。"
  (if (eq self/color-scheme-current-mode 'dark)
      self/bar-icon-color-dark
    self/bar-icon-color-light))

(defun self/bar--image (key)
  "构造 KEY 按钮的图标图像：SVG 重着色直渲优先，PNG 兜底。"
  (self/icon-asset (symbol-name key) nil self/bar-icon-height
                     (self/bar--icon-color)))

(declare-function self/save-buffer-and-recentf "self-ui-touch")
(declare-function self/inbox-quick-capture "self-org")
(declare-function self/icon-asset "self-glyph")
(declare-function self/touch-toggle-modifier-bar "self-touch")
(declare-function self/touch-find-file "self-touch")
(declare-function self/touch-copy "self-touch")
(declare-function self/touch-cut "self-touch")
(declare-function self/touch-search "self-touch")
(declare-function self/touch-open-config "self-touch")

(defun self/bar--add-button (key label command help)
  "向 `tool-bar-map' 添加使用 data/icons/<KEY> 图标的按钮。"
  (define-key tool-bar-map (vector key)
    `(menu-item ,label ,command
                :help ,help
                :image ,(self/bar--image key))))

(defvar self/bar--installed-color nil
  "上次安装按钮时的图标色（色未变的重装直接跳过）。")

(defun self/bar--install ()
  "安装底部 tool-bar 命令按钮（Android 启动时调用）。"
  ;; 主题加载后 advice 会按新色重装一次；色相同则跳过（省一遍 SVG 读取）
  (let ((color (self/bar--icon-color)))
    (unless (equal color self/bar--installed-color)
      (setq self/bar--installed-color color)
      ;; 底部 tool-bar 须设 frame parameter（bug#64174），三处同设覆盖当前与后续 frame
      (setq tool-bar-position 'bottom)
      (set-frame-parameter nil 'tool-bar-position 'bottom)
      (add-to-list 'default-frame-alist '(tool-bar-position . bottom))

      ;; 按钮过小是 Android 已知缺陷（margins 不随密度缩放），边距作触控 padding 单独调
      (setq tool-bar-button-margin self/bar-button-margin)

      ;; image-load-path 须在 find-image 调用前就位，early-init 禁了 package.el 时 image 特性可能未加载
      (require 'image)
      (add-to-list 'image-load-path
                   (expand-file-name "data/icons" user-emacs-directory))

      ;; 按钮表（10 钮单行）：首位 = modifier-bar 显隐开关
      (setq tool-bar-map (make-sparse-keymap))
      (self/bar--add-button 'modbar "修"
                              #'self/touch-toggle-modifier-bar
                              "显示/隐藏修饰键栏")
      (self/bar--add-button 'open "开" #'self/touch-find-file
                              "打开文件（默认共享存储根）")
      (self/bar--add-button 'save "存" #'self/save-buffer-and-recentf
                              "保存并记录最近文件")
      (self/bar--add-button 'copy "复" #'self/touch-copy "复制选区/当前行")
      (self/bar--add-button 'paste "贴" #'yank "粘贴 (C-y)")
      (self/bar--add-button 'cut "剪" #'self/touch-cut "剪切选区/当前行")
      (self/bar--add-button 'search "搜" #'self/touch-search
                              "搜索（rg 或当前缓冲区）")
      (self/bar--add-button 'theme "色" #'self/color-scheme-toggle
                              "切换深浅色主题")
      (self/bar--add-button 'config "配" #'self/touch-open-config
                              "打开配置文件夹（dired）")
      (self/bar--add-button 'quick "速" #'self/inbox-quick-capture
                              "剪贴板一键速存到 inbox")
      ;; keymap 按插入逆序渲染，反转一次使显示顺序 = 定义顺序（修=最左）
      (setq tool-bar-map (cons 'keymap (reverse (cdr tool-bar-map))))
      (tool-bar-mode 1))))

(when self:android-p
  (self/bar--install)
  ;; 挂在被调方而不是调用方：套主题的入口不止一处（切换命令、D-Bus 回调、
  ;; 启动时的初始套用），逐个调用点包一层必漏。装法是整个重建 tool-bar 而
  ;; 非改图标的 fill 属性——SVG 图标的着色信息在文件字节里，重着色等于重写
  ;; 资源，`self/bar--install' 才能拿到新主题的那一份。
  ;; `:after'：不关心 apply-theme 的返回值，装完就算完。
  (advice-add 'self/color-scheme-apply-theme :after
              (lambda (&rest _)
                (when (display-graphic-p)
                  (self/bar--install)))))

(provide 'self-bar)
;;; self-bar.el ends here
