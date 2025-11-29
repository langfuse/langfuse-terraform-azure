# コスト最適化ガイド

このドキュメントでは、Langfuse v3 on Azure Container Appsのコスト削減方法を説明します。

## Container Apps版のアーキテクチャ変更点

AKS版からContainer Apps版への移行で以下のアーキテクチャ変更があり、コスト構成が変わっています。
（両方ともLangfuse v3を使用）

### AKS版 → Container Apps版の主な変更

| 変更項目 | AKS版 | Container Apps版 | コストへの影響 |
|---------|-------|---------------------|--------------|
| **Application Gateway** | AGIC経由で使用 | 内部環境のため新規追加 | +$20-30/月 |
| **ClickHouse** | サイドカー（Webと同一Pod） | 専用Container App（常時起動） | +$30-60/月 |
| **Worker** | Pod内で動作 | 専用Container App（常時起動） | +$10-30/月 |
| **Redis** | Azure Managed Redis (Basic) | Azure Cache for Redis (Standard) | +$25-45/月 |
| **ClickHouse Storage** | 通常File Share | Premium NFS FileStorage | +$12-20/月 |

### 変更理由

1. **Application Gateway**: Container Apps内部環境は直接外部公開できないため、Application Gatewayが必要
2. **ClickHouse専用化**: Webのスケーリングに依存しない独立したデータベース運用のため
3. **Worker追加**: Langfuse v3の非同期イベント処理アーキテクチャに必要
4. **Redis種別変更**: Azure Managed Redis OSSClusterモードがBullキューのCROSSLOTエラーを起こすため、非クラスタのAzure Cache for Redisに変更
5. **Premium NFS**: Container AppsでのNFSマウントにはPremium FileStorageが必要

---

## 現在の構成とコスト概算

### 開発環境（Langfuse v3 現在の構成）

| リソース | 月額概算 | 備考 |
|---------|---------|------|
| **Application Gateway** | $20-30 | Standard_v2, capacity 1（内部Container Apps公開用） |
| **Container Apps (Web)** | $5-20 | CPU 0.5-1.0, Memory 1-2Gi, min 0-1 replica |
| **Container Apps (Worker)** | $10-30 | CPU 1.0, Memory 2Gi, 常時1台起動 |
| **Container Apps (ClickHouse)** | $30-60 | CPU 2.0, Memory 4Gi, 常時1台起動 |
| **PostgreSQL Flexible Server** | $10-30 | B_Standard_B1ms, HAなし |
| **Azure Cache for Redis** | $40-60 | Standard C1（非クラスタ、Bullキュー対応） |
| **Storage Account (Blob)** | $2-3 | Blob Storage LRS、Azure Blob SDK使用 |
| **Storage Account (Premium NFS)** | $15-25 | Premium FileStorage 100GB（ClickHouse用） |
| **Log Analytics** | $5 | 30日保持 |
| **Private Endpoints (2個)** | $2 | PostgreSQL, Redis用 |
| **合計** | **$139-265** | |

### 本番環境（推奨構成）

| リソース | 月額概算 | 備考 |
|---------|---------|------|
| **Application Gateway** | $40-80 | Standard_v2, capacity 2-4（冗長化） |
| **Container Apps (Web)** | $50-100 | CPU 2.0, Memory 4Gi, min 2 replicas |
| **Container Apps (Worker)** | $20-50 | CPU 2.0, Memory 4Gi, min 2 replicas |
| **Container Apps (ClickHouse)** | $60-120 | CPU 4.0, Memory 8Gi, 1台（スケール不可） |
| **PostgreSQL Flexible Server (HA)** | $100-300 | GP_Standard_D4s_v3 + HA |
| **Azure Cache for Redis** | $80-150 | Standard C2-C3 または Premium |
| **Storage Account (Blob)** | $20 | Blob Storage GRS |
| **Storage Account (Premium NFS)** | $30-50 | Premium FileStorage 200GB以上 |
| **Log Analytics** | $20-50 | 大量ログ |
| **NAT Gateway（オプション）** | $30 | 固定IPが必要な場合 |
| **Private Endpoints (2-4個)** | $2-4 | セキュリティ要件次第 |
| **DNS Zone（オプション）** | $0.50 | カスタムドメイン使用時 |
| **Key Vault（オプション）** | $0.03 | SSL証明書管理 |
| **合計** | **$433-935** | オプション含む |

### AKS版との比較

| 環境 | AKS版 | Container Apps版 | 差額 |
|-----|-------|-----------------|------|
| 開発 | $100-145 | $139-265 | +$39-120 |
| 本番 | $430-960 | $433-935 | ほぼ同等 |

**注意**: 両方ともLangfuse v3を使用。Container Apps版は運用がシンプルですが、以下の理由でやや高コスト：
- Application Gateway（内部環境公開用）
- Azure Cache for Redis Standard（非クラスタ必須）
- Premium NFS（Container Apps要件）

**メリット**:
- Kubernetes知識不要でシンプルな運用
- デプロイ時間短縮（10-18分 vs 20-30分）
- Helmチャート管理不要
- 自動スケーリング設定が簡単

---

## さらなるコスト削減案

現在の構成からさらにコストを削減したい場合の選択肢を示します。

### 🥇 優先度: 高（大きなコスト削減）

#### 1. Redisの代替案（月額 $35-55削減）

**現状**: Azure Cache for Redis Standard C1 = $40-60/月

**代替案A: Dragonfly on Container Apps**

Dragonflyは高性能でRedis互換のメモリストア（非クラスタモード対応）

新規ファイル `dragonfly.tf`:
```hcl
resource "azurerm_container_app" "dragonfly" {
  name                         = "dragonfly"
  container_app_environment_id = azapi_resource.container_app_environment.id
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

**コスト**: Container Apps料金のみ（約 $5-10/月）

**注意**: Langfuse v3はBullキューを使用するため、CROSSSLOT対応が必要。Dragonflyは非クラスタモードで動作するため対応可能。

**代替案B: Valkey on Container Apps (Redis fork)**

Redis 7.2.4のフォーク、完全互換、非クラスタモード対応

```hcl
resource "azurerm_container_app" "valkey" {
  # 同様の構成
  template {
    container {
      image = "valkey/valkey:7.2"
      cpu   = 0.5
      memory = "1Gi"
      # ...
    }
    min_replicas = 1
    max_replicas = 1
  }
}
```

**コスト**: Container Apps料金のみ（約 $5-10/月）

**代替案C: Azure Cache for Redis Basic**

⚠️ **非推奨**: Basic SKUは非クラスタですが、SLAなし・永続性なしのため本番非推奨

**推奨**: Dragonfly または Valkey on Container Apps（月額 $35-55削減）

---

#### 2. ClickHouseリソース削減（月額 $10-30削減）

**現状**: ClickHouse Container App (CPU 2.0, Memory 4Gi = $30-60/月)

**代替案**: 開発環境ではリソースを削減

```hcl
# clickhouse.tf を編集
resources = {
  cpu    = 1.0   # 2.0 から削減
  memory = "2Gi" # 4Gi から削減
}
```

**影響**:
- ✅ 月額 $10-30 削減
- ⚠️ 大量データ処理時のパフォーマンス低下
- ⚠️ 開発/テスト環境のみ推奨

---

#### 3. PostgreSQL/Redis Private Endpointの削除（月額 $2削減）

**現状**: 2つのPrivate Endpoint（PostgreSQL, Redis）

**代替案**: 開発環境ではPublicアクセスを許可（ファイアウォールルールで制限）

**影響**:
- ✅ 月額 $2 削減（Private Endpoint x 2）
- ⚠️ セキュリティが若干低下（本番環境では非推奨）
- ✅ ファイアウォールルールで制御可能

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

### シナリオ1: 現在の構成（月額 $139-265）

**構成**:
- ✅ Application Gateway: Standard_v2 capacity 1
- ✅ Container Apps (Web): CPU 0.5-1.0, min 0-1 replica
- ✅ Container Apps (Worker): CPU 1.0, 常時1台
- ✅ Container Apps (ClickHouse): CPU 2.0, 常時1台
- ✅ Redis: Azure Cache for Redis Standard C1（非クラスタ）
- ✅ PostgreSQL: B_Standard_B1ms
- ✅ Storage: LRS (Blob + Premium NFS 100GB)
- ✅ Private Endpoints: PostgreSQL, Redis用 (2個)
- ✅ Log Analytics: 30日保持

**月額コスト**: $139-265

**推奨**: Langfuse v3 開発/テスト環境向け標準構成

---

### シナリオ2: コスト最適化開発環境（月額 $75-140）

**現在の構成からの変更**:
- Redis → Dragonfly on Container Apps（-$35-55）
- ClickHouseリソース削減（CPU 1.0, 2Gi）（-$10-30）
- Private Endpoint削除（-$2）
- Log Analytics: 7日保持（-$2-5）
- Web Container Apps: min 0 replicas（-$3-10）

**月額コスト**:
| リソース | 月額概算 |
|---------|---------|
| Application Gateway | $20-30 |
| Container Apps (Web) | $2-10 |
| Container Apps (Worker) | $10-20 |
| Container Apps (ClickHouse) | $15-30 |
| Container Apps (Dragonfly) | $5-10 |
| PostgreSQL | $10-20 |
| Storage (Blob + NFS) | $17-28 |
| Log Analytics | $2-3 |
| **合計** | **$75-140** |

**トレードオフ**:
- マネージドRedisなし（Dragonfly運用）
- ClickHouseパフォーマンス低下
- Private Endpoint なし（開発環境のみ）
- 短いログ保持期間

**削減額**: 現在の構成から約 $64-125削減

---

### シナリオ3: 本番環境（月額 $433-935）

**変更内容**:
- Application Gateway: capacity 2-4（冗長化）
- Container Apps: 全て min 2 replicas
- ClickHouse: CPU 4.0, Memory 8Gi
- Redis: Azure Cache for Redis Standard C2-C3
- PostgreSQL: GP_Standard_D4s_v3 + HA
- Storage (Blob): GRS
- Storage (NFS): 200GB以上
- Log Analytics: 90日保持
- NAT Gateway（オプション）
- カスタムドメイン + SSL

**月額コスト**: $433-935

**推奨**: 本番環境向け高可用性構成

---

## さらなる削減の実装優先順位

現在の構成からさらにコストを削減する場合の推奨順序：

### すぐに実装可能（リスク低）

1. **Log Analytics保持期間短縮** - `retention_in_days = 7` （月額 -$2～5）
2. **Web Container Apps スケールtoゼロ** - `min_replicas = 0` （月額 -$3～10）
3. **ClickHouseリソース削減** - CPU 1.0, Memory 2Gi （月額 -$10～30）

### 検討すべき（中リスク）

4. **Redis代替（Dragonfly/Valkey）** - 動作検証後 （月額 -$35～55）
5. **外部PostgreSQLサービス** - Neon/Supabase等、データガバナンス要件確認後 （月額 -$5～20）

### 慎重に検討（高リスク）

6. **PostgreSQL/Redis Private Endpoint削除** - 開発環境のみ、セキュリティ要件確認後 （月額 -$2）

---

## 実装例: 現在の構成

ファイル `terraform.tfvars` (Langfuse v3 開発環境の現在の設定):

```hcl
# 基本設定
location = "japaneast"
name     = "langfuse-dev"
# domain は未設定（Application Gateway経由でHTTPアクセス）

# Container Apps - Web（開発環境向け）
container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # スケールtoゼロ
container_app_max_replicas = 3
langfuse_image_tag         = "3"

# Container Apps - Worker（常時起動）
worker_cpu          = 1.0
worker_memory       = 2
worker_min_replicas = 1  # 常時1台起動
worker_max_replicas = 1

# PostgreSQL（最小構成、HAなし）
postgres_instance_count = 1
postgres_sku_name       = "B_Standard_B1ms"
postgres_storage_mb     = 32768

# Redis（Azure Cache for Redis Standard - 非クラスタ）
redis_sku_name = "Standard"
redis_family   = "C"
redis_capacity = 1

# セキュリティ（開発環境）
use_encryption_key  = true   # 暗号化キー有効
use_ddos_protection = false  # DDoS保護なし
```

**月額コスト**: 約 $139-265

---

## モニタリングとアラート

コスト削減後も、以下のモニタリングを推奨：

1. **Azure Cost Management**
   - 日次コストレポート
   - 予算アラート設定（$150, $300等）

2. **リソース使用状況**
   - Container Apps (Web, Worker, ClickHouse) のメトリクス監視
   - PostgreSQLのCPU/メモリ使用率
   - Redis のメモリ使用率
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

### コスト比較（両方ともLangfuse v3）

| 環境 | AKS版 | Container Apps版 | 最適化後 |
|-----|-------|-----------------|---------|
| 開発 | $100-145 | **$139-265** | $75-140 |
| 本番 | $430-960 | **$433-935** | - |

### Container Apps版でのコスト増加要因（AKS版比）

| 要因 | 増加額 | 理由 |
|-----|-------|------|
| Application Gateway | +$20-30/月 | 内部Container Apps公開用 |
| Worker Container App | +$10-30/月 | 専用Container Appとして分離 |
| ClickHouse専用化 | +$20-40/月 | サイドカーから独立 |
| Redis種別変更 | +$25-45/月 | CROSSSLOT対応で非クラスタ必須 |
| Premium NFS | +$12-20/月 | Container Apps NFSマウント要件 |

### コスト削減の選択肢

**コスト最適化開発環境**:
1. Redis → Dragonfly/Valkey on Container Apps
2. ClickHouseリソース削減
3. Log Analytics 7日保持
4. Web Container Apps スケールtoゼロ
5. Private Endpoint削除（開発環境のみ）

→ **月額 $75-140** (現在の構成から -$64～125)

**本番環境**:
1. Application Gateway冗長化
2. Container Apps min 2 replicas
3. Redis: Standard C2-C3
4. PostgreSQL: GP_Standard_D4s_v3 + HA
5. Storage: GRS、NFS 200GB以上

→ **月額 $433-935**

---

## 次のステップ

1. 要件の確認（セキュリティ、可用性、パフォーマンス）
2. 開発環境でDragonfly/Valkeyを検証
3. コストモニタリング設定（予算アラート $200）
4. 段階的に本番環境へ適用

---

**最終更新**: 2025-11-29
**対象バージョン**: Langfuse v3 on Container Apps（Web + Worker + ClickHouse）
