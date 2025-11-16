# ロールバック手順書

## 概要

ClickHouse専用コンテナへの移行で問題が発生した場合、動作確認済みのサイドカーパターンに戻すための手順書

**作成日**: 2025-11-16

---

## 🔖 動作確認済みの構成（ロールバック基準点）

### コミット情報

**コミットハッシュ**: `d3665e77194138135981049466af4665cecb3c89` (短縮形: `d3665e7`)

**Gitタグ**: `v2.2.0-stable`

**コミットメッセージ**: "Add persistent storage for ClickHouse data"

**日時**: 2025-11-16 12:43:54 UTC

**構成の特徴**:
- ClickHouseはサイドカーコンテナとしてLangfuse Container Appに同梱
- Azure File Share (50GB) で永続ストレージ実装済み
- 初期管理者ユーザー自動作成機能あり
- Localhost通信（認証なし）

### このコミットでの構成

```
Container App (Langfuse)
├── Container: langfuse (main)
│   ├── CPU: 0.5-1.0
│   └── Memory: 1-2Gi
└── Container: clickhouse (sidecar)
    ├── CPU: 1.0
    ├── Memory: 2Gi
    └── Volume: Azure File Share (50GB)
        └── Mount: /var/lib/clickhouse
```

**接続方法**:
- `CLICKHOUSE_URL`: `http://localhost:8123/default`
- `CLICKHOUSE_MIGRATION_URL`: `clickhouse://localhost:9000/default`

**月額コスト（開発環境）**: $41-77

**動作確認済み**:
- ✅ Langfuse起動成功
- ✅ ClickHouse接続成功
- ✅ データ永続化動作
- ✅ 初期管理者ユーザー作成

---

## 📋 ロールバックが必要なケース

以下の場合は、動作確認済みの構成に戻すことを推奨：

1. **専用コンテナでClickHouseが起動しない**
   - Container Appのステータスが`Failed`または`Running`にならない
   - イメージ取得エラー、リソース不足エラー

2. **Langfuseから接続できない**
   - `dial tcp: i/o timeout`
   - `connection refused`
   - Internal Ingress FQDNの解決失敗

3. **マイグレーション処理が失敗**
   - データベーススキーマのマイグレーションエラー
   - ClickHouseプロトコルの互換性問題（port 9000必須など）

4. **データが消失**
   - File Shareのマウント失敗
   - データの永続化が機能しない

5. **コストが予想より高い**
   - 専用コンテナ化によるコスト増加が許容範囲を超える

---

## 🔄 ロールバック方法

### Method 1: Gitリポジトリからのロールバック（推奨）

#### Step 1: コミット履歴を確認

```bash
# 現在のブランチとコミット履歴を確認
git log --oneline -10
```

#### Step 2: 動作確認済みコミットにチェックアウト

```bash
# 方法A: タグを使う（推奨）
git checkout v2.2.0-stable

# 方法B: コミットハッシュを使う
git checkout d3665e7
```

#### Step 3: Terraformで変更を適用

```bash
# 現在の状態を確認
terraform plan

# ロールバック実行
terraform apply
```

**所要時間**: 5-10分

#### Step 4: 動作確認

```bash
# Container Appの状態確認
az containerapp show \
  --name langfuse \
  --resource-group <rg-name> \
  --query "properties.runningStatus"

# ログ確認
az containerapp logs show \
  --name langfuse \
  --resource-group <rg-name> \
  --follow
```

期待される結果:
- ✅ `runningStatus`: "Running"
- ✅ ログにClickHouse接続成功メッセージ
- ✅ Langfuse UIにアクセス可能

---

### Method 2: ファイル単位での復元

専用コンテナ移行で変更されるファイルを手動で復元する方法

#### Step 1: 変更ファイルのリスト

移行で変更されるファイル:
- `container_apps.tf` - サイドカー削除、接続URL変更
- `clickhouse_dedicated.tf` - 新規作成（専用Container App）

#### Step 2: 動作確認済みの状態に復元

```bash
# container_apps.tfを復元
git checkout d3665e7 -- container_apps.tf

# clickhouse_dedicated.tfを削除（存在する場合）
rm -f clickhouse_dedicated.tf

# 変更内容を確認
git diff
```

#### Step 3: Terraformで適用

```bash
terraform plan
terraform apply
```

---

### Method 3: 新しいブランチでのロールバック

現在の変更を保持しながらロールバックする場合

#### Step 1: 現在の変更を新しいブランチに保存

```bash
# 現在の変更をコミット（まだの場合）
git add .
git commit -m "WIP: ClickHouse dedicated container migration attempt"

# 新しいブランチに移動
git checkout -b clickhouse-dedicated-attempt
git push -u origin clickhouse-dedicated-attempt
```

#### Step 2: メインブランチに戻る

```bash
# メインブランチに戻る
git checkout claude/terraform-creation-011CV6412rAHcUwF3iory4aw

# 動作確認済みコミットまでリセット
git reset --hard d3665e7
```

#### Step 3: Terraformで適用

```bash
terraform apply
```

これにより、試した変更は別ブランチに保存され、後で再度挑戦できます。

---

## 🧪 ロールバック後の検証

### 必須チェック項目

1. **Container Appの状態**
```bash
az containerapp show \
  --name langfuse \
  --resource-group <rg-name> \
  --query "{Status:properties.runningStatus,FQDN:properties.configuration.ingress.fqdn}"
```

期待値: `Status: "Running"`

2. **ClickHouseコンテナの存在確認**
```bash
az containerapp show \
  --name langfuse \
  --resource-group <rg-name> \
  --query "properties.template.containers[].name"
```

期待値: `["langfuse", "clickhouse"]`

3. **環境変数の確認**
```bash
az containerapp show \
  --name langfuse \
  --resource-group <rg-name> \
  --query "properties.template.containers[0].env[?name=='CLICKHOUSE_URL']"
```

期待値: `secret_name: "clickhouse-url"` (値: `http://localhost:8123/default`)

4. **ボリュームマウントの確認**
```bash
az containerapp show \
  --name langfuse \
  --resource-group <rg-name> \
  --query "properties.template.volumes"
```

期待値: `name: "clickhouse-data"`, `storage_type: "AzureFile"`

5. **Langfuse UIアクセステスト**
```bash
# Container App URLを取得
terraform output container_app_url

# ブラウザでアクセス
# https://<fqdn>
```

期待値: Langfuseのログイン画面が表示される

6. **初期管理者ユーザーでログイン**
```bash
# パスワード取得
terraform output -raw langfuse_admin_password
```

- Email: `admin@example.com`
- Password: 上記コマンドで取得したパスワード

期待値: ログイン成功、ダッシュボード表示

7. **データの永続性テスト**
```bash
# Container Appを再起動
az containerapp revision restart \
  --name langfuse \
  --resource-group <rg-name>

# 再起動後、データが残っているか確認
```

---

## 📊 ロールバック前後の比較

### 専用コンテナ構成（移行後）

| 項目 | 値 |
|-----|-----|
| Container App数 | 2個（Langfuse + ClickHouse） |
| ClickHouseレプリカ | 1固定 |
| 接続方法 | Internal Ingress (HTTPS) |
| データ一貫性 | ✅ 保証される |
| 月額コスト（2レプリカ時） | $20 |

### サイドカー構成（ロールバック後）

| 項目 | 値 |
|-----|-----|
| Container App数 | 1個（Langfuse） |
| ClickHouseレプリカ | Langfuseと同数 |
| 接続方法 | localhost |
| データ一貫性 | ⚠️ スケール時に問題あり |
| 月額コスト（2レプリカ時） | $30 |

---

## 🔍 トラブルシューティング

### 問題: ロールバック後もClickHouseが起動しない

**原因**: File Shareの状態が不整合

**対処**:
```bash
# File Shareの状態確認
az storage share show \
  --name clickhouse-data \
  --account-name <storage-account-name>

# 必要に応じてFile Shareを再作成
az storage share delete --name clickhouse-data --account-name <storage-account-name>
terraform apply  # File Shareが再作成される
```

### 問題: ロールバック後も接続エラー

**原因**: 環境変数のシークレット値が古い

**対処**:
```bash
# Revision履歴確認
az containerapp revision list \
  --name langfuse \
  --resource-group <rg-name> \
  --output table

# 最新Revisionをアクティブ化
az containerapp revision activate \
  --name langfuse \
  --resource-group <rg-name> \
  --revision <latest-revision-name>
```

### 問題: Terraform stateの不整合

**原因**: 手動でリソースを削除/変更した

**対処**:
```bash
# State確認
terraform state list

# State refresh
terraform refresh

# 必要に応じてimport
terraform import azurerm_container_app.langfuse /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/containerApps/langfuse
```

---

## 📝 ロールバック実施記録テンプレート

ロールバックを実施した場合、以下の情報を記録してください：

```markdown
## ロールバック実施記録

**実施日時**: YYYY-MM-DD HH:MM:SS
**実施者**:
**理由**:

### ロールバック前の状態
- コミットハッシュ:
- 問題の詳細:

### ロールバック方法
- [ ] Method 1: Gitリポジトリからのロールバック
- [ ] Method 2: ファイル単位での復元
- [ ] Method 3: 新しいブランチでのロールバック

### ロールバック後の確認
- [ ] Container App起動確認
- [ ] ClickHouseコンテナ確認
- [ ] 環境変数確認
- [ ] ボリュームマウント確認
- [ ] UI アクセス確認
- [ ] ログイン確認
- [ ] データ永続性確認

### 結果
- ステータス: 成功 / 失敗
- 備考:

### 次のアクション
- 専用コンテナ移行を再試行する場合の改善点:
  -
  -
```

---

## 🎯 再移行の検討事項

ロールバック後、専用コンテナ移行を再試行する場合の確認事項：

### 事前確認

1. **Langfuseの接続要件**
   - [ ] HTTPプロトコル（port 8123）のみで動作するか確認
   - [ ] ネイティブプロトコル（port 9000）が必須か確認
   - [ ] マイグレーション処理のプロトコル要件確認

2. **Container Apps機能**
   - [ ] Internal IngressのHTTP/HTTPSサポート確認
   - [ ] TCPプロトコルサポート状況確認
   - [ ] 同一Environment内のDNS解決確認

3. **データ移行計画**
   - [ ] 既存データのバックアップ
   - [ ] File Shareのスナップショット
   - [ ] ダウンタイム許容時間の確認

### 段階的な移行アプローチ

**Phase 1: テスト環境で検証**
- 別のContainer Apps Environmentでテスト
- 問題の早期発見

**Phase 2: 本番環境での並行稼働**
- 専用ClickHouseとサイドカーを両方稼働
- 徐々に切り替え

**Phase 3: 完全移行**
- サイドカー削除

---

## 📚 関連ドキュメント

- [CLICKHOUSE_MIGRATION_PLAN.md](./CLICKHOUSE_MIGRATION_PLAN.md) - 専用コンテナ移行計画
- [README.md](./README.md) - 全体アーキテクチャ
- [SETUP_GUIDE.md](./SETUP_GUIDE.md) - セットアップ手順

---

## 🆘 サポート

ロールバックで問題が発生した場合:

1. このドキュメントのトラブルシューティングセクションを確認
2. Container Appのログを詳細に確認
3. GitHubのIssuesで報告
4. Langfuse Discordで質問

---

**最終更新**: 2025-11-16
**ロールバック基準点**: `d3665e7` (Add persistent storage for ClickHouse data)
**ステータス**: 準備完了
