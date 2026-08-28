# Slowlight 构建脚本

## 平台构建矩阵

| 脚本 | 平台 | 运行环境 | 状态 |
|------|------|----------|------|
| `build_android.sh` | Android APK | Flutter + Android SDK | 可用 |
| `build_linux.sh` | Linux 桌面 | Flutter + GTK3 | 可用 |
| `build_windows.ps1` | Windows | PowerShell 7 + Flutter + Visual Studio | 可用 |
| `build_windows.sh` | Windows 兼容入口 | 能调用 `pwsh.exe` 的 Bash | 可选 |
| `build_macos.sh` | macOS | Flutter + Xcode | 可用 |
| `build_ios.sh` | iOS | Flutter + Xcode | 可用 |
| `release.sh` | GitHub Release 制品上传 | GitHub CLI | 可选 |

## 快速开始

```bash
# 1. 构建
cd client
SERVER_URL=https://slowlight.example.com/api ./shell/build_android.sh v0.2.0

# Windows 请使用 PowerShell 7
pwsh -File .\shell\build_windows.ps1 -Version 0.2.0 -ServerUrl https://slowlight.example.com/api

# 2. 可选：向已存在的 GitHub tag 上传制品
gh auth login
./shell/release.sh build/app/outputs/flutter-apk/app-release.apk v0.2.0
```

## 服务器地址注入

Android、Linux 和 Windows 构建脚本通过 `SERVER_URL` 注入 API 地址；未设置时使用 `http://localhost:8080/api`，适合本地或自托管环境。Windows PowerShell 脚本也可以通过 `-ServerUrl` 显式传入。仓库不保存官方环境或贡献者私有环境的固定地址。

```bash
SERVER_URL=https://slowlight.example.com/api ./shell/build_android.sh v0.2.0
```

Dart 端通过 `String.fromEnvironment('SERVER_URL')` 读取。正式预览包优先由 `.github/workflows/` 中的 GitHub Actions 构建和发布，服务地址放在 Repository Variables 中，签名材料放在 Repository Secrets 中。

所有脚本都会在构建前检查必要命令和宿主平台，并在结束前确认预期产物确实存在。版本参数只用于本地制品文件名；应用内部版本仍以 `client/pubspec.yaml` 为准。

## 发布边界

`release.sh` 不创建或删除 tag，也不会删除已有 Release。它只针对已经推送到 GitHub 的 tag 创建预发布版本或补充上传制品。默认使用当前 Git 仓库；需要指定其它仓库时设置 `GH_REPO=owner/repository`。
