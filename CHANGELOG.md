# Changelog

本文档记录 Slowlight 的产品版本变更。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Changed
- 收口公开 README、Roadmap、贡献指南、自托管说明与发行流程。
- GitHub Preview / Release 的服务端地址改由 Repository Variable 注入，普通源码构建保持 localhost / 自托管语义。
- 公开工作树仅保留当前正式品牌资产、当前设计基线与当前实现文档，不携带旧候选方案和内部历史资料。
- Cloud Data 模式的飞书写入与日历同步在具备可靠幂等 upsert 前明确关闭；Local Data 模式继续使用本机幂等飞书写入。
- Slowlight 项目许可证确定为 MIT；第三方内嵌组件继续保留各自许可证，并增加 `THIRD_PARTY_NOTICES.md` 统一说明。

### Fixed
- 服务端 JWT 校验明确限定 HS256，拒绝意外签名算法。
- 客户端云端 JWT 改用平台安全存储，并兼容迁移旧 SharedPreferences Token。
- HTTP 调试日志不再输出请求体、响应体或认证凭据，避免密码、Token、第三方 Secret 和迁移数据进入日志。
- Android 补齐定时通知 Receiver / 重启恢复声明；精确闹钟不可用时自动降级为非精确提醒。
- Cloud 增量同步的 ObservationTag `dimension_key` 遵守 pending / conflict 保护，不再静默覆盖本地未同步修改。
- 移除尚未实现却会出现在支持列表中的 Notion 占位集成。
- 飞书云端旧批量追加路径不再可通过正式 Provider 入口执行，避免重复记录和失败假成功。

### Security
- 增加 Gitleaks、自定义敏感文件检查、可选本地 pre-commit 与 GitHub Sensitive Information Guard。
- 官方 Android 构建使用固定发行签名 Secret；源码自构建在未配置发行密钥时仍允许使用本地开发签名。
- 服务端数据库、JWT、第三方集成凭据加密密钥保持强制环境配置；当前源码不提供真实凭据回退。

---

## [v0.2.0] - 2026-08-27

> 当前公开预览基线。主要验证平台为 Windows 与 Android；首个公开 Tag 在公开仓库 CI 与实机验收完成后确定。

### Added
- 完成 Local-first 产品核心：本地模式可运行任务、习惯、专注、观察与回顾主流程。
- 新增 Reflection / Observation，闭合 `Facts → Patterns → Questions → Reflection` 长期观察链路。
- 新增统一 Review / Analytics 数据入口，本地与云端共用核心语义。
- 新增独立 AI Provider 层，支持 Ollama / OpenAI / DeepSeek / 自定义 OpenAI-compatible Provider。
- 新增 BYOK 配置：普通配置与密钥分离，密钥进入安全存储。
- 新增多实体同步、稳定 deviceId、冲突策略、增量同步与 authoritative tombstone 基础。
- 新增同步、tombstone、用户隔离、冲突、Session、BehaviorEvent 与迁移相关回归测试代码。
- 完成 Slowlight 品牌源资产、Windows / Android 正式图标以及跨平台 SVG 母版。

### Changed
- 产品主线收敛为「记录 → 观察 → 提问 → Reflection」，Today / Review 成为顶级入口。
- Task / Habit / Focus / Calendar 等收敛为记录工具，Stats / Weekly Review / Time Distribution 收敛为分析工具。
- `Dimension` 与可编辑 ObservationTag 分离，固定 `body / cognition / output / relationship` 四个长期观察坐标。
- Local / Cloud 时间语义统一：instant 使用 UTC，日历日期保留纯日期语义。
- Task / Habit / ObservationTag / Review / Analytics 主调用链完成 Repository / API 收敛。
- SyncService 从 Local Data 普通 CRUD 主链移除，仅服务 Cloud Data 离线与多端同步。
- 产品与技术身份统一使用 Slowlight / slowlight；Android `applicationId` / `namespace` 使用 `site.z7ping.slowlight`。
- Windows 客户端默认启用软件渲染，可通过 `SLOWLIGHT_HARDWARE_RENDERING=1` 恢复硬件渲染。
- Android 隐藏不适合移动端的桌面休息提醒能力。
- 官方 Android Preview / Release 工作流使用固定发行签名。

### Fixed
- 修复 NVIDIA 显示驱动重置后 Windows 客户端可能长期白屏的问题。
- 修复桌面端托盘、启动与多窗口相关稳定性问题。
- 修复任务链 attempt 取消/回滚时可能误删既有任务的数据安全问题。
- 修复同步中 `dimension_key` 丢失、cursor 推进、远端删除与 pending 冲突处理问题。
- 修复 Task 编辑长期字段被默认值覆盖、Habit false/0/空标签更新语义不一致等问题。
- 修复 Cloud Habit 补卡日期与用户时区边界问题。
- 修复 Local Review / Analytics 对 instant 使用日期 LIKE 查询导致的时间边界偏差。

### Preview Scope
- 主要平台：Windows、Android。
- 发行门禁：Flutter tests、Go tests、公开文档检查、敏感信息检查、Windows Release 构建、Android Release APK 构建、同步/冲突/删除等回归与 Windows/Android 实机验收。
- iOS / macOS / Linux / Web 暂不作为首个公开预览版本的阻塞平台。
- Local ↔ Cloud 自动迁移和飞书完整双向闭环在完成真实数据验收前不作为稳定能力宣称。

---

## 版本说明

- **Unreleased**：正在开发、尚未形成公开 Release 的变化。
- **[x.y.z]**：产品版本记录；是否存在对应公开 GitHub Release 以仓库 Releases 页面为准。
- **Added / Changed / Fixed / Security**：分别表示新增、调整、修复和安全相关变化。
