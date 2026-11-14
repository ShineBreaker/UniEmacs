# IDE 档与 IntelliJ IDEA

ide 档按 **IntelliJ IDEA 的 Windows / Linux 默认键图** 覆盖日常操作，外观按 **IDEA 2023+ New UI 的 Dark / Islands** 来配。macOS 键图把 Ctrl 换成 Command，和本仓库桌面档的 Ctrl 习惯不一致，所以不用那一套。

选择本档：

```bash
UNI_EMACS_PROFILE=ide emacs
```

或 `M-x self/set-profile` 写成 `ide`，下次启动生效。standard 档不加载这些覆写。

## 外观

| IDEA New UI | 本档 |
| --- | --- |
| Dark 编辑区 `#1E1F22`、工具窗 `#2B2D30`、强调蓝 `#3574F0` | 盖在 Modus 之上的 face。浅色切换后再盖回来 |
| Islands：面板之间有缝、圆角 | 帧内边距 + 8px 窗口缝，底色 `#131314`。Emacs 窗口是直角，圆角做不到 |
| 紧凑主工具栏、汉堡菜单 | 帧顶 `tab-bar`：菜单、项目名、运行、调试、停止、搜索、分支、设置。菜单栏本身关掉 |
| 左侧工具窗竖条 | Emacs 没有这条窗口原语。按钮收在顶栏，快捷键仍是 Alt+数字 |
| 编辑器标签 | 窗口顶部 `tab-line`。当前标签与编辑区同色，其余贴在 `#2B2D30` 上 |
| 面包屑 | 标签下方 header-line：项目相对路径 › 当前函数 |
| 状态栏 | echo area。左：检查计数与分支。右：`行:列`、LF/CRLF、缩进、编码、语言 |
| JetBrains Mono | 编辑区优先这个家族，没有则用 Maple Mono NF CN（中文注释不会变成方框）。顶栏用 Sarasa UI SC |
| 行号、VCS 色条、断点 | 绝对行号；`diff-hl` 画在左 fringe（增绿、改蓝、删红）；点击行号槽或 fringe 切换 dape 断点 |
| 行内诊断 | `flymake-show-diagnostics-at-end-of-line`（Emacs 30+ 才画在行尾；更早的版本只有 fringe 与 Alt+6） |

启动图形帧时只打开左侧项目树，终端等 Alt+F12，和 IDEA 一样不默认铺底栏。

## 键位对照

下表是 Windows / Linux 默认键，以及本档实际调用的命令。`<f1> ?` 的帮助页里这些条目在「IDEA 键位」组。

| IDEA 操作 | 键 | 本档命令 |
| --- | --- | --- |
| Search Everywhere | 双击 Shift，见下文 | `self/ide-search-everywhere`（Ctrl+Shift+P） |
| Find Action | Ctrl+Shift+A | `execute-extended-command` |
| Go to Class | Ctrl+N | `consult-imenu-multi` |
| Go to File | Ctrl+Shift+N | `project-find-file` |
| Go to Symbol | Ctrl+Alt+Shift+N | `self/workspace-symbol`（工作区符号，有 LSP 时走 Eglot） |
| Recent Files | Ctrl+E | `consult-recent-file` |
| Recent Locations | Ctrl+Shift+E | `consult-global-mark` |
| Go to Line | Ctrl+G，见下文 | Ctrl+Shift+G 与 `M-g g` |
| Go to Declaration | Ctrl+B，Ctrl+点击 | `xref-find-definitions`，鼠标沿用 `xref-find-definitions-at-mouse` |
| Find Usages | Alt+F7 | `xref-find-references` |
| Rename | Shift+F6 | `self/rename-dwim`（有 LSP 时走 eglot-rename） |
| Reformat Code | Ctrl+Alt+L | `apheleia-format-buffer`，没有格式化器时缩进全缓冲 |
| Optimize Imports | Ctrl+Alt+O | `eglot-code-action-organize-imports` |
| Comment / Uncomment | Ctrl+/ | `comment-line` |
| Block comment | Ctrl+Shift+/ | `self/ide-comment-block` |
| Duplicate Line | Ctrl+D | `duplicate-dwim` |
| Delete Line | Ctrl+Y | `kill-whole-line` |
| Move Line | Alt+Shift+Up/Down | `self/code-move-line-up` / `down` |
| Extend / Shrink Selection | Ctrl+W / Ctrl+Shift+W | `er/expand-region` / `er/contract-region` |
| 下一处多光标 | Alt+J | `self/ide-select-next-occurrence` |
| 取消一处 | Alt+Shift+J | `self/ide-unselect-occurrence` |
| 全部出现 | Ctrl+Alt+Shift+J | `self/ide-select-all-occurrences` |
| Alt+Shift+点击加光标 | Alt+Shift+点击 | `self/mc-add-cursor-on-click`。Alt+点击仍是原来的加光标 |
| Show Intention Actions | Alt+Enter | `eglot-code-actions`。Org 缓冲里这个键仍是 Org 的标题命令，用 `C-.` |
| Basic Completion | Ctrl+Space | `completion-at-point`（corfu） |
| Parameter Info | Ctrl+P | `self/ide-parameter-info`（eldoc-box 浮窗） |
| Quick Documentation | Ctrl+Q | `eldoc-doc-buffer` |
| Find / Replace | Ctrl+F / Ctrl+R | `self/isearch-forward-dwim` / `query-replace` |
| Find / Replace in Path | Ctrl+Shift+F / Ctrl+Shift+R | `consult-ripgrep` / `project-query-replace-regexp` |
| Run | Shift+F10 | `self/ide-run`（有编译缓冲则 `recompile`） |
| Debug | Shift+F9 | `dape`，已有会话则继续 |
| Stop | Ctrl+F2 | `dape-quit` 或停掉编译 |
| Build | Ctrl+F9 | `project-compile` |
| Toggle Breakpoint | Ctrl+F8 | `dape-breakpoint-toggle`。点行号槽同样有效 |
| Step Over / Into / Out | F8 / F7 / Shift+F8 | `dape-next` / `dape-step-in` / `dape-step-out` |
| Resume | F9 | `dape-continue` |
| Next / Previous Highlighted Error | F2 / Shift+F2 | `flymake-goto-next-error` / `prev` |
| Back / Forward | Ctrl+Alt+Left / Right | `xref-go-back` / `xref-go-forward` |
| 上一个 / 下一个标签 | Alt+Left / Right | `self/tabs-previous` / `next` |
| 上一个 / 下一个方法 | Alt+Up / Down | `beginning-of-defun` / `end-of-defun` |
| Project | Alt+1 | Treemacs |
| Bookmarks | Alt+2 | `bookmark-bmenu-list` |
| Find | Alt+3 | 关掉已有结果窗，否则 `consult-ripgrep` |
| Run 工具窗 | Alt+4 | `*compilation*` |
| Debug 工具窗 | Alt+5 | 同 Shift+F9 |
| Problems | Alt+6 | `self/flymake-list-errors-dwim` |
| Structure | Alt+7，Ctrl+F12 | `consult-imenu`（弹出，不是常驻侧栏） |
| Services | Alt+8 | `list-processes` |
| Git | Alt+9 | `magit-status` |
| Commit | Alt+0，Ctrl+K | `magit-commit` |
| Terminal | Alt+F12 | ghostel 终端，再按一次关掉 |
| Update Project | Ctrl+T | `magit-pull-from-upstream` |
| Push | Ctrl+Shift+K | `magit-push-current-to-pushremote` |
| Close Tab | Ctrl+F4 | `kill-current-buffer` |
| Undo / Redo | Ctrl+Z / Ctrl+Shift+Z | `undo` / `undo-redo` |
| Save All | Ctrl+S | `save-some-buffers`。只存当前文件仍是 `C-x C-s` |
| Select All | Ctrl+A | `mark-whole-buffer` |
| Copy / Cut / Paste | Ctrl+C / X / V | 见下文 cua。Ctrl+V 在全局键图上是 `cua-paste`（粘贴） |
| Paste from History | Ctrl+Shift+V | `yank-from-kill-ring` |
| Settings | Ctrl+Alt+S | `customize-group` `self-ide`。打开仓库配置文件仍是 `C-,` |
| 在项目树中定位 | Alt+F1 | `self/ide-panel-reveal` |
| 上一个工具窗 | F12 | 再执行上一次的工具窗命令 |
| 书签 | F11 | `bookmark-set` |
| 重新加载文件 | F5 | `revert-buffer` |
| 下方新开一行 | Shift+Enter | `self/open-line-below` |

迷你缓冲（查找、补全输入）里 `C-a` `C-e` `C-f` `C-b` `C-n` `C-p` `C-y` 等仍是行编辑。vertico 打开时 `C-n` / `C-p` 移动候选。

## 做不到或故意改过的地方

1. **双击 Shift。** Shift 只是修饰键，图形 Emacs 收不到「按下又松开」，所以 Search Everywhere 放在 **Ctrl+Shift+P**。Find Action 仍是 **Ctrl+Shift+A**。
2. **Ctrl+G 跳到行。** `C-g` 是 Emacs 的取消键，改掉以后 isearch、补全、哪步出错都退不出来。跳行是 **Ctrl+Shift+G**，`M-g g` 也还在。
3. **Ctrl+C / Ctrl+X 不能永远当复制 / 剪切。** `C-c` 下面是代码、Git、窗口这些前缀，`C-x` 下面是文件和窗口。`cua-mode` 的规则：有选区时这两个键复制 / 剪切；没有选区，或者按住约 0.2 秒，它们仍是前缀。没有选区时复制当前行用 **Ctrl+Shift+C**，剪切用 **Ctrl+Shift+X**。**Ctrl+V** 始终是粘贴。输入替换选区由 `delete-selection-mode` 打开。
4. **Ctrl+H 不是类型层次。** 本档 `C-h` 是左移，帮助在 `<f1>`。没有一个跨语言、又和 IDEA 的类型层次同一回事的命令。
5. **Ctrl+J 不是 Live Template。** `C-j` 仍是下移。模板展开在 `C-c e t`（tempel）。上移的 `C-k` 让给了提交，上移用方向键。
6. **Ctrl+P / Ctrl+F / Ctrl+E / Ctrl+N / Ctrl+Y / Ctrl+W** 不再是上一行、右移、行尾、下一行、粘贴、杀区域。对应关系见上表。右移仍是 `C-l`，下移仍是 `C-j`，行尾用 End，粘贴是 `Ctrl+V`。
7. **Alt+1 … Alt+0 不再是数字参数。** 它们是工具窗。数字前缀用 `C-u` 或 `C-1` … `C-9`。
8. **结构工具窗是弹出列表**，不是 IDEA 左侧那棵常驻大纲。Treemacs 的 tag-follow 会在项目树里展开当前文件的符号，算半个替代。
9. **Services（Alt+8）** 打开的是进程列表，不是 IDEA 的 Services 视图。
10. **Run / Build 都走 Emacs 的 compile**，不是 IDEA 的运行配置下拉框。第一次会问命令，之后 Shift+F10 重复上一次。调试走 dape，第一次要选适配器。
11. **Go to Class** 在多语言里没有「只列类」的索引，用的是项目 imenu（类、函数、标题都会出现）。
12. **块注释** 依赖 major mode 的 `comment-end`。没有块注释语法的语言退回逐行注释。
13. **Optimize Imports** 只在 Eglot 托管、并且语言服务器提供这个 code action 时成功。
14. **Islands 的圆角和真正的浮动卡片** Emacs 的窗口模型做不到，只做了暗色缝隙和不同的底色。
15. **窗口管理器可能吃掉 Ctrl+F4**（有的桌面用它关窗口）。Emacs 收不到就关不了标签，改按 `C-x k`。

原先桌面档的一批直达键还留着，只要不和上表冲突：`C-S-o` 文件结构、`M-s p` 项目搜索、`C-.` 代码操作、`C-,` 打开配置文件、`<menu>` 右键菜单。`C-h j k l` 里只剩 `C-h` 左、`C-j` 下、`C-l` 右；`C-k` 是提交。

## 核对

`just verify` 在 ide 档冒烟之后会加载 `scripts/verify-ide-keys.el`，逐条核对上表里的全局绑定，并确认 `C-c` / `C-x` 仍是前缀、迷你缓冲的 `C-f` 仍是右移、状态栏布局是 `idea`。单独跑：

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=ide \
  emacs --batch -q -l early-init.el -l init.el \
  -l scripts/verify-ide-keys.el </dev/null
```

看到 `IDE-KEYS-OK` 即通过。
