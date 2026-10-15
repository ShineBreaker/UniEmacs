;;; self-keys.el --- 键位机制层：self/bind 声明器、Which-key/Winner 与顶层前缀 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: minimal, portable, full
;; Requires: 无（机制层是键位体系的底座，被所有用 self/bind 的模块依赖）
;; Packages: which-key, winner
;;
;; 移植自桌面端配置的「键位声明」域的机制部分。本文件只提供**机制**与
;; **顶层分类导航**，具体功能的键位清单在各自的模块里（full 档的跨域
;; 公共键清单见 self-keys-desktop）。
;;
;; ─── 为什么统一走 self/bind 而不是 keymap-global-set ──────────────────
;;
;; `self/bind' 把三件事合成一次声明，因此配置各模块时优先用它：
;;
;;   1. 一处绑定，多处生效：绑定的同时自动为 Which-key 注册中文提示，
;;      并把条目写进 `self:binding-spec'，快捷键帮助手册由该表派生。
;;   2. 防重复声明：同一个按键被不小心重复绑定时立即报错中断，避免
;;      后写的绑定静默覆盖先写的绑定。
;;   3. 调用格式固定：(self/bind "快捷键" #'命令 "中文说明" "分组名称")。
;;
;; 查键与改键：
;;
;;   · 查某个键现在做什么：C-h k 再按那个键（describe-key）。
;;   · 查声明格式与键位总表：C-h f self/bind / C-h v self:binding-spec。
;;   · 改键：在对应模块找到 (self/bind "..." ...) 行改键串或命令；键串语法
;;     见 C-h f key-valid-p，功能键须写成 <f12> 而非 "F12"。
;;   · 只分组不绑键：self/declare-binding-group 是 self/bind 的特例
;;     （:prefix t），只注册 Which-key 分组名、不绑定命令。
;;
;; ─── 键位内聚原则 ────────────────────────────────────────────────────
;;
;; 专属于某一模块的快捷键（Git 走 C-c g、Org 走 C-c o）随其模块就近绑定，
;; 由各自模块调用本文件提供的 self/bind。所以查找某个具体功能的键位，
;; 第一步去那个功能的域，最后才来这里。
;;
;; 前缀声明的遍历形状是本仓库处理「同构重复」的标准答案：14 个前缀写成一张
;; (键 . 中文名) 的 alist，再用 dolist 逐条展开——数据与执行分离，增删前缀
;; 只改那张表，不写宏、不动态拼符号名。
;;
;; ─── Which-key 与 Winner 为什么能进三档 ──────────────────────────────
;;
;; 二者都不是第三方包：which-key 自 Emacs 30 起进入 lisp/ 内建库，winner
;; 更早。minimal 档「不得声明任何第三方包」的约束因此不受影响——这里只
;; 声明不安装（安装是 profile 清单的职责，AGENTS.md §3 包管理纪律），
;; 依赖的是「minimal 只面向 Emacs 31+ 平台」这一前提（见 self-lib.el 的
;; 版本与平台说明）。哪天真要在 Emacs 29 上跑 minimal，which-key 的
;; use-package 会因找不到库而报一次警告，不影响其余功能。
;;
;; Which-key：按下前缀键后停顿 0.3 秒，自动在屏幕下方弹出三列等宽排版的
;; 中文候选提示。Winner Mode：窗口布局历史记录（撤销/重做由 full 档的
;; self-keys-desktop 绑到 C-c w u / C-c w r），撤销不小心打乱的分屏。
;;
;; ─── 与其它模块的接口约定 ────────────────────────────────────────────
;;
;; · Which-key 的延迟注册缓冲 `self--pending-wk-descs' 与冲刷入口：
;;   缓冲在本文件唯一实现，冲刷（`self/which-key-apply-descriptions'）在
;;   self-help-zh——模块加载顺序早于包加载是常态，故 self/bind 不能假定
;;   which-key 已就绪，只能先暂存。
;; · `self/binding-help-sections' 的返回值形状已冻结，供 self-help-zh 的
;;   <f1> ? 速查表消费。
;; · 键位目标命令一律跨模块显式 declare-function，不做 boundp 防御访问。

;;; Code:

;; ─── Which-key 与 Winner 的第三方符号声明 ────────────────────────────
;; 二者随 Emacs 内建，但编译本文件时 which-key.el / winner.el 未必已加载，
;; 故把用到的变量与函数就近声明（不带值）。

(defvar which-key-mode)
(defvar which-key-idle-delay)
(defvar which-key-prefix-prefix)
(defvar which-key-allow-multiple-replacements)
(defvar which-key-max-display-columns)
(defvar which-key-min-display-lines)
(defvar which-key-side-window-max-height)
(defvar which-key-sort-order)
(defvar which-key-C-h-map-prompt)
(declare-function which-key-add-key-based-replacements "which-key"
                  "为全局 KEY 注册 DESCRIPTION。")
(declare-function which-key-prefix-then-key-order "which-key"
                  "Which-key 候选排序：先前缀、后按键本身。")

(defvar winner-mode)
(defvar winner-dont-bind-my-keys)
(defvar winner-boring-buffers)

;; ═══ 一、机制部分 ═════════════════════════════════════════════════════

(defvar self:binding-spec nil
  "本地声明式键位表。
每条是一个 plist：:key 键串、:command 目标命令（:prefix 声明时为 nil）、
:description 中文说明、:group 分组名（:prefix 声明为 nil），其余属性由
`self/bind' 的 &rest PROPERTIES 原样附加。所有模块的键位声明都汇总到此处，
既是 Which-key 的数据源，也是快捷键帮助页的唯一事实源。")

(defvar self--pending-wk-descs nil
  "Which-key 加载前暂存的全局键位描述。
每条是 (键串 . 说明)。`self/bind' 发现 which-key 尚未加载时 push 到此处，
由 self-help-zh 在 which-key 就绪后冲刷并清空。")

(defun self/binding--record (entry)
  "把 ENTRY 追加到 `self:binding-spec'，并拒绝重复的 key/mode 组合。
重复声明立即报错中断，是防按键冲突的第一道闸；mode 缺省按 `global' 计。"
  (let ((key (plist-get entry :key))
        (mode (or (plist-get entry :mode) 'global)))
    (when (seq-find
           (lambda (existing)
             (and (equal key (plist-get existing :key))
                  (eq mode (or (plist-get existing :mode) 'global))))
           self:binding-spec)
      (error "重复键位声明: %s (%s)" key mode))
    (setq self:binding-spec
          (append self:binding-spec (list entry)))))

(defun self/binding--register-which-key (key description)
  "为 KEY 注册中文 DESCRIPTION。
Which-key 尚未加载时把 (KEY . DESCRIPTION) 暂存进 `self--pending-wk-descs'，
加载完成后由 self-help-zh 统一冲刷——声明顺序早于包加载顺序是常态，
故这里不能假定 which-key 可用。"
  (if (featurep 'which-key)
      (which-key-add-key-based-replacements key description)
    (push (cons key description) self--pending-wk-descs)))

(defun self/bind (key target description group &rest properties)
  "声明并全局绑定 KEY 到 TARGET。
KEY 是键串（如 \"C-c w t\"，功能键写 <f12>），TARGET 是命令符号。
DESCRIPTION 与 GROUP 是中文说明与帮助分组名，同时供 Which-key 与帮助页使用。
PROPERTIES 是附加属性（:prefix t 表示只声明分组不绑定；:mode 标记局部键）。
返回本条声明写入 `self:binding-spec' 的 plist。"
  (let ((entry (append (list :key key
                             :command target
                             :description description
                             :group group)
                       properties)))
    (self/binding--record entry)
    (unless (plist-get entry :prefix)
      (keymap-global-set key target))
    (self/binding--register-which-key key description)
    entry))

(defun self/declare-binding-group (key description)
  "声明 Which-key 展示的中间分组 KEY，只注册分组名不绑定命令。
等价于 (self/bind KEY nil DESCRIPTION nil :prefix t)。"
  (self/bind key nil description nil :prefix t))

(defun self/binding-help-sections ()
  "从 `self:binding-spec' 生成帮助分组。
返回 ((GROUP . ((KEY . DESCRIPTION) ...)) ...)：分组按首次出现顺序，
组内条目按声明顺序；前缀声明条目（:group 为 nil）不进分组。
实现是一遍扫描按分组归并：已见过的分组用 `assoc' 找到后把新条目追加到组尾，
新分组先 push（倒序）最后 `nreverse' 恢复首次出现顺序——与
`self/language--derive-eglot-programs' 同为「归并 + nreverse」形状。
（返回形状已冻结：self-help-zh 的 <f1> ? 速查表按 (GROUP . 行列表) 消费。）"
  (let (groups)
    (dolist (entry self:binding-spec)
      (let ((group (plist-get entry :group))
            (line (cons (plist-get entry :key)
                        (plist-get entry :description))))
        (when group
          (let ((existing (assoc group groups)))
            (if existing
                (setcdr existing (append (cdr existing) (list line)))
              (push (list group line) groups))))))
    (nreverse groups)))

;; ═══ 二、Which-key 与 Winner ═════════════════════════════════════════

(use-package which-key
  :demand t
  :config
  (which-key-mode 1)
  (setq which-key-idle-delay 0.3
        which-key-prefix-prefix ""
        which-key-allow-multiple-replacements t
        which-key-max-display-columns 3
        which-key-min-display-lines 10
        which-key-side-window-max-height 0.38
        which-key-sort-order #'which-key-prefix-then-key-order
        which-key-C-h-map-prompt
        " \\<which-key-C-h-map>\\[which-key-show-next-page-cycle]/\\[which-key-show-previous-page-cycle] 翻页,\\[which-key-show-standard-help] 帮助,\\[which-key-abort] 退出"))

(use-package winner
  :custom
  (winner-dont-bind-my-keys t)
  :config
  (setq winner-boring-buffers
        (append winner-boring-buffers
                '("*Completions*" "*Help*" "*Apropos*" "*which-key*")))
  (winner-mode 1))

;; ═══ 三、14 个顶层前缀 ═══════════════════════════════════════════════
;;
;; 顶层分类导航：文件/窗口/标签（C-x）、项目（C-x p）、搜索（M-s）、
;; 跳转（M-g）、代码（C-c c）、Git（C-c g）、生活应用（C-c a）、
;; 编辑变换（C-c e）、Org 与知识库（C-c o）、帮助（C-c h）、
;; 窗口面板（C-c w）、开关（C-c t）、退出与 Frame（C-c q）。
;; 只声明分组名，具体子键由各功能模块在自己的 prefix 下声明。

(dolist (prefix
         '(("C-x" . "文件/缓冲区/窗口/标签")
           ("C-x t" . "标签")
           ("C-x p" . "项目")
           ("M-s" . "搜索")
           ("M-g" . "跳转 / 错误")
           ("C-c c" . "代码")
           ("C-c g" . "Git")
           ("C-c a" . "生活应用")
           ("C-c e" . "编辑变换")
           ("C-c o" . "Org 与知识库")
           ("C-c h" . "帮助")
           ("C-c w" . "窗口与面板")
           ("C-c t" . "开关")
           ("C-c q" . "退出与 Frame")))
  (self/declare-binding-group (car prefix) (cdr prefix)))

(provide 'self-keys)

;;; self-keys.el ends here
