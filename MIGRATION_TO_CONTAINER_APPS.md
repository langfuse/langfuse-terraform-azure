# Container Appsへの移行ドキュメント

## 概要

このドキュメントは、現在のAKSベースのLangfuseデプロイメントから、Azure Container Appsベースのデプロイメントへの移行について説明します。

## 現在の構成（AKS版）のフロー

### ステップ1: Terraform初期化
```bash
terraform init
```
- Terraformプロバイダーのダウンロード（azurerm, kubernetes, helm, random, tls）
- .terraformディレクトリの作成

### ステップ2: DNSゾーンの先行作成
```bash
terraform apply --target module.langfuse.azurerm_dns_zone.this
```
- Azure DNS Zoneのみを作成

### ステップ3: DNS委任設定（手動）
- Azureのネームサーバーをドメインレジストラに設定

### ステップ4: フルスタック構築
```bash
terraform apply
```

#### フェーズ1: 基盤インフラ（15-20分）
1. リソースグループ、VNet、サブネット
2. PostgreSQL、Redis、Storage Account
3. Private Endpoint、Private DNS Zone
4. **AKS クラスター作成（10-15分）**
5. **Application Gateway作成**
6. Key Vault、SSL証明書
7. DNS Aレコード

#### フェーズ2: Kubernetes構成（2-3分）
8. **Kubernetesプロバイダー経由でAKSに接続**
9. Namespace、Secret作成

#### フェーズ3: アプリケーションデプロイ（3-5分）
10. **Helmチャートインストール**
    - コンテナイメージのプル
    - Deployment、Service作成
    - Ingressリソース作成
    - データベースマイグレーション実行
11. **AGIC（Application Gateway Ingress Controller）が動作**
    - IngressをAppGW設定に変換

**合計所要時間: 20-30分**

---

## Container Apps版のフロー

### ステップ1: Terraform初期化
```bash
terraform init
```
- Terraformプロバイダーのダウンロード（azurerm, random, tls）
- **kubernetes、helmプロバイダーは不要**

### ステップ2: DNSゾーンの先行作成（オプション）
```bash
terraform apply --target module.langfuse.azurerm_dns_zone.this
```
- Azure DNS Zoneのみを作成
- **Container AppsのデフォルトドメインでもOK（DNSゾーン不要）**

### ステップ3: DNS委任設定（オプション）
- カスタムドメインを使う場合のみ必要

### ステップ4: フルスタック構築
```bash
terraform apply
```

#### フェーズ1: 基盤インフラ（8-12分）
1. リソースグループ、VNet、サブネット
2. PostgreSQL、Redis、Storage Account
3. Private Endpoint、Private DNS Zone
4. **Container Apps Environment作成（2-3分）**
5. Key Vault（カスタムドメイン使用時のみ）
6. DNS Aレコード（カスタムドメイン使用時のみ）

#### フェーズ2: アプリケーションデプロイ（3-5分）
7. **Container App作成**
    - コンテナイメージ指定（直接デプロイ）
    - 環境変数、シークレット設定
    - スケーリングルール設定
    - データベースマイグレーション（初回起動時）
8. **Ingress設定**
    - Container AppsのマネージドIngress
    - または Application Gateway統合（オプション）

**合計所要時間: 10-20分（AKSより短縮）**

---

## リソース比較

### 削除されるリソース

| リソース | 理由 |
|---------|------|
| `azurerm_kubernetes_cluster` | Container Appsに置き換え |
| `azurerm_user_assigned_identity.aks` | AKS専用のID |
| `azurerm_role_assignment.aks_*` | AKS関連のロール割り当て |
| `azurerm_subnet.aks` | Container Apps専用サブネットに変更 |
| `azurerm_network_security_group.aks` | Container Apps用に再構成 |
| `azurerm_application_gateway` | Container Appsのマネージドingressを使用（オプションで保持可） |
| `azurerm_subnet.appgw` | AppGW削除時は不要 |
| `azurerm_public_ip.appgw` | AppGW削除時は不要 |
| `azurerm_user_assigned_identity.appgw` | AppGW削除時は不要 |
| `azurerm_key_vault_access_policy.appgw` | AppGW削除時は不要 |
| AGIC関連の全リソース | AGICは不要 |
| `kubernetes_namespace` | Kubernetesリソースは不要 |
| `kubernetes_secret` | Container Appのsecretsに変更 |
| `helm_release` | Container Appの直接デプロイに変更 |

### 追加されるリソース

| リソース | 用途 |
|---------|------|
| `azurerm_container_app_environment` | Container Appsの実行環境 |
| `azurerm_container_app` | Langfuseアプリケーション |
| `azurerm_subnet.container_apps` | Container Apps専用サブネット |
| `azurerm_log_analytics_workspace` | Container Appsのログ収集（必須） |

### 変更されるリソース

| リソース | 変更内容 |
|---------|---------|
| `azurerm_subnet` | AKSサブネット → Container Appsサブネット（delegation追加） |
| サブネット構成 | AKS用の大きなサブネット(/16)が不要に |
| NAT Gateway関連付け | Container Appsサブネットに関連付け |

---

## アーキテクチャの変更

### 現在（AKS版）
```
インターネット
  ↓
Application Gateway (SSL終端)
  ↓
AGIC (Ingress Controller)
  ↓
AKS (Kubernetes)
  └─ Langfuse Pod (Helm経由でデプロイ)
     ↓
PostgreSQL / Redis / Storage (Private Endpoint)
```

### 移行後（Container Apps版）

#### オプション1: マネージドIngress使用
```
インターネット
  ↓
Container Apps Managed Ingress (SSL終端)
  ↓
Container App (Langfuse)
  ↓
PostgreSQL / Redis / Storage (Private Endpoint)
```

#### オプション2: Application Gateway統合
```
インターネット
  ↓
Application Gateway (SSL終端)
  ↓
Container Apps Environment
  └─ Container App (Langfuse)
     ↓
PostgreSQL / Redis / Storage (Private Endpoint)
```

---

## メリット・デメリット

### メリット

| 項目 | 説明 |
|-----|------|
| **シンプルな構成** | Kubernetes、Helm不要でTerraformコードが簡素化 |
| **デプロイ時間短縮** | AKSクラスター作成が不要（10-15分削減） |
| **コスト削減** | AKSノードプールが不要、スケールtoゼロ可能 |
| **管理オーバーヘッド削減** | Kubernetesのバージョン管理、ノード管理が不要 |
| **簡単なスケーリング** | HTTP/CPU/メモリベースの自動スケーリング |
| **ビルトインログ** | Log Analytics統合が標準 |

### デメリット

| 項目 | 説明 |
|-----|------|
| **Kubernetes機能の制限** | カスタムCRD、Operator等は使用不可 |
| **カスタマイズ性の低下** | Kubernetes細かい制御ができない |
| **Application Gateway統合の複雑さ** | AppGWを使う場合、AGICより手動設定が必要 |
| **サイドカーの制限** | Kubernetesのような柔軟なサイドカーパターンは制限あり |

---

## 移行手順

### 前提条件
- 既存のAKSベースのデプロイメントが存在する
- データのバックアップが取得済み

### 手順

#### 1. Container Apps用ブランチの作成
```bash
git checkout -b feature/migrate-to-container-apps
```

#### 2. Terraformコードの変更
以下のファイルを変更/削除:

**削除するファイル:**
- `aks.tf` - AKSクラスター定義
- `ingress.tf` - Application Gateway定義（オプション: 保持してContainer Apps統合も可能）
- `langfuse.tf` - Kubernetes/Helm関連（Container App定義に置き換え）

**新規作成するファイル:**
- `container_apps.tf` - Container Apps Environment + Container App定義
- `log_analytics.tf` - Log Analytics Workspace（Container Apps必須）

**変更するファイル:**
- `variables.tf` - AKS関連変数を削除、Container Apps関連を追加
- `outputs.tf` - AKS出力を削除、Container App URLを追加
- `versions.tf` - kubernetes、helmプロバイダーを削除

#### 3. Container Apps用サブネット設定
`network.tf` に追加:
```hcl
resource "azurerm_subnet" "container_apps" {
  name                 = "${module.naming.subnet.name}-container-apps"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.container_apps_subnet_address_prefix]

  delegation {
    name = "container-apps-delegation"
    service_delegation {
      name = "Microsoft.App/environments"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}
```

#### 4. Container Apps定義
新規 `container_apps.tf`:
```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "this" {
  name                       = module.naming.container_app_environment.name
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id   = azurerm_subnet.container_apps.id
}

resource "azurerm_container_app" "langfuse" {
  name                         = "langfuse"
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = azurerm_resource_group.this.name
  revision_mode                = "Single"

  template {
    container {
      name   = "langfuse"
      image  = "langfuse/langfuse:2.latest"  # バージョン指定推奨
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "DATABASE_URL"
        value = "postgresql://${azurerm_postgresql_flexible_server.this.administrator_login}:${azurerm_postgresql_flexible_server.this.administrator_password}@${azurerm_private_endpoint.postgres.private_service_connection[0].private_ip_address}:5432/langfuse"
      }

      env {
        name  = "REDIS_HOST"
        value = azurerm_redis_cache.this.name
      }

      env {
        name        = "REDIS_AUTH"
        secret_name = "redis-password"
      }

      env {
        name  = "NEXTAUTH_URL"
        value = "https://${var.domain}"
      }

      env {
        name        = "NEXTAUTH_SECRET"
        secret_name = "nextauth-secret"
      }

      env {
        name        = "SALT"
        secret_name = "salt"
      }

      env {
        name  = "S3_ENDPOINT"
        value = "https://${azurerm_storage_account.this.name}.blob.core.windows.net"
      }

      env {
        name  = "S3_BUCKET_NAME"
        value = azurerm_storage_container.this.name
      }

      env {
        name  = "S3_ACCESS_KEY_ID"
        value = azurerm_storage_account.this.name
      }

      env {
        name        = "S3_SECRET_ACCESS_KEY"
        secret_name = "storage-access-key"
      }
    }

    min_replicas = 1
    max_replicas = 10
  }

  secret {
    name  = "redis-password"
    value = azurerm_redis_cache.this.primary_access_key
  }

  secret {
    name  = "nextauth-secret"
    value = random_bytes.nextauth_secret.base64
  }

  secret {
    name  = "salt"
    value = random_bytes.salt.base64
  }

  secret {
    name  = "storage-access-key"
    value = azurerm_storage_account.this.primary_access_key
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}
```

#### 5. 既存環境のバックアップ
```bash
# PostgreSQLのバックアップ
# Redisのスナップショット（必要に応じて）
```

#### 6. 新環境のデプロイ
```bash
terraform init
terraform plan
terraform apply
```

#### 7. 動作確認
- Container AppのURLにアクセス
- データベース接続確認
- 機能テスト

#### 8. DNSの切り替え（カスタムドメイン使用時）
```bash
# Container AppにカスタムドメインとSSL証明書を設定
```

#### 9. 旧環境の削除
```bash
# 別のTerraform state/workspaceで管理している場合
terraform destroy
```

---

## 構成例

### 最小構成（開発環境）
- Container Apps Environment
- Container App (Langfuse)
- PostgreSQL (HA無効)
- Redis (Basic)
- Storage Account
- マネージドIngress（カスタムドメイン無し）

**コスト目安:** AKS版の40-50%削減

### 本番構成
- Container Apps Environment（Zone冗長）
- Container App (Langfuse) with 複数レプリカ
- PostgreSQL (HA有効)
- Redis (Standard/Premium)
- Storage Account (GRS)
- Application Gateway統合
- カスタムドメイン + SSL証明書

**コスト目安:** AKS版の30-40%削減

---

## トラブルシューティング

### Container Appが起動しない
```bash
# ログ確認
az containerapp logs show --name langfuse --resource-group <rg-name>
```

### データベース接続エラー
- Private Endpointの設定確認
- Container Appsサブネットからのアクセス許可確認
- NSGルール確認

### スケーリングが動作しない
- スケーリングルールの設定確認
- CPU/メモリリミットの確認

---

## 参考リンク

- [Azure Container Apps documentation](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Langfuse Self-hosting documentation](https://langfuse.com/docs/deployment/self-host)
- [Container Apps と AKS の比較](https://learn.microsoft.com/en-us/azure/container-apps/compare-options)
