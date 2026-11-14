;;; verify-ide-keys.el --- 核对 ide 档的 IDEA 全局键 -*- lexical-binding: t; -*-

;;; Commentary:
;; 在 ide 档 init 之后用 -l 加载。不匹配就 error，成功打印 IDE-KEYS-OK。
;; 不单独求值：它读的是已经装好的键图。

;;; Code:

(defvar self:ide-keymap-rebinds)
(defvar self:ide-keymap-binds)
(defvar self:modeline-layout)

(defun verify-ide-keys--expect (key command)
  "全局键 KEY 必须绑到 COMMAND，否则报错退出。
cua 会把 C-v 改成 `cua-paste'（仍然是粘贴），这算通过。"
  (let ((bound (keymap-lookup global-map key)))
    (unless (or (eq bound command)
                (and (eq command 'yank) (eq bound 'cua-paste)))
      (error "IDE-KEYS %s => %s，期望 %s" key bound command))))

(dolist (item self:ide-keymap-rebinds)
  (verify-ide-keys--expect (nth 0 item) (nth 1 item)))
(dolist (item self:ide-keymap-binds)
  (verify-ide-keys--expect (nth 0 item) (nth 1 item)))

(unless (keymapp (keymap-lookup global-map "C-c"))
  (error "IDE-KEYS C-c 不再是前缀"))
(unless (keymapp (keymap-lookup global-map "C-x"))
  (error "IDE-KEYS C-x 不再是前缀"))
(unless (eq (keymap-lookup minibuffer-local-map "C-f") 'forward-char)
  (error "IDE-KEYS 迷你缓冲 C-f => %s" (keymap-lookup minibuffer-local-map "C-f")))
(unless (eq (keymap-lookup global-map "C-z") 'undo)
  (error "IDE-KEYS C-z => %s" (keymap-lookup global-map "C-z")))
(unless (eq (keymap-lookup global-map "C-/") 'comment-line)
  (error "IDE-KEYS C-/ => %s" (keymap-lookup global-map "C-/")))
(unless (eq self:modeline-layout 'idea)
  (error "IDE-KEYS 状态栏布局 => %s" self:modeline-layout))

(message "IDE-KEYS-OK")

;;; verify-ide-keys.el ends here
