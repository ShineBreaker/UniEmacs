;;; self-compat.el --- Emacs 31 版本兼容 shim：arei Scheme 染色兜底 -*- lexical-binding: t; -*-

;; SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Profiles: full
;; Requires: 无
;; Packages: 无
;;
;; 移植自桌面端配置「实验性与待确认」一节。该节在源配置里是整份配置的
;; noweb 定义中心：正文里的片段都带 `:tangle no' 与 `:noweb-ref'，由靠前
;; 章节以顶格 `<<emacs31/...>>' 展开进 tangle 产物。之所以集中堆在文件
;; 尾部而不是就地展开，是因为版本兜底代码应当在同一个地方可追踪、可
;; 统一清理——上游修好后删掉整段即可，不必满仓库找零散 workaround。
;;
;; 本文件只保留这些 shim 本身；它们原本的 noweb 引用点已由上游章节改写
;; 为对 `self--maybe-enable-arei-mode' 的直接调用（见下方「引用点」）。
;;
;; Shim 清单（名字 / 根因 / 受影响功能 / 移除条件）：
;;
;;   emacs31/source-load-compat
;;     根因：Guix 产出的 .elc 与 Emacs 31 的宏展开不兼容
;;     受影响：arei（Scheme 语义染色）
;;     移除：所有相关包改由 Emacs 31 重新编译
;;
;;   emacs31/arei-compat
;;     根因：arei 0.9.7 的 .elc 在旧 Emacs 下编译，与 Emacs 31 新增的
;;           `buffer-local-set-state' 宏不兼容（bug#80812），在
;;           scheme-mode-hook 里抛异常，Scheme 高亮整个失效
;;     受影响：各语言 major mode 里的 Scheme 染色
;;     移除：升级 arei，或让 Guix 改用 Emacs 31 重新编译
;;
;; 引用点（源配置 grep 统计）：
;;   `<<emacs31/source-load-compat>>' 与 `<<emacs31/arei-compat>>'
;;   在正文里各被引用 1 次，都集中在「各语言 major mode」那一段的
;;   arei 声明之前——原样是把这两段代码摊进去，紧接着才是
;;   `(use-package arei :hook (scheme-mode . self--maybe-enable-arei-mode))'。
;;   在本仓库里该 hook 直接引用 `self--maybe-enable-arei-mode'，本文件
;;   与 self-prog 的加载先后由此确定：self-compat 必须先于 self-prog。
;;
;; 版本分派：根因是 Emacs 31 才有的宏不兼容，所以两个 shim 都只在
;; `(>= emacs-major-version 31)' 下生效；在 30 及更早版本上 arei 的 .elc
;; 本来就可用，强制从 .el 加载只是白费一次解析。
;;
;; 三档都登记的原因：shim 是纯函数、无副作用、无第三方包依赖，定义它
;; 本身没有成本，minimal 档不装 arei 也就永远不会触发——但这样
;; `self--maybe-enable-arei-mode' 这个名字在任何档位都存在，别的模块
;; 往 scheme-mode-hook 上挂它不会踩到未定义函数。

;;; Code:

(defun self/load-library-from-source (library)
  "从 LIBRARY 对应的 .el 源加载，绕过与 Emacs 31 宏展开不兼容的 Guix .elc。
返回 t 若成功，否则记一条消息并返回 nil。

为什么不能靠别的方式绕过去：GNU store 只读，没法删掉坏 .elc；而
store 里的 .el 与 .elc 时间戳都是 epoch 1，`load-prefer-newer' 判不出
新旧，于是只能显式拼出 .el 路径直接 `load'。这正是 Emacs 31 需要
source-load-compat 这层兜底的原因。

LIBRARY 找不到对应 .el（比如包只带了 .elc）时返回 nil，由调用方决定
是继续还是放弃——这里不代调用方做主。"
  (condition-case err
      (when-let* ((found (locate-library library))
                  (source (concat (file-name-sans-extension found) ".el"))
                  ((file-exists-p source)))
        (load source nil t t)
        t)
    (error
     (message "[ERROR] %s 从源加载失败: %S" library err)
     nil)))

(defun self--maybe-enable-arei-mode ()
  "在真实 Scheme 编辑 buffer 中启用 `arei-mode'（跳过 org src 临时 buffer）。

org 在导出/预览时会把代码块复制进名为 ` *org-src-fontification:' 的
临时 buffer 并在那里跑 major mode hook；那里没有真正的文件名与
目录上下文，让 arei 去猜类型只会得到噪声，所以直接跳过。

为什么给 `arei-mode' 本身也包一层 condition-case：它是个 minor-mode，
启用失败绝不该连带掐掉 scheme-mode-hook 的后续步骤——尤其是
font-lock 的初始化，那才是用户真正要的语法高亮。宁可没有语义染色，
也不能连普通高亮一起丢。"
  (unless (string-prefix-p " *org-src-fontification:" (buffer-name))
    ;; Emacs 31 才需要从 .el 加载：arei 0.9.7 的 .elc 是在旧 Emacs 下
    ;; 编译的，展开不认 31 新增的 `buffer-local-set-state' 宏。30 及更早
    ;; 版本直接让 arei-mode 自己 autoload 对应的 .elc 即可。
    (when (>= emacs-major-version 31)
      (unless (featurep 'arei)
        (self/load-library-from-source "arei")))
    (condition-case err
        (arei-mode 1)
      (error
       (message "[ERROR] arei-mode 启用失败,Scheme 染色不受影响: %S" err)))))

(provide 'self-compat)
;;; self-compat.el ends here
