;;; portable.el --- portable 档：移动端（Android）全量 -*- lexical-binding: t; -*-

;;; Commentary:
;; 跑在 Android 原生 Emacs 上的全量档：触屏优化、移动端包管理（无 Guix
;; 时走 elpaca）与同步链路。
;;
;; Profiles: portable
;; Requires: self-lib self-package
;;
;; 本档与 full 档共享 core/ 与 modules/ 里标 Profiles: portable 的模块，
;; 差异只在清单勾选：桌面专属的编程栈（self-prog / self-langs / self-vcs /
;; self-project / self-apps）、终端面板（self-terminal）、agenote 知识库
;; （self-agenote）与桌面键位表（self-keys-desktop）都不在本档加载。
;;
;; 平台差异（`self:android-p'）由各模块内部守卫承担，不在这里做——例如
;; self-completion 的第三方补全栈、self-org 的操作面板与议程提醒、
;; self-dashboard 的窄屏视觉层，都是模块内 `(when self:android-p …)'。

;;; Code:

;; ─── 本档第三方包清单 ─────────────────────────────────────────────
;; MELPA 包名，逐档汇总各模块头部的 `;; Packages:' 去重而来。
;; 注意新增第三方包须同时在 manifest.scm（Guix 侧）登记。
;; 只列第三方包。which-key / winner / editorconfig / modus-themes /
;; context-menu（mouse.el）等在 Emacs 30+ 均为内建，不再登记；
;; geiser / arei / magit 虽在 self-help-zh 的 Packages 头里，但触屏端
;; 只消费它的 which-key 中文层，不进本清单。
(setq self:profile-packages
      '(dashboard nerd-icons
        vertico orderless marginalia consult embark embark-consult corfu cape
        indent-bars goto-chg multiple-cursors expand-region
        vundo idle-highlight-mode tempel
        expreg
        org-appear org-modern org-modern-indent olivetti
        org-roam emacsql
        markdown-mode
        nov))

;; 主题用 Modus（Emacs 内建，桌面/Android 共用，切档见 modules/ui/self-theme.el），
;; 故不再装 ef-themes。emacsql 包自带 emacsql-sqlite.el（org-roam 2.2.x 的
;; `sqlite' 连接器）；Emacs 29+ 的 Android 构建已内置 sqlite3，org-roam 2.3+
;; 自动选内置后端。

(self/package-ensure)

;; ─── 模块 require 序列（即本档的依赖契约，顺序不可随意调换）────────
;;
;; · self-glyph       图标字形回退表，被 self-ui-touch / self-touch /
;;                     self-dashboard / self-bar 引用。
;; · self-session     建立 var/ etc/ 落盘位置与 custom-file。
;; · self-keys        键位机制层底座，必须早于任何用 self/bind 的模块。
;; · self-theme       主题与菜单中文化，早于按主题面构造视觉的 UI 模块。
;; · self-editing     依赖 self-keys 与 self-lib 路径常量。
;; · self-completion  minibuffer / isearch / 行内补全。
;; · self-ui-touch    触屏 mode-line 按钮与配色；内部有大量
;;                     self/mode-line--button 的加载期求值。
;; · self-touch       触屏键盘、选择面板、expreg 钮表——同样在加载期就调用
;;                     self-ui-touch 的 self/mode-line--button，故必须在其后。
;; · self-help-zh     which-key 中文层与帮助入口，依赖 self-keys。
;; · self-org         Org 栈；其 Android 分支在加载期派生自 self-touch 的
;;                     self/touch-confirm-mode，故必须晚于 self-touch。
;; · self-roam        双链笔记，依赖 self-keys 与 self-org 的路径常量。
;; · self-markdown    触屏 Markdown 阅读视图。
;; · self-dashboard   欢迎屏窄屏视觉层，依赖 self-touch / self-org /
;;                     self-help-zh。
;; · self-bar         触屏功能栏，Requires 里列了 self-org，故排其后。
;; · self-reading     触屏阅读器（nov），依赖 self-ui-touch。
;; · self-misc        性能面板与状态页，依赖 self-dashboard 与 self-org。

(require 'self-glyph)
(require 'self-session)
(require 'self-keys)
(require 'self-theme)
(require 'self-editing)
(require 'self-completion)
(require 'self-ui-touch)
(require 'self-touch)
(require 'self-help-zh)
(require 'self-org)
(require 'self-roam)
(require 'self-markdown)
(require 'self-dashboard)
(require 'self-bar)
(require 'self-reading)
(require 'self-misc)

(provide 'self-profile-portable)
;;; portable.el ends here
