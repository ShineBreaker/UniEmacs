# Windows 使用指南

UniEmacs 在 Windows 上的完整使用手册：安装、部署、首次启动、Windows
特有机制与边界。便携版（U 盘拷走即用）的组装见
[portable.md](portable.md)。

本文所有结论均在 Windows 10（1809）+ Emacs 31.1（GNU 官方 MSYS2
构建）上实测：四档 profile 加载干净、45 个源文件 byte-compile 零警告、
63 个第三方包经 elpaca 装齐、121 个 tree-sitter 语法库可用、ghostel
原生终端可用、agenote 知识库 CLI 端到端可用。

## 1. 安装 Emacs

从 GNU 官方 Windows 目录 <https://ftp.gnu.org/gnu/emacs/windows/>
下载最新的 emacs-31.x zip（MSYS2 构建，含 `runemacs.exe`、
`emacsclient.exe` 与全部运行库），解压到任意目录，例如
`C:\Tools\emacs`。不需要安装器，解压即用。

- 日常启动用 `bin\runemacs.exe`（纯 GUI，无控制台窗口）；
  `bin\emacs.exe` 在终端里跑 batch/调试用。
- 把 `bin\` 加进 PATH 可以让 `emacs` / `emacsclient` 在任意终端可用；
  不加也行，配置不依赖 PATH 里的 Emacs 自身。

系统要求：Windows 10 1803+（首次启动自举依赖系统自带的 `curl.exe`
与 `tar.exe`，二者从 1803 起内置于 System32）。

## 2. 部署配置

部署形态与 Linux 桌面一致（见主 README「部署」节）：**两个入口副本 +
仓库本体**。

```bash
git clone https://github.com/ShineBreaker/UniEmacs ~/UniEmacs
```

把仓库根下的 `early-init.el` 与 `init.el` 复制到 Emacs 家目录的
`.emacs.d/`，再告诉入口仓库在哪（二选一）：

- 环境变量 `UNI_EMACS_REPO=C:\Users\<你>\UniEmacs`；
- 或在 `.emacs.d/` 放 `repo-location.el`，内容一行：

  ```elisp
  ;;; repo-location.el --- repo pointer -*- lexical-binding: t; -*-
  (setq self:repo "C:/Users/<你>/UniEmacs")
  ```

**Windows 家目录的坑**：未设 `HOME` 环境变量时，Windows 版 Emacs 把
`%APPDATA%`（`C:\Users\<你>\AppData\Roaming`）当家目录——入口文件要放
`%APPDATA%\.emacs.d\`，不是 `C:\Users\<你>\.emacs.d\`。两个办法任选：

1. 设系统环境变量 `HOME=C:\Users\<你>`（推荐，状态目录也跟着归位，
   与 Linux 行为一致）；
2. 不设 HOME，入口放 `%APPDATA%\.emacs.d\`，状态会落在 Roaming 下。

档位选择：环境变量 `UNI_EMACS_PROFILE`（`minimal` / `portable` /
`standard` / `ide`），或启动后 `M-x self/set-profile` 写入家目录
`profile.el`。Windows 桌面默认 `standard`；想要 IDE 体验选 `ide`。
`portable` 是 Android 触屏档，不要在 Windows 上用。

## 3. 首次启动会发生什么

1. **装包**：`self/package-ensure` 经 elpaca 从 MELPA/GNU ELPA 安装
   约 60 个包并逐包 byte-compile，实测 15–20 分钟（机器与网络而异），
   期间无输出属正常。包装完落在状态目录（`~/.cache/emacs/elpaca/`），
   之后启动秒开。中途断网/断电不怕，重启会接着装。
2. **补字体与语法库**：`modules/base/self-bootstrap.el` 在
   `emacs-startup-hook` 上后台检查并下载缺失项（不阻塞启动）：
   - Maple Mono NF CN 字体（中英等宽 + Nerd 图标字形）：仓库自带
     `data/fonts/` TTF 时（便携包）离线安装，否则下载；
   - Windows 预编译 tree-sitter 语法库（121 个 DLL）。

   装完提示「重启 Emacs 生效」。失败会写冷却时间戳，24 小时内不再
   自动重试；随时可手动补：

   ```
   M-x self/bootstrap-fonts
   M-x self/bootstrap-grammars
   ```

   关掉自动行为：`M-x customize-variable RET self:bootstrap-auto-p`。
   Guix 环境（WSL 里跑 Guix 的 Emacs 等）默认跳过字体下载，
   `UNI_EMACS_FONT_DOWNLOAD=1` 可强制。

## 4. Windows 特有机制与边界

### 字体：per-user 注册表安装

Windows 版 Emacs 用 w32 字体后端，经 Windows API 枚举字体，**不读
fontconfig 的用户目录**——把 TTF 拷进 `~/.local/share/fonts` 在
Windows 上无效。自举模块的做法（无需管理员）：

1. TTF 落 `%LOCALAPPDATA%\Microsoft\Windows\Fonts\`；
2. 在 `HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts`
   注册三个值（Regular/Italic/Bold）。

卸载字体：删上述注册表值与文件即可。Linux 分支仍走
`~/.local/share/fonts`，Android 走应用 `fonts/` 目录。

仓库自带字体时（便携包的 `config/data/fonts/` 三个 TTF 齐全），
自举直接从包内拷贝并注册，全程无需联网；缺任何一个才回退下载。

### Tree-sitter：预编译 DLL，无编译器

Windows 没有 cc 编译器，`treesit-install-language-grammar` 的源码
编译路线走不通。自举下载 tree-sitter-langs release 的预编译 bundle，
改名 `libtree-sitter-<lang>.dll` 落 `~/.cache/emacs/tree-sitter/`，
`self-prog` 把该目录注册进 `treesit-extra-load-path`。c-sharp 按配置
覆盖表用下划线名 `libtree-sitter-c_sharp.dll`（与 Guix 一致）。
`self-langs` 有就绪守卫：语法库缺失时退回普通 mode，不报错。

### 终端：ghostel 原生支持

ghostel 官方支持 Windows：首次加载自动从 GitHub releases 下载
`ghostel-module-x86_64-windows.dll` 与 ConPTY 资产，无需手动干预。
v0.63.0 实测可用（标准档 `M-x ghostel`）。

### PDF：graceful degradation

pdf-tools 的 `epdfinfo` 服务端需要 MSYS2 工具链编译，Windows 上默认
不可用。配置以 `(pdf-tools-install t t)` 静默降级：PDF 功能缺席但
不影响其余配置。需要时自行装 MSYS2 编译 epdfinfo。

### 主题：注册表深浅色

Windows 无 D-Bus，`self-theme` 改读注册表
`HKCU\...\Themes\Personalize\AppsUseLightTheme` 判断系统深浅色，
启动时生效；系统切换主题不会推送给 Emacs，手动 `M-x self/color-scheme-toggle`
（或重启动）跟随。

### 控制台编码：GBK

中文 Windows 控制台默认 GBK，batch 输出里的中文在 Git Bash 管道中
可能显示为乱码——**只是显示问题**，配置内部全程 UTF-8。需要可读输出
时 `... 2>&1 | iconv -f GBK -t UTF-8//IGNORE`。agenote CLI 包装器
已设 `PYTHONUTF8=1`，不受影响。

## 5. 可选外部工具

配置对工具缺席一律静默降级，按需安装：

| 工具 | 用途 | 获取 |
| --- | --- | --- |
| Git for Windows | magit / elpaca 包更新 / forge | <https://git-scm.com>（便携包已内置 MinGit，无需另装） |
| ripgrep | consult 检索加速 | GitHub releases，放 PATH |
| aspell | 拼写检查 | MSYS2 或 GNU 构建 |
| Python ≥3.10 | agenote 知识库 CLI | 见下节 |

### agenote CLI（嵌入式 Python 方案）

agenote 运行时只用标准库，可以用 Python 嵌入式发行版承载，不污染
系统：

1. 下载 python.org 的 Windows embeddable package（3.10+，实测
   3.11.9），解压到例如 `C:\Tools\python`；
2. 编辑 `python311._pth`，保留 `Lib/site-packages` 与 `import site`
   两行不注释（嵌入式发行版默认禁用 site，`.pth` 才会生效）；
3. 在 `Lib/site-packages/` 放 `agenote.pth`，内容为 agenote 源码路径
   （`<agenote 仓库>/packages/agenote/src` 的绝对路径；便携包用相对
   路径，见 portable.md）；
4. 写一个 `agenote.cmd` 包装器放进 PATH（**必须纯 ASCII + CRLF**，
   UTF-8 中文注释或 LF 换行会让 cmd.exe 解析出错）：

   ```bat
   @echo off
   rem agenote CLI wrapper: embeddable Python + agenote.pth source path
   set PYTHONUTF8=1
   "%~dp0..\python\python.exe" -c "from agenote.cli import main; main()" %*
   ```

   （假设 `agenote.cmd` 与 `python\` 同在 `C:\Tools\` 下。）

Emacs 侧 `self-agenote` 经 `executable-find "agenote"` 找到包装器，
Windows 上 `.cmd` 扩展名由 Emacs 原生处理。注意 Git Bash 里手动调用
要写全 `agenote.cmd`（bash 不自动补 `.cmd`）。

## 6. 验证与排错

部署链路诊断（不依赖 modules，require 失败后仍可用）：

```
M-x self/deploy-diagnose
```

开发验证（需要 Git Bash + [just](https://github.com/casey/just)）：

```bash
just verify     # 四档沙箱冒烟 + 路径探针 + 图标字形覆盖
just compile    # 全模块 byte-compile 零警告门禁
```

不用 just 时手动冒烟某档（HOME 隔离，不污染真实家目录）：

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=standard \
  emacs --batch -q -l early-init.el -l init.el </dev/null
```

常见问题：

- **启动报「仓库根不可用」**：入口副本没放对家目录（见 §2 的
  `%APPDATA%` 坑），或 `repo-location.el` 路径写错。先跑
  `self/deploy-diagnose`。
- **图标显示为方框**：Maple Mono NF CN 未装好。跑
  `M-x self/bootstrap-fonts` 后重启；仍缺字形用 `just glyph-check`
  定位码点。
- **某语言没有语法高亮**：语法库未就绪。跑
  `M-x self/bootstrap-grammars` 后重启。
- **首启很久没动静**：elpaca 在装包，看 `*elpaca*` 缓冲；15–20 分钟
  属正常。