;;; ide.el --- ide 档：Zed 对齐的深度定制桌面 -*- lexical-binding: t; -*-

;;; Commentary:
;; IDE 档：完整复刻 Zed/VSCode/JetBrains 的 IDE 体验。在 full 档
;; 全量模块之上叠加 IDE 设施——Treemacs 项目树、命令面板式补全栈
;; （vertico/corfu/kind-icon）、面包屑行、行内 Git blame、代码缩略图，
;; 以及鼠标平权层（Ctrl+点击跳定义、Shift+滚轮横滚、行槽断点、
;; 代码右键菜单）。本档是桌面默认 profile（未设 UNI_EMACS_PROFILE
;; 且非 Android 时落到这里）；显式选择仍可用：
;;
;;   UNI_EMACS_PROFILE=ide
;;
;; Profiles: ide
;; Requires: self-lib self-package
;;
;; 定位与关系：
;;   · minimal   纯内建底座；
;;   · portable  移动端触屏；
;;   · full      桌面全量、语法可读优先，定位「学习用完备配置」；
;;   · ide       本档。模块清单是 full 的超集：同一批模块按相同顺序
;;               require（差异只在 manifest 勾选与模块选择，符合
;;               AGENTS.md §2 加载契约），末端追加 modules/ide/ 六个
;;               覆写/新增模块。full 档刻意保留为可读性版本，不要为
;;               「避免重复」把 ide 的实现塞回 full。
;;
;; 覆写发生在 ide 模块内部（面包屑接管 header-line、Treemacs 接管
;; C-b 等键位、corfu 接管行内补全），不在本文件；本文件只负责
;; 包清单与 require 序列两件事。

;;; Code:

;; ─── 本档第三方包清单 ─────────────────────────────────────────────
;; full 档清单原样保留，尾部追加 ide 专属包。新增第三方包须同时在
;; manifest.scm（Guix 侧）登记。vertico 栈在本档是桌面组件而非
;; Android 专属（与 portable 档共用同一批包）。
(setq self:profile-packages
      '(;; full 档清单（与 profiles/full.el 保持一致，勿增删其一忘其二）
        dashboard nerd-icons minibuffer-line
        indent-bars goto-chg multiple-cursors expand-region
        vundo idle-highlight-mode tempel
        geiser arei
        magit diff-hl forge magit-fast
        org-appear org-modern org-modern-indent olivetti
        org-roam emacsql
        markdown-mode
        apheleia dape envrc rainbow-delimiters
        fish-mode gdscript-mode kdl-mode nix-mode pdf-tools zig-mode
        agent-shell dsh-emacs telega guix
        ghostel
        agenote
        gcmh no-littering
        ;; ide 档新增
        vertico orderless marginalia consult embark embark-consult
        corfu cape kind-icon eldoc-box
        treemacs treemacs-nerd-icons
        colorful-mode minimap))

(self/package-ensure)

;; ─── 模块 require 序列 ────────────────────────────────────────────
;;
;; 前半与 profiles/full.el 逐行同序（契约说明见该文件注释）；
;; 末端六个 self-ide-* 模块按「外观 → 面板 → 槽位 → 补全 → blame →
;; minimap」排列，全部排在 self-keys-desktop 之后：键位覆写必须
;; 最后落地。

(require 'self-compat)
(require 'self-session)
(require 'self-windowing)
(require 'self-keys)
(require 'self-completion)
(require 'self-editing)
(require 'self-theme)
(require 'self-help-zh)
(require 'self-terminal)
(require 'self-org)
(require 'self-roam)
(require 'self-agenote)
(require 'self-prog)
(require 'self-langs)
(require 'self-vcs)
(require 'self-project)
(require 'self-modeline)
(require 'self-tabline)
(require 'self-glyph)
(require 'self-dashboard)
(require 'self-apps)
(require 'self-daemon)
(require 'self-discover)
(require 'self-keys-desktop)

;; ─── ide 专属层 ───────────────────────────────────────────────────
;;
;; · self-ide-chrome      字体分轨、绝对行号、面包屑 header-line、
;;                        标签 Git/诊断着色、frame 标题、colorful。
;;                        依赖 self-theme/self-tabline/self-modeline 的
;;                        face 与缓存变量，排在其后。
;; · self-ide-panel       Treemacs 项目树 + 接管 C-b/C-S-e/C-c w f/d/T，
;;                        必须排在 self-keys-desktop 之后。
;; · self-ide-slots       三槽位窗口契约（左树/底面板/编辑区）：
;;                        display-buffer-alist 双层注册收编一切弹窗。
;; · self-ide-completion  vertico/corfu/kind-icon/eldoc-box 补全栈；
;;                        关掉 self-completion 的 completion-preview，
;;                        排在其后。
;; · self-ide-mouse       鼠标平权层：Shift+滚轮横滚、gutter 断点、
;;                        代码右键子菜单，并把已就绪的 Ctrl+点击/
;;                        Ctrl+滚轮缩放登记进帮助速查表。
;; · self-ide-blame       行内 Git blame，无三方包依赖。
;; · self-ide-minimap     右侧代码缩略图。

(require 'self-ide-chrome)
(require 'self-ide-panel)
(require 'self-ide-slots)
(require 'self-ide-completion)
(require 'self-ide-mouse)
(require 'self-ide-blame)
(require 'self-ide-minimap)

;; ─── 本档私有的两段 use-package 配置 ──────────────────────────────
;; 与 full 档同款（理由与取舍见 profiles/full.el 注释）。ide 是桌面档，
;; 同样需要 GC 空闲回收与 var/ 目录隔离。

(use-package gcmh
  :demand t
  :custom
  (gcmh-idle-delay 'auto)
  (gcmh-auto-idle-delay-factor 10)
  (gcmh-high-cons-threshold (* 32 1024 1024))
  :config
  (gcmh-mode 1))

(use-package no-littering
  :demand t
  :custom
  (no-littering-var-directory self:var-directory)
  (no-littering-etc-directory self:etc-directory)
  :config
  (setq backup-directory-alist
        `((".*" . ,(no-littering-expand-var-file-name "backup/"))))
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t)))
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file t)))

(provide 'self-profile-ide)
;;; ide.el ends here
