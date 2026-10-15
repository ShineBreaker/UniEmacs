# UniEmacs 本机命令入口（最小集）。

default: verify

# 三档沙箱冒烟：任一档失败即整体失败。
# 注意 Guix 的 emacs wrapper 会吞掉非零退出码，这里用哨兵行做
# fail-closed 判定：哨兵缺失即失败，不看退出码。
verify:
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
    for profile in minimal portable full; do
      echo "--- smoke: $profile ---"
      out=$(UNI_EMACS_PROFILE="$profile" emacs --batch -q -l early-init.el -l init.el --eval '(message "VERIFY-SMOKE-OK")' 2>&1)
      echo "$out" | grep -E "UniEmacs|Warning|Error" || true
      echo "$out" | grep -q "VERIFY-SMOKE-OK" || { echo "FAIL: $profile（哨兵缺失）"; echo "$out"; exit 1; }
      echo "OK: $profile"
    done

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
    for f in early-init.el init.el core/*.el modules/*.el profiles/*.el; do
      echo "--- compile: $f ---"
      out=$(emacs --batch -q -l early-init.el -l init.el --eval "(byte-compile-file \"$f\")" --eval '(message "COMPILE-DONE")' 2>&1) || { echo "FAIL(进程退出): $f"; echo "$out"; fail=1; continue; }
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

# 清字节码、沙箱与 eln 缓存。
clean:
    rm -f early-init.elc init.elc core/*.elc modules/*.elc profiles/*.elc
    rm -rf .sandbox eln-cache
