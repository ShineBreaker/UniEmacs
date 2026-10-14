;;; manifest.scm --- UniEmacs 开发环境（direnv use guix）
;;;
;;; 声明本仓库开发/验证所需的工具链。Emacs 本体与各 emacs-* 包
;;; 由用户的 Guix profile 提供（full 档运行侧），此处只声明
;;; 开发与验证工具，保持最小。
;;;
;;; 新增依赖流程：先在本文件登记 → direnv reload（或 denv load）。

(specifications->manifest
 '("emacs"        ; batch byte-compile / 冒烟验证
   "just"         ; 本机命令入口（justfile）
   "git"          ; 版本控制
   "ripgrep"      ; 模块内外部检索依赖
   "fd"           ; 文件查找
   "sqlite"       ; org-roam CLI 后端（emacsql-sqlite3）
   "make"))       ; 备用构建
