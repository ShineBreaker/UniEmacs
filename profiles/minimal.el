;;; minimal.el --- minimal 档：纯内建底座 -*- lexical-binding: t; -*-

;;; Commentary:
;; 三档中最轻的一档：只要 Emacs 内建功能，不声明任何第三方包，对标
;; nano 与未配置 nvim 的功能水平与可调试性。跑在任何能启动 Emacs 的
;; 地方，是冒烟测试与故障排查的基准。
;;
;; Profiles: minimal
;; Requires: self-lib self-package self-session self-keys self-completion
;;           self-editing
;;
;; 本档只有四个模块，且四个都是纯内建实现：
;;   self-session    目录隔离、历史持久化、失焦保存、auto-revert
;;   self-keys       键位机制层（self/bind 声明器 + which-key / winner，
;;                   两者在 Emacs 30+ 均为内建 lisp/ 库，见该文件注释）
;;   self-completion minibuffer 模糊匹配、行内幽灵文本、isearch IDE 化
;;   self-editing    缩进排版、软换行、片段插入、C-c e 变换
;;
;; 不含主题模块：本档刻意停在 Emacs 内建外观上——连主题都是第三方包，
;; 想要「最小可调试」就该能一眼看出问题出在配置还是出在环境。
;;
;; 依赖取向：本档刻意不含外部命令（LSP / 格式化器 / 终端 / VCS 全无），
;; 它要验证的是「配置自身的加载链与内建能力」，不是编程环境。

;;; Code:

;; minimal 档不得声明任何第三方包：保持空表。
(setq self:profile-packages '())

(self/package-ensure)

;; ─── 模块 require 序列（即本档的依赖契约，顺序不可随意调换）────────
;;
;; · self-session  最先：它建立 self:var-directory / self:etc-directory
;;   并据此设置 custom-file 与备份/自动保存落盘位置，其余模块都依赖这些。
;; · self-keys     机制层底座，必须早于任何用 self/bind 的模块。
;; · self-editing  依赖 self-keys（键位声明）与 self-lib 的路径常量。
;; · self-completion 无仓库内依赖，放最后即可。

(require 'self-session)
(require 'self-keys)
(require 'self-editing)
(require 'self-completion)

(provide 'self-profile-minimal)
;;; minimal.el ends here
