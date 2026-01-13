# ファクトチェック機能 設計ドキュメント

## 概要

AI生成記事の信頼性を向上させるため、事実確認を支援する機能を追加する。完全自動のファクトチェックは技術的に困難なため、人間の判断を支援するアプローチを採用する。

## 背景・目的

- AI生成コンテンツはハルシネーション（事実誤認）のリスクがある
- SEO観点でもE-E-A-T（経験・専門性・権威性・信頼性）が重要
- 「AI生成 + 人間レビュー」のワークフローを支援する

## 実装アプローチ

### Phase 1: プロンプト改善（低コスト）

生成時にソース明示を要求するプロンプトに変更する。

```
各主張に対して信頼できるソースURLを付記してください。
ソースがない場合は「要確認」と明記してください。
```

**変更箇所:**
- 管理画面のデフォルトプロンプトテンプレート
- `user_settings` テーブルの初期値

**工数:** 小（プロンプト変更のみ）

### Phase 2: LLMによる自己検証（中コスト）

生成した記事を別のAPIコールで検証し、信頼度スコアを付与する。

```
[記事生成] → [検証APIコール] → [信頼度スコア付きで表示]
```

**実装内容:**
- `gemini_service.lua` に `verify_facts` メソッド追加
- 検証結果をJSON形式で返却
- 管理画面で「要確認」箇所をハイライト表示

**レスポンス例:**
```json
{
  "overall_confidence": 0.75,
  "claims": [
    {
      "text": "OpenRestyは2011年にリリースされた",
      "confidence": 0.9,
      "source": "https://openresty.org/en/",
      "status": "verified"
    },
    {
      "text": "LuaJITはPythonより100倍速い",
      "confidence": 0.3,
      "source": null,
      "status": "needs_review"
    }
  ]
}
```

**工数:** 中（バックエンド + フロントエンド）

### Phase 3: 外部データソース照合（高コスト）

外部APIと照合して事実確認を行う。

| ソース | 用途 | API |
|--------|------|-----|
| Wikipedia | 一般的な事実 | Wikipedia API（無料） |
| Wikidata | 構造化データ（日付、数値） | Wikidata API（無料） |
| Google Fact Check | ニュース・主張の検証 | Fact Check Tools API |

**実装内容:**
- `fact_check_service.lua` 新規作成
- 固有名詞、日付、数値を抽出して外部照合
- 不一致があれば警告表示

**工数:** 高（外部API統合 + エラーハンドリング）

## 推奨実装順序

1. **Phase 1** から開始（即日対応可能）
2. 運用して効果を検証
3. 需要に応じて Phase 2 を実装
4. Phase 3 は必要性が明確になってから

## UI設計案

### 記事編集画面

```
[AI生成] ボタン
    ↓
生成結果プレビュー
    - 信頼度スコア: 75%
    - 要確認箇所: 3件（ハイライト表示）
    ↓
[エディタに挿入] [再生成]
```

### 要確認箇所の表示

```html
<span class="fact-needs-review" title="ソースが確認できません">
  LuaJITはPythonより100倍速い
</span>
```

## 技術的考慮事項

### APIコスト

- Phase 2: 記事1本あたり追加で1 APIコール
- Gemini無料枠（1500 RPD）で十分対応可能

### 制限事項

- LLMによる検証はLLM自体の知識に依存
- 最新情報や専門分野は検証精度が低下
- 最終判断は人間が行う前提

## 関連機能

- 限定公開機能（別ドキュメント参照）と組み合わせ
  - AI生成 → 限定公開 → 外部レビュー → 修正 → 公開

## 参考

- Google E-E-A-T ガイドライン
- Google Fact Check Tools API: https://developers.google.com/fact-check/tools/api
- Wikipedia API: https://www.mediawiki.org/wiki/API:Main_page
