;;; self-dashboard.el --- 启动欢迎屏：启动路由、版心排版与窄屏自绘视觉层 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: portable, full
;; Requires: self-glyph（`self/glyph'）、self-touch（触屏键盘与存储权限）、
;;           self-org（`self/org--ensure-directories' 等）、self-help-zh（`self/show-help'）
;; Packages: dashboard, nerd-icons
;;
;; 桌面端配置的「Dashboard」域七个子节（启动路由 / 顶部按钮与 ASCII 横幅 /
;; 版心计算与路径压缩 / 板块边界与行距排版 / 装饰总览与版心居中 / 尺寸防抖与
;; 重绘自愈 / 日程扫描单次缓存 / 插件配置）与移动端那份窄屏自绘欢迎屏合并到
;; 本文件，按「宽屏排版 + 帧就绪自愈 + agenda 缓存」与「窄屏自绘 + 触屏按钮」
;; 两层组织：计算层（版心、路径、板块边界、防抖、agenda 缓存）两平台共用，
;; 视觉层与插件配置按 `self:android-p' 分支。
;;
;; ─── 启动路由 ────────────────────────────────────────────────────
;;
;; `initial-buffer-choice' 指向 `self/dashboard-initial-buffer'：只有
;; emacsclient 不带文件参数时才走欢迎屏，带参数启动照常打开目标文件。
;;
;; ─── 重绘很贵 ────────────────────────────────────────────────────
;;
;; 一次全量 `dashboard-open' 包含三块成本：item 生成（插件内部展开各段模板）、
;; agenda 扫描（`org-map-entries' 走文件）、以及本文件的装饰（按行改 text
;; property）。因此只在这三处省成本：
;;   · 宽度记忆 `self/dashboard--rendered-width'：渲染后记下当时的窗口正文宽，
;;     frame 就绪回调与 resize 合并刷新都先比宽度，相符就整轮跳过；
;;   · agenda 单次缓存 `self/dashboard--agenda-once'：见下文；
;;   · resize 防抖：拖拽窗口时每个中间宽度一个事件，只挂一个 idle timer，
;;     静止 0.3 秒后按最终宽度刷一次，绝不逐事件全量渲染。
;;
;; ─── 为什么 daemon 下必须过滤哑 initial frame ─────────────────────
;;
;; daemon 启动后会同时存在「没有 client 参数的哑 initial frame」和真实
;; client frame。`switch-to-buffer' 可能把欢迎屏泄漏到那个超宽的哑 frame 上；
;; 版心宽度、路径截断、居中偏移全部取自 selected window，取错 frame 就是整屏
;; 排版皆错。故 `self/dashboard--dashboard-window' 只在带 `client' 参数的
;; frame 里找，且后续渲染与装饰都在该窗口为 selected 的上下文里执行。
;;
;; ─── 版心计算与路径两级降级 ──────────────────────────────────────
;;
;; 版心宽 = 窗口正文宽 × `self:dashboard-content-ratio'（默认 0.8），两侧空列
;; 各占 (1-ratio)/2。这个基准被三处共用：路径截断上限、标题快捷键右贴终点、
;; 分割线长度。
;;
;; 最近文件列表里的长路径先做第一级降级——中间目录压成首字母（隐藏目录 `.x`
;; 保留点号取第二个字符）；仍超版心再做第二级——头部补 `...` 截断。截断按
;; 显示宽度计（CJK 占 2 列），而不是 `substring' 按字符数切——后者在 CJK 长
;; 文件名上会 `args-out-of-range'，直接中断整个渲染。显示文本与真实路径由
;; 插件的 path-alist 解耦，缩短不影响点击跳转。
;;
;; 行宽测量为什么用 `dashboard-str-len' 而非 `string-width'
;; -------------------------------------------------------
;; 版心居中要看「这行实际渲染出来多宽」。`string-width' 会把 ─ ═ 这类
;; ambiguous 字符按双列计，而 GUI 字体下它们实际渲染是单列，用它居中会整体
;; 偏移；插件的 `dashboard-str-len' 按像素量，才是真机所见。
;;
;; 居中为什么分两组
;; ----------------
;; 板块区（首板块标题行 → 末分割线行）整块共用一个 `align-to' 前缀，块内
;; 左对齐，看起来是一个居中的盒子；banner / 欢迎语 / navigator / footer 这些
;; 行长短不一，逐行按自身行宽各自居中才好看。插件给这些行自设过测量式前缀，
;; 而 `add-text-properties' 不覆盖已有属性，所以必须先
;; `remove-text-properties' 再改写。行宽超过窗口时**不加**前缀——`align-to'
;; 负值会把整行推出屏幕左缘；`align-to' 表达式没有可用的 max 钳制，只能在
;; 装饰时静态排除。
;;
;; 标题装饰固定三步
;; ----------------
;; 每个板块固定三步，都围绕该板块的 heading overlay 展开：
;;   1. 分割线：把板块尾部第一段空行换成与主题融合的细线；同时给板块内每一行
;;      加 `self:dashboard-line-spacing' 行间距，不插空行也有呼吸感；
;;   2. 缩进：标题行左缩进 `self:dashboard-heading-indent' 列；
;;   3. 快捷键右贴：把该板块的入口键补空格右贴到版心右缘。
;; 定位走 heading overlay（`dashboard-heading' face）而不是插件的
;; `dashboard--section-starts'：渲染末尾的 page-separator 替换会让后者的绝对
;; 位置漂移。装饰**倒序**执行——前面的 insert 不会影响后面 heading 的位置。
;; 末板块若一直找不到空行（没有板块尾部），第 1 步整体跳过。
;;
;; ─── Android 窄屏自绘层 ─────────────────────────────────────────
;;
;; Android 上跑官方的 ASCII banner + 多段 items 排版会在约 40 列宽度里挤成
;; 一团，故整条视觉层自绘：官方盲文 Emacs logo（30×14 块居中）+ 时段问候
;; 与随机小句 + 日期/启动信息行；三枚 [] 按钮（括号 dim、内文 bold）；各段
;; heading 短装饰线 + NF 图标夹标题、条目间空行（4+4）；footer 英文短名言
;; 随机；tty 无 NF 字形自动降级纯文本。`dashboard-startupify-list' 整条接管，
;; 官方 banner / navigator / footer 一律不参与。
;;
;; ─── agenda 为什么只扫一次 ───────────────────────────────────────
;;
;; 上游 `dashboard-insert-section' 宏对它收到的 list 参数求值 4 次（heading 判断
;; / if 分支 / subseq / section-list 的 car）。传进去的 agenda 表达式会被执行
;; 4 次，于是 `org-map-entries' 全量扫描被重复 4 次，是渲染耗时与 GC 压力的
;; 大头。这里给 `dashboard-get-agenda' 挂 :around advice，在单次渲染范围内缓存
;; 结果；缓存变量只在渲染入口的 `let' 绑定内有效，渲染结束自动丢弃，下一次
;; 渲染重新扫描——数据新鲜度与插件原生行为一致，也绝不跨渲染持有过期的
;; agenda 列表。

;;; Code:

(require 'dashboard)

;; ─── faces ──────────────────────────────────────────────────────────

(defface self/dashboard-logo
  '((t :inherit font-lock-keyword-face :weight bold))
  "盲文 logo（主题关键词单色）。" :group 'self)

(defface self/dashboard-hero
  '((t :weight bold :height 1.5))
  "抓笔记面板大标题。" :group 'self)

(defface self/dashboard-subtitle
  '((t :inherit font-lock-doc-face :height 0.9))
  "仪表盘问候行。" :group 'self)

(defface self/dashboard-deco
  '((t :inherit shadow))
  "装饰线与按钮括号。" :group 'self)

(defface self/dashboard-deco-icon
  '((t :inherit font-lock-keyword-face))
  "装饰线/条目中的 NF 图标。" :group 'self)

(defface self/dashboard-meta
  '((t :inherit shadow))
  "日期/启动信息行。" :group 'self)

(defface self/dashboard-button
  '((t :weight bold))
  "navigator 按钮文字。" :group 'self)

(defface self/dashboard-warning
  '((t :inherit warning :weight bold))
  "存储权限未授予警示行。" :group 'self)

;; ─── 声明 ───────────────────────────────────────────────────────────

(declare-function self/glyph "self-glyph")
(declare-function self/org--ensure-directories "self-org")
(declare-function self/org--ensure-agenda-file "self-org")
(declare-function self/touch-show-keyboard "self-touch")
(declare-function self/android-storage-granted-p "self-touch")
(declare-function self/android-request-storage-access "self-touch")
(declare-function self/show-help "self-help-zh")
(declare-function project-switch-project "project")
(declare-function nerd-icons-octicon "nerd-icons")
(declare-function agenote-knowledge-browse "agenote")
;; dashboard 2.x 的 API（自绘接管、盲文 logo、包计数）。1.8.0 没有这几个，
;; 沙箱里装的正是 1.8.0，故只做声明：值在真正的 2.x 里由包自己 defcustom，
;; 这里带值声明反而会把它顶成 nil。
(declare-function dashboard-insert-items "dashboard")
(declare-function dashboard-init--packages-count "dashboard")
(declare-function org-clocking-p "org")
(declare-function org-clock-goto "org-clock")
(defvar dashboard-startupify-list)
(defvar dashboard-banner-logo-braille)
(defvar self:android-p)
(defvar self:org-directory)
(defvar self:org-roam-directory)
(defvar org-capture-templates)

;; ─── 版心计算 ──────────────────────────────────────────────────────

(defcustom self:dashboard-content-ratio 0.8
  "Dashboard 版心占窗口正文宽度的比例,两侧空列各占 (1-ratio)/2。
按 100/140/200 三档常用列宽调优,不做逐列自适应。"
  :type 'number
  :group 'self)

(defcustom self:dashboard-min-content-width 40
  "触发渲染的最小版心宽度(列)。版心低于此值的窗口(含 resize
拖拽经过的窄中间态)不做全量渲染,保留上一次可读内容,避免破碎
显示;align-to 前缀的 max 0 钳制负责这类场景的显示兜底。"
  :type 'integer
  :group 'self)

(defcustom self:dashboard-line-spacing 6
  "板块内行间距(像素),标题与条目统一生效。
text property line-spacing 仅 GUI frame 生效,TTY 行高固定会忽略。"
  :type 'integer
  :group 'self)

(defconst self:dashboard-heading-indent 4
  "标题行缩进列数(行首插入的空格数)。
装饰时按此值把 overlay 拨回原位,快捷键右贴宽度也按此折算。")

(defun self/dashboard--content-width (&optional window)
  "WINDOW(默认 selected)下的 dashboard 版心宽度(列)。"
  (floor (* self:dashboard-content-ratio
            (window-body-width window))))

;; ─── 路径压缩与截断 ────────────────────────────────────────────────
;;
;; 两级降级：先压中间目录为首字母，仍超版心再头部补 `...' 截断。
;; 单字母压法对隐藏目录取点号后的第一个字符（`.x' → `.x'），
;; 空目录项原样返回。自绘条目标签与插件的 `dashboard-shorten-path'
;; 覆写共用 `self/dashboard--dir-initial'，避免两份同构实现。

(defun self/dashboard--dir-initial (dir)
  "返回目录 DIR 压缩成的首字母项。
隐藏目录(.x)保留点号取第二个字符,空目录项原样返回。"
  (cond ((string-empty-p dir) dir)
        ((string-prefix-p "." dir)
         (if (> (length dir) 1)
             (concat "." (substring dir 1 2))
           dir))
        (t (substring dir 0 1))))

(defun self/dashboard--compress-middle-dirs (abbrev)
  "把 ABBREV 的中间目录压为首字母,返回压缩后的完整路径。
首段(根或卷标)与末段(文件名)不压缩,中间段逐段交给
`self/dashboard--dir-initial'。"
  (let* ((parts (split-string abbrev "/" t))
         (len (length parts))
         (head (car parts))
         (file (car (last parts)))
         (middle (seq-subseq parts 1 (1- len)))
         (compressed '()))
    (dolist (dir middle)
      (push (self/dashboard--dir-initial dir) compressed))
    (concat head "/"
            (mapconcat #'identity (nreverse compressed) "/")
            "/" file)))

(defun self/dashboard--truncate-to-width (path width)
  "PATH 超出 WIDTH 列时头部截断补 ...,WIDTH 不足 3 列则只留 ...。
截断按显示宽度计(CJK 字符占 2 列),取显示宽度不超过 WIDTH-3 的
最长前缀,保证结果连同 ... 不超宽;直接用 substring 按字符数截
会在 CJK 长文件名上 args-out-of-range,中断整个 dashboard 渲染。
未超宽时原样返回 PATH。"
  (if (<= (string-width path) width)
      path
    (if (<= width 3)
        "..."
      (let ((limit (- width 3))
            (chars 0)
            (cols 0))
        (catch 'exceed
          (dolist (ch (string-to-list path))
            (let ((w (char-width ch)))
              (when (> (+ cols w) limit)
                (throw 'exceed t))
              (setq cols (+ cols w)
                    chars (1+ chars)))))
        (concat (substring path 0 chars) "...")))))

(defun self/dashboard--shorten-path (path _type)
  "dashboard-shorten-path 的替代:超版心的路径两级降级。
先压缩中间目录为首字母(隐藏目录以 . 开头,取其第二个字符),仍超
则头部 ... 截断。显示文本与真实路径经 plugin 的 path-alist 解耦,
缩短不影响点击跳转。_TYPE 是 dashboard 传入的展示类型,本实现不用
(下划线前缀表示占位)。"
  (let* ((abbrev (abbreviate-file-name path))
         (width (self/dashboard--content-width))
         (parts (split-string abbrev "/" t))
         (p (if (<= (length parts) 3)
                abbrev
              (self/dashboard--compress-middle-dirs abbrev))))
    (self/dashboard--truncate-to-width p width)))

(defconst self:dashboard-banner-ascii
  "███████╗  ███╗   ███╗   █████╗    ██████╗  ███████╗
██╔════╝  ████╗ ████║  ██╔══██╗  ██╔════╝  ██╔════╝
█████╗    ██╔████╔██║  ███████║  ██║       ███████╗
██╔══╝    ██║╚██╔╝██║  ██╔══██║  ██║       ╚════██║
███████╗  ██║ ╚═╝ ██║  ██║  ██║  ╚██████╗  ███████║
╚══════╝  ╚═╝     ╚═╝  ╚═╝  ╚═╝   ╚═════╝  ╚══════╝"
  "Dashboard 顶部 ASCII banner（宽屏平台用）。")

(defconst self:dashboard-heading-keys
  '("C-c o a" "C-x C-r" "C-x p p")
  "各标题行右缘显示的快捷键，顺序与 `dashboard-items' 一致。")

;; ─── hero：盲文 logo + 问候 + 日期/启动信息 ─────────────────────────

(defconst self/dashboard--mottos
  '("今天也要 org-mode" "万物皆 buffer" "写下来就成功了一半"
    "慢慢来比较快" "一切皆文本，一切可编程")
  "问候行随机小句池。")

(defun self/dashboard--greeting ()
  "按时段返回中文问候。"
  (let ((h (nth 2 (decode-time))))
    (cond ((<= 5 h 7) "晨光正好")
          ((<= 8 h 10) "上午好，日光正盛")
          ((<= 11 h 12) "午安")
          ((<= 13 h 16) "日色渐西")
          ((<= 17 h 18) "暮色四合")
          ((<= 19 h 22) "夜色温柔")
          (t "夜深了"))))

(defun self/dashboard--info-line ()
  "日期与启动信息短行。"
  (let* ((now (decode-time))
         (week (nth (nth 6 now)
                    '("周日" "周一" "周二" "周三" "周四" "周五" "周六"))))
    (format "%d月%d日 %s · %d 包 · %.2fs"
            (nth 4 now) (nth 3 now) week
            (dashboard-init--packages-count)
            (string-to-number (emacs-init-time)))))

(defun self/dashboard-insert-hero ()
  "hero 区：盲文 logo（块居中保持图形）+ 问候行 + 日期/启动信息行。
问候 + 小句组合超 36 列时省略小句（窄屏防折行）。"
  (insert "\n")
  (let ((start (point)))
    (insert (propertize
             (with-temp-buffer
               (insert-file-contents dashboard-banner-logo-braille)
               (buffer-string))
             'face 'self/dashboard-logo))
    (dashboard-center-text start (point)))
  (insert "\n")
  (let* ((greet (self/dashboard--greeting))
         (motto (nth (random (length self/dashboard--mottos))
                     self/dashboard--mottos))
         (line (format "%s · %s" greet motto)))
    (dashboard-insert-center
     (propertize (if (<= (string-width line) 36) line greet)
                 'face 'self/dashboard-subtitle)))
  (insert "\n")
  (dashboard-insert-center
   (propertize (self/dashboard--info-line) 'face 'self/dashboard-meta))
  (insert "\n"))

;; ─── heading：中文标题 + NF 图标 + 两侧短装饰线 ─────────────────────
;; 标题直接用中文 buffer 文本：`dashboard--find-max-width' 按 buffer
;; 原文计宽，overlay display 换名不参与计算。

(defun self/dashboard--heading-icon (code)
  "返回码点 CODE 的图标串。"
  (propertize code 'face 'self/dashboard-deco-icon))

(defun self/dashboard-insert-heading-deco (fn heading &optional shortcut icon)
  "HEADING 两侧加短装饰线（整行居中由 `dashboard-center-content' 统一做）。"
  (prog1 (funcall fn heading shortcut icon)
    (let ((deco (propertize "──── " 'face 'self/dashboard-deco)))
      (save-excursion
        ;; icon 回退须与官方插入条件一致（tty 无字形不插入 icon）
        (goto-char (- (point) (length heading)))
        (when (and (dashboard-display-icons-p) dashboard-set-heading-icons icon)
          (goto-char (- (point) (1+ (length icon)))))
        (insert deco)))
    (insert (propertize " ────" 'face 'self/dashboard-deco))))

(advice-add #'dashboard-insert-heading :around
            #'self/dashboard-insert-heading-deco)

;; ─── 窄屏条目标签截断 ───────────────────────────────────────────────

(defun self/dashboard--take-width (str n &optional from-end)
  "取 STR 列宽不超 N 的子串（FROM-END 非 nil 从尾部取）。"
  (let ((chs (if from-end
                 (reverse (string-to-list str))
               (string-to-list str))))
    (cl-loop with w = 0
             for ch in chs
             for cw = (string-width (string ch))
             while (<= (+ w cw) n)
             do (cl-incf w cw) and collect ch into acc
             finally return (concat (if from-end (nreverse acc) acc)))))

(defun self/dashboard--fit (label icon-w)
  "LABEL 超宽时中截，预留 ICON-W 与条目缩进（窄屏防折行）。"
  (let ((max (- (window-total-width) 6 icon-w)))
    (if (<= (string-width label) max)
        label
      (concat (self/dashboard--take-width label (- max 10))
              "…"
              (self/dashboard--take-width label 8 t)))))

;; ─── recents 条目：图标 + org 根相对路径 ────────────────────────────

(defun self/dashboard--path-initials (path)
  "把 PATH 的目录部分缩成首字母（逐段交给 `self/dashboard--dir-initial'）。
远程路径保留 method 前缀，只压缩本地部分。"
  (let* ((remote (or (file-remote-p path) ""))
         (local (or (file-remote-p path 'localname) path))
         (parts (split-string
                 (string-remove-prefix
                  "~/" (abbreviate-file-name (directory-file-name local)))
                 "/" t)))
    (concat remote
            (string-join (mapcar #'self/dashboard--dir-initial parts) "/"))))

(defun self/dashboard--recent-label (path)
  "recents 条目文本：org 根下显示相对路径，其余目录首字母缩写。
（反映文件原名，不做标题替换。）"
  (let ((rel (and self:org-directory
                  (file-in-directory-p path self:org-directory)
                  (file-relative-name path self:org-directory))))
    (cond
     ;; 上级回溯路径无信息量，直接用文件名
     ((string-prefix-p "../" rel) (file-name-nondirectory path))
     (rel (abbreviate-file-name rel))
     (t (format "%s/%s"
                (self/dashboard--path-initials (file-name-directory path))
                (file-name-nondirectory path))))))

;; ─── 笔记段：文件夹内最近修改的文件 ─────────────────────────────────
;; 直接列目录（按 mtime），不经 org-roam db——首屏即出、零延迟。
;; 条目显示文件头 #+title:（时间戳文件名无信息量），缺失回退文件名。

(defun self/dashboard--note-title (file)
  "笔记 FILE 头部 #+title: 的值，缺失或读取失败回退文件名。
只读首 4KB，N 个条目启动期一次性开销可忽略。"
  (or (ignore-errors
        (with-temp-buffer
          (insert-file-contents file nil 0 4096)
          (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)" nil t)
            (string-trim (match-string 1)))))
      (file-name-nondirectory file)))

(defun self/dashboard--recent-roam-files (n)
  "笔记目录按 mtime 最近的 N 个 org 文件。
`directory-files-and-attributes' 一次 stat 全表（装饰排序，比较
纯内存）——sort 比较器内逐对 file-attributes 在 FUSE 存储上是
n·log(n) 次 stat 风暴。"
  (mapcar #'car
          (seq-take
           (sort (directory-files-and-attributes
                  self:org-roam-directory t "\\.org\\'")
                 (lambda (a b)
                   (time-less-p
                    (file-attribute-modification-time (cdr b))
                    (file-attribute-modification-time (cdr a)))))
           n)))

(defun self/dashboard--icon (code)
  "GUI 返回 NF 码点 CODE 的图标串，tty 返回空串。"
  (and (display-graphic-p)
       (propertize code 'face 'self/dashboard-deco-icon)))

(defun self/dashboard--file-icon (path)
  "按扩展名取 NF 文件图标（tty 返回空串）。"
  (or (self/dashboard--icon
       (pcase (downcase (or (file-name-extension path) ""))
         ("org" "\uF0F6")
         ((or "md" "txt") "\uF15C")
         (_ "\uF15B")))
      ""))

;; ─── 条目段自绘：heading + 条目间空行 ───────────────────────────────

(defun self/dashboard-insert-section* (heading icon files tag)
  "自绘段：HEADING + FILES 逐条 TAG 文本按钮，条目间空行。"
  (insert "\n")
  (dashboard-insert-heading heading nil icon)
  (if (null files)
      (insert "\n\n    "
              (propertize "暂无文件" 'face 'self/dashboard-meta))
    (dolist (file files)
      (insert "\n\n    ")
      (widget-create 'item
                     :tag (funcall tag file)
                     :action `(lambda (&rest _) (find-file-existing ,file))
                     :button-face 'dashboard-items-face
                     :mouse-face 'highlight
                     :button-prefix "" :button-suffix ""
                     :format "%[%t%]")))
  (insert "\n"))

(defun self/dashboard-insert-recents (list-size)
  "最近文件 LIST-SIZE 条：图标 + 路径标签（中截防窄屏折行）。"
  (unless recentf-mode (recentf-mode 1))
  (self/dashboard-insert-section*
   "最近文件" (self/dashboard--heading-icon "\uF017")
   (seq-take recentf-list list-size)
   (lambda (file)
     (let ((icon (self/dashboard--file-icon file)))
       (concat icon (unless (string-empty-p icon) " ")
               (self/dashboard--fit
                (self/dashboard--recent-label file)
                (length icon)))))))

(defun self/dashboard-insert-roam (list-size)
  "笔记文件夹按修改时间最近的 LIST-SIZE 个文件。"
  (self/dashboard-insert-section*
   "最近笔记" (self/dashboard--heading-icon "\uF02E")
   (self/dashboard--recent-roam-files list-size)
   (lambda (file)
     (let ((icon (self/dashboard--file-icon file)))
       (concat icon (unless (string-empty-p icon) " ")
               (self/dashboard--fit (self/dashboard--note-title file)
                                      (length icon)))))))

;; ─── navigator：[] 按钮 ─────────────────────────────────────────────

(defun self/dashboard-button-icon (name)
  "取 dashboard 按钮用的 nerd-icons octicon 图标串。NAME 是图标名。"
  (nerd-icons-octicon name :height 1.2 :v-adjust -0.05))

(defun self/dashboard-goto-clock-or-agenda (&rest _)
  "Dashboard 按钮：正在计时的任务则跳转，否则打开今日议程。
交互命令：dashboard navigator 按钮；亦可 `M-x self/dashboard-goto-clock-or-agenda'。"
  (interactive)
  (require 'org-clock)
  (call-interactively
   (if (org-clocking-p) #'org-clock-goto #'org-agenda-list)))

(defun self/dashboard-jump-bookmark (&rest _)
  "Dashboard 按钮：交互式跳转书签。
交互命令：dashboard navigator 按钮。"
  (interactive)
  (call-interactively #'bookmark-jump))

(defun self/dashboard-browse-knowledge (&rest _)
  "Dashboard 按钮：打开知识库总览。
交互命令：dashboard navigator 按钮。"
  (interactive)
  (call-interactively #'agenote-knowledge-browse))

(defun self/dashboard-show-shortcuts (&rest _)
  "Dashboard 按钮：打开快捷键帮助。
交互命令：dashboard navigator 按钮。"
  (interactive)
  (call-interactively #'self/show-help))

(defun self/dashboard--nav-buttons ()
  "返回 navigator 按钮数据表：(图标 标题 帮助 动作) 四元组列表。
宽屏图形 frame（非 Android）走桌面端四枚（计时 / 书签 / 知识库 / 快捷键，
图标用 nerd-icons 渲染），其余（Android 触屏、窄屏、纯 tty）走移动端三枚
（抓笔记 / 议程 / 笔记，纯文本图标走 `self/glyph' 的 tty 回退）。
COMMAND 是命令符号，而 widget 以 (widget EVENT) 两参调用它，所以这些命令
都用 &rest 兜底参数；图标在求值时就渲染成字符串，插件直接拿去当按钮文字。"
  (if (and (display-graphic-p) (not self:android-p))
      (list
       (list (self/dashboard-button-icon "nf-oct-clock") "计时"
             "计时的任务: 跳转;否则打开今日议程(按 I 计时)"
             #'self/dashboard-goto-clock-or-agenda)
       (list (self/dashboard-button-icon "nf-oct-bookmark") "书签"
             "跳转书签 (C-x r b)"
             #'self/dashboard-jump-bookmark)
       (list (self/dashboard-button-icon "nf-oct-book") "知识库"
             "知识库总览 (RET 打开卡片)"
             #'self/dashboard-browse-knowledge)
       (list (self/dashboard-button-icon "nf-oct-question") "快捷键"
             "快捷键帮助 (F1 ?)"
             #'self/dashboard-show-shortcuts))
    `((,(self/glyph "\uF0E7" "") "抓笔记" "选择模板快速捕获"
       self/capture-menu)
      (,(self/glyph "\uF133" "") "议程" "本周日程"
       (lambda (&rest _)
         (require 'org-agenda)
         (self/org--ensure-agenda-file)
         (org-agenda-list)))
      (,(self/glyph "\uF07C" "") "笔记" "打开笔记文件夹"
       (lambda (&rest _)
         (self/org--ensure-directories)
         (dired self:org-roam-directory))))))

(defun self/dashboard--nav-tag (icon title)
  "[] 按钮 tag：括号 dim、内文 bold；tty 无图标时内衬缩进对齐。"
  (concat (propertize "[" 'face 'self/dashboard-deco)
          (propertize (if (string-empty-p icon)
                          (concat " " title " ")
                        (concat " " icon " " title " "))
                      'face 'self/dashboard-button)
          (propertize "]" 'face 'self/dashboard-deco)))

(defun self/dashboard-insert-navigator ()
  "自绘 navigator：把 `self/dashboard--nav-buttons' 的按钮横排，整行居中。"
  (insert "\n")
  (let ((first t))
    (dolist (btn (self/dashboard--nav-buttons))
      (unless first (insert "  "))
      (setq first nil)
      (widget-create 'item
                     :tag (self/dashboard--nav-tag (nth 0 btn) (nth 1 btn))
                     :help-echo (nth 2 btn)
                     :action (nth 3 btn)
                     :button-face 'dashboard-items-face
                     :mouse-face 'highlight
                     :button-prefix "" :button-suffix ""
                     :format "%[%t%]")))
  (dashboard-center-text (line-beginning-position) (line-end-position))
  (insert "\n"))

;; ─── 存储权限警示（官方 splash 提示的 dashboard 承接） ────────────

(defun self/dashboard-insert-permission-notice ()
  "Android 存储权限未授予时插入可点警示行，已授予/非 Android 不输出。"
  (when (and self:android-p
             (not (self/android-storage-granted-p)))
    (insert "\n  ")
    (let ((beg (point)))
      (widget-create 'item
                     :tag (concat (self/glyph "\uF071" "!")
                                  " 未授予存储权限：点我授权（笔记/文件需要）")
                     :action (lambda (&rest _)
                               (self/android-request-storage-access))
                     :button-face 'self/dashboard-warning
                     :mouse-face 'highlight
                     :button-prefix "" :button-suffix ""
                     :format "%[%t%]")
      (dashboard-center-text beg (point)))
    (insert "\n")))

;; ─── 抓笔记：触屏模板选择面板 ───────────────────────────────────────
;; org-mks（*Org Select*）以 `read-key-exclusive' 读键盘字符，tap 事件
;; 无法选中且每次触摸触发一轮重绘，触屏上不可用；改 widget 按钮直达。

(defvar self/capture-menu-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'widget-button-click)
    (define-key map (kbd "<touchscreen-begin>") #'widget-button-click)
    map))

(define-derived-mode self/capture-menu-mode special-mode "抓笔记"
  "触屏 capture 模板选择面板。"
  (setq-local touch-screen-display-keyboard nil))

(defun self/capture--open (keys)
  "返回调 org-capture 模板 KEYS 的 widget action：当前窗显示并唤起键盘。"
  (lambda (&rest _)
    (require 'org-capture)
    ;; org 默认 split 显示 CAPTURE buffer，单窗机强制占当前窗
    (let ((display-buffer-overriding-action '((display-buffer-same-window))))
      (org-capture nil keys))
    (self/touch-show-keyboard)))

(defun self/capture-menu (&rest _)
  "打开触屏友好的抓笔记模板选择面板（条目取自 `org-capture-templates'）。"
  (interactive)
  (require 'org-capture)
  (switch-to-buffer (get-buffer-create "*抓笔记*"))
  (self/capture-menu-mode)
  (let ((inhibit-read-only t))
    (erase-buffer)
    (insert (propertize "  选择抓笔记模板\n\n" 'face 'self/dashboard-hero))
    ;; 过滤 :immediate-finish 隐藏模板（如剪贴板速存，无输入环节）
    (dolist (entry (seq-remove (lambda (e) (memq :immediate-finish e))
                               org-capture-templates))
      (widget-create 'item
                     :tag (concat " " (nth 1 entry) " ")
                     :action (self/capture--open (car entry))
                     :button-face 'self/dashboard-button
                     :mouse-face 'highlight
                     :button-prefix " "
                     :button-suffix " "
                     :format "%[%t%]")
      (insert "\n"))
    (goto-char (point-min))))

;; ─── 渲染窗口定位与重绘 ────────────────────────────────────────────
;;
;; daemon 启动后同时存在哑 initial frame 与真实 client frame，dashboard
;; 可能被 switch-to-buffer 泄漏到前者；版心、路径与居中偏移全部取自 selected
;; window，取错 frame 即整屏排版皆错，故先定位出「client frame 里显示
;; dashboard 的窗口」，后续渲染与装饰都在该窗口的 selected 上下文里执行。

(defvar self/dashboard--rendered-width nil
  "上次渲染 dashboard 时的窗口正文宽度。
渲染宽度与目标窗口相符时跳过全量重渲染(frame 就绪回调与 resize
合并刷新共用),不符才重刷。")

(defun self/dashboard--client-window-p (w)
  "窗口 W 是否开在带 `client' 参数的 client frame 里。
daemon 的哑 initial frame 没有该参数,返回 nil。"
  (frame-parameter (window-frame w) 'client))

(defun self/dashboard--dashboard-window ()
  "返回 client frame 中显示 dashboard 的窗口,无则 nil。
必须过滤掉 daemon 的 initial frame(它没有 `client' 参数):switch-to-buffer
会把 dashboard 泄漏到那个超宽的哑 frame 上,误选它版心宽度就错了。"
  (let (found)
    (dolist (w (get-buffer-window-list dashboard-buffer-name nil 0))
      (when (and (not found) (self/dashboard--client-window-p w))
        (setq found w)))
    found))

(defun self/dashboard--refresh-in-window (&optional win)
  "在显示 dashboard 的窗口 WIN 上下文里强制重渲染并装饰。
WIN 缺省重新定位 dashboard 窗口;调用方已持有时透传,避免二次
get-buffer-window 查询。渲染与装饰都必须以该窗口为 selected:版心、
路径缩短和居中前缀的宽度全部取自这里,别的 frame 上下文算出来是错的。"
  (when-let* ((win (or win (self/dashboard--dashboard-window))))
    (with-selected-window win
      (setq self/dashboard--rendered-width (window-body-width win))
      (dashboard-open)
      (self/dashboard--decorate-headings win))))

;; ─── 标题装饰三步 ──────────────────────────────────────────────────

(defun self/dashboard--heading-overlay-p (ov)
  "OV 是仍然有效的板块标题 overlay 时返回 t。
重渲染后旧 overlay 塌缩成空壳(起止位置相等)仍残留在 buffer 里,
按起止位置把它们剔除。"
  (and (eq (overlay-get ov 'face) 'dashboard-heading)
       (> (overlay-end ov) (overlay-start ov))))

(defun self/dashboard--heading-overlays ()
  "收集 dashboard buffer 内有效的标题 overlay,按位置排序返回。"
  (let (ovs)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (self/dashboard--heading-overlay-p ov)
        (push ov ovs)))
    (sort (nreverse ovs)
          (lambda (a b) (< (overlay-start a) (overlay-start b))))))

(defun self/dashboard--replace-section-separator (ov separator)
  "把板块尾第一段空行换成 SEPARATOR,并为板块内行加行间距。
OV 是板块标题 overlay。板块边界 = 标题行后第一个空行:从标题行起
一遍扫描,顺手收集行范围;扫到空行即边界,走到 point-max 仍无
空行则整体跳过(末板块无分割线)。"
  (save-excursion
    (goto-char (overlay-start ov))
    (let ((lines '())
          blank)
      (while (and (not blank) (< (point) (point-max)))
        (let ((beg (line-beginning-position))
              (end (line-end-position)))
          (if (= end beg)
              (setq blank t)
            (push (cons beg end) lines)
            (forward-line 1))))
      (when blank
        (dolist (line lines)
          (put-text-property (car line) (cdr line)
                             'line-spacing self:dashboard-line-spacing))
        (delete-region (line-beginning-position) (line-end-position))
        (insert separator)))))

(defun self/dashboard--indent-heading (ov)
  "标题行缩进 `self:dashboard-heading-indent' 列,并把 OV 拨回原位。
heading overlay 是 front-advance:TTY 无 icon 时其起点恰在行首,行首
插入的缩进会被吞进 overlay(display 替换后消失)。记住原文本范围,
插入后把 overlay 拨回。缩进继承行首的 line-prefix,否则标题行脱离
板块整体缩进。"
  (goto-char (overlay-start ov))
  (let ((line-start (line-beginning-position))
        (off-s (- (overlay-start ov) (line-beginning-position)))
        (off-e (- (overlay-end ov) (line-beginning-position))))
    (goto-char line-start)
    (let ((prefix (get-text-property line-start 'line-prefix)))
      (insert (propertize
               (make-string self:dashboard-heading-indent ?\s)
               'line-prefix prefix
               'line-spacing self:dashboard-line-spacing))
      (move-overlay ov
                    (+ line-start self:dashboard-heading-indent off-s)
                    (+ line-start self:dashboard-heading-indent off-e)))))

(defun self/dashboard--suffix-heading-key (ov key width icon-w)
  "把 KEY 右贴到标题行行尾,补齐到 WIDTH 版心宽(先扣掉 ICON-W 图标宽)。
OV 提供标题显示文本,用于折算已占用宽度;须在
`self/dashboard--indent-heading' 之后调用,point 此时落在标题行。"
  (let* ((name (or (overlay-get ov 'display)
                   (buffer-substring-no-properties
                    (overlay-start ov) (overlay-end ov))))
         (used (+ self:dashboard-heading-indent icon-w
                  (string-width name))))
    (goto-char (line-end-position))
    (insert (concat
             (make-string
              (max 1 (- width used (string-width key))) ?\s)
             (propertize key 'face 'font-lock-comment-face)))))

;; ─── 版心居中 ──────────────────────────────────────────────────────

(defun self/dashboard--center-line (body-width)
  "把当前行按自身行宽居中(行首加 align-to 前缀);超过 BODY-WIDTH 不加。
行宽用插件的 dashboard-str-len 按像素量:string-width 会把 ─ ═ 这类
ambiguous 字符按双列计、GUI 实际渲染单列,居中会偏。"
  (let* ((beg (line-beginning-position))
         (end (line-end-position))
         (w (dashboard-str-len (buffer-substring-no-properties beg end))))
    (when (and (> w 0) (<= w body-width))
      (let ((p (propertize
                " " 'display
                `(space . (:align-to (- center ,(/ w 2)))))))
        (add-text-properties beg end
                             (list 'line-prefix p 'indent-prefix p))))))

(defun self/dashboard--center-groups (ovs width window)
  "分组居中:板块区统一版心前缀,其余行逐行自身居中。
先 remove-text-properties 再改写——banner/Welcome/navigator/footer 都带
插件自设的测量式前缀,而 add-text-properties 不覆盖已有属性。"
  (remove-text-properties (point-min) (point-max)
                          '(line-prefix nil indent-prefix nil))
  (let* ((sec-beg (save-excursion
                    (goto-char (overlay-start (car ovs)))
                    (line-beginning-position)))
         (sec-end (save-excursion
                    (goto-char (point-max))
                    (search-backward "─" nil t)
                    (line-end-position)))
         (block-prefix (propertize
                        " " 'display
                        `(space . (:align-to (- center ,(/ width 2))))))
         (body-width (window-body-width window)))
    (save-excursion
      (goto-char (point-min))
      (while (< (point) sec-beg)
        (self/dashboard--center-line body-width)
        (forward-line 1))
      (add-text-properties sec-beg sec-end
                           `(line-prefix ,block-prefix
                                         indent-prefix ,block-prefix))
      (goto-char sec-end)
      (while (and (< (point) (point-max))
                  (progn (forward-line 1) t))
        (self/dashboard--center-line body-width)))))

(defun self/dashboard--decorate-headings (&optional window)
  "渲染后装饰标题行、右贴快捷键、行间距与板块分割线,最后分组居中。
标题行与分割线补齐到版心宽;只从 `self/dashboard--refresh-in-window' 与
`self/dashboard-initial-buffer' 调用。

三步装饰（分割线 / 缩进 / 快捷键右贴）按平台分支：Android 走自绘窄屏版式，
段落的入口键是触屏面板而非 `self:dashboard-heading-keys' 里的键位，右贴
出来只会误导；居中则两平台统一走 `self/dashboard--center-groups'。"
  (when-let* ((window (or window (selected-window))))
    (with-current-buffer (get-buffer dashboard-buffer-name)
      (let* ((width (self/dashboard--content-width window))
             (icon-w (if (and (dashboard-display-icons-p)
                              dashboard-set-heading-icons)
                         2 0))
             (separator (propertize
                         (make-string
                          (max 1 (/ (* width (frame-char-width))
                                    (max 1 (string-pixel-width "─")))) ?─)
                         'face 'shadow))
             (ovs (self/dashboard--heading-overlays))
             (keys (and (not self:android-p) self:dashboard-heading-keys))
             (pairs '())
             (inhibit-read-only t))
        (dolist (ov ovs)
          (when keys
            (push (cons ov (pop keys)) pairs)))
        (dolist (pair pairs)
          (when (cdr pair)
            (self/dashboard--replace-section-separator (car pair) separator)
            (self/dashboard--indent-heading (car pair))
            (self/dashboard--suffix-heading-key
             (car pair) (cdr pair) width icon-w)))
        ;; OVS 为空（该次渲染没产出板块标题）时无从划分板块边界，跳过分组居中
        (when ovs
          (self/dashboard--center-groups ovs width window))))))

;; ─── 启动路由与入口 ────────────────────────────────────────────────

(defun self/dashboard-initial-buffer ()
  "emacsclient 无文件参数时显示 dashboard(作为 `initial-buffer-choice')。
agenda 渲染走 `org-map-entries',先确保惰性加载的 org 就绪。渲染后
立即装饰并记录当时的窗口宽度:frame 就绪回调比较宽度,相符则跳过
重渲染,首帧只渲染一次;GUI daemon 首帧可能仍在哑 frame 上下文渲染
(宽度错),回调比较不符才重渲染自愈。"
  (require 'org-agenda)
  (let ((buffer (dashboard-open)))
    (self/dashboard--decorate-headings)
    (setq self/dashboard--rendered-width (window-body-width))
    buffer))

;; ─── 尺寸防抖与重绘自愈 ────────────────────────────────────────────

(defun self/dashboard--refresh-if-stale ()
  "目标窗口宽度与上次渲染不同时才重渲染 dashboard。
frame 就绪回调与 resize 合并刷新共用:全量渲染(item 生成 + agenda
扫描 + 装饰)成本高,宽度相符就跳过。窗口过窄(版心不足
`self:dashboard-min-content-width')时跳过且不记录宽度——极窄渲染
出来也是破碎的,保留上一次可读的内容,窗口拖宽后宽度仍不匹配,
自然触发重渲染。"
  (when-let* ((win (self/dashboard--dashboard-window)))
    (and (>= (self/dashboard--content-width win)
             self:dashboard-min-content-width)
         (/= (window-body-width win)
             (or self/dashboard--rendered-width 0))
         (self/dashboard--refresh-in-window win))))

(defun self/dashboard--on-frame-make (&rest _)
  "新 client frame 就绪后,渲染宽度不匹配才重渲染自愈。
挂 `server-after-make-frame-hook'。initial-buffer-choice 阶段 selected
window 可能仍是 daemon 旧 frame,首帧版心会按错误宽度装饰且记录下错误
宽度,本回调比较后自愈;宽度相符(正常路径或同宽新帧)则零成本跳过。"
  (run-at-time 0 nil #'self/dashboard--refresh-if-stale))

(defvar self/dashboard--resize-timer nil
  "Resize 合并刷新的 pending idle timer,静止后触发一次。")

(defun self/dashboard--on-resize-idle ()
  "Resize 静止后的合并刷新回调(idle timer)。"
  (setq self/dashboard--resize-timer nil)
  (self/dashboard--refresh-if-stale))

(defun self/dashboard--on-resize (frame)
  "FRAME 尺寸变化时合并重渲染 dashboard,不逐事件全量渲染。
挂 `window-size-change-functions'。拖拽 resize 每个中间宽度一个事件,
逐次渲染会把主循环卡死在连续全量 item 生成上;只挂一个 idle timer,
静止 0.3s 后按最终宽度刷一次。daemon initial frame 的尺寸事件直接
忽略(见 `self/dashboard--dashboard-window')。"
  (when (and (frame-live-p frame)
             (frame-parameter frame 'client)
             (get-buffer-window dashboard-buffer-name frame))
    (unless self/dashboard--resize-timer
      (setq self/dashboard--resize-timer
            (run-with-idle-timer
             0.3 nil #'self/dashboard--on-resize-idle)))))

;; ─── agenda 扫描单次缓存 ───────────────────────────────────────────

(defvar self/dashboard--agenda-once nil
  "单次渲染内的 agenda 结果请求级缓存。
仅渲染入口的 let 绑定内有效;跨渲染不缓存,数据新鲜度与插件原生
行为一致。")

(defun self/dashboard--agenda-scan-once (orig &rest _)
  "dashboard-get-agenda 的 :around advice:单次渲染内只扫一次。
插件 `dashboard-insert-section' 宏对 list 参数求值 4 次(heading
判断 / if 分支 / subseq / section-list 的 car),agenda 的
org-map-entries 全量扫描被重复 4 次,是渲染耗时与 GC 压力的大头;
缓存命中直接复用,未命中扫一次并记住。"
  (or self/dashboard--agenda-once
      (setq self/dashboard--agenda-once (funcall orig))))

(defun self/dashboard--insert-lists-once (orig &rest args)
  "dashboard-insert-startupify-lists 的 :around advice:渲染入口。
let 绑定请求级缓存变量,渲染结束自动丢弃,下次渲染重新扫描。"
  (let ((self/dashboard--agenda-once nil))
    (apply orig args)))

;; ─── 配置与启动 ─────────────────────────────────────────────────────

(defun self/dashboard-insert-gap ()
  "footer 前空隙（与 items 尾部换行合计 2 空行）。"
  (insert "\n"))

;; 启动路由：emacsclient 不带文件参数时才走欢迎屏。
(setq initial-buffer-choice #'self/dashboard-initial-buffer)

;; 两平台共用的插件开关：居中生效、不显示字母快捷键（改用中文 which-key
;; 提示）、heading 图标开启。Android 无键盘，展示快捷键字母无意义。
(setq dashboard-center-content t
      dashboard-show-shortcuts nil
      dashboard-set-heading-icons t)

;; 自绘段 generator：recents / roam 两段在两平台都用移动端的窄屏实现
;; （图标 + 中截标签 + 条目间空行），宽屏平台也不再退回官方 recents 段。
(setf (alist-get 'recents dashboard-item-generators)
      #'self/dashboard-insert-recents)
(setf (alist-get 'roam dashboard-item-generators)
      #'self/dashboard-insert-roam)

(if self:android-p
    (progn
      ;; ─── Android：整条视觉层自绘 ──────────────────────────────
      ;; 约 40 列宽度下官方 ASCII banner 与多段 items 会挤成一团，故
      ;; `dashboard-startupify-list' 整条接管：hero（盲文 logo + 问候 +
      ;; 日期/启动信息）替换官方 banner/标题，自绘 navigator 与 footer
      ;; 替换官方对应段。段距由自绘 generator 的首尾换行控制，故官方
      ;; page-separator 保持默认值（桌面端排版依赖它划分章节边界）。
      (setq dashboard-startupify-list
            '(self/dashboard-insert-hero
              self/dashboard-insert-navigator
              self/dashboard-insert-permission-notice
              dashboard-insert-items
              self/dashboard-insert-gap
              dashboard-insert-footer))
      (setq dashboard-items '((recents . 4) (roam . 4)))
      ;; 名言池长度均 ≤34 列（含图标 footer 居中不折行）
      (setq dashboard-footer-messages
            '("Learn Emacs once, use it forever."
              "Only Emacs can save your soul."
              "Lisp is a building material."
              "Everything is a buffer."
              "C-x M-c M-butterfly"
              "Org-mode is a way of life."
              "Real programmers count from zero."
              "Escape Meta Alt Control Shift"
              "Emacs is not just an editor."))
      ;; footer：随机名言 + 心形图标（tty 回退普通字符）
      (setq dashboard-footer-icon
            (propertize (self/glyph "\uF004" "♥")
                        'face 'self/dashboard-deco-icon)))
  (progn
    ;; ─── 宽屏：官方 banner / navigator / footer + 桌面三段 items ───
    (require 'nerd-icons)
    (setq dashboard-icon-type 'nerd-icons
          dashboard-heading-icons '((recents . "nf-oct-history")
                                    (agenda . "nf-oct-calendar")
                                    (projects . "nf-oct-rocket"))
          dashboard-startup-banner 'ascii
          dashboard-banner-ascii self:dashboard-banner-ascii
          dashboard-set-navigator t
          dashboard-items '((agenda . 5) (recents . 6) (projects . 6))
          dashboard-projects-backend 'project-el
          dashboard-projects-switch-function #'project-switch-project
          dashboard-week-agenda nil
          dashboard-filter-agenda-entry #'dashboard-filter-agenda-by-todo
          dashboard-agenda-sort-strategy '(time-up)
          dashboard-agenda-prefix-format "%i %s"
          dashboard-agenda-release-buffers t
          dashboard-item-names '(("Agenda for today:" . "待办")
                                 ("Recent Files:" . "最近文件")
                                 ("Projects:" . "项目"))
          dashboard-navigator-buttons (list (self/dashboard--nav-buttons)))
    ;; 路径缩短走本文件的两级降级覆写；agenda 扫描走单次缓存；渲染入口
    ;; 绑定请求级缓存变量。
    (advice-add 'dashboard-shorten-path :override
                #'self/dashboard--shorten-path)
    (advice-add 'dashboard-get-agenda :around
                #'self/dashboard--agenda-scan-once)
    (advice-add 'dashboard-insert-startupify-lists :around
                #'self/dashboard--insert-lists-once)
    ;; 帧就绪与 resize 的合并重绘只在宽屏平台启用：Android 的窗口尺寸由
    ;; 旋转/分屏驱动，重绘代价（两次目录扫描 + 条目生成）远大于收益。
    (add-hook 'server-after-make-frame-hook #'self/dashboard--on-frame-make)
    (add-hook 'window-size-change-functions #'self/dashboard--on-resize)))

(provide 'self-dashboard)
;;; self-dashboard.el ends here
