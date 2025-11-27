# Architectural Decisions and Learnings (Langfuse on Azure Container Apps)

このドキュメントは、Langfuse と ClickHouse を Azure Container Apps (ACA) に構築する過程で得られた技術的な知見、発生した問題、および最終的なアーキテクチャの決定理由をまとめたものです。
AI アシスタントが今後のメンテナンスやトラブルシューティングを行う際のコンテキストとして活用することを想定しています。

## 1. 最終アーキテクチャ (Final Architecture)

**構成:** Internal Environment + Application Gateway (Best Practice)

*   **Environment**: `internal = true` (VNet 統合、外部公開なし)
*   **Ingress**:
    *   **Langfuse**: Application Gateway 経由で HTTP (80) を受信。
    *   **ClickHouse**: VNet 内部からの TCP (9000) / HTTP (8123) のみ許可。
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

---

## 3. 今後のメンテナンスへの推奨 (Recommendations)

1.  **API バージョン**: ACA は進化が早いため、`azapi` で使用する `apiVersion` は定期的に見直すこと（現在は `2024-03-01` を使用）。
2.  **Ingress**: ClickHouse のネイティブプロトコル (9000) は TCP なので、Ingress 設定時は `transport = "tcp"` を明示すること。
3.  **デバッグ**: 接続問題が発生した場合、一時的に `external_enabled = true` にして外部から `curl` で疎通確認を行う切り分けが有効。

