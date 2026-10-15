#!/usr/bin/env bash
# startup-time.sh <profile> — 启动耗时中位数
#
# 用法: scripts/startup-time.sh <minimal|portable|full>
#
# 沙箱内跑 3 次 `emacs --batch -q -l early-init.el -l init.el'，每次以
# --eval 打印 (emacs-init-time)，抓 INIT-TIME 行取中位数。
# 结论行：`=== STARTUP <profile> median=<秒>s (runs: <x>, <y>, <z>) ==='

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
    echo "note: 入口文件 $entry 尚不存在（core 脚手架未交付），跳过 $profile 计时。"
    echo "=== STARTUP $profile SKIP（入口缺失） ==="
    exit 0
  fi
done

mkdir -p .sandbox

runs=3
times=()
for _ in $(seq "$runs"); do
  out_file="$(mktemp "${TMPDIR:-/tmp}/uniemacs-startup.XXXXXX")"
  HOME="$(pwd)/.sandbox" UNI_EMACS_PROFILE="$profile" \
    emacs --batch -q -l early-init.el -l init.el \
         --eval '(message "INIT-TIME %s" (emacs-init-time))' \
    >"$out_file" 2>&1 || true
  t="$(sed -n 's/^INIT-TIME \([0-9.]*\) seconds$/\1/p' "$out_file" | tail -1)"
  rm -f "$out_file"
  if [ -n "$t" ]; then times+=("$t"); fi
done

if [ ${#times[@]} -eq 0 ]; then
  echo "error: 未抓到任何 INIT-TIME 行（启动链可能失败）。" >&2
  echo "=== STARTUP $profile FAIL ==="
  exit 1
fi

# 中位：升序排序后取中间行。样本数为偶数时取中间两个的均值。
sorted="$(printf '%s\n' "${times[@]}" | sort -n)"
n=${#times[@]}
if [ $((n % 2)) -eq 1 ]; then
  median="$(printf '%s\n' "$sorted" | awk -v m=$((n / 2 + 1)) 'NR==m{print}')"
else
  median="$(printf '%s\n' "$sorted" | awk -v a=$((n / 2)) -v b=$((n / 2 + 1)) \
             'NR==a{x=$0} NR==b{y=$0} END{printf "%.6f", (x+y)/2}')"
fi

runs_list="$(printf '%s, ' "${times[@]}")"
runs_list="${runs_list%, }"
echo "=== STARTUP $profile median=${median}s (runs: $runs_list) ==="
