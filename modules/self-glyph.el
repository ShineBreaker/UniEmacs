;;; self-glyph.el --- 图标资产加载与 NF 字形降级入口 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable
;; Requires: 无
;; Packages: 无
;;
;; 移植自移动端配置（init-basis 的图标/字形部分）。路径常量、启动优化
;; 复位与 modules 后台预编译属基础设施，已在 core，本文件只留字形与
;; 图标资产两件事：
;;
;; · `self/icon-asset'：按钮图标的唯一入口——modifier-bar 徽章走
;;   mod-KEY（.pbm 优先、.png 兜底），其余走 KEY 的 .svg（按当前主题色
;;   重着色后渲染）/ .png（72px 兜底）。资产在 data/icons/，见该目录
;;   的 README。
;; · `self/glyph'：NF 私用区字形的唯一降级入口——GUI 恒按 NF 渲染，
;;   tty 由环境变量 UNI_EMACS_NF_TTY=1 开启校验模式（宿主终端确实带
;;   Nerd Font 时用；真机宽度模型的对照实验走这条）。
;;
;; NF 私用区字形宽度：GUI 按 Maple advance 渲染恰 1 列，宽度表默认记
;; 1 即与渲染一致（置 2 会布局 2 列、字形墨迹占左半，高亮框/间距错位）；
;; 终端把 PUA 记 2 列（tmux/utf8proc），NF 校验模式下同步置 2 保对齐。

;;; Code:

;; ─── 图标资产（唯一入口：tool-bar 按钮、modifier-bar 徽章） ──────────

(defvar self/icon--svg-cache (make-hash-table :test 'equal)
  "SVG 图标 (NAME COLOR HEIGHT) → image 的会话内缓存。
同一色重复安装按钮（主题来回切换）时省一次读盘 + 正则替换 + librsvg 解析。")

(defun self/icon--svg-image (name color height)
  "重着色 data/icons/NAME.svg 的 ColorScheme-Text 为 COLOR 后按 HEIGHT 建图；
无 librsvg 或文件缺失时返回 nil。"
  (let ((key (list name color height)))
    (or (gethash key self/icon--svg-cache)
        (let* ((svg (expand-file-name (concat name ".svg")
                                      (expand-file-name "data/icons"
                                                        user-emacs-directory)))
               (img (and (image-type-available-p 'svg)
                         (file-exists-p svg)
                         (ignore-errors
                          (create-image
                           (replace-regexp-in-string
                            "ColorScheme-Text { color:#[0-9a-fA-F]\\{6\\}"
                            (concat "ColorScheme-Text { color:" color)
                            (with-temp-buffer
                              (insert-file-contents svg)
                              (buffer-string)))
                           'svg t :height height)))))
          (when img (puthash key img self/icon--svg-cache))
          img))))

(defun self/icon-asset (key &optional mod height color)
  "KEY 按钮图标：MOD 非 nil 时查 mod-KEY 徽章（PBM 优先 PNG 兜底），
否则查 KEY 的 SVG（按 COLOR 重着色）/PNG。按序回退，全部缺失返回 nil。"
  (let ((dir (expand-file-name "data/icons" user-emacs-directory)))
    (if mod
        (find-image
         `((:type pbm :file ,(expand-file-name (format "mod-%s.pbm" key) dir))
           (:type png :file ,(expand-file-name (format "mod-%s.png" key) dir))))
      (or (self/icon--svg-image key color height)
          (find-image
           `((:type png :file ,(expand-file-name (format "%s.png" key) dir)
                    :height ,height)))))))

;; ─── NF 字形降级（mode-line 字形、dashboard/确认面板按钮共用入口） ────

(defvar self:glyph-nf-tty
  (equal (getenv "UNI_EMACS_NF_TTY") "1")
  "tty 下宿主终端是否带 Nerd Font 字形（tmux 校验对齐真机宽度模型用，
经环境变量 UNI_EMACS_NF_TTY=1 开启）。")

(defun self/glyph-nf-p ()
  "当前环境是否按 NF 字形渲染（GUI 恒是；tty 由 `self:glyph-nf-tty' 开）。"
  (or (display-graphic-p) self:glyph-nf-tty))

(defun self/glyph (code fallback)
  "有 NF 字形的环境返回 CODE，其余 tty 返回 FALLBACK 文字。
字形降级的唯一入口。"
  (if (self/glyph-nf-p)
      code
    fallback))

(when self:glyph-nf-tty
  (set-char-table-range char-width-table '(#xE000 . #xF8FF) 2))

(provide 'self-glyph)
;;; self-glyph.el ends here
