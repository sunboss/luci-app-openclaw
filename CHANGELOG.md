# Changelog

本项目所有重大变更都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

## [1.0.0] - 2026-03-02

### 新增
- LuCI 管理界面：基本设置、配置管理（Web 终端）、Web 控制台
- 一键安装 Node.js + OpenClaw 运行环境
- 支持 x86_64 和 aarch64 架构，glibc / musl 自动检测
- 支持 12+ AI 模型提供商配置向导
- 支持 Telegram / Discord / 飞书 / Slack 消息渠道
- `.run` 自解压包和 `.ipk` 安装包两种分发方式
- OpenWrt SDK feeds 集成支持
- GitHub Actions 自动构建与发布

### 安全
- WebSocket PTY 服务添加 token 认证
- WebSocket 最大并发会话限制（默认 5）
- PTY 服务默认绑定 127.0.0.1，不对外暴露
- Token 不再嵌入 HTML 源码，改为 AJAX 动态获取
- sync_uci_to_json 通过环境变量传递 token，避免 ps 泄露
- 所有渠道 Token 输入统一 sanitize_input 清洗

### 修复
- Telegram Bot Token 粘贴时被 bracketed paste 转义序列污染
- Web PTY 终端粘贴包含 ANSI 转义序列问题
- 恢复出厂配置流程异常退出
- Gemini CLI OAuth 登录在 OpenWrt 上失败
- init.d status_service() 在无 netstat 的系统上报错
- Makefile 损坏导致 OpenWrt SDK 编译失败

### 改进
- 所有 AI 提供商模型列表更新到最新版本
- UID/GID 动态分配，避免与已有系统用户冲突
- 版本号统一由 VERSION 文件管理
- README.md 完善安装说明、FAQ 和项目结构
