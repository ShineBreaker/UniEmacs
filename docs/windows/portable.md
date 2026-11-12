# Windows 便携包组装指南

把「Emacs 程序 + UniEmacs 配置 + 全部已装包与状态」打成一个目录，
拷到 U 盘或任何 Windows 机器，双击启动器即用。本文是组装手册；
Windows 日常使用见 [README.md](README.md)。

实测成品约 935MB：程序 378MB + MinGit 93MB + 状态 397MB +
配置（含自带字体）62MB + agenote 约 6MB。
组装在 Git Bash 里做（`cp -rL` 解引用符号链接是关键步骤）。

## 1. 成品形态

```
EmacsPortable/
├── emacs/            Emacs 发行版（bin/ lib/ share/ ...）+ 可选 python/ 嵌入式
├── git/              MinGit（elpaca/magit 依赖；目标机器可能没有 git）
├── config/           UniEmacs 仓库本体（除 .sandbox 等本地脚手架）；
│                     data/fonts/ 带 Maple 三个 TTF（首启离线安装）
├── home/             隔离家目录：.emacs.d 入口 + .cache 包/语法库 + .local 状态
├── agenote/          agenote 仓库（可选，知识库 CLI 的 Python 源码）
└── 启动Emacs.cmd     唯一入口：所有路径从自身位置解析，盘符无关
```

便携的原理：配置把一切持久化状态都落在 HOME 下（包缓存
`~/.cache/emacs/`、状态 `~/.local/state/emacs/`、入口
`~/.emacs.d/`），仓库目录只读。启动器把 HOME 与 XDG 各基目录全部
指进包内 `home/`，于是整个目录搬到哪台机器都自洽。

自包含的原则：目标机器的环境无法保证一致——包必须同时带上 Emacs
程序、git（**包已预构建，elpaca 启动时仍会检查 git 可执行文件**，
裸机 PATH 无 git 会直接加载 profile 失败）、字体、语法库与全部包。
启动器经 PATH 与环境变量把它们全部钉进包内，不依赖目标机器的 PATH
与已装软件；首次启动可完全离线。

## 2. 两个必须处理的坑

### 坑一：elpaca builds 里的绝对路径符号链接

elpaca 的 `builds/<包>/` 下是指向 `repos/<包>/` 源文件的 **NTFS 符号
链接，目标是绝对路径**（`cmd /c dir` 可见 `<SYMLINK>`）。直接复制会
把链接原样带走：换一台机器（或盘符变了）链接全部失效，包加载即崩。
FAT32/exFAT 根本不支持符号链接，复制时还会直接报错。

**解法**：`cp -rL` 解引用复制——链接变成实体文件。代价是体积略增
（约 +25MB），换来对文件系统与盘符的完全免疫。

### 坑二：agenote.pth 的绝对路径

嵌入式 Python 靠 `Lib/site-packages/agenote.pth` 找到 agenote 源码，
常规安装写的是绝对路径，搬走即失效。

**解法**：改成相对路径。Python 的 site 机制以 `.pth` 所在目录
（site-packages）为基准解析相对行，所以从
`emacs/python/Lib/site-packages/` 上溯四级到包根再进 agenote：

```
../../../../agenote/packages/agenote/src
```

## 3. 组装步骤

前置：本机已按 [README.md](README.md) 把配置跑起来，包、字体、语法
库都装齐（状态在仓库的 `.sandbox/` 或真实 HOME 下，下文以 `.sandbox`
为例）。设三个变量：

```bash
ROOT=/c/Users/<你>/path/to/workspace   # 含 UniEmacs/ 与 Emacs 发行版
DIST="$ROOT/tools"                     # Emacs 发行版根（bin/ lib/ share/，可含 python/）
B="/c/Users/<你>/Desktop/EmacsPortable"  # 成品目录
```

### 3.1 复制各部分

```bash
mkdir -p "$B"

# 程序：解引用复制（发行版本身一般无链接，-L 保险）
cp -rL "$DIST" "$B/emacs"
# 删掉发行版目录里的安装 zip（如果有），它们不是运行时依赖
rm -f "$B/emacs/"*.zip

# 配置：排除沙箱与本地脚手架（.agents/.claude/.denv 不入包）
mkdir -p "$B/config"
tar -C "$ROOT/UniEmacs" \
    --exclude='./.sandbox' --exclude='./.agents' \
    --exclude='./.claude' --exclude='./.denv' \
    -cf - . | tar -C "$B/config" -xf -

# 状态：解引用复制（坑一在这一步解决）
cp -rL "$ROOT/UniEmacs/.sandbox" "$B/home"

# agenote 源码（可选；不要知识库可跳过，并删掉 emacs/bin/agenote.cmd）
cp -rL "$ROOT/agenote" "$B/agenote"

# git：MinGit 免安装版（elpaca/magit 依赖，见 §1 自包含原则）。
# 从 git-for-windows releases 下 MinGit-<版本>-64-bit.zip
# （实测 v2.56.1.windows.1），解压后 git/cmd/git.exe 就位：
mkdir -p "$B/git"
unzip -q MinGit-2.56.1-64-bit.zip -d "$B/git"

# 字体：Maple 三个 TTF（首启离线安装，见 §4）。从已装好的机器取：
mkdir -p "$B/config/data/fonts"
cp "$LOCALAPPDATA/Microsoft/Windows/Fonts/MapleMono-NF-CN-Regular.ttf" \
   "$LOCALAPPDATA/Microsoft/Windows/Fonts/MapleMono-NF-CN-Italic.ttf" \
   "$LOCALAPPDATA/Microsoft/Windows/Fonts/MapleMono-NF-CN-Bold.ttf" \
   "$B/config/data/fonts/"
```

### 3.2 清理 home 里的机器绑定残留

```bash
# 仓库指针：启动器改用 UNI_EMACS_REPO 环境变量，这份绝对路径文件必须删
rm -f "$B/home/.emacs.d/repo-location.el"
# 上一台机器的会话残留
rm -rf "$B/home/.emacs.d/server" "$B/home/.emacs.d/auto-save-list"
rm -f "$B/home/.emacs.d/var/recentf-save.el" \
      "$B/home/.emacs.d/var/savehist.el" \
      "$B/home/.emacs.d/var/save-place.el"
```

`var/org/org-roam.db` 与 `Documents/Org/` 是笔记数据，**保留**。

### 3.3 agenote.pth 改相对（坑二）

```bash
printf '../../../../agenote/packages/agenote/src\n' \
  > "$B/emacs/python/Lib/site-packages/agenote.pth"
# 验证：必须从包内源码导入
"$B/emacs/python/python.exe" -c "import agenote; print(agenote.__file__)"
```

### 3.4 写启动器

`启动Emacs.cmd`，**纯 ASCII 内容 + CRLF 换行**（中文只能出现在文件名；
UTF-8 中文注释或 LF 换行会让 cmd.exe 解析出错）。用编辑器保存为
ANSI/ASCII + CRLF，或写完后 `sed -i 's/$/\r/' 启动Emacs.cmd`：

```bat
@echo off
rem UniEmacs portable launcher - drive-letter independent.
rem HOME / repo / profile / XDG bases all resolve from this folder,
rem so the whole directory can be copied to any drive or machine.
set "HOME=%~dp0home"
set "UNI_EMACS_REPO=%~dp0config"
set "UNI_EMACS_PROFILE=standard"
set "XDG_CACHE_HOME=%~dp0home\.cache"
set "XDG_STATE_HOME=%~dp0home\.local\state"
set "XDG_DATA_HOME=%~dp0home\.local\share"
rem Bundled MinGit: elpaca needs git even when packages are pre-built,
rem and host machines may have no git on PATH. Keep the bundle self-contained.
set "PATH=%~dp0emacs\bin;%~dp0git\cmd;%PATH%"
start "" "%~dp0emacs\bin\runemacs.exe" --init-directory "%~dp0home\.emacs.d"
```

逐行职责：

| 行 | 作用 |
| --- | --- |
| `%~dp0` | 启动器所在目录（末尾带 `\`），盘符/路径无关的锚点 |
| `HOME` | 状态根：`~/.cache`、`~/.local`、`~/Documents` 全落包内 |
| `UNI_EMACS_REPO` | 入口解析仓库根的最高优先级来源，替代 repo-location.el |
| `UNI_EMACS_PROFILE` | 档位，按需改 `ide` |
| `XDG_*` 三行 | 钉死缓存/状态/数据基目录，防止目标机器自带 XDG 变量把状态拽出包外 |
| `PATH` 前置 | 包内 Emacs 与 MinGit 前置：elpaca 启动即查 git（裸机 PATH 无 git 会加载 profile 失败），magit 同理；`agenote.cmd` 也经此找到 |
| `--init-directory` | 钉死 `user-emacs-directory`，不受目标机器 XDG_CONFIG_HOME 干扰 |

## 4. 目标机器首次启动

双击 `启动Emacs.cmd`，**全程可离线**：

- 包与语法库已随包携带，**无需重装**；
- 字体随包携带（`config/data/fonts/` 三个 TTF），自举模块首启直接
  拷贝到 per-user 字体目录并注册 HKCU（见 README.md §4），不联网、
  不碰系统目录、无需管理员；仅当包内字体缺失才回退联网下载；
- MinGit 已随包携带并在启动器 PATH 里，elpaca / magit 直接可用。

## 5. 验证清单

组装完在本机先验一遍（全部用包内程序与包内 HOME）：

```bash
# batch 冒烟：仓库解析、档位、语法库目录必须全部指向包内
HOME="$B/home" UNI_EMACS_REPO="$B/config" UNI_EMACS_PROFILE=standard \
XDG_CACHE_HOME="$B/home/.cache" XDG_STATE_HOME="$B/home/.local/state" \
XDG_DATA_HOME="$B/home/.local/share" \
  "$B/emacs/bin/emacs.exe" --batch -q --init-directory "$B/home/.emacs.d" \
  -l "$B/home/.emacs.d/early-init.el" -l "$B/home/.emacs.d/init.el" \
  --eval '(message "OK repo=%s profile=%s" self:repo self:profile)' </dev/null

# 干净 PATH 冒烟（模拟裸目标机器：PATH 里没有 git/emacs）。
# PATH 用 Windows 式分号 + 反斜杠，只含包内程序与 System32；
# 把 <包路径> 换成实际位置（如 C:\Users\你\Desktop\EmacsPortable）：
PATH='<包路径>\emacs\bin;<包路径>\git\cmd;C:\Windows\System32;C:\Windows' \
HOME="$B/home" UNI_EMACS_REPO="$B/config" UNI_EMACS_PROFILE=standard \
XDG_CACHE_HOME="$B/home/.cache" XDG_STATE_HOME="$B/home/.local/state" \
XDG_DATA_HOME="$B/home/.local/share" \
  "$B/emacs/bin/emacs.exe" --batch -q --init-directory "$B/home/.emacs.d" \
  -l "$B/home/.emacs.d/early-init.el" -l "$B/home/.emacs.d/init.el" \
  --eval '(message "OK git=%s" (executable-find "git"))' </dev/null
# git= 必须指向包内 git\cmd\git.exe；出现「Elpaca unable to find git」
# 即启动器 PATH 没生效（Git Bash 里跑 batch 会继承 bash 的 git，
# 掩盖这个问题——必须用干净 PATH 验）。

# agenote CLI（可选）
"$B/emacs/bin/agenote.cmd" --version

# GUI：双击启动器，确认 dashboard 出现、无 *Warnings* 弹窗，
# 且默认字体是 Maple（在 Emacs 里求值）：
#   (face-attribute 'default :family)  ⇒ "Maple Mono NF CN"
```

再拷到 U 盘换一台机器复验 GUI。注意：验证 GUI 后包里会留下
`home/.emacs.d/server/` 等会话文件，交付前按 §3.2 再清一次。

## 6. 更新与维护

- **更新配置**：包内 `config/` 是完整 git 仓库，`git pull` 即可；
  入口副本（`home/.emacs.d/early-init.el`、`init.el`）若随仓库更新
  了，要重新复制覆盖。
- **更新包**：Emacs 里照常 elpaca 更新；builds 会重新生成绝对路径
  符号链接——**在 U 盘上这没问题**（链接目标与包同盘符），但若之后
  要把包再拷去别处，重新 `cp -rL` 一遍 home/ 即可。
- **不要**把目标机器的真实 HOME 状态拷回包里覆盖——包内状态是
  自洽的一份，混入机器绑定路径会破坏便携性。

## 7. 边界

- 文件系统：FAT32/exFAT/NTFS 均可（解引用后无符号链接依赖）；
  单文件均小于 4GB，FAT32 无碍。推荐 exFAT。
- 路径：启动器全引号，含空格路径可用；仍建议放简单位置
  （如 `E:\EmacsPortable`），减少第三方工具的路径怪癖。
- 字体注册表项是 per-user 的（HKCU）：U 盘拔走后目标机器留有注册表
  值与字体文件（per-user 安装的常规行为），删值与文件即可卸载。
- 包内已含 MinGit（magit/forge、elpaca 更新可用）；不含 MSYS2 工具链：
  pdf-tools epdfinfo 在裸目标机器上不可用，属预期降级。