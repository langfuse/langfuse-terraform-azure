# Azure Langfuse セットアップガイド

このガイドでは、Azureアカウントを新規作成してから、TerraformでLangfuseをデプロイするまでの全手順を説明します。

## 前提条件

- クレジットカード（Azure アカウント作成に必要）
- メールアドレス
- ドメイン（カスタムドメインを使用する場合）

---

## ステップ1: Azureアカウントの作成

### 1.1 Azureアカウントの登録

1. [Azure公式サイト](https://azure.microsoft.com/)にアクセス
2. 「無料で始める」または「無料アカウント」をクリック
3. Microsoftアカウントでサインイン（持っていない場合は新規作成）
4. 以下の情報を入力：
   - 国/地域
   - 名前
   - 電話番号（SMS認証）
   - クレジットカード情報（本人確認用、無料枠内は課金されない）

5. 利用規約に同意してアカウント作成完了

### 1.2 無料クレジット

- 初回登録で$200の無料クレジット（30日間有効）
- 12ヶ月間の無料サービス
- 常時無料のサービス

> **注意**: 無料期間終了後は自動的に従量課金に移行します。予算アラートの設定を推奨します。

---

## ステップ2: Azure CLIのインストール

### 2.1 インストール

#### macOS
```bash
brew update && brew install azure-cli
```

#### Windows
[Azure CLI インストーラー](https://aka.ms/installazurecliwindows)をダウンロードして実行

#### Linux (Ubuntu/Debian)
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### 2.2 インストール確認

```bash
az --version
```

### 2.3 Azureにログイン

```bash
az login
```

ブラウザが開くので、Azureアカウントでサインインします。

### 2.4 サブスクリプションの確認

```bash
az account list --output table
```

複数のサブスクリプションがある場合は、使用するものを設定：

```bash
az account set --subscription "サブスクリプション名またはID"
```

### 2.5 現在のアカウント情報確認

```bash
az account show
```

---

## ステップ3: Terraformのインストール

### 3.1 インストール

#### macOS
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

#### Windows
1. [Terraform公式サイト](https://www.terraform.io/downloads)からダウンロード
2. ZIPを解凍してPATHに追加

#### Linux
```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

### 3.2 インストール確認

```bash
terraform --version
```

最低バージョン: `>= 1.0`

---

## ステップ4: 必要な権限の設定

### 4.1 サービスプリンシパルの作成（推奨）

本番環境では、サービスプリンシパルを使用することを推奨します。

```bash
# サービスプリンシパルの作成
az ad sp create-for-rbac --name "langfuse-terraform" --role Contributor --scopes /subscriptions/<SUBSCRIPTION_ID>
```

出力された情報を保存：
- `appId` → `ARM_CLIENT_ID`
- `password` → `ARM_CLIENT_SECRET`
- `tenant` → `ARM_TENANT_ID`

### 4.2 環境変数の設定

#### macOS/Linux
```bash
export ARM_CLIENT_ID="<appId>"
export ARM_CLIENT_SECRET="<password>"
export ARM_TENANT_ID="<tenant>"
export ARM_SUBSCRIPTION_ID="<subscription_id>"
```

#### Windows (PowerShell)
```powershell
$env:ARM_CLIENT_ID="<appId>"
$env:ARM_CLIENT_SECRET="<password>"
$env:ARM_TENANT_ID="<tenant>"
$env:ARM_SUBSCRIPTION_ID="<subscription_id>"
```

> **重要**: これらの認証情報は安全に管理してください。

---

## ステップ5: プロジェクトのセットアップ

### 5.1 リポジトリのクローン

```bash
git clone https://github.com/langfuse/langfuse-terraform-azure.git
cd langfuse-terraform-azure
```

### 5.2 設定ファイルの作成

`terraform.tfvars` を作成（推奨）：

```hcl
# 基本設定
location = "japaneast"
name     = "langfuse-dev"

# オプション: カスタムドメイン（不要な場合はコメントアウト）
# domain = "langfuse.example.com"

# Container Apps設定（開発環境向け）
container_app_cpu          = 0.5
container_app_memory       = 1
container_app_min_replicas = 0  # スケールtoゼロ
container_app_max_replicas = 3
langfuse_image_tag        = "2"

# データベース設定（開発環境向け）
postgres_instance_count = 1  # HAなし
postgres_sku_name      = "B_Standard_B1ms"
postgres_storage_mb    = 32768

# Redis設定（開発環境向け）
redis_sku_name = "Basic"
redis_family   = "C"
redis_capacity = 0

# セキュリティ設定
use_encryption_key  = true
use_ddos_protection = false  # 開発環境では無効化してコスト削減

# オプション: 追加の環境変数
additional_env = []
```

**注意**: `terraform.tfvars` は既存のファイル（`*.tf`）とともに使用されます。`main.tf` を新規作成する必要は**ありません**。

**上記の設定で月額 $20-40 になります。**

---

## ステップ6: Terraformの実行

### 6.1 初期化

```bash
terraform init
```

これにより、必要なプロバイダーとモジュールがダウンロードされます。

### 6.2 プランの確認

```bash
terraform plan
```

作成されるリソースを確認します。問題がなければ次へ進みます。

### 6.3 適用

```bash
terraform apply
```

`yes` と入力して実行します。

**所要時間**: 約10-20分

### 6.4 デプロイの進行状況

以下のリソースが順番に作成されます：

1. リソースグループ
2. Virtual Network、サブネット
3. PostgreSQL、Redis、Storage Account
4. Private Endpoint、Private DNS Zone
5. Log Analytics Workspace
6. Container Apps Environment
7. Container App（Langfuse）

---

## ステップ7: デプロイ完了後の確認

### 7.1 Container AppのURLを確認

```bash
terraform output container_app_url
```

### 7.2 動作確認

ブラウザで以下にアクセス：

```
https://<container-app-fqdn>
```

> **注意**: カスタムドメインを使用する場合は、DNS伝播完了後にアクセスしてください。

### 7.3 初期セットアップ

1. 管理者アカウントの作成
2. プロジェクトの作成
3. APIキーの生成

---

## ステップ8: コストの監視と管理

### 8.1 予算アラートの設定

Azureポータルで予算アラートを設定することを強く推奨します。

1. Azureポータルにログイン
2. 「Cost Management + Billing」を開く
3. 「Budgets」から新規予算を作成
4. アラートのしきい値を設定（例: $50, $100）

### 8.2 コスト分析

```bash
# Azure CLIでコスト確認
az consumption usage list --start-date 2025-11-01 --end-date 2025-11-30
```

### 8.3 主なコスト要因

Container Apps版の場合：

| リソース | 月額概算（開発環境） | 月額概算（本番環境） |
|---------|-------------------|-------------------|
| Container Apps | $5-20 | $50-200 |
| PostgreSQL | $10-30 | $100-300 |
| Redis | $15 | $50-100 |
| Storage Account | $5 | $20 |
| Log Analytics | $5 | $20-50 |
| **合計** | **$40-85** | **$240-670** |

> **注意**: 実際のコストは使用量により変動します。この構成ではNAT Gateway、DNS Zone、Key Vaultは含まれていません（開発環境向け最適化）。

---

## ステップ9: トラブルシューティング

### 9.1 よくあるエラー

#### エラー: "Subscription is not registered"

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.Cache
```

登録完了まで数分待ってから再実行。

#### エラー: "Quota exceeded"

Azureの無料アカウントには制限があります。制限の確認：

```bash
az vm list-usage --location japaneast --output table
```

サポートに連絡して制限の引き上げをリクエストできます。

#### エラー: "Subnet delegation failed"

Container Appsのサブネットには特定の委任設定が必要です。`network.tf`を確認してください。

### 9.2 デバッグ

#### Terraformログの有効化

```bash
export TF_LOG=DEBUG
terraform apply
```

#### Container Appのログ確認

```bash
# Azure CLI経由
az containerapp logs show \
  --name langfuse \
  --resource-group <resource-group-name> \
  --follow

# または Azure Portal で確認
```

#### データベース接続テスト

Container App環境からデータベースへの接続は、Private Endpointを通じて自動的に行われます。接続エラーが発生した場合は、Log Analyticsでアプリケーションログを確認してください。

### 9.3 リソースのクリーンアップ

テストが終わったらリソースを削除してコストを節約：

```bash
terraform destroy
```

`yes` と入力して削除を確認します。

---

## ステップ10: 本番環境への移行

### 10.1 本番環境用の設定

`production.tfvars` ファイルを作成：

```hcl
domain   = "langfuse.yourcompany.com"
location = "japaneast"
name     = "langfuse-prod"

# 本番環境向けスペック
container_app_cpu          = 2.0
container_app_memory       = 4
container_app_min_replicas = 2
container_app_max_replicas = 20

postgres_instance_count = 2
postgres_ha_mode       = "ZoneRedundant"
postgres_sku_name      = "GP_Standard_D4s_v3"
postgres_storage_mb    = 131072

redis_sku_name = "Standard"
redis_family   = "C"
redis_capacity = 1

use_encryption_key  = true
use_ddos_protection = true
```

適用：

```bash
terraform apply -var-file="production.tfvars"
```

### 10.2 バックアップの設定

PostgreSQLは自動的に7日間のバックアップを保持します。追加のバックアップ設定：

```bash
# Azure Backup の設定
az backup vault create --resource-group <rg-name> --name langfuse-backup --location japaneast
```

### 10.3 監視とアラート

Azure Monitorでアラートを設定：

- Container Appのエラー率
- データベースのCPU使用率
- メモリ使用率
- レスポンスタイム

---

## 付録A: リージョンの選択

推奨リージョン（日本から利用する場合）：

| リージョン | 場所 | レイテンシ | 備考 |
|----------|------|----------|------|
| japaneast | 東京 | 最低 | 推奨 |
| japanwest | 大阪 | 低 | DR用 |
| koreacentral | ソウル | 低 | - |
| southeastasia | シンガポール | 中 | - |

全リージョン確認：

```bash
az account list-locations --output table
```

---

## 付録B: セキュリティベストプラクティス

1. **最小権限の原則**: サービスプリンシパルには必要最小限の権限のみ付与
2. **シークレット管理**: Azure Key Vaultで管理（Terraformの外で）
3. **ネットワーク分離**: Private Endpointを使用（デフォルトで有効）
4. **TLS/SSL**: 必須（Container Appsで自動設定）
5. **監査ログ**: Azure Monitorで記録
6. **定期的な更新**: Langfuseイメージとモジュールの更新

---

## 付録C: 参考リンク

- [Azure公式ドキュメント](https://docs.microsoft.com/azure/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/)
- [Langfuse公式ドキュメント](https://langfuse.com/docs)
- [Langfuse Self-hosting](https://langfuse.com/docs/deployment/self-host)

---

## サポート

問題が発生した場合：

1. このドキュメントのトラブルシューティングセクションを確認
2. [GitHubのIssues](https://github.com/langfuse/langfuse-terraform-azure/issues)を検索
3. [Langfuse Discord](https://langfuse.com/discord)でコミュニティに質問
4. 新しいIssueを作成

---

## 次のステップ

デプロイが完了したら：

1. [Langfuse ドキュメント](https://langfuse.com/docs)でLangfuseの使い方を学ぶ
2. アプリケーションとの統合を設定
3. チームメンバーを招待
4. 本番環境へのデプロイを計画

---

**最終更新**: 2025-11-13
**対象バージョン**: Container Apps版
