# UniEmacs 本机命令入口。
#
# 通用（桌面 + 手机）：verify / probe / glyph-check / compile / clean。
# 手机专属：APK 构建组（Termux 重签名流水线，见 docs/mobile/）；
# 配置依赖组（真机一键补全字体/图标/插件，桌面同样可用）。

default: verify

# ═══ 验证 ═══

# 交付前验证：启动后路径探针 + 图标字形覆盖 + 四档沙箱冒烟。
# 注意 Guix 的 emacs wrapper 会吞掉非零退出码，这里用哨兵行做
# fail-closed 判定：哨兵缺失即失败，不看退出码。
verify: probe glyph-check
    #!/usr/bin/env bash
    set -euo pipefail
    # 沙箱隔离：除 HOME 外，XDG 四个 bases 也要指进沙箱，否则本机
    # 的 XDG_CONFIG_HOME 等会把 user-emacs-directory 拽回真实家目录。
    export HOME="$(pwd)/.sandbox"
    export XDG_CONFIG_HOME="$HOME/config"
    export XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state"
    export XDG_CACHE_HOME="$HOME/cache"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    for profile in minimal portable full ide; do
      echo "--- smoke: $profile ---"
      out=$(UNI_EMACS_PROFILE="$profile" emacs --batch -q -l early-init.el -l init.el --eval '(message "VERIFY-SMOKE-OK")' </dev/null 2>&1)
      echo "$out" | grep -E "UniEmacs|Warning|Error" || true
      echo "$out" | grep -q "VERIFY-SMOKE-OK" || { echo "FAIL: $profile（哨兵缺失）"; echo "$out"; exit 1; }
      echo "OK: $profile"
    done

# 启动后路径探针（portable 档）：batch 冒烟不触发的路径——tool-bar 按钮
# 安装、图标资产解析、仪表盘首屏数据、mode-line 钮组构造——在桌面沙箱里
# 显式跑一遍。判定同 verify：哨兵行缺失即失败。
probe:
    #!/usr/bin/env bash
    set -euo pipefail
    export HOME="$(pwd)/.sandbox"
    export XDG_CONFIG_HOME="$HOME/config"
    export XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state"
    export XDG_CACHE_HOME="$HOME/cache"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    out=$(emacs --batch -q -l "$(pwd)/scripts/verify-probe.el" </dev/null 2>&1 || true)
    printf '%s\n' "$out" | grep -v 'guix-emacs-c-source\|^You can add\|^See \|^for more' || true
    printf '%s\n' "$out" | grep -q 'VERIFY-PROBE-OK' \
      || { echo "FAIL: 探针未通过"; exit 1; }
    echo "OK: probe"

# 图标字形覆盖：代码里用到的 NF 私用区码点必须在 Maple 字体中有字形
# （缺字形时真机渲染成回退框，历史上踩过 ✦/╭╯）。本机无 Maple 字体时跳过。
glyph-check:
    #!/usr/bin/env bash
    set -euo pipefail
    # 不用 grep -q：-q 命中即退出会让 fc-list 吃 EPIPE，pipefail 下误报
    if command -v fc-list >/dev/null && fc-list :family 2>/dev/null | grep -i maple >/dev/null; then
      missing=""
      for cp in $(grep -ohE '\\u[0-9A-Fa-f]{4}' modules/*/*.el | sed 's/\\u//' | sort -u); do
        fc-list ":charset=$cp" family 2>/dev/null | grep -i maple >/dev/null \
          || missing="$missing U+$cp"
      done
      if [[ -n "$missing" ]]; then
        echo "FAIL：以下码点在 Maple 字体中缺字形：$missing"
        exit 1
      fi
      echo "OK: 全部图标码点均有字形"
    else
      echo "跳过（本机无 Maple 字体，跑 just font 后再验）"
    fi

# batch byte-compile 全部 .el：先加载完整配置再逐文件编译，否则误报
# 未定义符号。警告与错误如实报告并整体失败（缺模块导致失败属预期，
# 会逐个打印出来，不静默）。
compile:
    #!/usr/bin/env bash
    set -uo pipefail
    export HOME="$(pwd)/.sandbox"
    export XDG_CONFIG_HOME="$HOME/config"
    export XDG_DATA_HOME="$HOME/data"
    export XDG_STATE_HOME="$HOME/state"
    export XDG_CACHE_HOME="$HOME/cache"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    fail=0
    for f in early-init.el init.el core/*.el modules/*/*.el profiles/*.el; do
      echo "--- compile: $f ---"
      out=$(emacs --batch -q -l early-init.el -l init.el --eval "(byte-compile-file \"$f\")" --eval '(message "COMPILE-DONE")' </dev/null 2>&1) || { echo "FAIL(进程退出): $f"; echo "$out"; fail=1; continue; }
      echo "$out" | grep -q "COMPILE-DONE" || { echo "FAIL(哨兵缺失): $f"; echo "$out"; fail=1; continue; }
      warns=$(echo "$out" | grep -E "Warning|Error" | grep -v "COMPILE-DONE" || true)
      if [ -n "$warns" ]; then
        echo "FAIL(警告): $f"
        echo "$warns"
        fail=1
      else
        echo "OK: $f"
      fi
    done
    exit $fail

# ═══ APK 构建（Termux 重签名流水线，见 docs/mobile/）═══
# 自动抓取上游预览版并用 Emacs 官方公开构建密钥重签，使 Termux 与
# Android 原生 Emacs 共享 UID。日常使用直接到 Releases 下载
# *-emacs-signed.apk，无需本地执行以下任何一条。

# apksigner 调用命令，默认用 `just tools` 准备的 build-tools jar；
# 已装 Android SDK 的系统可 export APKSIGNER=apksigner 覆盖
apksigner_cmd := env_var_or_default("APKSIGNER", "java -jar tools/apksigner.jar")

# 一次性准备 apksigner：下载 build-tools 34 并提取 apksigner.jar（临时下载约 60MB）
[group('APK 构建')]
tools:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f tools/apksigner.jar ]]; then
        echo "tools/apksigner.jar 已存在，跳过"
        exit 0
    fi
    mkdir -p tools
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    url="https://dl.google.com/android/repository/build-tools_r34-linux.zip"
    echo "==> 下载 $url"
    curl -fsSL --retry 3 -o "$tmp/bt.zip" "$url"
    unzip -q "$tmp/bt.zip" 'android-14/lib/apksigner.jar' -d "$tmp"
    mv "$tmp/android-14/lib/apksigner.jar" tools/
    java -jar tools/apksigner.jar --version

# 抓取上游预览版 APK 到 download/ 并校验 sha256（本地已有且校验通过则跳过下载）
[group('APK 构建')]
fetch tag="" flavor="apt-android-7" abi="universal":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(-o download -f "{{flavor}}" -a "{{abi}}")
    if [[ -n "{{tag}}" ]]; then args+=(-t "{{tag}}"); fi
    scripts/fetch-termux-prerelease.sh "${args[@]}"

# 用 Emacs 构建密钥重签 APK 并断言证书指纹（缺省自动选 download/ 下最新的未签名 APK）
[group('APK 构建')]
resign apk="": tools
    #!/usr/bin/env bash
    set -euo pipefail
    target="{{apk}}"
    if [[ -z "$target" ]]; then
        target=$(ls -t download/*.apk 2>/dev/null | grep -v 'emacs-signed' | sed -n '1p' || true)
        if [[ -z "$target" ]]; then
            echo "download/ 下没有待签名的 APK，先运行: just fetch" >&2
            exit 1
        fi
    fi
    APKSIGNER="{{apksigner_cmd}}" scripts/resign-apk.sh "$target"

# 抓取 + 重签一条龙（参数同 fetch；产物为 download/ 下 *-emacs-signed.apk）
[group('APK 构建')]
termux tag="" flavor="apt-android-7" abi="universal": tools
    #!/usr/bin/env bash
    set -euo pipefail
    args=(-o download -f "{{flavor}}" -a "{{abi}}")
    if [[ -n "{{tag}}" ]]; then args+=(-t "{{tag}}"); fi
    out=$(scripts/fetch-termux-prerelease.sh "${args[@]}")
    apk=$(sed -n 's/^apk=//p' <<<"$out")
    APKSIGNER="{{apksigner_cmd}}" scripts/resign-apk.sh "$apk"
    echo
    echo "==> 产物: ${apk%.apk}-emacs-signed.apk"

# ═══ 配置依赖（真机 / 桌面通用）═══

maple-font-url := "https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-NF-CN.zip"

# 一键补全配置侧依赖：Termux 包 → 字体 → 图标 → 插件预构建
[group('配置依赖')]
emacs: termux-deps font icons packages

# Termux 环境一键安装配置侧依赖包（桌面自动跳过）。
# 包名经 termux-packages 源核实：curl/sqlite 为 libcurl/libsqlite 子包，sqlite3 无独立包
[group('配置依赖')]
termux-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v pkg >/dev/null || { echo "非 Termux 环境，跳过包安装"; exit 0; }
    pkg install -y curl unzip fontconfig emacs git sqlite ripgrep

# 生成 tool-bar 图标（Papirus symbolic 矢量，随仓库分发；缺失才重建）。
# SVG 直渲 + 运行端按主题重着色（见 modules/touch/self-bar.el）；PNG 为
# 2× 超采样中灰兜底（无 librsvg 的构建）。桌面依赖 rsvg-convert；来源与
# 许可见 data/icons/README.md。
papirus_tag := "20260801"
[group('配置依赖')]
icons:
    #!/usr/bin/env bash
    set -euo pipefail
    base="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/{{papirus_tag}}/Papirus/24x24/symbolic"
    spec=(
        "modbar devices/input-keyboard"     "open actions/document-open"
        "save actions/document-save"        "copy actions/edit-copy"
        "paste actions/edit-paste"          "cut actions/edit-cut"
        "search actions/edit-find"          "theme status/night-light"
        "config places/folder"              "quick actions/feather-zap"
    )
    missing=""
    for item in "${spec[@]}"; do
        read -r name _ <<<"$item"
        [[ -f "data/icons/$name.svg" ]] || missing="$missing $name"
    done
    # modifier-bar 徽章也算依赖（少了即触发重建）
    for n in control shift meta alt super hyper tab esc; do
        [[ -f "data/icons/mod-$n.pbm" ]] || missing="$missing mod-$n"
    done
    if [[ -z "$missing" ]]; then
        echo "data/icons/ 图标已齐（随仓库分发），跳过"
        exit 0
    fi
    command -v rsvg-convert >/dev/null || { echo "需要 rsvg-convert (librsvg)"; exit 1; }
    # 不用 grep -q：-q 命中即退出会让 fc-list 吃 EPIPE，pipefail 下误报
    command -v fc-list >/dev/null && fc-list :family | grep -i maple >/dev/null \
        || echo "提示：本机无 Maple 字体，徽章文字将用 fallback 字体渲染（建议先 just font）"
    mkdir -p data/icons
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # 多数 symbolic 图标是符号链接（raw URL 返回目标路径文本），
    # 须逐跳跟随解析到真实文件
    fetch_svg() {
        local url="$1" out="$2" content tries=0
        while :; do
            content=$(curl -fsSL --retry 3 "$url")
            [[ "$content" == \<* ]] && { printf '%s\n' "$content" > "$out"; return 0; }
            url="${url%/*}/$content"
            tries=$((tries + 1)); (( tries > 5 )) && return 1
        done
    }
    for item in "${spec[@]}"; do
        read -r name path <<<"$item"
        fetch_svg "$base/${path}-symbolic.svg" "$tmp/$name.svg"
        # 垂直防手势垫：画布统一 24×30、内容顶对齐（xMidYMin），底部留
        # 6 单位死区，避开全面屏上滑手势区；上游画布尺寸不一，宽高通配替换
        sed -e 's/<svg \(.*\)width="[0-9]*" height="[0-9]*"/<svg \1width="24" height="30" preserveAspectRatio="xMidYMin"/' \
            "$tmp/$name.svg" > "$tmp/$name-pad.svg"
        # PNG 兜底：重着色中灰后 2× 光栅化（72×90）
        sed 's/\(ColorScheme-Text { color:\)#[0-9a-fA-F]*/\1#808080/' \
            "$tmp/$name-pad.svg" > "$tmp/$name-gray.svg"
        rsvg-convert -w 72 -h 90 "$tmp/$name-gray.svg" > "data/icons/$name.png"
        cp "$tmp/$name-pad.svg" "data/icons/$name.svg"
    done
    # modifier-bar 徽章：修饰键取前缀单字母（C S M A s H），Tab/Esc 全名。
    # 字体 = Cozette（MIT 像素字体，6×13 网格 2×=26px 整数倍渲染保对齐）：
    # 按最终尺寸直出不缩放，笔画阈值化。输出 PBM 位图（官方修饰键同机制，
    # 按工具栏前景色着色，深浅主题自动适配；PNG alpha 露白底仅兜底）。
    # 尺寸烤死在资产：字母 32×32、Tab/Esc 64×32。
    command -v pngtopam >/dev/null || { echo "需要 netpbm（guix install netpbm）"; exit 1; }
    if ! fc-list :family 2>/dev/null | grep -i cozette >/dev/null; then
        command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
        mkdir -p "${HOME}/.local/share/fonts"
        curl -fsSL --retry 3 -o "${HOME}/.local/share/fonts/CozetteVector.ttf" \
            "https://github.com/slavfox/Cozette/releases/latest/download/CozetteVector.ttf"
        fc-cache -f >/dev/null 2>&1 || true
        fc-list :family | grep -i cozette >/dev/null \
            || { echo "Cozette 字体安装失败"; exit 1; }
    fi
    mk_badge() {  # $1=name $2=label $3=outW $4=outH $5=fontSize
        local name="$1" label="$2" ow="$3" oh="$4" fs="$5"
        printf '%s\n' \
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"$ow\" height=\"$oh\"><text x=\"$((ow/2))\" y=\"$((oh*3/4+1))\" font-family=\"CozetteVector\" font-size=\"$fs\" fill=\"#000000\" text-anchor=\"middle\">$label</text></svg>" \
            > "$tmp/mod-$name.svg"
        rsvg-convert "$tmp/mod-$name.svg" > "$tmp/mod-$name.png"
        cp "$tmp/mod-$name.png" "data/icons/mod-$name.png"
        # PBM：alpha 通道阈值化（不透明=笔画），pnminvert 使笔画位=1
        # （PBM 1=黑=按前景色绘制的字形）
        pngtopam -alpha "$tmp/mod-$name.png" \
            | pgmtopbm -threshold | pnminvert > "data/icons/mod-$name.pbm"
    }
    mk_badge control  C   32 32 26
    mk_badge shift    S   32 32 26
    mk_badge meta     M   32 32 26
    mk_badge alt      A   32 32 26
    mk_badge super    s   32 32 26
    mk_badge hyper    H   32 32 26
    mk_badge tab      Tab 64 32 26
    mk_badge esc      Esc 64 32 26
    echo "已生成 10 枚 Papirus symbolic .svg + PNG 兜底 + 8 枚 modifier-bar 徽章（PBM/Cozette）"

# 下载 Maple Mono NF CN（中英等宽 + Nerd 图标）并安装。
# Android → Emacs home 的 fonts/（sfnt-android 枚举）；桌面 → fontconfig 用户目录。
# 安装后需重启 Emacs 生效。
[group('配置依赖')]
font:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v fc-list >/dev/null && fc-list :family | grep -qi "maple"; then
        echo "Maple 字体已安装，跳过"
        exit 0
    fi
    command -v curl >/dev/null || { echo "需要 curl"; exit 1; }
    command -v unzip >/dev/null || { echo "需要 unzip"; exit 1; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL --retry 3 --max-time 300 -o "$tmp/maple.zip" "{{maple-font-url}}"
    unzip -o -q "$tmp/maple.zip" -d "$tmp/font"
    if [[ -d /data/data/org.gnu.emacs ]]; then
        dest="/data/data/org.gnu.emacs/files/fonts"
    else
        dest="${HOME}/.local/share/fonts"
    fi
    mkdir -p "$dest"
    cp "$tmp"/font/MapleMono-NF-CN-Regular.ttf \
       "$tmp"/font/MapleMono-NF-CN-Italic.ttf \
       "$tmp"/font/MapleMono-NF-CN-Bold.ttf "$dest"/
    fc-cache -f >/dev/null 2>&1 || true
    echo "字体已安装到 $dest（重启 Emacs 生效）"

# 预构建某档全部 Emacs 插件（跑一遍完整 init，包后端装齐并 byte-compile）。
# 真机默认 portable 档、缓存进真实 HOME；桌面进 .sandbox 隔离，档位可传参。
[group('配置依赖')]
packages profile="portable":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d /data/data/org.gnu.emacs ]]; then
        export HOME="$(pwd)/.sandbox"
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_STATE_HOME="$HOME/state"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
    fi
    UNI_EMACS_PROFILE="{{profile}}" emacs --batch -q -l early-init.el -l init.el </dev/null
    echo "插件已按 {{profile}} 档构建完成"

# ═══ 清理 ═══

# 清字节码、沙箱、eln 缓存与重签名产物。
clean: clean-emacs clean-download

# 清编译产物与本地缓存：仓库内 *.elc、eln-cache/ 与桌面沙箱 .sandbox/
clean-emacs:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -path ./.git -prune -o -name '*.elc' -type f -delete
    rm -rf .sandbox eln-cache
    echo "已清理 *.elc、eln-cache/、.sandbox/"

# 清 Termux 重签名时的下载目录
clean-download:
    rm -rf download
