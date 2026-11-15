;;; self-ide-mouse.el --- ide 档鼠标交互层：Ctrl 点击/横滚/gutter 断点/代码右键 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-keys（`self/bind'）
;; Packages: 无新包（dape/eglot/consult 均已在 ide 清单内，经懒加载入口调用）
;;
;; ide 档的鼠标行为对齐 IDEA 的日常操作：点项目树、点标签、滚轮、
;; 行号槽断点。本模块落地前
;; 已就绪的部分（写在这里是为了不再重复实现，也便于读者自助查证）：
;;
;;   · Ctrl+点击跳定义：有 `global-xref-mouse-mode' 的 Emacs 由 self-prog
;;     打开它。Emacs 30.2 还没有这个模式，本文件的 self/bind 把
;;     C-<mouse-1> 接到 xref-find-definitions-at-mouse；
;;   · 鼠标侧键前进/后退：<mouse-8>/<mouse-9>→xref-go-back/forward
;;     （self-prog）；
;;   · Alt+点击加多光标：M-<down-mouse-1>（self-editing）；
;;   · Tab 点击切换/中键关闭、滚轮切 Tab（self-tabline）；
;;   · 右键菜单本地化与「查找与替换/窗口」子菜单（self-help-zh）、
;;     context-menu-mode 开启与 pixel-scroll 平滑滚动（self-theme）。
;;
;; 本模块补上剩下的缝隙：
;;
;;   · 把 Ctrl+点击 / Ctrl+滚轮缩放再声明进 `self:binding-spec'——
;;     行为不变（同键同命令），但帮助页速查表只认这张表，不登记等于
;;     功能不可发现；
;;   · C-<drag-mouse-1>→mouse-set-point：Ctrl 按下拖动只移动光标，
;;     避免想在文本上 Ctrl+框选时松手误触发跳转；
;;   · Shift+滚轮横向滚动（Emacs 默认仍按竖滚派发 S-wheel-*），
;;     等价 IDE 的 Shift+Wheel 横滚；顺带开 `mouse-wheel-tilt-scroll'
;;     让触摸板倾斜滚动也走横滚；
;;   · gutter 点击切换断点：<left-fringe>/<left-margin> 的 mouse-1，
;;     点行号槽打断点，底层调 dape；
;;   · prog buffer 右键菜单顶部追加「代码」子菜单（跳转/重构/断点/
;;     定位文件树），等价 IDE 编辑区右键的第一段。
;;
;; 右键菜单的追加走 `context-menu-functions'：负 depth 让本函数在默认
;; 菜单项（撤销/剪贴板族）之前运行，条目落在菜单顶部，对齐 IDE 里
;; 「跳转与操作在上」的排布。

;;; Code:

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function dape-breakpoint-toggle "dape" nil)

;; eglot 的受管状态存在 buffer-local 私有变量里；bound-and-true-p 判读
;; 不触发 eglot 加载（菜单渲染路径禁止拉起整个 LSP 栈）。
(defvar eglot--managed-mode)

;; ─── Ctrl+点击：登记 + 拖拽防误触 ─────────────────────────────────
;;
;; xref-mouse-mode 已经把 C-<mouse-1> 绑到定义跳转；这里按「同键同命令」
;; 再声明一遍换取帮助页条目，并把拖拽释放绑成「只落光标」。Ctrl+滚轮
;; 缩放是 Emacs 内建（mouse-wheel-text-scale），同样只登记不改行为。

(self/bind "C-<mouse-1>" #'xref-find-definitions-at-mouse
           "Ctrl+点击跳定义" "鼠标")
(self/bind "C-<drag-mouse-1>" #'mouse-set-point
           "Ctrl+拖拽只移光标" "鼠标")
(self/bind "C-<wheel-up>" #'mouse-wheel-text-scale
           "Ctrl+滚轮放大字号" "鼠标")
(self/bind "C-<wheel-down>" #'mouse-wheel-text-scale
           "Ctrl+滚轮缩小字号" "鼠标")

;; ─── Shift+滚轮 / 触摸板 tilt：横向滚动 ────────────────────────────
;;
;; Shift+WheelUp 把视口往左滚（看到更靠左的列）。
;; Emacs 里「视口往左、内容往右露」对应命令 scroll-right（reveals
;; columns on the left），scroll-left 反之——函数名按「用户看到的方向」
;; 起，函数体调用方向相反的内建命令，注释里说明这层反向。

(setq mouse-wheel-tilt-scroll t)  ; 触摸板 tilt 事件也走横滚

(defun self/ide-scroll-h-left ()
  "横向滚动：视口左移，露出更靠左的列。
实际是调用 `scroll-right'——Emacs 的 scroll-right 把内容往右推、
从而露出左边的列，与「视口方向」命名恰好相反。也绑在 S-<wheel-up>
与 S-<wheel-left>。"
  (interactive)
  (scroll-right 8))

(defun self/ide-scroll-h-right ()
  "横向滚动：视口右移，露出更靠右的列。
调用 `scroll-left'（方向反向的原因见 `self/ide-scroll-h-left'）。
也绑在 S-<wheel-down> 与 S-<wheel-right>。"
  (interactive)
  (scroll-left 8))

(self/bind "S-<wheel-up>" #'self/ide-scroll-h-left "横滚向左" "鼠标")
(self/bind "S-<wheel-down>" #'self/ide-scroll-h-right "横滚向右" "鼠标")
(self/bind "S-<wheel-left>" #'self/ide-scroll-h-left "横滚向左" "鼠标")
(self/bind "S-<wheel-right>" #'self/ide-scroll-h-right "横滚向右" "鼠标")

;; ─── gutter 点击断点 ───────────────────────────────────────────────
;;
;; IDEA 里点行号槽切换断点。Emacs 的行号数字**不是**独立鼠标区：点它
;; 派发的是普通 mouse-1（posn-area 为 nil），left-margin/left-fringe
;; 绑定收不到；岛屿内边距下 fringe 事件也不可靠。故在 prog buffer 接管
;; mouse-1，按落点像素分流：正文首列以左（fringe+行号）即 gutter，切换
;; 断点;其余交回 mouse-set-point。判别见 `self/ide--gutter-click-p'。
;; left-fringe/left-margin 两条绑定保留，覆盖能派发这两类事件的帧。
;; 断点只对 prog-mode 派生 buffer 有意义;dape 懒加载，首次点击现 require。

(defun self/ide-toggle-breakpoint-at-mouse (event)
  "在点击行（或直接调用时的当前行）切换 DAP 断点。
点行号槽或左 fringe 切换断点;非 prog-mode buffer 只提示不动作。
交互命令：点击行号区或左 fringe 触发，也可 M-x 在当前行切换。"
  (interactive "e")
  ;; event 经鼠标触发时带落点位置;经 M-x/键盘触发时 posn-window 不是
  ;; window 对象，退回选中窗口，posn-point 则给出当前 point。
  (let* ((posn (event-start event))
         (posn-win (posn-window posn))
         (win (if (windowp posn-win) posn-win (selected-window))))
    (with-current-buffer (window-buffer win)
      (if (not (derived-mode-p 'prog-mode))
          (message "断点仅在代码缓冲可用")
        ;; posn-point 是点击处的 buffer 位置;save-excursion 保证切换
        ;; 断点不把用户光标拽走。dape 无 autoload cookie，fboundp 守卫
        ;; 会永远停在「未加载」，这里首次点击现 require 再切换。
        (save-excursion
          (when (posn-point posn)
            (goto-char (posn-point posn)))
          (if (require 'dape nil t)
              (dape-breakpoint-toggle)
            (message "dape 未安装，无法切换断点")))))))

(self/bind "<left-fringe> <mouse-1>" #'self/ide-toggle-breakpoint-at-mouse
           "点击 fringe 切换断点" "鼠标")
(self/bind "<left-margin> <mouse-1>" #'self/ide-toggle-breakpoint-at-mouse
           "点击 margin 切换断点" "鼠标")

(defun self/ide--gutter-click-p (posn)
  "POSN 落点是否在 gutter 区（fringe+行号，正文首列以左）。
行首文本列的像素 x 经 `posn-at-point' 现取，落点 x 比它小即 gutter;
不依赖字体/行号宽度，换字体缩放都成立。落点不在窗口或无 buffer 位置
（如点模式行）返回 nil。"
  (let ((win (posn-window posn))
        (pt (posn-point posn)))
    (and (windowp win) pt
         (with-current-buffer (window-buffer win)
           (< (car (posn-x-y posn))
              (car (posn-x-y
                    (posn-at-point
                     (save-excursion
                       (goto-char pt)
                       (line-beginning-position))
                     win))))))))

(defun self/ide-gutter-mouse-1 (event)
  "prog buffer 的 mouse-1：gutter 区切换断点，其余照常落光标。
IDEA 点行号槽打断点;Emacs 行号区点击是普通 mouse-1，这里按落点像素
分流（见 `self/ide--gutter-click-p'）。非 gutter 交回 `mouse-set-point';
拖拽框选仍由 down-mouse-1 负责，不受影响。
交互命令：prog buffer 内单击触发。"
  (interactive "e")
  (if (self/ide--gutter-click-p (event-start event))
      (self/ide-toggle-breakpoint-at-mouse event)
    (mouse-set-point event)))

(defun self/ide--gutter-setup ()
  "prog buffer 接管 mouse-1 以支持 gutter 断点（`self/ide-gutter-mouse-1'）。"
  (local-set-key [mouse-1] #'self/ide-gutter-mouse-1))

(add-hook 'prog-mode-hook #'self/ide--gutter-setup)

;; ─── 代码右键菜单 ──────────────────────────────────────────────────
;;
;; 追加在菜单顶部（负 depth 先跑），只在点击位置属于 prog-mode buffer
;; 时出现。eglot/dape 相关条目用 bound-and-true-p / fboundp 做 :enable，
;; 懒加载库不在菜单渲染路径上被拉起。

(defun self/ide--context-menu-code (menu click)
  "给 MENU 顶部追加「代码」子菜单；点击位置在 prog-mode buffer 才生效。
CLICK 是右键事件，经 `posn-window' 判定目标 buffer 的 major mode。"
  (let ((win (posn-window (event-start click))))
    (when (and (window-live-p win)
               (with-current-buffer (window-buffer win)
                 (derived-mode-p 'prog-mode)))
      ;; 先子菜单后分隔线：本函数最先跑，条目落在菜单最顶部，分隔线
      ;; 在「代码」段与默认撤销/剪贴板段之间（顶部放分隔线会是空行）。
      (define-key-after menu [code]
        (list 'menu-item "代码" (self/ide--code-menu)))
      (define-key-after menu [code-separator] menu-bar-separator))
    menu))

(defun self/ide--code-menu ()
  "构造「代码」右键子菜单，条目对齐 IDE 编辑区右键的常用段。
用 `define-key-after' 尾插而非 `define-key':后者往 keymap 头部 cons,
显示顺序会与定义顺序相反;尾插保证「导航在上、编辑居中、断点/定位在下」。"
  (let ((map (make-sparse-keymap "代码")))
    (define-key-after map [definition]
                '(menu-item "跳转到定义" xref-find-definitions
                            :help "跳到光标符号的定义处（Ctrl+点击同义）"
                            :keys "C-c c d"))
    (define-key-after map [references]
                '(menu-item "查找引用" xref-find-references
                            :help "列出当前符号的全部引用" :keys "M-g r"))
    (define-key-after map [back]
                '(menu-item "后退" xref-go-back
                            :help "回到上一处跳转点" :keys "M-g b"))
    (define-key-after map [outline]
                '(menu-item "符号大纲…" consult-imenu
                            :help "文件内符号列表跳转" :keys "C-S-o"))
    (define-key-after map [separator-nav] menu-bar-separator)
    (define-key-after map [rename]
                '(menu-item "重命名符号" self/rename-dwim
                            :help "LSP 接管时走 eglot-rename，否则替换选区"
                            :keys "<f2>"))
    (define-key-after map [actions]
                '(menu-item "代码操作…" eglot-code-actions
                            :enable (bound-and-true-p eglot--managed-mode)
                            :help "LSP 提供的 quickfix/重构动作" :keys "C-c c a"))
    (define-key-after map [diagnostics]
                '(menu-item "诊断列表" self/flymake-list-errors-dwim
                            :help "打开/关闭 Flymake 诊断面板" :keys "C-c c k"))
    (define-key-after map [format]
                '(menu-item "格式化缓冲" apheleia-format-buffer
                            :help "按语言表调用外部 formatter" :keys "C-c c f"))
    (define-key-after map [comment]
                '(menu-item "切换注释" comment-line
                            :help "注释/取消注释当前行或选区" :keys "M-;"))
    (define-key-after map [separator-edit] menu-bar-separator)
    (define-key-after map [breakpoint]
                '(menu-item "切换断点" dape-breakpoint-toggle
                            :help "在当前行添加/移除 DAP 断点（点行号槽同义）"))
    (define-key-after map [reveal]
                '(menu-item "文件树中定位" self/ide-panel-reveal
                            :help "在 Treemacs 面板里定位当前文件"
                            :keys "C-S-e"))
    map))

;; 负 depth 让本函数在 context-menu-functions 里最先跑，「代码」子菜单
;; 落到菜单最顶部（默认项与 self-help-zh 的两个子菜单都在其后追加）。
(add-hook 'context-menu-functions #'self/ide--context-menu-code -90)

(provide 'self-ide-mouse)

;;; self-ide-mouse.el ends here
