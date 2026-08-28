# 为 Slowlight 贡献

感谢你关注 Slowlight。当前项目仍处于公开预览阶段，贡献优先级是 **数据安全、真实可用和现有产品方向的一致性**，而不是快速堆叠功能。

## 开始之前

建议先阅读：

- [`README.md`](README.md)：产品定位、当前能力与运行方式；
- [`ROADMAP.md`](ROADMAP.md)：公开产品方向与优先级；
- [`SECURITY.md`](SECURITY.md)：敏感信息与安全门禁；
- [`AGENTS.md`](AGENTS.md)：AI Agent 或自动化编码工具的协作约束。

## 本地开发

### Flutter 客户端

```bash
cd client
flutter pub get
flutter test
```

需要运行应用时：

```bash
flutter run
```

当前主要验收平台为 Windows 和 Android。Web 可用于构建回归，但暂不是正式发行重点。

### Go 服务端

需要 Go 1.23 和 PostgreSQL 16。

```bash
cp .env.example server/.env
cd server
go mod download
go test ./...
go run ./cmd
```

`.env.example` 只包含示例值。不要把真实数据库密码、JWT 密钥、第三方 Token 或其它凭据提交到仓库。

## 提交前检查

根据改动范围至少运行相关检查：

```bash
cd client && flutter test
cd server && go test ./...
```

修改路由、模型、依赖或服务端环境变量后，更新并检查生成工程事实：

```bash
python scripts/docs/generate.py
python scripts/docs/check.py
```

Python 只用于文档生成/检查和 CI，不是普通本地提交的强制依赖。

### 更新版本号

发布前使用 PowerShell 7 统一更新 Flutter 版本、README 版本基线、Changelog 和生成文档：

```powershell
pwsh scripts/bump-version.ps1 -Version v1.0.0-alpha.1 -BuildNumber 1
```

`-Version` 同时接受 `v1.0.0-alpha.1` 和 `1.0.0-alpha.1`，最终 Git Tag 始终使用 `v` 前缀，`client/pubspec.yaml` 写入 `1.0.0-alpha.1+1`。脚本会把当前 `Unreleased` 内容提升为对应版本段，但不会创建 Commit、Tag 或推送。需要先预览时增加 `-DryRun`。

### 可选的本地敏感信息检查

如果本机安装了 Gitleaks，可以启用仓库提供的 pre-commit：

```bash
git config core.hooksPath .githooks
```

未安装 Gitleaks 时本地 Hook 只提示，不阻止提交；GitHub CI 仍会执行正式敏感信息门禁。

## 数据完整性要求

涉及以下区域的修改需要额外谨慎：

- Local / Cloud 数据模式；
- Sync Queue、cursor、ID 映射和 tombstone；
- 删除、冲突和离线恢复；
- Task / Habit / HabitLog / WorkSession / BehaviorEvent；
- 日期、时区、重复任务；
- Local ↔ Cloud 数据迁移；
- 飞书、CalDAV、Webhook 等外部集成。

此类改动至少要考虑：

1. 删除的数据不能被其它设备重新“复活”；
2. 重复同步不能产生重复记录；
3. false、0、空字符串和 null 不能被错误地当成“没有更新”；
4. 冲突不能静默覆盖用户数据；
5. 外部服务失败不能显示成成功；
6. 一个用户的数据不能被另一个用户读取或修改。

如果无法完成真实环境验证，请在 PR 中明确写出尚未验证的部分，不要把“代码已实现”描述为“已经验证可用”。

## UI 贡献

- 优先使用 `client/lib/ui/fx.dart` 暴露的 Fx 组件；
- spacing、radius、字号和颜色优先使用现有 Theme Token；
- 同时检查亮色 / 暗色主题；
- 可点击区域尽量不小于 44px；
- 不为了视觉重构绕过现有 Controller / Repository / Service 边界；
- 不重新设计已经确定的 Slowlight Logo。

## Pull Request

PR 建议保持单一目标，并说明：

- 为什么要改；
- 改了什么；
- 执行了哪些测试/构建；
- 哪些风险仍未验证；
- 是否涉及数据迁移、同步、外部集成或敏感配置。

不要在 PR、Issue、日志、截图或测试数据中粘贴真实 Secret。

## 当前不建议的贡献方向

在公开预览稳定之前，优先不要：

- 大规模重做产品架构；
- 为了“更智能”恢复默认替用户决定下一任务的教练模式；
- 让 Local-first 核心能力强依赖 Slowlight Server；
- 把尚未完成真实验证的迁移或双向同步宣称为稳定能力；
- 为 iOS / macOS / Linux / Web 的非阻塞问题牺牲 Windows / Android 的当前稳定性。

如果要讨论明显超出当前 Roadmap 的能力，建议先开 Issue 说明问题、使用场景和数据边界，再决定是否进入实现。
