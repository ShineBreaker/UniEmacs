;;; self-apps.el --- 桌面实用应用集成：Agent Shell / DSH / RSS / Telegram / 游戏 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: self-keys
;; Packages: agent-shell, dsh-emacs, newsticker, telega, guix
;;
;; 移植自桌面端配置「实用应用」域。域内每个应用都是同一形状：
;; `use-package' 声明懒加载 → `self/declare-binding-group' 注册前缀
;; → `self/bind' 绑 `C-c a' 下的子键。接入新应用照抄这三连即可。
;;
;; 键位布局（`C-c a' 这一层前缀本身由 self-keys 声明）：
;;
;;   C-c a a  Agent Shell    AI Agent 交互面板，右侧 side-window
;;   C-c a d  DeepSeek       dsh-emacs 会话，复用本机 dsh CLI
;;   C-c a f  Newsticker     树形 RSS 阅读器
;;   C-c a t  Telega         Telegram 客户端（直接绑 prefix-map）
;;   C-c a g  内置游戏       tetris / snake / gomoku / pong
;;   C-c a x  Emacs-Guix     Guix 管理界面与 store 路径美化
;;
;; 关于 Emacs-Guix（guix.el）：只保留「界面集成」这一层——`M-x guix'
;; 的 Magit-like popup 入口、generations / installed-packages 查看、
;; `guix-devel-mode' 与 `guix-prettify-mode'。包安装机制（profile 同步、
;; generation 回滚、`guix package --install' 一类事务）刻意不移植：
;; 那是 core/self-package.el 的 guix 后端职责，两处各写一套包管理必然
;; 出现两个真相源。这里 `guix-installed-user-packages' 只是只读查看
;; 已装清单，不触发任何安装动作。
;;
;; 加载策略：全部 `:defer t'（内置游戏除外，走 autoload）。Agent Shell
;; 与 Telega 是重 IM/AI 客户端，预热会明显拖慢 daemon 启动；Guix 管理
;; 是低频工具，同样不预热。

;;; Code:

(declare-function self/bind
                  (key target description group &rest properties))
(declare-function self/declare-binding-group (key description))

;; ─── Agent Shell（AI Agent 交互面板） ───────────────────────────────
;; display-buffer action 把面板停靠在右侧、占屏幕宽度的 1/4，让出左侧
;; 位置给正在编辑的 buffer——这个动作被 agent-shell 自己每次弹窗时
;; 读取，所以放在 :config 里一次性设好。

(defconst self:agent-side-action
  '(display-buffer-in-side-window
    (side . right) (window-width . 0.25))
  "Agent Shell 面板的 display-buffer action：右侧 side-window，宽度占屏 0.25。")

(use-package agent-shell
  :defer t
  :commands (agent-shell agent-shell-toggle)
  :config
  (setq agent-shell-display-action self:agent-side-action))

(self/declare-binding-group "C-c a a" "Agent Shell (智能终端)")
(self/bind "C-c a a a" #'agent-shell "Agent Shell (智能终端)" "生活应用")
(self/bind "C-c a a t" #'agent-shell-toggle "切换 Agent Shell" "生活应用")

;; ─── DeepSeek Harness（dsh-emacs） ──────────────────────────────────
;; 只声明命令入口，不主动连接：dsh-emacs 复用本机 dsh CLI 与它自己的
;; provider/model 配置，首次打开会话列表时才按需连接或拉起服务。凭据由
;; dsh 自己管，不落到本配置。

(use-package dsh-emacs
  :commands (dsh-emacs dsh-emacs-new-session dsh-emacs-open-web))

(self/declare-binding-group "C-c a d" "DeepSeek Harness")
(self/bind "C-c a d d" #'dsh-emacs "DSH 会话列表" "生活应用")
(self/bind "C-c a d n" #'dsh-emacs-new-session "新建 DSH 会话" "生活应用")
(self/bind "C-c a d w" #'dsh-emacs-open-web "DSH 网页设置" "生活应用")

;; ─── RSS 阅读器（Newsticker） ───────────────────────────────────────
;; 树形视图：左列 feed、右列条目；界面内 g 刷新、n/p 上下条目、
;; SPC 浏览摘要、RET 用 browse-url 打开原文。

(use-package newsticker
  :defer t
  :commands (newsticker-treeview newsticker-get-all-news))

(self/declare-binding-group "C-c a f" "RSS / Newsticker (订阅)")
(self/bind "C-c a f f" #'newsticker-treeview "打开 RSS 阅读器" "生活应用")
(self/bind "C-c a f u" #'newsticker-get-all-news "拉取全部订阅" "生活应用")

;; ─── Telegram（Telega） ─────────────────────────────────────────────
;; Telega 自带一整套 prefix-map，所以不再声明中间分组，直接把 C-c a t
;; 绑到它的 prefix-map 上；只在 :config 里补一个关掉当前 bot 的键。

(use-package telega
  :defer t
  :commands (telega telega-kill)
  :config
  (keymap-set telega-prefix-map "k" #'telega-kill))

(self/bind "C-c a t" telega-prefix-map "Telegram (电报)" "生活应用")

;; ─── 内置游戏（Emacs 自带，autoload 即用） ──────────────────────────

(self/declare-binding-group "C-c a g" "内置游戏")
(self/bind "C-c a g t" #'tetris "俄罗斯方块" "生活应用")
(self/bind "C-c a g s" #'snake "贪吃蛇" "生活应用")
(self/bind "C-c a g m" #'gomoku "五子棋" "生活应用")
(self/bind "C-c a g p" #'pong "乒乓 (Pong)" "生活应用")

;; ─── Emacs-Guix（guix.el）——只做界面集成 ────────────────────────────
;; · 管理界面：`M-x guix` 的 popup 与 list/info 接口
;; · guix-devel-mode：处理 Guix .scm 包定义的 scheme-mode 辅助 minor
;;   mode。刻意手动启用、不挂全局 scheme-mode-hook，免得影响非 Guix
;;   的 scheme 文件。
;; · guix-prettify-mode：把 /gnu/store/<hash>-name 的 hash 段显示成 …，
;;   读 generation 输出与 package 名时短很多。
;; 低频工具，同样 :defer t，不进 daemon 预热白名单。

(use-package guix
  :defer t
  :commands (guix
             guix-packages-by-regexp
             guix-installed-user-packages
             guix-generations
             guix-prettify-mode
             global-guix-prettify-mode
             guix-devel-mode)
  :config
  (global-guix-prettify-mode 1))

(self/declare-binding-group "C-c a x" "Guix 包管理")
(self/bind "C-c a x x" #'guix                         "Guix 管理界面"   "生活应用")
(self/bind "C-c a x s" #'guix-packages-by-regexp      "搜索包"          "生活应用")
(self/bind "C-c a x i" #'guix-installed-user-packages "已安装用户包"    "生活应用")
(self/bind "C-c a x g" #'guix-generations             "Profile 代系"    "生活应用")
(self/bind "C-c a x p" #'guix-prettify-mode           "切换 store 美化" "生活应用")
(self/bind "C-c a x d" #'guix-devel-mode              "切换 devel 模式" "生活应用")

(provide 'self-apps)
;;; self-apps.el ends here
