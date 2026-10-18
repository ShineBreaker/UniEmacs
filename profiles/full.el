;;; full.el --- full 档：桌面全量 -*- lexical-binding: t; -*-

;;; Commentary:
;; 桌面全量学习档：功能完备、语法平铺直白，桌面默认档是 ide，本档经
;; UNI_EMACS_PROFILE=full 显式选择。勾选全部模块，含编程栈（语言 /
;; LSP / VCS / 工程）、终端面板、知识库适配与桌面键位表。
;;
;; Profiles: full
;; Requires: self-lib self-package
;;
;; 本档与 portable 档共享 core/ 与 modules/，差异只在清单勾选：桌面专属的
;; 编程栈与键位表在这里加载，触屏设施（self-ui-touch / self-touch /
;; self-bar / self-reading）与它们的包不在本档。
;;
;; 平台差异（`self:android-p'）仍由各模块内部守卫承担：full 档跑在桌面，
;; 但 emacsclient 也可能从终端连上来，那些守卫会在运行时自然退化。

;;; Code:

;; ─── 本档第三方包清单 ─────────────────────────────────────────────
;; MELPA 包名，逐档汇总各模块头部的 `;; Packages:' 去重而来，外加尾部
;; gcmh / no-littering 两段 profile 私有配置所需的包。
;; 注意新增第三方包须同时在 manifest.scm（Guix 侧）登记。
;; 只列第三方包。内建（which-key / winner / editorconfig / eglot /
;; flymake / project / newsticker / context-menu / modus-themes）不登记；
;; vertico 栈只出现在 self-completion 的 Android 分支，桌面不装；
;; magit-diff 是 magit 包内部 feature，无独立包；
;; emacsql-sqlite3 是 Android 的 sqlite CLI 后端，桌面走内建 sqlite。
(setq self:profile-packages
      '(dashboard nerd-icons minibuffer-line
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
        gcmh no-littering))

(self/package-ensure)

;; ─── 模块 require 序列（即本档的依赖契约，顺序不可随意调换）────────
;;
;; · self-compat     Emacs 31 版本 shim（arei 染色兜底），必须早于
;;                   self-prog / self-langs——那两个模块在 scheme-mode-hook
;;                   上直接调用 `self--maybe-enable-arei-mode'。
;; · self-session    建立 var/ etc/ 落盘位置与 custom-file。
;; · self-windowing  窗口路由底层，被 self-vcs / self-project /
;;                   self-terminal 反向消费。
;; · self-keys       键位机制层底座，必须早于任何用 self/bind 的模块。
;; · self-theme      主题与菜单中文化，早于按主题面构造的 mode-line /
;;                   tabline（self-prog / self-tabline 依赖它）。
;; · self-help-zh    which-key 中文层与帮助入口，依赖 self-keys。
;; · self-terminal   ghostel 终端面板，依赖 self-editing 的
;;                   `self--buffers-in-mode' 与 self-windowing。
;; · self-org        Org 栈；self-agenote 的 capture 模板挂在它的装配点上。
;; · self-agenote    经验卡知识库，必须晚于 self-org。
;; · self-prog / self-langs / self-vcs / self-project  编程栈。
;; · self-modeline   mode-line 增强，必须早于 self-tabline。
;; · self-glyph      字形回退原语，self-dashboard 的桌面分支在加载期
;;                   就调用 `self/glyph'，必须排在它前面。
;; · self-dashboard  欢迎屏，消费 org / roam 的渲染结果与 help-zh 的
;;                   `self/show-help'，排在这三家之后。
;; · self-keys-desktop 桌面键位表，Requires 里列了 editing / terminal /
;;                   project / prog / tabline / completion / help-zh，
;;                   故排在全部模块之后。

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
(require 'self-keys-desktop)

;; ─── 本档私有的两段 use-package 配置 ──────────────────────────────
;;
;; gcmh（空闲垃圾回收）与 no-littering（目录隔离）刻意不进共享模块：
;; 前者是第三方包，minimal 档明令不得声明任何第三方包；后者接管
;; backup-directory-alist / auto-save-file-name-transforms / custom-file
;; 三处全局重定向，而 portable 档已有内建的等价实现在 self-session 里，
;; 两边同时生效会互相覆盖。故这两段按 AGENTS.md §2「档内覆写写在 profile
;; 文件内」的约定留在本文件尾部。进程级设置（read-process-output-max、
;; inhibit-startup-screen 等）与档位无关，已上提到 core/self-lib.el。

(use-package gcmh
  :demand t
  :custom
  ;; 空闲垃圾回收：持续敲键盘时暂停 GC，直到停下进入空闲才清理，
  ;; 彻底杜绝打字过程中的微卡顿。
  (gcmh-idle-delay 'auto)
  (gcmh-auto-idle-delay-factor 10)
  (gcmh-high-cons-threshold (* 32 1024 1024))
  :config
  (gcmh-mode 1))

;; no-littering 把备份、自动保存等文件从配置根目录赶进 var/，
;; 把 custom.el 放进 etc/，让仓库目录保持只读源码身份。
;; 原配置依赖 no-littering 的默认值（指向 user-emacs-directory），
;; UniEmacs 的仓库不在 ~/.emacs.d 下，故在此显式指定两处目录。
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
  ;; 注意：`custom-file' 是 Emacs 内建变量（自定义项的加载文件），
  ;; 不是本配置命名空间的符号，按 AGENTS.md §3 规定不改名。
  (setq custom-file (no-littering-expand-etc-file-name "custom.el"))
  (when (file-exists-p custom-file)
    (load custom-file t)))

(provide 'self-profile-full)
;;; full.el ends here
