#!/bin/sh
# UniEmacs 一键安装器（Linux / macOS / Android-Termux）
#
# 用法（一条命令）：
#   curl -fsSL https://raw.githubusercontent.com/ShineBreaker/UniEmacs/main/install.sh | sh
# 或克隆后：
#   sh install.sh
#
# 中国大陆网络（GitHub 常不可达）改用 Gitee 镜像：
#   curl -fsSL https://gitee.com/brokenshine/UniEmacs/raw/main/install.sh | sh -s -- --mirror gitee
#
# 选项：
#   --mirror <github|gitee>  仓库来源，默认 github；gitee 为国内镜像（自动同步）
#   -h, --help               显示说明
#
# 做三件事：
#   1. 仓库 clone 到 ~/.config/emacs（桌面默认位置；已存在则 git pull）
#   2. 入口文件就位：仓库即默认位置，无需副本；Android 时复制到
#      Emacs 应用家目录（.emacs.d），Termux 惯例位置仓库本体不变
#   3. 首次启动验证：batch 加载默认档，失败给出诊断命令
#
# 幂等：重复运行安全。UNI_EMACS_REPO / repo-location.el 高级覆盖不受影响
# （early-init 的解析优先级里环境变量与 repo-location 仍高于本默认位置）。
set -eu

msg() { printf '\033[1;32m==>\033[0m %s\n' "$1"; }
die() {
	printf '\033[1;31m错误:\033[0m %s\n' "$1" >&2
	exit 1
}

usage() {
	cat <<'USAGE'
用法: install.sh [--mirror <github|gitee>]

  --mirror <源>  仓库来源：github（默认）或 gitee（国内镜像，与主仓库自动同步）
  -h, --help     显示本说明

一条命令安装（需已装好 git 与 emacs）：
  curl -fsSL https://raw.githubusercontent.com/ShineBreaker/UniEmacs/main/install.sh | sh

国内网络：脚本地址换 Gitee，并用 sh -s -- 传参指定镜像：
  curl -fsSL https://gitee.com/brokenshine/UniEmacs/raw/main/install.sh | sh -s -- --mirror gitee
USAGE
}

# ── 参数 ────────────────────────────────────────────────────
# 仓库来源：默认 GitHub。国内走 Gitee 镜像（与主仓库自动同步），clone 与
# 后续 git pull 都落在镜像上。
MIRROR=github
while [ $# -gt 0 ]; do
	case "$1" in
	--mirror)
		[ $# -ge 2 ] || die "--mirror 缺少取值（github 或 gitee）"
		MIRROR="$2"
		shift 2
		;;
	--mirror=*)
		MIRROR="${1#--mirror=}"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		die "未知参数：$1"
		;;
	esac
done

case "$MIRROR" in
github) REPO_URL="https://github.com/ShineBreaker/UniEmacs.git" ;;
gitee) REPO_URL="https://gitee.com/brokenshine/UniEmacs.git" ;;
*) die "未知镜像：$MIRROR（可用：github / gitee）" ;;
esac

TARGET="${HOME}/.config/emacs"
ANDROID_EMACS_HOME="/data/data/org.gnu.emacs/files/.emacs.d"
TERMUX_REPO="/data/data/com.termux/files/home/.config/emacs"

# ── 前置检查 ────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || die "需要 git（Termux: pkg install git）"
command -v emacs >/dev/null 2>&1 || die "需要 emacs（Termux 需同签名重签版，见 docs/mobile/README.md）"

# ── 1. 仓库就位 ─────────────────────────────────────────────
if [ -d "${TARGET}/.git" ]; then
	msg "仓库已存在，更新到最新…"
	git -C "$TARGET" pull --ff-only
elif [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
	die "${TARGET} 存在但不是目录，请先处理（它是 UniEmacs 的标准落点）"
else
	msg "克隆 UniEmacs 到 ${TARGET}…"
	mkdir -p "$(dirname "$TARGET")"
	git clone --depth=1 "$REPO_URL" "$TARGET"
fi

# ── 2. 入口就位 ─────────────────────────────────────────────
if [ -d /data/data/org.gnu.emacs ]; then
	# Android：仓库本体另放 Termux 家目录（Emacs 与 Termux 不同 UID，
	# 应用家目录放不下 .git；惯例位置见 early-init 第 4 优先级）。
	if [ "$TARGET" != "$TERMUX_REPO" ] && [ ! -d "${TERMUX_REPO}/.git" ]; then
		msg "Android：仓库本体放到 Termux 家目录 ${TERMUX_REPO}…"
		mkdir -p "$(dirname "$TERMUX_REPO")"
		git clone --depth=1 "$REPO_URL" "$TERMUX_REPO"
	fi
	msg "Android：入口文件复制到 Emacs 应用家目录…"
	mkdir -p "$ANDROID_EMACS_HOME"
	cp "${TERMUX_REPO}/early-init.el" "${TERMUX_REPO}/init.el" "$ANDROID_EMACS_HOME/"
fi
# 桌面：~/.config/emacs 即仓库，入口即仓库文件，无需任何副本。

# ── 3. 首次启动验证 ─────────────────────────────────────────
msg "首次启动验证（首次会安装第三方包，可能 15–35 分钟，期间无输出属正常）…"
if UNI_EMACS_REPO="$TARGET" emacs --batch -q \
	-l "${TARGET}/early-init.el" -l "${TARGET}/init.el" \
	--eval '(message "INSTALL-VERIFY-OK")' </dev/null 2>&1 | tail -5; then
	:
fi
# 上面 tail -5 已把关键输出放行；用哨兵再判定一次。
if UNI_EMACS_REPO="$TARGET" emacs --batch -q \
	-l "${TARGET}/early-init.el" -l "${TARGET}/init.el" \
	--eval '(message "INSTALL-VERIFY-OK")' </dev/null 2>&1 |
	grep -q "INSTALL-VERIFY-OK"; then
	msg "安装完成。直接启动 emacs 即可（默认 standard 档）。"
	msg "切档：M-x self/set-profile；诊断：M-x self/deploy-diagnose"
else
	die "首次启动验证失败。运行 emacs 后 M-x self/deploy-diagnose 查看诊断，或重跑本脚本。"
fi
