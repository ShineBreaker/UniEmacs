;;; verify-probe.el --- 交付前验证：启动后路径探针 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; `just verify' 的启动后段落（移植自移动端配置的同名脚本，符号名改为
;; self/ 命名空间）：batch 冒烟不触发 `emacs-startup-hook'，且 Android
;; 专属分支被 `self:android-p' 守卫跳过——tool-bar 按钮安装、图标资产
;; 解析、仪表盘首屏数据、mode-line 钮组构造这些真机路径在桌面冒烟中
;; 从不运行。本探针在桌面沙箱里显式调用它们。
;;
;; 覆盖边界：只断言桌面可达的路径。定义在 `(when self:android-p …)'
;; 内的触屏件（org 操作面板、vertico 候选点选、appt 系统通知、
;; modifier-bar）桌面无从调用，归真机验证清单（docs/mobile/README.md §7）。
;;
;; 结论以哨兵行输出，不依赖退出码：Guix 的 emacs 是 Guile wrapper，
;; 任何错误的退出码都会被吞成 0；wrapper 只保留执行流，故调用方必须
;; 检查 `VERIFY-PROBE-OK' 是否出现（缺哨兵即失败）。
;;
;; 用法（沙箱 HOME 由调用方隔离）:
;;   emacs --batch -q -l scripts/verify-probe.el

;;; Code:

(require 'cl-lib)

(let* ((this-file (expand-file-name (or load-file-name buffer-file-name)))
       (repo (file-name-directory
              (directory-file-name (file-name-directory this-file)))))
  ;; 探针自带 repo 与 profile：走正规入口（early-init → init.el），与
  ;; 真机加载链一致。profile 取 portable——探针断言的对象（触屏件）都
  ;; 在该档装载。this-file 先 expand-file-name：`-l' 传相对路径时
  ;; load-file-name 是相对名，直接取目录会推不出仓库根。
  (setenv "UNI_EMACS_REPO" repo)
  (setenv "UNI_EMACS_PROFILE" "portable")
  (setq user-emacs-directory repo)
  (condition-case err
      (progn
        (load (expand-file-name "early-init.el" repo) nil t)
        (load (expand-file-name "init.el" repo) nil t)

        ;; 1) 图标资产：tool-bar 10 键 + modifier-bar 8 徽章全部可解析
        ;;    （SVG 重着色 / PBM 徽章 / PNG 兜底回退链，见 self/icon-asset）
        (let ((missing nil))
          (dolist (k '(modbar open save copy paste cut search theme config quick))
            (unless (self/icon-asset (symbol-name k) nil self/bar-icon-height
                                     self/bar-icon-color-light)
              (push k missing)))
          (dolist (k '(control shift meta alt super hyper tab esc))
            (unless (self/icon-asset k t) (push k missing)))
          (when missing
            (error "图标资产缺失: %S（跑 `just icons' 重建）" (nreverse missing))))

        ;; 2) 仪表盘首屏数据：列笔记目录 + 读文件头 #+title:
        (self/dashboard--recent-roam-files 5)

        ;; 3) tool-bar 安装（Android 启动时执行，桌面 init 不执行，显式跑
        ;;    一遍）。断言顺序（keymap 逆序存储，install 末尾反转，真机曾
        ;;    反馈顺序反了）、图标高度契约、SVG 重着色按主题生效
        (self/bar--install)
        (let* ((bindings (cdr tool-bar-map))
               (expected '(modbar open save copy paste cut search theme config quick))
               (keys (mapcar #'car bindings)))
          (unless (equal keys expected)
            (error "tool-bar 顺序异常: %S（期望 %S）" keys expected))
          (dolist (k expected)
            (let* ((mi (cdr (assq k bindings)))
                   (img (plist-get (nthcdr 3 mi) :image)))
              (unless img (error "tool-bar %s 缺少图标" k))
              (unless (equal self/bar-icon-height (image-property img :height))
                (error "tool-bar %s 图标高度 %S（期望 %d）"
                       k (image-property img :height) self/bar-icon-height))))
          (when (image-type-available-p 'svg)
            (dolist (color (list self/bar-icon-color-light self/bar-icon-color-dark))
              (let ((data (image-property
                           (self/icon-asset "open" nil self/bar-icon-height color)
                           :data)))
                (unless (and data (string-match-p (regexp-quote color) data))
                  (error "SVG 重着色未生效：%s 的数据里找不到颜色 %s" "open" color))))))

        ;; 4) dired 下右端钮组省略首项 M-x（40 列窄屏给文件操作钮留宽）
        (let ((normal (string-width (self/mode-line--buttons)))
              (dired (with-temp-buffer
                       (setq major-mode 'dired-mode)
                       (string-width (self/mode-line--buttons)))))
          (unless (< dired normal)
            (error "dired 下 M-x 钮未过滤：常规 %d 列 vs dired %d 列"
                   normal dired)))

        ;; 5) which-key 开启兜底必需：Android 下 idle timer 疑不触发，
        ;;    只挂 idle 会让 which-key 与其触屏翻页钮一起永久失效
        (self/which-key-ensure)
        (unless (bound-and-true-p which-key-mode)
          (error "self/which-key-ensure 调用后 which-key-mode 仍未开启"))

        ;; 6) mode-line 右端只构造一次按钮串：弹性空格与按钮串合并为单个
        ;;    :eval（原先是两个，每次重绘把整组按钮连同 mouse-map 构造两遍）
        (let* ((n 0)
               (counter (lambda (&rest _) (cl-incf n))))
          (advice-add #'self/mode-line--buttons :before counter)
          (unwind-protect
              (progn
                (self/mode-line--right-part)
                (unless (= n 1)
                  (error "self/mode-line--right-part 构造按钮串 %d 次（应 1 次）" n)))
            (advice-remove #'self/mode-line--buttons counter)))

        ;; 7) 存储权限警示：桌面（非 Android）应静默无输出
        (let ((buf (generate-new-buffer " *probe-perm*")))
          (unwind-protect
              (with-current-buffer buf
                (self/dashboard-insert-permission-notice)
                (unless (zerop (buffer-size))
                  (error "桌面环境权限警示应无输出，实际插入: %S"
                         (buffer-string))))
            (kill-buffer buf)))

        ;; 8) org-protocol 分享链路：kp 模板已注册且带 :immediate-finish
        ;;    （分享直达，不弹编辑）；标题 helper 优先取描述、空描述回退
        ;;    正文首行、空内容兜底
        (require 'org-capture)
        (let ((kp (assoc "kp" org-capture-templates)))
          (unless kp (error "org-capture-templates 缺少 kp 协议模板"))
          (unless (memq :immediate-finish kp)
            (error "kp 模板应为 :immediate-finish（分享直达，不弹编辑）")))
        (let ((org-capture-plist '(:description "标题" :initial "正文")))
          (unless (equal (self/org-capture--protocol-heading) "标题")
            (error "协议标题未取 :description")))
        (let ((org-capture-plist '(:description "" :initial "首行\n次行")))
          (unless (equal (self/org-capture--protocol-heading) "首行")
            (error "协议标题未回退正文首行")))
        (let ((org-capture-plist '(:description nil :initial nil)))
          (unless (equal (self/org-capture--protocol-heading) "（分享内容）")
            (error "协议标题空内容兜底失效")))

        ;; 9) eww 钮组与外部打开分派（appt 系统通知出口定义在 android
        ;;    守卫内，归真机清单）
        (let ((s (self/eww--mode-line-buttons)))
          (unless (> (string-width s) 0)
            (error "eww 钮串为空")))
        (unless (fboundp 'self/browse-url-external)
          (error "self/browse-url-external 未定义"))

        ;; 10) 触屏交互的桌面可达部分：撤销/重做键位、expreg 扩选、
        ;;     「选」钮注入 hook（vertico 候选点选与 org 操作面板定义在
        ;;     android 守卫内，归真机清单）
        (unless (eq (key-binding (kbd "C-z")) 'undo-only)
          (error "C-z 未绑定 undo-only: %S" (key-binding (kbd "C-z"))))
        (unless (eq (key-binding (kbd "C-S-z")) 'undo-redo)
          (error "C-S-z 未绑定 undo-redo: %S" (key-binding (kbd "C-S-z"))))
        (unless (memq #'self/expreg--setup-mode-line text-mode-hook)
          (error "text-mode-hook 未挂「选」钮注入"))
        ;; 测的是 self-touch 里 use-package :commands 的 autoload 注册
        ;; （「选」钮按下去要能找到 expreg-expand），与包是否已安装无关
        ;; ——包缺失由 `self/package-ensure' 另行警告。
        (unless (fboundp 'expreg-expand)
          (error "expreg 未安装（autoload 未注册）"))

        (message "VERIFY-PROBE-OK 图标 18/18、仪表盘数据、tool-bar 10 钮、dired 钮组收缩、which-key 兜底、mode-line 单次构造、权限警示静默、kp 模板、eww 接口、撤销键位/expreg 钮"))
    (error
     (message "VERIFY-PROBE-FAIL %s" (error-message-string err))
     (kill-emacs 1))))

;;; verify-probe.el ends here
