;;; self-windowing.el --- display-buffer 路由与窗口面板布局 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: 无（本模块是窗口路由的底层，被 self-vcs 等上层反向消费）
;; Packages: 无
;;
;; 移植自桌面端配置的两处：「Git 与窗口路由 / Display-buffer 路由」一节
;; （窗口弹出与路由的基础辅助函数），以及文末「窗口与面板布局」一节
;; （各类辅助面板与工具窗口的弹出位置登记）。
;;
;; 本模块只做一件事：决定「一个 buffer 该在哪个窗口出现」。所有具体面板
;; 的落位规则都通过 `display-buffer-alist' 声明，不在代码里散写
;; `split-window' / `switch-to-buffer'，这样布局调整只改数据不改逻辑。
;;
;; 三个基础辅助函数：
;;
;; · `self/register-side-window'：把匹配正则表达式的 buffer 固定挂载到
;;   底部、左侧或右侧侧边栏。
;; · `self/display-buffer-in-main-window'：通过 `self--window-above-p'
;;   比较窗口几何坐标（`window-edges' 的 Y 轴边缘），定位当前窗口树中
;;   最上方的主编辑窗口并展示内容——保证无论光标当前在哪个窗口（如底部
;;   Magit 状态页），COMMIT_EDITMSG 都稳定落到上方编辑窗口，与「上编辑 +
;;   下 Magit」布局一致。同时它兼作两种身份：`display-buffer-alist' 的
;;   action 函数（ALIST 被忽略）与 `server-window' 的值（server.el 只传
;;   buffer 一个参数）。
;; · `self/display-or-focus'：目标缓冲区若已在某个窗口中显示则直接聚焦，
;;   否则新建窗口，防止无休止地产生新的分屏。终端面板与 Dired 侧栏都经它
;;   弹出（定义方传入自己的 action）。
;;
;; 「窗口与面板布局」一节登记的落位规则：
;;
;; · 底部工具面板——Magit 状态 40% 高度、终端（ghostel / term）33%、
;;   帮助窗口 40%、Flymake 诊断 30%、编译输出 33%、全文搜索结果（grep /
;;   xref）40%。
;; · 提交信息编辑——经 `server-window' 走主编辑窗口路由，与下方状态面板
;;   互不冲突；让提交消息文件进入 git-commit-mode 的那层 `find-file-hook'
;;   挂在 self-vcs.el（Git 关注入点），本模块不反向依赖它。
;; · 快捷退出——`quit-window-kill-buffer' 把这些只读辅助窗口的 q 键变成
;;   「关窗口并杀掉缓冲区」，不在后台堆积无用窗口。

;;; Code:

;; ─── 跨模块符号的就近声明 ──────────────────────────────────────────
;;
;; AGENTS.md §2：跨模块引用必须显式声明，不加 fboundp/boundp 守卫。
;; 本模块只被自绘界面层反向消费（self-vcs 用它的 display-buffer 路由），
;; 自身不依赖任何 self-* 模块，故 Requires 为空。

;; ─── 窗口弹出与路由的基础辅助 ──────────────────────────────────────

(defun self/register-side-window (regex side size)
  "把 REGEX 匹配的 buffer 路由到 SIDE 边的 side-window，占用 SIZE 比例。
SIDE 为 bottom/right/left/top；SIZE 是 0~1 比例，左右解释为宽度比、
上下解释为高度比。规则追加到 `display-buffer-alist' 末尾，顺序敏感：
更具体的规则应先注册。"
  (add-to-list 'display-buffer-alist
               `(,regex
                 (display-buffer-in-side-window)
                 (side . ,side)
                 ,(if (memq side '(left right))
                      `(window-width . ,size)
                    `(window-height . ,size)))
               t))

(defun self--window-above-p (a b)
  "窗口 A 是否在 B 的上方（y 相同则比 x，左在前）。"
  (let ((ea (window-edges a nil t t))
        (eb (window-edges b nil t t)))
    (or (< (nth 1 ea) (nth 1 eb))
        (and (= (nth 1 ea) (nth 1 eb))
             (< (nth 0 ea) (nth 0 eb))))))

(defun self/display-buffer-in-main-window (buffer &optional _alist)
  "把 BUFFER 显示在「主编辑窗口」并选中。
主编辑窗口 = 当前 frame 内最靠上（y 坐标最小）的非 side-window 窗口；
无候选时退化为 `display-buffer-pop-up-window'。同时用作
`display-buffer-alist' 的 action 函数（ALIST 被忽略）与 `server-window'
的值（server.el 只传 buffer 一个参数）。"
  (let* ((frame (selected-frame))
         (candidates
          (seq-remove
           (lambda (w) (window-parameter w 'window-side))
           (window-list frame 'no-minibuf (frame-first-window frame))))
         (target (car (sort candidates #'self--window-above-p))))
    (cond ((window-live-p target)
           (set-window-buffer target buffer)
           (select-window target)
           target)
          (t (display-buffer buffer '(display-buffer-pop-up-window))))))

(defun self/display-or-focus (buffer action &optional select)
  "有则聚焦，无则按 ACTION 创建。
BUFFER 已在某窗口显示时，聚焦该窗口（SELECT 非 nil）；否则把 ACTION 绑定为
`display-buffer-overriding-action' 创建——它的优先级高于 `display-buffer-alist'，
只影响本次调用，绕过 side-window 规则的同时不屏蔽其他包注册的路由。"
  (when (buffer-live-p buffer)
    (if-let* ((win (get-buffer-window buffer)))
        (when select (select-window win))
      (let ((display-buffer-overriding-action action))
        (display-buffer buffer)))))

;; ─── 窗口与面板布局登记 ────────────────────────────────────────────

;; 提交消息文件一落盘就进入 git-commit-mode——这条 hook 属于 Git 关注入
;; 点，挂在 self-vcs.el 的 `self/git-commit-setup-buffer-maybe' 定义之后，
;; 那里正是该命令的归属模块；此处只登记提交信息 buffer 的弹出位置。

;; 底部工具面板。规则自上而下按「越具体越靠前」排列。
(self/register-side-window "^magit: " 'bottom 0.4)
;; 提交信息不走 side-window：必须落到上方主编辑窗口。
(add-to-list 'display-buffer-alist
             '("^\\*git-commit\\|\\`COMMIT_EDITMSG\\|\\`MERGE_MSG"
               (self/display-buffer-in-main-window))
             t)
(self/register-side-window "^\\*ghostel\\|^\\*term" 'bottom 0.33)
(self/register-side-window "^\\*Help\\*" 'bottom 0.4)
(self/register-side-window "^\\*Flymake diagnostics" 'bottom 0.3)
(self/register-side-window "^\\*compilation" 'bottom 0.33)
(self/register-side-window "^\\*grep\\|^\\*xref" 'bottom 0.4)

;; server.el（如 emacsclient -c）只传 buffer 一个参数，路由到主编辑窗口。
;; server.el 不在预加载库里，batch 编译时它是自由变量——声明不带值，
;; daemon 真正用到的运行期由 server.el 自己 defvar。
(defvar server-window)
(setq server-window #'self/display-buffer-in-main-window)

;; 只读辅助窗口里按 q 直接关窗口并杀掉缓冲区，不留空窗口在后台堆积。
(setq quit-window-kill-buffer
      '(help-mode diff-mode grep-mode occur-mode
                  flymake-diagnostics-buffer-mode proced-mode ibuffer-mode
                  xref--xref-buffer-mode))

(provide 'self-windowing)
;;; self-windowing.el ends here
