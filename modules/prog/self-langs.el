;;; self-langs.el --- 各语言 major mode 注册与语言级专属设置 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: standard, ide
;; Requires: self-prog
;; Packages: arei, fish-mode, gdscript-mode, kdl-mode, markdown-mode,
;;           nix-mode, pdf-tools, zig-mode
;;
;; 移植自桌面端配置的「编程与开发」域之「各语言 major mode」一节。
;;
;; ## 为什么与 self-prog 分家
;;
;; self-prog 装的是「编程基础设施」——语言能力表、LSP、Tree-sitter、
;; 诊断、格式化与键位，这些对所有语言是同一套机制；本文件装的是
;; 「语言注册表」——具体某门语言的 mode 声明、后缀映射与该语言专属的
;; 兜底 shim。两者的变更节奏不同（基础设施很少动，语言表经常加一行），
;; 放一起会让能力表这条主线索被大量 mode 声明淹没。
;;
;; ## 语言覆盖与延迟加载
;;
;; TypeScript / TSX / JSX、Rust、JSON、KDL、Markdown、Nix、YAML、Zig、
;; GDScript、Fish、C#、Guile Scheme，以及 PDF 浏览。所有语言模式均
;; =:defer t=，只在打开对应后缀的文件时加载。Markdown 用传统 font-lock
;; 实现（不引 ts）；YAML 用 Emacs 31 内置的 yaml-ts-mode 并补了
;; =.yml.dist= 后缀；HTML 由能力表把 mhtml-ts-mode 升级到 html-mode，
;; 处理内嵌 JS/CSS。
;;
;; ## Elisp 语义染色
;;
;; 打开 Emacs 31 的 `elisp-fontify-semantically'：通过代码分析区分函数
;; 调用、变量与宏引用，比传统正则高亮精确得多。代价是对
;; dynamic-binding 老代码可能误判，故留成可关的 `setopt'。
;;
;; ## arei 启用策略
;;
;; arei 的 `.elc` 现已能直接加载（Emacs 32 + 当前 Guix 包实测），原先绕
;; store 从 .el 源加载的 Emacs 31 兼容层已不需要。仍然保留的是「跳过
;; org src 临时 buffer」这一层：org 导出/预览会把代码块复制进
;; ` *org-src-fontification:' 并在那里跑 major mode hook，那里没有文件名
;; 与目录上下文，让 arei 去猜类型只会得到噪声。启用失败也不该连带掐掉
;; font-lock，故仍包一层 condition-case。

;;; Code:

;; 外部命令名常量（self:executable-* 族）统一在 core/self-lib.el 定义，
;; 此处只就近声明取值来源，不带值——否则会与那里的 defconst 抢定义。
(defvar self:executable-godot)

;; ─── 各语言 mode 注册（全部 :defer t）────────────────────────────────

(use-package gdscript-mode
  :mode "\\.gd\\'"
  :defer t
  :custom
  (gdscript-godot-executable self:executable-godot))

(use-package fish-mode :mode "\\.fish\\'" :defer t)

;; 这几条 auto-mode-alist 覆盖把内置模式直接换成 ts 版本：能力表里
;; json / rust / typescript / tsx / csharp 都已登记 ts-mode，剩下只差
;; 后缀到模式的登记。只在语法库就绪时覆盖：Emacs 31 对这些后缀的默认
;; 映射是传统 mode 或自带 *-ts-mode-maybe（自查语法库、缺则降级），
;; 硬 ts 版本在缺库的环境（未跑 just grammars 的非 Guix 机器）会报错。
(declare-function treesit-ready-p "treesit" (language &optional quiet))

(defun self/langs--ts-mode-when-ready (regexp mode lang)
  "LANG 语法库就绪才把 REGEXP 覆盖到 MODE，否则保留内建兜底映射。"
  (when (treesit-ready-p lang t)
    (add-to-list 'auto-mode-alist (cons regexp mode))))

(self/langs--ts-mode-when-ready "\\.json\\'" 'json-ts-mode 'json)
(self/langs--ts-mode-when-ready "\\.rs\\'" 'rust-ts-mode 'rust)
(self/langs--ts-mode-when-ready "\\.ts\\'" 'typescript-ts-mode 'typescript)
(use-package kdl-mode :mode "\\.kdl\\'" :defer t)
(declare-function markdown-export "markdown-mode")
(defvar markdown-mode-map) ; keymap-set 的目标键图，markdown-mode 加载后才有

(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'")
  :defer t
  :config
  (keymap-set markdown-mode-map "C-c p" #'markdown-export)
  (which-key-add-major-mode-key-based-replacements
    'markdown-mode "C-c p" "导出 Markdown"))
(use-package nix-mode :mode "\\.nix\\'" :defer t)
(add-to-list 'auto-mode-alist '("\\.yml\\.dist\\'" . yaml-ts-mode-maybe))
(self/langs--ts-mode-when-ready "\\.tsx\\'" 'tsx-ts-mode 'tsx)
(self/langs--ts-mode-when-ready "\\.jsx\\'" 'tsx-ts-mode 'tsx)
(use-package zig-mode :mode "\\.zig\\'" :defer t)

;; ─── Scheme 染色（arei） ─────────────────────────────────────────────

(declare-function arei-mode "arei")

(defun self/langs--enable-arei-mode ()
  "在真实 Scheme 编辑 buffer 中启用 `arei-mode'（跳过 org src 临时 buffer）。
启用失败只记一条消息：font-lock 初始化才是用户真正要的语法高亮，不能
因为语义染色不可用就连普通高亮一起丢。"
  (unless (string-prefix-p " *org-src-fontification:" (buffer-name))
    (condition-case err
        (arei-mode 1)
      (error
       (message "[ERROR] arei-mode 启用失败,Scheme 染色不受影响: %S" err)))))

(use-package arei
  :defer t
  :hook (scheme-mode . self/langs--enable-arei-mode))

;; ─── Elisp 语义染色与 PDF 浏览 ───────────────────────────────────────

(setopt elisp-fontify-semantically t)

(self/langs--ts-mode-when-ready "\\.cs\\'" 'csharp-ts-mode 'c-sharp)

;; pdf-tools 不走 use-package：elpaca 后端下，配置加载后再对该文件
;; byte-compile 时，use-package 对本块的展开会截断编译产物（.elc 缺
;; provide，load-prefer-newer 选中它毒化启动链）。改写为等价的普通
;; 延迟加载形式，行为不变：打开 PDF 文件才加载、挂 auto-mode 与
;; magic 检测、加载后装服务器。
(add-to-list 'auto-mode-alist '("\\.pdf\\'" . pdf-view-mode))
(add-to-list 'magic-mode-alist '("%PDF" . pdf-view-mode))
(with-eval-after-load 'pdf-tools
  (pdf-tools-install t t))

(provide 'self-langs)
;;; self-langs.el ends here
