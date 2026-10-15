;;; self-project.el --- 项目管理（project.el）与左侧 Dired 面板 -*- lexical-binding: t; -*-

;;; Commentary:
;; Profiles: full
;; Requires: self-keys, self-windowing, self-tabline
;; Packages: dape
;;
;; 移植自桌面端配置「项目与导航」域（Custom ID: projects，含 project-navigation
;; 与 panel-dired-setup / panel-dired-nav 三段），本模块分两块：
;;
;; 1. 项目管理：基于 Emacs 内置 project.el，自动把 Git 仓库根识别为工程边界，
;;    提供工程切换、文件查找、全文检索、工程内缓冲切换与工程级编译/调试入口。
;; 2. 左侧 Dired 面板：基于 Dired 定制的轻量侧边文件树（宽度 20%，不占标签位），
;;    回车/点击把文件开进主编辑窗口，目录原地切换，支持开关、定位与自动跟随。
;;
;; 阅读要点（原文散文并入此处）：
;;
;; - let* 圈定临时上下文：`self/open-project-folder` 把 `default-directory`
;;   临时指向目标目录再探测项目——`default-directory` 只在 let* 括号内改变值，
;;   出了括号自动复原，这种「划定作用域边界」的写法代替了「先保存、再恢复」的
;;   命令式套路。这里必须用 let*（带星号）：它允许后面的绑定引用同括号内更早的
;;   绑定——dir 先定下来，default-directory 才能指向它；普通 let 的各绑定互相
;;   看不见，只能用括号外已有的值。
;; - 面板就是带参数的窗口：本模块不引入文件树插件，而是把 Dired 缓冲区放进
;;   `(display-buffer-in-side-window (side . left) ...)` 产生的侧边窗口，再用
;;   buffer-local 标记 `self--dired-panel-p` 打上面板标记——据此从标签栏豁免、
;;   并把回车重定向到主窗口打开。理解「Emacs 里一切窗口行为都由 display-buffer
;;   规则决定」后，display-buffer 路由表也就顺带读懂了。
;; - 面板访问语义集中在 `self/dired--panel-visit`：目录不能走
;;   `find-alternate-file`——其内部 switch-to-buffer 会被 side-window 拒绝而把
;;   新 Dired 投到其他窗口，故显式 set-window-buffer 替换面板窗口并 kill 旧面板
;;   buffer；`dired-noselect` 天然复用已存在的同目录 Dired buffer，不堆积。
;;   取行文件名必须用 `dired-get-file-for-visit`：裸 `dired-get-filename` 对 `.`
;;   与 `..` 行会抛 "Cannot operate on '.' or '..'"；鼠标入口先用
;;   `dired-get-filename` 无报错探测，让点在空白处（空行/目录头/点线）的点击
;;   退化为「只聚焦面板」。
;; - 键位内聚的活例子：下面 C-x p 与 C-c c G 两组键位就绑在本模块末尾，而不是
;;   集中放到键位域——功能按键跟随功能实现，是全配置的编排原则。键位本身通过
;;   `self/bind` 声明，机制归属 self-keys 模块。
;;
;; 依赖说明：
;; - self-keys 提供 `self/bind` / `self/declare-binding-group` 键位声明机制。
;; - self-windowing 提供 `self/display-buffer-in-main-window` 与
;;   `self/display-or-focus`（display-buffer 路由）。
;; - self-tabline 提供 `self--tabs-unregister-buffer`；面板标记
;;   `self--dired-panel-p` 由本模块打、由标签栏读取做白名单豁免。
;;
;; 外部依赖：ripgrep CLI（`xref-search-program` 用它做全文检索，非 elisp 包，
;; 不进包后端清单，需在系统里自行安装）。
;;
;; 面板的开关类按键（C-b / C-S-e / C-c w f / C-c w d）不在本域，属键位域的
;; 「基础移动与直达键」「窗口与面板」两组，此处不重复绑定。

;;; Code:

(require 'dired)

;; project.el / xref.el 的 defcustom 不随 Emacs 启动加载，但下面要 setq 它们的
;; 变量、调用 project-root。只在编译期 require：让 byte-compile 认识这些符号与
;; 函数，运行期零成本（project 的命令本来就靠 autoload 延迟加载，变量值由后面
;; 真正 require 时的 defcustom 保留，不会被默认值覆盖）。
(eval-when-compile
  (require 'project)
  (require 'xref))

;; ─── 跨模块符号声明（模块由 manifest 保证已加载，不加 fboundp/boundp 守卫） ──

(declare-function self/bind "self-keys"
                  "按键 KEY 指向 TARGET，DESCRIPTION 为中文说明，GROUP 为分组名。")
(declare-function self/declare-binding-group "self-keys"
                  "声明键位前缀 KEY 的中文说明。")
(declare-function self/display-buffer-in-main-window "self-windowing"
                  "把 BUFFER 显示在主编辑窗口并选中。")
(declare-function self/display-or-focus "self-windowing"
                  "BUFFER 已在某窗口显示则聚焦，否则按 ACTION 创建。")
(declare-function self--tabs-unregister-buffer "self-tabline"
                  "从 FRAME 的标签列表中移除 BUFFER。")
(declare-function dape "dape"
                  "启动 DAP 调试会话。")
(declare-function dired-mouse-find-file "dired"
                  "在 Dired 中用 mouse-2 打开文件（默认行为）。")

;; ─── 项目管理：工程识别与切换 ─────────────────────────────────────────

(defun self/project-root-or-default ()
  "返回当前 project 的 root，不在项目中时返回 `default-directory'。"
  (let ((proj (project-current nil)))
    (if proj
        (project-root proj)
      default-directory)))

(defun self/open-project-folder ()
  "交互式命令：打开任意文件夹。

显示 Dired，并把可识别的项目根注册到已知项目。`default-directory'
只在 let* 内指向目标目录，出括号自动复原，不污染当前 buffer。"
  (interactive)
  (let* ((dir (file-name-as-directory
               (expand-file-name (read-directory-name "项目目录: "))))
         (default-directory dir)
         (project (project-current nil)))
    (when project
      (project-remember-project project))
    (dired dir)))

;; C-x p 弹出带标签的切换菜单：d 打开目录、f 寻找文件、r 搜索关键字、a 执行命令。
(setq project-switch-commands
      '((project-dired "打开目录" ?d)
        (project-find-file "寻找文件" ?f)
        (project-find-regexp "查找关键字" ?r)
        (project-any-command "其他命令" ?a)))

;; 僵尸项目清理：某个项目目录在磁盘上被删除或移动后，自动从已知项目列表剔除。
(setq project-prune-zombie-projects
      '((prompt . project-prune-zombies-default)
        (list-first-read . project-prune-zombies-default)
        (list-write . project-prune-zombies-default)))

;; 全文检索后端：Ripgrep。
(setq xref-search-program 'ripgrep)

;; 目录导航即新标签：在 Dired 中进入子目录时新建目录缓冲区并追加为新标签，
;; 不顶替当前标签；同目录缓冲区由 dired-noselect 天然复用，回访不产生重复标签。
(setq dired-kill-when-opening-new-dired-buffer nil)
(with-eval-after-load 'dired
  (define-key dired-mode-map [mouse-2] #'dired-mouse-find-file))

;; ─── 项目键位：C-x p 前缀与 C-c c G 编译/调试组 ──────────────────────

(self/bind "C-x p b" #'project-switch-to-buffer "切换项目缓冲区" "项目")
(self/bind "C-x p p" #'project-switch-project "切换项目" "项目")
(self/bind "C-x p f" #'project-find-file "查找项目文件" "项目")
(self/bind "C-x p s" #'project-find-regexp "项目全文搜索" "项目")
(self/bind "C-x p o" #'self/open-project-folder "打开项目目录" "项目")
(self/bind "C-x p O" #'dired-jump "目录浏览" "项目")
(self/bind "C-x p k" #'project-kill-buffers "关闭项目缓冲区" "项目")
(self/bind "C-x p D" #'project-dired "项目根 Dired" "项目")
(self/bind "C-x p m" #'project-find-matching-buffer "worktree 对应缓冲区" "项目")
(self/bind "C-x p S" #'project-save-some-buffers "保存本项目缓冲区" "项目")
(self/declare-binding-group "C-c c G" "编译与调试")
(self/bind "C-c c G c" #'project-compile "项目编译" "代码")
(self/bind "C-c c G d" #'gdb "GDB 调试" "代码")
(self/bind "C-c c G r" #'recompile "重新编译" "代码")
(self/bind "C-c c G e" #'dape "DAP 调试" "代码")

;; ─── 左侧 Dired 面板：配置与本地键表 ─────────────────────────────────

(defconst self:dired-side-action
  '(display-buffer-in-side-window
    (side . left) (window-width . 0.2))
  "左侧 Dired 面板的 display-buffer action：宽度 0.2（Zed project panel 比例）。")

(defvar self--dired-panel-p nil
  "非 nil 表示当前 buffer 是左侧 Dired 面板。
buffer-local 标记，由 `self/dired--panel-setup' 打上。
标签栏据此把面板从白名单豁免（面板是导航工具而非内容标签）。")

(defun self/dired--panel-setup (buffer)
  "对 BUFFER 应用面板定制：窄视图、header 路径、面板标记与访问键。

所有 Dired buffer 共享 `dired-mode-map'，面板 remap 必须落在 buffer
私有的 keymap copy 上，否则会污染其他 Dired buffer。
`dired-noselect' 可能复用到已登记为标签的同目录普通 Dired buffer，
打上面板标记后须从所有 frame 的标签列表注销，保证面板永不占标签位。"
  (with-current-buffer buffer
    ;; 精简视图：隐藏文件权限与大小细节，只突出目录与文件名层级。
    (dired-hide-details-mode 1)
    ;; header-line 显示完整路径（窄面板里 Dired 自带的首行放不下）。
    (setq-local header-line-format 'default-directory)
    (setq-local self--dired-panel-p t)
    (dolist (frame (frame-list))
      (self--tabs-unregister-buffer buffer frame))
    ;; 私有键表隔离：复制 dired-mode-map 再重映射，避免污染普通 Dired 窗口。
    (use-local-map (copy-keymap dired-mode-map))
    (define-key (current-local-map) [remap dired-find-file]
                #'self/dired-find-file-in-main)
    (define-key (current-local-map) [remap dired-up-directory]
                #'self/dired-up-in-panel)
    (define-key (current-local-map) [mouse-1]
                #'self/dired-mouse-find-file-in-main)
    (define-key (current-local-map) [mouse-2]
                #'self/dired-mouse-find-file-in-main)))

;; ─── 面板导航与主窗口联动 ───────────────────────────────────────────

(defun self/dired--panel-visit (filename)
  "面板访问语义：目录原地替换面板 buffer，文件进主编辑窗口。

FILENAME 须为绝对路径——`dired-get-file-for-visit' 对 `..' 返回相对名，
调用前先 expand。目录不 `find-alternate-file'（其内部 switch-to-buffer
会被 side-window 拒绝，把新 Dired 投到别的窗口），故显式替换面板窗口并
kill 掉旧面板 buffer。`dired-noselect' 天然复用同目录已有 Dired buffer。"
  (setq filename (expand-file-name filename))
  (if (not (file-directory-p filename))
      (self/display-buffer-in-main-window (find-file-noselect filename))
    (let ((old-buf (current-buffer))
          (new-buf (dired-noselect filename)))
      (unless (eq new-buf old-buf)
        (self/dired--panel-setup new-buf)
        (set-window-buffer nil new-buf)
        (set-buffer new-buf)
        (kill-buffer old-buf)))))

(defun self/dired-find-file-in-main ()
  "面板版 RET：目录原地替换面板 buffer，文件进主编辑窗口。

side-window 内直接 RET 会把文件开进面板，故走本命令改写目标窗口。"
  (interactive)
  (self/dired--panel-visit (dired-get-file-for-visit)))

(defun self/dired-up-in-panel ()
  "面板内回到上级目录（原地替换，保持面板定制）。"
  (interactive)
  (self/dired--panel-visit
   (file-name-directory (directory-file-name (dired-current-directory)))))

(defun self/dired-mouse-find-file-in-main (event)
  "面板版 mouse-1/2：与 `self/dired-find-file-in-main' 同语义。

单击打开对齐 VSCode Explorer；点在非文件行（空行/目录头/点线）退化为
「只聚焦面板」——先用无报错的 `dired-get-filename' 探测。
EVENT 是本次鼠标事件。"
  (interactive "e")
  (let ((window (posn-window (event-end event)))
        (pos (posn-point (event-end event))))
    (unless (windowp window)
      (error "No file chosen"))
    (select-window window)
    (save-excursion
      (goto-char pos)
      (when (dired-get-filename nil t)
        (self/dired--panel-visit (dired-get-file-for-visit))))))

;; ─── 面板开关与定位 ─────────────────────────────────────────────────

(defun self/panel-dired ()
  "打开项目根（不在项目则当前目录）的左侧 Dired 面板。

有已显示的面板窗口则聚焦；buffer 存在则重新显示；无则新建。
窄面板默认隐藏文件详情，header-line 显示完整路径。"
  (interactive)
  (let ((buf (dired-noselect (self/project-root-or-default))))
    (self/dired--panel-setup buf)
    (self/display-or-focus buf self:dired-side-action t)))

(defun self/dired--panel-window-p (window)
  "WINDOW 当前显示的是否为左侧 Dired 面板窗口。

判据是 buffer-local 标记而非 side 窗口参数：用户可能把面板窗口拖出
side 位，标记才是语义来源。"
  (with-current-buffer (window-buffer window)
    (and (derived-mode-p 'dired-mode)
         (bound-and-true-p self--dired-panel-p))))

(defun self/panel-dired-toggle ()
  "开关左侧文件面板（VSCode Ctrl+B）：已显示则收起窗口（buffer 保留），否则打开。"
  (interactive)
  (let ((panels (seq-filter #'self/dired--panel-window-p (window-list))))
    (if panels
        (dolist (window panels)
          (delete-window window))
      (self/panel-dired))))

(defun self/panel-dired-reveal ()
  "把左侧文件面板切到当前文件所在目录并选中该文件（VSCode Explorer Reveal）。

面板 buffer 由 `dired-noselect' 复用/新建后按面板规则重设，再经
`dired-goto-file' 把点定位到文件行。当前缓冲区必须访问了文件。"
  (interactive)
  (unless buffer-file-name
    (user-error "当前缓冲区未访问文件"))
  ;; 必须在切入面板 buffer 之前抓住文件名：Dired buffer 的 buffer-file-name 是 nil。
  ;; 这里必须是 let*：buf 的初始值要引用同一括号里更早绑定的 file。
  (let* ((file buffer-file-name)
         (buf (dired-noselect (file-name-directory file))))
    (self/dired--panel-setup buf)
    (self/display-or-focus buf self:dired-side-action t)
    (with-current-buffer buf
      (dired-goto-file file))))

;; ─── 自动跟随：切换到同目录文件时把面板光标落到对应行 ───────────────

(defun self/panel-dired--auto-reveal (frame)
  "FRAME 内窗口 buffer 变化后，让 Dired 面板跟随当前文件。

仅在文件落在面板当前显示的目录内时移动面板光标（纯 marker 定位，零 I/O）；
文件在其他目录时保持面板现状——Dired 面板只显示单层目录，无法像 Explorer
树那样原地展开，每次切 buffer 都重建视图反而扰人。"
  (dolist (window (window-list frame))
    (with-current-buffer (window-buffer window)
      (when (and (derived-mode-p 'dired-mode)
                 (bound-and-true-p self--dired-panel-p))
        (let ((file (buffer-file-name
                     (window-buffer (frame-selected-window frame)))))
          (when (and file
                     (stringp dired-directory)
                     (equal (file-name-as-directory
                             (expand-file-name dired-directory))
                            (file-name-directory file)))
            (ignore-errors (dired-goto-file file))))))))

;; window-buffer-change-functions 同时接受 frame（全局 hook）与 window
;; （buffer-local hook）；此处挂全局版本，遍历 FRAME 内所有窗口。
(add-hook 'window-buffer-change-functions #'self/panel-dired--auto-reveal)

(provide 'self-project)
;;; self-project.el ends here
