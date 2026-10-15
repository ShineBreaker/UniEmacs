;;; self-terminal.el --- Ghostty 虚拟终端面板与 Git 提交深度集成 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: self-editing（`self--buffers-in-mode'）、self-windowing（`self/display-or-focus'）
;; Packages: ghostel
;;
;; 移植自桌面端配置「编辑与文本」域里的「终端集成 ghostel」小节，
;; 按模块边界从 self-editing 拆出来——终端面板有自己的主题、自己的按键
;; 修正、自己的进程启动策略，混在编辑模块里既不该也无法被 portable 档复用。
;;
;; 只挂 full 档：minimal 禁止第三方包；portable 跑在 Android 上，
;; libghostty-vt 通常不可用。
;;
;; 基于 Ghostty 的虚拟终端引擎（libghostty-vt）构建的 Emacs 内置终端面板，
;; 分三件事：
;;
;; · 进程环境：终端里跑 `git commit' 时 GIT_EDITOR 指向 emacsclient，
;;   自动在上方主编辑窗口打开提交日志输入界面。这是**刻意**的同步集成，
;;   不改成异步管道——提交信息必须回到 Emacs 里编辑才谈得上 LSP、
;;   spell-check 与仓库级片段。
;; · 按键修正：重绑 C-h 发送原生退格信号（否则被全局 `backward-char'
;;   抢占，终端里没法删字符）；放行 M-方向键给 PTY（shell 里按词跳转），
;;   同时保留 Emacs 侧的切窗口能力。
;; · 窗口路由：底部 1/3 高度的 side-window，自动 cd 到项目根，已存在的
;;   终端窗口直接聚焦。

;;; Code:

(declare-function self/display-or-focus "self-windowing"
                  (buffer action &optional select))
(declare-function self--buffers-in-mode "self-editing"
                  "返回所有派生自 MODE 的存活 buffer。")
(declare-function project-root "project" (project))
(declare-function ghostel-send-key "ghostel" (key mods))
(declare-function ghostel--rebuild-semi-char-keymap "ghostel")
(defvar ghostel-mode-map)
(defvar ghostel-keymap-exceptions)

;; ─── 环境变量与键盘映射 ─────────────────────────────────────────
;;
;; · Git 提交深度集成：终端里跑 `git commit' 时，`GIT_EDITOR` 指向
;;   emacsclient，自动在上方主编辑窗口打开提交日志输入界面，写完按
;;   `C-x #' 提交并让终端里的 Git 继续执行。
;; · 按键修正：重绑 `C-h' 发送原生退格信号，避免被全局 `backward-char'
;;   抢占。
;; · 方向键放行：Ghostel 默认把 `M-方向键' 透传给 PTY（shell 里用于按词
;;   跳转）。把它们加入 `ghostel-keymap-exceptions' 后按键回落到 Emacs 全局
;;   绑定，终端面板聚焦时 `M-方向键' 依然能切窗口；shell 内的按词移动仍可
;;   用 `M-b' / `M-f'。改动后需调用 `ghostel--rebuild-semi-char-keymap' 就地
;;   重建共享键表（改动对已存在的终端缓冲区即时生效）。

(defun self/ghostel-export-git-editor ()
  "在 Ghostel 创建进程前把 GIT_EDITOR 设为 emacsclient。

`setenv' 修改的是全局 `process-environment'，pre-spawn 之后 spawn 的子
进程一律继承；emacsclient 需要已运行的 server（daemon 常驻或 standalone
的 `server-mode'，后者在 self-daemon.el 里开），提交 buffer 由
`server-window'（self-windowing.el 设为 `self/display-buffer-in-main-window'）
路由到主编辑窗口。"
  (setenv "GIT_EDITOR" "emacsclient"))

(defun self/ghostel-send-ctrl-h ()
  "向 ghostel 发送 C-h（全局被 backward-char 占用，需显式重绑）。
交互命令：ghostel-mode 内按 C-h 即触发此函数。"
  (interactive)
  (ghostel-send-key "h" "ctrl"))

(with-eval-after-load 'ghostel
  (add-hook 'ghostel-pre-spawn-hook #'self/ghostel-export-git-editor)
  (define-key ghostel-mode-map (kbd "C-h") #'self/ghostel-send-ctrl-h)
  (setq ghostel-keymap-exceptions
        (append '("M-<left>" "M-<right>" "M-<up>" "M-<down>")
                ghostel-keymap-exceptions))
  (ghostel--rebuild-semi-char-keymap))

;; ─── 窗口路由与打开终端 ─────────────────────────────────────────
;;
;; 通过 `self/open-terminal' 在屏幕底部以 1/3 高度的侧边窗口打开：
;; · 自动识别项目：当前缓冲区处于某个工程内时自动 cd 到该工程根目录，
;;   不在工程内则用当前文件目录。
;; · 窗口自动对齐：已有终端窗口则直接聚焦，避免重复创建多个终端窗口。
;; · 进程探测防闪烁：无现存普通 ghostel 时，用 `save-window-excursion'
;;   配合调用前后的缓冲区差集定位新终端，消除屏幕闪烁。

(defconst self:terminal-side-action
  '(display-buffer-in-side-window
    (side . bottom) (window-height . 0.33))
  "终端面板的 display-buffer action：底部 side-window，高度 1/3。

action 参数须为 `(FUNCTION . ALIST)' 裸 cons；包一层列表会把 side/size
条目误解析为函数列表，静默回落 side 默认值 bottom 与默认高度。")

(defun self--terminal-existing-buffer ()
  "返回当前已存在的 ghostel buffer，无则 nil。"
  (car (self--buffers-in-mode 'ghostel-mode)))

(defun self/open-terminal (&optional arg)
  "打开 ghostel 终端（底部 side-window，高度 1/3），自动切换到项目根目录。

不在项目中则使用当前目录；带前缀参数 ARG 时使用当前文件所在目录。
有已显示的终端窗口则聚焦；有终端 buffer 但未显示则按
`self:terminal-side-action' 显示到底部；无则新建。
交互命令：M-x self/open-terminal，也绑在 C-` 与 C-c w t。"
  (interactive "P")
  (let* ((project-root (when-let* ((proj (project-current nil)))
                         (project-root proj)))
         (default-directory
          (if arg
              default-directory
            (or project-root default-directory)))
         (buf (or (self--terminal-existing-buffer)
                  (let ((before (buffer-list)))
                    (save-window-excursion (ghostel))
                    (seq-find
                     (lambda (b)
                       (with-current-buffer b (derived-mode-p 'ghostel-mode)))
                     (seq-difference (buffer-list) before))))))
    (self/display-or-focus buf self:terminal-side-action t)))

(provide 'self-terminal)

;;; self-terminal.el ends here
