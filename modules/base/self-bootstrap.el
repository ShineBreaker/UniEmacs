;;; self-bootstrap.el --- 首次启动自动补全字体与语法库 -*- lexical-binding: t; -*-

;;; Commentary:
;; 把 justfile 里两项「纯下载」依赖搬进 Emacs 首次启动：缺失时后台
;; 自动补齐，不阻塞启动。justfile 的 font / grammars 目标改为本文件的
;; batch 薄包装，URL 与版本号只在本文件定义（单一真相源）。
;;
;; 搬与不搬的决策记录：
;; · font / grammars 搬——幂等、无需编译器、状态落 HOME、可异步；
;;   Windows 10+ 自带 curl 与 tar（bsdtar，连 zip 也能解），零额外依赖。
;; · icons 不搬——需要 rsvg-convert / netpbm 工具链，且资产随仓库分发。
;; · termux-deps 不搬——系统包安装，Emacs 无法代劳。
;; · packages 无需搬——self/package-ensure 每次启动本就自动装包。
;; · verify / compile 等是开发门禁，留在 justfile。
;;
;; 字体优先用仓库自带的 data/fonts/ TTF（便携包离线安装），
;; 三个文件齐全才走离线路径，缺任何一个都回退下载。
;;
;; 【机制】单条异步步骤链：步骤是命令行 (PROGRAM ARG...) 或 elisp 函数
;; 符号（文件操作），make-process + sentinel 逐步推进；batch（just 包装
;; 路径）没有事件循环，命令步退化为 call-process 同步。同一时刻只跑一条
;; 链。失败写冷却时间戳，自动模式 24 小时内不再重试（避免每次启动都撞
;; 同一堵网络墙），手动命令不受冷却限制。
;;
;; 【Windows 字体后端的坑】w32 字体后端经 Windows API 枚举字体，不读
;; fontconfig 的用户目录——把 TTF 拷进 ~/.local/share/fonts 在 Windows
;; 上无效（just 旧目标的行为）。正确做法是落 per-user 字体目录
;; %LOCALAPPDATA%\Microsoft\Windows\Fonts 并在 HKCU 的 Fonts 键注册
;; （无需管理员）。Linux 仍走 fontconfig 用户目录，Android 走应用
;; fonts/ 目录（sfnt-android 枚举）。
;;
;; Profiles: portable, standard, ide
;; Requires: self-lib（`self:repo'、`self:cache-directory'、`self:font-family'）self-package（`self/package--guix-emacs-p'）
;; Packages: 无（curl / tar / unzip / reg 均为系统自带或 Termux 已装）

;;; Code:

(defvar self:repo)
(defvar self:cache-directory)
(defvar self:font-family)
(declare-function self/package--guix-emacs-p "self-package")

(defcustom self:bootstrap-auto-p t
  "首次启动后是否自动后台补全缺失的字体与语法库。
设为 nil 只关闭自动行为；M-x self/bootstrap-fonts 与
M-x self/bootstrap-grammars 仍可手动触发。"
  :type 'boolean
  :group 'self)

;; ─── 常量：下载源与落点 ───────────────────────────────────────────

(defconst self:bootstrap-font-url
  "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-NF-CN.zip"
  "Maple Mono NF CN 发布 zip（含 Regular / Italic / Bold）。")

(defconst self:bootstrap-font-files
  '(("Regular" . "MapleMono-NF-CN-Regular.ttf")
    ("Italic" . "MapleMono-NF-CN-Italic.ttf")
    ("Bold" . "MapleMono-NF-CN-Bold.ttf"))
  "字体样式 → 文件名表。Windows 注册表值名也由此派生。")

;; Platform: android, windows, linux
(defconst self:bootstrap-font-directory
  (cond
   ;; Android：sfnt-android 只枚举应用私有 fonts 目录
   ((file-directory-p "/data/data/org.gnu.emacs")
    "/data/data/org.gnu.emacs/files/fonts/")
   ;; Windows：per-user 字体目录，配合 HKCU 注册表注册（见文件头）
   ((eq system-type 'windows-nt)
    (expand-file-name "Microsoft/Windows/Fonts/" (getenv "LOCALAPPDATA")))
   (t (expand-file-name "~/.local/share/fonts/")))
  "字体安装目录（按平台）。与 justfile 旧目标的桌面落点一致，
Windows 分支修正为 w32 字体后端真正读取的位置。")

(defconst self:bootstrap-grammars-version "0.13.75"
  "tree-sitter-langs 预编译 bundle 版本。")

(defconst self:bootstrap-grammars-url
  (format "https://github.com/emacs-tree-sitter/tree-sitter-langs/releases/download/%s/tree-sitter-grammars-windows-%s.tar.gz"
          self:bootstrap-grammars-version self:bootstrap-grammars-version)
  "Windows 预编译语法库 bundle（平铺 <lang>.dll，无编译器可用）。")

(defconst self:bootstrap-grammars-directory
  (expand-file-name "tree-sitter/" self:cache-directory)
  "语法库落点，与 self-prog 注册进 `treesit-extra-load-path' 的目录一致。")

;; Platform: windows
(defconst self:bootstrap-tar-program
  (if (eq system-type 'windows-nt)
      ;; 钉死 System32 的 bsdtar：PATH 里常有 Git Bash 的 GNU tar，
      ;; 它既不认 zip，又把路径里的 c: 当远程主机名（colon 陷阱）。
      ;; bsdtar 两种格式都解，也没有 colon 问题。
      (expand-file-name "System32/tar.exe" (getenv "SystemRoot"))
    "tar")
  "解压用 tar 程序。Windows 用系统自带 bsdtar 的绝对路径，其余平台
走 PATH（GNU tar 解 tar.gz 无碍，zip 在那边交给 unzip）。")

(defconst self:bootstrap-cooldown-file
  (expand-file-name "bootstrap-last-failure" self:cache-directory)
  "最近一次失败的时间戳文件（epoch 秒），自动模式的冷却依据。")

;; ─── 步骤链状态（同一时刻只有一条链） ─────────────────────────────

(defvar self/bootstrap--queue nil
  "剩余步骤表。元素是命令行 (PROGRAM ARG...) 或 elisp 函数符号。")

(defvar self/bootstrap--tmp nil
  "本条链的临时目录（下载与解压产物）。")

(defvar self/bootstrap--label nil
  "本条链的对象名（字体 / 语法库 / 配置依赖），消息与警告用。")

(defvar self/bootstrap--running nil
  "是否有链在跑。用于拒绝并发请求。")

;; ─── 缺失判定 ─────────────────────────────────────────────────────

;; Platform: guix
(defun self/bootstrap--font-needed-p ()
  "字体是否需要下载：家族与安装文件都缺，且不归 Guix 声明管理。
batch 下无 frame 时 `font-family-list' 为空，文件判定兜底。
UNI_EMACS_FONT_DOWNLOAD=1 强制绕过 Guix 守卫（与 justfile 口径一致）。"
  (and (not (member self:font-family (font-family-list)))
       (not (file-exists-p
             (expand-file-name "MapleMono-NF-CN-Regular.ttf"
                               self:bootstrap-font-directory)))
       (or (equal (getenv "UNI_EMACS_FONT_DOWNLOAD") "1")
           (not (self/package--guix-emacs-p)))))

;; Platform: windows
(defun self/bootstrap--grammars-needed-p ()
  "语法库是否需要下载：仅 Windows，以 json 库为哨兵（与 justfile 一致）。
其它平台：Guix 用 profile 语法库，其余 Linux 自行编译。"
  (and (eq system-type 'windows-nt)
       (not (file-exists-p
             (expand-file-name "libtree-sitter-json.dll"
                               self:bootstrap-grammars-directory)))))

(defun self/bootstrap--cooldown-p ()
  "是否处于失败冷却期（24 小时内）。时间戳文件缺失即无冷却。"
  (if (not (file-exists-p self:bootstrap-cooldown-file))
      nil
    (let ((last (with-temp-buffer
                  (insert-file-contents self:bootstrap-cooldown-file)
                  (string-to-number (buffer-string)))))
      (< (- (float-time) last) 86400))))

;; ─── 步骤构造 ─────────────────────────────────────────────────────

(defun self/bootstrap--bundled-fonts-dir ()
  "仓库自带字体目录（data/fonts/）三个 TTF 齐全时返回它，否则 nil。
便携包随仓库携带字体，首启安装可完全离线，不依赖网络。"
  (let ((dir (expand-file-name "data/fonts/" self:repo))
        (all t))
    (dolist (pair self:bootstrap-font-files)
      (unless (file-exists-p (expand-file-name (cdr pair) dir))
        (setq all nil)))
    (and all dir)))

;; Platform: windows
(defun self/bootstrap--font-steps ()
  "字体步骤：仓库自带字体时直接拷贝（离线）；
否则下载 → 解压 → 拷贝 →（Windows）注册表注册。"
  (if (self/bootstrap--bundled-fonts-dir)
      (append (list #'self/bootstrap--copy-fonts)
              (when (eq system-type 'windows-nt)
                (self/bootstrap--reg-steps)))
    (let ((zip (expand-file-name "maple.zip" self/bootstrap--tmp))
          (out (expand-file-name "font" self/bootstrap--tmp)))
      (append
       (list (list "curl" "-fsSL" "--retry" "3" "--max-time" "300"
                   "-o" zip self:bootstrap-font-url)
             (if (eq system-type 'windows-nt)
                 ;; bsdtar 连 zip 也能解，不依赖 unzip（程序选择见常量）
                 (list self:bootstrap-tar-program "-xf" zip "-C" out)
               (list "unzip" "-o" "-q" zip "-d" out))
             #'self/bootstrap--copy-fonts)
       (when (eq system-type 'windows-nt)
         (self/bootstrap--reg-steps))))))

;; Platform: windows
(defun self/bootstrap--reg-steps ()
  "Windows per-user 字体注册命令（HKCU，无需管理员）。
w32 字体后端经 Windows API 枚举，只拷文件不注册等于没装。"
  (let ((key "HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts")
        (steps '()))
    (dolist (pair self:bootstrap-font-files)
      (push (list "reg" "add" key "/v"
                  (concat self:font-family " " (car pair) " (TrueType)")
                  "/t" "REG_SZ" "/d"
                  (expand-file-name (cdr pair) self:bootstrap-font-directory)
                  "/f")
            steps))
    (nreverse steps)))

(defun self/bootstrap--grammars-steps ()
  "语法库步骤：下载 → 解压 → 改名落缓存。"
  (let ((tgz (expand-file-name "grammars.tar.gz" self/bootstrap--tmp))
        (out (expand-file-name "grammars" self/bootstrap--tmp)))
    (list (list "curl" "-fsSL" "--retry" "3" "--max-time" "600"
                "-o" tgz self:bootstrap-grammars-url)
          (list self:bootstrap-tar-program "xzf" tgz "-C" out)
          #'self/bootstrap--install-grammars)))

;; ─── elisp 安装步 ─────────────────────────────────────────────────

(defun self/bootstrap--copy-fonts ()
  "把字体拷进平台用户字体目录（注册由后续命令步完成）。
源优先取仓库自带的 data/fonts/（离线），否则取本条链的解压产物目录。"
  (let ((src (or (self/bootstrap--bundled-fonts-dir)
                 (expand-file-name "font" self/bootstrap--tmp))))
    (unless (file-directory-p self:bootstrap-font-directory)
      (make-directory self:bootstrap-font-directory t))
    (dolist (pair self:bootstrap-font-files)
      (copy-file (expand-file-name (cdr pair) src)
                 (expand-file-name (cdr pair) self:bootstrap-font-directory)
                 t))))

(defun self/bootstrap--install-grammars ()
  "把解压出的 <lang>.dll 改名 libtree-sitter-<lang>.dll 落缓存目录。"
  (let ((src (expand-file-name "grammars" self/bootstrap--tmp)))
    (unless (file-directory-p self:bootstrap-grammars-directory)
      (make-directory self:bootstrap-grammars-directory t))
    (dolist (dll (directory-files src t "\\.dll\\'"))
      (let ((name (file-name-sans-extension (file-name-nondirectory dll))))
        ;; c-sharp 按配置覆盖表用下划线名（与 Guix 一致，见 self-prog）
        (when (equal name "c-sharp")
          (setq name "c_sharp"))
        (rename-file dll
                     (expand-file-name (concat "libtree-sitter-" name ".dll")
                                       self:bootstrap-grammars-directory)
                     t)))))

;; ─── 步骤链推进 ───────────────────────────────────────────────────

(defun self/bootstrap--start (label assets)
  "启动一条步骤链。LABEL 是消息用对象名；ASSETS 是 font/grammars 符号表。
临时目录与输出缓冲每条链重建；已有链在跑时拒绝并发。"
  (if self/bootstrap--running
      (message "UniEmacs: 依赖补全正在进行，跳过本次请求")
    (setq self/bootstrap--label label
          self/bootstrap--tmp (make-temp-file "self-bootstrap" t)
          self/bootstrap--queue '()
          self/bootstrap--running t)
    (with-current-buffer (get-buffer-create " *self-bootstrap*")
      (erase-buffer))
    (dolist (asset assets)
      (cond
       ((eq asset 'font)
        (make-directory (expand-file-name "font" self/bootstrap--tmp))
        (setq self/bootstrap--queue
              (append self/bootstrap--queue (self/bootstrap--font-steps))))
       ((eq asset 'grammars)
        (make-directory (expand-file-name "grammars" self/bootstrap--tmp))
        (setq self/bootstrap--queue
              (append self/bootstrap--queue (self/bootstrap--grammars-steps))))))
    (self/bootstrap--next)))

(defun self/bootstrap--next ()
  "推进一步：elisp 步直接执行，命令步交子进程；队列空即收尾。"
  (if (null self/bootstrap--queue)
      (self/bootstrap--finish)
    (let ((step (car self/bootstrap--queue)))
      (setq self/bootstrap--queue (cdr self/bootstrap--queue))
      (if (symbolp step)
          ;; 文件 I/O 步：condition-case 是允许场景，失败走统一冷却
          (condition-case err
              (progn
                (funcall step)
                (self/bootstrap--next))
            (error
             (self/bootstrap--fail (error-message-string err))))
        (self/bootstrap--run-command step)))))

(defun self/bootstrap--run-command (step)
  "执行命令步 STEP = (PROGRAM ARG...)。
batch（just 包装）没有事件循环，call-process 同步等；交互会话
make-process 异步，sentinel 推进——启动与输入全程不被网络阻塞。"
  (let ((program (executable-find (car step))))
    (if (null program)
        (self/bootstrap--fail (format "找不到外部命令 %s" (car step)))
      (if noninteractive
          (let ((code (apply #'call-process program nil nil nil (cdr step))))
            (if (eq code 0)
                (self/bootstrap--next)
              (self/bootstrap--fail (format "%s 退出码 %s" (car step) code))))
        (make-process :name "self-bootstrap"
                      :buffer (get-buffer-create " *self-bootstrap*")
                      :command (cons program (cdr step))
                      :noquery t
                      :sentinel #'self/bootstrap--sentinel)))))

(defun self/bootstrap--sentinel (process event)
  "命令步哨兵：成功推进下一步，失败带输出尾部进冷却。"
  (when (memq (process-status process) '(exit signal))
    (if (and (eq (process-status process) 'exit)
             (= (process-exit-status process) 0))
        (self/bootstrap--next)
      (self/bootstrap--fail
       (format "%s（%s）" (string-trim event) (self/bootstrap--output-tail))))))

(defun self/bootstrap--output-tail ()
  "子进程输出的最后 200 字符，供失败诊断。"
  (with-current-buffer " *self-bootstrap*"
    (buffer-substring (max (point-min) (- (point-max) 200)) (point-max))))

(defun self/bootstrap--finish ()
  "链成功收尾：清理临时目录并提示重启生效。"
  (setq self/bootstrap--running nil)
  (delete-directory self/bootstrap--tmp t)
  (message "UniEmacs: %s 补全完成（重启 Emacs 生效）" self/bootstrap--label))

(defun self/bootstrap--fail (reason)
  "链失败：写冷却时间戳、清临时目录、警告并给手动重试入口。
REASON 是失败描述。自动模式 24 小时内不再重试；手动命令不受限。"
  (setq self/bootstrap--running nil)
  (with-temp-file self:bootstrap-cooldown-file
    (insert (number-to-string (truncate (float-time)))))
  (when (and self/bootstrap--tmp (file-directory-p self/bootstrap--tmp))
    (delete-directory self/bootstrap--tmp t))
  (display-warning
   'self-bootstrap
   (format "%s 补全失败：%s。手动重试：M-x self/bootstrap-fonts / self/bootstrap-grammars"
           self/bootstrap--label reason)))

;; ─── 入口：手动命令与首次启动钩子 ─────────────────────────────────

(defun self/bootstrap-fonts ()
  "安装 Maple Mono NF CN 字体（已装或归 Guix 管理则跳过）。
仓库自带字体（data/fonts/）时离线安装，否则下载。
交互命令：M-x self/bootstrap-fonts；`just font' 是它的 batch 薄包装。
Windows 落 per-user 字体目录并注册 HKCU（无需管理员）；Guix 环境
默认跳过，UNI_EMACS_FONT_DOWNLOAD=1 可强制。装完重启 Emacs 生效。"
  (interactive)
  (if (self/bootstrap--font-needed-p)
      (self/bootstrap--start "字体" '(font))
    (message "UniEmacs: 字体已安装或归 Guix 管理，跳过")))

;; Platform: windows
(defun self/bootstrap-grammars ()
  "下载 Windows 预编译 tree-sitter 语法库（已装则跳过）。
交互命令：M-x self/bootstrap-grammars；`just grammars' 是它的 batch 薄包装。
其它平台用 Guix profile 语法库或自行编译，本命令直接跳过。装完重启生效。"
  (interactive)
  (cond
   ((not (eq system-type 'windows-nt))
    (message "UniEmacs: 语法库仅 Windows 需要自动补全"))
   ((self/bootstrap--grammars-needed-p)
    (self/bootstrap--start "语法库" '(grammars)))
   (t (message "UniEmacs: 语法库已安装，跳过"))))

(defun self/bootstrap--auto ()
  "首次启动自动补全：把缺失项拼成一条链后台跑。
batch 跳过（just 包装走显式命令，验证管线保持封闭）；失败冷却期内
不重试。钩子挂在 `emacs-startup-hook'：首屏已出，下载不挡启动。"
  (when (and self:bootstrap-auto-p
             (not noninteractive)
             (not (self/bootstrap--cooldown-p)))
    (let ((assets '()))
      (when (self/bootstrap--font-needed-p)
        (push 'font assets))
      (when (self/bootstrap--grammars-needed-p)
        (push 'grammars assets))
      (when assets
        (condition-case err
            (self/bootstrap--start "配置依赖" (nreverse assets))
          (error
           (self/bootstrap--fail (error-message-string err))))))))

(add-hook 'emacs-startup-hook #'self/bootstrap--auto)

(provide 'self-bootstrap)
;;; self-bootstrap.el ends here