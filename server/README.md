# Slowlight Server

Slowlight Server 用于需要账号、多设备同步和服务端集成能力的场景。只使用 Local Data 时不需要部署 Server。

## 依赖

- Go 1.23
- PostgreSQL 16（兼容性基线）

## 从源码运行

在仓库根目录复制环境变量模板：

```bash
cp .env.example server/.env
cd server
go mod download
go run ./cmd
```

至少需要正确配置：

- `DATABASE_URL`
- `JWT_SECRET`
- `CONFIG_ENCRYPTION_KEY`

生产环境必须为 JWT 和配置加密使用独立的高强度随机值，不要沿用 `.env.example` 中的占位值。

默认端口为 `8080`，健康检查：

```text
GET /health
```

## GitHub 一键登录（可选）

Slowlight 复用现有 Go/Gin + PostgreSQL 用户体系，通过 GitHub OAuth App 登录，Windows 和 Android 共用浏览器授权。不需要另一个登录服务。

1. 在 [GitHub Developer Settings](https://github.com/settings/developers) → OAuth Apps 新建应用，名称可填写 `Slowlight`。
2. Homepage URL 填自己的官网或项目主页。
3. Authorization callback URL 填 **精确** 的 `https://你的域名/api/auth/github/callback`，不要开启通配符匹配。
4. 服务端环境配置以下变量，注意 Client Secret **只在服务端保存**，不要写进 Flutter、公开仓库、PR 或聊天。

```text
GITHUB_OAUTH_CLIENT_ID=<GitHub OAuth App 的 Client ID>
GITHUB_OAUTH_CLIENT_SECRET=<GitHub OAuth App 的 Client Secret>
GITHUB_OAUTH_CALLBACK_URL=https://你的域名/api/auth/github/callback
```

Docker Compose 已透传这三个变量；重建 Go 服务端后生效。新安装客户端仍需 `SERVER_URL=https://你的域名/api` 指向同一服务端。反向代理需允许回调路径，并为公网启用 HTTPS。

- `POST /api/auth/github/start` 发起登录；`GET /api/auth/github/callback` 接收 GitHub 回调；`POST /api/auth/github/poll` 一次性领取 Slowlight JWT。
- 客户端在 `start` / `link/start` 的 JSON 请求体中可传 `{"platform":"android"}`。Android 首选系统安全浏览器标签（Custom Tabs，允许复用浏览器登录态），不支持时回退系统默认浏览器；Windows 使用默认浏览器。
- GitHub 并未保证 OAuth 授权页由 GitHub 手机 App 接管，**不得**拼造 GitHub App URI 或把已安装 GitHub App 作为登录前提。
- Android 成功回调会尝试打开 `slowlight://oauth-complete` 唤醒 Slowlight；浏览器禁止自动打开时可点击「返回所行映我」。Windows 回调页也提供该按钮：**安装版**通过 Inno Setup 注册当前用户的 `slowlight://` 协议，点击后优先恢复同一安装目录下已经运行的客户端窗口（包括托盘隐藏状态），不会另开第二个会话；便携版或仅 `flutter run -d windows` 未注册协议时，须手动切回应用。浏览器可能要求确认“打开所行映我”。回跳 URI **不包含** `code`、`state`、JWT、轮询凭据；只是返回应用，不代表登录完成，实际结果仍由客户端安全轮询确认。若 Windows 客户端在授权期间已完全退出，重新打开并不能自动恢复旧授权会话，需要重新发起登录。
- 注意 Android Manifest 已禁用 Flutter 自行解析此唤醒 URI，以防 OAuth 回调被解释成应用内页面路由；如将来引入其他 App Links，需单独评估路由管理。
- 已登录云端用户可以在「设置 → 账号」显式绑定 GitHub，对应服务端受 JWT 保护的 `POST /api/auth/github/link/start`。**不会通过同邮箱自动绑定或合并账号**。
- 新 GitHub 用户创建独立的 Slowlight 账号。内部账号以 GitHub 不变的数字 ID 为锚点，首次注册使用占位邮箱，不向 GitHub 索取私人邮箱/仓库权限；常规密码无法登录该账号。
- 授权状态和轮询凭据仅保留 SHA-256 摘要；使用 `state`、PKCE (S256)、十分钟有效期和一次性领取。GitHub Access Token 不写入数据库。
- 未配置上述参数时传统账号密码登录与本地模式仍可使用，GitHub 登录入口会提示不可用。
- 该改动不迁移、不上传 Local SQLite，也不改变按用户隔离的 Cloud Cache。
- 请限制 Nginx/Caddy 访问日志中回调 `code`、`state` 等参数的保存，设置 OAuth 登录入口的反向代理限流。

上线前至少手工验证：Windows/Android 各完成一次真实授权；GitHub 拒绝/取消、断网、重复回调、过期、旧账号绑定、跨设备同账号查看数据。客户端现有 JWT 有效期仍是 7 天，到期需要重新登录；此功能未引入刷新令牌。

## Docker Compose

仓库提供 `Dockerfile` 与 `docker-compose.yml` 作为最小自托管起点。Compose 不包含项目维护者的部署地址或数据库账号，启动时必须由部署者提供自己的 Secret。

在 `server/` 目录执行前，先通过当前 Shell 或本地未提交的 `.env` 设置：

```text
SLOWLIGHT_DB_PASSWORD=<随机数据库密码>
JWT_SECRET=<长随机 JWT 密钥>
CONFIG_ENCRYPTION_KEY=<至少 32 字符的独立随机密钥>
CORS_ALLOW_ORIGINS=<允许访问的前端 Origin，可选>
```

然后：

```bash
cd server
docker compose up -d --build
```

默认仅将后端映射到宿主机 `127.0.0.1:8080`，PostgreSQL 只映射到 `127.0.0.1:5432`。远程访问必须由部署者显式配置 HTTPS 反向代理。

> `docker-compose.yml` 只解决最小运行依赖。正式互联网部署仍应自行配置 TLS、反向代理、数据库备份、防火墙和访问控制。

## 运行 Release 二进制

GitHub Release 中的 Linux Server 包计划包含：

- `slowlight-server-linux-<arch>`
- `.env.example`
- `README.md`
- 项目许可证（许可证确定并加入仓库后）

解压后将 `.env.example` 复制为 `.env`，填写真实配置，然后在该目录启动二进制。

## 云端部署与恢复基线

- 客户端使用 `--dart-define=SERVER_URL=https://<你的域名>/api` 注入云端接口，正式构建还应启用 `--dart-define=SLOWLIGHT_REQUIRE_HTTPS=true`；开发/内网自托管保留 localhost HTTP 能力。
- 服务端容器只绑定本机环回端口；公网入口由 Nginx/Caddy 等成熟 TLS 反向代理承担，不在仓库提交域名、证书或密钥。
- 开放给公网前配置数据库异地加密备份、保留周期和备份恢复监控；不要只保留唯一云端数据库。
- 账号 JWT 当前有效期为七天，到期要求重新登录；离线待同步队列按账号隔离，不得因为过期清空云端缓存。
- 恢复演练：先备份当前数据库，再在独立的临时 PostgreSQL 库执行恢复并检查表、账号、任务、习惯、专注、反思、同步墓碑及迁移报告；不要先在生产数据库运行带 `--clean` 的恢复命令。

使用现有 Compose PostgreSQL 容器创建归档（备份文件由操作者妥善加密并存放在服务器之外）：

```bash
cd server
docker compose exec -T db pg_dump -U slowlight -Fc slowlight > slowlight-backup.dump
pg_restore --list slowlight-backup.dump
```

`pg_restore --list` 只检查归档内容，**不等于完整恢复验证**。建议定期在隔离环境实际执行恢复并使用 `go test ./...` 与手工多设备场景核查。
升级前保持 PostgreSQL 备份；Cloud-first 不改变 Local Data 用户手工导出/迁移的权利。

## 数据与升级

当前项目仍处于公开预览阶段。升级服务端之前建议备份 PostgreSQL，并先阅读 [`../CHANGELOG.md`](../CHANGELOG.md) 与 [`docs/migration-guide.md`](docs/migration-guide.md)。

涉及同步、删除、迁移或数据库结构的版本升级，应先在非唯一数据副本上验证，再用于重要数据。

## 安全

不要提交：

- `.env`
- 数据库真实 DSN / 密码
- JWT Secret
- `CONFIG_ENCRYPTION_KEY`
- 飞书等第三方 App Secret
- 私钥、keystore 或凭据文件

完整规则见 [`../SECURITY.md`](../SECURITY.md)。
