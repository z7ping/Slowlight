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
