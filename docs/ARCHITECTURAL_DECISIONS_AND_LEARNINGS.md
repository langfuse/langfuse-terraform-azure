# Architectural Decisions and Learnings (Langfuse on Azure Container Apps)

このドキュメントは、Langfuse と ClickHouse を Azure Container Apps (ACA) に構築する過程で得られた技術的な知見、発生した問題、および最終的なアーキテクチャの決定理由をまとめたものです。
AI アシスタントが今後のメンテナンスやトラブルシューティングを行う際のコンテキストとして活用することを想定しています。

## 1. 最終アーキテクチャ (Final Architecture)

**構成:** Internal Environment + Application Gateway (Best Practice)

*   **Environment**: `internal = true` (VNet 統合、外部公開なし)
*   **Ingress**:
    *   **Langfuse**: Application Gateway 経由で HTTP (80) を受信。
    *   **ClickHouse**: VNet 内部からの **TCP (9000) + HTTP (8123)**。TCP は migration 用、HTTP はデータアクセス用。
*   **Storage**: Azure Files NFS (Premium)

この構成により、ClickHouse を安全に VNet 内に閉じ込めつつ、Langfuse をインターネットに公開し、かつ両者間の安定した内部通信を実現しています。

---

## 2. トラブルシューティングと技術的決定 (Troubleshooting & Decisions)

### 2.1 ストレージ: Azure Files SMB vs NFS

*   **課題**: 当初、Azure Files (SMB) を使用したが、ClickHouse コンテナ起動時に `Operation not permitted` (chmod/chown 失敗) エラーが発生。
*   **原因**: Azure Files SMB は POSIX 準拠のパーミッション管理を完全にはサポートしていないため、ClickHouse のような DB がデータディレクトリの権限を変更しようとすると失敗する。
*   **解決策**: **Azure Files NFS (Premium)** を採用。
    *   NFS は POSIX 準拠の権限管理が可能。
    *   `azapi_resource` を使用して `Microsoft.App/managedEnvironments/storages` としてマウント定義を作成。

### 2.2 ネットワーク: VNet 統合とサブネット委任

*   **課題**: `external = true` (外部公開) な Environment で VNet 統合を行おうとした際、内部通信 (Langfuse -> ClickHouse) が `i/o timeout` で失敗。
    *   また、サブネット委任 (`Microsoft.App/environments`) を設定するとデプロイ時に `ManagedEnvironmentSubnetIsDelegated` エラーが発生するケースがあった。
*   **原因**:
    *   ACA の `Consumption` プランや特定の API バージョンにおいて、外部公開 Environment と VNet 統合の組み合わせには制約や挙動の不安定さがある（NAT Gateway が必須になるケースなど）。
    *   委任エラーは、Environment の作成モードとサブネット設定の不整合によるもの。
*   **解決策**: **Internal Environment (`internal = true`)** への切り替え。
    *   完全閉域にすることで VNet 統合が標準動作となり、安定する。
    *   外部アクセスは **Application Gateway** を前段に置くことで解決。

### 2.3 ClickHouse: IPv4 バインディング

*   **課題**: ClickHouse が起動しても、`127.0.0.1` や VNet IP で接続できない。ログには `Address already in use: 0.0.0.0:9000` の警告。
*   **原因**: ClickHouse がデフォルトで IPv6 (`::`) にバインドしようとし、IPv4 と競合または正しくリッスンできていなかった。
*   **解決策**: カスタム `listen.xml` をマウントし、`<listen_host>0.0.0.0</listen_host>` を明示的に設定して IPv4 でのリッスンを強制。

### 2.4 Terraform: Provider の制約と回避策

*   **課題**: `azurerm` プロバイダでは ACA の最新機能（NFS マウントの詳細設定や特定の Ingress 設定）がサポートされていない、または挙動が怪しい場合があった。
*   **解決策**: **`azapi` プロバイダ** の活用。
    *   `azapi_resource` や `azapi_update_resource` を使用して、ARM テンプレートレベルでリソースを定義・パッチ適用。
    *   特に Environment の `vnetConfiguration` や `appLogsConfiguration` の詳細制御に有効。

### 2.5 デッドロック: ManagedEnvironmentStorageDeleteInUse

*   **課題**: `terraform destroy` や Environment の再作成時に、`Cannot delete ... because it's still in use` エラーが発生。
*   **原因**: Container App が起動している状態で、紐付いている Environment Storage (NFS設定) を削除しようとするとロックがかかる。
*   **解決策**: アプリ (`azurerm_container_app`) を先に削除 (`terraform destroy -target=...`) してから、Environment を削除する手順が必要。

### 2.6 Container Apps 間通信: TCP Ingress の設定

*   **課題**: Internal Environment で ClickHouse を別 Container App として配置し、TCP Ingress (port 9000) で公開したが、Langfuse から接続すると `dial tcp <ip>:9000: i/o timeout` が発生。
    *   DNS 解決は成功し、IP アドレスに解決されるが、TCP 接続がタイムアウトする。
    *   サイドカー構成では同じ設定で動作していた。
*   **原因**: TCP Ingress の設定が不完全だった可能性。
    *   `exposed_port` の明示的設定が必要。
    *   `additionalPortMappings` を使用する場合は `azapi_update_resource` で設定。
*   **解決策**: **TCP (9000) を primary、HTTP (8123) を additionalPortMappings で設定**。
    *   Langfuse は `CLICKHOUSE_MIGRATION_URL` に TCP (9000)、`CLICKHOUSE_URL` に HTTP (8123) を必要とする。
    *   Internal Environment 内では、短い名前 (`<app-name>:<exposed_port>`) で他の Container App にアクセス可能。

### 2.7 Langfuse の ClickHouse 接続要件

*   **要件**: Langfuse は 2 つの異なるプロトコルで ClickHouse に接続する。
    *   `CLICKHOUSE_URL`: HTTP (8123) - データアクセス用
    *   `CLICKHOUSE_MIGRATION_URL`: Native TCP (9000) - マイグレーション用
*   **参考**: [Langfuse ClickHouse Documentation](https://langfuse.com/self-hosting/infrastructure/clickhouse)
*   **注意**: HTTP-only 動作は現時点でサポートされていない ([Discussion #5458](https://github.com/orgs/langfuse/discussions/5458))

### 2.8 Application Gateway と Internal Environment の DNS 解決

*   **課題**: Application Gateway のバックエンドヘルスが `Unknown` になり、「FQDN configured in the backend pool could not be resolved to an IP address」エラーが発生。
*   **原因**: Internal Container Apps Environment の FQDN (`*.{unique-id}.{region}.azurecontainerapps.io`) は、VNet 内から DNS 解決できない。
    *   Internal Environment は自動的に Private DNS Zone を作成しないため、手動で設定が必要。
*   **解決策**: **Private DNS Zone を作成し、VNet にリンク**。
    *   Private DNS Zone 名: Environment の `defaultDomain` (`{unique-id}.{region}.azurecontainerapps.io`)
    *   ワイルドカード A レコード (`*`): Environment の `staticIp` を指す
    *   VNet リンク: Application Gateway を含む VNet にリンク
*   **Terraform 実装**:
    ```hcl
    resource "azurerm_private_dns_zone" "container_apps" {
      name = azapi_resource.container_app_environment.output.properties.defaultDomain
      ...
    }
    resource "azurerm_private_dns_a_record" "container_apps_wildcard" {
      name    = "*"
      records = [azapi_resource.container_app_environment.output.properties.staticIp]
      ...
    }
    ```
*   **参考**: [Protect Azure Container Apps with Application Gateway and WAF](https://learn.microsoft.com/en-us/azure/container-apps/waf-app-gateway)

---

## 3. 今後のメンテナンスへの推奨 (Recommendations)

1.  **API バージョン**: ACA は進化が早いため、`azapi` で使用する `apiVersion` は定期的に見直すこと（現在は `2024-03-01` を使用）。
2.  **Ingress**: TCP Ingress を使用する場合は `exposed_port` を明示的に設定すること。複数ポートは `additionalPortMappings` で設定。
3.  **内部通信**: Internal Environment 内では、短い名前 (`<app-name>:<exposed_port>`) で他の Container App にアクセス可能。FQDN よりも短い名前を推奨。
4.  **Private DNS Zone**: Internal Environment を Application Gateway と組み合わせる場合、Private DNS Zone の設定が必須。Environment の `defaultDomain` と `staticIp` を使用してワイルドカード A レコードを作成。
5.  **デバッグ**: 接続問題が発生した場合、一時的に `external_enabled = true` にして外部から `curl` で疎通確認を行う切り分けが有効。

