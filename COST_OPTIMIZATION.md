# コスト最適化ガイド

このドキュメントでは、Langfuse on Azure Container Appsのコスト削減方法を説明します。

## 実施済みの最適化

このリポジトリでは、開発/テスト環境向けに以下の最適化を**既に実施済み**です：

- ✅ **NAT Gateway削除** - アウトバウンド通信はContainer Apps経由（月額 -$10～30）
- ✅ **DNS Zone削除** - Container Appsのデフォルトドメインを使用（月額 -$0.50）
- ✅ **Key Vault削除** - カスタムドメイン不使用のため不要（月額 -$0.03）
- ✅ **Storage Private Endpoint削除** - 公開アクセス+ファイアウォール制限に変更（月額 -$1）
- ✅ **Storage LRS化** - GRSからLRSに変更（月額 -$2～10）
- ✅ **DDoS Protection無効** - 開発環境では不要（月額 -$2,944）

**削減額合計**: 月額 約$14～42削減（元の構成比で25～50%削減）

---

## 現在の構成とコスト概算

### 開発環境（現在の構成）
| リソース | 月額概算 | 備考 |
|---------|---------|------|
| Container Apps | $5-20 | CPU 0.5-1.0, Memory 1-2Gi, min 0-1 replica |
| PostgreSQL Flexible Server | $10-30 | B_Standard_B1ms, HAなし |
| Redis Cache (Basic C0) | $15 | 最小構成 |
| Storage Account (Blob) | $2-3 | Blob Storage LRS、公開アクセス |
| Storage Account (File Share 50GB) | $2.50 | ClickHouse永続ストレージ |
| Log Analytics | $5 | 30日保持 |
| Private Endpoints (2個) | $2 | PostgreSQL, Redis用 |
| **合計** | **$41-77** | |

### 本番環境（推奨構成）
| リソース | 月額概算 | 備考 |
|---------|---------|------|
| Container Apps | $50-200 | CPU 2.0, Memory 4Gi, min 2 replicas |
| PostgreSQL Flexible Server (HA) | $100-300 | GP_Standard_D4s_v3 + HA |
| Redis Cache (Standard C1) | $50-100 | 推奨構成 |
| Storage Account (Blob) | $20 | Blob Storage GRS |
| Storage Account (File Share 50GB) | $2.50-10 | ClickHouse永続ストレージ（冗長化） |
| Log Analytics | $20-50 | 大量ログ |
| NAT Gateway（オプション） | $30 | 固定IPが必要な場合 |
| Private Endpoints (2-4個) | $2-4 | セキュリティ要件次第 |
| DNS Zone（オプション） | $0.50 | カスタムドメイン使用時 |
| Key Vault（オプション） | $0.03 | SSL証明書管理 |
| **合計** | **$245-714** | オプション含む |

---

## さらなるコスト削減案

現在の構成からさらにコストを削減したい場合の選択肢を示します。

### 🥇 優先度: 高（大きなコスト削減）

#### 1. Redisの代替案（月額 $15削減）

**現状**: Azure Managed Redis (Balanced B0 = $14.60/月)

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

#### 2. PostgreSQL/Redis Private Endpointの削除（月額 $2削減）

**現状**: 2つのPrivate Endpoint（PostgreSQL, Redis）

**代替案**: 開発環境ではPublicアクセスを許可（ファイアウォールルールで制限）

**実装方法**:

`postgres.tf`:
```hcl
resource "azurerm_postgresql_flexible_server" "this" {
  # ...
  public_network_access_enabled = true  # Private Endpoint削除

  # Container Appsサブネットからのアクセスを許可
  dynamic "firewall_rule" {
    for_each = var.enable_public_access ? [var.container_apps_subnet_address_prefix] : []
    content {
      name             = "allow-container-apps"
      start_ip_address = cidrhost(firewall_rule.value, 0)
      end_ip_address   = cidrhost(firewall_rule.value, -1)
    }
  }
}

# Private Endpoint、Private DNS Zone等を削除
```

**影響**:
- ✅ 月額 $2 削減（Private Endpoint x 2）
- ⚠️ セキュリティが若干低下（本番環境では非推奨）
- ✅ ファイアウォールルールで制御可能
- ⚠️ 同一リージョン内通信のため、データ転送コストは変わらない（Azureは同一リージョン内は常に無料）

**推奨**: 開発環境のみ適用

---

### 🥈 優先度: 中（中程度のコスト削減）

#### 3. PostgreSQLのサーバーレス化（月額 $5-20削減）

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

#### 4. Log Analyticsの保持期間短縮（月額 $2-10削減）

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

## コスト削減シナリオ

### シナリオ1: 現在の構成（月額 $41-77）

**構成**:
- ✅ NAT Gateway削除済み
- ✅ DNS Zone削除済み
- ✅ Key Vault削除済み
- ✅ Storage Private Endpoint削除済み
- ✅ Storage: LRS (Blob + File Share 50GB)
- ✅ ClickHouse: 永続ストレージ付き
- ✅ Redis: Azure Managed Redis Balanced_B0
- ✅ PostgreSQL: B_Standard_B1ms
- ✅ Private Endpoints: PostgreSQL, Redis用のみ (2個)
- ✅ Log Analytics: 30日保持
- ✅ Container Apps: 可変スケーリング

**月額コスト**: $41-77

**推奨**: 開発/テスト環境向けのバランス型構成

---

### シナリオ2: 超低コスト開発環境（月額 $22-36）

**現在の構成からの追加変更**:
- Redis → Dragonfly on Container Apps
- Private Endpoint削除（Public + Firewall）
- Log Analytics: 7日保持
- Container Apps: min 0 replicas（スケールtoゼロ）
- File Share: 最小10GB

**月額コスト**:
- Container Apps: $3-10（スケールtoゼロ）
- PostgreSQL: $10
- Dragonfly: $3-5
- Storage (Blob): $2-3
- Storage (File Share 10GB): $0.50
- Log Analytics: $2-3
- **合計: $22-36**

**トレードオフ**:
- さらにセキュリティが低下（個人プロジェクトのみ推奨）
- Private Endpoint なし
- 短いログ保持期間
- ClickHouse用File Shareを10GBに削減

**削減額**: 現在の構成から約 $19-41削減

---

### シナリオ3: コスト最適化本番環境（月額 $245-514）

**変更内容**:
- NAT Gateway追加（固定IP必要な場合）
- DNS Zone追加（カスタムドメイン）
- Key Vault追加（SSL証明書管理）
- Redis: Standard C1またはDragonfly
- Private Endpoint: 全リソース用
- PostgreSQL: GP_Standard_D2s_v3 + HA
- Storage (Blob): GRS
- Storage (File Share): 50-100GB、冗長化オプション
- Log Analytics: 90日保持
- Container Apps: 適切なスケーリング（min 2 replicas）

**月額コスト**: $245-514

**推奨**: 本番環境で必要な機能とコストのバランス

---

## さらなる削減の実装優先順位

現在の構成からさらにコストを削減する場合の推奨順序：

### すぐに実装可能（リスク低）

1. **Log Analytics保持期間短縮** - `retention_in_days = 7` （月額 -$2～10）
2. **Container Apps スケールtoゼロ** - `min_replicas = 0` （月額 -$2～10）

### 検討すべき（中リスク）

3. **Redis代替（Dragonfly）** - 動作検証後 （月額 -$12～95）
4. **外部PostgreSQLサービス** - Neon/Supabase等、データガバナンス要件確認後 （月額 -$5～20）

### 慎重に検討（高リスク）

5. **PostgreSQL/Redis Private Endpoint削除** - 開発環境のみ、セキュリティ要件確認後 （月額 -$2）

---

## 実装例: 現在の構成

ファイル `terraform.tfvars` (開発環境の現在の推奨設定):

```hcl
# 基本設定
location = "japaneast"
name     = "langfuse-dev"
# domain は未設定（Container Appsのデフォルトドメインを使用）

# Container Apps（開発環境向け）
container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # スケールtoゼロ
container_app_max_replicas = 3
langfuse_image_tag        = "2"

# PostgreSQL（最小構成、HAなし）
postgres_instance_count = 1
postgres_sku_name      = "B_Standard_B1ms"
postgres_storage_mb    = 32768

# Redis（管理型、最小構成）
redis_sku_name = "Balanced_B0"

# セキュリティ（開発環境）
use_encryption_key  = false  # 暗号化キーなし
use_ddos_protection = false  # DDoS保護なし
```

**月額コスト**: 約 $41-77

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

### コスト比較

| 環境 | 元の構成 | 現在の構成 | 超低コスト構成 | 削減額 |
|-----|---------|----------|------------|--------|
| 開発 | $53-117 | **$41-77** | $22-36 | -$12～81 |
| 本番 | $275-704 | - | $245-514 | - |

### 既に実施済みの最適化

**開発環境（現在の構成）**:
1. ✅ NAT Gateway削除
2. ✅ DNS Zone削除
3. ✅ Key Vault削除
4. ✅ Storage Private Endpoint削除
5. ✅ Storage LRS化
6. ✅ ClickHouse永続ストレージ追加（File Share 50GB）

→ **月額 $41-77** (元の構成から約 25-50%削減済み、ClickHouse永続化含む)

### さらなる削減の選択肢

**超低コスト開発環境（個人プロジェクト向け）**:
1. Redis → Dragonfly on Container Apps
2. PostgreSQL/Redis Private Endpoint削除
3. Log Analytics 7日保持
4. Container Apps スケールtoゼロ
5. File Share容量削減（50GB → 10GB）

→ **月額 $22-36** (現在の構成からさらに -$19～41)

**本番環境**:
1. 必要に応じてNAT Gateway、DNS Zone、Key Vault追加
2. Redis: Standard C1またはDragonfly（検証後）
3. Storage (Blob): GRS
4. Storage (File Share): 50-100GB、冗長化オプション
5. Private Endpoint: 全リソース用
6. 適切なPostgreSQL SKU選択（GP + HA）

→ **月額 $245-514**

---

## 次のステップ

1. 要件の確認（セキュリティ、可用性、パフォーマンス）
2. 開発環境で削減案をテスト
3. コストモニタリング設定
4. 段階的に本番環境へ適用

---

**最終更新**: 2025-11-16
**対象バージョン**: Container Apps版（開発環境最適化済み + ClickHouse永続化）
