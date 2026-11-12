;;; self-lib.el --- 平台谓词、路径常量、进程环境与加载辅助 -*- lexical-binding: t; -*-

;;; Commentary:
;; 四档 profile 共享的基础设施：平台判断、目录常量、外部命令名、进程级
;; 环境设置、profile 加载器、模块耗时记录、启动优化复位、后台补编译。
;; 只读 early-init.el 定义的 `self:repo'、`self:profile' 与
;; `self--startup-file-name-handlers'，不做防御性改写。
;;
;; 路径常量（含 Org 笔记目录与 data/ 本地化数据目录）在本文件里是**唯一
;; 真相源**——功能模块只做 `(defvar self:org-directory)' 这类就近声明，
;; 不再各自 defconst，免得同一路径在四档里悄悄长出四个值。
;;
;; Org 根目录是唯一的例外：`M-x self/org-relocate' 可在 Emacs 内改它，
;; 由 `self:org-config-file' 持久化，启动时在本文件派生路径之前读回；
;; Roam/收件箱/知识库都是它的派生值，不单独可配（见该段注释）。
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
;; Platform: android, gui, tty

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

;; Platform: android
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

;; Platform: android
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

;; Platform: android
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
  "用户自定义文件目录：custom.el 的落点。standard 档的 no-littering 配置读它。")

;; ─── Org 与笔记目录 ──────────────────────────────────────────────
;;
;; 平台差异写进默认值定义本身（AGENTS.md §2：平台正交于档位，用平台谓词在
;; 定义处分支，模块里不再重复判断）。桌面端沿用原配置的固定家目录路径，
;; Android 端优先用 Syncthing 同步目录，存在性检测一次，缺失则回退本地。
;;
;; 目录可在 Emacs 内改：`M-x self/org-relocate' 把新根目录写进
;; `self:org-config-file'（状态目录下，不污染仓库），并在当场重算下面的
;; 派生路径、触发 `self/org-relocate-hook'。下次启动由本文件在派生路径**之前**
;; 读回该文件，故四档、各次启动拿到的仍是同一个值。

;; Platform: android
(defconst self:org-default-directory
  (if self:android-p
      (if (file-directory-p "/storage/emulated/0/Data/Syncthing/notebook/org/")
          "/storage/emulated/0/Data/Syncthing/notebook/org/"
        (expand-file-name "org/" user-emacs-directory))
    (expand-file-name "~/Documents/Org/"))
  "平台默认的 Org 根目录（未被用户覆盖时生效）。
桌面端为家目录下的 ~/Documents/Org/；Android 端优先 Syncthing 同步目录，
检测不到时回退仓库内的 org/（保证沙箱与新设备首次启动可用）。")

(defconst self:org-config-file
  (expand-file-name "org-locations.el" self:etc-directory)
  "用户 Org 目录覆盖文件（放 `self:etc-directory' 状态目录，不污染仓库）。
由 `M-x self/org-relocate' 写入，也可手工编辑：只需一行
`(setq self:org-directory \"...\")'。本文件在派生 Roam/收件箱/知识库路径
之前加载，故改动只此一处，派生值自动跟随。")

(defvar self:org-directory self:org-default-directory
  "Org 文件根目录。默认取 `self:org-default-directory'；
用户经 `M-x self/org-relocate'（写 `self:org-config-file'）覆盖。
派生值见 `self--org-recompute-paths'。")

;; 覆盖必须在派生路径之前应用，否则 Roam/收件箱会停在平台默认。文件被
;; 手改坏时不静默吞掉，警示后退回默认，避免整个启动因一份数据文件失败。
(when (file-exists-p self:org-config-file)
  (condition-case err
      (load self:org-config-file nil t)
    (error
     (display-warning 'self-lib
                      (format "Org 目录覆盖文件加载失败（%s），改用平台默认：%s"
                              self:org-config-file (error-message-string err))))))

(defvar self:org-roam-directory
  (expand-file-name "roam" self:org-directory)
  "Org-roam 笔记目录（派生自 `self:org-directory'）。")

(defvar self:org-inbox-file
  (expand-file-name "inbox.org" self:org-directory)
  "Org 收件箱文件（派生自 `self:org-directory'）。")

(defvar self:org-knowledge-directory
  (expand-file-name "experiences" self:org-directory)
  "知识库经验卡片目录（派生自 `self:org-directory'，人类域）。")

;; ─── Org 目录重定位（在 Emacs 内改笔记目录） ─────────────────────
;;
;; 机制分两半：core 改路径并广播，各 Org 模块把**已加载的第三方包变量**
;; （org-directory / org-roam-directory / agenote-*）挂到钩子上跟着走。
;; 这样 core 不必知道 org-roam 的内部变量，模块也不必关心持久化格式。

(defvar self/org-relocate-hook nil
  "Org 根目录被 `self/org-relocate' 改动后运行的钩子（无参数）。
各 Org 模块在此注册刷新函数，把已加载的第三方变量同步到新的
`self:org-directory'；核心路径由 `self--org-recompute-paths' 直接更新。")

(defun self--org-recompute-paths ()
  "按当前的 `self:org-directory' 重算全部派生路径。
改 `self:org-directory' 后必须调用，否则 Roam/收件箱/知识库仍指旧目录。"
  (setq self:org-roam-directory
        (expand-file-name "roam" self:org-directory)
        self:org-inbox-file
        (expand-file-name "inbox.org" self:org-directory)
        self:org-knowledge-directory
        (expand-file-name "experiences" self:org-directory)))

(defun self--org-write-config ()
  "把当前 `self:org-directory' 写进 `self:org-config-file'。
文件是一份最小可读的 Lisp（只有一行 setq），启动时被本文件加载即生效。"
  (let ((dir (file-name-directory self:org-config-file)))
    (unless (file-directory-p dir)
      (make-directory dir t)))
  (with-temp-file self:org-config-file
    (insert ";;; org-locations.el --- 用户 Org 目录覆盖 -*- lexical-binding: t; -*-\n"
            ";; 由 M-x self/org-relocate 写入，也可手工编辑；\n"
            ";; self-lib 在派生 Roam/收件箱路径之前加载本文件。\n\n"
            (format "(setq self:org-directory %S)\n" self:org-directory))))

(defun self--org-move-contents (from to)
  "把 FROM 下的顶层条目搬到 TO（含隐藏文件）。
逐个 `rename-file'，单个失败只警示不中断（跨文件系统或权限不足时
可能失败）。FROM 不存在、或两目录互相嵌套（搬进去会自我递归）时
直接跳过。"
  (when (and (file-directory-p from)
             (not (file-in-directory-p to from))
             (not (file-in-directory-p from to)))
    (unless (file-directory-p to)
      (make-directory to t))
    (dolist (entry (directory-files from t "\\`\\(?:[^.]\\|\\.[^.]\\)"))
      (let ((target (expand-file-name (file-name-nondirectory entry) to)))
        (condition-case err
            (rename-file entry target)
          (error
           (display-warning 'self-lib
                            (format "移动 %s 到 %s 失败：%s"
                                    entry target (error-message-string err)))))))))

(defun self/org-relocate (directory &optional move)
  "把 Org 根目录改到 DIRECTORY，持久化并让已加载的 Org 栈立刻跟随。
交互命令：M-x self/org-relocate；前缀参数（C-u）表示把现有内容搬过去。

这是「在 Emacs 内改笔记目录」的唯一入口：改完后 Roam、收件箱、agenda、
知识库经验卡全部指向新根目录，无需重启，也无需手改仓库源码。目录可以尚
不存在——`self/org-relocate-hook' 上的各模块会补齐自己那部分骨架。

副作用：写 `self:org-config-file'（下次启动直接生效）；是否随迁旧内容由
MOVE 决定，跨设备搬迁失败会逐个报错但不中断。"
  (interactive
   (list (read-directory-name "新的 Org 根目录: "
                              (file-name-as-directory self:org-directory))
         current-prefix-arg))
  (let ((new (file-name-as-directory (expand-file-name directory))))
    (unless (file-directory-p new)
      (make-directory new t))
    (when move
      (self--org-move-contents self:org-directory new))
    (setq self:org-directory new)
    (self--org-recompute-paths)
    (self--org-write-config)
    (run-hooks 'self/org-relocate-hook)
    (message "Org 根目录已改为 %s（已写入 %s）"
             self:org-directory self:org-config-file)))

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

;; Platform: guix
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
;; 就该生效，且不随某档的模块清单增减而反复重设。全部是内建变量，四档共用。
;; （垃圾回收节律另见 `self/restore-startup-perf'；gcmh 属第三方包，
;; 因此留在 profiles/standard.el 档内配置。）

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

;; ─── 跨模块共享的能力与阈值（唯一真相源） ─────────────────────────
;;
;; 曾被多个模块各自重复声明的变量归并于此；模块侧只写不带值的 defvar。

(defconst self:font-family "Maple Mono NF CN"
  "主字体家族名（中英等宽 + Nerd 图标字形），全配置唯一真相源。
self-theme 的外观应用、self-ui-touch 触屏档、ide-chrome 的编辑区字体
与 self-bootstrap 的安装判定都读它。普通版 Maple Mono 无 NF 图标
字形，装了也不算数（判定只认这个全名）。")

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
  "加载 profiles/<PROFILE>.el，PROFILE 为 minimal、portable、standard、ide 之一。
加载失败时报错并带上 profile 名与文件路径。成功返回 t。"
  (interactive
   (list (let ((name (completing-read
                      "Profile (minimal/portable/standard/ide): "
                      '("minimal" "portable" "standard" "ide") nil t)))
           (cond
            ((equal name "minimal") 'minimal)
            ((equal name "portable") 'portable)
            ((equal name "ide") 'ide)
            (t 'standard)))))
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

(defun self/set-profile (profile)
  "把 PROFILE 写入家目录 profile.el，下次启动生效。
PROFILE 为 minimal、portable、standard、ide 之一。优先级方面
UNI_EMACS_PROFILE 环境变量更高，存在时本文件被忽略；删除
profile.el 即回到平台默认档（桌面 standard）。本命令不改当前会话
已加载的模块，切换后需重启 Emacs，daemon 用
`herd restart emacs-daemon'。"
  (interactive
   (list (intern (completing-read "Profile: "
                                  '("minimal" "portable" "standard" "ide")
                                  nil t))))
  (let ((file (expand-file-name "profile.el" user-emacs-directory)))
    (with-temp-file file
      (insert ";; 由 M-x self/set-profile 生成；删除本文件即回到默认档（standard）。\n"
              (format "(setq self:profile '%s)\n" profile)))
    (message "已写入 %s：下次启动加载 %s 档（当前会话不变）。" file profile)))

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
;; 一些上游包的 defface 用反引号在 spec 里内联求值 face-foreground /
;; face-background 之类的取色式（svg-lib 按钮 face、treemacs
;; fringe-indicator face 都是此类）；daemon 启动时尚无 GUI 帧，取色式
;; 求值出 nil。defface 对现存帧 recalc 时 nil 直达 C 层，打出
;; "nil value is invalid" 警告——警告在 defface 执行当下发生，事后改
;; spec 拦不住，只能在 `set-face-attribute' 入口归一化。
;; xfaces.c 的 HANDLE_INVALID_NIL_VALUE 只检查 :foreground /
;; :distant-foreground / :background 三个 attr 的 nil，且该宏自身就把
;; nil 改写成 unspecified——advice 做同样的替换，语义与上游兜底完全一致。

(defun self/lib--face-attr-de-nil (args)
  "把 `set-face-attribute' 参数 plist 中三个颜色 attr 的 nil 值改为 unspecified。
ARGS 是 (face frame &rest attrs) 形状的调用参数列表（:filter-args advice）。"
  (let ((tail (cddr args)))
    (while tail
      (when (and (memq (car tail) '(:foreground :background :distant-foreground))
                 (null (cadr tail)))
        (setcar (cdr tail) 'unspecified))
      (setq tail (cddr tail))))
  args)

(advice-add 'set-face-attribute :filter-args #'self/lib--face-attr-de-nil)

(provide 'self-lib)
;;; self-lib.el ends here
