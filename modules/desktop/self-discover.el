;;; self-discover.el --- Emacs 独门特性发现层：窄化/寄存器/宏/矩形/间接缓冲/Ediff -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, ide
;; Requires: self-keys（`self/bind'、`self/declare-binding-group'）
;; Packages: 无（本模块只做内建机制的显式化，零第三方依赖）
;;
;; full 档的目标体验是「把 Emacs 当 Emacs 用」：让用户学到并掌握其它
;; 编辑器里没有同构物的机制——窄化（Narrowing）、寄存器、矩形编辑、
;; 键盘宏、间接缓冲、Sexp 结构化编辑、Ediff、hi-lock、递归
;; minibuffer……这些命令大多有内建键位，但入口深埋且无中文提示，
;; 新手根本意识不到它们存在。
;;
;; 本模块做两件事：
;;
;;   1. *再声明*：对内建键位用 `self/bind' 按「同键、同命令」原样再
;;      登记一遍。行为零变化（写入的目标与默认绑定相同，幂等），换来
;;      的是 Which-key 中文提示与 `self:binding-spec' 条目——帮助页
;;      只认这张表，不登记的内建键位在 <f1> ? 速查表里等于不存在。
;;      查重闸只拦本配置内部的重复声明，对 Emacs 出厂键位不生效。
;;   2. *补齐*：少数值得默认打开的行为开关（标记环连按、kill-ring
;;      去重、递归 minibuffer、解除 disabled 限制），以及缺默认键位的
;;      新绑定（C-x C-k i、C-x 4 n、C-x n t 等）。
;;
;; ─── 为什么是一个独立模块而不是并进 self-editing ─────────────────────
;;
;; self-editing 是三档共用底座（minimal 也加载），它的内容是「编辑就该
;; 有的基础体感」；本模块是「按 Emacs 语义重学一遍」的选修面，只被
;; full / ide 勾选。合进去会让 minimal 背上它不需要的键位面。
;;
;; ─── 使用指引 ────────────────────────────────────────────────────────
;;
;; · <f1> ? 打开快捷键帮助页，本模块贡献的分组：窄化、寄存器与矩形、
;;   键盘宏、结构化编辑、求值、比较与差异。
;; · 窄化中的 buffer 状态由 mode-line 的 `mode-line-modes' 段给出
;;   Narrow 标志；恢复永远是 C-x n w，忘路时先按它。
;; · 宏持久化三步：C-x C-k n 命名 → C-x C-k i 生成 Lisp 定义 →
;;   把输出贴进自己的配置（C-h f insert-kbd-macro 看细节）。
;; · 无键位的独门功能集中提示在 data/help-zh.el 的导读段：Wdired
;;   （Dired 里 C-x C-q 把文件名当文本改）、occur-edit（Occur 结果页
;;   按 e 直接编辑回写）、undo-in-region（有选区时 undo 只撤销选区）、
;;   repeat-complex-command（C-x ESC ESC 回放复杂命令）。

;;; Code:

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))
(declare-function describe-repeat-maps "repeat")

;; 懒加载库里的变量就近声明（不带值），消除 byte-compile 自由变量告警。
(defvar apropos-do-all)
(defvar dired-dwim-target)
(defvar wdired-allow-to-change-permissions)
(defvar ediff-window-setup-function)

;; ─── 值得默认打开的内建开关 ────────────────────────────────────────
;;
;; 每项一行一注：这几个变量定义在懒加载库里，直接 setq 先占住值，
;; 库加载时 defcustom 遇到已绑定的变量不会覆盖（defvar 语义）。

(setq set-mark-command-repeat-pop t           ; C-u C-SPC 后连按 C-SPC 继续弹标记环
      kill-do-not-save-duplicates t           ; kill-ring 不收重复条目
      save-interprogram-paste-before-kill t   ; 系统剪贴板内容入环后再被覆盖
      apropos-do-all t                        ; C-h a 搜索全部符号而非仅命令
      enable-recursive-minibuffers t          ; minibuffer 里允许再开 minibuffer
      dired-dwim-target t                     ; 双 Dired 窗口时拷贝/移动目标自动为对面
      wdired-allow-to-change-permissions t    ; Wdired 里可直接改权限位
      ediff-window-setup-function 'ediff-setup-windows-plain) ; Ediff 单帧三窗，不弹控制 frame

;; 递归 minibuffer 打开后，深度指示让「当前在几层」可见（Emacs 28+ 内建）。
(minibuffer-depth-indicate-mode 1)

;; Emacs 出厂把「容易吓到新手」的命令标成 disabled——首次执行会弹确认。
;; 本档面向学习，确认一次后它们就该静默可用，故直接摘除标记。
(dolist (command '(narrow-to-region narrow-to-page
                   upcase-region downcase-region
                   scroll-left scroll-right))
  (put command 'disabled nil))

;; ─── 窄化（Narrowing）── C-x n ────────────────────────────────────
;;
;; 把 buffer 暂时收窄到选区/函数/页来专注编辑，其余文本隐身但完好。
;; C-x n t 是本模块新增的 DWIM 开关：已窄化则恢复，有选区收窄到选区，
;; 否则收窄到当前函数。

(self/declare-binding-group "C-x n" "窄化 (Narrowing)")

(defun self/narrow-dwim ()
  "窄化/恢复切换：已窄化则 `widen'；有选区收窄到选区；否则收窄到当前函数。
交互命令：M-x self/narrow-dwim，也绑在 C-x n t。"
  (interactive)
  (cond
   ((buffer-narrowed-p) (widen))
   ((use-region-p) (narrow-to-region (region-beginning) (region-end)))
   (t (narrow-to-defun))))

(self/bind "C-x n n" #'narrow-to-region "窄化到选区" "窄化")
(self/bind "C-x n d" #'narrow-to-defun "窄化到函数" "窄化")
(self/bind "C-x n w" #'widen "恢复全缓冲" "窄化")
(self/bind "C-x n p" #'narrow-to-page "窄化到页" "窄化")
(self/bind "C-x n g" #'goto-line-relative "窄化内跳行" "窄化")
(self/bind "C-x n t" #'self/narrow-dwim "窄化/恢复切换" "窄化")

;; ─── 寄存器 / 矩形 / 书签 ─── C-x r 与 C-x SPC ─────────────────────
;;
;; 寄存器是 Emacs 的「命名剪贴板 + 快照箱」：文本、位置、窗口布局、
;; Frame 布局各存一格，C-x r SPC 存位置 / C-x r j 跳回是最常用的对儿。
;; 书签是带名字的持久化位置（跨会话）；矩形编辑把选区换成「列块」，
;; C-x SPC 进入矩形选区后 C-w/M-w/粘贴全部按块操作。

(self/declare-binding-group "C-x r" "寄存器 / 矩形 / 书签")

(self/bind "C-x r SPC" #'point-to-register "存光标位置到寄存器" "寄存器与矩形")
(self/bind "C-x r j" #'jump-to-register "跳到寄存器" "寄存器与矩形")
(self/bind "C-x r s" #'copy-to-register "存选区到寄存器" "寄存器与矩形")
(self/bind "C-x r i" #'insert-register "插入寄存器内容" "寄存器与矩形")
(self/bind "C-x r n" #'number-to-register "存数字到寄存器" "寄存器与矩形")
(self/bind "C-x r F" #'file-to-register "存文件位置到寄存器" "寄存器与矩形")
(self/bind "C-x r w" #'window-configuration-to-register "存窗口布局到寄存器" "寄存器与矩形")
(self/bind "C-x r f" #'frameset-to-register "存 Frame 布局到寄存器" "寄存器与矩形")
(self/bind "C-x r r" #'copy-rectangle-to-register "存矩形到寄存器" "寄存器与矩形")
(self/bind "C-x r m" #'bookmark-set "设置书签" "寄存器与矩形")
(self/bind "C-x r b" #'bookmark-jump "跳转书签" "寄存器与矩形")
(self/bind "C-x r l" #'bookmark-bmenu-list "书签列表" "寄存器与矩形")
(self/bind "C-x SPC" #'rectangle-mark-mode "矩形选区开关" "寄存器与矩形")
(self/bind "C-x r t" #'string-rectangle "矩形填充/替换" "寄存器与矩形")
(self/bind "C-x r k" #'kill-rectangle "矩形剪切" "寄存器与矩形")
(self/bind "C-x r y" #'yank-rectangle "矩形粘贴" "寄存器与矩形")
(self/bind "C-x r o" #'open-rectangle "矩形右侧开空白" "寄存器与矩形")
(self/bind "C-x r c" #'clear-rectangle "矩形清空" "寄存器与矩形")
(self/bind "C-x r N" #'rectangle-number-lines "矩形行编号" "寄存器与矩形")

;; ─── 键盘宏 ─── F3/F4、C-x ( 系与 C-x C-k ─────────────────────────
;;
;; 键盘宏把一串操作录下来重放：F3 开始录、F4 结束或回放是最顺手的入口，
;; C-x ( / C-x ) / C-x e 是 Emacs 经典三键。C-x C-k 前缀下有整棵宏树：
;; 编辑、命名、对选区逐行执行、执行中交互确认，以及把宏写成 Lisp 持久化。
;;
;; C-x C-k 的子 keymap 是懒加载占位符号，往里写新键（C-x C-k i）会先
;; 拉起 kmacro.el；显式 require 把这次加载摆在明面上，也让
;; kmacro-edit-lossage 等名字在 byte-compile 期可解析。
(require 'kmacro)

(self/declare-binding-group "C-x C-k" "键盘宏")

(self/bind "<f3>" #'kmacro-start-macro-or-insert-counter "宏：开始录制/插计数" "键盘宏")
(self/bind "<f4>" #'kmacro-end-or-call-macro "宏：结束/回放" "键盘宏")
(self/bind "C-x (" #'kmacro-start-macro "开始录制宏" "键盘宏")
(self/bind "C-x )" #'kmacro-end-macro "结束录制宏" "键盘宏")
(self/bind "C-x e" #'kmacro-end-and-call-macro "结束并回放宏" "键盘宏")
(self/bind "C-x q" #'kbd-macro-query "宏执行中交互确认" "键盘宏")
(self/bind "C-x C-k e" #'edit-kbd-macro "编辑宏" "键盘宏")
(self/bind "C-x C-k l" #'kmacro-edit-lossage "最近按键转宏" "键盘宏")
(self/bind "C-x C-k n" #'kmacro-name-last-macro "命名最近宏" "键盘宏")
(self/bind "C-x C-k r" #'apply-macro-to-region-lines "选区逐行执行宏" "键盘宏")
(self/bind "C-x C-k i" #'insert-kbd-macro "把命名宏写成 Lisp" "键盘宏")

;; ─── 间接缓冲与「其他窗口」─── C-x 4 ───────────────────────────────
;;
;; 间接缓冲与原 buffer 共享同一份文本，但各有自己的光标、窄化与选区：
;; 同一文件「全览 + 窄化到某函数」两个视图就靠它。C-x 4 c 在其他窗口
;; 克隆（内建），C-x 4 n 在当前窗口克隆（本模块新增）。

(self/declare-binding-group "C-x 4" "其他窗口 / Frame")

(self/bind "C-x 4 c" #'clone-indirect-buffer-other-window "克隆间接缓冲（其他窗口）" "间接缓冲")
(self/bind "C-x 4 n" #'clone-indirect-buffer "克隆间接缓冲（本窗口）" "间接缓冲")
(self/bind "C-x C-j" #'dired-jump "回到当前文件的 Dired 目录" "文件 / 缓冲区 / 窗口 / 标签")
(self/bind "C-x C-SPC" #'pop-global-mark "弹全局标记（跨缓冲回跳）" "基础移动与直达键")

;; ─── 结构化编辑（Sexp 导航）─── C-M-* ──────────────────────────────
;;
;; 按「表达式/括号/函数」而非字符移动：在任何语言里 C-M-f/b 按括号语义
;; 跳，Lisp 里则是真正的语法单元。先学 C-M-f/b/u/d 四个移动，
;; 再学 C-M-t 交换、C-M-SPC 标记、C-M-a/e/h 函数级操作。

(self/bind "C-M-f" #'forward-sexp "前向表达式" "结构化编辑")
(self/bind "C-M-b" #'backward-sexp "后向表达式" "结构化编辑")
(self/bind "C-M-u" #'backward-up-list "上跳出括号" "结构化编辑")
(self/bind "C-M-d" #'down-list "下进入括号" "结构化编辑")
(self/bind "C-M-k" #'kill-sexp "删除表达式" "结构化编辑")
(self/bind "C-M-t" #'transpose-sexps "交换相邻表达式" "结构化编辑")
(self/bind "C-M-SPC" #'mark-sexp "标记表达式" "结构化编辑")
(self/bind "C-M-a" #'beginning-of-defun "跳到函数头" "结构化编辑")
(self/bind "C-M-e" #'end-of-defun "跳到函数尾" "结构化编辑")
(self/bind "C-M-h" #'mark-defun "标记整个函数" "结构化编辑")

;; ─── 求值与命令回放 ────────────────────────────────────────────────
;;
;; Emacs 是一台活的 Lisp 机：C-x C-e 就地求值光标前的表达式，
;; 配置写一半就能验证；C-x ESC ESC 把最近一条复杂命令连同参数完整
;; 摆回 minibuffer 里改改再跑——两者都是「改配置立刻见结果」的回路。

(self/bind "C-x C-e" #'eval-last-sexp "求值光标前表达式" "求值")
(self/bind "C-M-x" #'eval-defun "求值顶层表达式" "求值")
(self/bind "M-:" #'eval-expression "求值表达式" "求值")
(self/bind "C-x ESC ESC" #'repeat-complex-command "回放最近复杂命令" "求值")

;; ─── 比较与差异（Ediff）─── C-c d ─────────────────────────────────
;;
;; Ediff 是 Emacs 的可视化 diff/merge 界面：两/三份内容逐块对照，
;; 按 a/b 选边把差异块拷到对方。顶层前缀「C-c d」的登记在 self-keys
;; 的前缀目录里（其余顶层前缀也在那里）。

(self/bind "C-c d d" #'diff-buffer-with-file "缓冲与磁盘文件对比" "比较与差异")
(self/bind "C-c d b" #'ediff-buffers "两缓冲 Ediff 对比" "比较与差异")
(self/bind "C-c d f" #'ediff-files "两文件 Ediff 对比" "比较与差异")
(self/bind "C-c d 3" #'ediff-buffers3 "三缓冲 Ediff 合并" "比较与差异")
(self/bind "C-c d r" #'ediff-revision "与历史版本 Ediff 对比" "比较与差异")

;; ─── 搜索的行级操作与高亮 ─── M-s ──────────────────────────────────
;;
;; occur 之外的同族独门：keep/flush-lines 按正则保/删整行，how-many
;; 只数不跳；hi-lock 是交互式高亮（M-s h 前缀），写注释、读日志时
;; 让关键词一直亮着，还能把高亮规则写回文件持久化。

(self/declare-binding-group "M-s h" "高亮 (hi-lock)")

(self/bind "M-s k" #'keep-lines "只保留匹配行" "搜索")
(self/bind "M-s x" #'flush-lines "删除匹配行" "搜索")
(self/bind "M-s n" #'how-many "计数匹配" "搜索")
(self/bind "M-s h r" #'highlight-regexp "高亮正则" "搜索")
(self/bind "M-s h ." #'highlight-symbol-at-point "高亮光标符号" "搜索")
(self/bind "M-s h l" #'highlight-lines-matching-regexp "高亮匹配行" "搜索")
(self/bind "M-s h u" #'unhighlight-regexp "取消高亮" "搜索")
(self/bind "M-s h w" #'hi-lock-write-interactive-patterns "高亮规则写入文件" "搜索")

;; ─── 窗口独门 ──────────────────────────────────────────────────────
;;
;; follow-mode 让并排两个窗口显示同一份 buffer 的连续段落（长文双栏
;; 连续阅读）；scroll-all-mode 让滚动命令同步滚动全部窗口（并排 diff
;; 两份文件时尤其趁手）。

(self/bind "C-c w F" #'follow-mode "双窗连续阅读" "窗口与面板")
(self/bind "C-c w A" #'scroll-all-mode "联动滚动全部窗口" "窗口与面板")

;; ─── 编辑变换补遗 ──────────────────────────────────────────────────
;;
;; 这一组是「有选区/光标处就能用」的内建变换：选区大小写（已解除
;; disabled）、行/词级交换、dabbrev 动态缩写补全（无需补全框架），
;; 以及补进 C-c e 表的清理与排序。

(self/bind "C-x C-u" #'upcase-region "选区转大写" "编辑变换")
(self/bind "C-x C-l" #'downcase-region "选区转小写" "编辑变换")
(self/bind "C-x C-t" #'transpose-lines "交换相邻行" "编辑变换")
(self/bind "M-t" #'transpose-words "交换相邻词" "编辑变换")
(self/bind "M-^" #'delete-indentation "并入上一行" "编辑变换")
(self/bind "M-/" #'dabbrev-expand "动态缩写补全" "编辑变换")
(self/bind "C-c e w" #'whitespace-cleanup "清理空白" "编辑变换")
(self/bind "C-c e S" #'sort-lines "排序选区行" "编辑变换")

;; ─── 独门应用入口 ─── C-c a ────────────────────────────────────────
;;
;; 生活应用前缀下补四个纯内建的「 Emacs 才有」入口：eshell（Lisp 写的
;; shell，命令输出可当文本编辑）、ielm（Elisp REPL）、calc（栈式科学
;; 计算器）、proced（进程管理器，Emacs 自己的 htop）。

(self/bind "C-c a e" #'eshell "Eshell (Lisp shell)" "生活应用")
(self/bind "C-c a i" #'ielm "IELM (Elisp REPL)" "生活应用")
(self/bind "C-c a c" #'calc "Calc 计算器" "生活应用")
(self/bind "C-c a p" #'proced "进程管理器" "生活应用")

;; ─── 帮助补遗 ──────────────────────────────────────────────────────
;;
;; describe-repeat-maps 列出 repeat-mode 认得的全部「连按表」（比如
;; 窗口调整后可连按方向键）。repeat.el 懒加载，包一层先 require 再调，
;; 避免键位先于库加载时报 void-function。

(defun self/describe-repeat-maps ()
  "列出 repeat-mode 的全部连按键映射（哪些命令按完后可连按尾键）。
交互命令：M-x self/describe-repeat-maps，也绑在 C-c h r。"
  (interactive)
  (require 'repeat)
  (call-interactively #'describe-repeat-maps))

(self/bind "C-c h r" #'self/describe-repeat-maps "可连按命令一览" "帮助")

(provide 'self-discover)

;;; self-discover.el ends here
