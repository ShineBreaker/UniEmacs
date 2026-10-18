;;; manifest.scm --- UniEmacs 开发环境（direnv use guix）
;;;
;;; 声明两类依赖：
;;;   1. 开发/验证工具链（just / git / ripgrep / fd / sqlite / make）
;;;      与手机基建/图标重建工具（curl / jq / unzip / openjdk / fontconfig /
;;;      librsvg / netpbm，见「手机基建」组注释）。
;;;   2. profiles/*.el 清单里的全部第三方 Emacs 包（Guix 侧登记点）。
;;;      登记后 `guix shell -m manifest.scm -- just verify` 能在完整包
;;;      环境下跑四档冒烟与 byte-compile，不再是「找不到就跳过」。
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
   "sqlite"       ; org-roam 2.2.x 的 CLI 兜底后端（emacsql-sqlite）
   "make"         ; 备用构建

   ;; ─── 手机基建与图标重建（just 的 APK 构建 / 配置依赖组）─────────
   "curl"         ; 抓取上游预览版 APK / 字体与字体图标下载
   "jq"           ; 重签脚本解析 GitHub release API
   "unzip"        ; build-tools、字体包解包
   "openjdk"      ; apksigner（java -jar tools/apksigner.jar）
   "fontconfig"   ; fc-list：字体检测（font / glyph-check）与图标重建
   "librsvg"      ; rsvg-convert：图标重建（just icons 缺资产时）
   "netpbm"       ; pngtopam 等：modifier-bar 徽章生成（同上）

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
   "emacs-magit-fast"       ; 缓存 porcelain 加速 magit status（jeans channel）
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
   "emacs-dsh"            ; elisp 侧包名 dsh-emacs（上游 repo vritser/dsh-emacs）
   "emacs-telega"
   "emacs-guix"
   "emacs-ghostel"
   "emacs-agenote"
   "emacs-gcmh"
   "emacs-no-littering"

   ;; ─── portable / ide 档共用补全栈 ──────────────────────────────
   ;; 便携档（Android / 触屏点选）与 ide 档（桌面命令面板式补全）共用。
   "emacs-vertico"
   "emacs-orderless"
   "emacs-marginalia"
   "emacs-consult"
   "emacs-embark"          ; embark-consult.el 随本包分发，无独立包
   "emacs-corfu"
   "emacs-cape"

   ;; ─── ide 档专用 ──────────────────────────────────────────────
   "emacs-kind-icon"        ; corfu 补全项类型图标
   "emacs-eldoc-box"        ; posframe 文档/signature 浮窗
   "emacs-treemacs"         ; 左侧项目文件树
   "emacs-treemacs-nerd-icons"
   "emacs-colorful-mode"    ; 颜色字面量就地渲染（Zed colorizer 对应）
   "emacs-minimap"          ; 右侧代码缩略图

   ;; ─── portable 档专用 ──────────────────────────────────────────
   ;; emacsql-sqlite（org-roam 2.2.x 的 CLI 连接器）随 emacs-emacsql 分发，
   ;; 无需单独登记；org-roam 2.3+ 在 Android 上自动用内置 sqlite 后端。
   "emacs-ef-themes"
   "emacs-expreg"
   "emacs-nov"))
