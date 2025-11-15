# Azure Provider Registration Issues in Terraform

## 問題の概要

Terraformで`azurerm_resource_provider_registration`リソースを使用すると、以下の2つの競合する問題が発生します：

### 1. Apply時の問題：自動登録との競合

**エラー内容:**
```
Error: The Resource Provider "Microsoft.Storage" is automatically registered by Terraform.
To manage this Resource Provider registration with the "azurerm_resource_provider_registration" resource,
you need to prevent Terraform from managing this Resource Provider automatically
```

**原因:**
- azurerm providerはデフォルトでリソースプロバイダーを自動登録する
- 明示的に`azurerm_resource_provider_registration`リソースを使うと競合する

**解決策:**
```hcl
provider "azurerm" {
  features {}
  resource_provider_registrations = "none"  # 自動登録を無効化
}
```

### 2. Destroy時の問題：登録解除ができない

**エラー内容:**
```
Error: unregistering Resource Provider: The subscription cannot be unregistered from resource namespace
'Microsoft.Network'. Please delete existing resources for the provider.
```

**原因:**
- terraform destroyでプロバイダー登録を解除しようとする
- しかしAzureでは、リソースが削除された後もプロバイダーの登録は残る仕様
- 非同期的な削除処理により、Terraformがリソース削除を確認するタイミングとAzure側の実際の削除完了タイミングにズレがある

**試した解決策と結果:**

#### A. lifecycle { prevent_destroy = true } を設定
```hcl
resource "azurerm_resource_provider_registration" "app" {
  name = "Microsoft.App"
  lifecycle {
    prevent_destroy = true
  }
}
```

**結果:** ❌ terraform destroyが失敗
```
Error: Instance cannot be destroyed
Resource azurerm_resource_provider_registration.app has lifecycle.prevent_destroy set,
but the plan calls for this resource to be destroyed.
```

#### B. provider_registration.tfを削除して自動登録に戻す
```hcl
provider "azurerm" {
  features {}
  # resource_provider_registrations設定なし（デフォルト動作）
}
```

**結果:** ✅ これが推奨される方法

## 推奨される解決策

**terraform stateからプロバイダー登録リソースを削除して、管理対象外にする**

### 理由：

1. **Terraformでのプロバイダー登録管理は困難:**
   - 自動登録: apply時に競合エラー
   - 明示的管理: destroy時に登録解除エラー
   - prevent_destroy: destroy時に削除禁止エラー
   - **どの方法も完全には機能しない**

2. **Azureの設計思想:**
   - プロバイダー登録は一度行えばサブスクリプション全体で有効
   - 登録解除する必要性はほとんどない
   - リソースを削除してもプロバイダー登録は残っても問題ない
   - **Terraformで管理する必要がない**

3. **実用性:**
   - プロバイダー登録自体にコストはかからない
   - terraform destroyでクリーンに削除できることの方が重要

### 実装手順：

#### 1. terraform stateからプロバイダー登録リソースを削除

```bash
terraform state rm azurerm_resource_provider_registration.app
terraform state rm azurerm_resource_provider_registration.storage
terraform state rm azurerm_resource_provider_registration.dbforpostgresql
terraform state rm azurerm_resource_provider_registration.cache
terraform state rm azurerm_resource_provider_registration.network
terraform state rm azurerm_resource_provider_registration.operationalinsights
```

これにより：
- Terraformの管理対象から除外される
- Azure側のプロバイダー登録は残る（必要）
- 今後のterraform applyやdestroyに影響しない

#### 2. provider_registration.tfを削除

```bash
rm provider_registration.tf
```

#### 3. provider.tfから設定を削除

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # resource_provider_registrations設定を削除
}
```

#### 4. container_apps.tfのdepends_onを更新

```hcl
depends_on = [
  azurerm_subnet.container_apps
  # azurerm_resource_provider_registration.appの参照を削除
]
```

### 今後の動作：

- Azure側でプロバイダーは既に登録されているため、新規リソース作成時も問題なし
- terraform destroyは正常に動作する
- 新しいプロバイダーが必要になった場合、Azureポータルまたはazコマンドで手動登録

## まとめ

| アプローチ | terraform apply | terraform destroy | 推奨度 |
|-----------|-----------------|-------------------|--------|
| 自動登録 (デフォルト) | ❌ (競合エラー) | - | ❌ |
| 明示的管理のみ | ❌ (競合エラー) | ❌ (登録解除失敗) | ❌ |
| 明示的管理 + prevent_destroy | ✅ | ❌ (削除禁止) | ❌ |
| **stateから削除して管理対象外** | ✅ | ✅ | ✅ |

**結論:** プロバイダー登録はTerraformで管理せず、Azure側に任せるのが最適です。
