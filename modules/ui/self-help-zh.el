;;; self-help-zh.el --- 快捷键帮助、右键菜单与 Which-key 的中文化 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, portable
;; Requires: self-keys（`self/binding-help-sections'、`self--pending-wk-descs'）、self-completion（`self/isearch-forward-dwim'）
;;   本模块同时是 which-key 的视觉层归属地：弹窗分页按钮、触屏 tap 分发器、
;;   触屏专属的 which-key 取值覆盖都在这里（AGENTS.md §2：Which-key 的
;;   「中文描述 + 弹窗呈现」是一个内聚单元，与 data/ 的加载方同属一处）。
;; Packages: which-key, geiser, arei, magit, winner
;;
;; 移植自桌面端配置「界面与外观」域的四个小节：Which-key 中文描述数据、
;; 右键菜单本地化、右键菜单功能扩展、快捷键帮助，以及「右键菜单与 Which-key
;; 中文化」一节。核心思路只有一条：中文化不走上游——不改写 which-key 或各
;; 插件包内部的菜单/提示生成逻辑，而是在数据文件里维护映射，再递归遍历
;; keymap 结构把显示标签替换掉。要补翻译只动 data/*.el，零逻辑改动。
;;
;; · 数据与逻辑分离（`self:i18n-data-files'）
;;   三份纯数据放在仓库的 data/ 下，按加载顺序依次 load：which-key-zh.el
;;   （全局键、各 major-mode、minor-mode keymap 的描述与正则替换规则）、
;;   context-menu-zh.el（右键菜单与顶部菜单栏的中英映射）、help-zh.el
;;   （帮助页导读文案）。数据文件只含字面量 setq，改动非常安全；缺文件直接
;;   error，避免半中文半英文还查不出原因。
;;
;; · 右键菜单本地化（`self/context-menu--translate-keymap' 一族）
;;   Emacs Lisp 里扩展菜单项是 =(menu-item LABEL BINDING . PROPS)= 结构，
;;   子菜单是 =(cons "标题" 子keymap)= 形式。翻译函数递归遍历、只替换显示
;;   标签，未在映射表收录的项原样保留英文。间接 keymap：keymapp 对符号型
;;   间接 keymap 同样返回 t，遍历前先 consp 校验即可安全处理。挂载点有三处：
;;   `context-menu-map' 的 :filter-return advice（菜单弹出前翻译）、启动时把
;;   `global-map' 的 [menu-bar] 键表原地翻一次，再对 `menu-bar-keymap' 挂
;;   advice 兜住 ispell/Geiser 等懒加载包生成的条目，以及 GUI 下
;;   `activate-menubar-hook' 上的重翻——GUI 菜单栏点击由底层 C 代码直接读
;;   keymap，hook 是唯一能兜住启动后新加载 minor mode（envrc、so-long）
;;   的时机。Magit 缓冲区内的右键菜单走 magit-menu-format-desc 的
;;   :filter-return advice。
;;
;; · 右键菜单功能扩展（`self/context-menu-append'）
;;   菜单栏与工具栏全关、各窗口 mode-line 清空之后，缓冲区内的右键菜单是仅存
;;   的鼠标功能发现入口。除内建默认项外，经 `context-menu-functions' hook 在
;;   菜单末尾追加「查找与替换」与「窗口」两个子菜单；新增条目直接写中文标签，
;;   翻译机制对未收录标签原样保留，不必进 context-menu-zh.el。查找与替换的键
;;   提示与查替直达键一一对应（:keys 属性让菜单右侧显示键位，菜单既是操作
;;   入口也是快捷键的发现入口）；窗口子菜单是终端的最小替代通道——终端的鼠标
;;   协议按字符单元上报事件、分隔线宽为 0，拖拽无处落脚，故提供步进调窗命令。
;;
;; · 快捷键帮助（`self/show-help'）
;;   `<f1> ?' 呼出速查表：正文分组来自 `self/binding-help-sections'（由
;;   self/bind 收集的 `self:binding-spec' 派生），Magit 状态页速查卡是静态
;;   数据——状态页内的单键（s 暂存、c 提交、P 推送等）不经过 self/bind 声明。
;;   想核对某个键的实时行为，在状态页按 C-h k 再按那个键。帮助窗口内按 q
;;   退出（special-mode 绑定）。
;;
;; · Which-key 注册（`self/which-key-apply-descriptions'）
;;   按 which-key 加载后、显示前注册中文描述：先冲刷 self-keys 暂存的延迟
;;   描述，再集中注册全局 / major-mode 描述。Geiser、Arei 这类把 C-c 子树
;;   挂到 minor-mode keymap 上的包，以及 preloaded 的 isearch，在包本体与
;;   which-key 均就绪后按 keymap 精准注册。
;;
;; · Which-key 视觉层（`self/which-key-*' 一族，含触屏分页）
;;   which-key 本体与其中文描述的注册机制在 self-keys；本模块负责它在屏幕上
;;   怎么呈现：触屏没有 C-h，故自绘一页「[ 上一页 ] [ 下一页 ]」胶囊按钮，
;;   并把 tap 事件按前缀+mouse 的组合序列分发过去。桌面端用 C-h 翻页，
;;   不依赖这层，但它无平台副作用，故按档位（portable / full）而非平台归属。

;;; Code:

(declare-function self/binding-help-sections "self-keys"
                  "从 `self:binding-spec' 生成帮助分组。")
(declare-function self/isearch-forward-dwim "self-completion"
                  "启动增量搜索，有活跃选区时把选区文本填入搜索串。")
(declare-function which-key-add-key-based-replacements "which-key"
                  "为 KEY 注册中文描述。")
(declare-function which-key-add-major-mode-key-based-replacements "which-key"
                  "为 MODE 下的 KEY 注册中文描述。")
(declare-function which-key-add-keymap-based-replacements "which-key"
                  "按 keymap 内的键注册中文描述。")

;; ─── 本地化纯数据（data/*.el） ────────────────────────────────────────

;; 本地化数据目录归 core/self-lib.el 定义（路径常量的唯一真相源），
;; 这里只声明不赋值。
(defvar self:i18n-data-directory)

(defconst self:i18n-data-files
  '("which-key-zh.el" "context-menu-zh.el" "help-zh.el")
  "按加载顺序列出的本地化数据文件。")

;; 三份数据文件只用字面量 setq 赋值，就近 defvar 既声明契约又消除
;; byte-compile 的自由变量告警。
(defvar self:which-key-description-spec nil
  "which-key 全局键中文描述：(完整键序列 . 说明) 列表。")
(defvar self:which-key-major-mode-description-spec nil
  "which-key major-mode 键中文描述：(键 MODE . 说明) 列表。")
(defvar self:which-key-keymap-description-spec nil
  "which-key keymap 描述：(MAPVAR (键 . 说明) ...) 列表。
按 keymap 变量注册，供把 C-c 子树挂到 minor-mode keymap 的包使用。")
(defvar self:which-key-regexp-replacements nil
  "which-key 正则替换规则，追加进 `which-key-replacement-alist'。")
(defvar self:context-menu-label-translations nil
  "右键菜单标签中英映射：(英文标签 . 中文) 列表，取用走 `assoc' 首命中。")
(defvar self:help-introduction nil
  "快捷键帮助页开头的导读段落（字符串列表）。")
(defvar self:help-magit-notes nil
  "Magit 状态页速查卡的条目模型说明行（字符串列表）。")
(defvar self:help-magit-keys nil
  "Magit 状态页速查卡键位行（(键 . 中文说明) 列表）。")

(dolist (name self:i18n-data-files)
  (let ((file (expand-file-name name self:i18n-data-directory)))
    (unless (file-readable-p file)
      (error "本地化数据文件不可读: %s" file))
    (load file nil 'nomessage)))

;; ─── 右键菜单本地化 ───────────────────────────────────────────────────

(defun self/context-menu--translate-string (string)
  "翻译 STRING；未登记时返回原字符串。
译文沿用 STRING 的文本属性（face 等），避免译文掉色。"
  (if-let* ((translation
             (cdr (assoc (substring-no-properties string)
                         self:context-menu-label-translations))))
      (apply #'propertize translation (text-properties-at 0 string))
    string))

(defun self/context-menu--translate-object (object)
  "递归翻译 OBJECT 中的字符串。"
  (cond
   ((stringp object)
    (self/context-menu--translate-string object))
   ((consp object)
    (mapcar #'self/context-menu--translate-object object))
   (t object)))

(defun self/context-menu--translate-menu-item (item)
  "翻译菜单项 ITEM 的标题和子菜单。
ITEM 形如 =(menu-item LABEL BINDING . PROPS)=：就地改写 LABEL 所占的那个
cons 格，BINDING 若是子 keymap 则递归下去，PROPS 里只有 :help 的值需要
翻译（:keys 等键提示已是本配置自己写的中文/键序列）。"
  (when (and (consp item) (eq (car item) 'menu-item))
    (let ((label-cell (cdr item))
          (binding (nth 2 item))
          (properties (nthcdr 3 item)))
      (when label-cell
        (setcar label-cell
                (self/context-menu--translate-object (car label-cell))))
      (when (keymapp binding)
        (self/context-menu--translate-keymap binding))
      (while (consp properties)
        (when (and (eq (car properties) :help)
                   (consp (cdr properties)))
          (setcar (cdr properties)
                  (self/context-menu--translate-object (cadr properties))))
        (setq properties (cddr properties))))))

(defun self/context-menu--translate-binding (_event binding)
  "翻译 keymap 中的一个条目 BINDING（EVENT 是 `map-keymap' 回调位，未使用）。"
  (cond
   ((and (consp binding) (eq (car binding) 'menu-item))
    (self/context-menu--translate-menu-item binding))
   ((and (consp binding) (stringp (car binding))
         (keymapp (cdr binding)))
    (setcar binding
            (self/context-menu--translate-string (car binding)))
    (self/context-menu--translate-keymap (cdr binding)))
   ((keymapp binding)
    (self/context-menu--translate-keymap binding))))

(defun self/context-menu--translate-keymap (keymap)
  "递归翻译 KEYMAP 内的菜单标题。"
  (when (keymapp keymap)
    ;; keymap 的提示字符串挂在第二个 cons 格（`(t PROMPT . BINDINGS)' 形状），
    ;; 顶层菜单的 "File"/"Edit" 等就靠这一格翻译。
    (when (and (consp keymap)
               (stringp (cadr keymap)))
      (setcar (cdr keymap)
              (self/context-menu--translate-string (cadr keymap))))
    (map-keymap #'self/context-menu--translate-binding keymap))
  keymap)

;; advice-add 对同一 advice 函数重复添加不会叠加执行，无需 member-p 前置。
(advice-add 'context-menu-map :filter-return
            #'self/context-menu--translate-keymap)

(self/context-menu--translate-keymap
 (lookup-key global-map [menu-bar]))

(advice-add 'menu-bar-keymap :filter-return
            #'self/context-menu--translate-keymap)

(defun self/context-menu--translate-menubar-on-activate ()
  "菜单栏展开前重翻 `global-map' 的 [menu-bar] 子树，兜住懒加载条目。"
  (self/context-menu--translate-keymap
   (lookup-key global-map [menu-bar])))

(add-hook 'activate-menubar-hook
          #'self/context-menu--translate-menubar-on-activate)

(with-eval-after-load 'magit-section
  (advice-add 'magit-menu-format-desc :filter-return
              #'self/context-menu--translate-string))

;; ─── 右键菜单功能扩展 ─────────────────────────────────────────────────

(defun self/context-menu--search-menu ()
  "构造「查找与替换」子菜单，条目与查替直达键一一对应。"
  (let ((map (make-sparse-keymap "查找与替换")))
    (define-key map [search]
                '(menu-item "查找…" self/isearch-forward-dwim
                            :help "增量搜索当前文件，选中即搜索词" :keys "C-S-f"))
    (define-key map [replace]
                '(menu-item "替换 (diff 预览)…" replace-regexp-as-diff
                            :help "正则替换，改动手法以 diff 预览确认" :keys "C-S-h"))
    (define-key map [project-search]
                '(menu-item "项目搜索…" project-find-regexp
                            :help "在当前项目所有文件中搜索正则" :keys "C-x p s"))
    (define-key map [project-replace]
                '(menu-item "项目替换…" project-query-replace-regexp
                            :help "在当前项目范围内逐个确认替换" :keys "M-s R"))
    map))

(defun self/window-wider ()
  "加宽当前窗口 5 列，并排邻居让位。"
  (interactive)
  (enlarge-window-horizontally 5))

(defun self/window-narrower ()
  "收窄当前窗口 5 列，并排邻居变宽。"
  (interactive)
  (shrink-window-horizontally 5))

(defun self/window-taller ()
  "增加当前窗口高度 3 行，上下邻居让位。"
  (interactive)
  (enlarge-window 3))

(defun self/window-shorter ()
  "减少当前窗口高度 3 行，上下邻居变高。"
  (interactive)
  (shrink-window 3))

(defun self/context-menu--window-menu ()
  "构造「窗口」子菜单；终端拖不了分隔线，这里是步进调窗的替代通道。
步进命令直接包装内建调窗原语：菜单点击传不了前缀参数，而这些命令的交互
默认步长只有 1 列 / 1 行，鼠标用户连点太碎。"
  (let ((map (make-sparse-keymap "窗口")))
    (define-key map [wider]
                '(menu-item "加宽 5 列" self/window-wider
                            :help "加宽当前窗口，并排邻居让位"))
    (define-key map [narrower]
                '(menu-item "收窄 5 列" self/window-narrower
                            :help "收窄当前窗口，并排邻居变宽"))
    (define-key map [taller]
                '(menu-item "增高 3 行" self/window-taller
                            :help "增加当前窗口高度，上下邻居让位"))
    (define-key map [shorter]
                '(menu-item "减矮 3 行" self/window-shorter
                            :help "减少当前窗口高度，上下邻居变高"))
    (define-key map [balance]
                '(menu-item "均衡窗口大小" balance-windows
                            :help "同 Frame 内所有窗口恢复等分"))
    (define-key map [maximize]
                '(menu-item "最大化此窗口" maximize-window
                            :help "临时扩满当前窗口；用均衡或撤销窗口变更还原"))
    (define-key map [delete]
                '(menu-item "关闭此窗口" delete-window
                            :help "关闭当前窗口，缓冲区保留"))
    (define-key map [delete-others]
                '(menu-item "只保留此窗口" delete-other-windows
                            :help "关闭同 Frame 内其他所有窗口"))
    (define-key map [winner-undo]
                '(menu-item "撤销窗口变更" winner-undo
                            :help "恢复上一次窗口布局" :keys "C-c w u"))
    map))

(defun self/context-menu-append (menu _click)
  "在右键菜单 MENU 末尾追加「查找与替换」与「窗口」两个子菜单。"
  (define-key-after menu [separator-custom] menu-bar-separator)
  (define-key-after menu [search-replace]
    (list 'menu-item "查找与替换" (self/context-menu--search-menu)))
  (define-key-after menu [window]
    (list 'menu-item "窗口" (self/context-menu--window-menu)))
  menu)

(add-hook 'context-menu-functions #'self/context-menu-append t)

;; ─── 快捷键帮助 ───────────────────────────────────────────────────────

(defun self/show-help ()
  "显示完整的快捷键帮助（交互命令：`M-x self/show-help'，键位 `C-c h ?'）。"
  (let ((buf (get-buffer-create "*Shortcuts Help*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (insert "\n")
        (insert (propertize "快捷键参考\n\n"
                            'face '(:height 1.5 :weight bold)))
        (dolist (paragraph self:help-introduction)
          (insert paragraph "\n"))
        (insert "\n")
        ;; 分组与条目全部由 `self/binding-help-sections' 从键位声明表派生，
        ;; 因此新增 `self/bind' 声明即自动进本页，无需改本函数。
        (dolist (section (self/binding-help-sections))
          (insert (propertize (format "═══ %s ═══" (car section))
                              'face '(:inherit font-lock-keyword-face :weight bold :height 1.2)))
          (insert "\n\n")
          (dolist (binding (cdr section))
            (insert (format "  %-24s %s\n"
                            (propertize (car binding)
                                        'face 'font-lock-keyword-face)
                            (cdr binding))))
          (insert "\n"))
        (when self:help-magit-keys
          (insert (propertize "═══ Magit 状态页速查 ═══"
                              'face '(:inherit font-lock-keyword-face :weight bold :height 1.2)))
          (insert "\n\n")
          (dolist (note self:help-magit-notes)
            (insert (format "  %s\n" note)))
          (insert "\n")
          (dolist (binding self:help-magit-keys)
            (insert (format "  %-24s %s\n"
                            (propertize (car binding)
                                        'face 'font-lock-keyword-face)
                            (cdr binding))))
          (insert "\n"))
        (insert (propertize "提示:" 'face '(:weight bold)))
        (insert " 按 ")
        (insert (propertize "q" 'face 'font-lock-keyword-face))
        (insert " 关闭此帮助窗口\n"))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(defun self/open-config-source ()
  "打开本配置的架构设计文档（IDE「设置」的等价入口）。
交互命令：`M-x self/open-config-source'，键位 `C-c h c' 与 `C-,'。

移植改动：桌面配置在这里打开它的 literate 真理源；本仓库没有单一真理源
文件（配置是 modules/ 下的多个模块 + AGENTS.md 规范），故改指向
docs/architecture.md——它是「想知道某个模块为什么这么切」的入口。"
  (interactive)
  (find-file (expand-file-name "docs/architecture.md" user-emacs-directory)))

;; ─── Which-key 中文化 ─────────────────────────────────────────────────

;; which-key 是延迟加载的包，本模块加载时它还没进来。包变量的 defvar 只
;; 声明不赋值：带上 nil 值同样会把包自己的默认值挡在门外（Emacs 的
;; defvar 遇到已绑定的变量就不改），所以这里只留声明 + 行尾注释。
(defvar which-key-replacement-alist) ; 键描述替换规则，本模块往里追加条目

;; 缓冲的唯一实现归 self-keys（本模块只 push/cons 它，which-key 就绪后
;; 冲刷并清空）。这里只声明不赋值：带值声明会把 self-keys 里的 defvar
;; 顶成 nil（Emacs 的 defvar 遇到已绑定变量就不改），反而清掉已暂存内容。
(defvar self--pending-wk-descs)

(defun self/which-key--apply-keymap-spec (mapvar)
  "把 `self:which-key-keymap-description-spec' 中 MAPVAR 的描述注册到 which-key。
调用点须保证 MAPVAR 与 which-key 均已加载；同一 map 只会注册一次。"
  (dolist (entry (alist-get mapvar self:which-key-keymap-description-spec))
    (which-key-add-keymap-based-replacements
      (symbol-value mapvar) (car entry) (cdr entry))))

(defun self/which-key-apply-descriptions ()
  "将中文描述注册到 which-key（仅在 which-key 加载后调用一次）。
注册顺序：正则替换规则 → 全局键 → major-mode 键。which-key 的替换链以先
注册的条目为最终展示，故顺序即优先级。"
  (setq which-key-replacement-alist
        (append which-key-replacement-alist
                self:which-key-regexp-replacements))
  (dolist (entry self:which-key-description-spec)
    (which-key-add-key-based-replacements (car entry) (cdr entry)))
  (dolist (entry self:which-key-major-mode-description-spec)
    (which-key-add-major-mode-key-based-replacements
      (car entry) (cadr entry) (cddr entry))))

(with-eval-after-load 'which-key
  ;; 先冲刷 self-keys 在 which-key 未加载时暂存的描述，再注册集中维护的表。
  (dolist (entry (nreverse self--pending-wk-descs))
    (which-key-add-key-based-replacements (car entry) (cdr entry)))
  (setq self--pending-wk-descs nil)
  (self/which-key-apply-descriptions))

;; isearch 是 preloaded 特性，会话内按 M-s 等前缀停顿时 which-key 弹窗合并
;; 展示 isearch 键表，故同样按 keymap 注册。
(with-eval-after-load 'isearch
  (with-eval-after-load 'which-key
    (self/which-key--apply-keymap-spec 'isearch-mode-map)))
;; Geiser / Arei 把 C-c 子树挂在 minor-mode keymap 上，需包本体与 which-key
;; 均就绪后才能注册。
(with-eval-after-load 'geiser-mode
  (with-eval-after-load 'which-key
    (self/which-key--apply-keymap-spec 'geiser-mode-map)))
(with-eval-after-load 'arei
  (with-eval-after-load 'which-key
    (self/which-key--apply-keymap-spec 'arei-mode-map)))

;; ─── Which-key 的触屏视觉层 ───────────────────────────────────────────
;;
;; 触屏没有 C-h，which-key 官方的翻页命令（C-h C-h p / n）发不出来，长按
;; 前缀键只能看到第一页。下面这组函数给弹窗**自绘**一页翻页按钮，并把触屏
;; tap 事件接成分发器。
;;
;; · `self/which-key--page-button'：把一截带 text-property keymap 的文本
;;   做成「[ 上一页 ]」形状的胶囊按钮（face 与 dashboard 的胶囊一致）。
;; · `self/which-key--paging-tap'：按落点处的 wk-page-button 属性分发到
;;   上/下一页命令。它**必须**挂在 global-map 的「前缀 + mouse 事件」组合
;;   序列上，原因见下方长注释。
;; · `self/which-key--insert-buttons-into-buffer' + `--popup-with-buttons'：
;;   弹窗 fit 之前把按钮行插进 which-key buffer 并把高度 +1，否则按钮会被
;;   裁掉。
;;
;; 桌面端不需要这层（鼠标有 C-h、有滚轮），但代码本身无平台副作用，故按
;; 档位归属（portable/full）而非平台分支：触屏之外的场景多注册几个
;; global 组合键不影响任何既有行为。

(defvar which-key--buffer)          ; which-key.el 弹窗缓冲区
(defvar which-key--pages-obj)       ; which-key.el 分页状态对象
(defvar which-key--paging-functions) ; which-key.el 翻页白名单
(declare-function which-key-show-next-page-cycle "which-key"
                  "翻到 which-key 弹窗的下一页。")
(declare-function which-key-show-previous-page-cycle "which-key"
                  "翻到 which-key 弹窗的上一页。")
(declare-function which-key--pages-pages "which-key"
                  "取 PAGES-OBJ 的页列表。")

(defun self/which-key-next-page ()
  "which-key 弹窗显示时翻到下一页，无弹窗时无操作。
交互命令：M-x self/which-key-next-page，供 mode-line 按钮组调用。
用 fboundp 守是必要的：which-key 尚未加载时这两个符号连 autoload 都没有，
而本命令挂在常驻的 mode-line 上，会在任意缓冲区被求值。"
  (interactive)
  (when (and (fboundp 'which-key--popup-showing-p)
             (which-key--popup-showing-p)
             (fboundp 'which-key-show-next-page-cycle))
    (which-key-show-next-page-cycle)))

(defun self/which-key--page-button (label command sym)
  "弹窗翻页按钮文本（[] 胶囊风格，与 dashboard 一致）。
SYM（prev/next）作 wk-page-button 属性标记，供前缀序列路径的
`self/which-key--paging-tap' 按落点分发；顶层 mouse/touchscreen
绑定覆盖无前缀场景。"
  (concat
   (propertize "[" 'face 'shadow)
   (propertize (format " %s " label)
               'keymap (let ((map (make-sparse-keymap)))
                         (define-key map [mouse-1] command)
                         (define-key map [mouse-2] command)
                         (define-key map [touchscreen-begin] command)
                         map)
               'wk-page-button sym
               'mouse-face 'highlight
               'follow-link t)
   (propertize "]" 'face 'shadow)))

;; ─── 前缀序列路径的翻页兜底 ────────────────────────────────────────
;; which-key 弹窗必然处于前缀键等待中，tap 事件以「前缀+事件」组合
;; 序列查找（如 "C-c <mouse-2>"）。GUI command loop 实测（端到端
;; 事件注入 + undefined 插桩）：带前缀的 mouse 事件组合序列**不查
;; text-property 键图、也不查 transient map**，只落 global/minor
;; 层——故组合绑定必须挂 global-map 的前缀子树。渲染安全：
;; which-key 内置 `which-key--ignore-non-evil-keys-regexp' 过滤
;; mouse- 条目，mouse 组合不会出现在弹窗里（touchscreen-begin
;; 不被过滤，故不绑 global；真机 tap 到达 command loop 实测即
;; mouse-2）。查不到绑定时 pre-command-hook 先藏弹窗清页再报
;; undefined，事后拦截已太晚，必须让查找命中。

(defun self/which-key--paging-tap (event)
  "按 EVENT 落点分发 which-key 翻页。
交互命令：以 `e' 接收 mouse 事件（M-x self/which-key--paging-tap 是
调试用入口），实际由下方绑到 global-map 前缀子树的组合序列触发。"
  (interactive "e")
  (let* ((start (event-start event))
         (pt (posn-point start)))
    (when (and (integerp pt) (> pt 0)
               (eq (window-buffer (posn-window start)) which-key--buffer))
      ;; 属性在落点 buffer 上，查询须显式切换（不依赖 command-loop
      ;; 派发 mouse 事件时的自动选窗）
      (with-current-buffer which-key--buffer
        (pcase (get-char-property pt 'wk-page-button)
          ('next (which-key-show-next-page-cycle))
          ('prev (which-key-show-previous-page-cycle)))))))

;; paging 前缀 × mouse 事件组合序列绑分发器（弹窗按钮 tap 即命中；
;; 落点不在按钮上则静默，覆盖的本是 undefined 报错场景）
(dolist (pfx '("C-x" "C-c" "C-h" "M-s" "M-g"))
  (dolist (ev '(mouse-1 mouse-2))
    (define-key global-map (vconcat (kbd pfx) (vector ev))
                #'self/which-key--paging-tap)))

;; mode 挂的 pre-command-hook `which-key--hide-popup' 对翻页白名单
;; （`which-key--paging-functions'）外的命令先藏弹窗并清 pages-obj，
;; 分发器随后执行时已无页可翻（真机 tap 翻页即弹窗消失根因）；
;; idle timer 路径的隐藏检查用同一白名单，一并豁免。
(with-eval-after-load 'which-key
  (add-to-list 'which-key--paging-functions #'self/which-key--paging-tap))

(defun self/which-key--insert-buttons-into-buffer ()
  "向 which-key buffer 末尾追加居中翻页按钮行（不动窗口）。"
  (with-current-buffer which-key--buffer
    (let* ((inhibit-read-only t)
           (btns (concat (self/which-key--page-button
                          "上一页" #'which-key-show-previous-page-cycle 'prev)
                         "  "
                         (self/which-key--page-button
                          "下一页" #'which-key-show-next-page-cycle 'next))))
      (goto-char (point-max))
      (insert "\n"
              (make-string (max 0 (/ (- (frame-width) (string-width btns)) 2))
                           ?\s)
              btns))))

(defun self/which-key--popup-with-buttons (orig dim)
  "多页时注入翻页按钮行并计入弹窗高度（fit 之前注入才可见）。"
  (when (and which-key--pages-obj
             (> (length (which-key--pages-pages which-key--pages-obj)) 1))
    (self/which-key--insert-buttons-into-buffer)
    (setcar dim (1+ (car dim))))
  (funcall orig dim))

(advice-add 'which-key--show-popup :around
            #'self/which-key--popup-with-buttons)

(defun self/which-key-ensure ()
  "确保 which-key 已开启（幂等）。idle 与绝对计时兜底共用。
用 bound-and-true-p 守：which-key 未加载时变量不存在，而本函数被
idle timer 与 20 秒绝对计时器直接调用，不经 autoload。"
  (unless (bound-and-true-p which-key-mode)
    (which-key-mode 1)))

;; 触屏专属的 which-key 取值覆盖：自-keys 给出三档共用默认值（桌面取向），
;; 这里按平台分支补触屏取向——底部弹窗（视线近）、窄屏列宽（描述限 20 列，
;; 否则 40 列窗的单列上限会让列宽算出负数崩渲染）、关掉 C-h 分发（触屏
;; 发不出 C-h，页脚键位提示随之消失，翻页改走上面的自绘按钮）。
(when self:android-p
  (use-package which-key
    :defer t
    :custom (which-key-idle-delay 0.6)
            (which-key-side-window-location 'bottom)
            (which-key-side-window-max-height 0.5)
            (which-key-min-display-lines 10)
            (which-key-max-description-length 20)
            (which-key-min-column-description-width 16)
            (which-key-add-column-padding 1)
            (which-key-allow-multiple-replacements t)
            ;; 触屏无 C-h：关 C-h 分发，翻页走弹窗按钮
            (which-key-use-C-h-commands nil)
            ;; 多层前缀启用官方 paging（翻页按钮依赖其分页状态）
            (which-key-paging-prefixes '("C-x" "C-c" "C-h" "M-s" "M-g"))
    :init
    ;; 空闲才加载并开启：包加载与中文描述注册不占启动时间。
    ;; 绝对计时兜底：Android 功耗管理下 idle timer 疑不触发（历史观察），
    ;; 只挂 idle 会让 which-key 永久缺席（含依赖它的触屏翻页按钮）
    (run-with-idle-timer 1 nil #'self/which-key-ensure)
    (run-with-timer 20 nil #'self/which-key-ensure)
    :config
    (self/which-key-apply-descriptions)))

(provide 'self-help-zh)
;;; self-help-zh.el ends here
