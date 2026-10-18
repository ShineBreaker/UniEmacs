# UniEmacs

跨桌面与手机的统一 Emacs 配置：单一代码库，四档 profile。

| 档位       | 场景                                                                                | 选择方式                    |
| ---------- | ----------------------------------------------------------------------------------- | --------------------------- |
| `minimal`  | 底座：纯内建、可调试、秒开                                                          | `UNI_EMACS_PROFILE=minimal` |
| `portable` | Android 原生 Emacs 触屏                                                             | Android 上自动；可 env 强制 |
| `full`     | 桌面全量：功能完备、可读性优先的学习档                                              | `UNI_EMACS_PROFILE=full`    |
| `ide`      | full 超集：Zed 对齐的深度定制（Treemacs 树/命令面板补全/面包屑/行内 blame/minimap） | 默认档                      |

> ide 档是给「从 Zed/现代 IDE 直接迁移」的用户的直接承接层；full 档保持语法平铺直白，是学习用的完备桌面档。

## 结构速览

- `early-init.el` / `init.el` — 入口
- `core/` — 四档共享基础设施（平台谓词、路径、包后端）
- `modules/` — 全部功能模块（`self-*.el`，含 `ide/` 档专属层）
- `profiles/` — 四档的模块清单与包声明
- `data/` — 翻译表、图标资产
- `docs/architecture.md` — 设计文档；`docs/mobile/` — 手机安装指南与 Termux 重签专题
- `scripts/` / `justfile` — 验证与运维命令（APK 重签脚本见 `docs/mobile/`）
- `assets/` / `.github/workflows/` — Termux 重签密钥（Emacs 官方公开）与 CI 流水线

## 开发

设计原则：**可读性优先**——代码按 Emacs 初学者能读懂、能写、能调的标准组织（直白平铺 > 高阶压缩，函数体 ~40 行预算，详见 `docs/architecture.md` §1 与 `AGENTS.md` §3）；**单一真相源**——同一概念只允许一处定义。

```bash
direnv allow       # 或 denv load；环境由 manifest.scm 声明
just verify        # 启动后路径探针 + 图标字形覆盖 + 四档沙箱冒烟
just compile       # 全模块 byte-compile 零警告
```

手动冒烟某档：

```bash
HOME=$(pwd)/.sandbox UNI_EMACS_PROFILE=minimal \
  emacs --batch -q -l early-init.el -l init.el
```

## 部署

- 桌面：入口两文件（`early-init.el`、`init.el`）放 `~/.config/emacs/`，`user-emacs-directory` 重定向到本仓库。
- Android：入口两文件复制到 Emacs 应用家目录的 `.emacs.d`（`/data/data/org.gnu.emacs/files/.emacs.d/`），仓库本体 clone 到 Termux home 的 `~/.config/emacs`；Termux 需为与 Emacs 同签名的重签版（本仓库 Releases 直接下载，或 `just termux` 自产），完整安装流程见 `docs/mobile/README.md`。

详见 `docs/architecture.md` §6。

## 规范

AI agent 与贡献者工作前先读 `AGENTS.md`。
