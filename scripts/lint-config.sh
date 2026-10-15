#!/usr/bin/env bash
# lint-config.sh — 约定 lint（grep 级检查，不跑 emacs）
#
# 用法: scripts/lint-config.sh
#
# 覆盖 AGENTS.md 的约定：模块头元信息、文件格式 cookie、包管理纪律、
# 命名空间、档位裁剪禁令，以及「本地参考资料夹不得被受版本库管理的
# 文件引用」这条禁令。
# 每条违规打印 `LINT <文件>:<行号> <规则>'，末尾汇总。
#
# 退出码：0 = 零违规；1 = 有违规。

set -euo pipefail
cd "$(dirname "$0")/.."

violations=0

# LINT <文件>:<行号> <规则>
viol() {
  echo "LINT $1:$2 $3"
  violations=$((violations + 1))
}

# 项目自身 .el 清单：排除本地参考资料夹、.git、.sandbox 与 .agents 技能库
# （后两者不是本项目源码）。参考资料夹名用通配写法，避免在本文件中
# 写出该目录的名字。
project_el() {
  find . -name '*.el' \
       -not -path './refe'*'/*' \
       -not -path './.git/*' \
       -not -path './.sandbox/*' \
       -not -path './.agents/*' \
    | sed 's|^\./||' | sort
}

el_files=()
while IFS= read -r f; do el_files+=("$f"); done < <(project_el)

if [ ${#el_files[@]} -eq 0 ]; then
  echo "note: 仓库中没有任何 .el 文件（core 脚手架未交付），无约定可查。"
  echo "=== LINT 0 violations ==="
  exit 0
fi

# ─── 规则 1：模块文件头元信息 ───────────────────────────────────
for f in modules/*/self-*.el; do
  [ -f "$f" ] || continue
  grep -q "^;; Profiles:" "$f" || viol "$f" 1 "module-header-missing:Profiles"
  grep -q "^;; Requires:" "$f" || viol "$f" 1 "module-header-missing:Requires"
done

# ─── 规则 2：文件格式硬要求 ────────────────────────────────────
# 判据取 AGENTS.md §3 原文：`modules/*/self-*.el' 要求 provide 'self-<名>；
# 其余 .el 只要求 `(provide '<feature>)' + `ends here'。
# data/ 是纯数据文件（AGENTS.md §2：只允许字面量 setq/defconst），
# 不要求 provide/ends here，但仍要求首行 cookie。
for f in "${el_files[@]}"; do
  head -1 "$f" | grep -q "lexical-binding: t" \
    || viol "$f" 1 "missing-lexical-binding-cookie"
  case "$f" in
    data/*) ;;
    *)
      case "$f" in
        modules/*/self-*.el)
          grep -q "(provide 'self-" "$f" \
            || viol "$f" 1 "missing-provide-self" ;;
        *)
          grep -q "(provide '" "$f" \
            || viol "$f" 1 "missing-provide" ;;
      esac
      grep -q "ends here" "$f" \
        || viol "$f" 1 "missing-ends-here" ;;
  esac
done

# ─── 规则 3：包管理纪律（模块体永不写 :ensure 系关键字） ──────────
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  viol "$file" "$line" "use-package-ensure-keyword"
done < <(grep -nE ':ensure|:straight|:elpaca' modules/*/*.el profiles/*.el 2>/dev/null || true)

# ─── 规则 4：不得残留 custom: / custom/ 前缀的本项目符号 ─────────
# 用 custom:[a-z] / custom/[a-z] 形态匹配：custom-file、custom-set 等
# 内建符号不构成匹配，天然排除误报。
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  viol "$file" "$line" "legacy-custom-namespace"
done < <(grep -nE 'custom:[a-z]|custom/[a-z]' "${el_files[@]}" 2>/dev/null || true)

# ─── 规则 5：模块内不得按档位自我裁剪 ───────────────────────────
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
  viol "$file" "$line" "profile-self-pruning"
done < <(grep -n '(eq self:profile' modules/*/*.el 2>/dev/null || true)

# ─── 规则 6.5：模块 Profiles 头与 profile require 清单双向一致 ──
# 教训来源：full.el 曾漏 require self-dashboard/self-glyph，daemon
# 加载时才以 void-function 暴露；声明方与清单方必须互相咬合。
for f in modules/*/self-*.el; do
  [ -f "$f" ] || continue
  m="$(basename "$f" .el)"
  declared="$(grep -m1 '^;; Profiles:' "$f" | sed 's/.*Profiles://;s/（.*//')"
  for p in minimal portable full; do
    if echo "$declared" | grep -qw "$p"; then
      grep -q "(require '$m)" "profiles/$p.el" \
        || viol "$f" 1 "declares-profile-$p-but-not-required"
    else
      grep -q "(require '$m)" "profiles/$p.el" \
        && viol "$f" 1 "required-by-$p-but-not-declared"
    fi
  done
done

# ─── 规则 6：git 跟踪文件不得引用本地参考资料夹 ─────────────────
# 禁令本身要有两处合法自指：AGENTS.md 是规则的声明处，.gitignore 是
# 把该目录排除出版本库的规则。这两处之外出现即为违规。
# 另豁免本脚本自身：匹配模式必须写出该目录名，否则规则无法工作。
if git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"; rest="${hit#*:}"; line="${rest%%:*}"
    case "$file" in
      AGENTS.md | .gitignore | scripts/lint-config.sh) continue ;;
    esac
    viol "$file" "$line" "reference-mention-in-tracked-file"
  done < <(git grep -n 'refe''rence/' 2>/dev/null || true)
fi

echo "=== LINT $violations violations ==="
[ "$violations" -eq 0 ]
