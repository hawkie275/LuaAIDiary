# テスト方針（E2E中心 + Mock適用境界）

最終更新: 2026-02-21

## 1. 現在方針（運用ルール）

- [`make test`](../Makefile:107) は **E2Eテストのみ** を実行する。
  - 実体は [`make test-e2e`](../Makefile:118) の呼び出し。
  - [`Makefile`](../Makefile:107) 上で `test` ターゲットはE2Eに委譲されている。

## 2. Mockテストを導入・維持する意義

E2E中心運用と矛盾せず、以下の目的でMockテストを併用する。

1. 外部依存の切り離し
   - DB/Redis/外部API/ファイルI/O等の不安定要因を分離し、ロジック検証を高速化できる。
2. 異常系の再現性
   - 実環境で再現しにくいタイムアウト・接続失敗・不正レスポンス等を、意図的に再現しやすい。
3. AI開発ループとの相性
   - 小さな変更を短サイクルで検証しやすく、失敗原因の切り分けが容易。

## 3. OpenResty / Lua（`ngx`依存）での注意点

- コントローラー/ミドルウェアは `ngx` コンテキストに強く依存するため、ユニット系では `_G.ngx` の差し替えが実質必要。
  - 例: [`tests/controllers/test_admin_controller_spec.lua`](../tests/controllers/test_admin_controller_spec.lua)
  - 例: [`tests/controllers/test_post_controller_spec.lua`](../tests/controllers/test_post_controller_spec.lua)
  - 例: [`tests/middleware/test_csrf_spec.lua`](../tests/middleware/test_csrf_spec.lua)
- `package.preload`/`package.loaded` を使った差し替えは、テストごとの初期化・クリーンアップを必須にする。
- `ngx` モックは「本物のOpenResty挙動を完全再現するものではない」ため、最終確認はE2Eで担保する。

## 4. 推奨境界（E2EとMockの責務分担）

- Controller層
  - 主検証: E2E / 結合（HTTP経由・実ルーティング）
  - 補助検証: 認可分岐などの細かい分岐をMockで短時間確認
- Service層
  - 外部I/O境界（外部API、ストレージ、キュー、メール等）はMock中心
  - 純ロジックはユニットで高速確認、配線確認は結合/E2Eで補完
- Model層
  - DB整合性・クエリ妥当性は統合テスト（実DB）を優先

## 5. 次の試験導入候補（予定）

以下は **現時点の候補** であり、未実装。

- [`app/services/gemini_service.lua`](../app/services/gemini_service.lua)
  - 外部AI呼び出し（成功/失敗/タイムアウト/不正レスポンス）をMock中心で検証。
- ストレージ連携相当のService（将来実装）
  - アップロード・取得・削除・署名URL生成などのI/O境界をMock中心で検証。
- [`app/services/cache_service.lua`](../app/services/cache_service.lua)
  - キャッシュヒット/ミス、接続失敗時のフォールバックをMockで再現。

## 6. 棚卸し結果サマリ（`tests/`配下のMock利用状況）

### 6.1 Mock利用あり

| ファイル | 主なモック対象 | 手法 |
|---|---|---|
| [`tests/auth/test_auth_spec.lua`](../tests/auth/test_auth_spec.lua) | `ngx`, `resty.*`, `bcrypt`, `bit` | `_G.ngx`差し替え / `package.preload` |
| [`tests/models/test_user_spec.lua`](../tests/models/test_user_spec.lua) | `ngx`, `resty.*`, `bcrypt`, `bit` | `_G.ngx`差し替え / `package.preload` |
| [`tests/controllers/test_admin_controller_spec.lua`](../tests/controllers/test_admin_controller_spec.lua) | Session, Model群, CSRF, DB設定, `etlua`, `ngx` | `package.preload` + `_G.ngx`差し替え |
| [`tests/controllers/test_post_controller_spec.lua`](../tests/controllers/test_post_controller_spec.lua) | Session, `cjson`, Post/Category/Tag, Validator, `ngx` | `package.preload` + `_G.ngx`差し替え |
| [`tests/middleware/test_csrf_spec.lua`](../tests/middleware/test_csrf_spec.lua) | `bit`, `resty.random`, `resty.string`, `utils.crypto`, Session, `ngx` | `package.preload` + `_G.ngx`差し替え |
| [`tests/theme_engine/test_php_executor_spec.lua`](../tests/theme_engine/test_php_executor_spec.lua) | `ngx` | `_G.ngx`差し替え |
| [`tests/integration/test_helper_integration.lua`](../tests/integration/test_helper_integration.lua) | `ngx`（補助的） | `setup_ngx_mock()` |

### 6.2 Mock非使用（または主目的が実接続）

- E2Eシェルスクリプト群（HTTP実行）
  - [`tests/e2e/test_post_api.sh`](../tests/e2e/test_post_api.sh)
  - [`tests/e2e/test_category_tag_api.sh`](../tests/e2e/test_category_tag_api.sh)
  - [`tests/e2e/test_admin_dashboard.sh`](../tests/e2e/test_admin_dashboard.sh)
  - [`tests/e2e/test_user_management.sh`](../tests/e2e/test_user_management.sh)
  - [`tests/e2e/test_password_change.sh`](../tests/e2e/test_password_change.sh)
  - [`tests/e2e/test_html_login.sh`](../tests/e2e/test_html_login.sh)
- 統合/接続寄りテスト
  - [`tests/integration/test_post_model_integration_spec.lua`](../tests/integration/test_post_model_integration_spec.lua)（実DB中心）
  - [`tests/test_database.lua`](../tests/test_database.lua)（実DB接続）
  - [`tests/test_health.lua`](../tests/test_health.lua), [`tests/test_health_spec.lua`](../tests/test_health_spec.lua)（HTTP実接続）
  - [`tests/utils/test_slug_spec.lua`](../tests/utils/test_slug_spec.lua)（純関数）

## 7. この方針が満たすもの

- 日常運用はE2E中心（`make test`で統一）
- 一方で、外部I/O境界と異常系はMockで効率的に担保
- OpenResty特有の `ngx` 依存を明文化し、適用境界を固定化
- 将来の外部API/ストレージ連携に向け、導入候補を「予定」として分離記載

