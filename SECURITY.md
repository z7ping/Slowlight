# 安全策略

Slowlight 涉及本地数据、云端同步、认证凭据以及用户自有 AI API Key。安全问题应优先避免公开披露敏感细节。

## 报告漏洞

仓库公开后，优先通过 GitHub 仓库 **Security** 页面提供的私密漏洞报告能力提交安全问题（启用后使用 “Report a vulnerability”）。

如果私密报告入口暂未启用，请不要在公开 Issue、Pull Request、讨论区或日志中粘贴：

- API Key、访问令牌、JWT Secret；
- 数据库账号、密码或完整 DSN；
- 私钥、签名文件、证书密码；
- 包含真实用户数据的数据库、日志或备份；
- 可直接利用且尚未修复的敏感漏洞细节。

普通非敏感缺陷可以正常提交公开 Issue。

## 范围

优先关注：

- 认证、授权和用户隔离；
- Local Data / Cloud Data 数据泄露或越权；
- 同步导致的数据错误删除、覆盖或跨用户污染；
- AI Provider / BYOK 密钥存储与传输；
- Webhook、CalDAV、飞书等外部连接能力；
- 桌面端、本地数据库、备份和日志中的敏感数据；
- CI/CD、发布包和签名链中的凭据泄露。

## 敏感信息提交门禁

Slowlight 使用三层防护，任何一层发现真实敏感信息都应停止提交或合并。

### 1. 本地提交前检查

仓库提供 `.githooks/pre-commit`。首次 clone 后可启用：

```bash
git config core.hooksPath .githooks
```

本地 Hook **不要求 Python**。

- 如果本机安装了 Gitleaks，会对暂存内容执行敏感信息扫描；
- 如果没有安装 Gitleaks，只给出提示，不阻断本地提交；
- 远端硬门禁以 GitHub CI 实际成功执行、配置为 Required status check，并结合 Push Protection 为准。

本地执行命令：

```bash
gitleaks git --pre-commit --staged --redact --config=.gitleaks.toml --no-banner
```

本地 Hook 只是提前反馈，不能替代 GitHub 门禁。

### 2. GitHub PR / main / Release 门禁

`.github/workflows/secret-guard.yml` 会在以下场景运行：

- 指向 `main` 的 Pull Request；
- `main` 新提交；
- 手动执行；
- Release 工作流复用安全门禁时。

门禁针对**当前检出的公开工作树**执行：

1. Slowlight 自定义敏感文件和私有环境痕迹检查；
2. Gitleaks 默认规则；
3. `.gitleaks.toml` 中 Slowlight 专用规则。

CI 中的 `scripts/security/check_sensitive_files.py` 由 GitHub Runner 执行，开发者本地不需要为了普通提交额外安装 Python。

重点阻止：

- `.env`、Android keystore、P12/PFX、私钥和凭据文件；
- `JWT_SECRET`、`CONFIG_ENCRYPTION_KEY`；
- Android 签名密码和 keystore Base64；
- 飞书 App Secret；
- 带真实密码的数据库 DSN；
- Bearer Token、常见云服务/API Token、私钥内容；
- RFC1918 私有网段、个人用户目录绝对路径和内部专用主机名；
- 源码中硬编码的远程 `SERVER_URL`；
- `String.fromEnvironment` 等客户端构建配置中为 `SERVER_*_URL` 设置的非本地默认地址。

`.env.example`、CI 测试占位值和 `${ENV_VAR}` / GitHub Actions 表达式可以保留，但不得因为是示例或变量引用就把真实凭据写入仓库。

仓库建立后，应先确认 `Sensitive information guard` 产生了真实 Step 执行结果并成功，再把它配置为 `main` 分支 Ruleset / Branch protection 的 **Required status check**。工作流文件存在本身不能证明远端门禁已经生效。

### 3. GitHub 原生 Secret Scanning / Push Protection

公开 `z7ping/Slowlight` 仓库应在 GitHub 仓库的代码安全设置中启用 Secret Scanning 与 Push Protection。

GitHub 原生 Push Protection 负责在凭据真正进入远端历史前阻断 GitHub 已识别的 Secret；仓库内 Gitleaks 与自定义检查负责扫描当前工作树并补充项目特有风险。

这两个边界互补：仓库内检查覆盖当前工作树与项目特有规则；后续新增 Secret 应优先在进入远端历史之前被 Push Protection 阻断。

### Repository Secrets / Variables 边界

以下内容必须放 GitHub **Secrets**，不得进入源码：

```text
SLOWLIGHT_ANDROID_KEYSTORE_BASE64
SLOWLIGHT_ANDROID_KEY_ALIAS
SLOWLIGHT_ANDROID_STORE_PASSWORD
SLOWLIGHT_ANDROID_KEY_PASSWORD
JWT_SECRET
CONFIG_ENCRYPTION_KEY
数据库生产凭据
飞书 App Secret
AI Provider API Key
```

非敏感但与官方预览环境有关的值，例如预览服务地址，使用 GitHub **Repository Variables**：

```text
SLOWLIGHT_DOGFOOD_SERVER_URL
```

普通源码和社区自构建未配置该变量时应保持 localhost / 自托管语义。

## 凭据处理原则

仓库中的示例配置只能使用占位值或环境变量引用。任何曾经进入 Git 历史的真实凭据都应视为已经暴露：

1. 立即轮换或撤销；
2. 判断影响范围；
3. 再评估是否需要清理 Git 历史；
4. 不把扫描报告中的真实 Secret 再次提交或粘贴到公开 Issue / PR。

单纯删除当前文件不能使历史凭据失效。
