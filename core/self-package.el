;;; self-package.el --- 包后端抽象（guix 校验 / elpaca 安装） -*- lexical-binding: t; -*-

;;; Commentary:
;; 各 profile 文件顶部 (setq self:profile-packages ...) 声明本档第三方包
;; 清单，本文件负责按后端执行。minimal 档无第三方包，不碰这份清单。
;;
;; Profiles: all
;; Requires: self-lib（读 `self:cache-directory' 放 elpaca 缓存）
;;
;; 后端只有两种：guix（包由系统层声明安装，Emacs 侧只校验）与 elpaca
;; （其余全部环境，现装现用）。模块体内的 use-package 永不写 :ensure，
;; 装包是 profile manifest 的职责，见下面的 use-package 注记。

;;; Code:

(require 'use-package)
;; use-package 是 Emacs 29+ 内建宏，这里 require 一次，各模块直接用。
;; 不启用 elpaca-use-package-mode：模块体内永不写 :ensure，开了也无事
;; 可做，反而多一层装包钩子——这是深思后的不用，不是缺功能。

(defvar self:cache-directory)

;; self:repo 由 early-init.el 解析，init.el 保证本文件加载时已有效。
;; 声明出来是为了单独编译本文件时不报自由变量警告。
(defvar self:repo)

;; elpaca 在运行时 bootstrap，本文件加载时它还不存在。下面是给编译器
;; 看的声明，避免「自由变量 / 未知函数」警告；运行时 bootstrap 会把
;; 真定义加载进来。
(defvar elpaca-directory)
(defvar elpaca-builds-directory)
(defvar elpaca-sources-directory)
(defvar elpaca-order)
(defvar elpaca-lock-file)

;; package.el 被禁用（见 early-init.el），不 require 它；只声明变量，
;; elpaca 回退装包时才实际赋值。
(defvar package-archives)

;; elpaca 的菜单链变量，前置 lockfile 菜单用；同样只声明，
;; 运行时 (require 'elpaca) 成功后才有真定义。
(defvar elpaca-menu-functions)
(declare-function elpaca-process-queues "elpaca" (&optional filter))
(declare-function elpaca-wait "elpaca" ())
(declare-function elpaca-generate-autoloads "elpaca" (package dir))
(declare-function url-retrieve-synchronously "url"
                  (url &optional silent inhibit-cookies timeout))

;; ─── profile 包清单 ──────────────────────────────────────────────

(defvar self:profile-packages '()
  "本档第三方包清单，由各 profile 文件顶部 setq。
元素为符号（Guix 与 MELPA 同名时直接写，如 magit）或
(MELPA名 . GUIX名) cons（两边名不一致时，如 (corfu . emacs-corfu)）。
`self/package-ensure' 按后端消费这份清单。")

;; ─── 镜像与代理 ──────────────────────────────────────────────────

(defcustom self:elpa-mirror 'tuna
  "ELPA/MELPA 归档镜像源：tuna、ustc 或 nil（官方源）。
只影响 elpaca 回退到 package.el 装包时的归档地址。"
  :type '(choice (const :tag "TUNA" tuna)
                 (const :tag "USTC" ustc)
                 (const :tag "官方" nil))
  :group 'self)

(defcustom self:github-proxy nil
  "GitHub 加速代理前缀（如 \"https://ghproxy.com/\"），nil 表示直连。
仅作用于 elpaca bootstrap 安装脚本的下载地址，不影响其他流量。"
  :type '(choice (const :tag "直连" nil)
                 (string :tag "代理前缀"))
  :group 'self)

(defvar self:elpaca-installer-url
  "https://raw.githubusercontent.com/progfolio/elpaca/master/doc/installer.el"
  "elpaca 官方安装脚本地址。下载时前面拼上 `self:github-proxy'。
上游若搬家改这个变量即可，不用动 bootstrap 逻辑。")

(defvar self:elpaca-lock-file
  (expand-file-name "data/elpaca-lockfile.el" self:repo)
  "elpaca 版本 lockfile 路径：放在仓库 data/ 下（数据文件语义），随仓库提交。
工作流：包升级验证无误后 `M-x elpaca-write-lock-file' 写盘（存这个
路径），此后 bootstrap 经菜单链第一位的 elpaca-menu-lock-file 固定检出
锁定版本；换版本时删对应源码目录后重启。")

(defvar self--missing-packages '()
  "guix 后端下 locate 不到的包名表，供启动后自查。")

;; ─── 后端检测 ────────────────────────────────────────────────────

(defun self/package-backend ()
  "返回包后端符号：guix 或 elpaca。
判定依据（命中任一即 guix）：EMACSLOADPATH 环境变量非空说明 Guix
在管 load-path；或 guix-emacs 库能被 locate；或 load-path 里有目录
名带 guix 气息。Guix 用户环境三者通常全中；其余全部环境走 elpaca。"
  (if (or (let ((ep (getenv "EMACSLOADPATH")))
            (and ep (> (length ep) 0)))
          (locate-library "guix-emacs")
          (let ((found nil))
            (dolist (dir load-path)
              (when (and (stringp dir) (string-match-p "guix" dir))
                (setq found t)))
            found))
      'guix
    'elpaca))

;; ─── 清单归一化 ──────────────────────────────────────────────────

(defun self/package--normalize-list (packages)
  "把包清单统一为 ((MELPA名 . GUIX名) ...) 形式的 alist。"
  (let ((result '()))
    (dolist (item packages)
      (push (if (symbolp item)
                (cons item item)
              item)
            result))
    (nreverse result)))

;; ─── guix 后端：只校验 ───────────────────────────────────────────

(defun self/package--spec-prefixes (name)
  "把 \"a-b-c\" 拆成 (\"a-b-c\" \"a-b\" \"a\") 前缀候选。
用于逐级试探 spec 名：embark-consult.el 随 emacs-embark 分发、
idle-highlight-mode 的 spec 叫 emacs-idle-highlight，剥尾缀即命中。"
  (let ((segs (split-string name "-"))
        (prefixes '()))
    (while segs
      (push (mapconcat #'identity segs "-") prefixes)
      (setq segs (butlast segs)))
    prefixes))

(defun self/package--spec-candidate (name manifest-text)
  "返回库名 NAME 在 MANIFEST-TEXT 中命中的 \"emacs-…\" spec 字符串。
逐级剥 `-` 尾缀试探；都未命中返回 nil。"
  (catch 'found
    (dolist (prefix (self/package--spec-prefixes name))
      (let ((spec (concat "\"emacs-" prefix "\"")))
        (when (string-match-p (regexp-quote spec) manifest-text)
          (throw 'found spec))))))

(defun self/package--missing-spec-lines (missing)
  "把缺失包名表 MISSING 渲染成可粘贴的 spec 行列表。
逐名查仓库 manifest.scm：命中用其中登记的 spec 名（处理
embark-consult→emacs-embark 这类不规则映射），未命中按 `emacs-'
前缀约定给猜测值并标注。"
  (let ((manifest-file (expand-file-name "manifest.scm" self:repo))
        (manifest-text ""))
    (when (file-readable-p manifest-file)
      (setq manifest-text
            (with-temp-buffer
              (insert-file-contents manifest-file)
              (buffer-string))))
    (let ((lines '()))
      (dolist (name missing)
        (let* ((n (symbol-name name))
               (spec (self/package--spec-candidate n manifest-text)))
          (push (cond
                 ((null spec)
                  (format "  \"emacs-%s\"  ; manifest.scm 未命中，按命名约定猜测" n))
                 ((string-equal spec (concat "\"emacs-" n "\""))
                  (concat "  " spec))
                 (t
                  (format "  %s  ; %s 的宿主包（补登后确认该包含此库）" spec n)))
                lines)))
      (nreverse lines))))

(defun self/package--ensure-guix (pkgs)
  "guix 后端：逐个 locate-library，缺失的记入并汇总警告。
Guix 环境的包由系统层（manifest.scm）声明安装，Emacs 侧只校验、
不中断启动：缺包时对应功能不可用，但编辑器照常打开。警告里按
manifest.scm 的登记给出可粘贴的 spec 清单，方便补登。"
  (setq self--missing-packages '())
  (dolist (pkg pkgs)
    (unless (locate-library (symbol-name (cdr pkg)))
      (push (cdr pkg) self--missing-packages)))
  (setq self--missing-packages (nreverse self--missing-packages))
  (when self--missing-packages
    (display-warning
     'self
     (format "以下包在 Guix 环境中找不到（manifest.scm 与部署清单可能不一致），已跳过。\n按 manifest.scm 推测的补登清单：\n%s"
             (mapconcat #'identity
                        (self/package--missing-spec-lines
                         self--missing-packages)
                        "\n")))))

;; ─── elpaca 后端：bootstrap 与安装 ───────────────────────────────

(defun self/package--apply-elpa-mirror ()
  "按 `self:elpa-mirror' 设置 package-archives（elpaca 的回退归档）。
移植自移动端配置的三层镜像思路：这里是第一层归档镜像。"
  (setq package-archives
        (cond
         ((eq self:elpa-mirror 'tuna)
          '(("gnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
            ("nongnu" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/nongnu/")
            ("melpa" . "https://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))
         ((eq self:elpa-mirror 'ustc)
          '(("gnu" . "https://mirrors.ustc.edu.cn/elpa/gnu/")
            ("nongnu" . "https://mirrors.ustc.edu.cn/elpa/nongnu/")
            ("melpa" . "https://mirrors.ustc.edu.cn/elpa/melpa/")))
         (t
          '(("gnu" . "https://elpa.gnu.org/packages/")
            ("nongnu" . "https://elpa.nongnu.org/nongnu/")
            ("melpa" . "https://melpa.org/packages/"))))))

(defun self/package--download-installer (url)
  "下载 URL 的安装脚本并求值，返回 t。
60 秒超时或网络失败时报中文引导错误（弱网走代理或手动 clone）。
脚本多 sexp 且自带 lexical-binding 头，不逐个 eval，落临时文件 load。"
  (require 'url)
  (let ((buf (condition-case nil
                 (url-retrieve-synchronously url 'silent 'inhibit-cookies 60)
               (error nil))))
    (unless buf
      (error "UniEmacs: elpaca 安装脚本下载失败（60 秒无响应）。弱网环境可设置 self:github-proxy 走加速代理，或手动把 elpaca 仓库 clone 到 %s 后重启"
             (expand-file-name "elpaca/sources/elpaca"
                               self:cache-directory)))
    (let ((tmp (make-temp-file "elpaca-installer")))
      (unwind-protect
          (progn
            (with-current-buffer buf
              (goto-char (point-min))
              ;; 跳过 HTTP 响应头（首个空行之后是正文）。
              (re-search-forward "^$" nil 'move)
              (forward-line 1)
              (write-region (point) (point-max) tmp nil 'silent))
            (kill-buffer buf)
            (load tmp nil t))
        (ignore-errors (delete-file tmp))))
    t))

(defun self/package--clone-elpaca (repo)
  "把 elpaca 仓库 clone 到 REPO（含代理前缀），成功返回 t。
不经上游 installer.el：该脚本按交互式加载设计（内部 pop-to-buffer、
-nested emacs -Q byte-recompile），在 batch 预构建里失败后会在 error
handler 里 delete-directory，只留一个空目录，导致后续 require 逐个
失败。这里直接 git clone，batch 下稳定。"
  (let ((url (concat (or self:github-proxy "")
                     "https://github.com/progfolio/elpaca.git"))
        (default-directory (file-name-directory (directory-file-name repo))))
    (make-directory repo t)
    (zerop (call-process "git" nil nil nil
                         "clone" "--depth=1" "--no-single-branch"
                         url repo))))

(defun self/package--bootstrap-elpaca ()
  "备好 elpaca 本体，目录一律在 `self:cache-directory' 下（仓库外）。
已 clone 过直接加载；否则 git clone（失败再退到官方安装脚本）。
目录变量必须用 setq 全局设定，不能用 let：`elpaca-directory' 是
defcustom，`elpaca-builds-directory' 等是由它派生的 defvar；let 绑定
出了本函数作用域就丢，随后在作用域外 `(require \='elpaca)' 加载时
沿用了默认的 `user-emacs-directory'/elpaca，包会被 clone 进仓库目录，
且队列处理时目录对不上导致全部失败。"
  (setq elpaca-directory (expand-file-name "elpaca/" self:cache-directory)
        elpaca-cache-directory (expand-file-name "elpaca/cache/"
                                                 self:cache-directory)
        elpaca-builds-directory (expand-file-name "elpaca/builds/"
                                                  self:cache-directory)
        elpaca-sources-directory (expand-file-name "elpaca/sources/"
                                                   self:cache-directory))
  ;; 下面的 `elpaca-order' let 绑定只给安装脚本回退路径用（脚本自带
  ;; 直连 order，这里绑定优先，clone 也走代理）；直连 git clone 路径
  ;; 的 URL 在 `self/package--clone-elpaca' 里拼代理前缀。
  (let ((elpaca-order `(elpaca :repo ,(concat (or self:github-proxy "")
                                              "https://github.com/progfolio/elpaca.git")
                               :depth 1 :inherit ignore
                               :files (:defaults "elpaca-test.el"
                                                 (:exclude "extensions"))
                               :build (:not elpaca-activate))))
    (let ((repo (expand-file-name "elpaca/" elpaca-sources-directory))
          (build (expand-file-name "elpaca/" elpaca-builds-directory)))
      (add-to-list 'load-path (if (file-exists-p build) build repo))
      (unless (file-exists-p repo)
        (unless (self/package--clone-elpaca repo)
          (ignore-errors (delete-directory repo t))
          (self/package--download-installer
           (concat (or self:github-proxy "") self:elpaca-installer-url))))
      (unless (require 'elpaca-autoloads nil t)
        (require 'elpaca)
        (elpaca-generate-autoloads "elpaca" repo)
        (let ((load-source-file-function nil))
          (load "./elpaca-autoloads"))))))

(defun self/package--ensure-elpaca (pkgs)
  "elpaca 后端：bootstrap 后逐个包入队，处理队列并等待完成。
显式调 elpaca-process-queues + elpaca-wait，不依赖 after-init-hook，
所以 batch/非交互场景也能跑通。版本 pin 走 `self:elpaca-lock-file'。
注意 elpaca 是宏（调用时 quoting 参数），包名来自变量时只能用
eval 拼调用，这是官方用法的动态版，不是炫技。"
  (self/package--apply-elpa-mirror)
  (self/package--bootstrap-elpaca)
  (require 'elpaca)
  ;; lockfile 生效前提：elpaca-menu-lock-file 必须是菜单链第一位
  ;; （见 elpaca 手册 Lock Files 一节；add-to-list 默认前置）。
  (add-to-list 'elpaca-menu-functions 'elpaca-menu-lock-file)
  (setq elpaca-lock-file self:elpaca-lock-file)
  (dolist (pkg pkgs)
    (eval `(elpaca ,(car pkg)) t))
  (elpaca-process-queues)
  (elpaca-wait))

;; ─── 入口 ────────────────────────────────────────────────────────

(defun self/package-ensure ()
  "按 `self:profile-packages' 把本档第三方包备好。
guix 后端只校验（缺失警告、不中断启动）；elpaca 后端安装缺失的包。
清单为空时直接返回：本阶段零外部包，不碰网络。交互调用可重跑。"
  (interactive)
  (let ((pkgs (self/package--normalize-list self:profile-packages)))
    (if (null pkgs)
        (message "UniEmacs: 包清单为空，跳过包管理（后端 %s）"
                 (self/package-backend))
      (if (eq (self/package-backend) 'guix)
          (self/package--ensure-guix pkgs)
        (self/package--ensure-elpaca pkgs)))))

(provide 'self-package)
;;; self-package.el ends here
