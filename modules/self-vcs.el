;;; self-vcs.el --- Git 命令包装与状态展示 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: self-keys, self-windowing
;; Packages: magit, magit-diff, diff-hl, forge
;;
;; 移植自桌面端配置「Git 与窗口路由 / Git 命令」一节，以及同节末尾的
;; Magit 状态页文件打开重定向与 C-c g 键位注册。
;;
;; 术语约定（沿用源配置）：「暂存」专指 Stage（`git add' 进暂存区），
;; 「贮藏」专指 Stash（把工作区改动整体打包存起来），两者不共用「暂存」。
;;
;; 命令分层：
;;
;; · 文件与目录级——`self/git-blame-current-line' 之外的部分都在这里：
;;   `self/git-stage-current-file'（暂存当前文件）、`self/git-stage-here'
;;   （按光标上下文暂存整目录或单个文件）、`self/git-discard-current-file'
;;   （丢弃未提交修改，二次确认）。
;; · 仓库级——`self/git-stash-push' / `self/git-stash-pop'。
;; · 底层安全机制——仓库根定位走 Emacs 原生 `vc-call-backend' 的
;;   rev-parse，自动兼容 Git Worktree 与 Submodule 结构，不靠正则猜路径；
;;   直发的 Git 子命令一律经 `self/git--run' 用 `make-process' 异步执行。
;;
;; 为什么自己再包一层 make-process：源配置原先用 `process-file' 同步等待
;; git 返回，大仓库上 stash / restore 会冻结 Emacs 直到命令结束。改异步
;; 后调用方把仓库根 ROOT、参数列表 ARGS 与成功回调 ON-SUCCESS 一起传入，
;; git 在隐藏 buffer 中跑，Emacs 立即返回继续交互；进程结束时 sentinel
;; 判断退出码，成功才触发回调，失败只向 echo area 报 git 输出——异步回调
;; 里抛 `error' 无人接住，只会弹 debugger 打断操作。
;;
;; `self/git--after-success' 是成功后的统一收口：revert 发起命令时的文件
;; buffer（丢弃改动等场景文件内容已变），并在仓库根上刷新 Magit 状态页。
;; 两处都要先做存活检查——异步回调执行时用户可能已经关闭该 buffer 或切走
;; 窗口；`magit-refresh' 不是 autoload 函数，Magit 从未加载过时它不存在，
;; 用 fboundp 守卫跳过（第三方包守卫，不受仓库内免守卫规则限制）。
;;
;; `self/git-stage-here' 是目录感知的整目录暂存。Magit 状态页里按 s 弹出的
;; 补全只列单个文件（目录条目不在候选中），逐个挑深层目录的文件非常繁琐；
;; 该命令反向操作——按光标上下文解析出一个完整路径直接传给
;; `magit-stage-files'：Dired（含左侧面板）光标在目录行上就暂存整个目录、
;; 在文件行上就暂存该文件，普通文件 buffer 则暂存当前文件所在目录。Dired
;; 的 `..' / `.' 行指向上级目录，展开后等于暂存整个仓库，超出「此目录」
;; 意图，故显式拒绝。`magit-stage-files' 收到路径列表后走 Magit 自己的
;; 异步 git 进程并自动刷新状态页，无须再过一遍 `self/git--run'。
;;
;; `self/magit-visit-file' 只改显示位置不改定位逻辑：底部 Magit 状态页中
;; 按回车或双击某行文件时，默认行为会顶掉 Magit 自身（切换到 transient
;; 窗口），这里把结果投放到上方主编辑窗口打开，始终维持「上方写代码、
;; 下方看状态」的清晰分屏格局。定位逻辑与 `magit-diff-visit-file' 一致
;; （diff 中 added/context 行进新版、removed 行进旧版）。

;;; Code:

;; ─── 跨模块符号的就近声明 ──────────────────────────────────────────
;;
;; AGENTS.md §2：跨模块引用必须显式声明，不加 fboundp/boundp 守卫。

;; self/bind：声明并绑定全局 KEY 到 TARGET，同时登记 Which-key 与帮助条目。
(declare-function self/bind "self-keys")
;; self/display-buffer-in-main-window：把 BUFFER 显示到当前 frame 最靠上的
;; 非 side-window 窗口（定义见 self-windowing）。
(declare-function self/display-buffer-in-main-window "self-windowing")

;; 外部命令名常量归 core/self-lib.el 定义（路径常量与 exec-path 也归它管），
;; 这里只声明不赋值，取值从当前 `exec-path' 动态解析。
(defvar self:executable-git)

;; 第三方包符号的就近声明：本模块只 bind 与调用 Magit，并不主动加载它，
;; byte-compile 时看不到定义，不声明会误报「未定义函数」。
(declare-function magit-refresh "magit")        ; 刷新当前 Magit 状态页
(declare-function magit-stage-files "magit")    ; 把 FILES 列表加入 Git 暂存区
(declare-function magit-diff-visit-file--internal "magit-diff") ; 按 DWIM 打开 diff 文件
(declare-function magit-diff--dwim "magit-diff") ; 猜当前光标所在的 diff 范围
(declare-function git-commit-setup-check-buffer "git-commit") ; 开 git-commit-mode
;; dired-get-filename：取光标处的 Dired 条目名（LOCALP 非 nil 时用本地名）。
(declare-function dired-get-filename "dired" (&optional pos localp raise-error))
(declare-function diff-hl-next-hunk "diff-hl")            ; 下一个改动块
(declare-function diff-hl-previous-hunk "diff-hl")        ; 上一个改动块
(declare-function diff-hl-revert-hunk "diff-hl")          ; 还原当前改动块
(declare-function diff-hl-update "diff-hl")               ; 重算当前 buffer 的改动块
(declare-function diff-hl-magit-post-refresh "diff-hl")   ; Magit 刷新后重算
(declare-function turn-on-diff-hl-mode "diff-hl" nil)     ; prog/text 模式的挂钩入口
(defvar diff-hl-mode)                                     ; 当前 buffer 是否启用
(defvar global-diff-hl-mode)                              ; 全局开关
;; 包变量只声明、不赋值。Emacs 的 defvar 语义是「变量已有值就不改」，
;; 所以反过来也不成立：这里一旦带上值（哪怕写成 docstring），等 magit /
;; diff-hl 真正加载时它们自己的 defvar 同样不会把这个值改回去——本文件
;; 加载时这些包还都没加载，变量是 void，于是字符串就成它们的最终值，
;; keymap 会被写成字符串。故用途一律写在行尾注释里。
(defvar magit-diff-visit-prefer-worktree) ; 非 nil 时 magit-diff-visit 优先看工作树版本
(defvar magit-diff-section-map)            ; Magit 状态页 section 的 keymap
(defvar magit-file-section-map)            ; Magit 文件区块的 keymap
(defvar magit-hunk-section-map)            ; Magit hunk 区块的 keymap
(defvar dired-mode-map)                    ; Dired 的 keymap
(defvar auto-revert-verbose)               ; 逐次报告 revert 了哪些 buffer（本文件关掉它）

;; ─── 仓库定位与异步执行 ────────────────────────────────────────────

(defun self/git-buffer-file ()
  "返回当前 buffer 对应的文件，不存在时抛出用户错误。"
  (or (buffer-file-name)
      (user-error "当前缓冲区没有关联文件")))

(defun self/git--ensure-repo (&optional file)
  "确保 FILE 或当前 buffer 位于 Git 仓库中，并返回仓库根目录。
仓库根定位走 `vc-call-backend' 的 rev-parse，worktree/submodule 安全。
不能改用 `vc-backend' 做类型判定：它只回答「对象是否被注册」，对目录恒 nil，
而入参常是 `default-directory'。非 Git 目录拿到 nil 后统一报错。"
  (or (when-let* ((target (or file (buffer-file-name) default-directory)))
        (vc-call-backend 'Git 'root target))
      (user-error "当前不在 Git 仓库中")))

(defun self/git--run (root args on-success)
  "在仓库 ROOT 中异步执行 Git ARGS，成功（退出码 0）后调用 ON-SUCCESS。
ON-SUCCESS 不接收参数。命令取 `self:executable-git'，由当前 `exec-path'
在调用时解析。失败时只向 echo area 报 git 输出，不触发回调。"
  (let ((buffer (generate-new-buffer " *self-git*"))
        (default-directory root))
    (make-process
     :name (format "git-%s" (car args))
     :buffer buffer
     :command (cons self:executable-git args)
     :sentinel
     (lambda (proc _event)
       (let ((output (if (buffer-live-p (process-buffer proc))
                         (string-trim
                          (with-current-buffer (process-buffer proc)
                            (buffer-string)))
                       "")))
         (when (buffer-live-p (process-buffer proc))
           (kill-buffer (process-buffer proc)))
         (if (and (eq (process-status proc) 'exit)
                  (= (process-exit-status proc) 0))
             (funcall on-success)
           (message "Git 命令失败(%s): %s"
                    (string-join args " ")
                    (if (string-empty-p output) "进程异常退出" output))))))))

(defun self/git--after-success (&optional buffer root)
  "Git 异步命令成功后的统一刷新。
BUFFER 是命令发起时的文件 buffer：丢弃改动后文件内容已变，存活时 revert；
ROOT 是仓库根：在其下刷新 Magit 状态页，底部状态页若在显示即随之更新。"
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when (and buffer-file-name (file-exists-p buffer-file-name))
        (revert-buffer t t t))))
  (when root
    (let ((default-directory root))
      (when (fboundp 'magit-refresh)
        (magit-refresh)))))

;; ─── 文件与目录级操作 ──────────────────────────────────────────────

(defun self/git-stage-here ()
  "按光标上下文暂存目录或文件（等价 git add，目录递归生效）。
Dired 目录行暂存整目录、文件行暂存该文件；文件 buffer 暂存所在目录；
Dired 的 `..'/`.' 行显式拒绝（等价暂存整个仓库，超出意图）。"
  (interactive)
  (let ((target (cond ((derived-mode-p 'dired-mode)
                       (let ((name (dired-get-filename nil t)))
                         (cond ((not name)
                                (user-error "光标处没有文件条目"))
                               ((member (file-name-nondirectory name) '("." ".."))
                                (user-error "光标在 . 或 .. 行，请先进入目标目录"))
                               (t name))))
                      (t (file-name-directory (self/git-buffer-file))))))
    (self/git--ensure-repo target)
    (magit-stage-files (list (expand-file-name target)))
    (message "已暂存: %s" (directory-file-name target))))

(defun self/git-stage-current-file ()
  "Stage 当前文件（异步，完成后刷新 Magit 状态页）。
交互命令，绑在 `C-c g S'。"
  (interactive)
  (let ((file (self/git-buffer-file))
        (root (self/git--ensure-repo (buffer-file-name))))
    (self/git--run
     root (list "add" "--" file)
     (lambda ()
       (self/git--after-success nil root)
       (message "已 stage: %s" (file-name-nondirectory file))))))

(defun self/git-discard-current-file ()
  "丢弃当前文件所有未提交修改（带确认，异步执行后 revert）。
交互命令，绑在 `C-c g D'。"
  (interactive)
  (let* ((file (self/git-buffer-file))
         (root (self/git--ensure-repo file))
         (buffer (current-buffer)))
    (when (y-or-n-p (format "丢弃 %s 的所有未提交修改？"
                            (file-name-nondirectory file)))
      (self/git--run
       root (list "restore" "--source=HEAD" "--staged" "--worktree" "--" file)
       (lambda ()
         (self/git--after-success buffer root)
         (message "已丢弃: %s" (file-name-nondirectory file)))))))

;; ─── 仓库级操作 ────────────────────────────────────────────────────

(defun self/git-stash-push ()
  "贮藏当前仓库中的修改（异步）。
交互命令，绑在 `C-c g #'。"
  (interactive)
  (let ((root (self/git--ensure-repo)))
    (self/git--run
     root (list "stash" "push" "-m"
                (format-time-string "stash-%Y%m%d-%H%M%S"))
     (lambda ()
       (self/git--after-success nil root)
       (message "已创建贮藏")))))

(defun self/git-stash-pop ()
  "恢复最近一次贮藏（带确认，异步）。
交互命令，绑在 `C-c g @'。"
  (interactive)
  (let ((root (self/git--ensure-repo)))
    (when (y-or-n-p "恢复最近一次贮藏？")
      (self/git--run
       root (list "stash" "pop")
       (lambda ()
         (self/git--after-success nil root)
         (message "已恢复最近一次贮藏"))))))

(defun self/git-commit-setup-buffer-maybe ()
  "当前 buffer 是 Git 提交消息文件时加载并启用 `git-commit-mode'。
注册点在本定义末尾的 `find-file-hook'；弹出位置由 self-windowing 决定。"
  (when (and buffer-file-name
             (member (file-name-nondirectory buffer-file-name)
                     '("COMMIT_EDITMSG" "MERGE_MSG" "TAG_EDITMSG"
                       "NOTES_EDITMSG" "PULLREQ_EDITMSG")))
    (require 'git-commit)
    (git-commit-setup-check-buffer)))

;; 提交消息 buffer 通常由 git/magit 用 find-file 打开，落在哪、怎么走
;; 由 self-windowing 的 display-buffer 路由表决定；这里只负责让内容进入
;; git-commit-mode。挂在定义之后，省掉一次符号解析。
(add-hook 'find-file-hook #'self/git-commit-setup-buffer-maybe)

;; ─── Magit 状态页内的文件打开重定向 ────────────────────────────────

(defun self/magit-visit-file ()
  "在主编辑窗口打开光标处文件的对应版本。
定位逻辑与 `magit-diff-visit-file' 一致（diff 中 added/context 行进
新版、removed 行进旧版），仅显示目标不同。"
  (interactive)
  (magit-diff-visit-file--internal
   (and magit-diff-visit-prefer-worktree
        (memq (magit-diff--dwim) '(staged unstaged)))
   #'self/display-buffer-in-main-window))

(defun self/magit-mouse-visit-file (event)
  "双击打开光标处文件到主编辑窗口。
交互命令，绑在 Magit 文件/hunk 区块的 `[double-mouse-1]' 上。"
  (interactive "e")
  (mouse-set-point event)
  (self/magit-visit-file))

;; 状态页默认的回车键是 `magit-visit-thing'（会切走 transient 窗口），
;; remap 到本模块的版本；双击则先置 `ignore' 拦掉默认的 visit，
;; 再自行绑定带 mouse-set-point 的版本。
(with-eval-after-load 'magit-diff
  (define-key magit-diff-section-map [remap magit-visit-thing]
              #'self/magit-visit-file)
  (dolist (map (list magit-file-section-map magit-hunk-section-map))
    (define-key map [double-down-mouse-1] #'ignore)
    (define-key map [double-mouse-1] #'self/magit-mouse-visit-file)))

;; ─── 键位与自动化注册 ──────────────────────────────────────────────

;; 核心操作。Which-key 中文提示统一登记在 data/which-key-zh.el。
(self/bind "C-c g s" #'magit-status "版本控制状态" "Git")
(self/bind "C-c g b" #'magit-blame-addition "当前文件追责" "Git")
(self/bind "C-c g l" #'magit-log-buffer-file "当前文件日志" "Git")
(self/bind "C-c g d" #'magit-diff-buffer-file "当前文件差异" "Git")
(self/bind "C-c g S" #'self/git-stage-current-file "暂存当前文件" "Git")
(self/bind "C-c g a" #'self/git-stage-here "暂存当前目录/条目" "Git")
(self/bind "C-c g D" #'self/git-discard-current-file "丢弃当前文件修改" "Git")
(self/bind "C-c g #" #'self/git-stash-push "保存贮藏" "Git")
(self/bind "C-c g @" #'self/git-stash-pop "恢复贮藏" "Git")

;; Dired 直达键：Dired 自身不占用 C-c 前缀，把 C-c s 绑到 dired-mode-map 上
;; （与状态页内 s 暂存同键位语义）。左侧面板的私有键表复制自 dired-mode-map，
;; 自动继承该键。
(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "C-c s") #'self/git-stage-here))

;; Emacs 31 的 VC 扩展。
(self/bind "C-c g y" #'vc-cherry-pick "拣选提交 (Cherry-pick)" "Git")
(self/bind "C-c g X" #'vc-delete-revision "删除修订" "Git")
(self/bind "C-c g o" #'vc-root-diff-outgoing "预览待推送提交" "Git")
(self/bind "C-c g O" #'vc-root-diff-outgoing-and-edited "本地全部工作" "Git")

;; diff-hl 行内导航：提前显式补充 autoload，防止延迟加载前按键报错。
(dolist (cmd '(diff-hl-next-hunk diff-hl-previous-hunk diff-hl-revert-hunk))
  (autoload cmd "diff-hl"))
(self/bind "C-c g n" #'diff-hl-next-hunk "下一个改动块" "Git")
(self/bind "C-c g p" #'diff-hl-previous-hunk "上一个改动块" "Git")
(self/bind "C-c g R" #'diff-hl-revert-hunk "还原当前改动块" "Git")

;; ─── 版本差异高亮（diff-hl）─────────────────────────────────────
;;
;; 在编辑区边缘实时呈现当前文件的 Git 增删改状态。
;; Fringe 与 Margin 分流由上游内置机制处理，切勿开启全局
;; `diff-hl-margin-mode'。每个缓冲区用独立的空闲定时器刷新，并在
;; `magit-post-refresh-hook' 挂载更新，确保暂存或提交后即时同步标记。
;;
;; 归本模块而非 self-editing：diff-hl 的数据源只有 Git，放进编辑模块
;; 会让「谁负责版本差异」这件事在两个文件里各答一半。

(defun self/diff-hl-schedule-update ()
  "为当前 buffer 排一个独立的 diff-hl 刷新 timer，不用全局 diff-hl-timer。"
  (when (bound-and-true-p diff-hl-mode)
    (let ((buf (current-buffer)))
      (run-with-idle-timer
       0 nil
       (lambda ()
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (bound-and-true-p diff-hl-mode)
               (diff-hl-update)))))))))

(use-package diff-hl
  :defer t
  :hook ((prog-mode . turn-on-diff-hl-mode)
         (text-mode . turn-on-diff-hl-mode))
  :config
  ;; 刷新函数定义在 use-package 之外（见上）：放在 :config 里会让它在包
  ;; 懒加载完成前不存在，hook 一挂上就指向未定义符号。
  (add-hook 'diff-hl-mode-on-hook #'self/diff-hl-schedule-update)
  (add-hook 'after-revert-hook #'self/diff-hl-schedule-update)
  (with-eval-after-load 'magit-mode
    (add-hook 'magit-post-refresh-hook #'diff-hl-magit-post-refresh))
  (global-diff-hl-mode 1))

;; 分支切换后静默刷新文件（不打扰正在编辑的人）。
(setq auto-revert-verbose nil)
(vc-auto-revert-mode 1)

;; Forge 随 Magit 一同加载，在状态页提供 Issue 与 PR 关联。
;; 装包由 profile manifest 负责，此处只声明加载时机。
(use-package forge
  :demand t
  :after magit)

(provide 'self-vcs)
;;; self-vcs.el ends here
