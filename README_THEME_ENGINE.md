# WordPressテーマ互換レイヤー実装完了

## 実装概要

LuaAIDiary用のWordPressテーマ互換レイヤーを実装しました。既存のWordPressテーマをそのまま使用できるように、PHPテンプレートエンジンとWordPress関数のエミュレーション層を構築しました。

## 実装済みコンポーネント

### 1. テーマディレクトリ構造
- `/wp-content/themes/` - テーマ格納ディレクトリ
- `/wp-content/plugins/` - プラグインディレクトリ（将来の拡張用）
- `/wp-content/uploads/` - アップロードファイル用
- `/app/theme_engine/` - テーマエンジン本体

### 2. PHPテンプレートエンジン

#### `/app/theme_engine/php_executor.lua`
- PHPコードの実行とエミュレーション
- `<?php ?>` および `<?= ?>` タグのサポート
- PHPとHTMLの混在テンプレート処理
- セキュリティ: 危険な関数（eval, system等）の制限
- WordPress関数の実行環境設定

#### `/app/theme_engine/template_loader.lua`
- WordPressテンプレート階層の実装
- テンプレートファイル探索（優先順位順）
- `get_header()`, `get_footer()`, `get_sidebar()`, `get_template_part()` の実装
- 子テーマのサポート準備

### 3. WordPress関数エミュレーション

#### `/app/theme_engine/wp_functions.lua`
主要なWordPress関数をLuaで実装:

**The Loop関数:**
- `have_posts()`, `the_post()`

**記事データ取得:**
- `the_title()`, `get_the_title()`
- `the_content()`, `get_the_content()`
- `the_excerpt()`, `get_the_excerpt()`
- `the_permalink()`, `get_permalink()`
- `the_date()`, `the_time()`
- `the_author()`, `get_the_author()`

**カテゴリー・タグ:**
- `the_category()`, `get_the_category_list()`
- `the_tags()`, `get_the_tag_list()`
- `get_categories()`, `get_tags()`

**条件分岐タグ:**
- `is_home()`, `is_single()`, `is_page()`
- `is_category()`, `is_tag()`, `is_archive()`
- `is_search()`, `is_404()`

**サイト情報:**
- `bloginfo()`, `get_bloginfo()`
- `wp_title()`, `home_url()`, `site_url()`

**その他:**
- `wp_head()`, `wp_footer()`
- `body_class()`, `post_class()`
- `wp_nav_menu()`

#### `/app/theme_engine/wp_query.lua`
- WP_Queryクラスのエミュレーション
- ループコンテキストの管理
- クエリ実行とデータ取得
- モデル層との連携

### 4. テーマ設定とカスタマイザー

#### `/app/theme_engine/theme_config.lua`
- `style.css` の解析（テーマメタデータ）
- テーマの有効化・無効化
- テーマオプションの保存・取得
- サムネイルサイズ設定
- テーマサポート機能の管理

### 5. アセット管理

#### `/app/theme_engine/asset_loader.lua`
- `wp_enqueue_style()`, `wp_enqueue_script()` の実装
- 依存関係の解決
- バージョン管理
- ヘッダー・フッターでの出力

### 6. サンプルテーマ

#### `/wp-content/themes/luaaidiary-default/`
動作確認用のシンプルなテーマを実装:
- `style.css` - テーマメタデータとスタイル定義
- `index.php` - メインテンプレート（投稿一覧）
- `header.php` - ヘッダー
- `footer.php` - フッター
- `sidebar.php` - サイドバー
- `single.php` - 単一投稿
- `archive.php` - アーカイブ
- `functions.php` - テーマ関数

### 7. コントローラーとの統合

#### `/app/controllers/theme_controller.lua`
- リクエストに応じた適切なテンプレート選択
- クエリパラメータの処理
- データの準備とテンプレートへの受け渡し
- エラーハンドリング（404等）

### 8. ルーティングの設定

`/app/init.lua` を更新し、WordPress風のURL構造をサポート:
- `/` - ホームページ
- `/:slug` - 単一投稿
- `/category/:slug` - カテゴリアーカイブ
- `/tag/:slug` - タグアーカイブ
- `/author/:username` - 著者アーカイブ
- `/search` - 検索結果
- `/:year/:month/:day` - 日付アーカイブ

### 9. テスト

#### `/tests/theme_engine/test_php_executor_spec.lua`
- PHPエグゼキューターの基本テスト
- PHP変数展開テスト
- PHPとHTMLの混在テスト
- セキュリティチェックテスト

## 使用方法

### 1. テーマの配置
WordPressテーマを `/wp-content/themes/` ディレクトリに配置します。

### 2. テーマの有効化
```lua
local theme_config = require "app.theme_engine.theme_config"
theme_config.set_active_theme("your-theme-name")
```

### 3. ルーティング
`/app/init.lua` で既にWordPress風のルーティングが設定されています。

## 制限事項

以下の制限があります:

1. **PHP実装の制限**
   - 完全なPHPエミュレーションではなく、テンプレートタグとループが動作する簡易版
   - 複雑なPHPロジックは動作しない可能性があります

2. **WordPress関数の制限**
   - 主要な関数のみ実装（DESIGN.mdのリスト参照）
   - すべてのWordPress関数は実装されていません

3. **プラグインサポート**
   - 現時点ではプラグインシステムは未実装

## セキュリティ

- 危険なPHP関数（eval, system, exec等）はブラックリストで制限
- ユーザー入力のエスケープ処理を実装
- SQLインジェクション対策（モデル層で実装）

## 次のステップ

1. 実際のWordPressテーマでの動作確認
2. 不足しているWordPress関数の追加実装
3. プラグインシステムの実装
4. パフォーマンスの最適化
5. エラーハンドリングの強化

## 動作確認方法

```bash
# Dockerコンテナを起動
make up

# ブラウザでアクセス
http://localhost:8080/

# テストの実行（実装後）
make test
```

## 実装ファイル一覧

- `/app/theme_engine/php_executor.lua` - PHPエグゼキューター
- `/app/theme_engine/template_loader.lua` - テンプレートローダー
- `/app/theme_engine/wp_functions.lua` - WordPress関数
- `/app/theme_engine/wp_query.lua` - WP_Queryエミュレーション
- `/app/theme_engine/theme_config.lua` - テーマ設定
- `/app/theme_engine/asset_loader.lua` - アセット管理
- `/app/controllers/theme_controller.lua` - テーマコントローラー
- `/wp-content/themes/luaaidiary-default/*` - サンプルテーマ
- `/tests/theme_engine/test_php_executor_spec.lua` - テスト

## 技術スタック

- **言語**: Lua
- **Webフレームワーク**: Lapis (OpenResty)
- **テンプレート**: PHP互換エミュレーション
- **データベース**: PostgreSQL 15
- **テスト**: Busted

## まとめ

WordPressテーマ互換レイヤーの実装により、既存のWordPressテーマをLuaAIDiaryで使用できる基盤が整いました。主要なWordPress関数とテンプレート階層を実装し、サンプルテーマで動作確認が可能です。

今後は実際のWordPressテーマでのテストを行い、不足している機能を追加していく必要があります。
