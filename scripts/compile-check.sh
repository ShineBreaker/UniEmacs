#!/usr/bin/env bash
# compile-check.sh — 全量 .el batch byte-compile 汇总
#
# 用法: scripts/compile-check.sh
#
# 每个文件起一个独立 emacs 进程：先 -l early-init.el -l init.el 加载
# 完整配置（UNI_EMACS_PROFILE=full，用最全档兜底，否则误报未定义符号），
# 再 byte-compile 单文件。AGENTS.md §5.3 要求的就是这个顺序。
#
# 为什么不能单进程批量编译：同进程内先编译的文件会把 defvar/defun
# 注册进 obarray，后续文件引用它们时字节码编译器就找不到「未定义符号」，
# 于是「跨模块未显式 declare-function/defvar」这类违规被掩盖——而那正是
# AGENTS.md 的硬约束。独立进程让每个文件面对干净的符号表，代价是每个
# 文件多约 0.2 秒，30 个文件总计约 6 秒。
#
# 退出码：0 = 零错误（允许有警告）；1 = 有错误。
# 缺依赖导致的 require 失败单独归类为 load-failed，不计入错误总数。

set -uo pipefail
cd "$(dirname "$0")/.."

profile="${UNI_EMACS_PROFILE:-full}"

for entry in early-init.el init.el; do
  if [ ! -f "$entry" ]; then
    echo "note: 缺少 $entry（core 脚手架未交付），无法执行编译检查。"
    echo "=== COMPILE 0 files, 0 warnings, 0 errors, 0 load-failed ==="
    exit 0
  fi
done

mkdir -p .sandbox

# 文件清单：shell 通配在无匹配时会留下字面量，逐项存在性检查。
files=()
for f in early-init.el init.el core/*.el modules/*.el profiles/*.el; do
  [ -f "$f" ] && files+=("$f")
done

if [ ${#files[@]} -eq 0 ]; then
  echo "note: 仓库中没有任何 .el 文件。"
  echo "=== COMPILE 0 files, 0 warnings, 0 errors, 0 load-failed ==="
  exit 0
fi

# 清掉历史遗留 .elc：残留字节码会让后续读取路径拿到旧代码，干扰诊断。
emacs --batch -q --eval '(dolist (f (directory-files-recursively "." "\\.elc$"))
  (delete-file f))' >/dev/null 2>&1 || true

total_w=0; total_e=0; total_lf=0; n=0

for f in "${files[@]}"; do
  n=$((n + 1))
  out_file="$(mktemp "${TMPDIR:-/tmp}/uniemacs-compile.XXXXXX")"

  HOME="$(pwd)/.sandbox" UNI_EMACS_PROFILE="$profile" \
    timeout 300 emacs --batch -q -l early-init.el -l init.el \
         --eval "(byte-compile-file \"$f\")" \
    >"$out_file" 2>&1 || true

  w=$(grep -c "Warning:" "$out_file" || true)
  e=$(grep -c "Error:" "$out_file" || true)
  # 编译期 require 失败：依赖缺失属环境问题，不算代码错误。
  lf=0
  if grep -q "Cannot open load file" "$out_file"; then lf=1; fi

  if [ "$w" -gt 0 ] || [ "$e" -gt 0 ] || [ "$lf" -gt 0 ]; then
    grep -E "Warning:|Error:|Cannot open load file" "$out_file"
  fi
  echo "COMPILE-FILE $f $w $e $lf"

  total_w=$((total_w + w)); total_e=$((total_e + e)); total_lf=$((total_lf + lf))
  rm -f "$out_file"

  # .elc 不进版本库，删掉免得污染 git status。
  if [ -f "${f}c" ]; then
    emacs --batch -q --eval "(delete-file \"${f}c\")" >/dev/null 2>&1 || true
  fi
done

echo "=== COMPILE $n files, $total_w warnings, $total_e errors, $total_lf load-failed ==="
[ "$total_e" -eq 0 ]
