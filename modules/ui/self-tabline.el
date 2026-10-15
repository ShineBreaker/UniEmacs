;;; self-tabline.el --- 桌面标签栏：per-frame 标签跟踪 + IDE 风格渲染 -*- lexical-binding: t; -*-

;;; Commentary:
;; Profiles: full
;; Requires: self-modeline, self-theme
;; Packages: nerd-icons
;;
;; 移植自桌面端配置。基于 Emacs 内置 tab-line 构建轻量稳定的文件标签栏，
;; 与 origin 的 mode-line 共用同一套分屏/routing 思路，但标签体系完全自绘。
;;
;; **为什么不直接用 Emacs 默认的 tab-line？**
;;
;; 原生 tab-line 会把当前窗口模式下的所有缓冲区（Scratch、内部日志、
;; 补全列表、终端等）全摆进标签栏，视觉杂乱且多窗口分屏时互相干扰。
;; 这里的方案实现了类似现代 IDE 的标签栏逻辑：
;;
;; 1. *只对文件与目录生效*：`self/tab-visible-p` 白名单过滤，终端、
;;    帮助、Scratch、Dashboard 与左侧文件面板等窗口不绘制标签栏。
;; 2. *多客户端独立隔离*：daemon 架构下每个 Frame 独立维护自己的标签
;;    序列（存在 frame 参数 `self--frame-tab-buffers` 中），互不干扰。
;; 3. *顺序稳定*：新文件一律追加到尾部，绝不顶替既有标签；支持鼠标
;;    点击关闭、快捷键循环切换，以及按键连按重排。
;;
;; **标签列表的生命周期流转**
;;
;; - *打开并显示文件或目录*：由 `window-buffer-change-functions` 统一
;;   捕获，首次显示时追加到该 Frame 标签列表尾部并去重。所有打开入口
;;   （find-file、project-find-file、Dired、面板跳转等）一律追加为新标签。
;; - *关闭缓冲区*：`kill-buffer-hook` 从所有 Frame 的列表中统一移除。
;; - *关闭窗口*：Frame 销毁时自动丢弃该 Frame 关联的列表。
;; - *切换项目*：不清空标签——切工程只是打开新文件或目录，既有标签
;;   原样保留；需要手动清场时 M-x self/tabs-clear-for-frame。
;;
;; **渲染格式的设计取舍**（self/tab-line-tab-name-format）
;;
;; face 选择交给内置 `tab-line-tab-face-functions` 而不手动构造 RGB
;; plist，current/inactive 用内置 face 自动跟随主题；标签之间不加分隔
;; 符——选中与非选中各自的底色块已足够区分，buffer 间分隔线由 window
;; divider 负责。标签正文是 " name "（前后留空格、% 转义防
;; format-mode-line 吃掉），带 mouse-face（仅非选中标签）与 help-echo；
;; 渲染 face 统一归一成 (:box nil . ...) 列表抹掉盒线后再上色。关闭按钮
;; 仅在选中标签渲染（`tab-line-close-button-show` 为 'selected）；按钮
;; 模板串是全局共享的，先复制再盖 face。
;;
;; **按钮与 face 策略**
;;
;; - 当前标签继承 mode-line 的前景色与半粗体；非当前标签继承 shadow。
;; - 标签之间不加分隔符，两块底色本身已把选中/非选中分开。
;; - 标签栏下缘横线由 `self/apply-tab-line-divider` 在主题加载/切换时
;;   重算，颜色取主题 border 与正文底色之间的插值，比纯 border 更淡。
;; - 未选中窗口由 Emacs 31 的 `tab-line-inactive` 自动变暗；TTY 环境下
;;   的透明背景策略由主题域统一处理。
;;
;; **hook 注册的时序**：`tab-line-exclude-buffers`（Emacs 31 机制）必须
;; 在 `global-tab-line-mode` 启用之前配置好，否则终端、帮助、Dashboard
;; 与左侧文件面板窗口会被错误启用标签栏。

;;; Code:

(require 'tab-line)
(tab-bar-mode -1)

;; 跨域符号就近声明（Nerd 图标来自外观域的 modeline 模块，终端取色
;; 来自主题域；模块由 manifest 保证已加载，不用 fboundp 守卫）。
;; 定义在 core/self-lib.el（跨模块共享能力变量），此处只声明。
(defvar self:nerd-icons-available)
(declare-function nerd-icons-icon-for-buffer "nerd-icons")
(declare-function self/terminal-theme-color "self-theme")

;; ─── 常量与窗口定位 ────────────────────────────────────────────────

(defconst self:tabs-name-max-width 36
  "单个标签名最大宽度。")

(defconst self:tab-line-height-display
  '(space :width (0) :height (+ height (8)) :ascent 75)
  "零宽标签高度 spacer；恢复原 4px box 提供的上下留白。")

(defvar-local self/tab-line--name-cache nil
  "当前 buffer 的 tab-line 标签名缓存。")

(defvar-local self--dired-panel-p nil
  "非 nil 表示本 Dired buffer 是左侧文件面板，不占标签位。
由项目导航域的 `self/dired--panel-setup' 设置。")

(defun self/tab-visible-p (buffer)
  "判断 BUFFER 是否应该显示在标签栏中。
白名单机制：关联文件的 buffer 与普通 Dired buffer 是合法标签；
面板 Dired（带 `self--dired-panel-p' 标记，属导航面板而非内容标签）
与终端、帮助等非内容 buffer 除外。"
  (and (buffer-live-p buffer)
       (not (buffer-local-value 'self--dired-panel-p buffer))
       (or (buffer-file-name buffer)
           (with-current-buffer buffer (derived-mode-p 'dired-mode)))))

(defun self--tab-line-exclude-non-tab-buffer (&optional buffer)
  "不占标签位的 BUFFER 所在窗口不启用 tab-line，返回非 nil 表示排除。
作为 `tab-line-exclude-buffers' 的 `buffer-match-p' 谓词条件
（Emacs 31 机制，接收 buffer 名或 buffer 对象），使标签栏只渲染在
`self/tab-visible-p' 为真的 buffer 所在 window；终端模拟器、scratch、
help、Dashboard 与左侧文件面板等 window 因此不显示标签栏。"
  (not (self/tab-visible-p (get-buffer (or buffer (current-buffer))))))

(defun self--tabs-target-window (&optional window)
  "返回标签命令应优先操作的 WINDOW，缺省当前窗口。
所有调用点的 WINDOW 实参都来自即时枚举（selected-window 或本函数
返回值的透传），恒存活，不做 live 检查。"
  (or window (selected-window)))

;; ─── Per-frame 缓冲区跟踪 ─────────────────────────────────────────
;;
;; 注册与注销采用对称设计：注册仅在尾部追加（保持稳定顺序），注销
;; 负责安全移除，不直接对编辑窗口产生副作用。

(defun self--tabs-get-frame-buffer-list (&optional frame)
  "返回 FRAME 的标签缓冲区列表。"
  (frame-parameter (or frame (selected-frame)) 'self--frame-tab-buffers))

(defun self--tabs-set-frame-buffer-list (buffers &optional frame)
  "设置 FRAME 的标签缓冲区列表为 BUFFERS。"
  (set-frame-parameter (or frame (selected-frame)) 'self--frame-tab-buffers buffers))

(defun self--tabs-should-track-p (buffer)
  "BUFFER 是否应进入标签列表：是合法标签（文件或普通 Dired）、存活、非 minibuffer。
`self/tab-visible-p' 已含存活检查，此处只补 minibuffer 排除。"
  (and (self/tab-visible-p buffer)
       (not (minibufferp buffer))))

(defun self--tabs-register-buffer (buffer &optional frame)
  "将 BUFFER 注册到 FRAME 的标签列表尾部（去重）。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (self--tabs-get-frame-buffer-list target-frame)))
    (unless (memq buffer buffers)
      (self--tabs-set-frame-buffer-list
       (append buffers (list buffer))
       target-frame))))

(defun self--tabs-unregister-buffer (buffer &optional frame)
  "从 FRAME 的标签列表中移除 BUFFER。"
  (let* ((target-frame (or frame (selected-frame)))
         (buffers (self--tabs-get-frame-buffer-list target-frame)))
    (when (memq buffer buffers)
      (self--tabs-set-frame-buffer-list
       (delq buffer buffers)
       target-frame))))

;; 标签列表的唯一注册入口，不依赖 find-file-hook / server-switch-hook：
;; FRAME-OR-WINDOW 既可能是 frame（全局 hook 场景），也可能是 window
;; （buffer-local 场景）。
(defun self--tabs-on-window-buffer-change (frame-or-window)
  "缓冲区变更时，把新缓冲区注册到对应 frame。"
  (cond
   ((frame-live-p frame-or-window)
    (walk-windows
     (lambda (window)
       (let ((buffer (window-buffer window)))
         (when (self--tabs-should-track-p buffer)
           (self--tabs-register-buffer buffer frame-or-window))))
     'no-mini frame-or-window))
   ((window-live-p frame-or-window)
    (let ((buffer (window-buffer frame-or-window))
          (frame (window-frame frame-or-window)))
      (when (self--tabs-should-track-p buffer)
        (self--tabs-register-buffer buffer frame))))))

(defun self--tabs-on-kill-buffer ()
  "缓冲区被关闭时，从所有 frame 的标签列表中移除。"
  (dolist (frame (frame-list))
    (self--tabs-unregister-buffer (current-buffer) frame)))

(defun self/tabs-clear-for-frame (&optional frame)
  "清空 FRAME 的标签缓冲区列表（手动清场命令，M-x 调用）。
只清 frame parameter，不重建；后续 window-buffer-change 自然填充。"
  (interactive)
  (let ((target-frame (or frame (selected-frame))))
    (self--tabs-set-frame-buffer-list nil target-frame)
    (walk-windows
     (lambda (window)
       (set-window-parameter window 'tab-line-cache nil))
     'no-mini target-frame)
    (when (called-interactively-p 'interactive)
      (message "已清空当前 frame 的标签列表"))))

(defun self--tabs-on-frame-deletion (frame)
  "FRAME 删除时清理标签状态。
TTY client 断开时 tty frame 可能已被先行删除，钩子拿到的是 dead frame
对象（`set-frame-parameter' 会报 wrong-type-argument frame-live-p，被
Emacs 的 safe_call 静音）；dead frame 的参数随之销毁，无需再清，故先判存活。"
  (when (frame-live-p frame)
    (self--tabs-set-frame-buffer-list nil frame)))

(defun self--tabs-frame-buffers (&optional window)
  "返回 WINDOW 所在 frame 的存活 + 可见缓冲区列表（按白名单筛选）。"
  (let* ((target-window (self--tabs-target-window window))
         (target-frame (window-frame target-window))
         (frame-buffers (self--tabs-get-frame-buffer-list target-frame)))
    (seq-filter #'self/tab-visible-p frame-buffers)))

;; ─── 标签渲染 ──────────────────────────────────────────────────────
;;
;; · *文件图标*：Nerd Font 可用时按文件类型在左侧渲染对应图标。
;; · *修改提示*：内容有修改未保存时，标签名右侧追加实心圆点（●）。
;; · *长名截断*：超过上限的标签名自适应截断，防止横向撑破标签栏。
;; · *语义样式*：配色完全跟随当前主题，不硬编码任何显式 RGB 颜色。
;; · *钩子与关闭按钮约束*：`self/tab-line-tabs' 是唯一源头，只产出有效
;;   缓冲区，因此传给 `tab-line-tab-face-functions' 的 BUFFER-P 实参恒
;;   为 t；关闭按钮只绑定在当前选中的标签上渲染。

(defun self/tab-line-tabs ()
  "返回当前窗口标签栏要展示的 buffer 列表。"
  (or (self--tabs-frame-buffers (selected-window))
      (list (current-buffer))))

(defun self/tab-line-tab-name (buffer &optional _buffers)
  "生成 BUFFER 的标签名（图标 + 名称 + 修改标记）。
标签名按 buffer 名、文件名、major-mode 与修改状态组成的 key 缓存到
`self/tab-line--name-cache'，未变化时直接复用，避免每次 redisplay 重复
做截断与图标查询。"
  (with-current-buffer buffer
    (let ((key (list (buffer-name) buffer-file-name major-mode
                     (buffer-modified-p))))
      (if (equal key (car-safe self/tab-line--name-cache))
          (cdr self/tab-line--name-cache)
        (let* ((name (truncate-string-to-width
                      (buffer-name)
                      self:tabs-name-max-width 0 nil t))
               (icon (when self:nerd-icons-available
                       (nerd-icons-icon-for-buffer)))
               (prefix (if (and (stringp icon)
                                (not (string-empty-p icon)))
                           (concat icon " ")
                         ""))
               (suffix (if (buffer-modified-p) " ●" ""))
               (label (concat prefix name suffix)))
          (setq self/tab-line--name-cache (cons key label))
          label)))))

(defun self/tab-line-tab-name-format (tab tabs)
  "以接近 IDE 的样式格式化 TAB（设计取舍见文件头 Commentary）。"
  (let* ((selected-p (eq tab (window-buffer)))
         (name (funcall tab-line-tab-name-function tab tabs))
         (face (if selected-p 'tab-line-tab-current 'tab-line-tab-inactive))
         (label
          (propertize (concat " " (string-replace "%" "%%" name) " ")
                      'mouse-face (unless selected-p 'tab-line-highlight)
                      'help-echo (concat (if selected-p "当前标签:" "左键切换标签,")
                                         "鼠标中键关闭,右键打开菜单"))))
    (dolist (fn tab-line-tab-face-functions)
      (setq face (funcall fn tab tabs face t selected-p)))
    (let* ((render-face
            (if (and (listp face) (not (keywordp (car-safe face))))
                (cons '(:box nil) face)
              (list '(:box nil) face)))
           (spacer
            (propertize " "
                        'face render-face
                        'display self:tab-line-height-display))
           (close (when selected-p
                    (let ((button (copy-sequence tab-line-close-button)))
                      (add-face-text-property
                       0 (length button) render-face t button)
                      button)))
           (rendered
            (concat
             spacer
             (propertize label
                         'face render-face
                         'keymap tab-line-tab-map
                         'follow-link 'ignore)
             close)))
      (add-text-properties
       0 (length rendered)
       `(tab ,tab ,@(and selected-p '(selected t)))
       rendered)
      rendered)))

;; ─── 按钮与 Face ───────────────────────────────────────────────────

(defun self/apply-tab-line-button-preset ()
  "应用统一的标签栏按钮文本样式。
关闭按钮悬停继承 error（警示红），滚动按钮悬停继承 mode-line-highlight。"
  (setq tab-line-close-button
        (propertize "x "
                    'rear-nonsticky nil
                    'keymap tab-line-tab-close-map
                    'mouse-face 'tab-line-close-highlight
                    'help-echo "关闭标签")
        tab-line-left-button
        (propertize " < "
                    'rear-nonsticky nil
                    'keymap tab-line-left-map
                    'mouse-face 'tab-line-highlight
                    'help-echo "向左滚动标签栏")
        tab-line-right-button
        (propertize " > "
                    'rear-nonsticky nil
                    'keymap tab-line-right-map
                    'mouse-face 'tab-line-highlight
                    'help-echo "向右滚动标签栏")))

(set-face-attribute 'tab-line nil
                    :inherit nil
                    :height 0.95
                    :box nil
                    :overline nil
                    :underline nil)
(set-face-attribute 'tab-line-tab-current nil
                    :inherit 'mode-line
                    :weight 'semibold
                    :box nil)
(set-face-attribute 'tab-line-tab-inactive nil
                    :inherit 'shadow
                    :box nil)
(set-face-attribute 'tab-line-highlight nil
                    :inherit 'mode-line-highlight
                    :box nil)
(set-face-attribute 'tab-line-close-highlight nil
                    :inherit 'error
                    :background 'unspecified
                    :box nil
                    :underline nil)

;; Emacs 31 提供窗口级 tab-line-inactive 样式：非活动窗口的整条标签栏
;; 自动变暗，与标签级的 current/inactive 形成互补。
(set-face-attribute 'tab-line-inactive nil
                    :inherit '(tab-line shadow))
(set-face-attribute 'tab-line-active nil
                    :inherit 'tab-line)

;; 标签栏下缘横线用的是贴在文本下缘的细下划线而非盒模型（盒线无法只画
;; 单边），落在标签与填充空白两类 face 上故整行连续；颜色在主题 border
;; 与正文底色之间按通道插值，比纯 border 更淡。插值 helper 与主题取色都
;; 由 self-theme.el 提供（窗口分隔线用的是同一对函数），此处只消费。
(declare-function self--mix-color "self-theme")

;; 分隔符颜色必须跟随主题，而本域早于主题域的 load-theme 求值，故属性
;; 统一交给这个函数在主题加载/切换时重算（enable-theme-functions）。
;; palette 取不到色时保留既有属性，不改 face。
(defun self/apply-tab-line-divider (&rest _)
  "按当前主题重算标签栏下缘的横线（挂在 `enable-theme-functions' 上）。"
  (when-let* ((border (self/terminal-theme-color 'border))
              (bg (self/terminal-theme-color 'bg-main)))
    (dolist (face '(tab-line tab-line-tab-current tab-line-tab-inactive
                             tab-line-highlight tab-line-close-highlight))
      (set-face-attribute face nil
                          :underline (list :color (self--mix-color border bg 0.5)
                                           :position t)))))

(add-hook 'enable-theme-functions #'self/apply-tab-line-divider)

;; ─── 标签操作 ──────────────────────────────────────────────────────
;;
;; · *隐藏而非杀死*：关闭标签执行的是 bury-buffer 并从列表注销，保留
;;   缓冲区内容供最近文件或后续跳转使用；真正 kill 文件缓冲区用 C-x k。
;; · *快捷键切换*：`self/tabs-next' / `self/tabs-previous' 在当前 Frame
;;   的标签序列中循环跳转。
;; · *稳定重排与按键连按*：官方的 `tab-line-move-tab-forward' 只对内置
;;   固定窗口生效，对多 Frame 驱动的标签体系是静默 no-op，故这里直接
;;   操作 Frame 列表实现位置调整，并接入 `self/tabs-repeat-map'（需
;;   `repeat-mode'），按下快捷键后连按 n / p / m 即可持续切换或移动。
;;
;; `self--tabs-switch-to-buffer' 自身不做存活检查：tabs-next/prev 的实参
;; 来自 kill-buffer-hook 即时清理过的 frame 列表，close-buffer 的实参经
;; `self--tabs-visible-other-p'（内含 `self/tab-visible-p' 的存活检查）
;; 过滤。

(defun self--tabs-switch-to-buffer (buffer &optional window)
  "在 WINDOW 中切换到 BUFFER，并刷新标签显示。调用方保证 BUFFER 存活。"
  (let ((target-window (self--tabs-target-window window))
        (switch-to-buffer-obey-display-actions nil))
    (with-selected-window target-window
      (switch-to-buffer buffer)
      (tab-line-force-update t))))

(defun self/tabs-next (&optional arg)
  "切换到当前标签列表中的下一个标签。ARG 为步数。"
  (interactive "p")
  (let* ((target-window (self--tabs-target-window))
         (buffers (self--tabs-frame-buffers target-window))
         (current (window-buffer target-window))
         (position (seq-position buffers current))
         (step (or arg 1)))
    (when (and position buffers)
      (self--tabs-switch-to-buffer
       (nth (mod (+ position step) (length buffers)) buffers)
       target-window))))

(defun self/tabs-previous (&optional arg)
  "切换到当前标签列表中的上一个标签。ARG 为步数。"
  (interactive "p")
  (self/tabs-next (- (or arg 1))))

;; 关闭路径：显式 BUFFER 实参只来自鼠标回调（已先行存活检查），窗口
;; 当前 buffer 恒存活，故内部不再重复守卫；`self/tab-line-close-tab' 是
;; 鼠标关闭按钮入口，与键盘路径语义对称。
(defun self--tabs-visible-other-p (candidate target-buffer)
  "CANDIDATE 是否可作 TARGET-BUFFER 关闭后的接替标签：存活且可见且非自身。"
  (and (self/tab-visible-p candidate)
       (not (eq candidate target-buffer))))

(defun self--tabs-other-buffer-p (buffer)
  "BUFFER 是否可作当前窗口标签的接替：与当前 buffer 不同。"
  (not (eq buffer (window-buffer))))

(defun self/tabs-close-buffer (&optional window buffer)
  "在 WINDOW 隐藏 BUFFER 的标签（bury + unregister，不 kill buffer）。
BUFFER 默认为 WINDOW 当前显示的 buffer：窗口 buffer 恒存活，显式
BUFFER 的唯一调用方 mouse 回调已先行存活检查，不再重复守卫。"
  (interactive)
  (let* ((target-window (self--tabs-target-window window))
         (target-buffer (or buffer (window-buffer target-window)))
         (target-frame (window-frame target-window)))
    (self--tabs-unregister-buffer target-buffer target-frame)
    (when (eq target-buffer (window-buffer target-window))
      (if-let* ((next (seq-find (lambda (candidate)
                                  (self--tabs-visible-other-p
                                   candidate target-buffer))
                                (self--tabs-get-frame-buffer-list target-frame))))
          (self--tabs-switch-to-buffer next target-window)
        (with-selected-window target-window
          (bury-buffer target-buffer)
          (let ((fallback
                 (seq-find #'self--tabs-other-buffer-p
                           (buffer-list target-frame))))
            (when fallback
              (switch-to-buffer fallback))))))
    (tab-line-force-update t)))

(defun self/tab-line-close-tab (tab)
  "鼠标关闭按钮回调：与键盘 close 走同一路径（语义对称）。"
  (interactive)
  (let ((buffer (if (bufferp tab) tab (current-buffer))))
    (when (buffer-live-p buffer)
      (self/tabs-close-buffer (self--tabs-target-window) buffer))))

(defun self/tabs-move (&optional arg)
  "把当前标签在 frame 标签列表中移动 ARG 位（正向后移，负值前移）。"
  (interactive "p")
  (let* ((frame (selected-frame))
         (buffers (self--tabs-get-frame-buffer-list frame))
         (buffer (current-buffer))
         (pos (seq-position buffers buffer)))
    (when (and pos (> (length buffers) 1))
      (let* ((rest (delq buffer buffers))
             (new-pos (mod (+ pos (or arg 1)) (length buffers))))
        (self--tabs-set-frame-buffer-list
         (append (seq-take rest new-pos)
                 (list buffer)
                 (seq-drop rest new-pos))
         frame)
        (tab-line-force-update t)))))

(defun self/tabs-move-backward (&optional arg)
  "把当前标签在 frame 标签列表中前移 ARG 位。"
  (interactive "p")
  (self/tabs-move (- (or arg 1))))

(defvar self/tabs-repeat-map (make-sparse-keymap)
  "标签栏连按表：一次快捷键后可连按 n / p / m 持续切换或移动。")

;; 官方 tab-line-move-tab-forward 对本体系是静默 no-op，故 n / p / m 绑到
;; 自己的等价命令上（n/p 切换、m 前移）。
(dolist (pair '((?n . self/tabs-next)
                (?p . self/tabs-previous)
                (?m . self/tabs-move)))
  (define-key self/tabs-repeat-map (char-to-string (car pair)) (cdr pair))
  (put (cdr pair) 'repeat-map 'self/tabs-repeat-map))

;; ─── 全局启用与 Hook 注册 ──────────────────────────────────────────
;;
;; 内置分隔符置空：标签间的间隔由自绘样式控制，防止终端下出现杂乱竖线。

(setq tab-line-tabs-function #'self/tab-line-tabs
      tab-line-tab-name-function #'self/tab-line-tab-name
      tab-line-tab-name-format-function #'self/tab-line-tab-name-format
      tab-line-close-tab-function #'self/tab-line-close-tab
      tab-line-close-button-show 'selected
      tab-line-new-button-show nil
      tab-line-switch-cycling t
      tab-line-separator "")

(self/apply-tab-line-button-preset)

(setq tab-line-exclude-buffers
      #'self--tab-line-exclude-non-tab-buffer)

(global-tab-line-mode 1)

(add-hook 'window-buffer-change-functions #'self--tabs-on-window-buffer-change)
(add-hook 'kill-buffer-hook #'self--tabs-on-kill-buffer)
(add-hook 'delete-frame-functions #'self--tabs-on-frame-deletion)

(provide 'self-tabline)
;;; self-tabline.el ends here
