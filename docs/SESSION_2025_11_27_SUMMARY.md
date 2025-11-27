# セッションサマリー: 2025-11-27

## 概要

ClickHouse を別の Container App として分離し、Langfuse からの接続を確立する作業を実施。
ClickHouse 接続は成功したが、Redis 接続に問題が残っている。

---

## 解決した問題

### 1. ClickHouse TCP + HTTP Ingress 設定

**課題**: Langfuse は ClickHouse に 2 つのプロトコルで接続する必要がある
- `CLICKHOUSE_MIGRATION_URL`: Native TCP (9000) - マイグレーション用
- `CLICKHOUSE_URL`: HTTP (8123) - データアクセス用

**解決策**:
- TCP (9000) を primary ingress として設定（`exposed_port = 9000`）
- HTTP (8123) を `additionalPortMappings` で追加（`azapi_update_resource` 使用）

```hcl
ingress {
  external_enabled = false
  target_port      = 9000
  exposed_port     = 9000
  transport        = "tcp"
}

# azapi_update_resource で additionalPortMappings を追加
additionalPortMappings = [
  {
    external    = false
    targetPort  = 8123
    exposedPort = 8123
  }
]
```

### 2. ClickHouse 認証エラー

**課題**: `Authentication failed: password is incorrect` エラー

**原因**:
1. Langfuse の URL フォーマットが間違っていた（URL に認証情報を埋め込んでいた）
2. ClickHouse の `CLICKHOUSE_PASSWORD` 環境変数は初回起動時のみ有効

**解決策**:
1. URL から認証情報を削除し、別の環境変数で設定
   ```hcl
   CLICKHOUSE_URL=http://<app-name>:8123
   CLICKHOUSE_MIGRATION_URL=clickhouse://<app-name>:9000
   CLICKHOUSE_USER=default
   CLICKHOUSE_PASSWORD=<password>
   ```

2. `users.xml` を `config.d` にマウントして明示的にパスワード設定
   ```xml
   <clickhouse>
     <users>
       <default>
         <password>...</password>
         <networks><ip>::/0</ip></networks>
         <profile>default</profile>
         <quota>default</quota>
         <access_management>1</access_management>
       </default>
     </users>
   </clickhouse>
   ```

**注意**: `users.d` は使用不可（Secret ボリュームは読み取り専用で、ClickHouse entrypoint が書き込もうとして失敗する）

### 3. Application Gateway DNS 解決

**課題**: Application Gateway のバックエンドヘルスが `Unknown` になり、FQDN が解決できない

**解決策**: Container Apps Environment 用の Private DNS Zone を追加

```hcl
resource "azurerm_private_dns_zone" "container_apps" {
  name                = azapi_resource.container_app_environment.output.properties.defaultDomain
  resource_group_name = azurerm_resource_group.this.name
}

resource "azurerm_private_dns_a_record" "container_apps_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.container_apps.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azapi_resource.container_app_environment.output.properties.staticIp]
}
```

### 4. Redis TLS 証明書エラー

**課題**: `ERR_TLS_CERT_ALTNAME_INVALID: Hostname/IP does not match certificate's altnames`

**原因**: Private Endpoint の IP アドレスが Redis の TLS 証明書の SAN に含まれていない

**解決策**: Langfuse 専用の環境変数で証明書検証を無効化

```hcl
REDIS_TLS_ENABLED=true
REDIS_TLS_REJECT_UNAUTHORIZED=false
REDIS_TLS_CHECK_SERVER_IDENTITY=false
```

---

## 未解決の問題

### 1. Redis 接続エラー (EPIPE / ECONNRESET)

**現象**:
- TLS ハンドシェイクは成功
- 接続後すぐに `write EPIPE` または `read ECONNRESET` エラー
- セッション管理ができずログインが完了しない

**試した設定**:
- `REDIS_TLS_ENABLED=true`
- `REDIS_TLS_REJECT_UNAUTHORIZED=false`
- `REDIS_TLS_CHECK_SERVER_IDENTITY=false`
- `REDIS_CLUSTER_ENABLED=true` + `REDIS_CLUSTER_NODES`
- `NODE_TLS_REJECT_UNAUTHORIZED=0`
- `REDIS_CONNECTION_STRING` with `rediss://` prefix

**調査ポイント**:
- Azure Managed Redis の `clustering_policy = "OSSCluster"` と Langfuse の互換性
- サイドカー時代の Redis 設定との差分
- Azure Portal で Redis の接続ログ確認
- Private Endpoint 経由の接続の問題

### 2. Terraform 差分問題

**現象**: `azapi_update_resource.clickhouse_volumes` で常に差分が出る

**原因**:
- `azurerm_container_app` と `azapi_update_resource` の二重管理
- 以前追加した `clickhouse-users` ボリュームが state に残っている

**解決策候補**:
```bash
# 両方を taint して再作成
terraform taint azurerm_container_app.clickhouse
terraform taint azapi_update_resource.clickhouse_volumes
terraform apply

# または state をリセット
terraform state rm azapi_update_resource.clickhouse_volumes
terraform apply
```

---

## 現在の設定

### Redis 環境変数 (container_apps.tf)

```hcl
REDIS_HOST = local.redis_host
REDIS_PORT = local.redis_port
REDIS_AUTH = (secret)
REDIS_TLS_ENABLED = true
REDIS_TLS_REJECT_UNAUTHORIZED = false
REDIS_TLS_CHECK_SERVER_IDENTITY = false
REDIS_CLUSTER_ENABLED = true
REDIS_CLUSTER_NODES = ${local.redis_host}:${local.redis_port}
```

### ClickHouse 環境変数 (container_apps.tf)

```hcl
CLICKHOUSE_URL = http://${azurerm_container_app.clickhouse.name}:8123
CLICKHOUSE_MIGRATION_URL = clickhouse://${azurerm_container_app.clickhouse.name}:9000
CLICKHOUSE_USER = default
CLICKHOUSE_PASSWORD = (secret)
```

---

## 参考リンク

- [Langfuse Cache Configuration](https://langfuse.com/self-hosting/deployment/infrastructure/cache)
- [Langfuse ClickHouse Configuration](https://langfuse.com/self-hosting/deployment/infrastructure/clickhouse)
- [Azure Container Apps TCP Ingress](https://learn.microsoft.com/en-us/azure/container-apps/ingress-how-to)

---

## 次のステップ

1. Redis 接続問題の調査
   - Azure Portal で Redis のメトリクス/ログを確認
   - サイドカー時代の設定と比較
   - `OSSCluster` vs 通常の Redis 設定を検討

2. Terraform 差分問題の解決
   - リソースの再作成または state の修正

3. 動作確認
   - ログインテスト
   - トレースデータの投入テスト
