;;; self-prog.el --- 编程基础设施：语言能力表 / LSP / Tree-sitter / 诊断 / 格式化 / 代码键位 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, ide
;; Requires: self-keys, self-theme
;; Packages: apheleia, dape, eglot, envrc, flymake, rainbow-delimiters
;;
;; 移植自桌面端配置的「编程与开发」域（编程基础设施 + 代码操作辅助函数 +
;; 代码与导航键三节）。各语言 major mode 的注册见 self-langs。
;;
;; ## 单一事实源 + 派生的架构
;;
;; 本域是全配置里最典型的一套「一张主表 + 三条派生链」结构，读懂
;; `self:language-capabilities' 这一张表，整个域就通了：
;;
;; - *主表* `self:language-capabilities' 是全部语言能力的唯一登记处，
;;   每条是一个 plist（`:modes' / `:ts-mode' / `:server' / `:formatter'）。
;;   添加语言、换 LSP 服务端、改格式化工具，都只改这张表，别处不设钩子。
;; - *派生链* 主表下方有三个派生量：
;;   · `self:language-treesit-remaps' 与
;;     `self:language-apheleia-mode-alist' 是标准派生形状
;;     =(let (acc) (dolist (entry 主表) ...) (nreverse acc))=——循环收集
;;     再倒转。
;;   · `self:language-eglot-server-programs' 比纯收集多一步分组：同一
;;     server 命令要归并成一条，故构造抽成具名函数
;;     `self/language--derive-eglot-programs'（`assoc' 找到已有组就
;;     `setcdr' 追加 mode，否则新建）。
;;   · `self:language-apheleia-formatters' 是第四个量，但手写字面量、
;;     不从主表派生：它登记的是 formatter 的*定义*（函数符号），与 mode
;;     映射是两回事，别按名字和 mode-alist 混淆。
;;
;; ## nil 是显式语义
;;
;; 表里 `:server nil` = 该语言不启用 LSP；`:formatter nil` = 显式禁用
;; 格式化——后者会写入派生映射覆盖包自带的默认值（如 gdscript→gdformat），
;; 避免缺二进制的 formatter 在保存时空跑。读到 nil 不是「还没填」。
;;
;; ## 查询型 API 不设防
;;
;; =(project-current nil)= 、=(treesit-ready-p ...)= 这类函数用返回 nil
;; 表达「不适用」，本文件直接用 `or' / `when-let*' 处理，不包
;; `condition-case'。异常捕获只留给文件 I/O 与外部子进程，这是全仓库
;; 统一的防御边界。
;;
;; ## Tree-sitter grammar 从哪来
;;
;; 在 GNU Guix 环境下，Tree-sitter 语法解析库统一由系统 profile 提供，
;; 不需要用户手动拉源码编译：Guix 把 profile 里的 lib/tree-sitter 注入
;; `TREE_SITTER_GRAMMAR_PATH'，Emacs 启动时自动加进 `treesit-extra-load-path'。
;; 本文件做三件事：关掉运行时下载询问（保持环境可复现）、登记语言名与
;; `*-ts-mode' 命名不一致的覆盖表、按 grammar 就绪情况把传统 major-mode
;; 升级映射进 `major-mode-remap-alist'。
;;
;; ## Eglot 激活序列与大文件保护
;;
;; Eglot 按需懒加载：进入 `prog-mode' 触发加载，并自动开启行内类型提示。
;; 当 buffer 超过 `self:large-file-size-threshold'（2 MB）时跳过 LSP 索引
;; 与折叠解析——rust-analyzer 的全 crate 扫描、hs 折叠块解析都是同步高成本
;; 操作，打开生成代码/大数据文件时会卡顿；且这条降级路径与
;; `global-so-long-mode' 互斥。确需 LSP 可 M-x eglot 手动启动。
;;
;; ## 跨模块符号的归属
;;
;; - `self:large-file-size-threshold' 由外观/行号域的 self-theme 定义
;;   （defcustom），本文件只就近 defvar 声明一下，见 Requires 行。
;; - `self:executable-*' 是外部可执行文件名常量族。源配置里它们与
;;   git/aspell 等同属启动基础设施域的一张常量表，该表尚未移植；本文件
;;   先按「只用一次就近声明」的原则自建本域用到的两项。编排者若把整族
;;   挪进 core/self-lib，删掉下面两行并把 Requires 加上 self-lib 即可。

;;; Code:

;; ─── 跨模块依赖的就近声明 ────────────────────────────────────────────

;; `self:large-file-size-threshold' 的唯一定义在 core/self-lib.el
;;（self-theme 与本模块共用），此处只声明不赋值。
(defvar self:large-file-size-threshold)

;; 外部命令名常量（self:executable-* 族）统一在 core/self-lib.el 定义，
;; 这里只声明不赋值：带值声明会把那里的 defconst 顶掉（defvar 不会覆盖已绑
;; 定变量），所以一律写成不带值的 defvar。
(defvar self:executable-direnv)   ; envrc 注入 direnv 环境时调用的命令名
(defvar self:executable-godot)    ; gdscript-mode 指定 Godot 解释器时的命令名

(declare-function self/bind (key target description group &rest properties)
  "声明并绑定全局 KEY 到 TARGET，归 self-keys。")
(declare-function self/declare-binding-group (key description)
  "声明 Which-key 展示的中间分组 KEY，归 self-keys。")

;; 内建库与延迟加载包的就近声明。org / hideshow 是内建（自带 autoload，
;; batch 编译时不在内存里），编译期先拉进来；eglot、flymake 是第三方包
;; 且延迟加载，按 AGENTS.md §2 用 declare-function 声明而不 require。
(eval-when-compile
  (require 'org)
  (require 'org-src)
  (require 'org-element)
  (require 'hideshow))
(declare-function eglot-inlay-hints-mode (arg)
  "开关联 eglot 的 inline hint 显示，归 eglot 包。")
(declare-function eglot-code-actions ()
  "列出当前 LSP 服务器给的光标处代码操作，归 eglot 包。")
(declare-function eglot-rename ()
  "经 LSP 重命名光标处符号，归 eglot 包。")
(declare-function eglot-find-declaration ()
  "跳到 LSP 声明，归 eglot 包。")
(declare-function eglot-find-implementation ()
  "跳到 LSP 实现，归 eglot 包。")
(declare-function eglot-find-typeDefinition ()
  "跳到 LSP 类型定义，归 eglot 包。")
(declare-function flymake-show-buffer-diagnostics (&optional flymake-diagnostics)
  "在回显区列出当前 buffer 的诊断，归内建 flymake。")
;; gdb.el 与 treesit.el 都不在预加载集；这些变量本模块只写不读，
;; 声明不带值，避免编译期自由变量告警。
(defvar gdb-many-windows)
(defvar gdb-show-main)
(defvar treesit-auto-install-grammar)
(defvar treesit-load-name-override-list)

;; 编译期 require 已把 org/hideshow 拉进来，但它们的多数入口带 autoload
;; cookie，byte-compile 仍判定「运行期可能不存在」；逐一 declare-function
;; 是内建库的标准写法。
(declare-function org-src-get-lang-mode (&optional associated-buffer)
  "从当前 src 块推断语言 major mode，归内建 org-src。")
(declare-function org-element-map (&optional element)
  "返回元素类型及其合法父类型，归内建 org-element。")
(declare-function org-element-property (node property &optional inherit)
  "取元素 NODE 的 PROPERTY，归内建 org-element。")
(declare-function org-element--property (node property)
  "org-element-property 的内部版（不走继承），归内建 org-element。")
(declare-function org-element-type (node)
  "返回元素 NODE 的类型符号，归内建 org-element。")
(declare-function org-element-parse-buffer (&optional node)
  "解析当前 buffer 为元素树，归内建 org-element。")
(declare-function hs-cycle (arg)
  "折叠/展开当前块，归内建 hideshow。")
(declare-function hs-hide-block ()
  "折叠当前块，归内建 hideshow。")
(declare-function hs-show-block ()
  "展开当前块，归内建 hideshow。")
(declare-function hs-hide-all ()
  "折叠全部块，归内建 hideshow。")
(declare-function hs-show-all ()
  "展开全部块，归内建 hideshow。")
(declare-function hs-toggle-all ()
  "在折叠/展开全部之间切换，归内建 hideshow。")

;; `(require 'json)' 看似突兀，实为下文 Eglot 激活序列的前置：
;; `eglot-workspace-configuration' 的反引号模板里用了 `json-false'
;; （JSON 的 false 字面量表示），该模板在配置加载期就展开，比 eglot
;; 真正加载早，必须先在这里把 json.el 拉进来。
(require 'json)

;; ─── 主表：全部语言能力的唯一登记处 ──────────────────────────────────

(defconst self:language-capabilities
  '((:modes (c-mode c-ts-mode)
            :ts-mode c-ts-mode
            :server ("ccls")
            :formatter clang-format)
    (:modes (c++-mode c++-ts-mode)
            :ts-mode c++-ts-mode
            :server ("ccls")
            :formatter clang-format)
    (:modes (css-mode css-ts-mode)
            :ts-mode nil
            :server nil
            :formatter prettier-css)
    (:modes (emacs-lisp-mode)
            :ts-mode nil
            :server nil
            :formatter lisp-indent)
    (:modes (gdscript-mode)
            :ts-mode nil
            :server nil
            :formatter nil)
    (:modes (go-mode go-ts-mode)
            :ts-mode go-ts-mode
            :server ("gopls")
            :formatter gofmt)
    (:modes (java-mode java-ts-mode)
            :ts-mode java-ts-mode
            :server nil
            :formatter clang-format)
    (:modes (js-mode js-ts-mode)
            :ts-mode nil
            :server nil
            :formatter prettier-javascript)
    (:modes (json-mode json-ts-mode js-json-mode)
            :ts-mode json-ts-mode
            :server nil
            :formatter prettier-json)
    (:modes (less-css-mode)
            :ts-mode nil
            :server nil
            :formatter prettier)
    (:modes (markdown-mode)
            :ts-mode nil
            :server nil
            :formatter prettier-markdown)
    (:modes (nix-mode)
            :ts-mode nil
            :server nil
            :formatter nixfmt)
    (:modes (python-mode python-ts-mode)
            :ts-mode python-ts-mode
            :server ("pylsp")
            :formatter black)
    (:modes (rust-mode rust-ts-mode)
            :ts-mode rust-ts-mode
            :server ("rust-analyzer")
            :formatter rustfmt)
    (:modes (scheme-mode)
            :ts-mode nil
            :server nil
            :formatter lisp-indent)
    (:modes (typescript-mode typescript-ts-mode)
            :ts-mode typescript-ts-mode
            :server ("typescript-language-server" "--stdio")
            :formatter prettier-typescript)
    (:modes (tsx-ts-mode)
            :ts-mode nil
            :server ("typescript-language-server" "--stdio")
            :formatter prettier-typescript)
    (:modes (html-mode mhtml-ts-mode)
            :ts-mode mhtml-ts-mode
            :server nil
            :formatter prettier-html)
    (:modes (sh-mode)
            :ts-mode nil
            :server nil
            :formatter shfmt)
    (:modes (fish-mode)
            :ts-mode nil
            :server nil
            :formatter fish-indent)
    (:modes (yaml-mode yaml-ts-mode)
            :ts-mode nil
            :server nil
            :formatter yq-yaml)
    (:modes (zig-mode)
            :ts-mode nil
            :server ("zls")
            :formatter zig-fmt)
    (:modes (csharp-ts-mode)
            :ts-mode nil
            :server nil
            :formatter nil))
  "统一的语言能力表。每条条目:
  :modes     生效的所有 major mode 列表(传统 mode 在前,ts-mode 在后)
  :ts-mode   Tree-sitter 对应 mode(nil 表示无 ts 版本)
  :server    LSP server 启动命令列表(nil 表示无 LSP)
  :formatter Apheleia formatter 符号(nil 表示显式禁用)")

;; ─── 派生一：Tree-sitter remap 表 ───────────────────────────────────

(defconst self:language-treesit-remaps
  (let (remaps)
    (dolist (entry self:language-capabilities)
      (let ((orig-mode (car (plist-get entry :modes)))
            (ts-mode (plist-get entry :ts-mode)))
        (when (and orig-mode ts-mode)
          (push (cons orig-mode ts-mode) remaps))))
    (nreverse remaps))
  "Tree-sitter major mode remap 列表(从 `self:language-capabilities' 派生)。
只收录同时给出传统 mode 与 ts-mode 的条目,例:
((c-mode . c-ts-mode) (c++-mode . c++-ts-mode) ...),顺序同能力表。")

;; ─── 派生二：Eglot server 配置（按命令归并）──────────────────────────

(defun self/language--derive-eglot-programs ()
  "把 `self:language-capabilities' 按 :server 展平为 eglot 条目。
同一 server 的多语言合并为 (MODE... . SERVER-CMD) 一条(:server 是命令行
列表,同命令的不同写法按 `equal' 视为同一 server);返回的 mode 列表是
新 cons,不与能力表共享结构。"
  (let (groups)
    (dolist (entry self:language-capabilities)
      (let ((server (plist-get entry :server)))
        (when server
          ;; `assoc' 用 `equal' 比较 car,故 ("gopls") 这类命令行列表
          ;; 按内容而非按 eq 归并。
          (let ((existing (assoc server groups)))
            (if existing
                (setcdr existing
                        (append (cdr existing) (plist-get entry :modes)))
              (push (cons server (copy-tree (plist-get entry :modes)))
                    groups))))))
    (let (programs)
      (dolist (group (nreverse groups))
        ;; 分组形状是 (SERVER-CMD . MODES),eglot 要的是反过来。
        (push (cons (cdr group) (car group)) programs))
      (nreverse programs))))

(defconst self:language-eglot-server-programs
  (self/language--derive-eglot-programs)
  "附加到 `eglot-server-programs' 的语言服务器配置(从能力表派生,按 server 命令去重)。
例:((c-mode c++-mode) . (\"ccls\")) —— 同一 server 的语言合并为一条。")

;; ─── 派生三：Apheleia formatter 定义与 mode 映射 ────────────────────

(defconst self:language-apheleia-formatters
  '((org-src-blocks . self--format-org-src-blocks))
  "Apheleia 自定义 formatter 定义(mode-alist 只引用符号);
dotted 条目为函数 formatter(value 是函数符号,协议同 apheleia-indent-lisp-buffer)。
org-src-blocks 不进 mode-alist,仅由 C-c o f(self/format-org-src-blocks)调用。")

(defconst self:language-apheleia-mode-alist
  (let (alist)
    (dolist (entry self:language-capabilities)
      (let ((formatter (plist-get entry :formatter)))
        (dolist (mode (plist-get entry :modes))
          (push (cons mode formatter) alist))))
    (nreverse alist))
  "Apheleia major mode 对应关系(从 `self:language-capabilities' 派生)。
每个 mode 一条,例:((c-mode . clang-format) (css-mode . prettier-css) ...),
顺序同能力表。
:formatter nil 的条目也写入,value 为 nil 显式禁用格式化——覆盖包默认
mode-alist 的残留映射(如 gdscript→gdformat),缺二进制的 formatter 不会
在保存时空跑。")

;; ─── Tree-sitter grammar 加载 ───────────────────────────────────────

(setq treesit-auto-install-grammar nil)

(add-to-list 'treesit-load-name-override-list
             '(c-sharp "libtree-sitter-c_sharp" "tree_sitter_c_sharp"))

(defconst self--treesit-lang-overrides
  '((c++-ts-mode . cpp) (csharp-ts-mode . c-sharp) (mhtml-ts-mode . html))
  "Tree-sitter 语言名与 `*-ts-mode' 命名不一致的覆盖表。")

(require 'treesit)
(dolist (mapping self:language-treesit-remaps)
  (let ((ts-mode (cdr mapping)))
    ;; `fboundp' 守的是「这个 ts mode 的包在本档有没有装」——第三方包
    ;; 延迟加载,不是同仓库内部调用。
    (when (fboundp ts-mode)
      (let* ((name (symbol-name ts-mode))
             (override (cdr (assq ts-mode self--treesit-lang-overrides)))
             (lang (or override
                       (intern (string-remove-suffix "-ts-mode" name)))))
        (when (treesit-ready-p lang t)
          (add-to-list 'major-mode-remap-alist mapping))))))

;; ─── Eglot 激活序列 ─────────────────────────────────────────────────

(defun self--eglot-enable-inlay-hints ()
  "eglot-managed-mode 回调：开启 inlay hints。"
  (eglot-inlay-hints-mode 1))

(defun self--maybe-enable-prog-helpers ()
  "`prog/conf-mode-hook' 回调:小 buffer 才启用 LSP 与折叠。
大文件(buffer 超过 `self:large-file-size-threshold')的 LSP 索引
(rust-analyzer 全 crate 扫描)与 hs 折叠块解析是同步高成本操作,且与
`global-so-long-mode' 的降级路径互斥,故跳过;LSP 仍可用 M-x eglot
手动启动。"
  (unless (> (buffer-size) self:large-file-size-threshold)
    (eglot-ensure)
    (hs-minor-mode 1)))

(use-package eglot
  :defer t
  :hook (prog-mode . self--maybe-enable-prog-helpers)
  :custom
  (eglot-autoshutdown t)
  (eglot-workspace-configuration
   `((:pylsp . (:plugins
                (:black (:enabled t)
                        :pylsp_mypy (:enabled t :live_mode nil)
                        :rope (:enabled t)
                        :pycodestyle (:enabled ,json-false)
                        :mccabe (:enabled ,json-false)
                        :pyflakes (:enabled ,json-false))))))
  :config
  (dolist (prog self:language-eglot-server-programs)
    (add-to-list 'eglot-server-programs prog))
  (add-hook 'eglot-managed-mode-hook #'self--eglot-enable-inlay-hints))

;; ─── Org 代码块格式化 ───────────────────────────────────────────────

(defun self--src-block-region (el)
  "EL 是可格式化的 src block 时返回 (起点 终点 MAJOR-MODE)，否则 nil。
三种块判为不可格式化：块没有正文（:value 为 nil）；语言标成 org
（那是元块，缩进归 org 的列表规则管，插进 formatter 会双重缩进）；
语言查不到对应 major mode（org-src-get-lang-mode 返回 nil，或返回的
名字背后没有命令，eg. 块里写了个没装的语言）。"
  (when (org-element-property :value el)
    (let ((lang (org-element-property :language el)))
      (when (and lang (not (equal lang "org")))
        (let ((mode (org-src-get-lang-mode lang)))
          (when (and mode (fboundp mode))
            (list (org-element-property :post-affiliated el)
                  (org-element-property :end el)
                  mode)))))))

(cl-defun self--format-org-src-blocks
    (&key buffer scratch callback &allow-other-keys)
  "按各语言的 major mode 缩进 org BUFFER 中全部 src block 代码。
SCRATCH 为承载变换的临时 buffer,CALLBACK 在变换完成后调用。
块在 org 列表/大纲里的缩进由 #+begin_src 行的缩进决定:写回前
先整体 dedent 再按 mode 缩进,最后按 base 缩进平移回去,保证
列表内代码块的 org 层级语义不变。"
  (with-current-buffer scratch
    (funcall (buffer-local-value 'major-mode buffer))
    (let (regions)
      ;; 每个可格式化的块贡献一个 (起点 终点 模式) 三元组。REGIONS 按块在
      ;; 文档中的先后 push，读的时候是逆序——下面的变换逐块独立，与顺序无关。
      (org-element-map (org-element-parse-buffer) 'src-block
        (lambda (el)
          (let ((region (self--src-block-region el)))
            (when region
              (push region regions)))))
      ;; 缩进变换对每个块独立完成，逐块按 BEG / EL-END / MODE 平铺处理。
      (dolist (region regions)
        (let ((beg (nth 0 region))
              (el-end (nth 1 region))
              (mode (nth 2 region)))
          (goto-char beg)
          (let ((base-indent (current-indentation)))
            (forward-line 1)
            (let* ((cbeg (point))
                   (cend (save-excursion
                           (re-search-forward "^[ \t]*#\\+end_src" el-end t)
                           (line-beginning-position)))
                   (content (buffer-substring-no-properties cbeg cend)))
              (with-temp-buffer
                (insert content)
                (when (> base-indent 0)
                  (indent-rigidly (point-min) (point-max) (- base-indent)))
                (funcall mode)
                (indent-region (point-min) (point-max))
                (when (> base-indent 0)
                  ;; 缩进补回去时跳过空行，否则纯空白行会累积前导空格。
                  (let ((pad (make-string base-indent ?\s)))
                    (goto-char (point-min))
                    (while (not (eobp))
                      (unless (looking-at-p "[ \t]*$")
                        (insert pad))
                      (forward-line 1))))
                (setq content (buffer-substring-no-properties
                               (point-min) (point-max))))
              (delete-region cbeg cend)
              (insert content))))))
    (funcall callback)))

;; `self/format-org-src-blocks' 的唯一实现在 self-org.el：它在
;; Apheleia 可用时走下面的 org-src-blocks formatter，否则退回内建
;; 缩进——命令本体不重复定义，本模块只负责注册 formatter。
(declare-function self/format-org-src-blocks "self-org")

;; ─── 异步保存自动格式化（Apheleia）─────────────────────────────────

;; 保存代码文件时自动在后台异步运行格式化工具（例如 prettier、rustfmt），
;; 光标位置和屏幕滚动不会发生任何跳动。
;; C-c c f 手动触发全缓冲区格式化；若某门语言需要 LSP 内部的格式化器，
;; 执行 M-x eglot-format-buffer。
;;
;; 下面两个 dolist 把语言能力表派生的映射灌进 apheleia 自身的两张表。
;; 这里特意用 =(setf (alist-get KEY LIST) VAL)= 而非 =push=：它的语义是
;; 「KEY 已存在则原位替换、不存在才追加」，整份配置重新求值（如手动
;; eval-buffer）时不会叠加出重复条目；push 做不到这一点。这是本仓库少数
;; 保留 setf 通用化 setq 的地方。
(use-package apheleia
  :hook ((prog-mode markdown-mode yaml-ts-mode) . apheleia-mode)
  :config
  (apheleia-global-mode 1)
  (dolist (formatter self:language-apheleia-formatters)
    (setf (alist-get (car formatter) apheleia-formatters)
          (cdr formatter)))
  (dolist (mapping self:language-apheleia-mode-alist)
    (setf (alist-get (car mapping) apheleia-mode-alist)
          (cdr mapping))))

;; ─── 实时诊断与调试辅助（Flymake, Dape, GDB）────────────────────────

;; - Flymake 语法检查：Eglot 启动后会自动挂接 Flymake。错误与警告会在
;;   行号左边缘标记，并在受影响行下方以图形清晰排版。
;; - 环境与调试辅助：启用 envrc 自动注入 Direnv 环境变量，启用
;;   rainbow-delimiters 彩虹括号，配置 Smerge 处理 Git 冲突，
;;   以及 GDB 与 Dape 调试支持。

(use-package flymake
  :defer t
  :custom
  (flymake-fringe-indicator-position 'left-fringe)
  (flymake-show-diagnostics-at-end-of-line 'fancy)
  (flymake-no-changes-timeout 0.5))

(defun self/flymake-list-errors-dwim ()
  "打开/关闭 Flymake 诊断列表面板。交互命令（绑定在 =M-g l= / =C-c c k=）。
面板已显示则关掉，否则打开；两者都不显示时才当作「首次打开」。"
  (interactive)
  (let ((buf (get-buffer "*Flymake diagnostics*")))
    (if (and buf (get-buffer-window buf))
        (quit-window nil (get-buffer-window buf))
      (flymake-show-buffer-diagnostics))))

(use-package envrc
  :demand t
  :if (executable-find self:executable-direnv)
  :config
  (envrc-global-mode 1))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(dolist (hook '(prog-mode-hook text-mode-hook))
  (add-hook hook #'smerge-mode))
(setq gdb-many-windows t
      gdb-show-main t)

(use-package dape
  :defer t
  :commands (dape dape-breakpoint-toggle))

;; ─── 代码操作辅助函数 ───────────────────────────────────────────────

(defun self/code-move-line (n)
  "将当前行下移 N 行;N 为负则上移,首行上移时不动。
交互命令（前缀数字＝移动行数，默认 1）。"
  (interactive "p")
  (dotimes (_ (abs n))
    (if (< n 0)
        (when (> (line-beginning-position) (point-min))
          (transpose-lines 1)
          (forward-line -2))
      (forward-line 1)
      (transpose-lines 1)
      (forward-line -1))))

(defun self/code-move-line-up ()
  "把当前行上移一行。交互命令（绑定在 =C-S-<up>=）。"
  (interactive)
  (self/code-move-line -1))

(defun self/code-move-line-down ()
  "把当前行下移一行。交互命令（绑定在 =C-S-<down>=）。"
  (interactive)
  (self/code-move-line 1))

(defun self/workspace-symbol ()
  "列出并跳转到工作区符号(VSCode Ctrl+T)。
交互命令（绑定在 =C-t=）。等价于 =C-u M-.':前缀参数让
`xref-find-definitions' 走 completing-read 弹出全部 workspace 符号,
由 Eglot 后端供数;无 LSP 时退化为提示输入标识符。"
  (interactive)
  (let ((current-prefix-arg '(4)))
    (call-interactively #'xref-find-definitions)))

(defun self/goto-matching-bracket ()
  "跳到与点相邻括号的配对处(VSCode Go to Bracket)。
交互命令（绑定在 =C-c c j=）。点在开括号上跳闭括号、闭括号后跳开括号;
在符号内部时退到外层结构起点,便于连续按 =C-M-u'/=C-M-f' 在结构间穿梭。"
  (interactive)
  (cond
   ((eq (char-syntax (char-after)) ?\() (forward-sexp))
   ((eq (char-syntax (char-before)) ?\)) (backward-sexp))
   (t (backward-up-list))))

;; ─── 代码与导航键 ───────────────────────────────────────────────────

;; - 跳转与错误穿梭（M-g 前缀）：
;;   =M-g n= / =M-g p= ：上一个 / 下一个诊断报错（Flymake）。
;;   =M-g l= ：打开或关闭诊断错误列表。
;;   =M-g r= ：查找当前符号的全部引用（References）。
;;   =M-g b= / =M-g f= ：跳回上一个位置或前进到下一个位置；鼠标侧键
;;     =<mouse-8>= / =<mouse-9>= 同义。
;;   =M-g g= ：跳转到指定行（VSCode Ctrl+G 的等价位）。
;;   =M-g j= ：Avy 屏幕内字符快速跳转。
;;   =C-t= ：列出并跳转工作区符号（VSCode Ctrl+T）。
;; - 代码重构与常用操作（C-c c 前缀）：
;;   =C-c c d= ：跳转到定义（Definition）。
;;   =C-c c a= ：呼出 LSP 代码修复动作（Code Actions）。
;;   =C-c c n= ：变量或函数全局重命名（Rename）。
;;   =C-c c f= ：格式化当前代码文件（Apheleia）。
;;   =C-c c i= ：文件内符号大纲（Imenu）。
;;   =C-c c j= ：跳转到匹配括号（Go to Bracket）。
;;   =C-c c z ...= ：代码块折叠与展开（Hideshow）；GUI 下也可用
;;     =C-S-[= / =C-S-]= 直接折叠/展开（VSCode Ctrl+Shift+[/]）。
;;
;; 键位全部经 self/bind 声明（归 self-keys）：一处绑定即同时注册
;; Which-key 中文提示与帮助速查表条目。

(autoload 'flymake-goto-next-error "flymake")
(autoload 'flymake-goto-prev-error "flymake")
(self/bind "M-g n" #'flymake-goto-next-error "下一个错误" "跳转与错误")
(self/bind "M-g p" #'flymake-goto-prev-error "上一个错误" "跳转与错误")
(self/bind "M-g l" #'self/flymake-list-errors-dwim "错误列表" "跳转与错误")
(self/bind "M-g r" #'xref-find-references "查找引用" "跳转与错误")
(self/bind "M-g b" #'xref-go-back "后退" "跳转与错误")
(self/bind "M-g f" #'xref-go-forward "前进" "跳转与错误")
(self/bind "<mouse-8>" #'xref-go-back "后退(鼠标侧键)" "跳转与错误")
(self/bind "<mouse-9>" #'xref-go-forward "前进(鼠标侧键)" "跳转与错误")
(self/bind "M-g g" #'goto-line "跳转到行" "跳转与错误")
(self/bind "M-g j" #'avy-goto-char-timer "屏幕内跳转" "跳转与错误")
(self/bind "M-g h" #'eldoc-doc-buffer "文档缓冲区" "跳转与错误")
(self/bind "C-t" #'self/workspace-symbol "工作区符号" "跳转与错误")
(self/bind "C-c c j" #'self/goto-matching-bracket "匹配括号" "代码")

(self/bind "C-c c d" #'xref-find-definitions "跳转到定义" "代码")
(dolist (cmd '(eglot-code-actions eglot-rename eglot-find-declaration
                                  eglot-find-implementation
                                  eglot-find-typeDefinition))
  (autoload cmd "eglot"))
(self/bind "C-c c a" #'eglot-code-actions "代码操作" "代码")
(self/bind "C-c c n" #'eglot-rename "重命名符号" "代码")
(self/bind "C-c c c" #'completion-at-point "触发补全" "代码")
(self/bind "C-c c i" #'imenu "符号大纲" "代码")
(self/bind "C-c c k" #'self/flymake-list-errors-dwim "诊断列表" "代码")
(self/bind "C-c c s" #'xref-find-references "引用搜索" "代码")
(self/bind "C-c c b" #'bookmark-jump "书签跳转" "代码")
(self/bind "C-c c m" #'bookmark-set "设置书签" "代码")
(self/declare-binding-group "C-c c x" "更多代码跳转")
(self/bind "C-c c x d" #'eglot-find-declaration "跳转到声明" "代码")
(self/bind "C-c c x i" #'eglot-find-implementation "跳转到实现" "代码")
(self/bind "C-c c x t" #'eglot-find-typeDefinition "跳转到类型定义" "代码")

(self/bind "C-c c f" #'apheleia-format-buffer "格式化" "代码")

(add-hook 'conf-mode-hook #'self--maybe-enable-prog-helpers)

(global-xref-mouse-mode 1)
(setq hs-show-indicators t
      hs-display-lines-hidden t)
(dolist (cmd '(hs-cycle hs-hide-block hs-show-block
                        hs-hide-all hs-show-all hs-toggle-all))
  (autoload cmd "hideshow"))
(self/bind "C-c c z a" #'hs-cycle "循环当前折叠" "代码")
(self/bind "C-c c z c" #'hs-hide-block "关闭当前折叠" "代码")
(self/bind "C-c c z o" #'hs-show-block "打开当前折叠" "代码")
(self/bind "C-c c z m" #'hs-hide-all "全部折叠" "代码")
(self/bind "C-c c z r" #'hs-show-all "全部展开" "代码")
(self/bind "C-c c z s" #'hs-toggle-all "开关全部折叠" "代码")
(self/bind "C-S-[" #'hs-hide-block "折叠代码块" "代码")
(self/bind "C-S-]" #'hs-show-block "展开代码块" "代码")

(provide 'self-prog)
;;; self-prog.el ends here
