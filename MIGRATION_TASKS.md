# Container Apps移行作業タスク

## 概要
このドキュメントは、AKSベースからContainer Appsベースへの移行作業の実際のタスクリストです。

## 作業日時
開始: 2025-11-13

## タスク一覧

### ✅ タスク1: 移行タスクドキュメントの作成
**ステータス**: 完了
**説明**: このドキュメントを作成し、作業タスクを明確化する
**成果物**: MIGRATION_TASKS.md

---

### ⬜ タスク2: AKS関連ファイルの削除
**ステータス**: 未着手
**説明**: AKSクラスター関連のTerraformファイルを削除する
**対象ファイル**:
- `aks.tf`

**削除されるリソース**:
- `azurerm_subnet.aks`
- `azurerm_subnet_nat_gateway_association.aks`
- `azurerm_user_assigned_identity.aks`
- `azurerm_role_assignment.aks_network`
- `azurerm_kubernetes_cluster.this`
- `azurerm_role_assignment.aks_agic_integration`
- `azurerm_role_assignment.aks_agic_reader`
- `azurerm_role_assignment.aks_agic_contributor`
- `azurerm_role_assignment.agic_identity_operator`
- `azurerm_network_security_group.aks`
- `azurerm_subnet_network_security_group_association.aks`

**コマンド**:
```bash
rm aks.tf
```

---

### ⬜ タスク3: Application Gateway関連リソースの削除
**ステータス**: 未着手
**説明**: Application Gateway（とAGIC統合）を削除し、Container Appsのマネージドingressを使用
**対象ファイル**:
- `ingress.tf`

**削除されるリソース**:
- `azurerm_subnet.appgw`
- `azurerm_network_security_group.appgw`
- `azurerm_network_security_rule.*` (AppGW関連)
- `azurerm_subnet_network_security_group_association.appgw`
- `azurerm_user_assigned_identity.appgw`
- `azurerm_key_vault_access_policy.appgw`
- `azurerm_application_gateway.this`
- `azurerm_public_ip.appgw`
- `locals.ingress_values`

**コマンド**:
```bash
rm ingress.tf
```

---

### ⬜ タスク4: Kubernetes/Helm関連の削除
**ステータス**: 未着手
**説明**: langfuse.tfからKubernetes/Helm関連リソースを削除
**対象ファイル**:
- `langfuse.tf`

**削除する内容**:
- `locals.langfuse_values`
- `locals.encryption_values`
- `locals.additional_env_values`
- `kubernetes_namespace.langfuse`
- `kubernetes_secret.langfuse`
- `helm_release.langfuse`

**保持する内容**:
- `random_bytes.salt`
- `random_bytes.nextauth_secret`
- `random_bytes.encryption_key`

**注意**: このファイルは後でContainer App定義に置き換えられます

---

### ⬜ タスク5: Log Analytics Workspaceファイルの作成
**ステータス**: 未着手
**説明**: Container Apps環境に必須のLog Analytics Workspaceを作成
**新規作成ファイル**:
- `log_analytics.tf`

**作成されるリソース**:
- `azurerm_log_analytics_workspace.this`

**内容**:
```hcl
resource "azurerm_log_analytics_workspace" "this" {
  name                = module.naming.log_analytics_workspace.name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    application = local.tag_name
  }
}
```

---

### ⬜ タスク6: Container Apps用サブネット設定の追加
**ステータス**: 未着手
**説明**: Container Apps専用のサブネットをnetwork.tfに追加
**対象ファイル**:
- `network.tf`

**追加する内容**:
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

# Associate NAT Gateway with Container Apps subnet
resource "azurerm_subnet_nat_gateway_association" "container_apps" {
  subnet_id      = azurerm_subnet.container_apps.id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
```

---

### ⬜ タスク7: Container Appsリソースファイルの作成
**ステータス**: 未着手
**説明**: Container Apps EnvironmentとContainer Appを定義する新しいファイルを作成
**新規作成ファイル**:
- `container_apps.tf`

**作成されるリソース**:
- `azurerm_container_app_environment.this`
- `azurerm_container_app.langfuse`

**内容**: 詳細はMIGRATION_TO_CONTAINER_APPS.mdを参照

---

### ⬜ タスク8: variables.tfの更新
**ステータス**: 未着手
**説明**: AKS関連変数を削除し、Container Apps関連変数を追加

**削除する変数**:
- `aks_subnet_address_prefix`
- `app_gateway_subnet_address_prefix`
- `kubernetes_version`
- `aks_service_cidr`
- `aks_dns_service_ip`
- `node_pool_vm_size`
- `node_pool_min_count`
- `node_pool_max_count`
- `app_gateway_capacity`

**追加する変数**:
- `container_apps_subnet_address_prefix`
- `container_app_cpu`
- `container_app_memory`
- `container_app_min_replicas`
- `container_app_max_replicas`
- `langfuse_image_tag`

---

### ⬜ タスク9: outputs.tfの更新
**ステータス**: 未着手
**説明**: AKS関連のoutputを削除し、Container Apps関連のoutputを追加

**削除するoutput**:
- `cluster_name`
- `cluster_host`
- `cluster_client_certificate`
- `cluster_client_key`
- `cluster_ca_certificate`

**追加するoutput**:
- `container_app_fqdn`
- `container_app_url`
- `log_analytics_workspace_id`

---

### ⬜ タスク10: versions.tfの更新
**ステータス**: 未着手
**説明**: kubernetes、helmプロバイダーを削除

**削除するプロバイダー**:
```hcl
kubernetes = {
  source  = "hashicorp/kubernetes"
  version = ">= 2.10"
}
helm = {
  source  = "hashicorp/helm"
  version = ">= 2.5"
}
```

---

### ⬜ タスク11: naming.tfの確認と更新
**ステータス**: 未着手
**説明**: naming moduleがContainer Apps、Log Analyticsリソースに対応しているか確認

**確認項目**:
- `log_analytics_workspace`のnaming定義
- `container_app_environment`のnaming定義
- `container_app`のnaming定義（必要に応じて）

**対象ファイル**:
- `naming.tf`

---

### ⬜ タスク12: 変更内容のコミットとプッシュ
**ステータス**: 未着手
**説明**: すべての変更をコミットしてリモートにプッシュ

**コマンド**:
```bash
git add .
git commit -m "Migrate from AKS to Container Apps"
git push -u origin claude/terraform-creation-011CV6412rAHcUwF3iory4aw
```

---

## チェックリスト

- [ ] タスク1: 移行タスクドキュメントの作成
- [ ] タスク2: AKS関連ファイルの削除
- [ ] タスク3: Application Gateway関連リソースの削除
- [ ] タスク4: Kubernetes/Helm関連の削除
- [ ] タスク5: Log Analytics Workspaceファイルの作成
- [ ] タスク6: Container Apps用サブネット設定の追加
- [ ] タスク7: Container Appsリソースファイルの作成
- [ ] タスク8: variables.tfの更新
- [ ] タスク9: outputs.tfの更新
- [ ] タスク10: versions.tfの更新
- [ ] タスク11: naming.tfの確認と更新
- [ ] タスク12: 変更内容のコミットとプッシュ

## 注意事項

1. **バックアップ**: 既存のリソースをデプロイ済みの場合は、事前にバックアップを取得すること
2. **段階的移行**: 本番環境では、新環境を並行稼働させてからカットオーバーすることを推奨
3. **DNS設定**: カスタムドメインを使用する場合、Container Appへの切り替え時にDNS設定変更が必要
4. **コスト**: Container Appsは従量課金のため、スケーリング設定に注意

## 参考ドキュメント

- [MIGRATION_TO_CONTAINER_APPS.md](./MIGRATION_TO_CONTAINER_APPS.md) - 詳細な移行ガイド
- [Azure Container Apps documentation](https://learn.microsoft.com/azure/container-apps/)
