# Slowlight Roadmap

Slowlight 的长期目标是把任务、习惯、专注和观察形成的行为事实，逐步沉淀为模式、问题与 Reflection，帮助用户在不被系统评判或替代决策的前提下，更长期地看见自己。

精确工程事实以代码、配置、测试和 `docs/_generated/` 为准；本文件只描述公开产品方向，不承诺具体发布日期。

## Current — 公开预览与狗粮稳定

当前优先保障 **Windows + Android** 的真实使用体验。

### 数据安全与可靠性

- [x] Local-first：核心任务、习惯、专注、观察与回顾可在本地模式运行。
- [x] Local / Cloud 数据模式分离，普通本地使用不依赖 Slowlight Server。
- [x] 多实体增量同步、稳定 deviceId、ID 映射与 tombstone 基础。
- [x] `localWins / remoteWins / merge / askUser` 冲突策略。
- [x] 同步、冲突、删除、用户隔离等回归测试代码。
- [ ] 完成 Windows + Android 真实多设备、断网恢复、远端删除与长时间运行验收。
- [ ] 完整验证 Local ↔ Cloud 数据迁移的预览、冲突、幂等和回滚边界后再开放一键迁移。

### 产品核心

- [x] Today / Review 双主线。
- [x] Task / Habit / Focus 统一形成 BehaviorEvent 行为事实。
- [x] 固定 Dimension：身体 / 认知 / 产出 / 关系。
- [x] ObservationTag 用于把具体行为映射到长期观察坐标。
- [x] Reflection / Observation 闭合“事实 → 模式 → 问题 → 反思”链路。
- [x] Review / Analytics 在 Local / Cloud 下统一核心语义。
- [ ] 继续用真实狗粮反馈修正交互、异常状态与数据边界问题。

### AI

- [x] AI Provider 与 Data Mode 正交。
- [x] 支持 Ollama、OpenAI、DeepSeek 和自定义 OpenAI-compatible Provider。
- [x] BYOK：普通配置与密钥分开保存，密钥进入安全存储。
- [x] AI 以解释事实、发现模式、提出开放问题为主，不默认替用户决定“下一步该做什么”。
- [ ] 在真实长期数据上继续验证 AI 解读质量、成本和隐私边界。

### 外部集成

- [x] Local Data 模式支持飞书多维表格配置、建表/连接和幂等写入。
- [x] CalDAV 与 Webhook 基础能力。
- [x] Cloud Data 模式的飞书危险写入已设安全边界：在具备可靠幂等 upsert 前明确拒绝导出和日历写入，不以重复数据换取“可用”。
- [ ] 为 Cloud Data 飞书建立稳定的远端记录映射 / upsert、失败重试和幂等语义，再重新开放写入。
- [ ] 飞书完整双向闭环在数据边界成熟后再开放，不把当前 Local Data 单向写入描述为完整双向同步。

## Next — 公开预览稳定后

- 完善 Local ↔ Cloud 数据迁移体验与报告。
- 收敛 Flutter UI 组件边界、响应式规则和历史遗留页面。
- 强化同步诊断、冲突解释和用户可恢复能力。
- 补齐更稳定的自托管 Server 部署说明与升级策略。
- 提升 Review 的周/月长期观察能力。
- 为 Cloud Data 飞书补齐幂等写入与完整失败语义后，再评估双向同步。
- 根据真实反馈决定 CalDAV、Webhook 的进一步产品化优先级。

## Later

以下方向不会阻塞当前 Windows + Android 版本：

- iOS / macOS 正式发行适配。
- Linux 桌面端正式发行适配。
- Web 作为正式使用入口的体验与安全边界。
- 更长期的行为模式比较、Reflection 检索和可解释 AI 能力。
- 更完整的数据导入、导出和迁移工具。

## 产品原则

Roadmap 中的新能力都应遵守以下原则：

1. **事实优先**：记录真实发生的行为，不把计划等同于事实。
2. **镜子，不是教练**：描述、提问和帮助理解优先于替用户做决定。
3. **Local-first**：不因为新增云端或 AI 能力破坏本地独立使用。
4. **数据安全优先于功能速度**：任何同步、迁移和集成都不能以静默覆盖、数据复活、重复写入或假成功换取体验上的“顺滑”。
5. **真实验证优先于功能宣称**：代码存在不等于已经完成真实环境验收。

## 当前发布优先级

```text
数据不丢、不重复、不复活
  > Windows / Android 真实可用
  > 同步与外部集成真实验收
  > 体验收口
  > 新功能
```
