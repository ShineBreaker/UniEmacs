;;; self-keys-desktop.el --- 桌面档键位清单：跨域公共键与直达键 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, ide
;; Requires: self-keys（`self/bind' 与 `self--pending-wk-descs'）、self-editing、self-terminal、self-project、self-prog、self-tabline、self-completion、self-help-zh
;; Packages: multiple-cursors
;;
;; 移植自桌面端配置「键位声明」域的键位清单部分——纯数据：跨域公共键、
;; 全局直达键（对齐 VSCode 的 C-S-* 家族）、C-c t/C-c q 开关退出系列、
;; C-c w 窗口面板体系。本文件不提供机制，`self/bind' 由 self-keys 提供。
;;
;; 为什么清单只在 full 档：这些键位是为「鼠标 + 键盘 + 图形窗口」的工作站
;; 场景设计的（<f12> 跳转、C-\ 分屏、面板停靠）。minimal 档对标 nano 的
;; 功能水平，不需要这层导航；portable 档是触屏，没有物理功能键与 Ctrl-Alt
;; 组合。真正跨平台的那部分（14 个顶层前缀）已经放在 self-keys。
;;
;; ─── 键位内聚原则 ────────────────────────────────────────────────────
;;
;; 专属于某一模块的快捷键（Git 走 C-c g、Org 走 C-c o、代码走 C-c c）
;; 随其模块就近绑定。本文件只声明两类：真正跨域的公共键（"C-x"、"M-s"
;; 系列与全局直达键），以及需要跨模块协作的窗口面板体系。查某个具体功能
;; 的键位，第一步去那个功能的域。
;;
;; 目标命令散落在 self-editing、self-terminal、self-project、self-prog
;; 等模块与第三方包中，故在此统一 declare-function 声明依赖
;; （AGENTS.md §2：跨模块引用显式声明，不加 fboundp 守卫）。

;;; Code:

;; ─── 跨模块符号的就近声明 ──────────────────────────────────────────

(declare-function self/isearch-forward-dwim "self-completion"
  "启动增量搜索，有活跃选区时把选区文本填入搜索串。")
(declare-function self/tabs-next "self-tabline"
  "切换到下一个标签页。")
(declare-function self/tabs-previous "self-tabline"
  "切换到上一个标签页。")
(declare-function self/tabs-move "self-tabline"
  "把当前标签页向后移动一位。")
(declare-function self/tabs-move-backward "self-tabline"
  "把当前标签页向前移动一位。")
(declare-function self/copy-dwim "self-editing"
  "智能复制：选区取选区，无选区取当前行。")
(declare-function self/cut-dwim "self-editing"
  "智能剪切：选区取选区，无选区取当前行。")
(declare-function self/code-move-line-up "self-editing"
  "把当前行上移一行。")
(declare-function self/code-move-line-down "self-editing"
  "把当前行下移一行。")
(declare-function self/open-line-below "self-editing"
  "在下方开一行并进入。")
(declare-function self/open-line-above "self-editing"
  "在上方开一行并进入。")
(declare-function self/home-dwim "self-editing"
  "智能行首：无参到行首，有参到行首非空白字符处。")
(declare-function self/reopen-closed-file "self-editing"
  "重新打开最近关闭的文件。")
(declare-function self/rename-dwim "self-editing"
  "智能重命名。")
(declare-function self/open-terminal "self-terminal"
  "打开终端面板。")
(declare-function self--terminal-existing-buffer "self-terminal"
  "返回已存在的终端 buffer，没有则返回 nil。")
(declare-function self--buffers-in-mode "self-editing"
  "返回处于 MODE 的所有 buffer 列表。")
(declare-function self/panel-dired "self-project"
  "打开左侧文件面板（Dired）。")
(declare-function self/panel-dired-toggle "self-project"
  "开关左侧文件面板。")
(declare-function self/panel-dired-reveal "self-project"
  "让文件面板切到当前文件所在目录并选中该行。")
(declare-function self/flymake-list-errors-dwim "self-prog"
  "打开诊断面板。")
(declare-function self/project-root-or-default "self-project"
  "返回当前项目根目录，没有项目时回退到默认目录。")
(declare-function agent-shell "agent-shell"
  "打开 Agent Shell 交互面板。")
(declare-function eglot-code-actions "eglot"
  "对光标处（或当前诊断）运行 code action。")
(declare-function dape "dape"
  "启动 DAP 调试会话。")
(declare-function dape-breakpoint-toggle "dape"
  "在当前行切换断点。")
(declare-function magit-status "magit"
  "打开 Magit 状态缓冲区。")
;; help.el 的前缀 keymap，本模块只把它绑成 <f1> 入口。它是变量，但
;; self/bind 的 TARGET 位置写作 #'help-map，byte-compile 按函数引用看待。
(defvar help-map)
(declare-function help-map "help")
(declare-function winner-undo "winner"
  "撤销上一次的窗口布局变更。")
(declare-function winner-redo "winner"
  "重做被撤销的窗口布局变更。")

;; multiple-cursors 只在本文件被绑键（C-d / C-S-l），故由本文件声明延迟
;; 加载：`:commands' 让 use-package 生成 autoload，用户按下键位那一刻才
;; 真正加载包——minimal 档根本不 require 本文件，full 档也只在用时才付代价。
(use-package multiple-cursors
  :commands (mc/mark-next-like-this-word mc/mark-all-like-this))

;; ─── 跨域基础键 ──────────────────────────────────────────────────────
;;
;; "C-x" 与 "M-s" 两棵子树里与缓冲区、文件、项目、搜索直接相关的公共键。

(self/bind "C-x C-r" #'recentf-open "最近文件" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x b" #'switch-to-buffer "切换缓冲区" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x C-b" #'ibuffer "缓冲区列表 (ibuffer)" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x B" #'ibuffer "缓冲区列表 (ibuffer)" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x k" #'kill-buffer-and-window "关闭当前缓冲区" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x K" #'kill-buffer "关闭指定缓冲区" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x C-f" #'ffap "打开文件" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x t n" #'self/tabs-next "下一个标签" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x t p" #'self/tabs-previous "上一个标签" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x T" #'self/reopen-closed-file "重开已关闭文件" "文件 / 缓冲区 / 窗口 / 标签")

(self/bind "M-s e" #'xref-find-apropos "符号搜索" "搜索")
(self/bind "M-s i" #'self/isearch-forward-dwim "增量搜索" "搜索")
(self/bind "M-s l" #'occur "搜索当前缓冲区" "搜索")
(self/bind "M-s m" #'multi-occur "多缓冲区搜索" "搜索")
(self/bind "M-s p" #'project-find-regexp "搜索项目" "搜索")
(self/bind "M-s R" #'project-query-replace-regexp "项目范围替换" "搜索")

(self/bind "<f1> ?" #'self/show-help "快捷键帮助" "帮助")
(self/bind "C-c h d" #'dashboard-open "打开仪表盘" "帮助")
(self/bind "C-c h c" #'self/open-config-source "打开设置 (emacs.org)" "帮助")
(self/bind "S-<f10>" #'context-menu-open "打开右键菜单" "帮助")
(self/bind "<menu>" #'context-menu-open "打开右键菜单" "帮助")

;; ─── 全局直达键：基础移动、文件、编辑 ─────────────────────────────────

(self/bind "C-h" #'backward-char "左移" "基础移动与直达键")
(self/bind "<f1>" #'help-map "帮助前缀" "基础移动与直达键")
(self/bind "C-j" #'next-line "下移" "基础移动与直达键")
(self/bind "C-k" #'previous-line "上移" "基础移动与直达键")
(self/bind "C-l" #'forward-char "右移" "基础移动与直达键")
(self/bind "C-z" #'undo "撤销" "基础移动与直达键")
(self/bind "C-S-z" #'undo-redo "重做" "基础移动与直达键")
(self/bind "C-s" #'save-buffer "保存" "基础移动与直达键")
(self/bind "C-p" #'project-find-file "项目内查找文件" "基础移动与直达键")
(self/bind "C-o" #'find-file "打开文件" "基础移动与直达键")
(self/bind "C-S-f" #'self/isearch-forward-dwim "文件内查找" "基础移动与直达键")
(self/bind "C-S-h" #'replace-regexp-as-diff "文件内替换 (diff 预览)" "基础移动与直达键")
;; TTY 退化备用键：C-S-h 在很多终端里发不出去（控制序列与 Shift+Ctrl 组合
;; 冲突，tmux / 部分终端仿真器会吞掉）。无歧义的备用入口是 self-editing.el
;; 里的 `C-c e r'——它与本文件的 C-S-h 指向同一个命令，而 self/bind 拒绝重复
;; 声明，故备用键只留那一处，不在此重复登记。
(self/bind "C-S-r" #'recentf-open "最近文件" "基础移动与直达键")
(self/bind "C-S-o" #'imenu "符号大纲" "基础移动与直达键")
(self/bind "C-S-p" #'execute-extended-command "命令面板" "基础移动与直达键")
(self/bind "C-<tab>" #'self/tabs-next "下一个标签" "基础移动与直达键")
(self/bind "C-<iso-lefttab>" #'self/tabs-previous "上一个标签" "基础移动与直达键")
(self/bind "C-S-<tab>" #'self/tabs-previous "上一个标签" "基础移动与直达键")
(self/bind "C-<prior>" #'self/tabs-previous "上一个标签" "基础移动与直达键")
(self/bind "C-<next>" #'self/tabs-next "下一个标签" "基础移动与直达键")
(self/bind "C-x M-<right>" #'self/tabs-move "标签后移" "基础移动与直达键")
(self/bind "C-x M-<left>" #'self/tabs-move-backward "标签前移" "基础移动与直达键")
(self/bind "C-a" #'mark-whole-buffer "全选" "基础移动与直达键")
(self/bind "C-/" #'comment-line "注释" "基础移动与直达键")
(self/bind "C-_" #'comment-line "注释" "基础移动与直达键")
(self/bind "C-S-c" #'self/copy-dwim "复制" "基础移动与直达键")
(self/bind "C-S-v" #'yank "粘贴" "基础移动与直达键")
(self/bind "M-y" #'yank-from-kill-ring "从剪贴环选择粘贴" "基础移动与直达键")
(self/bind "C-S-x" #'self/cut-dwim "剪切(行/选区)" "基础移动与直达键")
(self/bind "C-S-w" #'kill-current-buffer "关闭缓冲区" "基础移动与直达键")
(self/bind "C-S-d" #'duplicate-dwim "复制当前行" "基础移动与直达键")
(self/bind "C-S-<up>" #'self/code-move-line-up "上移当前行" "基础移动与直达键")
(self/bind "C-S-<down>" #'self/code-move-line-down "下移当前行" "基础移动与直达键")
(self/bind "C-<return>" #'self/open-line-below "下方开行" "基础移动与直达键")
(self/bind "C-S-<return>" #'self/open-line-above "上方开行" "基础移动与直达键")
(self/bind "<home>" #'self/home-dwim "智能行首" "基础移动与直达键")
(self/bind "C-S-/" #'comment-box "块注释" "基础移动与直达键")
(self/bind "C-S-s" #'write-file "另存为" "基础移动与直达键")
(self/bind "C-S-a" #'project-find-file "项目文件搜索" "基础移动与直达键")
(self/bind "<f2>" #'self/rename-dwim "重命名" "基础移动与直达键")
(self/bind "C-<f12>" #'xref-find-definitions "跳转到定义" "基础移动与直达键")
(self/bind "C-S-<f12>" #'xref-find-references "查找引用" "基础移动与直达键")
(self/bind "C-`" #'self/open-terminal "打开终端" "基础移动与直达键")
(self/bind "C-=" #'text-scale-increase "放大" "基础移动与直达键")
(self/bind "C--" #'text-scale-decrease "缩小" "基础移动与直达键")
(self/bind "C-0" (lambda () (interactive) (text-scale-set 0)) "重置缩放" "基础移动与直达键")
(self/bind "M-<left>" #'windmove-left "左切窗口" "基础移动与直达键")
(self/bind "M-<right>" #'windmove-right "右切窗口" "基础移动与直达键")
(self/bind "M-<up>" #'windmove-up "上切窗口" "基础移动与直达键")
(self/bind "M-<down>" #'windmove-down "下切窗口" "基础移动与直达键")

;; ─── 全局直达键：跳转、调试、面板直达、窗口 ───────────────────────────
;;
;; 跳转与调试：<f12> 定义、S-<f12> 引用、<f2> 重命名、C-. 快速修复、
;; <f8>/S-<f8> 错误跳转、<f5> 调试、<f9> 断点。
;; 面板直达：C-b 文件面板开关、C-S-e 文件面板、C-S-g Git 状态、C-S-m 诊断、
;; C-S-u 消息输出（对齐 VSCode 的 Explorer / SCM / Problems / Output 槽位）。

(self/bind "<f12>" #'xref-find-definitions "跳转到定义" "基础移动与直达键")
(self/bind "S-<f12>" #'xref-find-references "查找引用" "基础移动与直达键")
(self/bind "C-." #'eglot-code-actions "快速修复" "基础移动与直达键")
(self/bind "C-d" #'mc/mark-next-like-this-word "选中下一个匹配" "基础移动与直达键")
(self/bind "C-S-l" #'mc/mark-all-like-this "选中所有匹配" "基础移动与直达键")
(self/bind "C-S-k" #'kill-whole-line "删除整行" "基础移动与直达键")
(self/bind "C-S-t" #'self/reopen-closed-file "重开已关闭文件" "基础移动与直达键")
(self/bind "<f11>" #'toggle-frame-fullscreen "切换全屏" "基础移动与直达键")
(self/bind "<f5>" #'dape "开始调试" "基础移动与直达键")
(self/bind "<f9>" #'dape-breakpoint-toggle "切换断点" "基础移动与直达键")
(self/bind "<f8>" #'flymake-goto-next-error "下一个错误" "基础移动与直达键")
(self/bind "S-<f8>" #'flymake-goto-prev-error "上一个错误" "基础移动与直达键")
(self/bind "M-S-f" #'apheleia-format-buffer "格式化缓冲区" "基础移动与直达键")
(self/bind "C-S-e" #'self/panel-dired "文件面板" "基础移动与直达键")
(self/bind "C-b" #'self/panel-dired-toggle "文件面板开关" "基础移动与直达键")
(self/bind "C-S-g" #'magit-status "Git 状态面板" "基础移动与直达键")
(self/bind "C-S-m" #'self/flymake-list-errors-dwim "诊断面板" "基础移动与直达键")
(self/bind "C-S-u" #'view-echo-area-messages "消息输出面板" "基础移动与直达键")
(self/bind "C-S-b" #'project-compile "项目构建" "基础移动与直达键")
(self/bind "C-S-n" #'make-frame-command "新建窗口 (frame)" "基础移动与直达键")
(self/bind "C-," #'self/open-config-source "打开设置 (emacs.org)" "基础移动与直达键")

;; minibuffer 里 C-d 应删字符，而不是像 Emacs 24+ 那样绑定到 kill-line；
;; isearch 会话内同理——isearch 是 preloaded 特性，改键放在 eval-after-load 里。
(define-key minibuffer-local-map (kbd "C-d") #'delete-char)
(with-eval-after-load 'isearch
  (keymap-set isearch-mode-map "C-d" #'isearch-del-char))

;; ─── 缓冲区开关与退出命令（C-c t / C-c q）─────────────────────────────
;;
;; C-c t：当前缓冲区开关（行号 l、软折行 w、列宽指示线 c、语法诊断 f、
;; 拼写检查 s、只读 r、不可见文本 v、错误调试 d）。
;; C-c q：窗口退出与 Frame 关闭（f 当前、o 其他、q 保存并退出）。

(self/bind "C-c t l" #'display-line-numbers-mode "行号" "开关")
(self/bind "C-c t w" #'visual-line-mode "软折行" "开关")
(self/bind "C-c t c" #'display-fill-column-indicator-mode "列宽指示线" "开关")
(self/bind "C-c t f" #'flymake-mode "语法诊断" "开关")
(self/bind "C-c t s" #'flyspell-mode "拼写检查" "开关")
(self/bind "C-c t r" #'read-only-mode "只读" "开关")
(self/bind "C-c t v" #'visible-mode "显示不可见文本" "开关")
(self/bind "C-c t d" #'toggle-debug-on-error "错误调试" "开关")

(self/bind "C-c q f" #'delete-frame "关闭当前 Frame" "退出与 Frame")
(self/bind "C-c q o" #'delete-other-frames "关闭其他 Frame" "退出与 Frame")
(self/bind "C-c q q" #'save-buffers-kill-terminal "保存并退出 Emacs" "退出与 Frame")

;; ─── 窗口面板体系与布局总开关（C-c w）─────────────────────────────────
;;
;; 三面板一键总开关 C-c w T：类似现代编辑器的侧边栏停靠管理，一键展开或
;; 折叠左侧文件树、底部终端与右侧 Agent 面板，焦点自动回到主编辑区。
;; 布局重构与分屏（Emacs 31）：窗口树旋转、镜像、横竖转置、窗口内容轮转、
;; 临时合并与多 Frame 分屏移动；数字键 C-c w 0/1/2/3 与内建 C-x 0/1/2/3
;; 对偶。C-\ 一键向右分屏并聚焦新窗口（VSCode Ctrl+\）。
;; 面板定位 C-c w d：文件面板切到当前文件所在目录并选中文件行
;; （Explorer 的 Reveal in Explorer 等价物）。

(defun self/panels-toggle ()
  "一键开关三面板布局（左 Dired / 底终端 / 右 Agent）。
任一面板已显示则全部隐藏（缓冲区保留，终端与 agent 会话不中断）；
全部隐藏时重新打开。开关后焦点均回到主编辑窗口（Zed dock 行为）。
显隐判断只用已存在的 buffer：dired 按 dired-noselect 的复用规则查找
（dired-mode + dired-directory 匹配项目根），不为判断新建 buffer。
交互命令：M-x self/panels-toggle，也绑在 C-c w T。"
  (interactive)
  (let* ((root (expand-file-name (self/project-root-or-default)))
         (dired-buf (seq-find
                     (lambda (buf)
                       (with-current-buffer buf
                         (and (stringp dired-directory)
                              (equal (expand-file-name dired-directory)
                                     root))))
                     (self--buffers-in-mode 'dired-mode)))
         (buffers (append
                   (remq nil (list dired-buf
                                   (self--terminal-existing-buffer)))
                   (self--buffers-in-mode 'agent-shell-mode))))
    (if (seq-some #'get-buffer-window buffers)
        (dolist (buf buffers)
          (when-let* ((win (get-buffer-window buf)))
            (delete-window win)))
      (self/panel-dired)
      (self/open-terminal)
      (agent-shell)))
  (when-let* ((main (seq-find
                     (lambda (w) (not (window-parameter w 'window-side)))
                     (window-list (selected-frame)))))
    (select-window main)))

(defun self/split-window-right-follow ()
  "向右分屏并把焦点移到新窗口（VSCode Ctrl+\\）。
交互命令：M-x self/split-window-right-follow，也绑在 C-\\。"
  (interactive)
  (split-window-right)
  (other-window 1))

;; 终端下 M-方向键会被终端协议拦截，这里在 C-c w 下提供字符镜像。
(self/bind "C-c w h" #'windmove-left "左切窗口" "窗口与面板")
(self/bind "C-c w j" #'windmove-down "下切窗口" "窗口与面板")
(self/bind "C-c w k" #'windmove-up "上切窗口" "窗口与面板")
(self/bind "C-c w l" #'windmove-right "右切窗口" "窗口与面板")

(self/bind "C-\\" #'self/split-window-right-follow "右侧分屏" "窗口与面板")
(self/bind "C-c w f" #'self/panel-dired "文件面板" "窗口与面板")
(self/bind "C-c w d" #'self/panel-dired-reveal "面板定位当前文件" "窗口与面板")
(self/bind "C-c w t" #'self/open-terminal "终端面板" "窗口与面板")
(self/bind "C-c w a" #'agent-shell "Agent 面板" "窗口与面板")
(self/bind "C-c w T" #'self/panels-toggle "三面板总开关" "窗口与面板")
(self/bind "C-c w u" #'winner-undo "撤销窗口变更" "窗口与面板")
(self/bind "C-c w r" #'winner-redo "重做窗口变更" "窗口与面板")
(self/bind "C-c w <right>" #'window-layout-rotate-clockwise "顺时针旋转布局" "窗口与面板")
(self/bind "C-c w <left>" #'window-layout-rotate-anticlockwise "逆时针旋转布局" "窗口与面板")
(self/bind "C-c w <up>" #'window-layout-flip-topdown "上下镜像布局" "窗口与面板")
(self/bind "C-c w <down>" #'window-layout-flip-leftright "左右镜像布局" "窗口与面板")
(self/bind "C-c w x" #'window-layout-transpose "转置窗口分割" "窗口与面板")
(self/bind "C-c w o" #'rotate-windows "轮转窗口内容" "窗口与面板")
(self/bind "C-c w O" #'rotate-windows-back "逆向轮转窗口内容" "窗口与面板")
(self/bind "C-c w c" #'combine-windows "合并窗口为组" "窗口与面板")
(self/bind "C-c w C" #'uncombine-window "恢复窗口分组" "窗口与面板")
(self/bind "C-c w s" #'split-frame "拆分窗口到新 Frame" "窗口与面板")
(self/bind "C-c w S" #'merge-frames "合并 Frame 窗口" "窗口与面板")
(self/bind "C-c w =" #'balance-windows "平衡窗口大小" "窗口与面板")
(self/bind "C-c w 0" #'delete-window "关闭当前窗口" "窗口与面板")
(self/bind "C-c w 1" #'delete-other-windows "只保留当前窗口" "窗口与面板")
(self/bind "C-c w 2" #'split-window-below "上下分屏" "窗口与面板")
(self/bind "C-c w 3" #'split-window-right "左右分屏" "窗口与面板")

(provide 'self-keys-desktop)

;;; self-keys-desktop.el ends here
