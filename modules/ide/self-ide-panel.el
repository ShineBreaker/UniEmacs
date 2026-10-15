;;; self-ide-panel.el --- IDE 档左侧项目文件树（Treemacs）与面板键位接管 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-keys（`self:binding-spec'、`self/binding--register-which-key'）、
;;           self-terminal、self-keys-desktop（覆写其键位）
;; Packages: treemacs, treemacs-nerd-icons
;;
;; Zed 左侧 dock 的常驻面板是 Project Panel：一棵带文件图标、Git 状态色、
;; 缩进参考线的项目文件树。full 档的同位设施是 self-project 的 Dired 面板
;; ——目录平铺、无树形折叠、无图标，教育意义大于 IDE 体验。ide 档改用
;; Treemacs：
;;
;;   · nerd-icons 主题提供文件图标（self-glyph 的 NF 资产兜底逻辑同样生效，
;;     treemacs-nerd-icons 复用 nerd-icons 字体族）；
;;   · treemacs-git-mode 'deferred：异步打 Git 状态色，不阻塞打开；
;;   · treemacs-filewatch-mode 关闭：本机 inotify 实例上限 128，Zed 已报过
;;     inotify_init 失败，树内目录刷新交给手动 g（treemacs-refresh）；
;;   · treemacs-follow-mode：切换缓冲区时树自动定位当前文件，对齐 Zed 的
;;     Reveal in Project Panel 自动行为；
;;   · treemacs-tag-follow-mode：树内直接展开当前文件的 imenu 符号列表，
;;     近似 Zed 左侧 Outline Panel。
;;
;; 键位接管：self-keys-desktop 已为 full 档绑好 C-b / C-S-e / C-c w f/d/T
;; 指向 Dired 面板；本模块用 `self/ide--rebind' 把它们改绑到 Treemacs 等价物，
;; 并同步改写 `self:binding-spec' 与 Which-key 描述，让帮助页与提示不漂移。
;; `self/bind' 对重复声明直接报错，档内覆写只能绕过它——这是刻意的档私有
;; 覆写手段，仅限本模块使用。
;;
;; Treemacs 自身的打开行为：RET/TAB 打开文件到「最近使用的非树窗口」，
;; side-window 身份使文件自然落进主编辑区，无需额外窗口路由。

;;; Code:

(require 'self-lib)

(declare-function self/open-terminal "self-terminal")
(declare-function treemacs "treemacs")
(declare-function treemacs-find-file "treemacs")
(declare-function treemacs-get-local-window "treemacs")
(declare-function treemacs-add-and-display-current-project "treemacs")
(declare-function treemacs-load-theme "treemacs")

;; ─── Treemacs 配置 ─────────────────────────────────────────────────
;; 这一组 defcustom 都是「先赋值、后由 treemacs 启动时读取」的模式：
;; 对未加载包的变量先挂值、treemacs 首次显示时再消费，:custom 通道
;; （customize-set-variable）正是这个语义，且不会产生 byte-compile
;; 自由变量告警。

(use-package treemacs
  :defer t
  :custom
  (treemacs-width 30)                    ; Zed 侧栏 ≈ 240px，约 30 列
  (treemacs-position 'left)
  (treemacs-git-mode 'deferred)          ; 异步 Git 状态，不卡打开
  (treemacs-filewatch-mode nil)          ; inotify 实例紧张，关
  (treemacs-follow-mode t)               ; 树跟随当前文件
  (treemacs-tag-follow-mode t)           ; 树内展开当前文件符号
  (treemacs-indent-guide-mode t)         ; 对齐 Zed indent guides
  (treemacs-recenter-after-file-follow 'always)
  :config
  ;; nerd-icons 主题须在 treemacs 本体加载后切换。
  (require 'treemacs-nerd-icons)
  (treemacs-load-theme "nerd-icons"))

;; ─── 面板命令 ──────────────────────────────────────────────────────

(defun self/ide-panel-visible-p ()
  "Treemacs 面板窗口当前是否显示。"
  (and (fboundp 'treemacs-get-local-window)
       (treemacs-get-local-window)))

(defun self/ide-panel-toggle ()
  "开关左侧 Treemacs 文件树；等价 Zed 的 C-b。
交互命令：M-x self/ide-panel-toggle，也绑在 C-b。"
  (interactive)
  (treemacs))

(defun self/ide-panel-open ()
  "确保左侧文件树可见但不抢焦点；等价 Zed 打开 Explorer 面板。"
  (interactive)
  (unless (self/ide-panel-visible-p)
    (treemacs)))

(defun self/ide-panel-reveal ()
  "打开文件树并定位当前文件；等价 Zed 的 Reveal in Project Panel。
无文件的缓冲区退化为只开树。treemacs-find-file 对不在工作区内的
文件自行报 user-error，信息本身有解释力，不做额外包装。
交互命令：M-x self/ide-panel-reveal，也绑在 C-S-e / C-c w d。"
  (interactive)
  (if buffer-file-name
      (treemacs-find-file)
    (treemacs)))

;; ─── 双面板总开关（左 Treemacs / 底部槽）─────────────────────────────
;; 结构照搬 self-keys-desktop 的 self/panels-toggle：任一开着则全关、
;; 全关则全开、焦点回主区。full 档的「右 Agent」在 ide 档不是面板——
;; self-ide-slots 的槽位契约把 agent-shell 声明为编辑区内容 tab，
;; 底槽用 window-side=bottom 判定（槽内换过内容也算开着）。

(defun self/ide-panels-toggle ()
  "一键开关双面板布局（左 Treemacs / 底部槽）。
任一面板显示则全部隐藏（缓冲区保留，会话不中断）；全部隐藏则重新打开。
交互命令：M-x self/ide-panels-toggle，也绑在 C-c w T。"
  (interactive)
  (let* ((tree-win (self/ide-panel-visible-p))
         (bottom-win (seq-find
                      (lambda (w)
                        (eq (window-parameter w 'window-side) 'bottom))
                      (window-list (selected-frame))))
         (any-visible (or tree-win bottom-win)))
    (if any-visible
        (progn
          (when tree-win (delete-window tree-win))
          (when bottom-win (delete-window bottom-win)))
      (self/ide-panel-open)
      (self/open-terminal)))
  (when-let* ((main (seq-find
                     (lambda (w) (not (window-parameter w 'window-side)))
                     (window-list (selected-frame)))))
    (select-window main)))

;; ─── 档私有键位覆写 ─────────────────────────────────────────────────

(defun self/ide--rebind (key command description)
  "把全局键 KEY 改绑到 COMMAND 并同步帮助数据源。
`self/bind' 对重复 (key . mode) 声明直接报错，档内覆写只能用本函数：
keymap-global-set 换实际绑定，plist-put 就地改写 `self:binding-spec'
条目，Which-key 描述走 `self/binding--register-which-key' 正常通道
（which-key-allow-multiple-replacements 已开，重注册即覆盖）。"
  (keymap-global-set key command)
  (let ((entry (seq-find
                (lambda (item)
                  (and (equal key (plist-get item :key))
                       (eq (or (plist-get item :mode) 'global) 'global)))
                self:binding-spec)))
    (when entry
      (plist-put entry :command command)
      (plist-put entry :description description)))
  (self/binding--register-which-key key description))

(self/ide--rebind "C-b" #'self/ide-panel-toggle "文件树开关")
(self/ide--rebind "C-S-e" #'self/ide-panel-reveal "文件树定位当前文件")
(self/ide--rebind "C-c w f" #'self/ide-panel-open "文件树面板")
(self/ide--rebind "C-c w d" #'self/ide-panel-reveal "面板定位当前文件")
(self/ide--rebind "C-c w T" #'self/ide-panels-toggle "双面板总开关")

;; ─── 启动自开面板 ──────────────────────────────────────────────────
;; Zed 恢复会话时项目面板常驻。只在其能被有意义地填充时自开：cwd 是一个
;; project 根（UniEmacs 仓库本身就是 git 仓库）。Treemacs 会抢焦点，
;; save-selected-window 把焦点还给主区。

(defun self/ide--startup-panel ()
  "GUI 启动且 cwd 属于一个 project 时自动展开 Treemacs。"
  (when (and (not noninteractive)
             (display-graphic-p)
             (project-current nil))
    (save-selected-window
      (treemacs-add-and-display-current-project))))

(add-hook 'emacs-startup-hook #'self/ide--startup-panel)

(provide 'self-ide-panel)
;;; self-ide-panel.el ends here
