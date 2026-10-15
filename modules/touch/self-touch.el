;;; self-touch.el --- 触屏层：官方 modifier-bar + 触屏编辑命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable
;; Requires: self-glyph, self-ui-touch
;; Packages: expreg
;;
;; 移植自移动端配置。交互组件全部用官方宿主：
;; · 修饰键 → 官方 modifier-bar（tap 后下一个输入带修饰）
;; · 全局命令按钮 → 官方 tool-bar（self-bar.el 安装，底部）
;; · buffer/窗口控制 → mode-line（self-ui-touch.el）
;;
;; 本模块还提供两处供其他模块复用的触屏基建：widget 是/否确认面板
;; `self/touch-confirm'（替代键盘 y-or-n）与 dired 触屏改造。
;;
;; 加载顺序：本模块必须先于 self-org——org 的操作面板直接
;; `define-derived-mode' 自 `self/touch-confirm-mode'。反向的
;; `self:org-directory' 只是在 `self/touch-search--dir' 里惰性读取，
;; 用就近 `defvar' 声明即可（两模块同档共载，不构成 require 依赖）。

;;; Code:

(declare-function dashboard-open "dashboard")
(declare-function dired-hide-details-mode "dired")
(declare-function dired-mouse-find-file "dired")
(declare-function self/icon-asset "self-glyph")
(declare-function self/mode-line--button "self-ui-touch")
(declare-function self/mode-line--add-local-buttons "self-ui-touch")
(defvar dired-mode-map)
(defvar self:org-directory)

;; ─── 复制 / 剪切：有选区作用于选区，无选区作用于当前行 ─────────────
;; 无选区时整行操作更符合触屏直觉。

(defun self/touch-copy ()
  "复制：有选区复制选区，否则复制当前行。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (line-end-position))))
    (copy-region-as-kill beg end)
    (message "已复制%s" (if regionp "选区" "当前行"))))

(defun self/touch-cut ()
  "剪切：有选区剪切选区，否则剪切当前行（连换行整行消失）。"
  (interactive)
  (let* ((regionp (use-region-p))
         (beg (if regionp (region-beginning) (line-beginning-position)))
         (end (if regionp (region-end) (progn (forward-line 1) (point)))))
    (kill-region beg end)
    (message "已剪切%s" (if regionp "选区" "当前行"))))

;; 搜索入口：rg 可用走 consult-ripgrep，缺失降级 consult-line
(declare-function consult-ripgrep "consult")
(declare-function consult-line "consult")

;; 共享存储根目录，在本文件末尾的 Android 分支里 defconst。byte-compile 时
;; 该分支被跳过，不在此声明就会误报「引用自由变量」。
(defvar self/touch-storage-root)
(defun self/touch-search--dir ()
  "rg 检索的默认目录：非文件 buffer 从共享存储根继承时改落 org 根
（全盘 rg 分钟级；dired 与文件 buffer 保持各自目录）。"
  (if (and (not buffer-file-name)
           (not (derived-mode-p 'dired-mode))
           (equal default-directory self/touch-storage-root))
      self:org-directory
    default-directory))

(defun self/touch-search ()
  "搜索。rg 可用时全文检索（非文件 buffer 落 org 根），否则检索当前缓冲区。"
  (interactive)
  (if (executable-find "rg")
      (let ((default-directory (self/touch-search--dir)))
        (call-interactively #'consult-ripgrep))
    (call-interactively #'consult-line)))

;; ─── 撤销/重做键位（CUA 惯例，modbar 可达：修→Ctrl→z） ────────────
;; C-z 原绑 suspend-frame：GUI 下图标化 frame、Android 下无意义。
;; undo-only 连按到最早即报错，不会像 undo 那样反向进入重做。

(define-key global-map (kbd "C-z") #'undo-only)
(define-key global-map (kbd "C-S-z") #'undo-redo)

;; ─── 语义扩选（expreg）：「选」钮连点词→句→段逐级扩大选区 ──────────
;; 长按选词已由官方 touch-screen-word-select 覆盖；扩选补「词以上」的
;; 层级段，是触屏选中正文的主要途径（替代键盘的 mark-sexp/paragraph）。

(use-package expreg
  :defer t
  :commands (expreg-expand expreg-contract))

(defconst self/expreg--buttons
  '(("\uF065" "选" "扩大选区：连点逐级 词→句→段（expreg）" expreg-expand))
  "可编辑 buffer mode-line 局部钮表：(NF 字形 tty 回退 帮助 命令)。")

(defun self/expreg--mode-line-buttons ()
  "expreg 钮串。"
  (mapconcat #'self/mode-line--button self/expreg--buttons nil))

(defun self/expreg--setup-mode-line ()
  "可编辑 buffer：右端钮组前插入「选」钮。
org 跳过：其「作 选」钮组由 self-org 的 org-mode-hook 一并注入
（org 经 outline←text 链也会触发本 hook，不跳则「选」重复）。"
  (unless (derived-mode-p 'org-mode)
    (self/mode-line--add-local-buttons #'self/expreg--mode-line-buttons)))

;; org ← outline ← text、markdown/gfm ← text、配置等代码 ← prog
(add-hook 'text-mode-hook #'self/expreg--setup-mode-line)
(add-hook 'prog-mode-hook #'self/expreg--setup-mode-line)

;; ─── 触屏确认面板（widget 是/否，替代键盘 y-or-n） ─────────────────

(defvar self/touch-confirm-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'widget-button-click)
    (define-key map [touchscreen-begin] #'widget-button-click)
    map))

(define-derived-mode self/touch-confirm-mode special-mode "确认"
  "触屏确认面板。"
  (setq-local touch-screen-display-keyboard nil))

(defun self/touch-confirm (title action)
  "当前窗弹确认面板：TITLE 提示，点「确认」执行 ACTION（零参函数）。"
  (switch-to-buffer (get-buffer-create "*确认*"))
  (self/touch-confirm-mode)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert "\n  " (propertize title 'face 'bold) "\n\n  ")
    (widget-create 'item
                   :tag " 确认 "
                   :action (lambda (&rest _) (kill-buffer) (funcall action))
                   :button-face 'bold
                   :mouse-face 'highlight
                   :button-prefix "" :button-suffix ""
                   :format "%[%t%]")
    (insert "    ")
    (widget-create 'item
                   :tag " 取消 "
                   :action (lambda (&rest _) (kill-buffer))
                   :button-face 'shadow
                   :mouse-face 'highlight
                   :button-prefix "" :button-suffix ""
                   :format "%[%t%]")
    (goto-char (point-min))))

;; ─── modifier-bar 开关 / 打开配置（tool-bar 首尾按钮的命令） ────────

(defun self/touch-toggle-modifier-bar ()
  "显示/隐藏官方修饰键栏。"
  (interactive)
  (if (fboundp 'modifier-bar-mode)
      (modifier-bar-mode 'toggle)
    (message "本 Emacs 无 modifier-bar（需 Android 官方构建）")))

;; ─── modifier-bar 追加 Tab/ESC 按钮 ────────────────────────────────
;; 按钮集合即 secondary-tool-bar-map（Emacs 30 通用机制，可整体重建）；
;; TAB/ESC 非修饰键，塞进 unread-command-events 即等同物理按键。

(defun self/modbar-tab ()  "发送 TAB 键（等同物理键盘 Tab）。"
  (interactive)
  (setq unread-command-events (list ?\t)))

(defun self/modbar-esc ()
  "发送 ESC 键（取消补全/前缀键等）。"
  (interactive)
  (setq unread-command-events (list ?\e)))

(defun self/modbar--setup ()
  "整套重建 modifier-bar：六修饰键 + Tab/ESC 统一为文字徽章风格
（官方原图是 35×19 PBM 徽章，风格不搭）。
`modifier-bar-mode' 每次开启都会重置该 map，须在其后调用。"
  (when (and (bound-and-true-p modifier-bar-mode)
             (fboundp 'modifier-bar-available-p))
    (setq secondary-tool-bar-map
          `(keymap
            (control menu-item "Control Key" event-apply-control-modifier
                     :help "Add Control modifier to the following event"
                     :image ,(self/icon-asset "control" t)
                     :enable (modifier-bar-available-p 'control))
            (shift menu-item "Shift Key" event-apply-shift-modifier
                   :help "Add Shift modifier to the following event"
                   :image ,(self/icon-asset "shift" t)
                   :enable (modifier-bar-available-p 'shift))
            (meta menu-item "Meta Key" event-apply-meta-modifier
                  :help "Add Meta modifier to the following event"
                  :image ,(self/icon-asset "meta" t)
                  :enable (modifier-bar-available-p 'meta))
            (alt menu-item "Alt Key" event-apply-alt-modifier
                 :help "Add Alt modifier to the following event"
                 :image ,(self/icon-asset "alt" t)
                 :enable (modifier-bar-available-p 'alt))
            (super menu-item "Super Key" event-apply-super-modifier
                   :help "Add Super modifier to the following event"
                   :image ,(self/icon-asset "super" t)
                   :enable (modifier-bar-available-p 'super))
            (hyper menu-item "Hyper Key" event-apply-hyper-modifier
                   :help "Add Hyper modifier to the following event"
                   :image ,(self/icon-asset "hyper" t)
                   :enable (modifier-bar-available-p 'hyper))
            (tab menu-item "TAB Key" self/modbar-tab
                 :help "发送 TAB 键"
                 :image ,(self/icon-asset "tab" t))
            (esc menu-item "ESC Key" self/modbar-esc
                 :help "发送 ESC 键"
                 :image ,(self/icon-asset "esc" t))))
    ;; 重建后刷掉 tool-bar 键映射缓存（按 map 身份哈希缓存）
    (when (fboundp 'tool-bar--flush-cache)
      (tool-bar--flush-cache))
    (force-mode-line-update t)))

(defun self/touch-open-config ()
  "打开配置所在的文件夹（dired）。"
  (interactive)
  (dired user-emacs-directory))

(defconst self/touch-storage-root "/storage/emulated/0/"
  "共享存储根（Android 用户数据区，= /sdcard）。")

(defun self/touch-find-file ()
  "打开文件：默认落点强制为共享存储根。
启动期 buffer 在 setq-default 前已持有 ~，须显式绑定。"
  (interactive)
  (let ((default-directory
          (if (file-directory-p self/touch-storage-root)
              self/touch-storage-root
            default-directory)))
    (call-interactively #'find-file)))

(defun self/touch-no-keyboard ()
  "buffer-local 关闭 tap 弹虚拟键盘（展示型 buffer 用）。"
  (setq-local touch-screen-display-keyboard nil))

(defun self/touch-show-keyboard ()
  "主动唤出系统虚拟键盘（无软键盘的平台为空操作）。"
  (when (fboundp 'frame-toggle-on-screen-keyboard)
    (frame-toggle-on-screen-keyboard (selected-frame) nil)))

;; ─── 存储权限（App 常规首启授权流） ──────────────────────────────
;; 官方把未授权提示挂在启动屏（android-before-splash-screen），本配置
;; 抑制启动屏改由 dashboard 承接（self-dashboard.el 警示行）；此处只
;; 提供谓词与请求入口。

(declare-function android-external-storage-available-p "androidfns.c")
(declare-function android-display-storage-permission-popup "android-win")

(defun self/android-storage-granted-p ()
  "Emacs 是否已能访问外部存储（/sdcard POSIX 直读写前提）。
无查询接口的平台（桌面构建）视为已授予。"
  (if (fboundp 'android-external-storage-available-p)
      (android-external-storage-available-p)
    t))

(defun self/android-request-storage-access ()
  "弹出官方存储权限面板（授予「所有文件访问」或按目录授权）。"
  (interactive)
  (if (fboundp 'android-display-storage-permission-popup)
      (android-display-storage-permission-popup)
    (message "本 Emacs 无 Android 权限面板（非 Android 构建）")))

;; dired 窄屏精简：隐藏权限/属主/大小/时间细节列，只留文件名
;;（完整 -l 格式 60+ 列，手机屏文件名必然折行）
(add-hook 'dired-mode-hook #'dired-hide-details-mode)

;; ─── dired 触屏操作：改名/删除走 minibuffer 点选，新建直接输入 ────
;; dired 里 tap 即打开文件，无「只选中不打开」交互；操作对象改由
;; minibuffer 补全列表（vertico 点选）指定。

(declare-function dired-revert "dired")
(declare-function dired-create-empty-file "dired")
(declare-function dired-create-directory "dired")
(declare-function dired-current-directory "dired")

(defun self/dired-touch-rename ()
  "重命名：点选文件 → 输入新名。"
  (interactive)
  (let* ((dir (dired-current-directory))
         (old (read-file-name "重命名（点选文件）: " dir nil t))
         (new (read-file-name "新名字: " dir nil nil
                              (file-name-nondirectory old))))
    (unless (equal old new)
      (rename-file old new)
      (dired-revert))))

(defun self/dired-touch-delete ()
  "删除：点选文件 → 确认面板 → 删除。"
  (interactive)
  (let* ((dir (dired-current-directory))
         (file (read-file-name "删除（点选文件）: " dir nil t)))
    (if (file-directory-p file)
        (message "暂不支持删除目录")
      (self/touch-confirm
       (format "删除 %s ？" (file-name-nondirectory file))
       (lambda ()
         (delete-file file)
         (dired-revert))))))

(defun self/dired--op-buttons ()
  "dired 文件操作钮串：改名/删除/建文件/建目录。
四钮并排共用统一构造入口，前导 1 列保持紧凑间距。"
  (concat
   (self/mode-line--button (list "\uF304" "改" "重命名（点选文件）"
                                   #'self/dired-touch-rename)
                             1)
   (self/mode-line--button (list "\uF1F8" "删" "删除（点选文件）"
                                   #'self/dired-touch-delete)
                             1)
   (self/mode-line--button (list "\uF15B" "文" "新建文件"
                                   #'dired-create-empty-file)
                             1)
   (self/mode-line--button (list "\uF07B" "夹" "新建目录"
                                   #'dired-create-directory)
                             1)))

(defun self/dired-setup-mode-line ()
  "dired buffer：mode-line 右端钮组前插入文件操作钮。"
  ;; mode-name 压缩（默认 \"Dired by name\" 太占宽，窄屏挤出按钮）
  (setq-local mode-name "Dired")
  (self/mode-line--add-local-buttons #'self/dired--op-buttons))

(add-hook 'dired-mode-hook #'self/dired-setup-mode-line)

;; agenda 条目 tap（mouse-2）= 定位行 + 跳转源条目（编辑管理在 Orgzly，
;; Emacs 侧只读查看）
(defvar org-agenda-mode-map)  ; org-agenda.el
(declare-function org-agenda-switch-to "org-agenda")
(with-eval-after-load 'org-agenda
  (define-key org-agenda-mode-map [mouse-2]
    (lambda (e)
      "tap 条目行跳转源条目。"
      (interactive "e")
      (posn-set-point (event-start e))
      (org-agenda-switch-to))))

;; ─── Android 触屏特化 ───────────────────────────────────────────────

(when self:android-p
  ;; 打开文件/文件夹的默认落点 = 共享存储根（授权「所有文件访问」后
  ;; 可读写；文件 buffer 仍默认到自身所在目录，行为不变）
  (when (file-directory-p "/storage/emulated/0/")
    (setq-default default-directory "/storage/emulated/0/")
    ;; 启动期 buffer 已持有旧值，补齐局部值
    (dolist (buf (buffer-list))
      (unless (buffer-local-value 'buffer-file-name buf)
        (with-current-buffer buf
          (setq default-directory "/storage/emulated/0/")))))

  ;; 触屏选项：tap 任意处可唤出系统虚拟键盘
  (setq touch-screen-display-keyboard t
        touch-screen-preview-select t
        touch-screen-word-select t
        touch-screen-extend-selection t)

  ;; 展示型 read-only buffer 内 tap 也弹键盘，逐 buffer 停用
  (dolist (hook '(dashboard-mode-hook eww-mode-hook nov-mode-hook
                   Info-mode-hook help-mode-hook
                   org-agenda-mode-hook dired-mode-hook))
    (add-hook hook #'self/touch-no-keyboard))

  ;; dired tap 文件名（转 mouse-2）默认 other-window 打开会分屏，
  ;; 改为当前窗打开（目录同理）
  (with-eval-after-load 'dired
    (define-key dired-mode-map [mouse-2] #'dired-mouse-find-file))

  ;; 响铃以振动实现，默认时长偏长，调短（10–1000ms）
  (when (boundp 'android-keyboard-bell-duration)
    (setq android-keyboard-bell-duration 30))

  ;; 触屏无菜单交互，关闭菜单栏（命令走 tool-bar / M-x）
  (menu-bar-mode -1)

  ;; 修饰键交官方 modifier-bar，默认开（tool-bar 首位按钮可开关）。
  ;; 本模块先于 self-bar 加载，image-load-path 未就位，setup 须延迟到
  ;; self-bar 之后执行
  (when (fboundp 'modifier-bar-mode)
    (modifier-bar-mode 1)
    ;; 为什么 advice 而不是 setup 完就拉倒：modifier-bar-mode 是个可反复
    ;; 开关的 minor-mode，用户从 tool-bar 首位按钮关掉再打开、或后续包
    ;; 调它重建 tool-bar 时，修饰键按钮都要重新对齐（图标来自 self-bar 的
    ;; 安装结果）。挂 `:after' 才不漏这些重入。
    ;; 下方 with-eval-after-load 是首次兜底：advice 只对之后的调用生效，
    ;; 上面那行 `(modifier-bar-mode 1)' 发生在 self-bar 加载之前。
    (advice-add 'modifier-bar-mode :after
                (lambda (&rest _) (self/modbar--setup)))
    (with-eval-after-load 'self-bar
      (self/modbar--setup))))

(provide 'self-touch)
;;; self-touch.el ends here
