# AI 开发协作说明

本文件是 Slowlight 公开仓库中的 Agent 开发协作规则。

- 默认使用中文沟通；代码、协议名、库名和字段名保留原文。
- 先理解现有代码、测试、配置、公开文档和生成工件，再做最小范围修改。
- 不凭历史记忆编造业务规则、外部依赖、运行环境或已完成能力。
- 涉及分支、HEAD、PR、CI、Release 等易变事实时，必须实时核验。
- 内部工作状态、私人知识库和本机环境信息不得作为公开仓库事实源。

## 精确工程事实

同一精确工程事实只保留一个主要权威来源：

- HTTP 路由/Method：`server/cmd/main.go`；
- Go Model：`server/internal/model/`；
- SQLite Schema：`client/lib/db/local_db.dart`；
- 客户端版本和 Flutter 依赖：`client/pubspec.yaml`；
- Go 依赖：`server/go.mod`；
- 服务端环境变量：代码中的实际 `os.Getenv(...)`；
- 自动生成工程事实：`docs/_generated/`；
- 产品公开方向：`ROADMAP.md`。

修改上述事实后按需运行：

```bash
python scripts/docs/generate.py
python scripts/docs/check.py
```

Python 用于文档生成与 CI 检查，不是普通本地提交的强制依赖。

## Backend Guidelines

- 服务端入口：`server/cmd/main.go`。
- 领域模型：`server/internal/model/`。
- HTTP Handler：`server/internal/handler/`。
- 外部集成：`server/internal/integration/`。
- CalDAV：`server/internal/caldav/`。
- 数据库初始化：`server/internal/config/database.go`。
- 当前 Handler 直接使用 GORM；无关任务不要为了形式擅自引入新分层。
- 修改 API 时同时检查客户端调用兼容性。
- 修改 Task / Habit / Session 时检查统一 `behavior_events` 写入行为。
- 同步相关修改重点检查本地/服务端 ID 映射、`sync_queue`、删除、重试、冲突策略和多设备边界。

常用验证：

```bash
cd server
go test ./...
go build -o slowlight ./cmd
```

## Flutter Client Guidelines

- 入口：`client/lib/main.dart`。
- 页面：`client/lib/screens/`。
- 通用组件：`client/lib/widgets/`、`client/lib/ui/widgets/`。
- 服务：`client/lib/services/`。
- 客户端模型：`client/lib/models/`。
- Repository：`client/lib/repositories/`。
- 本地数据库：`client/lib/db/local_db.dart`。

UI 规则：

- 页面优先使用 `client/lib/ui/fx.dart` 暴露的 Fx 组件。
- 不无理由绕过 Fx 层直接堆 Material / shadcn_ui。
- spacing、radius、font size 优先使用统一 Theme Token。
- 避免硬编码颜色和一次性 magic number。
- 同时支持亮色 / 暗色主题。
- 可点击控件尽量不小于 44px。
- 不在生产代码保留临时 `debugPrint`。
- 不重新设计已经确定的 Slowlight Logo。

验证：

```bash
cd client
flutter test
flutter build web
```

## 安全与数据完整性

修改或审查代码时优先关注：

- 用户数据完整性与 Local / Cloud 同步；
- 冲突处理、ID 映射、离线队列、tombstone；
- 日期、时区、重复任务；
- 提醒、通知、CalDAV、飞书与 Webhook；
- BehaviorEvent 是否遗漏或错误回滚；
- API 与客户端兼容性；
- 敏感信息不得进入源码、日志、Issue、PR 或构建产物。

安全规则见 [`SECURITY.md`](SECURITY.md)，贡献规则见 [`CONTRIBUTING.md`](CONTRIBUTING.md)。

## 完成前

至少运行与改动直接相关的测试/构建。修改生成工程事实相关代码时，再运行：

```bash
python scripts/docs/check.py
```

结束时明确说明修改内容、验证结果和仍未验证的风险项。不得把“代码存在”描述成“真实环境已经验证通过”。
