#!/usr/bin/env bash
# smoke-profile.sh <profile> — 单档沙箱冒烟
#
# 用法: scripts/smoke-profile.sh <minimal|portable|full>
#
# 判定（不看退出码）：Guix 的 emacs 是 guile wrapper，会吞掉子进程退出码
# （kill-emacs 7 → rc=0），所以唯一可靠依据是输出里的 SMOKE-DONE 哨兵行。
# 输出中出现 Error/error: 行会一并列出，但不单独决定失败——启动链可能
# 自带可恢复的错误处理，哨兵才是「跑完了」的证据。

set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "usage: $(basename "$0") <minimal|portable|full>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
profile="$1"
case "$profile" in
  minimal | portable | full) ;;
  *) echo "error: 非法 profile '$profile'（可选 minimal/portable/full）" >&2
     usage ;;
esac

for entry in early-init.el init.el; do
  if [ ! -f "$entry" ]; then
    echo "note: 入口文件 $entry 尚不存在（core 脚手架未交付），跳过 $profile 冒烟。"
    echo "=== SMOKE $profile SKIP（入口缺失） ==="
    exit 0
  fi
done

mkdir -p .sandbox

# 用文件而不是管道承接输出：管道会同时改变 emacs 对 stdio 的判断。
out_file="$(mktemp "${TMPDIR:-/tmp}/uniemacs-smoke-$profile.XXXXXX")"
trap 'rm -f "$out_file"' EXIT

HOME="$(pwd)/.sandbox" UNI_EMACS_PROFILE="$profile" \
  emacs --batch -q -l early-init.el -l init.el \
       -l scripts/verify-common.el --eval '(verify/smoke-sentinel)' \
  >"$out_file" 2>&1 || true

# 冒烟过程的相关行：启动链消息 + 错误行。
grep -E "UniEmacs|Error|error:|Warning" "$out_file" || true

if grep -q "SMOKE-DONE" "$out_file"; then
  echo "=== SMOKE $profile PASS ==="
  exit 0
fi

echo "--- $profile 冒烟未完成，关键输出 ---" >&2
# backtrace 极长，只留首条 Error 行与前几行上下文，完整输出在仓库的
# .sandbox 与下方 INIT 日志里可复现。
grep -E "UniEmacs|Error|error:" "$out_file" | head -10 >&2 || true
echo "=== SMOKE $profile FAIL ==="
exit 1
