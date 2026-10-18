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
  "GUI 帧就绪后自动开 minimap（Zed automatic 模式语义）。
minimap-mode 是全局 mode：只开一次，各帧的缩略图窗口由包内 idle
timer 按当前 buffer major-mode 惰性创建。bound-and-true-p 是第三方
延迟加载包的合法守卫——未加载时不误触 autoload 外的判断，已开启
时不再重复执行 mode 主体（重复会重设其内部 timer）。"
  (when (and (not noninteractive)
             (display-graphic-p)
             (not (bound-and-true-p minimap-mode)))
    (minimap-mode 1)))

(add-hook 'emacs-startup-hook #'self/ide-minimap--startup)
;; daemon 启动时无 GUI 帧，上面的 startup-hook 判定落空；client 帧建立
;; 后再判一次。0s timer 等 server-execute 收尾（帧内 buffer 才就位），
;; 与 self-dashboard--on-frame-make 同一手法。两处上下文都要显式给：
;; with-selected-frame 供 display-graphic-p 读（它只切显示选择），
;; with-current-buffer 供 mode 主体的 minimap-major-modes 判定读——
;; select-frame 不改 current-buffer，timer 环境留下的 *server* 会误判。
(defun self/ide-minimap--schedule ()
  "在新建的 client 帧上排队执行 `self/ide-minimap--startup'（0s timer）。"
  (let ((frame (selected-frame)))
    (run-at-time
     0 nil
     (lambda ()
       (when (frame-live-p frame)
         (with-selected-frame frame
           (with-current-buffer (window-buffer (frame-selected-window frame))
             (self/ide-minimap--startup))))))))

(add-hook 'server-after-make-frame-hook #'self/ide-minimap--schedule)

(provide 'self-ide-minimap)
;;; self-ide-minimap.el ends here
