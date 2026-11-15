# 设计一致性：开发与检查入口

此文件只说明公开代码中的组件边界与检查方式，不复制私有高保真、产品方案和验收截图。

## 开始修改 UI 前

1. 读取适用的 `AGENTS.md`，定位当前页面与真实业务调用。
2. 在有内部设计库的环境读取 `product-internal/slowlight/DESIGN.md`，按其索引定位对应原型与专题；不要默认 `DESIGN.md` 已被自动载入。
3. 写明本次设计依据、复用组件、两端范围、主次操作与关键状态。内部资料不可用时，保留公开契约检查，不能把现有实现臆断为新设计或宣称与高保真一致。

## 代码中的唯一复用入口

- [Fx 导出](client/lib/ui/fx.dart)：业务页面通过 Fx / Feature 使用产品视觉。
- [布局 Token](client/lib/ui/layout_tokens.dart)：共享间距、圆角、平台密度与壳层断点。
- [排版 Token](client/lib/ui/typography_tokens.dart)、[颜色 Token](client/lib/ui/color_tokens.dart)：避免页面另建字号与产品色。
- [统一测试宿主](client/test/support/fx_test_host.dart)：测试沿用产品主题和反馈宿主。

App Shell 使用 600 / 1024；Feature 根据实际可用宽度折叠。Android 主点击目标至少44px，Windows 保留桌面密度。平台差异通过现有组件与 Token 解析，不能以“统一”为由抹平。

## 一条本地检查命令

先在 `client` 中完成项目正常的 `flutter pub get`。随后在仓库根目录执行：

```powershell
python scripts/design/check.py --report client/build/design-check/report.json
```

上例相对路径以仓库根目录为工作目录。脚本本身依据所在仓库定位测试，不依赖个人机器目录。

它运行现有组件契约和生产入口的页面回归，包括主导航、任务、习惯、日历、统计、设置和迁移历史。组件测试放在 `client/test/ui`，页面清单见 [检查入口](scripts/design/check.py)。共享组件有行为或布局变化时，核对实际调用点，并在受影响的代表性页面断言用户能看到或操作的结果。

[公共 UI Token 快照](client/test/fixtures/design/ui_tokens.json) 与 [UI-16/17 Sheet 快照](client/test/fixtures/design/android_bottom_sheet.json) 由内部 UI/UX 规范导出。更新与联验命令见内部设计入口的「结构化设计值」。Flutter 用现有设计检查核对主题、双平台字号、基础布局、Windows 按钮定义、Android 按钮命中区、紧凑月格及 Android 底栏。Sheet 从任务新建、习惯打卡和记录观察测双顶角与拖动起始区。

检查失败需要修复根因；不得通过扩大例外、更新截图或删除测试把失败变成通过。现有规则无法表达的合理平台适配，先说明能力原因，再在最小范围调整规则及反例。

## 验收不能由测试代替

UI 改动在 PR 中给出设计依据、相关页面与状态、实际运行命令，以及证据。页面级变更至少对照：

| 范围 | 场景 |
| --- | --- |
| Windows | 1280×720/800、100%/125% DPI、亮暗、Hover/Focus、键盘 |
| Android | 360dp、130%+系统字体、亮暗、滚动、键盘与返回 |
| 数据状态 | 正常/空/加载/错误；写入适用时再查待同步、部分成功、结果未确认 |

截图注明提交与工作区状态、平台、窗口/DPI或dp/字体倍率、主题、测试数据和状态。原型、Flutter测试宿主截图、真实设备证据分开标注。未执行项填写“待验”，不勾选通过。

CI 的“设计一致性契约”步骤是代码层失败门禁；合并策略仍遵循项目约定。整页外观、产品取舍及实际设备体验由相应证据验收，不能因为CI通过自动批准。首版视觉基线需明确确认后才能用于后续对比；不自动将当前截图写成已确认基线。
