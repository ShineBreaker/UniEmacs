;;; self-daemon.el --- daemon 预热与 client 帧启动噪声降噪 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: standard, ide
;; Requires: 无
;; Packages: 无
;;
;; 移植自桌面端配置「Guix 集成与 daemon 预热」一节，连同桌面「启动与基础
;; 设施」域里的 server-mode 开启段，只留三件都只影响进程启动路径的事：
;;
;; 1. `self/daemon-warmup'：后台守护进程静默启动时顺手把常用交互库加载
;;    掉。它是「交互延迟 > 长时运行稳定性 > 启动时间」这条优先级排序的
;;    直接产物——daemon 多花一两秒用户完全无感，而 emacsclient 首次
;;    打开才现加载 Magit / Org-agenda 的卡顿是有感的。重型后台子进程
;;    （LSP、外部聊天客户端）仍保持延迟按需加载，不进白名单。
;; 2. `self--warnings-benign-only-p'：daemon 下 display-warning 会把
;;    启动期的警告挂到 after-make-frame-functions 上、压到第一个 client
;;    frame 才弹（warnings.el 的 `(daemonp)' 分支），于是 Guix 的
;;    site-start.el 里那条 "Missing ‘lexical-binding’ cookie" 噪声每次
;;    重启都会从窗口底部冒出来变成 * Warnings *。该文件在 site-start
;;    阶段加载（早于 early-init.el），配置层拦不住「加载」，只能拦
;;    「展示」。
;;
;; 接入点：`self/daemon-warmup' 必须在本档所有模块 require 完之后调用
;; （原配置是在 main.el 末尾），因此调用点放在 profiles/standard.el 的
;; daemon 分支里，不在本文件自动执行——提前调用只会预热到一个半截的
;; 配置。警告 advice 则是加载即生效，无需额外接线。
;;
;; 另有一处从桌面端「启动与基础设施」域并入：非 daemon 的交互式启动顺便
;; 开 server-mode，让 emacsclient 能连上。daemon 启动时 server 已被 Emacs
;; 自己拉起（`daemon' 参数即以 server 模式运行），batch 与非交互场景根本
;; 不该监听 TCP，所以三处都要挡掉。
;;
;; server 这段有两个落点，核心是「认证目录必须先于 server-start 定好」：
;; · 认证目录要钉回 emacsclient 认得的默认落点。emacsclient 是独立 C 程序，
;;   不读 Elisp 的 `server-auth-dir'，默认只查 ~/.emacs.d/server/（或
;;   $XDG_CONFIG_HOME/emacs/server/）；而 standard/ide 档尾部的 no-littering
;;   会把该目录搬进 var/server/auth/，搬完 Emacs 把认证文件写去新址、
;;   emacsclient 仍按旧址找就连不上。认证目录是与 emacsclient 的公共约定，
;;   不是可随意搬的杂物。钉回挂在 no-littering 的 eval-after-load 上：认证
;;   文件写去哪由 server-start 那一刻的变量值决定，server 起来后再改不会挪
;;   文件，所以必须赶在 server-start 前钉好——no-littering 在 init 期加载，
;;   此刻钉回必然早于 after-init-hook 的 server-mode 与 daemon 的 server-start。
;; · 非 daemon 的 server-mode 经 `self/daemon--enable-server-mode' 包一层，
;;   延到 after-init-hook（此时钉目录已落地）：Windows 便携包先自愈认证目录
;;   所有权（管理员身份跑过启动器会把目录落成 Administrators 组 RID 544，
;;   普通账户被 `server-ensure-safe-dir' 拒绝），且启动失败只警告不中断——
;;   server 是可选便利，不该拖垮整份配置。

;;; Code:

(defvar server-auth-dir)
(declare-function server-running-p "server")
(declare-function server-mode "server")

;; ─── server-mode：让 emacsclient 能连上交互式启动的实例 ─────────────
;; 非 daemon 的交互式启动顺手开 server-mode；已经是 daemon 的、或根本不是
;; 交互式的（batch 冒烟、脚本化调用）都不必监听 TCP 端口。

;; Platform: windows
(defun self/daemon--heal-server-auth-dir ()
  "Windows 便携包自愈：server 认证目录被 Administrators 组持有时重建。
Emacs 的 `server-ensure-safe-dir' 只在当前用户是内置 Administrator
（RID 500）时才接受 Administrators 组（RID 544）的所有权；普通管理员
账户（RID≠500）会被拒。以管理员身份跑过一次启动器，认证目录就会落成
544，此后普通启动必报错。目录里只有上一实例的认证文件，确认无存活
server 后删掉，让 `server-start' 以当前用户重建（实测重建即归当前用户）。
机制见 server.el 的 `server-ensure-safe-dir'。"
  (let* ((dir (directory-file-name (expand-file-name server-auth-dir)))
         (attrs (file-attributes dir 'integer)))
    (when (and attrs
               (/= (file-attribute-user-id attrs) (user-uid))
               (not (server-running-p)))
      (delete-directory dir t))))

(defun self/daemon--enable-server-mode ()
  "交互式启动开 server-mode；失败只警告，不中断配置加载。
server 是 emacsclient 的便利入口，属可选能力：认证目录权限一类环境
问题不该让整份配置加载失败（与配置对可选工具缺席一律降级的口径一致）。
server-mode 内部建目录、写认证文件属文件 I/O，condition-case 是允许场景。"
  (require 'server)
  (condition-case err
      (progn
        ;; Platform: windows
        (when (eq system-type 'windows-nt)
          (self/daemon--heal-server-auth-dir))
        (server-mode 1))
    (error
     (display-warning
      'self-daemon
      (format "server-mode 启动失败（emacsclient 不可用）：%s"
              (error-message-string err))))))

;; ─── 认证目录钉回默认落点（emacsclient 的公共约定）──────────────────
;; 钉回必须赶在 server-start 之前：认证文件写去哪由 server-start 那一刻的
;; `server-auth-dir' 决定，server 起来后再改变量并不会挪动已写出的认证文件。
;; 故挂在 no-littering 的 eval-after-load 上——no-littering 在 profile 尾部、
;; init 期内加载，此刻钉回必然早于 after-init-hook 里的 server-mode，也早于
;; daemon 的 server-start，两条启动路都落在 emacsclient 认得处。
(defun self/daemon--pin-server-auth-dir ()
  "把 `server-auth-dir' 钉回 emacsclient 默认查找的目录。
no-littering 会把它搬进 var/，但 emacsclient 不读该变量、只认默认落点，
搬了就连不上，故在此恢复默认。"
  (setq server-auth-dir (locate-user-emacs-file "server/")))

(with-eval-after-load 'no-littering
  (self/daemon--pin-server-auth-dir))

;; 非 daemon 的交互式启动延到 after-init-hook 开 server-mode：此时钉目录已
;; 随 no-littering 加载落地，heal 与 server-start 都落在最终落点。
(unless (or (daemonp) noninteractive)
  (add-hook 'after-init-hook #'self/daemon--enable-server-mode))

;; ─── daemon 预热 ────────────────────────────────────────────────────
;; 预加载白名单：这些库都在交互路径上被高频首次触碰（Magit 的 status、
;; Org-agenda 扫描、Capture 模板、TRAMP 开远程文件），代价是纯 CPU 与
;; 几 MB 常驻内存，对一个常驻后台进程来说无所谓。

(defconst self:daemon-warmup-features
  '(org-agenda org-capture org-roam
               apheleia magit tramp)
  "daemon 启动阶段预载的常用交互 feature 白名单。")

(defun self/daemon-warmup ()
  "同步预载 `self:daemon-warmup-features'，让首个 client 直接复用。
返回 t 表示全部加载成功；任一 feature 缺失则记一条消息并返回 nil。
加载期间临时抬高 GC 阈值并降低触发百分比，避免几百个临时符号把
堆搅碎后紧接着来一次昂贵的完整回收；结束后手动回收一次，把预热
阶段产生的垃圾还给空闲 daemon（此时没有交互延迟压力）。"
  (let ((gc-cons-threshold most-positive-fixnum)
        (gc-cons-percentage 0.6)
        failed)
    (dolist (feature self:daemon-warmup-features)
      (condition-case err
          (unless (require feature nil t)
            (push (cons feature "未找到 feature") failed))
        (error
         (push (cons feature (error-message-string err)) failed))))
    (garbage-collect)
    (when failed
      (message "[self-config] daemon 预热失败: %S" (nreverse failed)))
    (null failed)))

;; ─── client 帧的启动警告降噪 ────────────────────────────────────────
;; 判据读文本而不是按钮属性：只数警告头行与其中匹配 cookie 噪声的行数，
;; 两者相等才算「整缓冲全无害」。上游若改了措辞，计数对不上就照常弹窗，
;; 不会静默吞掉真警告。日志本身仍原样留在 * Warnings * 里。

(defun self--warnings-benign-only-p (buffer)
  "BUFFER 中是否只含可忽略的 lexical-binding cookie 警告。
逐条数警告头行与其中匹配 cookie 噪声的行数：两者相等才算「全无害」。
判据读文本而非按钮属性，且只在计数完全对上时才返回 t——上游若改了措辞，
计数对不上即照常弹窗，不会静默吞掉真警告。"
  (with-current-buffer buffer
    (let ((total 0) (benign 0))
      (save-excursion
        (goto-char (point-min))
        (while (re-search-forward
                "^[ \t]*\\(?:[^ \t\n]+[ \t]+\\)?\\(?:Warning\\|Error\\|Emergency\\|Debug\\) ([^)]*): "
                nil t)
          (setq total (1+ total))
          (when (looking-at-p "Missing [‘`']lexical-binding[’'] cookie in ")
            (setq benign (1+ benign)))))
      (and (> total 0) (= total benign)))))

(defun self--skip-benign-warning-display (orig buffer)
  "只含无害噪声时跳过弹出 BUFFER（即 *Warnings*），否则交给 ORIG。"
  (unless (self--warnings-benign-only-p buffer)
    (funcall orig buffer)))

;; 滤在这一处而不是逐个 warning-source 打补丁：lexical-binding cookie 缺失
;; 是本配置里最高频的假阳性（大量第三方单文件脚本如此），而
;; warning--display-buffer 是所有警告弹窗的唯一入口，漏了它就会在启动后
;; 弹一个盖住 dashboard 的 *Warnings*。
;; 用 `:around' + 转发而非 `:override'：判定为非无害时要原样把 ORIG 叫回来，
;; 未来 Emacs 给警告弹窗加的功能不会因为我们拦了一道就丢掉。
(advice-add 'warning--display-buffer :around #'self--skip-benign-warning-display)

(provide 'self-daemon)
;;; self-daemon.el ends here
