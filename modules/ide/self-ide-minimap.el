;;; self-ide-minimap.el --- IDE 档右侧代码缩略图（Minimap） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-windowing（side-window 体系同源）
;; Packages: minimap
;;
;; Zed 的 minimap（automatic 模式、活跃编辑器、最大宽度 60px）是编辑区
;; 右缘的缩略预览条。Emacs 侧由 ELPA 的 minimap.el 承担：在帧右缘开
;; 一个专用侧窗，用小号字体重放当前缓冲，跟随滚动并高亮视窗范围。
;;
;; 与 full 档的差分定位：这只是一个常驻视觉条，不参与导航键位；
;; 只在图形界面启用，TTY/daemon 预热帧不会碰到窗口创建路径。
;; 手动开关：M-x self/ide-minimap-toggle。

;;; Code:

(require 'self-lib)

(declare-function minimap-mode "minimap")

(use-package minimap
  :defer t
  :custom
  ;; Zed 侧约 60px；字符列度量下 0.10 帧宽接近，minimum 兜底。
  (minimap-window-location 'right)
  (minimap-width-fraction 0.10)
  (minimap-minimum-width 16)
  ;; 只对内容缓冲开缩略图：树面板、终端、dashboard 这类缓冲不需要。
  (minimap-major-modes '(prog-mode text-mode conf-mode)))

(defun self/ide-minimap-toggle ()
  "开关右侧代码缩略图；等价 Zed 的 minimap show 开关。
交互命令：M-x self/ide-minimap-toggle。"
  (interactive)
  (minimap-mode (if (bound-and-true-p minimap-mode) -1 1)))

(defun self/ide-minimap--startup ()
  "GUI 启动后自动开 minimap（Zed automatic 模式语义）。"
  (when (and (not noninteractive)
             (display-graphic-p))
    (minimap-mode 1)))

(add-hook 'emacs-startup-hook #'self/ide-minimap--startup)

(provide 'self-ide-minimap)
;;; self-ide-minimap.el ends here
