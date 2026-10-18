;;; self-ide-panel.el --- IDE 档左侧项目文件树（Treemacs）与面板键位接管 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-keys（`self:binding-spec'、`self/binding--register-which-key'）、
;;           self-terminal、self-keys-desktop（覆写其键位）
;; Packages: treemacs, treemacs-nerd-icons
;;
;; Zed 左侧 dock 的常驻面板是 Project Panel：一棵带文件图标、Git 状态色、
;; 缩进参考线的项目文件树。full 档的同位设施是 self-project 的 Dired 面板
;; ——目录平铺、无树形折叠、无图标，教育意义大于 IDE 体验。ide 档改用
;; Treemacs：
;;
;;   · nerd-icons 主题提供文件图标（self-glyph 的 NF 资产兜底逻辑同样生效，
;;     treemacs-nerd-icons 复用 nerd-icons 字体族）；
;;   · treemacs-git-mode 'deferred：异步打 Git 状态色，不阻塞打开；
;;   · treemacs-filewatch-mode 关闭：本机 inotify 实例上限 128，Zed 已报过
;;     inotify_init 失败，树内目录刷新交给手动 g（treemacs-refresh）；
;;   · treemacs-follow-mode：切换缓冲区时树自动定位当前文件，对齐 Zed 的
;;     Reveal in Project Panel 自动行为；
;;   · treemacs-tag-follow-mode：树内直接展开当前文件的 imenu 符号列表，
;;     近似 Zed 左侧 Outline Panel。
;;
;; 键位接管：self-keys-desktop 已为 full 档绑好 C-b / C-S-e / C-c w f/d/T
;; 指向 Dired 面板；本模块用 `self/ide--rebind' 把它们改绑到 Treemacs 等价物，
;; 并同步改写 `self:binding-spec' 与 Which-key 描述，让帮助页与提示不漂移。
;; `self/bind' 对重复声明直接报错，档内覆写只能绕过它——这是刻意的档私有
;; 覆写手段，仅限本模块使用。
;;
;; Treemacs 自身的打开行为：RET/TAB 打开文件到「最近使用的非树窗口」，
;; side-window 身份使文件自然落进主编辑区，无需额外窗口路由。

;;; Code:

(require 'self-lib)

(declare-function self/open-terminal "self-terminal")
(declare-function self--terminal-existing-buffer "self-terminal")
(declare-function project-current "project" (&optional maybe-prompt directory))
(declare-function treemacs "treemacs")
(declare-function treemacs-find-file "treemacs")
(declare-function treemacs-get-local-window "treemacs")
(declare-function treemacs-add-and-display-current-project "treemacs")
(declare-function treemacs-load-theme "treemacs")

;; ─── Treemacs 配置 ─────────────────────────────────────────────────
;; 这一组 defcustom 都是「先赋值、后由 treemacs 启动时读取」的模式：
;; 对未加载包的变量先挂值、treemacs 首次显示时再消费，:custom 通道
;; （customize-set-variable）正是这个语义，且不会产生 byte-compile
;; 自由变量告警。

;; 急切加载（不写 :defer t）：:custom 里 treemacs-tag-follow-mode 这类
;; minor-mode defcustom 经 custom 置值时就已拉起 tag-follow 的 require
;; 链，惰性本来名存实亡；更关键的是 treemacs-persistence 只由伞特性
;; (require 'treemacs) 顶层拉起——treemacs--maybe-load-workspaces 被
;; define-inline 在编译期内联进 workspaces/tag-follow 的调用点，展开体
;; 直接调 treemacs--restore，persistence 缺位即 void-function（daemon
;; 日志里 tag-follow timer 报的正是这个）。伞特性 require 一次兜住
;; 全部 inline 调用点，ide 档启动也本就要开树。
(use-package treemacs
  :custom
  (treemacs-width 30)                    ; Zed 侧栏 ≈ 240px，约 30 列
  (treemacs-position 'left)
  (treemacs-git-mode 'deferred)          ; 异步 Git 状态，不卡打开
  (treemacs-filewatch-mode nil)          ; inotify 实例紧张，关
  (treemacs-follow-mode t)               ; 树跟随当前文件
  (treemacs-tag-follow-mode t)           ; 树内展开当前文件符号
  ;; indent guide 保持关闭（其 ┃ 参考线继承 font-lock-comment-face，本
  ;; 主题里是一条鲑红竖线而非 Zed 的灰线）。注意不能经 :custom 显式置
  ;; nil——customize-set-variable 走 custom-set-minor-mode 会执行 mode
  ;; 函数体，其关闭分支把 treemacs-indentation(-string) 回写成从未初始
  ;; 化的 saved 值 nil，之后每个 treemacs buffer 初始化时在
  ;; treemacs--build-indentation-cache 里 (% n (length nil)) 除零抛
  ;; arith-error，树初始化半途即挂（timer 里静默失败，树面板不显示）。
  ;; 默认就是关，什么都不写。
  ;; self-modeline 把全局 mode-line-format 置 nil（无窗口状态栏设计），
  ;; 但 treemacs--setup-mode-line 在 mode 启动时 setq 了 buffer-local
  ;; mode-line-format，默认值管不到它；官方旋钮 'none 才是正确关法。
  (treemacs-user-mode-line-format 'none)
  (treemacs-recenter-after-file-follow 'always)
  :config
  ;; treemacs-fringe-indicator-face 的 defface 用 `(face-background 'cursor)'
  ;; 取色，daemon 启动无 GUI 帧时烙进 nil，每个新 client 帧 realization
  ;; 重放即打 nil-attr 警告；就地归一化为 unspecified（语义等价）。
  (self/defface-spec-de-nil 'treemacs-fringe-indicator-face :foreground)
  ;; nerd-icons 主题须在 treemacs 本体加载后切换。
  (require 'treemacs-nerd-icons)
  (treemacs-load-theme "nerd-icons"))

;; ─── 面板命令 ──────────────────────────────────────────────────────

(defun self/ide-panel-visible-p ()
  "Treemacs 面板窗口当前是否显示。"
  (and (fboundp 'treemacs-get-local-window)
       (treemacs-get-local-window)))

(defun self/ide-panel-toggle ()
  "开关左侧 Treemacs 文件树；等价 Zed 的 C-b。
交互命令：M-x self/ide-panel-toggle，也绑在 C-b。"
  (interactive)
  (treemacs))

(defun self/ide-panel-open ()
  "确保左侧文件树可见但不抢焦点；等价 Zed 打开 Explorer 面板。"
  (interactive)
  (unless (self/ide-panel-visible-p)
    (treemacs)))

(defun self/ide-panel-reveal ()
  "打开文件树并定位当前文件；等价 Zed 的 Reveal in Project Panel。
无文件的缓冲区退化为只开树。treemacs-find-file 对不在工作区内的
文件自行报 user-error，信息本身有解释力，不做额外包装。
交互命令：M-x self/ide-panel-reveal，也绑在 C-S-e / C-c w d。"
  (interactive)
  (if buffer-file-name
      (treemacs-find-file)
    (treemacs)))

;; ─── 双面板总开关（左 Treemacs / 底部槽）─────────────────────────────
;; 结构照搬 self-keys-desktop 的 self/panels-toggle：任一开着则全关、
;; 全关则全开、焦点回主区。full 档的「右 Agent」在 ide 档不是面板——
;; self-ide-slots 的槽位契约把 agent-shell 声明为编辑区内容 tab，
;; 底槽用 window-side=bottom 判定（槽内换过内容也算开着）。

(defun self/ide-panels-toggle ()
  "一键开关双面板布局（左 Treemacs / 底部槽）。
任一面板显示则全部隐藏（缓冲区保留，会话不中断）；全部隐藏则重新打开。
交互命令：M-x self/ide-panels-toggle，也绑在 C-c w T。"
  (interactive)
  (let* ((tree-win (self/ide-panel-visible-p))
         (bottom-win (seq-find
                      (lambda (w)
                        (eq (window-parameter w 'window-side) 'bottom))
                      (window-list (selected-frame))))
         (any-visible (or tree-win bottom-win)))
    (if any-visible
        (progn
          (when tree-win (delete-window tree-win))
          (when bottom-win (delete-window bottom-win)))
      (self/ide-panel-open)
      (self/open-terminal)))
  (when-let* ((main (seq-find
                     (lambda (w) (not (window-parameter w 'window-side)))
                     (window-list (selected-frame)))))
    (select-window main)))

;; ─── 档私有键位覆写 ─────────────────────────────────────────────────

(defun self/ide--rebind (key command description)
  "把全局键 KEY 改绑到 COMMAND 并同步帮助数据源。
`self/bind' 对重复 (key . mode) 声明直接报错，档内覆写只能用本函数：
keymap-global-set 换实际绑定，plist-put 就地改写 `self:binding-spec'
条目，Which-key 描述走 `self/binding--register-which-key' 正常通道
（which-key-allow-multiple-replacements 已开，重注册即覆盖）。"
  (keymap-global-set key command)
  (let ((entry (seq-find
                (lambda (item)
                  (and (equal key (plist-get item :key))
                       (eq (or (plist-get item :mode) 'global) 'global)))
                self:binding-spec)))
    (when entry
      (plist-put entry :command command)
      (plist-put entry :description description)))
  (self/binding--register-which-key key description))

(self/ide--rebind "C-b" #'self/ide-panel-toggle "文件树开关")
(self/ide--rebind "C-S-e" #'self/ide-panel-reveal "文件树定位当前文件")
(self/ide--rebind "C-c w f" #'self/ide-panel-open "文件树面板")
(self/ide--rebind "C-c w d" #'self/ide-panel-reveal "面板定位当前文件")
(self/ide--rebind "C-c w T" #'self/ide-panels-toggle "双面板总开关")

;; ─── 新帧自动摆布局（左树 + 底槽终端）─────────────────────────────
;; Zed 打开文件夹/文件即进入「左树 + 编辑区 + 底面板」布局，本段覆盖
;; 两条进入路径：
;;
;;   · standalone `emacs <路径>'：emacs-startup-hook 时 current-buffer
;;     已是最后访问的目标 buffer，直接判定；
;;   · daemon `emacsclient -c <路径>'（本机主力形态）：新 client 帧走
;;     server-after-make-frame-hook。两个坑都在「上下文不在场」：
;;     hook 触发点 current-buffer 还是 *server*（server-visit-files 用
;;     save-current-buffer 包着，文件 buffer 要等 server-switch-buffer
;;     才切换上台）；timer 触发点 select-frame 又不改 current-buffer
;;     （它只是显示层选择，buffer 上下文仍是计时器环境的 *server* 或
;;     上个前台 buffer）。所以只排队一个 0s timer，等 server-execute
;;     整个收尾，再手动把帧选中窗的 buffer 设为判定上下文——与
;;     self/dashboard--on-frame-make 同一手法。
;;
;; 「值得摆布局」的上下文：本次打开的是文件或目录（buffer-file-name /
;; dired-mode），或当前目录本来就在 project 内。裸 `emacs' /
;; `emacsclient -c' 无参数时在 project cwd 下同样带上树，对齐 Zed
;; 恢复 workspace 面板的行为；非 project 目录不用自己解析根，
;; treemacs-add-and-display-current-project 内部的解析链是
;; project.el → 当前目录，直接以打开目录为根。
;;
;; 每帧只摆一次：frame 参数 self:ide-layout-seen 置位后不再触发，
;; 之后手动关掉面板不会被下一次 emacsclient 调用重新顶开。
;; Treemacs 与终端打开时都会抢焦点，save-selected-window 把焦点
;; 还给主区。

(defun self/ide--layout-context-p ()
  "当前 buffer 是否属于「打开了东西」的上下文：文件、目录或 project 内。"
  (or buffer-file-name
      (derived-mode-p 'dired-mode)
      (project-current nil)))

(defun self/ide--layout-window (frame)
  "在 FRAME 内找「布局上下文窗口」：优先返回选中窗，其后按窗序取第一个
buffer 满足 `self/ide--layout-context-p' 的窗口；都没有返回 nil。

不能盲信 `frame-selected-window'：0s timer 会被 `(redisplay t)' 让路
抢跑——实测首 client 帧上本 timer 恰在 `minimap-new-minimap' 的
with-selected-window 瞬态内触发，此时帧记录的选中窗是 *MINIMAP*，
按它判定上下文必假，布局永久跳过（seen 未置位）。扫描全部窗口
则不受这类瞬态选中影响。"
  (let ((sel (frame-selected-window frame))
        (hit nil)
        (rest (window-list frame 'no-minibuf)))
    (if (with-current-buffer (window-buffer sel)
          (self/ide--layout-context-p))
        sel
      (while (and rest (not hit))
        (let ((w (car rest)))
          (when (with-current-buffer (window-buffer w)
                  (self/ide--layout-context-p))
            (setq hit w)))
        (setq rest (cdr rest)))
      hit)))

(defun self/ide--show-bottom-terminal ()
  "在当前帧底槽就位一个终端 buffer。
已有 ghostel buffer 时用 display-buffer 显示到本帧（同一终端会话
多帧共显）；本帧已在显示则不动；没有则 `self/open-terminal' 新建。"
  (let ((buf (self--terminal-existing-buffer)))
    (cond ((null buf) (self/open-terminal))
          ((get-buffer-window buf (selected-frame)) nil)
          (t (display-buffer buf)))))

(defun self/ide--startup-layout ()
  "当前帧上下文值得时摆出 Zed 式三槽布局：左 Treemacs、底槽终端、编辑区。
GUI 帧且 `self/ide--layout-context-p' 成立才动作；每帧最多执行一次
（frame 参数 self:ide-layout-seen 标记）。"
  (when (and (not noninteractive)
             (display-graphic-p)
             (not (frame-parameter nil 'self:ide-layout-seen))
             (self/ide--layout-context-p))
    (set-frame-parameter nil 'self:ide-layout-seen t)
    (save-selected-window
      (unless (self/ide-panel-visible-p)
        (treemacs-add-and-display-current-project))
      (self/ide--show-bottom-terminal))))

(defun self/ide--layout-timer-tick (frame attempts)
  "布局调度的 timer 体：在 FRAME 上找上下文窗口并执行 `self/ide--startup-layout'。
找不到上下文窗口时最多重试 ATTEMPTS 次（间隔 0.15s）——0s timer
可能被别的 timer 里的 `(redisplay t)' 让路抢跑，赶上
server-switch-buffer 尚未把文件 buffer 摆上窗口的瞬间，稍候重试
兜底；裸 `emacsclient -c'（只开 dashboard）重试耗尽后自然放弃。"
  (when (frame-live-p frame)
    (with-selected-frame frame
      (let ((win (self/ide--layout-window frame)))
        (if win
            (with-selected-window win
              (self/ide--startup-layout))
          (when (< attempts 3)
            (run-at-time 0.15 nil #'self/ide--layout-timer-tick
                         frame (1+ attempts))))))))

(defun self/ide--schedule-startup-layout ()
  "在 client 帧上下文里排队执行 `self/ide--startup-layout'（0s timer）。
捕获触发时的 selected frame：timer 触发瞬间用户可能已切到别处，
布局必须落在刚建立的那个帧上。"
  (let ((frame (selected-frame)))
    (run-at-time 0 nil #'self/ide--layout-timer-tick frame 0)))

(add-hook 'emacs-startup-hook #'self/ide--startup-layout)
(add-hook 'server-after-make-frame-hook #'self/ide--schedule-startup-layout)

(provide 'self-ide-panel)
;;; self-ide-panel.el ends here
