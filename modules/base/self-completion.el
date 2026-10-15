;;; self-completion.el --- 补全框架：minibuffer 匹配、isearch IDE 化、行内补全 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: minimal, portable, full, ide
;; Requires: 无（外部命令名常量由 core/self-lib.el 提供，加载顺序天然在前）
;; Packages: vertico, orderless, marginalia, consult, embark, embark-consult,
;;           corfu, cape（全部只出现在 Android 平台分支里）
;;
;; 三档共用的补全基座全部是 Emacs 内建能力：flex 模糊匹配 + 行内幽灵文本
;; （completion-preview.el，Emacs 30 起随 Emacs 分发）+ isearch 的 IDE 化
;; 交互 + aspell 后端 + 回显行降噪。源配置这一整节本来就声明「完全基于
;; Emacs 30 与 31 原生内置的补全机制，不依赖任何第三方补全框架」，故
;; minimal 档可整份取用，不受「不得声明任何第三方包」的约束。
;;
;; 移动端另有一整套第三方补全栈（vertico / orderless / marginalia /
;; consult / embark / corfu / cape），那是触屏候选可点选的需求，整块收在
;; `(when self:android-p …)' 平台分支里——按 AGENTS.md §2，平台差异用
;; 平台谓词在模块内部守卫，不做成档位裁剪。
;;
;; ─── 机制说明 ──────────────────────────────────────────────────────
;;
;; 1. Minibuffer 模糊匹配。Emacs 31 内置的 `*Completions*' 候选窗口默认
;;    随打随滤。桌面开启 flex 模糊匹配并以 basic 前缀匹配兜底——输入 mbl
;;    即可直接命中 magit-blame；触屏换 orderless（子序列匹配，长中文候选
;;    里更少误排）。historical 排序让 savehist 记录的高频命令排在前面。
;; 2. 行内幽灵文本（Ghost-Text）。代码编辑区用内置 completion-preview-mode
;;    在光标右侧呈现灰色预览；TAB 直接接受，M-n / M-p 循环候选。相比下拉
;;    菜单，行内预览更安静、不遮挡上下文。
;; 3. isearch 的 IDE 化交互。原生 isearch 是「模式」而非「组件」：RET 退出
;;    搜索、C-s / C-r 前后循环、选区文本不会自动带入搜索串——与 VSCode /
;;    Zed 的 Find Widget（Enter 跳下一个、Esc 关闭、选中即搜索词）语义相反。
;;    本模块把键位语义对齐到 widget 模型，并给 isearch 的过程键补上可发现性。
;; 4. 回显行降噪。inhibit-message-regexps 是一张通用静音表：只压回显区，
;;    消息照写进 `*Messages*'，出问题时仍可回溯。
;;
;; ─── 对外提供的符号 ────────────────────────────────────────────────
;;
;;   self/isearch-forward-dwim          交互命令：带选区种子的 isearch
;;   self/isearch-message-hint-append   advice：回显行末尾追加速查提示
;;   self/completion-text-ispell-setup  text-mode 回调：接 aspell 后端
;;   self:isearch-hint                  常量：速查提示文本
;;   self:aspell-available              常量：启动时的 aspell 可用性
;;
;; which-key 的中文化与视觉层不在本文件——那属 self-help-zh。

;;; Code:

;; 外部命令名常量归 core/self-lib.el 定义，这里只声明不赋值。
(defvar self:executable-aspell)
(defvar ispell-program-name)   ; 拼写后端可执行文件名
(defvar ispell-extra-args)    ; aspell 额外参数

;; Android 分支的第三方补全栈入口函数：包全部延迟加载，byte-compile 时
;; 看不到定义，逐个声明以免误报。
(declare-function vertico-mode "vertico")
(declare-function vertico-mouse-mode "vertico")
(declare-function marginalia-mode "marginalia")
(declare-function global-corfu-mode "corfu")
(declare-function cape-file "cape")

;; ─── Minibuffer 匹配与排序 ──────────────────────────────────────────
;;
;; flex 模糊匹配负责「mbl → magit-blame」这类跳跃式输入，basic 前缀匹配
;; 兜底保证任何合法前缀都能命中；触屏换 orderless（子序列匹配，长候选列表
;; 里误排更少）。completions-sort 用 historical 让常用命令自然浮到顶部。
(setq completion-styles (if self:android-p '(orderless basic) '(flex basic))
      completions-sort 'historical)

;; ─── 行内幽灵文本 ───────────────────────────────────────────────────
;;
;; :demand t 表示配置加载时立刻 require completion-preview：这样 :config 里的
;; global-completion-preview-mode 与键位改写才拿得到
;; completion-preview-active-mode-map（该 keymap 在库被加载前并不 bound）。
(use-package completion-preview
  :demand t
  :config
  (global-completion-preview-mode 1)
  (define-key completion-preview-active-mode-map (kbd "M-n")
              #'completion-preview-next-candidate)
  (define-key completion-preview-active-mode-map (kbd "M-p")
              #'completion-preview-prev-candidate)
  (define-key completion-preview-active-mode-map [remap forward-word]
              #'completion-preview-insert-word)
  (define-key completion-preview-active-mode-map [remap forward-sexp]
              #'completion-preview-insert-sexp))

;; ─── 搜索导航增强 ───────────────────────────────────────────────────
;;
;; isearch-lazy-count：增量搜索时在回显区实时显示 3/15 这样的匹配序号，
;; 长文件里定位全靠它。grep-use-headings：搜索结果按文件成组分节。
;; 在 *grep* 缓冲区内按 e 就地编辑、随时 C-c C-c 批量写回，是内建能力，
;; 无需配置。
(setq isearch-lazy-count t)

(with-eval-after-load 'grep
  (setq grep-use-headings t))

;; ─── isearch 的 IDE 化交互 ──────────────────────────────────────────
;;
;; 键位语义对齐 VSCode / Zed 的 Find Widget：
;;   RET / S-RET       跳到下一个 / 上一个匹配（而非退出搜索）
;;   ESC               停在当前匹配并关闭搜索框（而非取消回起点）
;;   C-g               仍是「取消并回到起点」
;; 触底回绕不闪屏靠 isearch-wrap-pause 的 'no-ding。
(setq isearch-wrap-pause 'no-ding)

(defun self/isearch-forward-dwim ()
  "启动增量搜索；有活跃选区时先把选区文本填进搜索串。
对应 VSCode 选中一段后按 Ctrl+F 的行为。

第二个参数 t（NO-RECURSIVE-EDIT）让启动调用立即返回，搜索过程由
overriding keymap 继续读键；只有这样 `isearch-yank-string' 才能在
isearch 仍处活跃状态时把种子写进搜索串。直接调 `(isearch-forward)'
会进入递归编辑，等它返回时搜索已经退出，yank 就落空了。
交互命令：M-x self/isearch-forward-dwim，也绑在 M-s i 与 C-S-f。"
  (interactive)
  ;; 先取选区文本再 deactivate-mark：region 信息取完就没了。
  (let ((seed (when (use-region-p)
                (buffer-substring-no-properties
                 (region-beginning) (region-end)))))
    (deactivate-mark)
    (isearch-forward nil t)
    (when seed
      (isearch-yank-string seed))))

(with-eval-after-load 'isearch
  (keymap-set isearch-mode-map "RET" #'isearch-repeat-forward)
  (keymap-set isearch-mode-map "S-<return>" #'isearch-repeat-backward)
  (keymap-set isearch-mode-map "<escape>" #'isearch-exit))
;; 源配置里还有一条 (define-key isearch-mode-map "\e\e" #'isearch-exit)：
;; 那是终端下 ESC ESC 的双击手势，在 GUI 上根本发不出来，等于死绑定
;; （真要双 ESC，Emacs 自带 pre-command-hook 的 isearch-double-escape
;; 已处理），故只保留上面的 <escape> 单键。

;; ─── isearch 过程键引导 ─────────────────────────────────────────────
;;
;; isearch 是一个「按键即达」的会话：输入搜索串的任意时刻都能按 M-% 直接
;; 转替换、按 M-s o 把结果转成列表——但这些过程键默认零提示，不读手册完全
;; 不可发现。这里用两条通道补引导：
;;
;; · Which-key 弹窗：isearch 会话内按下 M-s 等前缀键停顿，Which-key 合并
;;   展示 isearch 键表与全局 M-s 子树。isearch 键表的中文词条在 which-key-ui
;;   域按 keymap 注册（由 self-help-zh 接线）。
;; · 回显行速查：M-% 、C-w 这类无前缀的顶层过程键不经过任何前缀弹窗，
;;   因此在回显行末尾常驻一条速查。
;;
;; 实现走 `isearch-message-suffix' 的 :filter-return advice：isearch 每次
;; 重绘回显行都调该函数生成 wrapped 一类的末尾状态注记，拼接一条常量串
;; 即可，不侵入渲染主逻辑。每键一次 concat，无热路径压力。
(defconst self:isearch-hint
  (propertize "  [M-s 更多 | M-% 替换 | C-w 取词]" 'face 'shadow)
  "isearch 回显行末尾常驻的过程键速查提示。")

(defun self/isearch-message-hint-append (suffix)
  "在原生 isearch 的末尾注记 SUFFIX 之后追加速查提示。
`isearch-message-suffix' 的返回值是 wrapped 一类的状态注记，常量串
直接拼在其后即可。"
  (concat suffix self:isearch-hint))

(advice-add 'isearch-message-suffix :filter-return
            #'self/isearch-message-hint-append)

;; ─── 区域内补全与拼写检查 ───────────────────────────────────────────
;;
;; · 动态单词补齐：M-/ （dabbrev-expand）按当前缓冲区已有的词补全长单词。
;;   dabbrev-check-all-buffers 设 nil，把扫描范围限制在同模式的缓冲区内，
;;   否则 Emacs 会遍历所有后台缓冲并逐个打印进度通知。
;; · 拼写检查：文本模式下用 Aspell 作 ispell 后端。aspell 是否可用只在加载
;;   时用 executable-find 探测一次，缓存的是布尔结果而非可执行文件路径——
;;   不违背「外部命令声明只存名字、不缓存 store 绝对路径」的公约；
;;   text-mode-hook 每开一个文本缓冲就能直接读结果，不再遍历一遍 exec-path。
;; · 补全源：直接复用 Major Mode 与 Eglot 提供的建议；Eglot 补全时 eldoc
;;   在 echo area 显示文档，Emacs 31 起的 C-u M-. （xref-find-apropos）
;;   能列出并补全当前 workspace 的符号。
;;
;; self:aspell-available 的取值是 defconst：加载时求值一次，之后整个会话
;; 不再重新探测。若用户中途装了 aspell 需重启 Emacs。
(defconst self:aspell-available
  (and (executable-find self:executable-aspell) t)
  "启动时一次性探测 aspell 是否可用；text-mode 回调直接读此值。")

(defun self/completion-text-ispell-setup ()
  "text-mode 回调：aspell 作 ispell 后端，并移除缺词表白跑的词表补全 capf。

拼写检查只报错不介入补全；ispell-completion-at-point 会拿字典词条当补全
候选，在文本模式下刷出一堆无关词，从 completion-at-point-functions 里摘掉。
"
  (require 'ispell)
  (when self:aspell-available
    (setq ispell-program-name self:executable-aspell
          ispell-extra-args '("--sug-mode=ultra")))
  (setq-local completion-at-point-functions
              (remq 'ispell-completion-at-point
                    completion-at-point-functions)))

(add-hook 'text-mode-hook #'self/completion-text-ispell-setup)

;; ─── 回显行降噪 ─────────────────────────────────────────────────────
;;
;; 同一张表同时管 dabbrev 与三类高频噪音：新开 client frame 时 server 的
;; 提示语、recentf 周期清理（recentf-show-messages 管不到它，消息是裸
;; message 调用）、以及 C-n/C-p 触底时每次按键都重复的边界提示（光标不动
;; 本身已是反馈，反复顶掉状态行左半的行号信息得不偿失）。
;;
;; inhibit-message-regexps 只静音回显，消息仍写进 `*Messages*`，出问题时
;; 可回溯——这是本表能承担通用降噪职责的前提。
(setq dabbrev-check-all-buffers nil
      inhibit-message-regexps
      '("Scanning for dabbrevs" "Expansion found in"
        "Beginning of buffer" "End of buffer"
        "When done with this frame" "When done with a buffer"
        "Cleaning up the recentf list" "removed from the recentf list"))

(add-to-list 'set-message-functions #'inhibit-message)

;; ─── Android 平台分支：第三方补全栈 ──────────────────────────────────
;;
;; 触屏没有物理键盘：候选列表要能滚动、要能点选、要点选后不弹系统键盘。
;; vertico + orderless + marginalia + consult + embark + corfu + cape 这一
;; 套就是为此组合的，桌面端用上面的内建方案即可，故整块按平台谓词守卫。
(when self:android-p
  (use-package vertico
    :init (vertico-mode)
          ;; 候选可点选（vertico 自带扩展）：真机 tap 经 touch-screen 翻译
          ;; 为 mouse-1（候选无 button/follow-link 属性，不会转 mouse-2），
          ;; 命中候选上的 vertico-mouse-map → RET 语义直接选中
          (vertico-mouse-mode)
    :custom (vertico-resize t))

  ;; tap 候选行选中后不唤系统键盘：候选 tap 解析出的命令不在
  ;; touch-screen-set-point-commands 内，display-keyboard 为 nil 时键盘
  ;; 逻辑只服务于 set-point 类命令；tap 输入区（mouse-set-point）仍照常
  ;; 唤键盘输入查询文本。桌面该变量本就为 nil，此设置无影响。
  (defvar touch-screen-display-keyboard)
  (add-hook 'minibuffer-setup-hook
            (lambda () (setq-local touch-screen-display-keyboard nil)))

  (use-package orderless)

  (use-package marginalia
    :init (marginalia-mode))

  ;; 搜索/导航：consult 接管 xref 展示
  (use-package consult
    :custom (xref-show-xrefs-function #'consult-xref)
            (xref-show-definitions-function #'consult-xref))

  ;; 上下文动作：embark + embark-consult
  (use-package embark
    :bind (("C-." . embark-act)))

  (use-package embark-consult
    :after (embark consult))

  ;; 行内补全：corfu + cape
  (use-package corfu
    :init (global-corfu-mode)
    :custom (corfu-auto t)
            (corfu-cycle t))

  (use-package cape
    :after corfu
    :init
    (add-to-list 'completion-at-point-functions #'cape-file)))

(provide 'self-completion)
;;; self-completion.el ends here
