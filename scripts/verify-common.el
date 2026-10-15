;;; verify-common.el --- UniEmacs 验证脚本共用的 batch 辅助 -*- lexical-binding: t; -*-
;;;
;;; 被 scripts/smoke-profile.sh 以 `emacs --batch -q -l verify-common.el ...'
;;; 加载。冒烟需要的不只是「进程没崩」，而是启动链真的走完了——
;;; 所以这里只放一个哨兵函数。
;;;
;;; 关键背景：Guix 的 emacs 是 guile wrapper，会吞掉子进程退出码
;;; （kill-emacs 7 → rc=0）。判定一律以本文件打印的哨兵行为准，
;;; 不看 emacs 进程退出码。

;;; Commentary:
;;; verify/smoke-sentinel 打印 SMOKE-DONE 行，带当前 profile 与已加载的
;;; self-* feature 列表，供外层脚本与人工核对启动链实际加载了哪些模块。

;;; Code:

(defun verify/features-of-prefix (prefix)
  "返回 features 中所有以 PREFIX 开头的符号名列表。"
  (sort (seq-filter (lambda (f) (string-prefix-p prefix (symbol-name f)))
                    features)
        (lambda (a b) (string< (symbol-name a) (symbol-name b)))))

(defun verify/smoke-sentinel ()
  "冒烟哨兵：确认启动链走完并打出实际加载的 self-* 模块清单。
外层脚本以 `SMOKE-DONE' 行为通过依据（Guix wrapper 吞退出码）。"
  (message "SMOKE-DONE profile=%s repo=%s features=%s"
           (if (boundp 'self:profile) (symbol-name self:profile) "?")
           (or (and (boundp 'self:repo) self:repo) "?")
           (mapconcat #'symbol-name (verify/features-of-prefix "self") ",")))

(provide 'verify-common)
;;; verify-common.el ends here
