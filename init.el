;;; init.el --- UniEmacs 引导入口：配 load-path 并按序加载 -*- lexical-binding: t; -*-

;;; Commentary:
;; 固定入口，只做三步：core/、modules/、profiles/ 三目录加入 load-path，
;; 按序 require self-lib、self-package，再加载当前 profile。
;; 模块顺序即依赖顺序，由各 profile 文件内的 require 序列声明。
;;
;; Profiles: all
;; Requires: self-lib self-package
;;
;; 部署形态：本文件与 early-init.el 复制到 Emacs 家目录，仓库本体另行
;; clone（桌面任意位置、Android 在 Termux 家目录惯例位置），位置靠
;; early-init 解析出的 `self:repo' 指过去。加载失败时先看
;; `M-x self/deploy-diagnose' 的诊断结论。

;;; Code:

;; early-init 未运行（入口副本缺失或过旧）时下面两个变量未定义：
;; 先声明再用 boundp 兜底，避免 void-variable 盖掉真正的错误信息。
;; （入口副本过期场景的合法守卫，非常驻防御逻辑。）
(defvar self:repo)
(defvar self:profile)

(unless (and (boundp 'self:repo) self:repo)
  (setq self:repo nil))
(unless (and (boundp 'self:profile) self:profile)
  ;; early-init 未运行的兜底：按平台推断，与 early-init 的回退逻辑一致，
  ;; 避免 Android 入口副本缺失时误装桌面档。
  (setq self:profile (if (eq system-type 'android) 'portable 'full)))

;; ─── 部署诊断（不依赖 modules，require 失败后仍可用） ─────────────

(defun self/deploy--conclusion ()
  "返回针对当前状态的诊断结论字符串。"
  (cond
   ((null self:repo)
    "self:repo 未解析：UNI_EMACS_REPO 未设、家目录下无 repo-location.el、本文件也不在仓库内。按本文件头部的部署形态检查。")
   ((not (file-directory-p (expand-file-name "core" self:repo)))
    (format "self:repo=%s 下缺少 core/ 目录：clone 不完整，或 repo-location.el 指向了错误位置。" self:repo))
   ((and (eq system-type 'android)
         (not (file-equal-p user-emacs-directory self:repo)))
    "仓库可达，但 user-emacs-directory 未重定向到仓库：Emacs 家目录的 early-init.el 是旧版或未复制，重新复制两个入口文件。")
   ((eq system-type 'android)
    "部署链路正常。")
   (t "桌面环境：代码从 self:repo 加载，状态落在 HOME 下的隔离目录，仓库目录保持只读。")))

(defun self/deploy-diagnose ()
  "弹出 buffer 显示部署链路诊断与结论。
不依赖 modules，require 失败后仍可调用排查。"
  (interactive)
  (let ((buf (get-buffer-create "*UniEmacs 部署诊断*")))
    (with-current-buffer buf
      (fundamental-mode)
      (erase-buffer)
      (insert
       (format
        "system-type:            %S
window-system:          %S
self:profile:           %S
self:repo:              %s
  仓库存在：            %s
  仓库 core/ 存在：     %s
  仓库 modules/ 存在：  %s
  仓库 profiles/ 存在： %s
user-emacs-directory:   %s
core/ 在 load-path：    %s
包后端：                %s
git 可用：              %s
ripgrep (rg) 可用：     %s
sqlite3 CLI 可用：      %s
native-comp 可用：      %S

结论：
%s"
        system-type (window-system)
        self:profile
        (or self:repo "(未解析)")
        (and self:repo (file-directory-p self:repo))
        (and self:repo
             (file-directory-p (expand-file-name "core" self:repo)))
        (and self:repo
             (file-directory-p (expand-file-name "modules" self:repo)))
        (and self:repo
             (file-directory-p (expand-file-name "profiles" self:repo)))
        user-emacs-directory
        (and self:repo
             (member (expand-file-name "core" self:repo) load-path)
             t)
        ;; self-package 未加载（如 require 失败）时不让诊断本身报错。
        (if (fboundp 'self/package-backend)
            (self/package-backend)
          "未知（self-package 未加载）")
        (executable-find "git")
        (executable-find "rg")
        (executable-find "sqlite3")
        (native-comp-available-p)
        (self/deploy--conclusion)))
      (goto-char (point-min)))
    (pop-to-buffer buf)))

;; ─── 入口：Android 转发或本体 ─────────────────────────────────────

(if (and self:repo
         (eq system-type 'android)
         (file-directory-p (expand-file-name "core" self:repo))
         (not (file-equal-p user-emacs-directory self:repo)))
    ;; user-emacs-directory 未经 early-init 重定向（副本缺失或过旧）：
    ;; 手动转发到仓库 init.el，由它走下面的本体。
    (progn
      (setq user-emacs-directory self:repo)
      (load (expand-file-name "init.el" self:repo) nil t))

  ;; 本体。
  (progn
    ;; 仓库根不可用时给出有信息量的错误，而不是裸 Cannot open load file。
    (unless (and self:repo
                 (file-directory-p (expand-file-name "core" self:repo)))
      (error "UniEmacs: 仓库根不可用（self:repo=%S）。期望结构：仓库根下含 core/、modules/、profiles/ 三个目录；桌面把 early-init.el 与 init.el 放入 Emacs 家目录（~/.config/emacs/ 或 ~/.emacs.d/），仓库本体 clone 到任意位置并用 UNI_EMACS_REPO 环境变量或家目录下 repo-location.el 指过去；Android 把两个入口文件放入 Emacs 的 ~/.emacs.d/，仓库本体放在 Termux 家目录惯例位置"
             self:repo))

    (dolist (dir '("core" "modules" "profiles"))
      (add-to-list 'load-path (expand-file-name dir self:repo)))

    (require 'self-lib)
    (require 'self-package)
    (self/load-profile self:profile)))

(provide 'self-init)
;;; init.el ends here
