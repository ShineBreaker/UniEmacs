;;; self-langs.el --- 各语言 major mode 注册与语言级专属设置 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full, ide
;; Requires: self-compat, self-prog
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
;; ## Emacs 31 兼容性兜底（迁移自源配置的 noweb 片段）
;;
;; 下面两个兜底函数在源配置里以 noweb 片段（=emacs31/source-load-compat=
;; 与 =emacs31/arei-compat=）的形式集中定义、由本节代码块展开引用，
;; 现已就地展开到使用它们的代码旁边，并保留出处注释：
;;
;; - =emacs31/source-load-compat= → `self/load-library-from-source'：
;;   Guix 的 .elc 与 Emacs 31 的宏展开不兼容，需绕过只读 store 直接从
;;   .el 源加载。移除条件：相关包改由 Emacs 31 重编译。
;; - =emacs31/arei-compat= → `self--maybe-enable-arei-mode'：
;;   arei 0.9.7 的 .elc 与 Emacs 31 的 `buffer-local-set-state' 宏
;;   不兼容（bug#80812），会在 `scheme-mode-hook' 抛异常导致 Scheme
;;   染色失效。移除条件：升级 arei 或 Guix 用 Emacs 31 重编译。

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
;; 后缀到模式的登记。
(add-to-list 'auto-mode-alist '("\\.json\\'" . json-ts-mode))
(add-to-list 'auto-mode-alist '("\\.rs\\'" . rust-ts-mode))
(add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode))
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
(add-to-list 'auto-mode-alist '("\\.tsx\\'" . tsx-ts-mode))
(add-to-list 'auto-mode-alist '("\\.jsx\\'" . tsx-ts-mode))
(use-package zig-mode :mode "\\.zig\\'" :defer t)

;; ─── Emacs 31 兼容性兜底（原 noweb 片段 emacs31/*）────────────────────
;;
;; 两个 shim 的实现集中在 self-compat.el（全档加载的版本兼容层），本模块
;; 只消费：把 `<<emacs31/source-load-compat>>' 与 `<<emacs31/arei-compat>>'
;; 摊开的动作在那里完成，这里只负责在正确的时机挂上 scheme-mode-hook。

(declare-function self/load-library-from-source "self-compat")
(declare-function self--maybe-enable-arei-mode "self-compat")

(use-package arei
  :defer t
  :hook (scheme-mode . self--maybe-enable-arei-mode))

;; ─── Elisp 语义染色与 PDF 浏览 ───────────────────────────────────────

(setopt elisp-fontify-semantically t)

(add-to-list 'auto-mode-alist '("\\.cs\\'" . csharp-ts-mode))

(use-package pdf-tools
  :defer t
  :mode ("\\.pdf\\'" . pdf-view-mode)
  :magic ("%PDF" . pdf-view-mode)
  :config
  (pdf-tools-install t t))

(provide 'self-langs)
;;; self-langs.el ends here
