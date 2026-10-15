;;; self-agenote.el --- Agenote 知识库适配层：经验卡采集与 C-c o k 命令 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 移植自桌面端配置的「知识库适配层 (agenote)」包声明（Org 与知识库域的包管理
;; 段，只取 :custom 配置、不取安装指令）与「Knowledge 系统」小节里属于经验卡
;; 采集的代码，以及 Capture 模板表中三张经验卡模板（原属 capture-templates
;; 小节，经验卡目标函数与类别预取一并跟来，因为它们直接依赖 agenote 的 CLI 与
;; entry-types 约定）。
;;
;; Profiles: full, ide
;; Requires: self-org（capture 模板装配点）、self-lib（路径常量）、
;;           self-keys（self/bind、self/declare-binding-group）
;; Packages: agenote
;;
;; 挂 full 档、不挂 portable：Android 上没有 agenote 这个 CLI，经验卡类别预取
;; 必然落回内置列表，18 个 C-c o k 命令也全部是 shell-out。按 AGENTS.md §2，
;; 档位差异只经 manifest 表达，模块内不做自我裁剪。
;;
;; 与本地 agenote 知识库命令行工具的集成
;; --------------------------------------
;; 目录对齐：agenote 的 org 根、经验卡目录、Inbox 三个常量直接指向本配置的
;; Org 路径（self:org-directory / self:org-knowledge-directory /
;; self:org-inbox-file），因此 Emacs 里 capture 出的经验卡与 CLI 侧
;; `agenote' 看到的是同一批文件。所有交互命令均自带 autoload，首个 C-c o k
;; 快捷键按下时自动触发延迟加载，`:custom' 配置经 eval-after-load 应用。
;;
;; 经验三卡与 agenote entry-types 的对齐
;; ------------------------------------
;; note / mistake / ascended 三个模板对齐 `agenote-base' 的 entry-types：
;; 属性 drawer 记录 `ENTRY_TYPE' 与 `CATEGORY'（note/mistake/ascended），
;; 模板体预置各卡的复盘章节骨架——**每章标题就是复盘时要回答的问题**，
;; 采集时留下空节头比事后回忆要填什么省事得多。三卡结构同源，公共表头
;; （标题 / PROPERTIES 里的 ID、CREATED、CATEGORY、TECH）已内联进各卡，
;; 原始设计里是抽成 `org-capture-tpl-experience-head' 再由各卡以列 0 引用
;; 拼入的 noweb 嵌套块，本文件已把嵌套展开全部就地为字面量。
;;
;; 类别候选的后台预取（为什么不是同步调 CLI）
;; ------------------------------------------
;; 经验卡的类别候选来自 `agenote fields --category'。这步 CLI 查询用
;; `make-process' 后台预取，经 `advice-add' 挂在 `org-capture' 入口之前
;; （org-capture 是 autoload 函数，advice 可直接挂载）：用户在模板选择菜单
;; 里挑条目的间隙 CLI 并行跑完并回填类别列表；等到经验卡目标函数真正弹出
;; 类别补全时候选已就绪，capture 流程不再被同步子进程阻塞。预取失败
;; （CLI 缺失或非零退出）一律静默——类别补全自动落回下方内置列表，行为与
;; 改造前的兜底一致。
;;
;; 临时状态的接力
;; --------------
;; 类别由目标函数 `self/org-capture--experience-file' 写入
;; `self/org-capture--last-category'，模板体展开时读走，本模块挂在
;; `org-capture-after-finalize-hook' 上的清理函数在 finalize 后清空。
;; 三个环节闭环，缺一则属性退化为默认值 `general'。改模板时勿删这个引用。
;;
;; 已知隐患（保留原样，未修）
;; ------------------------
;; · `advice-add 'org-capture :before` 每触发一次 capture 就 fork 一个
;;   agenote 子进程，即使选中的根本不是经验卡模板。
;; · `self/org-capture--experience-file' 用 `(concat "experiences/" cat)' 拼
;;   路径，而 `agenote-experiences-directory' 用 `self:org-knowledge-directory'；
;;   今天两者同值，常量一分家就写两个地方。

;;; Code:

;; ─── 路径与外部命令常量（由 self-lib 提供，此处只声明不定义）────────
;;
;; 带值声明会把 self-lib 的 defconst 顶掉（Emacs 的 defvar 遇到已绑定的
;; 变量就不改），所以一律只声明，用途写在行尾注释里。

(defvar self:org-directory)   ; Org 文件根目录
(defvar self:org-inbox-file)  ; 收件箱 inbox.org 绝对路径
(defvar self:org-knowledge-directory) ; 知识库经验卡目录（experiences/）
(defvar self:executable-agenote) ; 命令名；只存名字，由 exec-path 运行时解析

;; ─── 跨模块符号的就近声明 ──────────────────────────────────────────

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))
(declare-function self/org--ensure-directories "self-org"
                  "确保所有 Org 相关目录存在。")
(declare-function self/org--install-capture-templates "self-org"
                  "把本模块与 self-agenote 的模板装配进 `org-capture-templates'。")
;; 模板表在 self-org.el 里声明，本模块只往里赋值
(defvar self/agenote-capture-templates)

;; ─── 包配置（安装与版本 pin 是 profile manifest 的职责）─────────────

(use-package agenote
  :defer t
  :custom
  (agenote-org-directory self:org-directory)
  (agenote-experiences-directory self:org-knowledge-directory)
  (agenote-inbox-file self:org-inbox-file))

;; ─── Capture 临时状态与类别后台预取 ────────────────────────────────

(defvar self/org-capture--last-category nil
  "本次 capture 的经验卡 category，由目标文件函数写入、模板体读走。")
(defvar self/org-capture--experience-categories nil
  "后台预取的经验卡类别列表；nil 表示尚未就绪，类别补全退回内置列表。")

(defun self/org-capture--prefetch-experience-categories ()
  "后台异步拉取 `agenote fields --category'，回填 `self/org-capture--experience-categories'。
挂在 `org-capture' 入口之前：用户挑模板的间隙 CLI 并行跑，经验卡目标函数弹
类别补全时结果多半已就绪。失败静默退内置列表，不发消息。"
  (when-let* ((exe (executable-find self:executable-agenote)))
    (make-process
     :name "agenote-categories"
     :buffer (generate-new-buffer " *agenote-categories*")
     :command (list exe "--domain" "human" "fields" "--category")
     :sentinel (lambda (proc _event)
                 (when (memq (process-status proc) '(exit signal))
                   (let ((buf (process-buffer proc)))
                     (when (buffer-live-p buf)
                       (when (zerop (process-exit-status proc))
                         (with-current-buffer buf
                           (setq self/org-capture--experience-categories
                                 (split-string (buffer-string) "\n" t "[ \t]+"))))
                       (kill-buffer buf))))))))

(defun self/org-capture--experience-file ()
  "生成经验卡片目标文件路径（人类域，类别候选来自后台预取结果）。
交互选定的类别写入 `self/org-capture--last-category' 供模板体取值；
预取未就绪时用内置类别表兜底。"
  (self/org--ensure-directories)
  (let* ((choices (or self/org-capture--experience-categories
                      '("emacs" "guix" "general" "gamedev" "devops"
                        "research" "tooling")))
         (cat (completing-read "经验卡类别: " choices nil t))
         (dir (expand-file-name (concat "experiences/" cat)
                                self:org-directory)))
    (setq self/org-capture--last-category cat)
    (unless (file-directory-p dir)
      (make-directory dir t))
    (expand-file-name (format "%s.org" (format-time-string "%Y%m%d-%H%M%S"))
                      dir)))

(defun self/org-capture--clear-experience-state ()
  "`org-capture-after-finalize-hook' 回调：清理本次 capture 的经验卡临时状态。"
  (setq self/org-capture--last-category nil))

(add-hook 'org-capture-after-finalize-hook
          #'self/org-capture--clear-experience-state)

;; 挂在 org-capture 入口上：这里才是模板展开前最后一个可拦截点，而预取要
;; 抢的是「用户挑模板的那几秒」——CLI 异步跑完，回填类别变量时多半已就绪。
;; `:before' 而非 `:after'：晚一步，模板已经拿着空表求值完了。
;; 代价是这个 advice 挂在交互命令上，直接调 `org-capture-...-internals'
;; 绕过命令时会拿不到预取结果——那条路上类别补全退回内置列表。
(advice-add 'org-capture :before
            #'self/org-capture--prefetch-experience-categories)

;; ─── 三张经验卡模板 ────────────────────────────────────────────────
;; 模板体已把桌面端配置的 noweb 引用就地展开（嵌套）：
;;   org-capture-tpl-experience-head → 三张卡的公共表头，展开进每张卡；
;;   org-capture-tpl-note / mistake / ascended → 下面三处模板体。
;; 展开后模板体一律顶格：原引用行顶格，noweb 把空的行首前缀复制到每一行。
;; **不要给模板体加缩进**——首行缩进会让 `*` 标题失效，`#+filetags` 也会被
;; Org 当成普通文本。含双引号的 elisp 表达式写成 \" 是必需的：模板值是
;; 单引号列表，读入器会把 \" 解析成 "，org-capture 求值时才看到正确引号。

;; kn：note 条目——已经验证过的日常工作流。
(defconst self:org-capture-tpl-note
  '("kn" "经验-笔记 (note)" plain
    (file self/org-capture--experience-file)
    "
* %^{标题}
:PROPERTIES:
:ID:         %(format-time-string \"%Y%m%d-%H%M%S\")
:CREATED:    %(format-time-string \"[%Y-%m-%d %a]\")
:CATEGORY:   %(or self/org-capture--last-category \"general\")
:TECH:       %^{技术栈}
:TYPE:       workflow
:STATUS:     done
:ENTRY_TYPE: note
:END:
#+filetags: :%^{标签}:

** 事项内容
%?
** 为什么值得长期保留

** 适用场景与例外

** 后续行动
")
  "note 条目：工作流经验。")

;; km：mistake 条目——排错复盘，记录踩坑根因与防范措施。
(defconst self:org-capture-tpl-mistake
  '("km" "经验-踩坑 (mistake)" plain
    (file self/org-capture--experience-file)
    "
* %^{标题}
:PROPERTIES:
:ID:         %(format-time-string \"%Y%m%d-%H%M%S\")
:CREATED:    %(format-time-string \"[%Y-%m-%d %a]\")
:CATEGORY:   %(or self/org-capture--last-category \"general\")
:TECH:       %^{技术栈}
:TYPE:     debug
:STATUS:   done
:ENTRY_TYPE: mistake
:END:
#+filetags: :%^{标签}:

** 原始问题
%?
** 纠错反馈

** 这次到底错在哪里

** 最终正确处理
")
  "mistake 条目：踩坑记录。")

;; ka：ascended 条目——经历多轮尝试后得出的最强解决方案。
(defconst self:org-capture-tpl-ascended
  '("ka" "经验-试错后最优 (ascended)" plain
    (file self/org-capture--experience-file)
    "
* %^{标题}
:PROPERTIES:
:ID:         %(format-time-string \"%Y%m%d-%H%M%S\")
:CREATED:    %(format-time-string \"[%Y-%m-%d %a]\")
:CATEGORY:   %(or self/org-capture--last-category \"general\")
:TECH:       %^{技术栈}
:TYPE:     debug
:STATUS:   done
:ENTRY_TYPE: ascended
:END:
#+filetags: :%^{标签}:

** 前几轮失败的根因
%?
** 检索过的知识源

** 核对过的真实文件或输出

** 最终采用的最强方案
")
  "ascended 条目：多轮试错后的最优解。")

;; 用顺序赋值而不是 dolist + push：push 会把三张卡反序（ascended/mistake/note），
;; 而 org-capture 的选择菜单按表序显示、用字母键选，顺序必须与桌面端一致
;; （kn 笔记 → km 踩坑 → ka 最优解）。
(setq self/agenote-capture-templates
      (list self:org-capture-tpl-note
            self:org-capture-tpl-mistake
            self:org-capture-tpl-ascended))

;; 本模块在 self-org 之后加载，而 self-org 的装配函数在 org-capture 加载时
;; 才跑——正常流程下届时三张卡早已就位。这里主动再调一次是为了不把正确性
;; 押在 org-capture 何时被 autoload 上：装配函数是整表赋值，重复调用幂等，
;; 顺序与条目数都不受影响。
(self/org--install-capture-templates)

;; ─── 键位（C-c o k 知识库前缀） ────────────────────────────────────

(self/declare-binding-group "C-c o k" "知识库 / agenote")
(self/bind "C-c o k c" #'agenote-knowledge-capture "捕获经验卡" "Org 与知识库")
(self/bind "C-c o k s" #'agenote-knowledge-search "搜索经验" "Org 与知识库")
(self/bind "C-c o k t" #'agenote-knowledge-search-by-tag "按标签搜索" "Org 与知识库")
(self/bind "C-c o k I" #'agenote-knowledge-open-inbox "打开 Inbox" "Org 与知识库")
(self/bind "C-c o k S" #'agenote-knowledge-stats "知识库统计" "Org 与知识库")
(self/bind "C-c o k v" #'agenote-knowledge-browse-human "浏览人类知识库" "Org 与知识库")
(self/bind "C-c o k b" #'agenote-knowledge-browse-agenote "浏览 agenote 域" "Org 与知识库")
(self/bind "C-c o k a" #'agenote-knowledge-archive-inbox-entry "归档 Inbox 条目" "Org 与知识库")
(self/bind "C-c o k d" #'agenote-knowledge-deduplicate "检测重复卡" "Org 与知识库")
(self/bind "C-c o k e" #'agenote-knowledge-merge "合并卡片" "Org 与知识库")
(self/bind "C-c o k l" #'agenote-knowledge-lint "校验知识库" "Org 与知识库")
(self/bind "C-c o k m" #'agenote-knowledge-memory "记忆系统" "Org 与知识库")
(self/bind "C-c o k n" #'agenote-knowledge-connect "链接卡片" "Org 与知识库")
(self/bind "C-c o k o" #'agenote-knowledge-commit "提交知识库" "Org 与知识库")
(self/bind "C-c o k r" #'agenote-knowledge-review "审查卡片" "Org 与知识库")
(self/bind "C-c o k u" #'agenote-knowledge-touch "更新卡片时间" "Org 与知识库")
(self/bind "C-c o k V" #'agenote-knowledge-viz-open-browser "浏览器可视化" "Org 与知识库")

(provide 'self-agenote)
;;; self-agenote.el ends here
