;;; self-ide-slots.el --- 三槽位窗口布局契约（左树 / 底面板 / 编辑区） -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: ide
;; Requires: self-windowing（`self/display-buffer-in-main-window'）、
;;           self-terminal（`self/open-terminal'）、self-keys（`self/bind'）
;; Packages: 无
;;
;; Zed 式三槽位布局：左侧文件树（Treemacs 自管 side-window）、底部面板
;; （终端与一切辅助 buffer）、右上剩余区域的编辑器。full 档的窗口路由
;; 是「按名单弹底」——名单外的包弹窗落到哪全看运气；本模块把它收紧成
;; 槽位契约：**任何 buffer 显示请求必须落在三个槽位之一，未声明的一律
;; 进底槽**。这正是用户以前在同类布局里踩过的坑（插件开 buffer 时把
;; 终端窗口顶掉/跑到主区乱切）的根治办法。
;;
;; 实现靠 `display-buffer-alist' 的优先级结构，分两层注册：
;;
;;   调用方 ──display-buffer──▶ ① overriding-action（包显式指定，最高）
;;                              ② alist 从头扫描，首个 CONDITION 命中者
;;                              ③ base-action
;;                              ④ 调用方传进来的 ACTION 参数（最后兜底）
;;
;; 关键点在②：alist 条目按从前到后顺序取第一个 CONDITION 匹配的条目，
;; 一旦命中，④里包自带的 action（same-window、pop-up-frame 之类）根本没
;; 机会执行——所以兜底条目能把「插件自己决定弹哪」的请求全部收编。
;; 两条注册：
;;
;; · 声明条目 `self/ide--declared-p' 被 push 到 alist 最前：凡是
;;   `self:ide-slot-rules' 声明过的 buffer（如 magit-status → editor）
;;   压过 self-windowing 里 "^magit: " 之类的共享旧规则；
;; · 兜底条目 `self/ide--routable-p' append 到末尾：其余 buffer 由
;;   `self/ide--slot-for-buffer' 分类——文件 buffer 与无 *...* 特征的
;;   普通 buffer 进编辑区，*...* 辅助 buffer 进底槽。
;;
;; 槽位与 side-window 的对应：底槽是 bottom/slot-0 的唯一 side-window，
;; 与 self-windowing、self-terminal 既有规则共享同一窗口（那些规则不
;; 写 slot 默认也是 0，多 buffer 轮播共用一窗，正是「底槽」语义）；
;; 编辑区 = 全部非 side-window（`self/display-buffer-in-main-window'
;; 取最上方的那个，用户可再手动分屏）；左槽由 Treemacs 自己占住，
;; 不经本模块路由。
;;
;; 已知管不到的口子（不防御，了解即可）：`set-window-buffer' 直写、
;; `window-state-put' 整树恢复、`switch-to-buffer' 同窗替换——这些不走
;; display-buffer，任何 alist 方案都拦不住，但也不会破坏槽位结构本身。
;; `delete-other-windows' 与 `split-window' 对 side-window 天然免疫/报错，
;; 左树与底槽不会被包误删或误切分。

;;; Code:

(declare-function self/display-buffer-in-main-window "self-windowing"
                  (buffer &optional alist))
(declare-function self/open-terminal "self-terminal" (&optional arg))
(declare-function self/bind "self-keys"
                  (key target description group &rest properties))

;; ─── 槽位声明表 ──────────────────────────────────────────────────
;; 每条 (KIND MATCH SLOT)：KIND=name 按 buffer 名正则匹配，KIND=mode
;; 按 major-mode 符号匹配；SLOT 取 editor/left/bottom。默认只声明
;; 「必须是整页内容」的 buffer——Zed 里它们都是中心 tab 而非底部面板。
;; COMMIT_EDITMSG、终端、Help、编译输出等已由 self-windowing 共享规则
;; 覆盖（提交消息进编辑区、其余进底槽），此处不重复声明。

(defconst self:ide-slot-rules
  '((mode magit-status-mode    editor)   ; Git 主视图 = 中心 tab
    (mode magit-diff-mode      editor)   ; 完整 diff 视图
    (mode diff-mode            editor)   ; 读 diff 是编辑区工作
    (mode agent-shell-mode     editor)   ; agent 面板归入编辑区 tab
    (mode dired-mode           editor)   ; 目录列表 = 内容 tab
    (mode debugger-mode        editor)   ; *Backtrace* 需要整页
    (mode org-agenda-mode      editor)   ; agenda 是主视图
    (mode eww-mode             editor)   ; 网页阅读 = 内容
    (mode Info-mode            editor)   ; 手册阅读 = 内容
    (mode telega-root-mode     editor)   ; telega 主界面
    (name "\\`\\*Org Src "     editor)   ; org-src 编辑块
    (name "\\`\\*Newsticker"   editor))  ; newsticker 视图
  "槽位声明表：每条 (KIND MATCH SLOT)。
KIND = name 时 MATCH 是 buffer 名正则；KIND = mode 时 MATCH 是
major-mode 符号。SLOT 取 editor/left/bottom 之一。
调整布局只改本表，不改分类逻辑。")

;; ─── 豁免名单 ────────────────────────────────────────────────────
;; 条件函数对豁免 buffer 返回 nil，display-buffer 继续走调用方自带
;; action——「豁免」不是丢进默认槽，而是完全保持该包原来的弹出行为。

(defconst self:ide-slot-exempt-names
  '("\\` "                              ; 空格前缀：隐藏内部 buffer
    "\\`\\*Ediff Control Panel\\*\\'"   ; ediff 自管窗口布局
    "\\`\\*Minimap")                    ; minimap 自建窗口，不经路由
  "豁免路由的 buffer 名正则：这些 buffer 保持包自带弹出行为。")

(defun self/ide--exempt-name-p (name)
  "BUFFER 名 NAME 是否命中豁免名单。"
  (seq-some
   (lambda (regexp) (string-match-p regexp name))
   self:ide-slot-exempt-names))

;; ─── 分类器 ──────────────────────────────────────────────────────

(defun self/ide--declared-slot (buffer)
  "查 `self:ide-slot-rules'，返回 BUFFER 的声明槽位；未声明返回 nil。"
  (let ((name (buffer-name buffer))
        (rules self:ide-slot-rules)
        (slot nil))
    (while (and rules (not slot))
      (let ((kind  (nth 0 (car rules)))
            (match (nth 1 (car rules)))
            (want  (nth 2 (car rules))))
        (when (pcase kind
                ('name (string-match-p match name))
                ('mode (eq (buffer-local-value 'major-mode buffer) match))
                (_ nil))
          (setq slot want)))
      (setq rules (cdr rules)))
    slot))

(defun self/ide--editor-buffer-p (buffer)
  "未声明 buffer 的编辑器身份判定。
有文件名的 buffer（源码、org、conf）与不带 *...* 特征名的普通 buffer
（如 scratch 以外的用户新 buffer）进编辑区；*...* 形式的辅助 buffer
（*Help*、*Messages*、*transient*、各种包输出）落底槽。"
  (let ((name (buffer-name buffer)))
    (or (buffer-file-name buffer)
        (not (string-match-p "\\`\\*.*\\*\\'" name)))))

(defun self/ide--slot-for-buffer (buffer)
  "BUFFER 应去的槽位：声明表 > 形状分类（编辑器 | 底槽）。"
  (or (self/ide--declared-slot buffer)
      (if (self/ide--editor-buffer-p buffer)
          'editor
        'bottom)))

;; ─── display-buffer 条件与 action ────────────────────────────────
;; CONDITION 回调签名是 (buffer-name action)；action 签名是 (buffer alist)。

(defun self/ide--declared-p (name _action)
  "display-buffer-alist 的 CONDITION：buffer 有槽位声明且不豁免。"
  (and (not (self/ide--exempt-name-p name))
       (get-buffer name)
       (self/ide--declared-slot (get-buffer name))))

(defun self/ide--routable-p (name _action)
  "display-buffer-alist 的 CONDITION：一切非豁免 buffer 都归槽位管。"
  (not (self/ide--exempt-name-p name)))

(defconst self:ide-slot-bottom-alist
  '((side . bottom)
    (slot . 0)
    (window-height . 0.33)
    (window-parameters . ((no-delete-other-windows . t))))
  "底槽的 display-buffer ALIST。
slot=0 与 self-windowing/self-terminal 既有规则一致，共用一个底部
side-window——一次显示一个 buffer，换内容不开新窗，这就是「底槽」。
no-delete-other-windows 让 C-x 1 也删不掉它（side-window 本身已免疫
delete-other-windows，显式标注是为可读性）。")

(defconst self:ide-slot-left-alist
  '((side . left) (slot . 0) (window-width . 0.22))
  "左槽的 display-buffer ALIST：为声明 left 的面板预留；
Treemacs 自己占住本槽，不经此路由。")

(defun self/ide--display-in-slot (buffer _alist)
  "三槽路由 action：按 `self/ide--slot-for-buffer' 分发 BUFFER。
直接调 `display-buffer-in-side-window' / `self/display-buffer-in-main-window'
落地——它们都是普通函数，绕开递归进 display-buffer 的写法（递归会让
兜底条目再次命中，无限循环）。"
  (let ((slot (self/ide--slot-for-buffer buffer)))
    (cond
     ((eq slot 'editor)
      (self/display-buffer-in-main-window buffer))
     ((eq slot 'left)
      (display-buffer-in-side-window buffer self:ide-slot-left-alist))
     (t
      (display-buffer-in-side-window buffer self:ide-slot-bottom-alist)))))

;; 声明层压到 alist 最前（共享规则之前），兜底层垫在最后
;; （共享规则之后、调用方自带 action 之前被命中）。
(push '(self/ide--declared-p (self/ide--display-in-slot))
      display-buffer-alist)
(add-to-list 'display-buffer-alist
             '(self/ide--routable-p (self/ide--display-in-slot))
             t)

;; ─── 底槽开关 ────────────────────────────────────────────────────

(defun self/ide--bottom-window ()
  "当前 frame 的底槽窗口；无则 nil。"
  (seq-find
   (lambda (w) (eq (window-parameter w 'window-side) 'bottom))
   (window-list (selected-frame))))

(defun self/ide-bottom-toggle ()
  "开关底部面板；等价 Zed 的面板开合。
开着则关（buffer 不杀，会话不断）；关着则把终端显示回底槽——
终端是底槽的默认内容，其余辅助 buffer 用时自会顶上来。
交互命令：M-x self/ide-bottom-toggle，也绑在 C-c w b。"
  (interactive)
  (let ((win (self/ide--bottom-window)))
    (if win
        (delete-window win)
      (self/open-terminal))))

(self/bind "C-c w b" #'self/ide-bottom-toggle "底部面板开关" "窗口与面板")

(provide 'self-ide-slots)
;;; self-ide-slots.el ends here
