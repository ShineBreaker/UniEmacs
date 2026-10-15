;;; self-misc.el --- 移动端运行时杂项：emacsclient server / 性能取证 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable
;; Requires: self-dashboard, self-org
;; Packages: 无
;;
;; 移植自移动端配置的 misc 段，只留两处归不进既有模块的内容：
;; · Android 的 emacsclient server：从其他 App 打开文件与
;;   org-protocol 链接都经它转交本会话，必须在跑（socket 落在
;;   $TMPDIR/emacs<uid>，emacsclient 同规则查找）。
;; · `self/perf-report'：真机性能取证。启动路径耗时只能真机测
;;   （桌面 I/O 与 CPU 差距大），该命令现场重测关键路径——数字明显
;;   大于桌面（列目录通常 <0.01s）即说明是存储/CPU 瓶颈，否则是代码
;;   路径问题。
;;
;; 原 misc 段的 recentf / savehist / saveplace 已并入 self-ui-touch
;; （与失焦保存同属一条数据保全链），原「目录常量/GC 复位/后台预编译」
;; 属基础设施，归 core。

;;; Code:

(declare-function server-running-p "server")

(when self:android-p
  (require 'server)
  (unless (server-running-p) (server-start)))

;; ─── 真机性能诊断 ───────────────────────────────────────────────────

(declare-function self/dashboard--recent-roam-files "self-dashboard")
(declare-function self/dashboard--note-title "self-dashboard")
(declare-function org-element-parse-buffer "org-element")
(defvar self:org-roam-directory)  ; self-org 定义的常量，只读

(defun self/perf--elapsed (thunk)
  "执行 THUNK，返回 (耗时 . 结果)。"
  (let ((t0 (float-time)))
    (let ((res (funcall thunk)))
      (cons (- (float-time) t0) res))))

(defun self/perf--bench (n thunk)
  "跑 THUNK 共 N 次，返回 (总秒 . 每次毫秒)。"
  (let ((t0 (float-time)))
    (dotimes (_ n) (funcall thunk))
    (let ((el (- (float-time) t0)))
      (cons el (* 1000.0 (/ el n))))))

(defun self/perf-report ()
  "实测关键路径耗时并弹出 buffer（真机排障用）。"
  (interactive)
  (let* ((roam (self/perf--elapsed
                (lambda ()
                  (length (directory-files self:org-roam-directory t
                                           "\\.org\\'")))))
         (dash (self/perf--elapsed
                (lambda () (length (self/dashboard--recent-roam-files 4)))))
         (title (self/perf--elapsed
                 (lambda ()
                   (let ((f (car (self/dashboard--recent-roam-files 1))))
                     (and f (self/dashboard--note-title f))))))
         ;; 交互基准：全部在 pop-to-buffer 之前、调用者原 buffer/窗口上下文里测
         (ml (self/perf--bench 100
                             (lambda () (format-mode-line mode-line-format))))
         (bsize (buffer-size))
         (org-p (derived-mode-p 'org-mode))
         (parse (and org-p (< bsize 300000)
                     (self/perf--bench 1
                                      (lambda () (org-element-parse-buffer)))))
         (parse-line (cond (parse (format "%.3f s（%d 字节）" (car parse) bsize))
                           (org-p (format "跳过（buffer %d 字节，超 300KB）" bsize))
                           (t (format "跳过（非 org buffer，%d 字节）" bsize))))
         (buf (get-buffer-create "*UniEmacs 性能*")))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format "启动总耗时:        %s
已加载特性数:      %d
GC 阈值:           %s
recentf 条目数:    %d
org 笔记目录:      %s

── 现场重测 I/O（缓存可能已热，看量级不看绝对值）──
列笔记目录:        %.3f s（%d 个 .org）
仪表盘首屏数据:    %.3f s（%d 条）
笔记标题读取:      %.3f s（首条 %s）

── 交互基准（纯 CPU，与存储无关）──
mode-line 重绘:    100 次共 %.3f s（每次 %.2f ms）
当前 buffer parse: %s

参考：桌面列目录 <0.01s、mode-line 重绘每次亚毫秒。
I/O 偏大属 FUSE 存储差异；mode-line 每次偏大 → 每按键每滚动都付费；
parse 偏大 → 保存该尺寸的 org 笔记会卡（走 after-save 增量索引）。"
               (emacs-init-time)
               (length features)
               gc-cons-threshold
               (and (bound-and-true-p recentf-mode) (length recentf-list))
               (or self:org-roam-directory "(未定义)")
               (car roam) (cdr roam)
               (car dash) (cdr dash)
               (car title) (or (cdr title) "(无)")
               (car ml) (cdr ml)
               parse-line))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

(provide 'self-misc)
;;; self-misc.el ends here
