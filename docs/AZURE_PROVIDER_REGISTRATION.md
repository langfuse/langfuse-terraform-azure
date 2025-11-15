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

**provider_registration.tfを使用せず、Azureの自動登録に任せる**

### 理由：

1. **Azureの設計思想:**
   - プロバイダー登録は一度行えばサブスクリプション全体で有効
   - 登録解除する必要性はほとんどない
   - リソースを削除してもプロバイダー登録は残っても問題ない

2. **Terraformの制限:**
   - リソースの削除とプロバイダー登録の依存関係を正しく管理するのは困難
   - 削除順序を制御できても、Azureの非同期処理のため確実性がない

3. **実用性:**
   - プロバイダー登録自体にコストはかからない
   - 明示的に管理するメリットがほとんどない
   - terraform destroyでクリーンに削除できることの方が重要

### 実装方法：

**provider.tf:**
```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  # resource_provider_registrations設定なし
}
```

**provider_registration.tfは作成しない**

Azureが自動的に必要なプロバイダーを登録してくれます。

## まとめ

| アプローチ | terraform apply | terraform destroy | 推奨度 |
|-----------|-----------------|-------------------|--------|
| 明示的管理 + prevent_destroy | ✅ | ❌ | ❌ |
| 明示的管理のみ | ❌ (競合エラー) | ❌ (登録解除失敗) | ❌ |
| 自動登録 (デフォルト) | ✅ | ✅ | ✅ |

**結論:** provider_registration.tfを使用せず、Azureの自動登録機能を利用するのが最適です。
