# AI 开发协作说明

本文件是 Slowlight 公开仓库中的 Agent 开发协作规则。

- 默认使用中文沟通；代码、协议名、库名和字段名保留原文。
- 先理解现有代码、测试、配置、公开文档和生成工件，再判断问题是局部 / 页面 / 流程级，采用解决根因所需的**最小充分范围**修改；不得机械把页面级问题压成单点补丁。
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

- 页面优先使用 `client/lib/ui/fx.dart` 暴露的 Fx 组件；Screen / Feature Widget 不应绕过已有 Fx 视觉能力直接建立另一套 Material / shadcn_ui 实现。
- `shadcn_ui` 是主要视觉底座；Fx 负责统一接口、状态、响应式与必要的平台适配，不因迁移重新设计既有高保真。
- Fx 内部优先使用 shadcn_ui；Material 视觉控件仅允许作为有明确能力原因的平台适配例外，并保持 Slowlight 已确认视觉。
- spacing、radius、font size 优先使用统一 Theme / Design Token，避免硬编码颜色和一次性 magic number。
- 应用壳层断点使用 600 / 1024；组件内部根据真实可用宽度决定折叠，不自行扩散私有全局断点。
- 同时支持亮色 / 暗色主题。
- Android 主要可点击热区以 44px 为最低基线；Windows 保持高密度可见尺寸，不能为了移动端触控目标把桌面控件和布局整体撑大。
- 不在生产代码保留临时 `debugPrint`。
- 不重新设计已经确定的 Slowlight Logo。页面设计范围统一按下方“整页设计优先级”和权威 UI/UX 规范判断，不再保留单独的“高保真冻结”绝对约束。

### 整页设计优先级

用户可见问题先判断根因层级：

- **局部问题**：Token、单一文案、一个按钮状态、明确实现漂移等，按最小充分范围修复。
- **页面级问题**：用户明确说「重新设计」「一步到位」「很丑」「体现不了水准」「从新用户视角全面检查」，或问题涉及信息架构、视觉层级、密度/留白、多个相邻区块、跨页动线时，默认按**整页或完整流程**设计。
- 页面级设计施工前一次性确定：用户目标、首屏理解、信息架构、视觉构图、主次/危险操作、加载/空/错误/部分成功/未知结果、接口事实、Windows/Android 差异、长文本/大字号/窄屏/亮暗主题。
- 施工后重新从整页视角复查，不得只检查“用户刚点名的问题是否改掉”。目标是减少用户继续逐项发现基础 UI/UX 缺陷。
- “复用 Fx / Token”“不建立第二套设计系统”“冻结已确认产品方向”仍然有效，但**这些是边界，不是拒绝整页设计的理由**。整页重做应优先重组现有能力，不默认新造组件或改变已确认产品方向。

### 用户可见变更交付门禁

任何新增或修改用户可见功能（含按钮、设置、弹层、反馈、布局微调），先查 **现有代码与真实调用路径**，再核对内部权威高保真和 `product-internal/slowlight/agent-swe/knowledge/04_系统设计/UIUX设计规范.md` 的 §10、§13、§15，不得只按当前截图或个人直觉补样式。

- **开发前**：写明入口/信息层级、主次/危险操作、成功去向和返回/取消；按业务判断 Loading、Empty、Error、离线、权限、重试、回滚、重复点击、异步过期是否适用。纯静态修改不机械造全部状态，但要检查长文字、窄屏和大字号是否破版。
- **施工时**：复用已有 Fx/Token/Feature 和正式服务/数据状态；UI 复用不等于交互已经设计。不能将失败渲染为空数据、请求中冒充成功、保存失败显示生效；不做伪状态按钮和失效重试。保持 Windows 高密度与 Android 44px 触控策略的差别。
- **PR / Issue 收口**：写清设计依据、问题层级与最小充分修改范围、交互状态与恢复、Windows/Android 目标范围、实际测试/视觉证据和未验证风险。适用的关键状态缺失不得标记“功能完整交付”；可按用户授权仅做代码阶段合并，但必须如实留下实机体验待验。**PR 发起后按项目约定自行合并，不以远端 CI 作为等待门槛。合并前必须先做快速自检：对本次改动涉及的 Token、枚举、构造参数、导入、方法签名、测试依赖和新增标识符逐项核对仓库真实定义，并检查改动文件的语法结构与引用链。** CI 作为事后兜底；若后续发现失败，继续自行修复。不得把用户本地编译当作第一道校验。
- **边界**：冻结的是已确认产品方向和明确决策，不是被用户当前明确否定的页面质量。用户未重开设计时不擅自改方向；用户明确要求重设计或权威资料冲突时，先在 `product-internal` 更新完整页面方案，再实施。公开仓库不复制第二份高保真。

验证：

```bash
cd client
flutter test
flutter build web
```

UI 改动还需要按改动范围验证 Windows 常用窗口 / DPI / Hover / Focus 与 Android 窄屏 / 大字体 / Sheet / 返回手势；CI 绿不等于视觉验收完成。

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
