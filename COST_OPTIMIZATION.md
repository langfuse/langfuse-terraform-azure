# コスト最適化ガイド

このドキュメントでは、Langfuse on Azure Container Appsのコスト削減方法を説明します。

## 現在の構成とコスト概算

### 開発環境（最小構成）
| リソース | 月額概算 | 備考 |
|---------|---------|------|
| Container Apps | $5-20 | CPU 1.0, Memory 2Gi, min 1 replica |
| PostgreSQL Flexible Server | $10-30 | B_Standard_B1ms |
| Redis Cache (Basic C0) | $15 | 最小構成 |
| Storage Account | $5 | Blob Storage GRS |
| Log Analytics | $5 | 30日保持 |
| NAT Gateway | $10 | データ転送料別 |
| Private Endpoints (4個) | $4 | $1/個 |
| DNS Zone | $0.50 | 100万クエリまで |
| Key Vault | $0.03 | 証明書保存 |
| **合計** | **$54.53-85.53** | |

### 本番環境
| リソース | 月額概算 | 備考 |
|---------|---------|------|
| Container Apps | $50-200 | CPU 2.0, Memory 4Gi, min 2 replicas |
| PostgreSQL Flexible Server (HA) | $100-300 | GP_Standard_D4s_v3 + HA |
| Redis Cache (Standard C1) | $50-100 | 推奨構成 |
| Storage Account | $20 | Blob Storage GRS |
| Log Analytics | $20-50 | 大量ログ |
| NAT Gateway | $30 | データ転送料別 |
| Private Endpoints (4個) | $4 | $1/個 |
| DNS Zone | $0.50 | 100万クエリまで |
| Key Vault | $0.03 | 証明書保存 |
| DDoS Protection（オプション） | $2,944 | 非推奨 |
| **合計** | **$274.53-704.53** | DDoS除く |

---

## コスト削減案

### 🥇 優先度: 高（大きなコスト削減）

#### 1. NAT Gatewayの削除（月額 $10-30削減）

**現状**: NAT Gatewayを使用してアウトバウンド通信を行っている

**代替案**: Container Appsの環境で `workloadProfile` を `Consumption` プランのまま使用し、必要に応じてアウトバウンドIPを固定

**実装方法**:

`network.tf` から以下を削除またはコメントアウト：
```hcl
# resource "azurerm_public_ip" "nat_gateway" { ... }
# resource "azurerm_nat_gateway" "this" { ... }
# resource "azurerm_nat_gateway_public_ip_association" "this" { ... }
# resource "azurerm_subnet_nat_gateway_association" "container_apps" { ... }
```

**影響**:
- ✅ 月額 $10-30 削減
- ✅ アウトバウンド通信は引き続き可能
- ⚠️ アウトバウンドIPが固定されない（ホワイトリスト登録が必要な場合は問題）
- ⚠️ 外部サービスへの接続制御が必要な場合は不適

**推奨**: 開発環境では削除、本番環境では要件次第

---

#### 2. Redisの代替案（月額 $15-100削減）

**現状**: Azure Cache for Redis (Basic C0 = $15/月、Standard C1 = $50/月)

**代替案A: Dragonfly on Container Apps**

Dragonflyは高性能でRedis互換のメモリストア（よりコスト効率的）

新規ファイル `dragonfly.tf`:
```hcl
resource "azurerm_container_app" "dragonfly" {
  name                         = "dragonfly"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    container {
      name   = "dragonfly"
      image  = "docker.dragonflydb.io/dragonflydb/dragonfly:latest"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "DFLY_requirepass"
        secret_name = "dragonfly-password"
      }
    }

    min_replicas = 1
    max_replicas = 1
  }

  secret {
    name  = "dragonfly-password"
    value = random_password.dragonfly_password.result
  }

  ingress {
    external_enabled = false
    target_port      = 6379
    transport        = "tcp"
  }
}

resource "random_password" "dragonfly_password" {
  length  = 32
  special = false
}
```

**コスト**: Container Apps料金のみ（約 $3-5/月）

**代替案B: Valkey (Redis fork)**

Redis 7.2.4のフォーク、完全互換

```hcl
resource "azurerm_container_app" "valkey" {
  # 同様の構成
  template {
    container {
      image = "valkey/valkey:7.2"
      # ...
    }
  }
}
```

**代替案C: Redisをスキップ**

Langfuseは一部の機能でRedisをオプションとして扱える可能性があります。
ドキュメントを確認して、Redisなしで動作するか検証する価値があります。

**推奨**: Dragonfly on Container Apps（月額 $12-95削減）

---

#### 3. Private Endpointの削減（月額 $2-4削減）

**現状**: 4つのPrivate Endpoint（PostgreSQL, Redis, Storage, Key Vault）

**代替案**: 開発環境ではPublicアクセスを許可（ファイアウォールルールで制限）

**実装方法**:

`postgres.tf`:
```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  # ...
  public_network_access_enabled = var.enable_public_access  # falseからtrueに

  # ファイアウォールルールで制限
  dynamic "firewall_rule" {
    for_each = var.enable_public_access ? var.allowed_ip_ranges : []
    content {
      name             = "allow-${firewall_rule.key}"
      start_ip_address = firewall_rule.value.start
      end_ip_address   = firewall_rule.value.end
    }
  }
}

# Private Endpointをコメントアウト
# resource "azurerm_private_endpoint" "postgres" { ... }
```

**影響**:
- ✅ 月額 $4 削減（Private Endpoint x 4）
- ⚠️ セキュリティが低下（本番環境では非推奨）
- ✅ ファイアウォールルールで一定の制御は可能

**推奨**: 開発環境のみ適用

---

### 🥈 優先度: 中（中程度のコスト削減）

#### 4. PostgreSQLのサーバーレス化（月額 $5-20削減）

**現状**: Flexible Server (B_Standard_B1ms = 固定料金)

**代替案**: Azure SQL Database Serverless

Langfuseが必要とするのはPostgreSQL互換DBですが、Azure SQL DatabaseのServerlessプランを検討する価値があります。ただし、LangfuseはPostgreSQL前提のため、**PostgreSQL互換性の検証が必須**です。

別の選択肢として、**Supabase**や**Neon**などの外部PostgreSQLサービス（Serverless）を使用：

**Neon (Serverless Postgres)**:
- 無料枠: 0.5GB、月間191時間
- 有料: $19/月から（Autoscaling、Branching機能付き）

**Supabase**:
- 無料枠: 500MB、2 CPUまで
- 有料: $25/月から

**実装**: Terraformの外で管理し、`DATABASE_URL`のみ指定

**推奨**: 小規模プロジェクトや開発環境では検討の価値あり

---

#### 5. Log Analyticsの保持期間短縮（月額 $2-10削減）

**現状**: 30日保持

**代替案**: 7日保持に変更

`log_analytics.tf`:
```hcl
resource "azurerm_log_analytics_workspace" "this" {
  # ...
  retention_in_days   = 7  # 30から7に変更
}
```

**影響**:
- ✅ ログ保存コストが削減
- ⚠️ 過去のログが7日間しか見られない

**推奨**: 開発環境では7日、本番環境では30-90日

---

#### 6. Storageの冗長性変更（月額 $2-10削減）

**現状**: GRS（地理冗長ストレージ）

**代替案**: LRS（ローカル冗長ストレージ）

`storage.tf`:
```hcl
resource "azurerm_storage_account" "this" {
  # ...
  account_replication_type = var.storage_replication_type  # "GRS" → "LRS"
}
```

**影響**:
- ✅ ストレージコストが約50%削減
- ⚠️ リージョン障害時のデータ損失リスク

**推奨**: 開発環境ではLRS、本番環境ではGRS

---

### 🥉 優先度: 低（小規模な削減）

#### 7. DNSゾーンの削除（月額 $0.50削減）

**代替案**: 外部DNSサービス（Cloudflare無料プラン等）を使用

**影響**:
- ✅ わずかなコスト削減
- ⚠️ Azure外でDNS管理が必要

**推奨**: 削減効果が小さいため、通常は不要

---

#### 8. Key Vaultの削除（月額 $0.03削減）

**代替案**: Let's EncryptやContainer Appsマネージド証明書を使用

**影響**:
- ✅ ほぼコストなし
- ⚠️ 証明書管理が煩雑

**推奨**: 削減効果が極小のため、通常は不要

---

## コスト削減シナリオ

### シナリオ1: 超低コスト開発環境（月額 $25-40）

**変更内容**:
- ✅ NAT Gateway削除
- ✅ Redis → Dragonfly on Container Apps
- ✅ Private Endpoint削除（Public + Firewall）
- ✅ PostgreSQL: 最小SKU (B_Standard_B1ms)
- ✅ Storage: LRS
- ✅ Log Analytics: 7日保持
- ✅ Container Apps: min 0 replicas（スケールtoゼロ）
- ✅ DDoS Protection無効

**月額コスト**:
- Container Apps: $3-10（スケールtoゼロ）
- PostgreSQL: $10
- Dragonfly: $3-5
- Storage: $2-3
- Log Analytics: $2-3
- DNS: $0.50
- Key Vault: $0.03
- **合計: $20.53-31.53**

**トレードオフ**:
- セキュリティ低下（開発環境のみ推奨）
- 固定IPなし
- リージョン冗長性なし

---

### シナリオ2: バランス型開発環境（月額 $40-60）

**変更内容**:
- ✅ NAT Gateway削除
- ✅ Redis → Dragonfly on Container Apps
- ✅ Private Endpoint保持（セキュリティ維持）
- ✅ PostgreSQL: B_Standard_B1ms
- ✅ Storage: LRS
- ✅ Log Analytics: 30日保持

**月額コスト**: $40-60

**推奨**: セキュリティとコストのバランスが良い

---

### シナリオ3: コスト最適化本番環境（月額 $150-250）

**変更内容**:
- ✅ NAT Gateway保持（固定IP必要）
- ✅ Redis → Dragonfly or Redis Standard C1
- ✅ Private Endpoint保持
- ✅ PostgreSQL: GP_Standard_D2s_v3 + HA
- ✅ Storage: GRS
- ✅ Log Analytics: 90日保持
- ✅ Container Apps: 適切なスケーリング

**月額コスト**: $150-250

**推奨**: 本番環境で許容できるコスト削減

---

## 実装優先順位

### すぐに実装すべき（リスク低）

1. **Log Analytics保持期間短縮** - `retention_in_days = 7`
2. **Storage冗長性変更（開発環境のみ）** - `LRS`
3. **DDoS Protection無効化** - `use_ddos_protection = false`

### 検討すべき（中リスク）

4. **NAT Gateway削除** - アウトバウンドIP固定が不要な場合
5. **Redis代替（Dragonfly）** - 動作検証後

### 慎重に検討（高リスク）

6. **Private Endpoint削除** - 開発環境のみ、セキュリティ要件確認後
7. **外部PostgreSQLサービス** - データガバナンス要件確認後

---

## 実装例: 超低コスト構成

新規ファイル `terraform.tfvars` (開発環境):

```hcl
# 基本設定
domain   = "langfuse-dev.example.com"
location = "japaneast"
name     = "langfuse-dev"

# Container Apps（最小構成）
container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # スケールtoゼロ
container_app_max_replicas = 3
langfuse_image_tag        = "2"

# PostgreSQL（最小構成、HAなし）
postgres_instance_count = 1
postgres_sku_name      = "B_Standard_B1ms"
postgres_storage_mb    = 32768

# Redis（Dragonflyで代替）
# redis_* 変数は使用しない

# Storage（LRS）
# storage_replication_type = "LRS"  # variables.tfに追加が必要

# セキュリティ（開発環境）
use_encryption_key  = false  # 暗号化キーなし
use_ddos_protection = false  # DDoS保護なし
# enable_private_endpoints = false  # variables.tfに追加が必要
```

---

## モニタリングとアラート

コスト削減後も、以下のモニタリングを推奨：

1. **Azure Cost Management**
   - 日次コストレポート
   - 予算アラート設定（$50, $100等）

2. **リソース使用状況**
   - Container Appsのメトリクス監視
   - PostgreSQLのCPU/メモリ使用率
   - Storageの使用量

3. **コマンドでコスト確認**

```bash
# 現在月のコスト
az consumption usage list \
  --start-date $(date -u -d "$(date +%Y-%m-01)" '+%Y-%m-%d') \
  --end-date $(date -u '+%Y-%m-%d') \
  --query "[].{Service:instanceName,Cost:pretaxCost}" \
  --output table

# リソースグループ別コスト
az consumption usage list \
  --start-date 2025-11-01 \
  --end-date 2025-11-30 \
  | jq -r 'group_by(.instanceLocation) | .[] | {location: .[0].instanceLocation, total: (map(.pretaxCost|tonumber) | add)}'
```

---

## まとめ

### 最大削減可能額

| 環境 | 現在 | 最適化後 | 削減額 | 削減率 |
|-----|------|---------|-------|--------|
| 開発 | $55-85 | $20-40 | $35-45 | 53-64% |
| 本番 | $275-700 | $150-250 | $125-450 | 45-64% |

### 推奨アプローチ

**開発環境**:
1. NAT Gateway削除
2. Redis → Dragonfly
3. Private Endpoint削除
4. Storage LRS
5. Log Analytics 7日

→ **月額 $20-40** (約 60%削減)

**本番環境**:
1. Redis → Dragonfly（検証後）
2. Storage GRS維持
3. Private Endpoint維持
4. 適切なPostgreSQL SKU選択

→ **月額 $150-250** (約 45%削減)

---

## 次のステップ

1. 要件の確認（セキュリティ、可用性、パフォーマンス）
2. 開発環境で削減案をテスト
3. コストモニタリング設定
4. 段階的に本番環境へ適用

---

**最終更新**: 2025-11-13
**対象バージョン**: Container Apps版
