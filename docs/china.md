# 中国大陆网络使用指南

UniEmacs 的安装与首次启动要访问的网络资源里，除 ELPA 归档（默认清华镜像）
外，其余默认全部直连 GitHub。本文按链路给出做法与边界，所有配置都是可选的
加速项——不配也能装完，只是慢。

## 链路清单

| 环节 | 默认源 | 国内状况 | 做法 |
| --- | --- | --- | --- |
| 取安装脚本 `install.sh` | `raw.githubusercontent.com` | 常不可达 | Gitee 直链 |
| 克隆配置仓库 | `github.com/ShineBreaker/UniEmacs` | 慢 | Gitee 镜像 |
| ELPA 归档 | 清华 TUNA 镜像 | 正常 | 已默认，无需操作 |
| 首次启动装约 60 个包 | elpaca 逐个 `git clone` 上游仓库 | 最慢的一环 | git URL 改写 |
| Maple 字体 zip（160 MB） | GitHub Releases | 慢 | 同上，或离线拷贝 |
| Windows 预编译语法库（14 MB） | GitHub Releases | 慢 | 同上 |

URL 以代码为准（字体见 `modules/base/self-bootstrap.el` 的
`self:bootstrap-font-url`，语法库见 `self:bootstrap-grammars-url`），
体积为发布资产的实测值。

## 一、取脚本与克隆仓库：走 Gitee 镜像

Gitee 镜像与主仓库自动同步，代码完全相同：<https://gitee.com/brokenshine/UniEmacs>。

Linux / macOS / Android 一键安装：

```sh
curl -fsSL https://gitee.com/brokenshine/UniEmacs/raw/main/install.sh | sh -s -- --mirror gitee
```

`sh -s --` 是给管道读入的脚本传参的标准写法：`-s` 让 sh 从 stdin 读脚本，
`--` 之后才是脚本自己的参数。脚本已下载到本地时，直接
`sh install.sh --mirror gitee` 即可，`sh install.sh --help` 可查全部选项。

Windows 或手动克隆：

```powershell
git clone https://gitee.com/brokenshine/UniEmacs "$env:APPDATA\.emacs.d"
```

`--mirror` 只决定 `install.sh` 从哪个地址 clone。仓库落地后
`origin` 指向 Gitee，此后 `git pull` 更新也走镜像。想切回主仓库：

```sh
git remote set-url origin https://github.com/ShineBreaker/UniEmacs.git
```

镜像的边界：只承载代码。Releases 资产（字体 zip、[termux-emacs](https://github.com/ShineBreaker/termux-emacs) 的 APK）
与 issue / PR 仍在 GitHub。

## 二、ELPA 归档：已默认走清华镜像

`self:elpa-mirror` 默认 `tuna`，GNU、NonGNU、MELPA 三个归档都指向
`mirrors.tuna.tsinghua.edu.cn/elpa/`。要换源：

```elisp
(setq self:elpa-mirror 'ustc)   ; 或 nil 走官方源
```

注意它只影响 `package.el` 的归档下载。elpaca 装包的常规路径是从上游
`git clone`，不走归档——见下一节。

## 三、首次启动装包：给 git 配 URL 改写

首次启动 elpaca 会逐个 `git clone` 约 60 个包的上游仓库，这是国内最耗时、
也最容易失败的一环。让 GitHub 请求自动走代理前缀：

```sh
git config --global url."<代理前缀>https://github.com/".insteadOf "https://github.com/"
```

`<代理前缀>` 取自你手头的工具——自己的代理转换端点、公司内网镜像等。配置后
`git clone https://github.com/foo/bar` 实际请求
`<代理前缀>https://github.com/foo/bar`。撤销：

```sh
git config --global --unset url."<代理前缀>https://github.com/".insteadOf
```

边界有四条，都值得先看清：

- **全局生效**。对这台机器上所有 GitHub git 操作有效，包括你自己的其他仓库
  与向 GitHub 推送。elpaca 的 clone 落在 `~/.cache/emacs/elpaca/sources/`，
  不属于任何 git 工作区，没有仓库级的替代写法。
- **覆盖不到 curl 下载**。字体与语法库由 `curl` 完成，走的是
  `HTTPS_PROXY` 环境变量，不是 git 配置——见第四节。
- **覆盖不到 MELPA 配方仓库**。上游 `elpaca-menu-melpa--clone` 把
  `GIT_CONFIG_GLOBAL` 指向 `/dev/null`，用户级 git 配置对它无效。它只在首次
  启动拉一次，且 sparse checkout 只取 `recipes/`，体积小，通常能忍。
- **`self:github-proxy` 不覆盖这些流量**。它只作用于 elpaca 本体与安装脚本的
  下载地址。

## 四、字体与语法库：走 HTTPS_PROXY 或离线

两者都是在首次启动后台下载、不阻塞启动，失败后 24 小时内不自动重试。

要走代理，在**启动 Emacs 前**设好环境变量（`curl` 读它）：

```sh
export HTTPS_PROXY=http://127.0.0.1:<端口>
```

不想等 160 MB 的字体包，可以离线补：把 `MapleMono-NF-CN-Regular.ttf`、
`-Italic.ttf`、`-Bold.ttf` 三个文件放进系统字体目录——Linux 为
`~/.local/share/fonts/`，Windows 为 `%LOCALAPPDATA%\Microsoft\Windows\Fonts\`
（且需在系统里安装一次以完成注册表登记），Android 为 Emacs 应用家目录的
`fonts/`。缺失判定为「系统字体列表里没有 Maple Mono NF CN **且**该目录下没有
Regular 那个文件」，任一条件不成立即视为已装、不再下载。

手动重试：

```text
M-x self/bootstrap-fonts
M-x self/bootstrap-grammars
```

要立刻重试而不等冷却，删掉 `~/.cache/emacs/bootstrap-last-failure`。

## 五、装坏了怎么查

- 重跑安装命令是幂等的：已 clone 则 `git pull`，然后重新验证。
- `M-x self/deploy-diagnose` 给出诊断结论。
- 装包中断不用怕：重跑启动会接着装。

## 六、海外用户无需配置

默认值对海外网络同样成立。上面列的动作都只是加速项，不配置也能装完。
