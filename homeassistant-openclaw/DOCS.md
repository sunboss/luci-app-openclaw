# OpenClaw Home Assistant Add-on

这个 add-on 不是把 LuCI 页面原样搬进 Home Assistant，而是把 `luci-app-openclaw` 里真正有价值的部分迁成了 Home Assistant 更适合的运行方式：

- OpenClaw 程序在镜像构建时就装好，不再依赖 OpenWrt 里的运行时下载。
- 配置和状态统一放到 `/data/openclaw`，重启或升级 add-on 后会保留。
- 通过 Home Assistant ingress 打开 OpenClaw Web UI，不再依赖 LuCI iframe。
- 启动时会自动补 OpenClaw 配置、执行一次必要的 `doctor --fix` 迁移，并修补 iframe 相关响应头。

## 安装

1. 把当前仓库作为 add-on repository 加到 Home Assistant。
2. 安装 `OpenClaw` add-on。
3. 启动 add-on。
4. 从 add-on 日志里复制启动时输出的 `OpenClaw token`，或者读取 `/data/openclaw/gateway_token.txt`。
5. 从 Home Assistant 侧边栏打开 `OpenClaw`，首次进入会自动带上 token。

## 选项

- `gateway_token`: 留空会自动生成并持久化；填写后会覆盖为你指定的 token。
- `tools_profile`: 默认为 `coding`。
- `disable_update_check`: 默认关闭 OpenClaw 自检更新横幅，减少干扰。

## 当前取舍

- LuCI 里的“配置终端”“微信向导”“备份弹窗”没有直接照搬到 add-on UI。
- Home Assistant 已经有自己的 add-on 生命周期和备份机制，所以这些 OpenWrt 专属交互先被替换掉了。
- 如果后续要继续补能力，优先建议做成：
  - add-on 选项页
  - 独立的 ingress 辅助页
  - 或直接使用 OpenClaw 自带 Web UI / CLI

## 目录

- `config.yaml`: Home Assistant add-on 元数据
- `Dockerfile`: 基于 Home Assistant base image 的镜像构建
- `run.sh`: 初始化、配置同步、nginx ingress 代理和 OpenClaw 主进程启动
