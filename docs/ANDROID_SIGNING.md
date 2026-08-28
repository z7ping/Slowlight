# Android 预览与发行签名

Slowlight Android 官方预览包和后续正式发行包必须使用同一套长期固定签名，确保已安装应用可以原地覆盖升级并保留本地数据。

## 原则

- `site.z7ping.slowlight` 的官方预览/发行构建必须使用固定 keystore。
- keystore、密码、私钥不得提交到 Git 仓库。
- GitHub Actions 通过 Repository Secrets 临时恢复 keystore。
- 本地普通 `flutter build apk --release` 在未配置发行签名环境变量时仍允许使用 debug signing，方便社区自构建；这种包不属于 Slowlight 官方预览/发行包。
- 官方 GitHub `Preview Packages` 与 Tag Release 在缺少签名 Secret 时必须失败，不允许悄悄退回 debug signing。

## 生成 keystore

在安装了 JDK 的可信本机执行：

```bash
keytool -genkeypair -v -keystore slowlight-release.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias slowlight
```

请长期保存：

- `slowlight-release.jks`
- alias（建议 `slowlight`）
- keystore password
- key password

至少保留两份加密备份。丢失发行私钥会导致现有 Android 安装无法继续正常覆盖升级。

## 转为 Base64

PowerShell：

```powershell
$jks = Resolve-Path ".\slowlight-release.jks"

[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes($jks.Path)
) | Set-Content ".\slowlight-release-base64.txt"
```

Linux/macOS：

```bash
base64 -w 0 slowlight-release.jks > slowlight-release-base64.txt
```

macOS 若 `base64` 不支持 `-w`：

```bash
base64 < slowlight-release.jks | tr -d '\n' > slowlight-release-base64.txt
```

`slowlight-release.jks` 和 `slowlight-release-base64.txt` 都属于敏感本地文件；仓库 `.gitignore` 已显式忽略它们。

## GitHub Repository Secrets

Settings → Secrets and variables → Actions → Secrets → New repository secret。

在仓库 Actions Secrets 中配置：

```text
SLOWLIGHT_ANDROID_KEYSTORE_BASE64
SLOWLIGHT_ANDROID_KEY_ALIAS
SLOWLIGHT_ANDROID_STORE_PASSWORD
SLOWLIGHT_ANDROID_KEY_PASSWORD
```

其中：

- `SLOWLIGHT_ANDROID_KEYSTORE_BASE64`：`slowlight-release-base64.txt` 的完整内容。
- `SLOWLIGHT_ANDROID_KEY_ALIAS`：例如 `slowlight`。
- 其余两个分别为 keystore 密码和 key 密码。

不要把 Secret 值写入 Issue、PR、Actions 日志、README 或其它仓库文档。

## GitHub Actions 行为

`.github/workflows/dogfood.yml` 会：

1. 强制检查四个签名 Secret；
2. 在 Runner 上临时恢复 `client/android/app/slowlight-release.jks`；
3. 通过环境变量把签名信息传给 Gradle；
4. 构建固定签名的 release APK；
5. Runner 生命周期结束后临时文件随环境销毁。

`dogfood-pr.yml` 和 `release.yml` 使用 `secrets: inherit` 将 Repository Secrets 传入可复用预览构建工作流。

## 本地使用固定签名（可选）

如果需要在本地生成与官方构建同签名的 APK，可在当前 shell 设置：

```text
SLOWLIGHT_ANDROID_KEYSTORE_PATH=slowlight-release.jks
SLOWLIGHT_ANDROID_KEY_ALIAS=slowlight
SLOWLIGHT_ANDROID_STORE_PASSWORD=...
SLOWLIGHT_ANDROID_KEY_PASSWORD=...
```

`SLOWLIGHT_ANDROID_KEYSTORE_PATH` 相对于 `client/android/app/`。

## 首次预览验收

第一次使用固定签名后，至少验证一次：

1. 安装固定签名的候选 APK；
2. 创建若干本地任务、习惯和 Reflection 数据；
3. 使用同一 keystore 构建下一版 APK；
4. 直接覆盖安装，不卸载旧版；
5. 确认 Android 接受升级；
6. 确认本地数据仍完整存在。

只有完成覆盖升级验证后，Android 固定签名才算真正通过发行门禁。
