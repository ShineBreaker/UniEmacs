;;; self-session.el --- 历史持久化、备份隔离、目录隔离、失焦保存与外部变更同步 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; 三档共享的会话底座：让 Emacs 进程内的状态（输入历史、最近文件、光标
;; 位置、书签）落盘到仓库外的状态目录，把备份与自动保存同样赶出源码树，
;; 切换窗口时静默保存改过的本地文件，并在文件被外部改写时自动跟随磁盘。
;; 全部内建包，零第三方依赖。
;;
;; Profiles: minimal, portable, full, ide
;; Requires: self-lib（`self:var-directory' / `self:etc-directory' 决定落盘位置）
;; Packages: 无（recentf / savehist / saveplace 是内建库，use-package 只做配置包装）
;;
;; 移植自桌面端配置「启动与基础设施」域的最小集（pi 版底座 + staging 版
;; 补齐的 auto-revert 段）。刻意留在本文件之外的东西：
;;
;; · 垃圾回收节律与进程级环境（read-process-output-max 等）——描述的是
;;   进程而非会话，属 core/self-lib.el。
;; · gcmh 与 no-littering——第三方包，与「minimal 档不得声明任何第三方包」
;;   冲突，故写在 profiles/full.el 尾部作档内配置。本文件因此用纯 setq
;;   手工完成同样的目录隔离，三档都拿得到，full 档的 no-littering 只是把
;;   同一组目录再声明一遍（两边取值同源，不会打架）。
;; · `server-mode'——属 daemon 启动路径，在 self-daemon.el。
;;
;; 【目录隔离】
;;   备份、自动保存、自定义项（custom.el）统一重定向到状态目录，让仓库目录
;;   保持只读源码身份。原配置依赖 no-littering 的默认值（指向
;;   user-emacs-directory），UniEmacs 的仓库不在 ~/.emacs.d 下，故显式指定。
;;
;; 【输入与文件历史】
;;   savehist 记住输入命令与搜索历史；recentf 记住最近 300 个文件，
;;   300 秒（5 分钟）落盘一次——守护进程被 kill 时 kill-emacs-hook 未必
;;   执行，短周期落盘换一个重启后历史基本不丢；recentf-show-messages 静音
;;   写盘回显，否则每 5 分钟闪一次 "Saving recentf..."。
;;
;; 【失焦自动保存】
;;   切换离开 Emacs 窗口 1 秒后自动静默保存修改过的本地文件缓冲区，不再需要
;;   频繁手动 C-x C-s。为确保安全，机制自动跳过远程文件（TRAMP）、只读
;;   缓冲区以及间接缓冲区（browse 从属 buffer）。
;;
;;   add-function 与 add-hook 的区别：普通 hook 是函数列表，事件发生时依次
;;   调用；而 after-focus-change-function 是「存储单个函数」的变量，若直接
;;   setq 会覆盖掉别的包安装的函数（竞态窗口管理器、终端 frame 等）。用
;;   (add-function :after …) 是在当前值外安全套一层包装，原函数执行完后再跑
;;   我们的保存逻辑。当前挂载链可用 C-h v after-focus-change-function 查看。
;;
;; 【外部变更自动同步（auto-revert）】
;;   VSCode / Zed 把编辑器视为文件系统的实时视图：文件被外部修改（同时用
;;   Zed 打开同一文件、git checkout 切分支、代码生成工具回写）时缓冲区内容
;;   静默跟随磁盘。Emacs 默认不做这件事——缓冲区一直保持旧内容，直到保存
;;   时才抛出「文件已在磁盘上被修改」的冲突警告。
;;
;;   开启 global-auto-revert-mode 后，未本地修改的文件缓冲区会自动 revert
;;   到磁盘版本；已经编辑过的缓冲区不会被覆盖，仍走原有的保存冲突确认，
;;   不会丢失本地改动。auto-revert-verbose 保持默认 nil（静默刷新不回显），
;;   auto-revert-remote-files 保持默认 nil（TRAMP 远程文件豁免，与失焦自动
;;   保存的远程豁免策略一致）。

;;; Code:

(require 'savehist)
(require 'recentf)
(require 'saveplace)

(defvar self:var-directory)
(defvar self:etc-directory)

;; 下面四个变量所属的库（bookmark/tramp/url/eshell）启动时还没加载，
;; 先声明：单独编译不报自由变量警告；运行时 setq 先绑定，库加载时
;; 的 defcustom 不会覆盖已有值。
(defvar bookmark-default-file)
(defvar tramp-persistency-file-name)
(defvar url-history-file)
(defvar eshell-history-file-name)

;; ─── 目录隔离与备份策略 ────────────────────────────────────────────
;; 备份与自动保存统一收进状态目录，不污染源码树；custom.el 收进 etc/。
;; 注意：`custom-file' 是 Emacs 内建变量（自定义项的加载文件），不是本
;; 配置命名空间的符号，按 AGENTS.md §3 规定不改名。

(setq backup-directory-alist
      `((".*" . ,(expand-file-name "backup/" self:var-directory))))
(setq auto-save-file-name-transforms
      `((".*" ,(expand-file-name "auto-save/" self:var-directory) t)))
;; 备份子目录不存在时首次存盘会报错，提前建好。
(dolist (sub '("backup/" "auto-save/" "eshell/"))
  (let ((dir (expand-file-name sub self:var-directory)))
    (unless (file-directory-p dir)
      (make-directory dir t))))
(unless (file-directory-p self:etc-directory)
  (make-directory self:etc-directory t))
(setq custom-file (expand-file-name "custom.el" self:etc-directory))
(when (file-exists-p custom-file)
  (load custom-file t))

;; ─── 输入与文件历史 ──────────────────────────────────────────────
;; savehist 记住 minibuffer 输入与搜索历史；recentf 记住最近 300 个文件，
;; 5 分钟自动存盘一次（守护进程异常退出也不丢），存盘时静默不回显。
;;
;; savehist-file / recentf-save-file 默认落 ~/.emacs.d，收进状态目录——
;; 必须在对应 mode 启动前设置，否则它已按旧路径存过一次。

(setq savehist-file (expand-file-name "history" self:var-directory))
(savehist-mode 1)

(setq recentf-max-saved-items 300
      recentf-autosave-interval 300
      recentf-show-messages nil
      recentf-save-file (expand-file-name "recentf.eld" self:var-directory))
(recentf-mode 1)

;; ─── 光标位置记忆 ────────────────────────────────────────────────
;; 下次打开同一文件时回到上次离开的光标处，同样 5 分钟存盘。
;; save-place-file 默认落 ~/.emacs.d，收进状态目录。

(setq save-place-autosave-interval 300
      save-place-file (expand-file-name "places.eld" self:var-directory))
(save-place-mode 1)

;; ─── 其他内建状态文件 ──────────────────────────────────────────────
;; 这些库启动时不加载，路径默认散落在 ~/.emacs.d（或 XDG 下），一并收
;; 进状态目录。收容清单（变量 → 文件名）：
;;   ((bookmark-default-file . "bookmarks.eld")
;;    (tramp-persistency-file-name . "tramp")
;;    (url-history-file . "url-history.eld")
;;    (eshell-history-file-name . "eshell/history"))
;; 注意 eshell 用的是 eshell-history-file-name（eshell-directory-name
;; 在现版本 Emacs 已不存在）。url-history-file 默认 nil，设了才持久化。
(setq bookmark-default-file
      (expand-file-name "bookmarks.eld" self:var-directory)
      tramp-persistency-file-name
      (expand-file-name "tramp" self:var-directory)
      url-history-file
      (expand-file-name "url-history.eld" self:var-directory)
      eshell-history-file-name
      (expand-file-name "eshell/history" self:var-directory))

;; ─── 失焦自动保存 ────────────────────────────────────────────────

(defconst self:focus-save-idle-delay 1
  "失焦后保存用户文件 buffer 前等待的空闲秒数。")

(defvar self--focus-save-timer nil
  "失焦保存的 pending idle timer。")

(defun self/user-file-buffer-p ()
  "当前 buffer 是否为正常访问的、可保存的本地用户文件 buffer。
判据：指向真实存在的本地文件、已修改、非只读、非间接缓冲区、
且不是远程（TRAMP）文件。`save-some-buffers' 以此为谓词，
因此只读/远程/内部 buffer 天然被跳过。"
  (and buffer-file-name
       buffer-file-truename
       (buffer-modified-p)
       (not buffer-read-only)
       (not (buffer-base-buffer))
       (not (file-remote-p buffer-file-name))))

(defun self/save-user-file-buffers ()
  "保存已修改的本地用户文件 buffer，不触碰内部或远程 buffer。
idle timer 回调：触发时缓冲区可能已被 kill，故清空 timer 槽位。"
  (setq self--focus-save-timer nil)
  (save-some-buffers t #'self/user-file-buffer-p))

(defun self/schedule-focus-save ()
  "根据当前焦点状态安排或取消空闲保存。
焦点变化事件触发。先撤销上一个 pending timer；只要还有任一存活
frame 处于聚焦状态（或焦点状态未知，如终端 frame）就不安排保存，
等下一次失焦事件再说。"
  (when (timerp self--focus-save-timer)
    (cancel-timer self--focus-save-timer)
    (setq self--focus-save-timer nil))
  (unless (seq-some #'frame-focus-state (frame-list))
    (setq self--focus-save-timer
          (run-with-idle-timer self:focus-save-idle-delay nil
                               #'self/save-user-file-buffers))))

;; 焦点变化是单函数变量而非 hook，必须用 add-function :after 追加，
;; 否则会覆盖其它包（如竞态窗口管理器、终端 frame）装上去的函数。
;; 可用 C-h v after-focus-change-function 查看当前挂载链。
(add-function :after after-focus-change-function #'self/schedule-focus-save)

;; ─── 外部变更自动同步 (auto-revert) ──────────────────────────────
;; 见 Commentary「外部变更自动同步」段：未本地修改的缓冲区静默跟随磁盘，
;; 已修改的缓冲区不覆盖，走保存冲突确认。
;;
;; auto-revert-use-notify 安装 inotify 监视，实测事件到达后 handler 只把
;; 缓冲区标记为 stale，真正的 revert 由检查定时器按 auto-revert-interval
;; 驱动——默认 5s 延迟可感知，这里降到 1s（每秒对每个缓冲区一次 stat，
;; 成本可忽略）。auto-revert-avoid-polling 保证文件通知可用时不做额外
;; 轮询。global-auto-revert-non-file-buffers 让 Dired 面板也跟随目录内容
;; 变化自动刷新，对齐 Explorer 文件树的实时更新。
(setq auto-revert-use-notify t
      auto-revert-avoid-polling t
      auto-revert-interval 1
      global-auto-revert-non-file-buffers t)

(global-auto-revert-mode 1)

(provide 'self-session)
;;; self-session.el ends here
