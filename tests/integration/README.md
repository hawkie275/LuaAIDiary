# 統合テスト（Integration Tests）

このディレクトリには、モックを使用しない統合テストが含まれています。実際のデータベース（PostgreSQL）とRedisを使用してテストを実行します。

## 概要

統合テストは以下の特徴を持ちます：

- **実際のデータベース接続**: テスト環境のPostgreSQLに接続
- **実際のコード実行パス**: モックを使わずに実際のモデルとビジネスロジックをテスト
- **トランザクション管理**: 各テストはトランザクション内で実行され、終了時にロールバック
- **データクリーンアップ**: テストデータは自動的にクリーンアップされる

## 実装済みテスト

### 1. 投稿モデル統合テスト (`test_post_model_integration_spec.lua`)

実際のデータベースを使用して、以下の機能をテストします：

#### 投稿作成
- ✅ 基本的な投稿作成
- ✅ スラッグの自動生成
- ✅ カテゴリーとタグの関連付け
- ✅ 公開ステータスでの公開日時設定
- ✅ バリデーションエラー処理

#### 投稿取得
- ✅ スラッグによる検索
- ✅ 公開済み投稿のみの取得
- ✅ ページネーション（limit/offset）

#### 投稿更新
- ✅ 投稿情報の更新
- ✅ ステータス変更時の公開日時設定
- ✅ 存在しない投稿のエラー処理

#### カテゴリー・タグ管理
- ✅ カテゴリーの追加
- ✅ タグの追加
- ✅ カテゴリーの同期（置き換え）
- ✅ カテゴリーとタグの取得

#### トランザクション
- ✅ 複数操作の原子性確保（投稿とカテゴリーの同時作成）

## テストの実行方法

### 前提条件

1. **サービスの起動**: Docker Composeでサービスが起動している必要があります
   ```bash
   make up
   ```

2. **データベース接続**: PostgreSQLが正常に動作していること
   ```bash
   make health
   ```

### 統合テストの実行

```bash
# 統合テストのみを実行
make test-integration

# または直接bustedを使用
docker-compose exec -w /app web sh -c "LUA_PATH='/app/?.lua;/app/?/init.lua;;' busted /tests/integration/"
```

### すべてのテストを実行

```bash
# ユニット、統合、E2Eすべてのテストを実行
make test-all
```

## テストヘルパー (`test_helper_integration.lua`)

統合テスト用のヘルパー関数を提供します：

### データベース管理
- `setup_db()` - データベース接続を確立
- `teardown_db(db)` - データベース接続を閉じる
- `begin_transaction(db)` - トランザクションを開始
- `rollback_transaction(db)` - トランザクションをロールバック
- `commit_transaction(db)` - トランザクションをコミット

### テストデータ作成
- `create_test_user(db, username, email)` - テストユーザーを作成
- `create_test_post(db, user_id, title, content)` - テスト投稿を作成
- `create_test_category(db, name)` - テストカテゴリーを作成
- `create_test_tag(db, name)` - テストタグを作成
- `clean_test_data(db)` - TEST_プレフィックスのデータを削除

### アサーション
- `assert_not_nil(value, message)` - 値がnilでないことを確認
- `assert_equal(expected, actual, message)` - 値の等価性を確認
- `assert_true(value, message)` - 値がtrueであることを確認
- `assert_false(value, message)` - 値がfalseであることを確認
- `assert_table_has_key(tbl, key, message)` - テーブルにキーが存在することを確認
- `assert_greater_than(actual, expected, message)` - 値の大小関係を確認

## テスト戦略

### トランザクション分離

各テストは独自のトランザクション内で実行され、テスト終了時に自動的にロールバックされます：

```lua
before_each(function()
  db = helper.setup_db()
  helper.begin_transaction(db)
  -- テストデータ作成
end)

after_each(function()
  helper.rollback_transaction(db)  -- 自動ロールバック
  helper.teardown_db(db)
end)
```

これにより、テスト間の干渉を防ぎ、データベースをクリーンな状態に保ちます。

### テストデータの命名規則

テストデータは `TEST_` または `test_` プレフィックスを使用して識別します：

- 投稿: `TEST_投稿タイトル`
- ユーザー: `test_user_12345`
- カテゴリー: `TEST_CATEGORY_12345`
- タグ: `TEST_TAG_12345`

これにより、本番データと明確に区別でき、クリーンアップも容易になります。

## 技術的な制約と課題

### 実装できている機能

1. ✅ **実際のデータベース接続**: pgmoonを使用した直接的なDB接続
2. ✅ **トランザクション管理**: BEGIN/COMMIT/ROLLBACKによる適切な分離
3. ✅ **モデル層のテスト**: 実際のモデルコードを実行
4. ✅ **リレーションのテスト**: カテゴリー・タグの関連付けをテスト
5. ✅ **データクリーンアップ**: トランザクションロールバックによる自動クリーンアップ

### 技術的な制約

1. **OpenRestyコンテキストの制限**
   - `ngx.*` APIの一部はテスト環境で利用不可
   - `ngx.quote_sql_str` などはモック実装が必要
   - 解決策: test_helper内でngxモックを提供

2. **セッション管理のテスト**
   - Redisベースのセッションは別途E2Eテストで検証
   - 統合テストではモデル層に焦点を当てる

3. **HTTPリクエストのテスト**
   - コントローラー層のHTTP関連は統合テストでは困難
   - 解決策: E2Eテストで補完（`tests/e2e/`）

### 制約への対処

- **モデル層**: 統合テスト（このディレクトリ）
- **コントローラー層**: モックベーステスト（`tests/controllers/`）
- **エンドツーエンド**: HTTP E2Eテスト（`tests/e2e/`）

この3層のテスト戦略により、モックを使わない部分と使う部分を適切に分離しています。

## E2Eテストとの違い

| 項目 | 統合テスト | E2Eテスト |
|------|-----------|----------|
| 対象 | モデル層、ビジネスロジック | API全体（HTTP経由） |
| 接続 | 直接DB接続 | HTTP経由 |
| 環境 | Busted + pgmoon | curl/HTTPクライアント |
| 認証 | モックまたは直接DB | 実際のセッション |
| 速度 | 高速 | やや低速 |
| 範囲 | 狭い（モデルのみ） | 広い（全レイヤー） |

## ベストプラクティス

1. **テストの独立性**: 各テストは他のテストに依存しない
2. **トランザクション使用**: データの自動クリーンアップ
3. **明確な命名**: テストデータは識別可能な名前を使用
4. **アサーションの明確化**: エラーメッセージを含める
5. **before_each/after_each**: 一貫したセットアップとクリーンアップ

## 今後の拡張

以下のテストを追加できます：

- [ ] ユーザーモデルの統合テスト
- [ ] カテゴリーモデルの統合テスト
- [ ] タグモデルの統合テスト
- [ ] コメントモデルの統合テスト
- [ ] 複雑なクエリのパフォーマンステスト
- [ ] 並行処理のテスト

## トラブルシューティング

### データベース接続エラー

```bash
# データベースの状態を確認
make status
docker-compose ps

# データベースログを確認
make logs-db

# データベースに直接接続してテスト
make psql
```

### テストデータが残っている場合

```bash
# TEST_プレフィックスのデータを削除
make psql
DELETE FROM posts WHERE title LIKE 'TEST_%';
DELETE FROM users WHERE username LIKE 'test_%';
DELETE FROM categories WHERE name LIKE 'TEST_%';
DELETE FROM tags WHERE name LIKE 'TEST_%';
```

### pgmoonが見つからない

```bash
# Webコンテナを再ビルド
make build
make up
```

## 参考資料

- [Busted Testing Framework](https://olivinelabs.com/busted/)
- [pgmoon - PostgreSQL driver for Lua](https://github.com/leafo/pgmoon)
- [LuaRocks - Package manager](https://luarocks.org/)
