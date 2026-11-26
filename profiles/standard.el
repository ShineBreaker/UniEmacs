;;; standard.el --- standard 档：桌面全量 -*- lexical-binding: t; -*-

;;; Commentary:
;; 桌面全量学习档：目标是增强的完整 Emacs 体验，重点在于学习与掌握
;; Emacs 独有特性。桌面默认档（IDE 档请显式选 ide）。勾选全部模块，
;; 含编程栈（语言 / LSP / VCS / 工程）、
;; 终端面板、知识库适配、桌面键位表，以及 self-discover——把窄化、
;; 寄存器、键盘宏、矩形、间接缓冲、Ediff、hi-lock、递归 minibuffer
;; 等 Emacs 独门机制翻出来并中文化的那一层。
;;
;; Profiles: standard
;; Requires: self-lib self-package
;;
;; 本档与 portable 档共享 core/ 与 modules/，差异只在清单勾选：桌面专属的
;; 编程栈与键位表在这里加载，触屏设施（self-ui-touch / self-touch /
;; self-bar / self-reading）与它们的包不在本档。
;;
;; 平台差异（`self:android-p'）仍由各模块内部守卫承担：standard 档跑在桌面，
;; 但 emacsclient 也可能从终端连上来，那些守卫会在运行时自然退化。

;;; Code:

;; ─── 本档第三方包清单 ─────────────────────────────────────────────
;; MELPA 包名，逐档汇总各模块头部的 Packages 清单去重而来。
;; 注意新增第三方包须同时在 manifest.scm（Guix 侧）登记。
;; 只列第三方包。内建（which-key / winner / editorconfig / eglot /
;; flymake / project / context-menu / modus-themes）不登记；
;; vertico 栈只出现在 self-completion 的 Android 分支，桌面不装；
;; magit-diff 是 magit 包内部 feature，无独立包；
;; emacsql-sqlite（CLI 连接器）随 emacsql 包分发，桌面与新版 Android 用内置 sqlite。
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
        jupyter
        fish-mode gdscript-mode kdl-mode nix-mode pdf-tools zig-mode
        agent-shell dsh-emacs guix
        ghostel
        agenote))

(self/package-ensure)

;; ─── 模块 require 序列（即本档的依赖契约，顺序不可随意调换）────────
;;
;; · self-session    建立 var/ etc/ 落盘位置与 custom-file。
;; · self-bootstrap  首次启动后台补全字体/语法库，只依赖 self-lib 与
;;                   self-package，紧跟 session 即可。
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
;; · self-prog / self-langs / self-jupyter / self-vcs / self-project  编程栈。
;;   self-jupyter 排在 self-langs 之后：REPL 与 Org Babel 块要等语言
;;   模式都注册完，才有稳定的 python-mode 等宿主 buffer 可挂。
;; · self-modeline   mode-line 增强，必须早于 self-tabline。
;; · self-glyph      字形回退原语，self-dashboard 的桌面分支在加载期
;;                   就调用 `self/glyph'，必须排在它前面。
;; · self-dashboard  欢迎屏，消费 org / roam 的渲染结果与 help-zh 的
;;                   `self/show-help'，排在这三家之后。
;; · self-keys-desktop 桌面键位表，Requires 里列了 editing / terminal /
;;                   project / prog / tabline / completion / help-zh，
;;                   故排在全部模块之后。

(require 'self-session)
(require 'self-bootstrap)
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
(require 'self-jupyter)
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

(provide 'self-profile-standard)
;;; standard.el ends here
