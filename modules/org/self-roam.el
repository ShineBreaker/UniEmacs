;;; self-roam.el --- org-roam 双链笔记：索引维护、数据库位置与 C-c o r 键位 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable, full, ide
;; Requires: self-lib（路径常量）、self-keys（self/bind、self/declare-binding-group）
;; Packages: org-roam, emacsql
;;
;; 移植自桌面端配置「Org 与知识库」域之「双链笔记与专注写作」小节里属于
;; org-roam 的部分 + Knowledge 小节 C-c o r 前缀下的键位；移动端 self-org
;; 里的 roam 段一并搬到此文件——双链笔记是独立功能域，不该寄生在 Org 基础
;; 模块里（同小节的 Olivetti 在 self-org.el，agenote 知识库在 self-agenote.el）。
;;
;; 笔记文件本体放在 `self:org-roam-directory'（org/roam/），SQLite 数据库
;; 与笔记分离、单独落在 `self:cache-directory'。
;;
;; ─── 为什么 db 不跟笔记一起同步 ────────────────────────────────────
;;
;; 桌面端配置不显式指定 `org-roam-db-location'，org-roam 用默认值
;; `<roam>/org-roam.db'，即数据库随笔记一起同步；本配置统一改指缓存区。
;; 理由：org/ 目录在 Android 上是 Syncthing 同步目录，两端同时打开同一个
;; db 时 SQLite 的文件锁会在跨机场景下互相顶死（库级锁没有分布式仲裁），
;; 表现是查询一直等到 `emacsql-global-timeout' 兜底；而 db 只是纯文本笔记的
;; 派生索引，各端重建一份的代价（一次全量 org-roam-db-sync）远小于锁冲突
;; 的排查代价。
;;
;; ─── 双链自动同步：按平台开不开 ────────────────────────────────────
;;
;; `org-roam-db-autosync-mode' 会在首次调用 Roam 命令时触发后台全量重建，
;; 让新建/改名/删除笔记后的反向链接面板立即可用。代价是每次 Roam 会话都跑
;; 一次全量 db 重建——在 Android 的 FUSE 共享存储上是分钟级阻塞（db 被锁时
;; 每条查询还要各等满超时）。故只在非 Android 平台开启；Android 侧只取其
;; 增量部分（见 `self/org-roam-update-on-save'），全量重建手动 M-x
;; org-roam-db-sync（有进度可预期）。
;;
;; ─── SQLite 后端与版本（版本 pin 本身属 core 的包后端）────────────
;;
;; Emacs 29+ 起 Android 版（含官方 termux APK）已静态链接 sqlite3，
;; `(sqlite-available-p)' 为 t。org-roam 2.3+ 用 emacsql-sqlite-open 自动
;; 选内置后端；org-roam 2.2.x 读 connector 变量，指向 `sqlite'
;;（emacsql-sqlite，走 Termux 的 sqlite3 CLI）。上游从未提供独立的
;; emacsql-sqlite3 包（早先清单里那个名字是笔误），emacsql-sqlite.el 随
;; emacsql 包分发，故包清单只保留 emacsql。

;;; Code:

;; ─── 路径常量 ──────────────────────────────────────────────────────
;;
;; org/roam/ 与 self:cache-directory（cache/）由 core/self-lib.el 定义，
;; 这里只声明不赋值。db 文件路径按上文理由落在缓存区。
(defvar self:org-roam-directory)
(defvar self:cache-directory)

(defconst self:org-roam-db-file
  (expand-file-name "org-roam.db" self:cache-directory)
  "org-roam sqlite 数据库路径（缓存区，各端独立重建，不随笔记同步）。")

(declare-function self/bind "self-keys"
                  (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))
(declare-function org-roam-file-p "org-roam")
(declare-function org-roam-db-update-file "org-roam")
(defvar org-roam-database-connector) ; org-roam 2.2.x 的 connector 变量

;; ─── 保存后增量索引 ────────────────────────────────────────────────
;;
;; 移动端实现（桌面端没有这段，它完全依赖 db-autosync 的全量重建）：
;; 保存后只更新该文件的索引，不触发全量 db 重建。
(defcustom self/org-roam-defer-threshold (* 100 1024)
  "超过此字节数的 org-roam 文件改为延迟合并索引。
索引要全文 parse（227KB 桌面实测 0.4s，真机数倍），放在保存路径会卡输入。"
  :type 'integer
  :group 'self)

(defvar self/org-roam--pending nil
  "保存后待索引的大文件（合并连续保存，避免每次都同步 parse 全文）。")
(defvar self/org-roam--flush-timer nil
  "待索引刷新计时器（去重用；idle 与绝对计时两条路都调 flush）。")

(defun self/org-roam-update-on-save ()
  "保存 org-roam 文件后增量更新索引。
小文件立即更新保持即时性；大文件（超 `self/org-roam-defer-threshold'）
只记入待办，由 `self/org-roam-flush-pending' 择机合并刷新。"
  (when (org-roam-file-p (buffer-file-name))
    (if (< (buffer-size) self/org-roam-defer-threshold)
        (with-demoted-errors "org-roam 索引更新失败: %S"
          (org-roam-db-update-file))
      (add-to-list 'self/org-roam--pending (buffer-file-name))
      (unless (timerp self/org-roam--flush-timer)
        ;; idle 优先（用户停手后才做重活）；绝对计时兜底——Android 功耗
        ;; 管理下 idle timer 疑不触发
        (setq self/org-roam--flush-timer
              (run-with-idle-timer 3 nil #'self/org-roam-flush-pending))
        (run-with-timer 15 nil #'self/org-roam-flush-pending)))))

(defun self/org-roam-flush-pending ()
  "把待索引文件写进 org-roam db（幂等，可被 idle/绝对计时/退出钩子调用）。"
  (when (timerp self/org-roam--flush-timer)
    (cancel-timer self/org-roam--flush-timer)
    (setq self/org-roam--flush-timer nil))
  (let ((files (prog1 (nreverse self/org-roam--pending)
                 (setq self/org-roam--pending nil))))
    (when files
      (with-demoted-errors "org-roam 索引更新失败: %S"
        (dolist (f files)
          (when (file-exists-p f)
            (org-roam-db-update-file f)))))))

;; 退出时兜底刷完，避免待索引的文件留到下次会话
(add-hook 'kill-emacs-hook #'self/org-roam-flush-pending)

;; ─── emacsql：SQLite 后端选择 ─────────────────────────────────────
;;
;; emacsql 包自带 emacsql-sqlite.el（CLI 连接器）与 emacsql-sqlite-builtin.el
;; （内置连接器）；上游从未有过独立的 emacsql-sqlite3 包。Emacs 29+ 的
;; Android 构建静态链接了 sqlite3，org-roam 2.3+ 用 emacsql-sqlite-open
;; 自动选内置后端；org-roam 2.2.x 则读 connector 变量，在下方 :init 里显式
;; 指定 `sqlite'（CLI）。这里只声明延迟加载（安装由 profile 清单负责）。

(use-package emacsql
  :defer t
  :init
  ;; 3s：db 被残留进程锁住时查询快速失败降级，默认 30s 在触屏上无法中断
  (setq emacsql-global-timeout 3))

;; emacsql-sqlite.el 随 emacsql 包分发，org-roam 的 `sqlite' 连接器按需 require
(use-package emacsql-sqlite
  :defer t)

(when self:android-p
  (unless (or (and (fboundp 'sqlite-available-p) (sqlite-available-p))
              (executable-find "sqlite3"))
    (display-warning 'self-roam
                     "SQLite 后端不可用：内置 sqlite 未启用且无 sqlite3 CLI（Termux: pkg install sqlite）")))

;; ─── org-roam ──────────────────────────────────────────────────────

(use-package org-roam
  :defer t
  :commands (org-roam-node-find org-roam-node-insert org-roam-buffer-toggle)
  :init
  (when self:android-p
    ;; org-roam 2.2.x：显式用 `sqlite'（emacsql-sqlite，CLI 连接器）；
    ;; 2.3+ 已移除该变量，改由 emacsql-sqlite-open 自动选内置后端。
    (setq org-roam-database-connector 'sqlite)
    ;; 清残留 sqlite3 子进程：Emacs 被系统杀掉时子进程成孤儿，独占
    ;; org-roam.db 文件锁，新连接打开同一 db 时阻塞直至 emacsql-wait
    ;; 超时（30s）。pkill -f 按 db 完整路径匹配，不影响其它 sqlite3。
    (when (executable-find "pkill")
      (call-process "pkill" nil nil nil "-f" self:org-roam-db-file)))
  :custom
  (org-roam-directory self:org-roam-directory)
  (org-roam-db-location self:org-roam-db-file)
  (org-roam-completion-everywhere nil)
  :config
  ;; 全量自动同步只在非 Android 平台开（理由见 Commentary）
  (unless self:android-p
    (org-roam-db-autosync-mode 1))
  (add-hook 'after-save-hook #'self/org-roam-update-on-save))

;; ─── 键位（C-c o r 网状笔记前缀） ──────────────────────────────────

(self/declare-binding-group "C-c o r" "Org Roam (网状笔记)")
(self/bind "C-c o r f" #'org-roam-node-find "查找或新建 Roam 笔记" "Org 与知识库")
(self/bind "C-c o r i" #'org-roam-node-insert "插入 Roam 链接" "Org 与知识库")
(self/bind "C-c o r l" #'org-roam-buffer-toggle "切换反向链接" "Org 与知识库")

(provide 'self-roam)
;;; self-roam.el ends here
