# 所行映我 · Slowlight 品牌规范

> **行为留下轨迹，时间让自我显影。**

## 品牌定义

- 中文主品牌：**所行映我**
- 英文品牌：**Slowlight**
- 标准组合：**所行映我 · Slowlight**
- 品牌 Slogan：**行为留下轨迹，时间让自我显影。**
- 核心意象：真实行为形成轨迹，长期积累让自我逐渐显现。

“所行”强调真实发生的行为事实，而不是计划本身；“映我”强调这些长期事实帮助用户看见自己，但不替用户定义自己。Slowlight 使用“长时间显影”的隐喻：单次行为只是微弱信号，持续积累后才逐渐形成可理解的轨迹与轮廓。

## 正式方案

正式 Logo 为 **“光迹成形”**。平台适配只做尺寸、留白、对比度与系统规范上的光学适配，不重新设计 Logo。

设计语义：

- 外部光弧：时间与持续积累；
- 光点：一次可追溯的真实行为；
- 中部流动光迹：行为之间逐渐形成的连续轨迹；
- 右侧开放轮廓：正在显现、但不被系统最终定义的“我”；
- 点状来路：来自任务、习惯、专注和其它数据源的离散行为事实。

## 正式事实源

正式 Logo 与应用图标以以下文件为准：

- `slowlight-logo-mark.svg`：正式纯图形 Logo 几何母版；
- `slowlight-logo-horizontal.svg`：正式横版品牌组合；
- `../../../assets/brand/slowlight/masters/slowlight-app-icon-dark.svg`：正式深色应用图标母版；
- `../../../assets/brand/slowlight/masters/slowlight-app-icon-light.svg`：浅色备份母版；
- `../../../assets/brand/slowlight/masters/slowlight-app-icon-monochrome-dark.svg`：单色深色备份母版；
- `../../../assets/brand/slowlight/masters/slowlight-app-icon-monochrome-light.svg`：单色浅色备份母版。

PNG / ICO 等平台静态资产是这些母版的交付结果，不反向作为 Logo 几何事实源。

## 平台优先级

当前优先保障 **Android + Windows**：

1. Android + Windows 正式图标和用户可见品牌必须可用；
2. 品牌规范和 SVG 母版必须与这两个平台保持同步；
3. iOS / macOS / Web / Linux 后续从正式 SVG 母版派生并人工复核，不阻塞当前公开预览。

详细平台状态见 [`asset-rollout.md`](asset-rollout.md)。

## 色彩

| 用途 | 色值 |
| --- | --- |
| 深色品牌底 | `#0B1220` |
| 主蓝 | `#2563EB` |
| 光迹青 | `#22D3EE` |
| 辅助紫 | `#8B7CF6` |
| 月白 | `#F5FAFF` |
| 次级文字 | `#94A3B8` |

光效主要用于主视觉、启动页和较大尺寸品牌图形。16–32px 小尺寸图标必须优先保证轮廓和对比度，不依赖模糊光晕维持识别。

## 响应式图标

主 Logo、应用图标和系统小图标属于同一品牌结构，但按尺寸做光学优化：

- 64px 及以上：允许完整光迹、光点与轮廓；
- 32px：减少光晕，保留主弧、光点、主光迹和开放轮廓；
- 16 / 20 / 24px：使用专用简化图，不从 1024px 主图机械缩小；
- Windows 托盘使用小尺寸光学简化 ICO；
- Windows 程序/任务栏使用深色应用图标；
- Android 启动器与自适应前景使用人工检查后提交的静态派生资源。

Apple、Web、Linux 的平台尺寸规则在对应平台正式收口时补充，不把尚未验收的资产写成“已完成”。

## 字标与文案

- 中文优先展示“所行映我”；
- 中英共同出现时使用“所行映我 · Slowlight”；
- 普通产品界面不强制反复显示英文名；
- 英文独立场景使用“Slowlight”；
- Slogan 固定使用“行为留下轨迹，时间让自我显影。”，不要与产品定位文案混用。

## 静态资产原则

品牌图标在设计阶段生成、人工检查并直接提交最终文件。应用构建、CI 和发布流程只消费这些文件，不动态生成或重绘正式 Logo。

禁止：

- 拉伸或压扁标志；
- 擅自改变路径结构；
- 为小尺寸直接缩放主视觉而不做光学适配；
- 增加与品牌无关的复杂阴影、外框或渐变；
- 在低对比背景上使用无法辨识的版本；
- 把 Logo 解释成对用户人格的判断或评分。

## 技术身份边界

当前产品自有技术身份统一使用 **Slowlight / slowlight**：

- Android `namespace` 与 `applicationId`：`site.z7ping.slowlight`；
- Windows 工程名、二进制名、`InternalName`、`OriginalFilename` 与 AppUserModelID：`Slowlight`；
- 用户可见名称：优先“所行映我”，需要完整品牌表达时使用“所行映我 · Slowlight”。
