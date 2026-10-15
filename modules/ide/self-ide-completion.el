;;; self-ide-completion.el --- IDE 档补全栈：命令面板、行内补全与文档浮窗 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-completion（被本档接管 completion-preview）、self-keys
;; Packages: vertico, orderless, marginalia, consult, embark, embark-consult,
;;           corfu, cape, kind-icon, eldoc-box
;;
;; Zed 的两套补全界面：
;;
;;   · 命令面板 / 文件查找：底部弹出的窄条列表 + 模糊匹配（Ctrl-P、
;;     Ctrl-Shift-P）。对应 minibuffer 栈：vertico 提供竖排候选，
;;     orderless 给无序子串匹配，marginalia 加类型注解列，consult 把
;;     xref / 搜索结果接到预览式界面。
;;   · 行内补全：光标下方的弹出菜单，带符号类型图标与文档侧窗。对应
;;     corfu（弹窗）+ kind-icon（类型图标）+ corfu-popupinfo（文档窗），
;;     cape-file 补路径片段。
;;
;; self-completion 已在 Android 平台分支里装过同款栈（那里是触屏点选
;; 需求）；本模块是桌面的 ide 档自选安装，两份 use-package 因平台/档位
;; 互斥不会同时生效，故允许并存而不抽公共模块——抽了反而要在调用处加
;; 守卫，违背「档位差异只走 manifest」的约定。
;;
;; 与 full 档行为的差分：
;;   · completion-preview-mode 的行内幽灵文本在本档关闭——Zed 没有 ghost
;;     text，corfu 弹窗已覆盖同一触发场景，双 UI 只会打架；
;;   · completion-styles 从 flex 换 orderless：命令面板里多词乱序匹配
;;     更接近 Zed 的 fuzzy 体验；
;;   · embark-act 挂 C-;（C-. 留给了 bind-key 常见约定之外的空隙）。

;;; Code:

(require 'self-lib)

(declare-function global-completion-preview-mode "completion-preview")
(declare-function vertico-mode "vertico")
(declare-function vertico-mouse-mode "vertico")
(declare-function marginalia-mode "marginalia")
(declare-function consult-xref "consult")
(declare-function global-corfu-mode "corfu")
(declare-function corfu-popupinfo-mode "corfu-popupinfo")
(declare-function kind-icon-margin-formatter "kind-icon")
(declare-function cape-file "cape")
(declare-function eldoc-box-hover-at-point-mode "eldoc-box")

;; ─── 命令面板栈（minibuffer）────────────────────────────────────────

;; orderless：无序子串匹配，「magit blame」可命中 magit-blame。
;; file 类别留 partial-completion，~/P/E 这类路径缩写仍能用。
(use-package orderless
  :defer t
  :init
  (setq completion-styles '(orderless basic)
        completion-category-overrides
        '((file (styles partial-completion)))))

(use-package vertico
  :init
  (vertico-mode)
  ;; 桌面保留鼠标点选候选的能力（Zed 面板可点）。
  (vertico-mouse-mode))

(use-package marginalia
  :init (marginalia-mode))

;; consult：xref 定义/引用列表换预览式界面，对齐 Zed 的引用面板。
(use-package consult
  :defer t
  :custom
  (xref-show-xrefs-function #'consult-xref)
  (xref-show-definitions-function #'consult-xref))

;; embark：候选上的「右键菜单」——对文件条目做 copy/rename/delete 等动作。
(use-package embark
  :defer t
  :bind (("C-;" . embark-act)))

(use-package embark-consult
  :after (embark consult))

;; ─── 行内补全栈 ────────────────────────────────────────────────────

;; Zed 无 ghost text：幽灵文本与 corfu 弹窗在同一光标处竞争显示，关前者。
;; global-completion-preview-mode 由 self-completion :demand 加载，
;; 此时必然已 bound，可直接关闭。
(global-completion-preview-mode -1)

(use-package corfu
  :init (global-corfu-mode)
  :custom
  (corfu-auto t)            ; Zed 式自动弹补全
  (corfu-cycle t)
  (corfu-preselect 'prompt)) ; 不预选首项，RET 语义留给用户

;; corfu-popupinfo：补全项的文档侧窗（Zed completion menu 右侧 doc pane）。
;; 扩展文件随 corfu 包分发，Guix 包一并安装；缺库时静默降级为无文档窗。
(when (locate-library "corfu-popupinfo")
  (require 'corfu-popupinfo)
  (corfu-popupinfo-mode 1))

(use-package kind-icon
  :after corfu
  :config
  ;; Maple Mono NF CN 自带 NF 字形，kind-icon 的类型图标直接可用。
  (add-to-list 'corfu-margin-formatters #'kind-icon-margin-formatter))

(use-package cape
  :after corfu
  :config
  (add-to-list 'completion-at-point-functions #'cape-file))

;; ─── 文档浮窗 ──────────────────────────────────────────────────────
;; Zed 的 hover/signature 浮窗。Eglot 把 signature/documentation 都喂给
;; eldoc，eldoc-box 将其渲染为 posframe 浮窗而不是挤进 echo area
;; （echo area 已被 minibuffer-line 状态条占用）。

(use-package eldoc-box
  :defer t
  :hook ((prog-mode . eldoc-box-hover-at-point-mode)))

(provide 'self-ide-completion)
;;; self-ide-completion.el ends here
