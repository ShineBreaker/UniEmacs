;;; self-jupyter.el --- Jupyter 内核 REPL 与 Org Babel 源码块 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: standard, ide
;; Requires: self-lib（`self:var-directory'）、self-keys（`self/bind'、`self/declare-binding-group'）
;; Packages: jupyter
;;
;; 把 Jupyter 内核接进 Emacs，两条使用路径：
;;
;;   · REPL 缓冲：C-c j j 起 python3 内核，像 IPython 一样逐行交互；
;;     在普通源码 buffer 里 C-c C-c 把当前行/选区送进同一个内核。
;;   · Org Babel：`#+begin_src jupyter-python' 块，结果（含图片与
;;     表格）直接留在文档里，适合边写笔记边跑分析。
;;
;; ## 为什么保留 Jupyter 而不是只用 `python-shell'
;;
;; `python-shell' 是"一行命令一张嘴"，没有富输出（DataFrame 表格、
;; 图像、HTML），也没有跨语言内核。Jupyter 协议把这层统一成内核，
;; 同一套键位可接 python / guile / julia。日常写一段脚本仍走
;; `python-shell' 更轻；本模块补的是「交互式分析」这一档。
;;
;; ## 懒加载边界
;;
;; jupyter 全栈（jupyter-client + org-client + websocket/simple-httpd）
;; 首次加载实测约 550ms。REPL 侧全部走 autoload，不起 REPL 就不加载；
;; Org Babel 侧无法懒加载（见下方「Org Babel」一节的原因），改为在首次
;; 加载 Org 时拉起，代价约 0.5s 一次。
;;
;; ## 内核从哪来
;;
;; `jupyter-kernelspec' 通过 `jupyter kernelspec list' 发现内核，命令
;; 与内核都由 Guix profile 提供（`jupyter' 包带 python3/ipykernel，
;; `guix' 包带 scheme 内核）。C-c j r 列出全部内核供选；C-c j j 直连
;; python3。若 `jupyter' 不在 exec-path，REPL 启动会报找不到命令。
;;
;; ## 键位
;;
;; C-c j 前缀组：
;;   j 起 Python REPL   r 选内核起 REPL   c 连接已有内核
;;   e 执行行/选区      b 执行整个 buffer  d 执行当前函数
;;   i 查看对象文档     o 清除执行结果     k 内核信息
;;
;; REPL 内沿用包自带键位：RET 发送、M-n/M-p 翻历史、C-c C-o 清屏。

;;; Code:

(require 'self-lib)

(declare-function self/bind "self-keys" (key target description group &rest properties))
(declare-function self/declare-binding-group "self-keys" (key description))

;; ─── REPL 与求值命令的 autoload ───────────────────────────────────
;;
;; Guix 的 Emacs 包机制通常已经生成这些 autoload；此处显式再声明一遍，
;; 是为了不依赖 site-start 的加载顺序。重复定义 autoload 无副作用。

(autoload 'jupyter-run-repl "jupyter-repl" "启动新的 Jupyter REPL。" t)
(autoload 'jupyter-connect-repl "jupyter-repl" "连接已运行的 Jupyter 内核。" t)
(autoload 'jupyter-eval-line-or-region "jupyter-client" "执行当前行或选区。" t)
(autoload 'jupyter-eval-buffer "jupyter-client" "执行整个 buffer。" t)
(autoload 'jupyter-eval-defun "jupyter-client" "执行当前函数。" t)
(autoload 'jupyter-inspect-at-point "jupyter-client" "查看光标处对象的文档。" t)
(autoload 'jupyter-eval-remove-overlays "jupyter-client" "清除执行结果浮层。" t)
(autoload 'jupyter-kernel-info "jupyter-client" "显示当前内核信息。" t)
(autoload 'jupyter-repl-persistent-mode "jupyter-repl"
  "把 REPL 连接传播到同语言的 buffer。" t)

;; Org 的这两个变量在 ob-core 里定义；此处只为 byte-compile 可见，
;; 不带值（运行时由 with-eval-after-load 保证 org 已加载）。
(defvar org-babel-load-languages)
(defvar jupyter-repl-mode-hook)

;; ─── 包默认值（稍后真正加载时生效）────────────────────────────────

(use-package jupyter
  :defer t
  :custom
  (jupyter-use-zmq t)
  (jupyter-executable "jupyter")
  ;; 普通 buffer 的执行结果以浮层贴在代码下方，不再跳 REPL 看重播。
  (jupyter-eval-use-overlays t)
  ;; 宽图不撑破窗口；0 表示按原尺寸（长图会顶宽窗口）。
  (jupyter-image-max-width 800)
  ;; Org 块第一次执行时自动连内核，不必先手动起 REPL。
  (jupyter-org-auto-connect t)
  (jupyter-org-display-execution-time t)
  ;; 图片等资源落在 var/ 下，不污染打开的项目目录。
  (jupyter-org-resource-directory
   (expand-file-name "jupyter/" self:var-directory))
  ;; REPL 最多保留 4096 行输出，超出截尾，避免长时间会话拖慢重绘。
  (jupyter-repl-maximum-size 4096))

;; ─── Org Babel：jupyter 源码块 ────────────────────────────────────
;;
;; Org 一加载就拉起 ob-jupyter，不能等 autoload。原因有二：
;;   1. 语言别名（`org-babel-execute:jupyter-python'）与
;;      `org-babel-default-header-args:jupyter-python' 的 :kernel 默认值
;;      都在 ob-jupyter 加载时生成；
;;   2. Org 在执行块之前就把 header 参数算好了，autoload 触发时已太晚，
;;      首次执行会报「Need a valid session and a kernel」。
;;
;; 代价是首次打开 Org 文件多约 0.5s（ob-jupyter 全栈）；之后会话内
;; 不再重复。REPL 侧仍是纯 autoload，不碰 Org 时不付这笔钱。

(with-eval-after-load 'org
  (require 'ob-jupyter)
  (add-to-list 'org-babel-load-languages '(jupyter . t)))

;; ─── REPL 建立后的连接传播 ────────────────────────────────────────
;;
;; `jupyter-repl-persistent-mode' 是全局 minor mode：把当前 REPL 的
;; client 传播到之后切过去的、语言相同的 buffer，并自动启用
;; `jupyter-repl-interaction-mode'（C-c C-c / C-M-x / C-c C-b 直达内核）。
;; 只在第一个 REPL 出现后开启，避免它对 switch-to-buffer 的 advice
;; 在纯编辑会话里白跑。

(defun self/jupyter--on-repl-mode ()
  "在 Jupyter REPL 建立后启用连接传播。"
  (jupyter-repl-persistent-mode 1))

(add-hook 'jupyter-repl-mode-hook #'self/jupyter--on-repl-mode)

;; ─── 起 Python 内核的命令 ─────────────────────────────────────────

(defun self/jupyter-run-python ()
  "启动 python3 内核的 Jupyter REPL。
交互命令：C-c j j。

内核名写死 python3：Guix 的 `jupyter' / `python-ipykernel' 固定提供
这个名字（`jupyter kernelspec list' 可见）。要别的内核用 C-c j r。"
  (interactive)
  (jupyter-run-repl "python3"))

;; ─── 键位 ─────────────────────────────────────────────────────────
;; 归 self-keys：一条声明同时完成绑定、中文说明与 which-key 分组。

(self/declare-binding-group "C-c j" "Jupyter（交互式内核）")

(self/bind "C-c j j" #'self/jupyter-run-python "启动 Python 内核 REPL" "Jupyter")
(self/bind "C-c j r" #'jupyter-run-repl "选内核启动 REPL" "Jupyter")
(self/bind "C-c j c" #'jupyter-connect-repl "连接已运行的内核" "Jupyter")
(self/bind "C-c j e" #'jupyter-eval-line-or-region "执行当前行/选区" "Jupyter")
(self/bind "C-c j b" #'jupyter-eval-buffer "执行整个 buffer" "Jupyter")
(self/bind "C-c j d" #'jupyter-eval-defun "执行当前函数" "Jupyter")
(self/bind "C-c j i" #'jupyter-inspect-at-point "查看对象文档" "Jupyter")
(self/bind "C-c j o" #'jupyter-eval-remove-overlays "清除执行结果" "Jupyter")
(self/bind "C-c j k" #'jupyter-kernel-info "内核信息" "Jupyter")

(provide 'self-jupyter)
;;; self-jupyter.el ends here
