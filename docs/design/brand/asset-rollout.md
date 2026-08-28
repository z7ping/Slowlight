# Slowlight 品牌资产状态

当前品牌名：**所行映我 · Slowlight**
正式 Slogan：**行为留下轨迹，时间让自我显影。**

本文件记录正式品牌资产在各平台的当前落地状态。品牌设计本身以 `docs/design/brand/README.md` 和 SVG 母版为准。

## 平台优先级

当前正式验收平台为 **Android + Windows**：

1. Android + Windows：正式图标、用户可见品牌和平台身份优先保证可用；
2. 品牌文档与 SVG 母版：必须与正式方案同步，是后续平台资产的事实源；
3. iOS / macOS / Web / Linux：不阻塞当前公开预览，后续从 SVG 母版生成并人工复核静态资产。

Logo 已定稿为“光迹成形”，各平台只做尺寸、留白和系统规范上的光学适配，不演化另一套 Logo。

## 正式品牌源资产

- `docs/design/brand/slowlight-logo-mark.svg`：正式 Logo 几何母版；
- `docs/design/brand/slowlight-logo-horizontal.svg`：正式横版品牌组合；
- `assets/brand/slowlight/masters/slowlight-app-icon-dark.svg`：正式深色应用图标母版；
- `assets/brand/slowlight/masters/slowlight-app-icon-light.svg`：浅色备份母版；
- `assets/brand/slowlight/masters/slowlight-app-icon-monochrome-dark.svg`：单色深色备份母版；
- `assets/brand/slowlight/masters/slowlight-app-icon-monochrome-light.svg`：单色浅色备份母版。

PNG / ICO 等平台文件属于静态交付资产，不反向作为 Logo 几何事实源。

## Android

当前正式状态：

- 应用显示名：`所行映我`；
- `namespace` / `applicationId`：`site.z7ping.slowlight`；
- 启动器普通图标、圆形图标和自适应图标均使用 Slowlight 正式资产；
- Android 13+ 单色自适应图标使用同一“光迹成形”几何结构；
- 自适应图标深色背景为 `#0B1220`；
- mdpi / hdpi / xhdpi / xxhdpi / xxxhdpi 静态资源已落地；
- 官方 Preview / Release 构建使用固定发行签名；开发者本地未配置发行密钥时仍可进行开发构建。

关键文件：

- `client/android/app/src/main/AndroidManifest.xml`
- `client/android/app/build.gradle.kts`
- `client/android/app/src/main/res/mipmap-*`
- `client/android/app/src/main/res/drawable/ic_launcher_monochrome.xml`

## Windows

当前正式状态：

- 工程与二进制身份：`Slowlight`；
- 用户可见标题：`所行映我 · Slowlight` / `所行映我`；
- AppUserModelID：`Slowlight`；
- EXE、窗口和任务栏使用正式深色应用图标；
- 托盘使用透明背景的小尺寸简化图标；
- 程序内部 Logo 使用透明高清 Logo mark。

关键文件：

- `client/windows/CMakeLists.txt`
- `client/windows/runner/Runner.rc`
- `client/windows/runner/resources/app_icon.ico`
- `client/windows/runner/main.cpp`
- `client/windows/runner/app_identity.cpp`
- `client/assets/app_icon.ico`
- `client/assets/slowlight_logo.png`

## 后续平台

### iOS

后续从正式 SVG 母版生成并复核全尺寸 AppIcon、原生环境显示和发行元数据。

### macOS

后续生成并复核 AppIcon、菜单栏/状态栏图标与原生发行元数据。

### Web

后续生成并复核 favicon、PWA 普通图标与 maskable 图标。

### Linux

后续生成并复核应用图标、桌面条目和托盘图标。

这些平台暂不要求提前保存全部尺寸 PNG；正式收口时必须从确认过的 SVG 母版派生并人工检查。

## 静态资产规则

品牌图标必须在设计阶段生成、人工检查并直接提交最终静态文件。CI、Flutter 构建脚本和平台构建脚本只消费资产，不动态生成、重绘或重新缩放正式 Logo。

## 技术身份

当前产品自有技术身份统一使用 **Slowlight / slowlight**：

- Android：`site.z7ping.slowlight`；
- Windows：工程、二进制、版本资源和 AppUserModelID 使用 `Slowlight`；
- 用户可见主品牌：`所行映我` / `所行映我 · Slowlight`。

## 验证范围

当前品牌发布验收重点：

1. 核对 SVG 母版与 Android / Windows 实际资产一致；
2. 检查 Android / Windows 用户可见品牌与技术身份；
3. 验证 Windows 程序、任务栏、托盘和开始菜单显示；
4. 验证 Android 启动器、自适应图标和覆盖升级；
5. 确认后续平台仍可从正式 SVG 母版继续派生。
