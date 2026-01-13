# 限定公開機能 設計ドキュメント

## 概要

YouTubeの「限定公開」に相当する機能を実装する。URLを知っている人だけが記事にアクセスでき、検索エンジンにはインデックスされない。

## 背景・目的

- 公開前の記事を外部レビュー依頼したい
- NotebookLM等のAIツールにURLを渡してフィードバックを得たい
- 企業向け案件で納品前の確認に使いたい
- メール添付やPDF化より手軽に共有したい

## ユースケース

| 用途 | 説明 |
|------|------|
| AIレビュー | NotebookLM、Claude、Perplexityに記事URLを渡してファクトチェック |
| 人間レビュー | 編集者・監修者に公開前の確認依頼 |
| クライアント確認 | 受託案件で納品前のプレビュー共有 |
| 限定配信 | 特定の読者にのみ公開したいコンテンツ |

## 公開状態の設計

### 現在の状態

```
draft（下書き） → published（公開）
```

### 拡張後の状態

```
draft（下書き） → unlisted（限定公開） → published（公開）
                      ↑
                URLを知っている人のみアクセス可能
                検索エンジンにはインデックスされない
```

## 実装詳細

### Phase 1: 基本実装

#### データベース変更

`posts.status` の許容値を拡張:

```sql
-- 既存: 'draft', 'published'
-- 追加: 'unlisted'

-- マイグレーション不要（文字列型のため）
-- バリデーションの更新のみ
```

#### ルーティング変更

```lua
-- app/init.lua

-- 記事一覧（トップページ）: unlisted を除外
-- WHERE status = 'published'

-- 記事詳細: unlisted も表示可能
-- WHERE (status = 'published' OR status = 'unlisted') AND slug = ?

-- RSS/サイトマップ: unlisted を除外
```

#### SEO対策（noindex）

```lua
-- 記事詳細ビューで status が unlisted の場合
-- <meta name="robots" content="noindex, nofollow">
```

#### 管理画面変更

記事編集画面のステータス選択:

```html
<select name="status">
  <option value="draft">下書き</option>
  <option value="unlisted">限定公開</option>
  <option value="published">公開</option>
</select>
```

記事一覧画面:

```
[タイトル] [ステータス] [作成日]
記事A      公開         2024-01-01
記事B      限定公開 🔗  2024-01-02  ← リンクコピーボタン
記事C      下書き       2024-01-03
```

### Phase 2: 企業向け強化（オプション）

需要に応じて追加実装:

| 機能 | 説明 | 工数 |
|------|------|------|
| 有効期限 | 指定日時以降はアクセス不可 | 中 |
| パスワード保護 | 簡易的な追加認証 | 中 |
| 閲覧ログ | アクセス日時・IPを記録 | 小 |
| 閲覧通知 | アクセス時にメール通知 | 中 |

#### 有効期限の実装案

```sql
ALTER TABLE posts ADD COLUMN unlisted_expires_at TIMESTAMP NULL;
```

```lua
-- アクセス時のチェック
if post.status == 'unlisted' and post.unlisted_expires_at then
  if post.unlisted_expires_at < ngx.now() then
    return { status = 404 }
  end
end
```

## URL設計

通常の記事URLをそのまま使用:

```
/posts/{id}          -- ID指定
/{slug}              -- スラッグ指定
```

**理由:**
- 特別なトークンURL不要でシンプル
- URLを知らなければアクセスできない
- 記事を公開に変更してもURLが変わらない

## セキュリティ考慮事項

### リスク

- URLが漏洩した場合、誰でもアクセス可能
- 検索エンジンにインデックスされる可能性（noindexが無視される場合）

### 対策

- `noindex, nofollow` メタタグを必ず付与
- `X-Robots-Tag: noindex` HTTPヘッダーも追加
- sitemap.xml から除外
- robots.txt での明示的なブロックは不要（URLパターンが同じため）

### 企業向け案件での注意

機密性が高い場合は Phase 2 のパスワード保護を推奨。

## 実装工数見積もり

| Phase | 内容 | 工数 |
|-------|------|------|
| Phase 1 | 基本実装（status追加、noindex、UI） | 0.5〜1日 |
| Phase 2 | 有効期限 | 0.5日 |
| Phase 2 | パスワード保護 | 0.5日 |
| Phase 2 | 閲覧ログ | 0.5日 |

## テスト項目

### Phase 1

- [ ] 限定公開記事がトップページ一覧に表示されない
- [ ] 限定公開記事がRSSに含まれない
- [ ] 限定公開記事のURLに直接アクセスで閲覧可能
- [ ] 限定公開記事に `noindex` メタタグが付与される
- [ ] 管理画面でステータス変更が正常に動作
- [ ] 下書き→限定公開→公開の遷移が正常

### Phase 2

- [ ] 有効期限切れの記事が404になる
- [ ] パスワード保護が正常に機能
- [ ] 閲覧ログが記録される

## 関連機能

- ファクトチェック機能（別ドキュメント参照）との連携
  - AI生成 → 限定公開 → NotebookLMでレビュー → 修正 → 公開

## 参考

- YouTube 限定公開: https://support.google.com/youtube/answer/157177
- Google noindex ガイド: https://developers.google.com/search/docs/crawling-indexing/block-indexing
