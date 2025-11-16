# ClickHouse専用コンテナ移行計画

## 概要

現在のサイドカーパターンから専用Container Appへの移行計画書

**作成日**: 2025-11-16
**対象**: ClickHouse (Analytics Database)

> **⚠️ 重要**: 移行前に必ず [ROLLBACK.md](./ROLLBACK.md) を確認してください。
> 動作確認済みの構成（コミット `d3665e7`）へのロールバック手順が記載されています。

---

## 1. 現状の問題点

### 1.1 サイドカーパターンの問題

**現在の構成**:
```
Container App (Langfuse)
├── Container: langfuse (main)
└── Container: clickhouse (sidecar)
    └── Volume: Azure File Share (50GB)
```

**問題**:

1. **スケールアウト時の複数インスタンス問題**
   - Langfuseが2レプリカにスケールすると、ClickHouseも2インスタンス起動
   - 各ClickHouseインスタンスが独立してデータを持つ
   - データの不整合が発生する可能性

2. **Azure File Shareの同時書き込み競合**
   - 複数のClickHouseインスタンスが同じFile Shareに書き込もうとする
   - ファイルロックや競合の問題
   - データ破損のリスク

3. **リソースの無駄**
   - 各Langfuseレプリカごとに1.0 CPU + 2Gi MemoryのClickHouseが起動
   - min_replicas=2の場合、ClickHouseだけで2 CPU + 4Gi Memory消費

4. **LangfuseのスケーリングがClickHouseに影響**
   - Langfuseの負荷に応じてClickHouseも増減してしまう
   - ClickHouseは常に1インスタンスで動かすべき

### 1.2 以前の失敗要因（参考）

過去に専用Container Appを試みて失敗した理由：
- Container Apps間のTCP通信（ClickHouseネイティブプロトコル port 9000）がInternal Ingressでサポートされていない可能性
- HTTPプロトコルのみの検証が不十分だった

---

## 2. 目指すべき構成

### 2.1 ターゲットアーキテクチャ

```
Container App (Langfuse) - min 0-1, max 10
└── Container: langfuse

Container App (ClickHouse) - min 1, max 1 (固定)
└── Container: clickhouse
    └── Volume: Azure File Share (50GB)
```

**接続方法**:
- Internal Ingress (HTTPS) - port 8123 (HTTPプロトコル)
- FQDN: `clickhouse.internal.<environment-default-domain>`

### 2.2 期待される効果

✅ **データの一貫性**
- ClickHouseインスタンスが常に1つのみ
- すべてのLangfuseレプリカが同じClickHouseに接続
- データの不整合なし

✅ **リソース効率**
- ClickHouseは1インスタンスのみ（1 CPU + 2Gi Memory）
- Langfuseのスケーリングに影響されない

✅ **独立したスケーリング**
- LangfuseとClickHouseを独立してスケール
- ClickHouseは常に1レプリカ固定

✅ **永続ストレージ**
- Azure File Shareによるデータ永続化は継続

---

## 3. 技術的な選択肢

### Option 1: Container Apps + Internal Ingress (HTTP) ⭐推奨

**構成**:
```hcl
resource "azurerm_container_app" "clickhouse" {
  name = "clickhouse"
  # ...

  template {
    container {
      name   = "clickhouse"
      image  = "clickhouse/clickhouse-server:latest-alpine"
      # HTTP interface only (port 8123)
    }

    min_replicas = 1
    max_replicas = 1  # 固定
  }

  ingress {
    external_enabled = false  # Internal only
    target_port      = 8123   # HTTP protocol
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
```

**接続URL**:
- `CLICKHOUSE_URL`: `https://clickhouse.internal.<env-domain>/default`
- `CLICKHOUSE_MIGRATION_URL`: HTTPプロトコルのみ使用可能な場合は注意

**メリット**:
- ✅ Container Apps間通信がサポートされている
- ✅ Internal Ingressは無料
- ✅ 同一Container Apps Environment内で低レイテンシ
- ✅ HTTPSで暗号化

**デメリット**:
- ⚠️ ClickHouseネイティブプロトコル（port 9000）が使えない可能性
- ⚠️ Langfuseがport 9000必須なら動作しない

**判定条件**:
- Langfuseのマイグレーション処理がHTTPプロトコル（port 8123）のみで動作するか確認

---

### Option 2: Container Apps + TCP Support (要検証)

**構成**:
```hcl
resource "azurerm_container_app" "clickhouse" {
  # ...
  ingress {
    external_enabled = false
    target_port      = 9000
    transport        = "tcp"  # TCP transport
  }
}
```

**現状**: Azure Container AppsがTCP transportをサポートしているか要確認

**調査が必要**:
1. Container Apps IngressのTCPサポート状況
2. Internal IngressでのTCP通信の可否
3. ClickHouseネイティブプロトコル（port 9000）の動作確認

**メリット**:
- ✅ すべてのClickHouse機能が使える
- ✅ パフォーマンス最適化

**デメリット**:
- ❌ TCPサポートが不明
- ❌ 実装が複雑になる可能性

---

### Option 3: Azure Container Instances (代替案)

**構成**:
```hcl
resource "azurerm_container_group" "clickhouse" {
  name                = "clickhouse"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  os_type             = "Linux"

  container {
    name   = "clickhouse"
    image  = "clickhouse/clickhouse-server:latest-alpine"
    cpu    = 1
    memory = 2

    ports {
      port     = 8123
      protocol = "TCP"
    }

    volume {
      name                 = "clickhouse-data"
      mount_path           = "/var/lib/clickhouse"
      storage_account_name = azurerm_storage_account.this.name
      storage_account_key  = azurerm_storage_account.this.primary_access_key
      share_name           = azurerm_storage_share.clickhouse.name
    }
  }

  ip_address_type = "Private"
  subnet_ids      = [azurerm_subnet.container_instances.id]  # 新規サブネット
}
```

**接続URL**:
- `CLICKHOUSE_URL`: `http://<private-ip>:8123/default`

**メリット**:
- ✅ VNet統合で安全な通信
- ✅ 完全なTCP/UDPサポート
- ✅ シンプルな構成

**デメリット**:
- ⚠️ Container Appsと異なるサービス（管理が増える）
- ⚠️ Private IPの管理が必要
- ⚠️ 追加のサブネットが必要
- ⚠️ 月額コスト: 約$30-40（Container Apps単独より高い）

---

## 4. 推奨アプローチ

### Phase 1: 検証 (推奨実施順序)

#### Step 1.1: Langfuseの接続要件確認

**目的**: LangfuseがHTTPプロトコル（port 8123）のみで動作するか確認

**実施内容**:
1. 現在のログを確認し、ClickHouseへの接続URLを特定
2. `CLICKHOUSE_MIGRATION_URL`でport 9000が必須か確認
3. Langfuseのドキュメント・ソースコードを調査

**判定**:
- ✅ HTTPのみで動作 → Option 1へ
- ❌ port 9000必須 → Option 2検証へ

#### Step 1.2: Container Apps TCP Support検証

**前提**: Step 1.1でport 9000が必須だった場合のみ実施

**実施内容**:
```bash
# Azure CLIでTCP transport設定を試す
az containerapp ingress update \
  --name test-clickhouse \
  --resource-group test-rg \
  --target-port 9000 \
  --transport tcp
```

**判定**:
- ✅ TCP設定成功 → Option 2へ
- ❌ エラー発生 → Option 3検討

---

### Phase 2: 実装

#### **推奨: Option 1 (Internal Ingress HTTP)**

以下の条件を満たす場合に推奨：
- LangfuseがHTTPプロトコル（port 8123）で動作する
- マイグレーションもHTTPで可能

**実装手順**:

1. **新規ファイル作成: `clickhouse_dedicated.tf`**

```hcl
# Dedicated ClickHouse Container App
resource "azurerm_container_app" "clickhouse" {
  name                         = "${var.name}-clickhouse"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    container {
      name   = "clickhouse"
      image  = "clickhouse/clickhouse-server:latest-alpine"
      cpu    = 1.0
      memory = "2Gi"

      volume_mounts {
        name = "clickhouse-data"
        path = "/var/lib/clickhouse"
      }
    }

    volume {
      name         = "clickhouse-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.clickhouse.name
    }

    min_replicas = 1
    max_replicas = 1  # Always 1 instance
  }

  ingress {
    external_enabled = false  # Internal only
    target_port      = 8123   # HTTP protocol

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = {
    application = local.tag_name
  }
}
```

2. **`container_apps.tf`の修正**

```hcl
# Langfuse Container App - Remove ClickHouse sidecar
resource "azurerm_container_app" "langfuse" {
  # ...

  template {
    container {
      name   = "langfuse"
      image  = "langfuse/langfuse:${var.langfuse_image_tag}"
      # ... existing config

      # Update ClickHouse URLs
      env {
        name        = "CLICKHOUSE_URL"
        secret_name = "clickhouse-url"
      }

      env {
        name        = "CLICKHOUSE_MIGRATION_URL"
        secret_name = "clickhouse-migration-url"
      }
    }

    # Remove clickhouse sidecar container
    # Remove volume definition for clickhouse-data
  }

  # Update secrets with new URLs
  secret {
    name  = "clickhouse-url"
    value = "https://${azurerm_container_app.clickhouse.ingress[0].fqdn}/default"
  }

  secret {
    name  = "clickhouse-migration-url"
    value = "https://${azurerm_container_app.clickhouse.ingress[0].fqdn}/default"
  }
}
```

3. **既存リソースの維持**
   - `storage.tf`の`azurerm_storage_share.clickhouse`は変更なし
   - `container_apps.tf`の`azurerm_container_app_environment_storage.clickhouse`も変更なし

4. **デプロイ**

```bash
# Plan to verify changes
terraform plan

# Apply changes
terraform apply
```

---

### Phase 3: 検証とロールバック

#### 検証項目

1. **ClickHouseコンテナの起動確認**
```bash
az containerapp show \
  --name <clickhouse-app-name> \
  --resource-group <rg-name> \
  --query "properties.runningStatus"
```

2. **Internal FQDN取得**
```bash
az containerapp show \
  --name <clickhouse-app-name> \
  --resource-group <rg-name> \
  --query "properties.configuration.ingress.fqdn"
```

3. **Langfuseからの接続確認**
```bash
# Langfuseのログを確認
az containerapp logs show \
  --name langfuse \
  --resource-group <rg-name> \
  --follow
```

期待されるログ:
- ✅ ClickHouseへの接続成功
- ✅ マイグレーション実行成功
- ❌ 接続タイムアウトエラー → 要トラブルシューティング

4. **データの永続性確認**
```bash
# Langfuseでトレースを作成
# ClickHouseコンテナを再起動
az containerapp revision restart \
  --name <clickhouse-app-name> \
  --resource-group <rg-name>

# データが残っているか確認
```

#### ロールバック手順

問題が発生した場合は、動作確認済みの構成に戻してください。

**📋 詳細なロールバック手順は [ROLLBACK.md](./ROLLBACK.md) を参照**

**クイックロールバック**:

```bash
# Method 1: タグを使う（推奨）
git checkout v2.2.0-stable
terraform apply

# Method 2: コミットハッシュを使う
git checkout d3665e7
terraform apply

# Method 3: 前のコミットに戻す
git revert HEAD
terraform apply
```

**動作確認済みコミット情報**:
- Gitタグ: `v2.2.0-stable`
- コミットハッシュ: `d3665e7`
- コミットメッセージ: "Add persistent storage for ClickHouse data"
- 日時: 2025-11-16 12:43:54 UTC
- 構成: ClickHouseサイドカーパターン + 永続ストレージ

詳細な検証手順、トラブルシューティング、段階的なロールバック方法は [ROLLBACK.md](./ROLLBACK.md) を参照してください。

---

## 5. コスト比較

### 現在（サイドカーパターン、2レプリカの場合）
| リソース | CPU | Memory | 月額概算 |
|---------|-----|--------|---------|
| Langfuse (2 replicas) | 1.0 | 2Gi | $10 |
| ClickHouse (2 replicas) | 2.0 | 4Gi | $20 |
| **合計** | **3.0** | **6Gi** | **$30** |

### 専用コンテナ（2レプリカの場合）
| リソース | CPU | Memory | 月額概算 |
|---------|-----|--------|---------|
| Langfuse (2 replicas) | 1.0 | 2Gi | $10 |
| ClickHouse (1 replica) | 1.0 | 2Gi | $10 |
| **合計** | **2.0** | **4Gi** | **$20** |

**削減額**: 約$10/月（2レプリカ時）

---

## 6. リスクと対策

### リスク 1: HTTPプロトコルの互換性

**リスク**: LangfuseがClickHouseネイティブプロトコル（port 9000）を必要とする場合、HTTPのみでは動作しない

**対策**:
- Phase 1で事前検証を必ず実施
- port 9000が必須の場合はOption 2またはOption 3を検討

### リスク 2: Internal Ingressの接続問題

**リスク**: Container Apps間のInternal通信が期待通り動作しない

**対策**:
- テスト環境で先に検証
- 接続FQDNの確認（`<app-name>.internal.<env-default-domain>`）
- DNSの伝播待ち時間を考慮（最大5分）

### リスク 3: マイグレーション処理の失敗

**リスク**: ClickHouseへの接続変更によりマイグレーションが失敗

**対策**:
- 事前にデータベースのバックアップ取得
- マイグレーションログの詳細確認
- ロールバック手順を準備

### リスク 4: データ損失

**リスク**: 移行中のデータ損失

**対策**:
- Azure File Shareのスナップショット取得
- 移行前に既存データの確認
- ロールバック可能な状態を維持

---

## 7. 実装チェックリスト

### 事前準備
- [ ] Langfuseの接続要件確認（HTTPプロトコルのみで動作するか）
- [ ] 現在のClickHouseデータのバックアップ
- [ ] Azure File Shareのスナップショット作成
- [ ] テスト環境の準備（推奨）

### 実装
- [ ] `clickhouse_dedicated.tf`ファイル作成
- [ ] `container_apps.tf`からClickHouseサイドカー削除
- [ ] 接続URLの更新（Internal FQDN使用）
- [ ] `terraform plan`で変更内容確認
- [ ] `terraform apply`実行

### 検証
- [ ] ClickHouseコンテナの起動確認
- [ ] Internal FQDNの取得と確認
- [ ] Langfuseからの接続確認
- [ ] マイグレーション処理の成功確認
- [ ] データの永続性確認（再起動テスト）
- [ ] Langfuseのスケーリング確認（2レプリカでデータ一貫性確認）

### 後処理
- [ ] ドキュメント更新（README.md, SETUP_GUIDE.md）
- [ ] コスト削減の確認
- [ ] モニタリング設定

---

## 8. トラブルシューティング

### 問題 1: ClickHouseコンテナが起動しない

**症状**: Container Appのステータスが`Running`にならない

**確認点**:
```bash
# ログ確認
az containerapp logs show --name <clickhouse-app> --resource-group <rg>

# Revision status確認
az containerapp revision list --name <clickhouse-app> --resource-group <rg>
```

**対処**:
- イメージの取得エラー → イメージ名確認
- File Shareマウントエラー → ストレージ接続確認
- リソース不足 → CPU/Memory設定確認

### 問題 2: Langfuseから接続できない

**症状**: `dial tcp: i/o timeout`または`connection refused`

**確認点**:
```bash
# Internal FQDNの確認
az containerapp show --name <clickhouse-app> --resource-group <rg> \
  --query "properties.configuration.ingress.fqdn"

# Langfuseの環境変数確認
az containerapp show --name langfuse --resource-group <rg> \
  --query "properties.template.containers[0].env"
```

**対処**:
- FQDN形式: `https://<app-name>.internal.<env-default-domain>/default`
- プロトコル確認: `https://`（HTTPSが自動付与される）
- DNS伝播待ち: 5-10分待つ

### 問題 3: port 9000が必要

**症状**: HTTPプロトコルではマイグレーションが動作しない

**対処法A**: TCP Supportを試す（Option 2）
```bash
az containerapp ingress update \
  --name <clickhouse-app> \
  --resource-group <rg> \
  --target-port 9000 \
  --transport tcp
```

**対処法B**: Azure Container Instancesへ移行（Option 3）

### 問題 4: データが消える

**症状**: コンテナ再起動後にデータがリセットされる

**確認点**:
```bash
# Volume mount確認
az containerapp show --name <clickhouse-app> --resource-group <rg> \
  --query "properties.template.volumes"

# File Share確認
az storage share show \
  --name clickhouse-data \
  --account-name <storage-account>
```

**対処**:
- Volume定義の確認
- Storage Environment設定の確認
- File Shareのアクセスキー確認

---

## 9. 次のステップ

1. **Phase 1: 検証**
   - [ ] Langfuseの接続要件確認
   - [ ] 必要に応じてTCP Supportの調査

2. **Phase 2: 実装**
   - [ ] テスト環境での実装（推奨）
   - [ ] 本番環境への適用

3. **Phase 3: ドキュメント更新**
   - [ ] README.md更新
   - [ ] SETUP_GUIDE.md更新
   - [ ] アーキテクチャ図更新

---

## 10. 参考情報

### Azure Container Apps ドキュメント
- [Container Apps: Internal ingress](https://learn.microsoft.com/azure/container-apps/ingress-overview#internal-ingress)
- [Container Apps: Multiple containers](https://learn.microsoft.com/azure/container-apps/containers)
- [Container Apps: Storage mounts](https://learn.microsoft.com/azure/container-apps/storage-mounts)

### ClickHouse ドキュメント
- [ClickHouse Interfaces](https://clickhouse.com/docs/en/interfaces/overview)
- [HTTP Interface (port 8123)](https://clickhouse.com/docs/en/interfaces/http)
- [Native Protocol (port 9000)](https://clickhouse.com/docs/en/interfaces/tcp)

### Langfuse ドキュメント
- [Langfuse Self-hosting Configuration](https://langfuse.com/docs/deployment/self-host)
- [ClickHouse Configuration](https://langfuse.com/docs/deployment/self-host#clickhouse)

---

**最終更新**: 2025-11-16
**ステータス**: 計画中 - 実装待ち
**優先度**: 高（スケーリング時のデータ整合性問題のため）
