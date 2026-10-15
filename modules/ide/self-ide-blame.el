;;; self-ide-blame.el --- IDE 档行内 Git blame：行尾作者/时间/提交说明 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-vcs（仓库定位语义同源）
;; Packages: 无（vc 判定 + 异步 git blame CLI）
;;
;; Zed 的 inline_blame：光标停在某行约两秒后，行尾浮现
;; 「作者 · 相对时间 · 提交摘要」。Git 没有按行查询的常驻通道，实现
;; 只能是「光标停稳 → 对当前行跑一次 git blame -L n,n --porcelain
;; → 解析 → overlay 画在行尾」。链条：
;;
;;   post-command-hook（仅一次行号整数比较，零 I/O，合规的热路径）
;;     → idle timer 防抖（默认 1.2s，Zed 是 2s）
;;     → make-process 异步起 git blame（交互绝不同步等 CLI 的硬约束）
;;     → sentinel 解析 porcelain 输出、在目标行尾放 overlay
;;
;; 失效路径：编辑（after-change 让行号失真）、光标换行、模式关闭、
;; buffer 杀死，各自负责清 overlay 与取消 timer/进程。
;; 不在 git 仓库 / 未跟踪 / 空行的查询静默落空，与 Zed 同行为。
;;
;; 开关：`self/ide-blame-mode' 是 buffer-local minor mode，由
;; `self/ide-blame-maybe-enable' 在打开文件时自动判定启用；
;; 手动 M-x self/ide-blame-mode 可关可开。

;;; Code:

(require 'self-lib)

;; ─── 状态 ──────────────────────────────────────────────────────────

(defcustom self:ide-blame-delay 1.2
  "光标停稳多少秒后发起当前行的 blame 查询；Zed 为 2s。"
  :type 'number
  :group 'self-ide)

(defvar-local self/ide-blame-mode nil)

(defvar-local self--ide-blame-timer nil
  "当前缓冲区待发的 blame 查询 timer。")

(defvar-local self--ide-blame-process nil
  "当前缓冲区在跑的 git blame 进程；同一缓冲同时只跑一条。")

(defvar-local self--ide-blame-overlay nil
  "当前显示的 blame overlay。")

(defvar-local self--ide-blame-line nil
  "最近一次发起过查询的行号；同号不重复查。")

(defvar-local self--ide-blame-root nil
  "缓存的 Git 仓库根；nil 表示本缓冲不在 Git 管理下。")

;; ─── 显示 ──────────────────────────────────────────────────────────

(defun self/ide-blame--relative-time (timestamp)
  "把 UNIX 时间戳格式化成「N 分钟/小时/天/个月/年前」相对时间。"
  (let* ((seconds (max 0 (- (float-time) timestamp)))
         (minutes (/ seconds 60))
         (hours (/ seconds 3600))
         (days (/ seconds 86400)))
    (cond
     ((< minutes 2) "刚刚")
     ((< hours 1) (format "%d 分钟前" (truncate minutes)))
     ((< days 1) (format "%d 小时前" (truncate hours)))
     ((< days 30) (format "%d 天前" (truncate days)))
     ((< days 365) (format "%d 个月前" (truncate (/ days 30))))
     (t (format "%d 年前" (truncate (/ days 365)))))))

(defun self/ide-blame--clear ()
  "清掉当前缓冲区的 blame overlay（进程与 timer 由调用方另行处理）。"
  (when self--ide-blame-overlay
    (delete-overlay self--ide-blame-overlay)
    (setq self--ide-blame-overlay nil)))

(defun self/ide-blame--show (line text)
  "在第 LINE 行行尾渲染 TEXT（截断与 face 在这里统一处理）。"
  (self/ide-blame--clear)
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line))
    (let ((ov (make-overlay (line-end-position) (line-end-position)))
          (rendered (truncate-string-to-width text 72 nil nil "…")))
      (overlay-put
       ov 'after-string
       (propertize (concat "  " rendered)
                   'face '(:inherit shadow :slant italic :height 0.9)))
      (setq self--ide-blame-overlay ov))))

;; ─── porcelain 解析 ────────────────────────────────────────────────

(defun self/ide-blame--field (name)
  "在当前 porcelain 输出缓冲中搜 ^NAME 字段，返回其值字符串或 nil。"
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward (concat "^" name " \\(.*\\)$") nil t)
      (match-string 1))))

(defun self/ide-blame--format (output-buffer)
  "把 OUTPUT-BUFFER 中的 porcelain 输出解析成显示文本；
未提交的行（sha 全零 / Not Committed Yet）返回「你 · 未提交」。"
  (with-current-buffer output-buffer
    (let ((sha (save-excursion
                 (goto-char (point-min))
                 (and (looking-at "\\([0-9a-f]+\\) ")
                      (match-string 1))))
          (author (self/ide-blame--field "author"))
          (time (self/ide-blame--field "author-time"))
          (summary (self/ide-blame--field "summary")))
      (if (or (null author)
              (null sha)
              (string-prefix-p "0000000" sha)
              (equal author "Not Committed Yet"))
          "你 · 未提交"
        (format "%s · %s · %s"
                author
                (self/ide-blame--relative-time
                 (string-to-number (or time "0")))
                (or summary ""))))))

;; ─── 异步查询 ──────────────────────────────────────────────────────

(defun self/ide-blame--sentinel (source-buffer line output-buffer
                                               process _event)
  "blame 进程收尾：成功且源缓冲仍在被查询行时渲染 overlay。
异步回调是唯一需要存活检查的地方：进程返回时源缓冲可能已死、
光标可能已换行、模式可能已关，三者任一不满足就静默丢弃结果。"
  (when (and (eq (process-status process) 'exit)
             (eq (process-exit-status process) 0)
             (buffer-live-p source-buffer))
    (with-current-buffer source-buffer
      (when (and self/ide-blame-mode
                 (eq self--ide-blame-line line))
        (let ((text (self/ide-blame--format output-buffer)))
          (when (> (length text) 0)
            (self/ide-blame--show line text))))))
  (when (buffer-live-p output-buffer)
    (kill-buffer output-buffer))
  (when (buffer-live-p source-buffer)
    (with-current-buffer source-buffer
      (setq self--ide-blame-process nil))))

(defun self/ide-blame--query (line)
  "对当前缓冲第 LINE 行异步发起 git blame。"
  (let* ((source (current-buffer))
         (root self--ide-blame-root)
         (relative (file-relative-name buffer-file-name root))
         (output (generate-new-buffer " *ide-blame*")))
    (setq self--ide-blame-process
          (make-process
           :name "self-ide-blame"
           :buffer output
           :command (list "git" "-C" root "blame" "--porcelain"
                          "-L" (format "%d,%d" line line)
                          "--" relative)
           :noquery t
           :sentinel
           (lambda (proc event)
             (self/ide-blame--sentinel source line output proc event))))))

(defun self/ide-blame--idle (line buffer)
  "idle 到点后的查询入口；BUFFER 可能已被切走或杀死，这里先验证。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and self/ide-blame-mode
                 buffer-file-name
                 (eq line (line-number-at-pos))
                 (null self--ide-blame-process))
        ;; 行号在此刻登记：进程跑完前再触发同行查询会被这里挡掉。
        (setq self--ide-blame-line line)
        (self/ide-blame--query line)))))

(defun self/ide-blame--post-command ()
  "光标换行则清旧 overlay 并重排 idle 查询；同行停留不做事。
post-command 每键必跑，本函数只做一次整数比较与 timer 调度，符合
热路径零 I/O 约束。"
  (let ((line (line-number-at-pos)))
    (unless (eq line self--ide-blame-line)
      (self/ide-blame--clear)
      (setq self--ide-blame-line nil)
      (when self--ide-blame-timer
        (cancel-timer self--ide-blame-timer))
      (setq self--ide-blame-timer
            (run-with-idle-timer self:ide-blame-delay nil
                                 #'self/ide-blame--idle
                                 line (current-buffer))))))

(defun self/ide-blame--after-change (&rest _)
  "任何编辑让行号失真：清 overlay 并作废已查行号。"
  (self/ide-blame--clear)
  (setq self--ide-blame-line nil))

;; ─── minor mode ────────────────────────────────────────────────────

(defun self/ide-blame--teardown ()
  "关闭 blame 的全部现场：timer、进程、overlay、hook。"
  (when self--ide-blame-timer
    (cancel-timer self--ide-blame-timer)
    (setq self--ide-blame-timer nil))
  (when (and self--ide-blame-process
             (process-live-p self--ide-blame-process))
    (delete-process self--ide-blame-process))
  (setq self--ide-blame-process nil)
  (self/ide-blame--clear)
  (remove-hook 'post-command-hook #'self/ide-blame--post-command t)
  (remove-hook 'after-change-functions #'self/ide-blame--after-change t)
  (remove-hook 'kill-buffer-hook #'self/ide-blame--teardown t))

;;;###autoload
(define-minor-mode self/ide-blame-mode
  "行内 Git blame：光标停稳时在行尾显示作者、相对时间与提交摘要。
只在 Git 仓库内的文件缓冲启用（见 `self/ide-blame-maybe-enable'）。"
  :lighter " Blame"
  (if self/ide-blame-mode
      (progn
        (add-hook 'post-command-hook #'self/ide-blame--post-command nil t)
        (add-hook 'after-change-functions #'self/ide-blame--after-change nil t)
        (add-hook 'kill-buffer-hook #'self/ide-blame--teardown nil t))
    (self/ide-blame--teardown)))

(defun self/ide-blame-maybe-enable ()
  "文件在 Git 仓库内则开启 `self/ide-blame-mode'；挂 find-file-hook。
仓库根判定沿用 self-vcs 的 vc-call-backend 通道并把结果缓存进
`self--ide-blame-root'，后续查询零重复 I/O。"
  (when buffer-file-name
    (let ((root (vc-call-backend 'Git 'root buffer-file-name)))
      (when root
        (setq self--ide-blame-root root)
        (self/ide-blame-mode 1)))))

(add-hook 'find-file-hook #'self/ide-blame-maybe-enable)

(provide 'self-ide-blame)
;;; self-ide-blame.el ends here
