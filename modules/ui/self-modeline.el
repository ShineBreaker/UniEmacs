;;; self-modeline.el --- 无窗口状态栏：底部 Minibuffer 状态行（Starship 风格） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: 无
;; Packages: minibuffer-line, nerd-icons, eglot
;;
;; 移植自桌面端配置的「Modeline」大节（原 CUSTOM_ID：modeline /
;; modeline-core / modeline-helpers / modeline-segments /
;; modeline-render / modeline-refresh / modeline-messages）。
;;
;; 设计：无窗口状态栏。全局把 `mode-line-format' 置 nil 省掉每个分屏的
;; 一行纵向空间，状态信息全部收拢到屏幕最底部的 *Minibuf-0*：Minibuffer
;; 空闲时该 buffer 的内容即 echo area 的显示内容。
;;
;; 整条管线分四段，逐段对应下面各小节：
;;
;; 1. *数据*  —— Flymake 计数、Eglot 连接、VC 状态、project 根目录全部在
;;    对应事件的 hook 里算好，写进 buffer-local 变量；渲染路径只读内存，
;;    热路径零 I/O、零子进程、零同步阻塞。
;; 2. *格式化*  —— 十几个「段函数」各自接收一个尺寸档位，返回一段带 face
;;    的短字符串，不适用就返回空串；`self/modeline--join' 负责过滤空串
;;    并用 Starship 风格分隔符连接。
;; 3. *渲染*  —— `self/modeline--render' 按固定顺序拼左右两段，中间塞一个
;;    带 `(space :align-to)' 的特殊空格做动态右对齐；左段超宽时优先截断
;;    左段，保证右段系统状态永远完整贴右缘。
;; 4. *刷新*  —— 1 秒普通定时器兜底 + post-command / 窗口尺寸变化钩子；
;;    写入前与 buffer 实际内容比较（`equal' 连文本属性一起比），相同就
;;    跳过 erase/insert，空闲期不做无谓的 redisplay 置位。
;;
;; 响应式档位由 `self/modeline-tier' 按 frame 总宽度判定（状态行横跨整个
;; frame，所以按 frame 宽而非窗口宽划分）：
;;
;;   wide   (>=160 列) 全部细节，时间显示到秒
;;   medium (>=120 列) 收敛部分指示，时间只到分
;;   narrow (>=80 列)  隐藏部分状态段
;;   compact (<80 列)  只留 major mode 名字
;;
;; 留白由 `self:modeline-padding' 控制（两侧一致，下限 1）：右缘末列是
;; 强制保留位，GUI 会在右 fringe 画溢出箭头（`overflow-newline-into-fringe'），
;; TTY 会在末列画截断符号，而状态行右段永远贴右缘必中这个标记，所以
;; `self/modeline--usable-width' 统一再减一列根治。
;;
;; 图标统一走 nerd-icons（Nerd Font 私用区），取到后一律
;; `substring-no-properties' 剥掉字体属性：图标 face 的 family 一旦进入
;; echo area 文本，GUI 会把整行渲染成豆腐块，故去属性后由默认字体渲染
;; （其本身带图标字形），着色交给各段的语义 face。图标结果进哈希表缓存，
;; 条目数达到 `self/modeline--icon-cache-limit' 时整体清空。
;;
;; 消息接管：`set-message-functions' 里的 `self/modeline--handle-message'
;; 把「Eglot 连接成功」「Wrote foo.el」这类单行短提示并入左半段（右侧
;; 系统状态保持可见），超过半宽则退回 Emacs 默认整行显示；短消息在下
;; 一次键盘输入（pre-command）或 4 秒后撤下。记录的是并入时刻而非空闲
;; 时长——daemon 长时间空闲时 `current-idle-time' 早已远超阈值，若按空闲
;; 时长算，刚并入的消息会被立刻撤掉。
;;
;; 图标资产（data/icons/）由 self-glyph 统一加载，本模块只用 nerd-icons
;; 的字体图标，不直接引用该目录的路径。

;;; Code:

;; ─── 架构与基础尺寸 ───────────────────────────────────────────────

(defgroup self-modeline nil
  "底部状态行的可定制项。
用 M-x customize-group RET self-modeline 浏览本模块全部 defcustom。"
  :group 'self)

;; 无窗口状态栏：状态信息全部交给底部的 *Minibuf-0* 承载。
(setq-default mode-line-format nil)

;; subr-x 提供 string-empty-p / string-search / string-remove-prefix；
;; warnings 提供按 severity 分类用的 warning-numeric-level。两者都不是
;; 预加载库，不显式 require 在裸 batch 里会报「函数未定义」。
(require 'subr-x)
(require 'warnings)
(require 'battery)
(require 'project)

(declare-function nerd-icons-icon-for-file "nerd-icons")
(declare-function nerd-icons-faicon "nerd-icons")
(declare-function nerd-icons-mdicon "nerd-icons")

;; `self:nerd-icons-available' 的唯一定义在 core/self-lib.el（跨模块
;; 共享能力变量）；此处只声明不赋值。
(defvar self:nerd-icons-available)

;; 渲染状态放在最前面声明：段求值、刷新调度、消息接管三段都要读它，
; 声明放在用点之后会触发 byte-compile 的自由变量告警。
(defvar self/modeline--target-window nil
  "本次渲染的目标窗口；nil 表示用选中窗口。
按 frame 刷新时把该 frame 的选中窗口动态绑到这里，使段求值与
%l/%c 的窗口上下文一致。")

(defvar self/modeline--message nil
  "当前并入状态行左半的短消息；nil 表示左半显示常规信息。")

(defvar self/modeline--message-time nil
  "短消息并入左半的时刻；`self/modeline--tick' 据此在 4 秒后撤下。")

(defvar self/modeline--rendering nil
  "状态行渲染期标志；渲染途中求值的组件若发消息，退化为整行显示以避免递归。")

(defcustom self:modeline-padding 1
  "状态行左右两侧的留白列数，两侧一致。
下限为 1：右缘末列是强制保留位（写满会触发溢出/截断标记，见
`self/modeline--usable-width'），无法再压缩。"
  :type 'integer
  :group 'self-modeline)

(defcustom self:modeline-show-time t
  "是否在状态行右段显示时间。"
  :type 'boolean
  :group 'self-modeline)

(defcustom self:modeline-show-vcs t
  "是否在状态行显示 VC 分支与状态。"
  :type 'boolean
  :group 'self-modeline)

(defcustom self:modeline-path-max-width 40
  "路径段最大显示宽度。"
  :type 'integer
  :group 'self-modeline)

(defvar self/modeline--icon-cache (make-hash-table :test #'equal)
  "状态行静态图标缓存。")

(defconst self/modeline--icon-cache-limit 256
  "图标缓存的最大条目数。")

(defvar-local self/modeline--flymake-counts '(0 0)
  "当前 buffer 的 Flymake 诊断计数 (ERRORS WARNINGS)。")

(defvar-local self/modeline--eglot-info nil
  "当前 buffer 的 Eglot 连接状态；t 表示已连接。")

(defvar-local self/modeline--project-cache :unknown
  "当前 buffer 的 (ROOT NAME)；:unknown 表示待重算。")

(defvar-local self/modeline--vc-state-cache :unknown
  "当前 buffer 的 VC 状态；:unknown 表示待重算。")

(defvar-local self/modeline--path-cache nil
  "路径段的缓存，形如 (KEY . SEGMENT)。")

(defvar-local self/modeline--name-cache nil
  "buffer 名段的缓存，形如 (KEY . SEGMENT)。")

(defun self/modeline-tier (window)
  "按 WINDOW 所在 frame 的宽度返回 wide、medium、narrow 或 compact。
状态行横跨整个 frame，档位按 frame 宽而非窗口宽划分。"
  (let ((width (window-total-width
                (minibuffer-window (window-frame window)))))
    (cond
     ((>= width 160) 'wide)
     ((>= width 120) 'medium)
     ((>= width 80) 'narrow)
     (t 'compact))))

;; ─── 图标与缓存辅助 ───────────────────────────────────────────────

(declare-function flymake--severity "flymake")

(defun self/modeline--icon (name &optional file)
  "返回去属性的 Nerd Font 图标 NAME；FILE 非 nil 时按文件类型取图标。
NAME 是 nerd-icons 图标名：\"nf-fa-*\" 前缀分发到 nerd-icons-faicon，
其余交给 nerd-icons-mdicon。出错时返回空串。"
  (if self:nerd-icons-available
      (let* ((key (if (and file (stringp file))
                      (list name (file-name-nondirectory file))
                    name))
             (cached (gethash key self/modeline--icon-cache :missing)))
        (if (not (eq cached :missing))
            cached
          (let ((icon
                 (substring-no-properties
                  (or (ignore-errors
                        (cond
                         ((and file (stringp file))
                          (nerd-icons-icon-for-file file))
                         ((string-prefix-p "nf-fa-" name)
                          (nerd-icons-faicon name))
                         (t
                          (nerd-icons-mdicon name))))
                      ""))))
            ;; 达到上限就整体清空：图标是有限集合，一次性重建比分代淘汰简单。
            (when (>= (hash-table-count self/modeline--icon-cache)
                      self/modeline--icon-cache-limit)
              (clrhash self/modeline--icon-cache))
            (puthash key icon self/modeline--icon-cache)
            icon)))
    ""))

(defun self/modeline--with-icon (icon text)
  "组合 ICON 与 TEXT；任一为空则只返回另一个。"
  (cond
   ((string-empty-p icon) (or text ""))
   ((string-empty-p text) icon)
   (t (concat icon " " text))))

(defun self/modeline--segment (text face)
  "用 FACE 呈现非空 TEXT；TEXT 为空串时返回空串（该段不占位）。"
  (if (string-empty-p text)
      ""
    (propertize text 'face face)))

(defun self/modeline--join (&rest segments)
  "以 Starship 风格分隔符连接非空 SEGMENTS。"
  (string-join (seq-filter
                (lambda (segment)
                  (and (stringp segment) (not (string-empty-p segment))))
                segments)
               " · "))

;; 路径缩写：父目录缩成首字母，当前工程名与文件名保持完整。

(defun self/modeline--path-part-initials (part)
  "把单个路径分量 PART 缩成首字母。
隐藏目录保留前导点：单独的 `.` 保持为 `.`，`.config` 缩为 `.c`——
否则 `string-join' 会留下悬空的 `/`。"
  (if (string-prefix-p "." part)
      (let ((rest (string-remove-prefix "." part)))
        (if (string-empty-p rest)
            "."
          (concat "." (substring rest 0 1))))
    (substring part 0 1)))

(defun self/modeline--path-initials (path)
  "把 PATH 的目录部分缩成首字母。
TRAMP 远程前缀原样保留，只缩本地部分。"
  (let* ((remote (or (file-remote-p path) ""))
         (local (or (file-remote-p path 'localname) path))
         (parts (split-string
                 (string-remove-prefix
                  "~/" (abbreviate-file-name (directory-file-name local)))
                 "/" t))
         (short nil))
    (dolist (part parts)
      (push (self/modeline--path-part-initials part) short))
    (concat remote (string-join (nreverse short) "/"))))

;; 状态缓存刷新：全部在事件 hook 里主动更新，渲染时只读内存。

;; flymake 在 Emacs 32 里是内建库但并非预加载；eglot 是第三方包。
;; 两者都用 with-eval-after-load 挂钩子，故在此声明编译期可见的符号。
(declare-function flymake-diagnostic-type "flymake")
(declare-function eglot-current-server "eglot")

(defun self/modeline--project-info ()
  "返回当前 buffer 的 (ROOT NAME) project 缓存。"
  (when (eq self/modeline--project-cache :unknown)
    (setq self/modeline--project-cache
          (when-let* ((project (project-current nil))
                      (root (project-root project)))
            (list root
                  (file-name-nondirectory (directory-file-name root))))))
  self/modeline--project-cache)

(defun self/modeline--reset-project-cache (&rest _)
  "失效当前 buffer 的 project 缓存。"
  (setq self/modeline--project-cache :unknown
        self/modeline--path-cache nil))

(defun self/modeline--refresh-vc-state (&rest _)
  "通过 VC 公开接口刷新当前 buffer 的状态缓存。"
  (setq self/modeline--vc-state-cache
        (when-let* ((backend (and buffer-file-name
                                  (vc-backend buffer-file-name))))
          (vc-state buffer-file-name backend))))

(defun self/modeline--refresh-flymake-counts (&rest _)
  "刷新错误与警告计数。
严重度经 `flymake--severity' 按类型查询：error 级入 ERRORS，
warning 级入 WARNINGS，note/debug 级不计。Flymake 公开 API 没有
「按类型取严重度」的函数，它自己的 mode-line 计数也走这个私有
函数，是本功能唯一能与内置计数对齐的口径。"
  (setq self/modeline--flymake-counts
        (if (bound-and-true-p flymake-mode)
            (let ((errors 0)
                  (warnings 0))
              (dolist (diagnostic (flymake-diagnostics))
                (let ((severity
                       (flymake--severity
                        (flymake-diagnostic-type diagnostic))))
                  (cond
                   ((>= severity (warning-numeric-level :error))
                    (setq errors (1+ errors)))
                   ((>= severity (warning-numeric-level :warning))
                    (setq warnings (1+ warnings))))))
              (list errors warnings))
          '(0 0))))

(defun self/modeline--refresh-eglot-info (&rest _)
  "通过 Eglot 公开接口刷新连接状态缓存（仅记录是否已连接）。"
  (setq self/modeline--eglot-info
        (and (ignore-errors (eglot-current-server)) t)))

;; ─── 状态段求值与格式化 ───────────────────────────────────────────
;;
;; 每个段函数接收尺寸档位 TIER（wide / medium / narrow / compact），
;; 返回一段带 face 的短字符串，该档位不适用时返回空串。
;; 左段：工程相对路径、文件名、Git 分支、VC 状态、编码、行列号。
;; 右段：Flymake 诊断、Eglot、全局模式信息、Major Mode、电池、时间。

(defun self/modeline--path-segment (tier)
  "返回 TIER 对应的路径段（目录缩写 + 文件夹图标）。"
  (if (or (eq tier 'compact) (not buffer-file-name))
      ""
    (let* ((project (self/modeline--project-info))
           (key (list buffer-file-name project self:modeline-path-max-width)))
      (if (equal key (car-safe self/modeline--path-cache))
          (cdr self/modeline--path-cache)
        (let* ((root (car-safe project))
               (directory (file-name-directory buffer-file-name))
               (path (if (and root (file-in-directory-p buffer-file-name root))
                         (file-relative-name directory root)
                       directory))
               (display (self/modeline--path-initials path))
               (segment
                (if (string-empty-p (or display ""))
                    ""
                  (self/modeline--segment
                   (self/modeline--with-icon
                    (self/modeline--icon "nf-md-folder_open")
                    (truncate-string-to-width
                     display self:modeline-path-max-width 0 nil t))
                   'shadow))))
          (setq self/modeline--path-cache (cons key segment))
          segment)))))

(defun self/modeline--name-segment (tier)
  "返回 TIER 对应的 buffer 名。
compact 档由 major 段独占左段，此处返回空串避免重复。"
  (if (eq tier 'compact)
      ""
    (let ((key (list tier buffer-file-name (buffer-name))))
      (if (equal key (car-safe self/modeline--name-cache))
          (cdr self/modeline--name-cache)
        (let* ((name (if buffer-file-name
                         (file-name-nondirectory buffer-file-name)
                       (buffer-name)))
               (width (cond
                        ((eq tier 'wide) 32)
                        ((eq tier 'medium) 24)
                        (t 18)))
               (segment
                (self/modeline--segment
                 (self/modeline--with-icon
                  (self/modeline--icon "nf-fa-file_o" buffer-file-name)
                  (truncate-string-to-width name width 0 nil t))
                 'font-lock-function-name-face)))
          (setq self/modeline--name-cache (cons key segment))
          segment)))))

(defun self/modeline--branch-segment (tier)
  "返回 TIER 对应的 VCS 分支（从 `vc-mode' 描述串里解析）。"
  (if (or (eq tier 'compact) (not self:modeline-show-vcs))
      ""
    (let ((branch
           (when (and (stringp vc-mode)
                      (string-match
                       "\\(?:Git\\|Hg\\|SVN\\)[-:]\\([^() ]+\\)" vc-mode))
             (string-trim (match-string 1 vc-mode)))))
      (if branch
          (self/modeline--segment
           (self/modeline--with-icon
            (self/modeline--icon "nf-md-source_branch") branch)
           'font-lock-type-face)
        ""))))

(defun self/modeline--vc-segment (tier)
  "返回 TIER 对应的 VC 状态（含状态 icon），收敛为三态。
有未保存改动或 VC 状态为编辑类 → edited(warning)；up-to-date →
clean(success)；unregistered → untracked(warning)；其余（含 ignored、
未受版本控制）不显示。"
  (if (or (eq tier 'compact) (not buffer-file-name))
      ""
    (when (eq self/modeline--vc-state-cache :unknown)
      (self/modeline--refresh-vc-state))
    (cond
     ((or (buffer-modified-p)
          (memq self/modeline--vc-state-cache
                '(edited added removed missing conflict
                         needs-merge needs-update)))
      (self/modeline--segment
       (self/modeline--with-icon
        (self/modeline--icon "nf-md-pencil") "edited")
       'warning))
     ((eq self/modeline--vc-state-cache 'up-to-date)
      (self/modeline--segment
       (self/modeline--with-icon
        (self/modeline--icon "nf-md-check_circle") "clean")
       'success))
     ((eq self/modeline--vc-state-cache 'unregistered)
      (self/modeline--segment
       (self/modeline--with-icon
        (self/modeline--icon "nf-md-help_circle") "untracked")
       'warning))
     (t ""))))

(defun self/modeline--coding-segment (tier)
  "返回 TIER 对应的文件编码（wide/medium 显示）。"
  (if (memq tier '(wide medium))
      (self/modeline--segment
       (self/modeline--with-icon
        (self/modeline--icon "nf-md-lock")
        (upcase
         (symbol-name
          (or (coding-system-base buffer-file-coding-system) 'undecided))))
       'font-lock-string-face)
    ""))

(defun self/modeline--location-segment (tier)
  "返回 TIER 对应的行列坐标 (%l,%c)。compact 档不显示。
位置按 `self/modeline--target-window' 的 point 求值：本函数在目标
buffer 的 `with-current-buffer' 里运行，不显式传窗口会拿到选中窗口
在该 buffer 的 point，多窗口同 buffer 时行列号会错。"
  (if (eq tier 'compact)
      ""
    (self/modeline--segment
     (self/modeline--with-icon
      (self/modeline--icon "nf-md-map_marker")
      (format "(%s)" (format-mode-line
                      "%l,%c" nil self/modeline--target-window)))
     'shadow)))

(defun self/modeline--diagnostics-segment (tier)
  "返回 TIER 对应的 Flymake 诊断计数（wide/medium 显示）。
wide 写全量 E:n W:n，medium 写紧凑 n:n，其余写总数。"
  (if (and (memq tier '(wide medium))
           (bound-and-true-p flymake-mode))
      (let* ((errors (car self/modeline--flymake-counts))
             (warnings (cadr self/modeline--flymake-counts))
             (total (+ errors warnings))
             (icon-name (cond
                         ((> errors 0)   "nf-md-times_circle")
                         ((> warnings 0) "nf-md-alert")
                         (t              "nf-md-check_circle")))
             (text (cond
                    ((eq tier 'wide)
                     (format "E:%d W:%d" errors warnings))
                    ((eq tier 'medium)
                     (format "%d:%d" errors warnings))
                    (t (number-to-string total))))
             (face (cond
                    ((> errors 0)   'error)
                    ((> warnings 0) 'warning)
                    (t              'success))))
        (self/modeline--segment
         (self/modeline--with-icon (self/modeline--icon icon-name) text)
         face))
    ""))

(defun self/modeline--eglot-segment (tier)
  "返回 TIER 对应的 Eglot 连接状态（wide 档带名称，wide/medium 显示）。"
  (if (and (memq tier '(wide medium)) self/modeline--eglot-info)
      (self/modeline--segment
       (self/modeline--with-icon
        (self/modeline--icon "nf-md-server_network")
        (if (eq tier 'wide) "eglot ●" "●"))
       'success)
    ""))

(defun self/modeline--global-segment (tier)
  "返回 TIER 对应的全局状态字符串（compact 档不显示）。
滤掉 `battery-mode-line-string' 和 `display-time-string'，避免与本
模块自定义的电池段、时间段重复。"
  (if (eq tier 'compact)
      ""
    (let* ((items (if (listp global-mode-string)
                      global-mode-string
                    (list global-mode-string)))
           (filtered (seq-remove
                      (lambda (item)
                        (memq item '(battery-mode-line-string
                                     display-time-string)))
                      items))
           (text (string-trim (format-mode-line filtered))))
      (if (string-empty-p text) "" text))))

(defun self/modeline--major-segment ()
  "major mode 段（带 icon）。
本段不接收 TIER：compact 档放左段压轴，其余档放右段，由
`self/modeline--render' 分流。"
  (self/modeline--segment
   (self/modeline--with-icon
    (self/modeline--icon "nf-md-code_tags")
    (symbol-name major-mode))
   'font-lock-keyword-face))

(defun self/modeline--battery-segment (tier)
  "返回 wide 档电池状态（按电量百分比着色）。
依赖 `display-battery-mode' 填充 `battery-mode-line-string'。"
  (if (eq tier 'wide)
      (let* ((raw (and (stringp battery-mode-line-string)
                       (string-trim battery-mode-line-string)))
             (percent (and raw
                           (string-match "\\([0-9]+\\)%" raw)
                           (string-to-number (match-string 1 raw))))
             (face (cond
                    ((not percent) 'font-lock-doc-face)
                    ((>= percent 50) 'success)
                    ((>= percent 20) 'warning)
                    (t 'error))))
        (if (and raw (not (string-empty-p raw)))
            (self/modeline--segment
             (self/modeline--with-icon
              (self/modeline--icon "nf-md-battery")
              raw)
             face)
          ""))
    ""))

(defun self/modeline--time-segment (tier)
  "返回非 compact 档时间（wide 档显示到秒）。"
  (if (and self:modeline-show-time (not (eq tier 'compact)))
      (let* ((wide (eq tier 'wide))
             (time (format-time-string (if wide "%H:%M:%S" "%H:%M"))))
        (self/modeline--segment
         (self/modeline--with-icon
          (self/modeline--icon "nf-md-clock")
          time)
         'font-lock-string-face))
    ""))

;; ─── 核心渲染与自适应对齐 ─────────────────────────────────────────

(defconst self/modeline--minibuffer " *Minibuf-0*"
  "状态行的承载 buffer；minibuffer 空闲时其内容即 echo area 的显示。")

(defconst self/modeline--display-table
  (let ((dt (make-display-table)))
    (set-display-table-slot dt 'truncation ?\s)
    dt)
  "`*Minibuf-0*' 的 display table：截断标记改为空格，溢出静默裁剪。")


(defun self/modeline--usable-width (frame)
  "返回 FRAME 的 echo area 可用列数。
对 GUI 与 TTY 统一减一列：内容一旦恰好写满窗口宽，行尾位置就会溢出
——GUI 在右 fringe 画溢出箭头，TTY 在末列画截断符号；状态行右段永远
贴右缘，必中这个标记，留出一列即可根治。"
  (1- (window-total-width (minibuffer-window frame))))

(defun self/modeline--render (&optional window)
  "渲染状态行：左段文件信息在前，右段系统状态贴右缘；放不下时截断左段。

段内容在 WINDOW 的 buffer 中求值（buffer-local 的 `vc-mode'、
flymake 计数、project 缓存都依赖该上下文）。左半有短消息时由消息顶替
常规信息（见 `self/modeline--handle-message'）。两侧留白由
`self:modeline-padding' 控制、左右一致（右缘保留位已计入该值）。

中缝用带 `(space :align-to)' 的特殊空格做动态右对齐：多客户端共享
后台守护进程时能自动适应各 frame 自身的实际宽度并贴齐右缘。"
  (let* ((window (or window self/modeline--target-window (selected-window)))
         (self/modeline--target-window window)
         (width (self/modeline--usable-width (window-frame window)))
         (pad (max 1 self:modeline-padding)))
    (with-current-buffer (window-buffer window)
      (let* ((tier (self/modeline-tier window))
             (left (concat (make-string pad ?\s)
                           (or self/modeline--message
                               (self/modeline--join
                                (self/modeline--path-segment tier)
                                (self/modeline--name-segment tier)
                                (self/modeline--branch-segment tier)
                                (self/modeline--vc-segment tier)
                                (self/modeline--coding-segment tier)
                                (self/modeline--location-segment tier)
                                (when (eq tier 'compact)
                                  (self/modeline--major-segment))))))
             (right (self/modeline--join
                     (self/modeline--diagnostics-segment tier)
                     (self/modeline--eglot-segment tier)
                     (self/modeline--global-segment tier)
                     (unless (eq tier 'compact)
                       (self/modeline--major-segment))
                     (self/modeline--battery-segment tier)
                     (self/modeline--time-segment tier)))
             (left-max (- width pad (string-width right))))
        ;; 放不下时宁可截左段（右段是常驻系统状态，优先级更高）。
        (when (> (string-width left) left-max)
          (setq left (truncate-string-to-width
                      left (max 1 left-max) nil nil t)))
        (concat left
                (propertize " " 'display
                            (list 'space :align-to
                                  (list '- 'right
                                        (+ pad (string-width right)))))
                right)))))

(defun self/modeline--apply-base-face (text)
  "给 TEXT 中无 face 的区域补上 minibuffer-line 基 face。
等价于 `format-mode-line' 的 FACE 参数合并语义：已有 face 的段文本保持
不变，无 face 文本（留白、分隔符、图标）继承 minibuffer-line。
逐段用 `next-single-property-change' 跳到下一个 face 边界，避免逐字符
扫描整行（这是每 tick 都跑的路径）。"
  (let ((pos 0)
        (len (length text)))
    (while (< pos len)
      (let ((next (next-single-property-change pos 'face text len)))
        (unless (get-text-property pos 'face text)
          (add-face-text-property pos next 'minibuffer-line nil text))
        (setq pos next))))
  text)

;; ─── 刷新调度与底栏集成 ───────────────────────────────────────────

(defun self/modeline-refresh (&optional frame)
  "把状态行写入 `self/modeline--minibuffer'，内容有变化才重写并置位 redisplay。

FRAME 缺省为选中 frame；挂在 `window-size-change-functions' 上时会传入
尺寸变化的 frame，使 TTY resize、分屏后的右缘对齐立即重算。
整体包 `condition-case'：挂在钩子上的函数一旦抛错会被 Emacs 自动卸载，
刷新函数被移出钩子后状态行会静默停摆——这正是「底栏莫名消失」的路径。
minibuffer 激活期间不刷新：此时底栏是输入区，退出后由 post-command
与每秒 tick 恢复。"
  (when (bound-and-true-p minibuffer-line-mode)
    (condition-case nil
        (unless (active-minibuffer-window)
          (let* ((frame (or frame (selected-frame)))
                 (mw (minibuffer-window frame))
                 (self/modeline--target-window
                  (frame-selected-window frame))
                 (self/modeline--rendering t)
                 (text (self/modeline--apply-base-face
                        (self/modeline--render))))
            ;; 图形界面下把 minibuffer 窗口的 fringe 清零，消掉右边框。
            (when (and (display-graphic-p frame)
                       (> (nth 1 (window-fringes mw)) 0))
              (set-window-fringes mw 0 0))
            (with-current-buffer
                (get-buffer-create self/modeline--minibuffer)
              (unless (eq buffer-display-table
                          self/modeline--display-table)
                (setq buffer-display-table self/modeline--display-table))
              ;; `equal' 连文本属性一起比：内容一字未变就跳过 erase/insert，
              ;; 空闲期每秒 tick 最常见的空转不再白做一次 buffer 修改与
              ;; redisplay 置位。比的是 buffer 实际内容而非缓存的上次渲染，
              ;; 所以回显区把内容清空后比较会立刻失配、防空白底栏的能力
              ;; 不受影响。真正落盘的写入用 with-silent-modifications 抑制 undo。
              (unless (equal text (buffer-string))
                (with-silent-modifications
                  (erase-buffer)
                  (insert text))))
            (when (eq (window-buffer mw)
                      (get-buffer self/modeline--minibuffer))
              (when (> (window-total-height mw) 1)
                (window-resize mw (- 1 (window-total-height mw))))
              (unless (zerop (window-hscroll mw))
                (set-window-hscroll mw 0))
              (unless (zerop (window-vscroll mw))
                (set-window-vscroll mw 0)))))
      (error nil))))

(defun self/modeline--tick ()
  "每秒兜底：重渲染状态行，短消息并入满 4 秒后撤下左半。
刻意用普通 timer 而非 repeat 型 idle timer：后者每个空闲周期只触发一次
（timer.el 重调度后置 `timer--triggered'，要等下次输入事件才复位），
daemon 无键盘输入时空闲周期无限长，idle timer 实际等同失效。"
  (self/modeline-refresh)
  (when (and self/modeline--message
             (or (null self/modeline--message-time)
                 (>= (float-time
                      (time-subtract nil self/modeline--message-time))
                     4)))
    (setq self/modeline--message nil
          self/modeline--message-time nil)
    (self/modeline-refresh)))

(use-package minibuffer-line
  :custom (minibuffer-line-refresh-interval 30)
  :config
  ;; :inherit 置 nil 彻底切断对 mode-line-inactive 底色的继承，
  ;; 使 minibuffer-line 完全融入 echo area 背景，消除字符边框与底色色差。
  (set-face-attribute 'minibuffer-line nil :inherit nil :box nil)
  (minibuffer-line-mode 1)
  (advice-add 'minibuffer-line--update :override #'self/modeline-refresh)
  (add-hook 'post-command-hook #'self/modeline-refresh)
  (add-hook 'window-size-change-functions #'self/modeline-refresh)
  (add-hook 'window-state-change-hook #'self/modeline-refresh)
  (cancel-function-timers #'self/modeline--tick)
  (run-with-timer 1 1 #'self/modeline--tick))

;; ─── 消息接管与事件防御 ───────────────────────────────────────────

(defun self/modeline--tooltip-hide (orig &rest args)
  "TTY 下 tooltip-hide 的 `(message \"\")` 在无消息可清时跳过。
GUI 分支、有消息可清、或 minibuffer 活动时照原样执行。
TTY 里点击/滚轮会触发 `tooltip-hide'，那次空 message 会清空整条
底栏造成闪烁，这里直接返回 t 表示「已处理」。"
  (if (or (display-graphic-p)
          (current-message)
          (active-minibuffer-window))
      (apply orig args)
    (tooltip-cancel-delayed-tip)
    t))

(advice-add 'tooltip-hide :around #'self/modeline--tooltip-hide)

(defun self/modeline--handle-message (text)
  "把短消息 TEXT 并入状态行左半，返回 t 表示已接管。
超过半宽、非字符串/空串/多行消息、minibuffer 活动期与渲染期返回 nil，
交回 Emacs 默认的整行显示。整体包 `condition-case'：本函数在 `message'
调用路径上，抛错会波及发消息的业务代码，还会被移出 set-message-functions。"
  (condition-case nil
      (when (and (bound-and-true-p minibuffer-line-mode)
                 (stringp text)
                 (> (string-width text) 0)
                 (not self/modeline--rendering)
                 (not (active-minibuffer-window))
                 (not (string-search "\n" text))
                 (<= (string-width text)
                     (/ (window-total-width (minibuffer-window)) 2)))
        (setq self/modeline--message text
              self/modeline--message-time (current-time))
        (self/modeline-refresh)
        t)
    (error nil)))

(defun self/modeline--clear-message ()
  "撤下左半的短消息。
两个触发点：`pre-command-hook' 对齐 echo area 的清除时机（下一个输入
事件）；`self/modeline--tick' 兜住长时间无输入的情况（并入满 4 秒）。"
  (when self/modeline--message
    (setq self/modeline--message nil
          self/modeline--message-time nil)
    (self/modeline-refresh)))

(add-to-list 'set-message-functions #'self/modeline--handle-message t)
(add-hook 'pre-command-hook #'self/modeline--clear-message)

;; 数据源挂钩：诊断、Eglot、VC、project 变化时更新 buffer-local 缓存，
;; 渲染路径只读内存。
(with-eval-after-load 'flymake
  (add-hook 'flymake-after-diagnostics-hook
            #'self/modeline--refresh-flymake-counts)
  (add-hook 'flymake-mode-hook
            #'self/modeline--refresh-flymake-counts))

(with-eval-after-load 'eglot
  (add-hook 'eglot-managed-mode-hook #'self/modeline--refresh-eglot-info)
  (add-hook 'eglot-server-initialized-hook
            #'self/modeline--refresh-eglot-info))

(add-hook 'find-file-hook #'self/modeline--refresh-vc-state)
(add-hook 'after-save-hook #'self/modeline--refresh-vc-state)
(add-hook 'after-revert-hook #'self/modeline--refresh-vc-state)
(add-hook 'after-save-hook #'self/modeline--reset-project-cache)
(add-hook 'after-change-major-mode-hook #'self/modeline--reset-project-cache)

(display-battery-mode 1)

(provide 'self-modeline)
;;; self-modeline.el ends here
