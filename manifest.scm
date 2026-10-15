;;; manifest.scm --- UniEmacs 开发环境（direnv use guix）
;;;
;;; 声明两类依赖：
;;;   1. 开发/验证工具链（just / git / ripgrep / fd / sqlite / make）。
;;;   2. profiles/*.el 清单里的全部第三方 Emacs 包（Guix 侧登记点）。
;;;      登记后 `guix shell -m manifest.scm -- just verify` 能在完整包
;;;      环境下跑三档冒烟与 byte-compile，不再是「找不到就跳过」。
;;;      用户桌面端的运行时包仍由 Guix home 提供，两处清单须保持同步；
;;;      便携档专用包已分组标注，桌面 home 可按需裁剪。
;;;
;;; 命名约定：Emacs Lisp 包名 → Guix 包名一律加 `emacs-' 前缀；
;;; 已知例外：`idle-highlight-mode' → `emacs-idle-highlight'。
;;; 新增依赖流程：先在本文件登记 → direnv reload（或 denv load）。

(specifications->manifest
 '("emacs"        ; batch byte-compile / 冒烟验证
   "just"         ; 本机命令入口（justfile）
   "git"          ; 版本控制
   "ripgrep"      ; 模块内外部检索依赖
   "fd"           ; 文件查找
   "sqlite"       ; org-roam CLI 后端（emacsql-sqlite3）
   "make"         ; 备用构建

   ;; ─── 两档共用 / full 档第三方包 ──────────────────────────────
   "emacs-dashboard"
   "emacs-nerd-icons"
   "emacs-minibuffer-line"
   "emacs-indent-bars"
   "emacs-goto-chg"
   "emacs-multiple-cursors"
   "emacs-expand-region"
   "emacs-vundo"
   "emacs-idle-highlight"   ; elisp 侧包名 idle-highlight-mode
   "emacs-tempel"
   "emacs-geiser"
   "emacs-arei"
   "emacs-magit"            ; 含 magit-diff feature，无独立包
   "emacs-diff-hl"
   "emacs-forge"
   "emacs-org-appear"
   "emacs-org-modern"
   "emacs-org-modern-indent"
   "emacs-olivetti"
   "emacs-org-roam"
   "emacs-emacsql"
   "emacs-markdown-mode"
   "emacs-apheleia"
   "emacs-dape"
   "emacs-envrc"
   "emacs-rainbow-delimiters"
   "emacs-fish-mode"
   "emacs-gdscript-mode"
   "emacs-kdl-mode"
   "emacs-nix-mode"
   "emacs-pdf-tools"
   "emacs-zig-mode"
   "emacs-agent-shell"
   "emacs-dsh-emacs"
   "emacs-telega"
   "emacs-guix"
   "emacs-ghostel"
   "emacs-agenote"
   "emacs-gcmh"
   "emacs-no-littering"

   ;; ─── portable 档专用（Android / elpaca 侧也按此清单安装）───────
   "emacs-vertico"
   "emacs-orderless"
   "emacs-marginalia"
   "emacs-consult"
   "emacs-embark"
   "emacs-embark-consult"
   "emacs-corfu"
   "emacs-cape"
   "emacs-ef-themes"
   "emacs-expreg"
   "emacs-emacsql-sqlite3"  ; Android 的 org-roam sqlite CLI 后端
   "emacs-nov"))
