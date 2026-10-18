;;; self-lib.el --- 平台谓词、路径常量、进程环境与加载辅助 -*- lexical-binding: t; -*-

;;; Commentary:
;; 三档 profile 共享的基础设施：平台判断、目录常量、外部命令名、进程级
;; 环境设置、profile 加载器、模块耗时记录、启动优化复位、后台补编译。
;; 只读 early-init.el 定义的 `self:repo'、`self:profile' 与
;; `self--startup-file-name-handlers'，不做防御性改写。
;;
;; 路径常量（含 Org 笔记目录与 data/ 本地化数据目录）在本文件里是**唯一
;; 真相源**——功能模块只做 `(defvar self:org-directory)' 这类就近声明，
;; 不再各自 defconst，免得同一路径在三档里悄悄长出三个值。
;;
;; Profiles: all
;; Requires: （无——只读 early-init 的变量，见文件头的 defvar 声明）

;;; Code:

(defgroup self nil
  "UniEmacs 统一配置。"
  :group 'emacs)

;; early-init.el 定义，本文件只读。声明出来是为了单独编译本文件时
;; 不报「引用自由变量」警告；运行时由加载顺序保证已定义。
(defvar self:repo)
(defvar self:profile)
(defvar self--startup-file-name-handlers)

;; ─── 平台谓词 ────────────────────────────────────────────────────

(defconst self:android-p (eq system-type 'android)
  "是否运行在 Android 原生 Emacs 上。")

;; GUI 与否跟 frame 走：daemon 启动时还没有图形 frame，`display-graphic-p'
;; 只能看到启动时刻的状态，所以这里保留启动时刻常量。需要按当前 frame
;; 判断时（如新建 frame 的钩子），直接调用 (display-graphic-p [frame])
;; 的函数形式，不要读这两个常量。
(defconst self:gui-p (display-graphic-p)
  "启动时刻是否为图形显示。daemon 场景下可能为 nil，见上面的取舍注释。")

(defconst self:tty-p (not (display-graphic-p))
  "启动时刻是否为终端显示。与 `self:gui-p' 相反，取舍同上。")

;; ─── 路径常量 ────────────────────────────────────────────────────

(defconst self:data-home
  (if (eq system-type 'android)
      "/data/data/com.termux/files/home/"
    (let ((xdg (getenv "XDG_DATA_HOME")))
      (if (and xdg (> (length xdg) 0))
          xdg
        (expand-file-name "~/"))))
  "缓存与持久化状态的根目录。
Android 用 Termux 家目录；其余取 $XDG_DATA_HOME（空字符串视为未设置），
无则回退家目录。沙箱冒烟时 HOME 被隔离，状态自动落进沙箱。")

(defconst self:var-directory
  (if (eq system-type 'android)
      (expand-file-name ".local/state/emacs/" self:data-home)
    (let ((xdg (getenv "XDG_STATE_HOME")))
      (if (and xdg (> (length xdg) 0))
          (expand-file-name "emacs/" xdg)
        (expand-file-name "~/.local/state/emacs/"))))
  "持久化状态目录（XDG state 语义），不存在则自动创建。
桌面端走 $XDG_STATE_HOME（缺省 ~/.local/state）；Android 无 XDG，
回退 Termux 家目录下的 .local/state。")

(unless (file-directory-p self:var-directory)
  (make-directory self:var-directory t))

(defconst self:cache-directory
  (if (eq system-type 'android)
      (expand-file-name ".cache/emacs/" self:data-home)
    (let ((xdg (getenv "XDG_CACHE_HOME")))
      (if (and xdg (> (length xdg) 0))
          (expand-file-name "emacs/" xdg)
        (expand-file-name "~/.cache/emacs/"))))
  "缓存根目录（$XDG_CACHE_HOME/emacs）：eln 与 elpaca 等放仓库外，
避免污染仓库源码目录。")

(unless (file-directory-p self:cache-directory)
  (make-directory self:cache-directory t))

(defconst self:etc-directory
  (expand-file-name "config/emacs/" self:var-directory)
  "用户自定义文件目录：custom.el 的落点。full 档的 no-littering 配置读它。")

;; ─── Org 与笔记目录 ──────────────────────────────────────────────
;;
;; 平台差异写进常量定义本身（AGENTS.md §2：平台正交于档位，用平台谓词在
;; 定义处分支，模块里不再重复判断）。桌面端沿用原配置的固定家目录路径，
;; Android 端优先用 Syncthing 同步目录，存在性检测一次，缺失则回退本地。

(defconst self:org-directory
  (if self:android-p
      (if (file-directory-p "/storage/emulated/0/Data/Syncthing/notebook/org/")
          "/storage/emulated/0/Data/Syncthing/notebook/org/"
        (expand-file-name "org/" user-emacs-directory))
    (expand-file-name "~/Documents/Org/"))
  "Org 文件根目录。
桌面端固定为家目录下的 ~/Documents/Org/；Android 端优先 Syncthing 同步
目录，检测不到时回退仓库内的 org/（保证沙箱与新设备首次启动可用）。")

(defconst self:org-roam-directory
  (expand-file-name "roam" self:org-directory)
  "Org-roam 笔记目录。")

(defconst self:org-inbox-file
  (expand-file-name "inbox.org" self:org-directory)
  "Org 收件箱文件。")

(defconst self:org-knowledge-directory
  (expand-file-name "experiences" self:org-directory)
  "知识库经验卡片目录（人类域）。")

;; ─── 本地化数据目录 ──────────────────────────────────────────────

(defconst self:i18n-data-directory
  (expand-file-name "data/" self:repo)
  "本地化纯数据文件目录（翻译表、图标资产等字面量数据）。
挂在仓库根下而非 `user-emacs-directory' 下：data/ 是仓库的一部分
（见 AGENTS.md §2 的目录契约），而 user-emacs-directory 只是入口文件的
安装位置——桌面仓库 clone 到任意位置，两者并不相等。")

;; ─── 外部命令声明 ────────────────────────────────────────────────
;;
;; 为什么只写命令名、不写绝对路径：在 GNU Guix 系统上，每次系统升级后
;; /gnu/store/ 里软件包的哈希（即 store path）都会变。把绝对路径硬编码进
;; 配置，升级后旧路径立即失效。这里只记录命令名（如 "git"），由 Emacs 运行时
;; 通过 `exec-path' 动态查找——即便后台守护进程跨代系升级，也能拿到最新工具。

(let* ((guix-profile (or (getenv "GUIX_PROFILE")
                         (expand-file-name "~/.guix-profile")))
       (guix-bin (expand-file-name "bin" guix-profile))
       (local-bin (expand-file-name "~/.local/bin")))
  ;; 候选目录存在的才加入，候选在前（先命中 Guix profile 的显式安装）。
  (when (file-directory-p local-bin)
    (add-to-list 'exec-path local-bin))
  (when (file-directory-p guix-bin)
    (add-to-list 'exec-path guix-bin))
  ;; 把 exec-path 同步写回 process-environment 的 PATH。少了这一步，
  ;; executable-find 找得到（它读 exec-path），但 make-process /
  ;; call-process 派生的子进程仍按启动时的旧 PATH 找命令——LSP、外部工具
  ;; 会出现「Emacs 里找得到、子进程里 not found」的分裂现象。
  ;; 注意 Emacs 内建没有 `set-exec-path' 这个函数（那是若干配置的私有
  ;; 封装），同步 PATH 的办法就是自己用 path-separator 拼回去。
  (setenv "PATH" (mapconcat #'identity exec-path path-separator)))

(defconst self:executable-aspell "aspell"
  "拼写检查程序名，供 ispell-program-name 使用。")

(defconst self:executable-agenote "agenote"
  "卡片盒笔记工具 agenote 的命令名。")

(defconst self:executable-direnv "direnv"
  "direnv 的命令名，用于环境加载检测。")

(defconst self:executable-git "git"
  "git 的命令名，供状态查询一类命令直接拼进进程参数。")

(defconst self:executable-godot "godot"
  "Godot 编辑器的命令名，供 gdscript-mode 指定解释器。")

;; ─── 进程运行环境 ────────────────────────────────────────────────
;;
;; 描述的是 Emacs **进程**而非「用户会话」的行为：任何模块被 require 之前
;; 就该生效，且不随某档的模块清单增减而反复重设。全部是内建变量，三档共用。
;; （垃圾回收节律另见 `self/restore-startup-perf'；gcmh 属第三方包，
;; 因此留在 profiles/full.el 档内配置。）

;; 子进程与输入吞吐：抬高 read-process-output-max 提升 LSP 与终端的输出
;; 吞吐；关掉自适应读缓冲以降低单次读取延迟；允许滚动时跳过像素级精确。
(setq read-process-output-max (* 4 1024 1024)
      process-adaptive-read-buffering nil
      fast-but-imprecise-scrolling t)

;; 启动问候语与图形弹窗：安静启动。
;; use-dialog-box / use-file-dialog 在无 GTK 端口时本来也会自动回退，
;; 这里显式关掉以免桌面端弹出原生对话框打断输入。
(setq inhibit-startup-screen t
      initial-scratch-message nil
      ring-bell-function 'ignore
      confirm-kill-processes nil
      use-dialog-box nil
      use-file-dialog nil)

;; ─── 版本谓词 ────────────────────────────────────────────────────

(defconst self:emacs-31-p (>= emacs-major-version 31)
  "当前 Emacs 是否为 31 及以上（load-path 查找缓存等新特性可用）。")

;; ─── 跨模块共享的能力与阈值（唯一真相源） ─────────────────────────
;;
;; 曾被多个模块各自重复声明的变量归并于此；模块侧只写不带值的 defvar。

(defvar self:nerd-icons-available (require 'nerd-icons nil t)
  "nerd-icons 包是否已加载；图标渲染的统一守卫变量。
缺包环境返回 nil 不报错；UI 模块（modeline/tabline/dashboard）
据此走字形降级链，不在各自文件里重复探测。")

(defcustom self:large-file-size-threshold (* 2 1024 1024)
  "关闭高成本显示功能的文件大小阈值（字节）。
self-theme 的行号开关与 self-prog 的大文件降级共用同一阈值。"
  :type 'integer
  :group 'self)

;; ─── profile 加载器 ──────────────────────────────────────────────

(defun self/load-profile (profile)
  "加载 profiles/<PROFILE>.el，PROFILE 为 minimal、portable、full、ide 之一。
加载失败时报错并带上 profile 名与文件路径。成功返回 t。"
  (interactive
   (list (let ((name (completing-read
                      "Profile (minimal/portable/full/ide): "
                      '("minimal" "portable" "full" "ide") nil t)))
           (cond
            ((equal name "minimal") 'minimal)
            ((equal name "portable") 'portable)
            ((equal name "ide") 'ide)
            (t 'full)))))
  ;; load 是文件 I/O，condition-case 包裹是允许的场景。
  (let ((file (expand-file-name (format "profiles/%s.el" profile)
                                self:repo)))
    (condition-case err
        (progn
          (load file nil nil)
          (message "UniEmacs: 已加载 profile %s" profile)
          t)
      (error
       (error "UniEmacs: 加载 profile %s 失败（%s）：%s"
              profile file (error-message-string err))))))

;; ─── 模块耗时记录 ────────────────────────────────────────────────

(defvar self--module-timings '()
  "已加载模块的耗时表，元素为 (FEATURE . 秒数）。
由 `self/require-all' 记录，供 `self/startup-report' 打印。")

(defun self/require-all (&rest features)
  "按序 require FEATURES，并把每个耗时记入 `self--module-timings'。
供各 profile 文件使用。加载失败直接报错中断：profile 的 require
序列即依赖契约，不静默跳过。"
  (dolist (feat features)
    (let ((start (current-time)))
      (require feat)
      (push (cons feat (float-time (time-subtract (current-time) start)))
            self--module-timings))))

(defun self--format-timing (entry)
  "把 (FEATURE . 秒数) 格式化为可读字符串。"
  (format "%s %.3fs" (car entry) (cdr entry)))

(defun self/startup-report ()
  "在 echo 区打印各模块加载耗时（来自 `self--module-timings'）。"
  (interactive)
  (if (null self--module-timings)
      (message "UniEmacs: 尚未记录模块耗时")
    (let ((entries (reverse self--module-timings))
          (total 0.0))
      (dolist (entry entries)
        (setq total (+ total (cdr entry))))
      (message "UniEmacs 模块耗时（共 %.3fs）：%s"
               total
               (mapconcat #'self--format-timing entries ", ")))))

;; ─── 启动优化复位 ────────────────────────────────────────────────

(defun self/restore-startup-perf ()
  "恢复 GC 稳态阈值与文件名处理器，空闲时回收一次启动垃圾。
挂在 `emacs-startup-hook' 上：after-init 的首屏生成仍在高阈值下进行。
（移植自移动端配置的同名函数语义。）"
  (setq gc-cons-threshold (* 16 1024 1024)
        gc-cons-percentage 0.1)
  ;; early-init 未运行的极端场景下变量不存在，boundp 兜底。
  (when (boundp 'self--startup-file-name-handlers)
    (setq file-name-handler-alist self--startup-file-name-handlers))
  (run-with-idle-timer 3 nil #'garbage-collect))

(add-hook 'emacs-startup-hook #'self/restore-startup-perf)

;; ─── modules 后台补编译 ──────────────────────────────────────────
;; 源码慢于字节码；空闲时逐文件补齐。byte-compile 跑在主线程同步执行、
;; 期间阻塞输入，所以间隔取 2 秒：有输入即重置计时，真正避让用户。

(defun self/lib--el-stale-p (el)
  "EL 对应的 .elc 缺失或旧于源码时返回非 nil。"
  (let ((elc (concat el "c")))
    (or (not (file-exists-p elc))
        (time-less-p (file-attribute-modification-time
                      (file-attributes elc))
                     (file-attribute-modification-time
                      (file-attributes el))))))

(defun self/compile-modules ()
  "编译 modules/ 下缺失或过期的 .el，编完一个再约下一轮。"
  (let ((stale '()))
    (dolist (el (directory-files (expand-file-name "modules" self:repo)
                                 t "\\.el\\'"))
      (when (self/lib--el-stale-p el)
        (push el stale)))
    (setq stale (nreverse stale))
    (when stale
      (byte-compile-file (car stale))
      (run-with-idle-timer 2 nil #'self/compile-modules))))

(defun self/lib--schedule-compile ()
  "启动后若 modules/ 可写，空闲 8 秒后开始后台补编译。"
  (when (file-writable-p (expand-file-name "modules" self:repo))
    (run-with-idle-timer 8 nil #'self/compile-modules)))

(add-hook 'emacs-startup-hook #'self/lib--schedule-compile)

;; ─── 上游 defface 修补 ────────────────────────────────────────────

(defun self/defface-spec-de-nil (face &rest attrs)
  "把 FACE 的 `face-defface-spec' 中 ATTRS 里值为 nil 的项改写成 unspecified。
一些上游包的 `defface' 用反引号在 spec 里内联求值 face-foreground /
face-background 之类的取色式（svg-lib 的按钮 face、treemacs 的
fringe-indicator face 都是此类）；daemon 启动时尚无 GUI frame，
取色式求值出 nil 并被烙进 spec。此后每个
新 frame 的 face realization 都重放该 spec，逐个打出
\"nil value is invalid\" 警告——`emacsclient -c' 每开一帧刷一轮。
这里按警告自身的处方就地改写 spec 的 cons 单元（不重建 spec 结构：
`face-spec-set' 对 entry 形状的约定与 defface 实际写出的 (DISPLAY . PLIST)
点对形式有出入，整体回写会腐蚀 spec）。unspecified 表示「不指定、
向上继承」，与 nil 语义等价，视觉无差；已有实色的属性不动。"
  (dolist (entry (get face 'face-defface-spec))
    (dolist (attr attrs)
      (let ((cell (member attr (cdr entry))))
        (when (and cell (null (cadr cell)))
          (setcar (cdr cell) 'unspecified))))))

(provide 'self-lib)
;;; self-lib.el ends here
