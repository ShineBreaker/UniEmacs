;;; early-init.el --- UniEmacs 启动期优化、仓库定位与 profile 解析 -*- lexical-binding: t; -*-

;;; Commentary:
;; 在图形界面初始化之前运行，只做必须早于启动完成的事：启动优化、
;; 仓库根定位、Android 重定向、profile 解析。
;;
;; Profiles: all
;; Requires: （无——本文件只依赖自身，self-lib 此时不在 load-path）
;;
;; 部署形态：桌面与 Android 都是「两个入口副本 + 仓库本体」——本文件与
;; init.el 复制到 Emacs 家目录（桌面 ~/.config/emacs/ 或 ~/.emacs.d/，
;; Android 上 Emacs 的 ~/.emacs.d/），仓库本体另行 clone。桌面靠
;; `self:repo' 定位代码（重定向不需要）；Android 在下面做一次性重定向
;; （沿用移动端配置已验证的转发模型）。

;;; Code:

;; modules/ 可能有后台补编译的 .elc：源码更新时必须优先加载新源码，
;; 否则更新后的首次启动仍跑旧字节码。
(setq load-prefer-newer t)

(defvar self:repo nil
  "UniEmacs 仓库根目录（末尾带斜杠）。
解析优先级：UNI_EMACS_REPO 环境变量 → 家目录下部署生成的
repo-location.el → 本文件所在目录（含 core/ 时）→ Android 惯例位置。
解析失败时为 nil，由 init.el 报错兜底。")

(defvar self:profile nil
  "当前 profile：minimal、portable、full 之一。
UNI_EMACS_PROFILE 环境变量优先（非法值警告并按平台推断回退），
其次 Android 推断为 portable，默认 full。")

(defvar self--startup-file-name-handlers file-name-handler-alist
  "启动前原 file-name-handler-alist，由 self-lib 复位用。")

;; ─── 仓库根解析（只用一次，直接平铺四段） ──────────────────────────

(setq self:repo nil)

;; 1. 环境变量优先。空字符串视为未设置（否则会相对当前目录误判）。
(let ((from-env (getenv "UNI_EMACS_REPO")))
  (when (and from-env
             (> (length from-env) 0)
             (file-directory-p (expand-file-name "core" from-env)))
    (setq self:repo (file-name-as-directory (expand-file-name from-env)))))

;; 2. 家目录下部署时生成的 repo-location.el，内含 (setq self:repo ...)。
;; 文件存在但内容无效（self:repo 仍空或其下无 core/）时回到 nil，
;; 继续走下面的兜底。
(when (and (null self:repo)
           (file-exists-p (expand-file-name "repo-location.el"
                                            user-emacs-directory)))
  (load (expand-file-name "repo-location.el" user-emacs-directory) nil t)
  (unless (and self:repo
               (file-directory-p (expand-file-name "core" self:repo)))
    (setq self:repo nil)))

;; 3. 本文件所在目录：软链或就地运行场景下其真实路径即仓库根。
(when (and (null self:repo) load-file-name)
  (let ((dir (file-name-directory (file-truename load-file-name))))
    (when (file-directory-p (expand-file-name "core" dir))
      (setq self:repo (file-name-as-directory dir)))))

;; 4. Android 惯例位置（Termux 家目录下的仓库）。
(when (and (null self:repo)
           (file-directory-p (expand-file-name
                              "core"
                              "/data/data/com.termux/files/home/.config/emacs/")))
  (setq self:repo "/data/data/com.termux/files/home/.config/emacs/"))

;; ─── Android 入口副本：重定向后加载仓库版 ──────────────────────────

(if (and self:repo
         (eq system-type 'android)
         (file-directory-p (expand-file-name "core" self:repo))
         (not (file-equal-p user-emacs-directory self:repo)))
    ;; Emacs 家目录里的副本：重定向后加载仓库版本。仓库版里
    ;; user-emacs-directory 已等于仓库，上面的 file-equal-p 成立，
    ;; 不再转发，直接执行下面的本体。
    (progn
      (setq user-emacs-directory self:repo)
      (load (expand-file-name "early-init.el" self:repo) nil t))

  ;; ── 本体（仓库内运行 / 桌面入口副本 / 已重定向后的仓库版） ──

  ;; 禁用 package.el 自动初始化（包由各 profile 的包清单管理）；
  ;; 跳过 site-start 与 default.el。
  (setq package-enable-at-startup nil
        inhibit-default-init t
        site-run-file nil)

  ;; frame 参数抑制：初始 frame 不建 menu/tool/scroll bar，
  ;; 省掉先建默认栏再拆的浪费。
  (dolist (param '((menu-bar-lines . 0) (tool-bar-lines . 0)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)))
    (add-to-list 'default-frame-alist param))

  ;; TTY frame 初始参数注入（移植自桌面端配置）：daemon client 与
  ;; standalone 启动阶段就继承终端默认前后景，避免短暂显示 Emacs
  ;; 的有色默认 face。t 条目不存在时新建，存在时逐项合入。
  (let ((tty-params '((background-color . "unspecified-bg")
                      (foreground-color . "unspecified-fg")
                      (menu-bar-lines . 0)
                      (tool-bar-lines . 0)
                      (vertical-scroll-bars . nil)
                      (horizontal-scroll-bars . nil)))
        (entry (assq t window-system-default-frame-alist)))
    (if entry
        (dolist (param tty-params)
          (setf (alist-get (car param) (cdr entry)) (cdr param)))
      (push (cons t tty-params) window-system-default-frame-alist)))

  ;; 启动性能优化：GC 阈值推高、绕过文件名处理器（启动后由
  ;; self-lib 的 self/restore-startup-perf 复位）。
  (setq gc-cons-threshold most-positive-fixnum
        gc-cons-percentage 0.6
        file-name-handler-alist nil)

  ;; load-path 查找缓存（Emacs 31+ 才有这个变量）：require 时跳过
  ;; 不含目标的目录。boundp 守卫是跨构建变量的合法场景。
  (when (boundp 'load-path-filter-function)
    (setq load-path-filter-function
          #'load-path-filter-cache-directory-files))

  ;; profile 解析：环境变量 → 平台推断 → 默认 full。
  ;; 非法值警告一次，并回退到平台推断（与下面两条同逻辑）。
  (setq self:profile
        (let ((from-env (getenv "UNI_EMACS_PROFILE")))
          (cond
           ((equal from-env "minimal") 'minimal)
           ((equal from-env "portable") 'portable)
           ((equal from-env "full") 'full)
           ((and from-env (> (length from-env) 0))
            (display-warning
             'self
             (format "非法的 UNI_EMACS_PROFILE=%S，可选 minimal/portable/full，已按平台推断回退。"
                     from-env))
            (if (eq system-type 'android) 'portable 'full))
           ((eq system-type 'android) 'portable)
           (t 'full)))))

(provide 'early-init)
;;; early-init.el ends here
