-- 既存ユーザーのAI設定プロンプトを更新するスクリプト
-- このスクリプトは既存のユーザー設定のプロンプトを最新版に更新します

-- 校正プロンプトの更新
UPDATE user_settings
SET preferences = jsonb_set(
    preferences,
    '{ai_preferences,proofread_prompt}',
    to_jsonb('あなたは経験豊富な編集者です。以下のブログ記事を校正してください。

【記事本文】
{content}

【校正方針】
- トーン: {tone}
- 文法、表現、構成の改善を提案してください

**重要**: 必ず以下の形式の有効なJSONのみを返してください。コードブロック記号（```json など）や余分な説明文は一切含めず、純粋なJSON形式のみを出力してください：
{
  "corrected": "校正後の全文",
  "suggestions": [
    {
      "type": "grammar",
      "original_text": "修正前のテキスト",
      "suggested_text": "修正後のテキスト",
      "reason": "修正理由の説明"
    }
  ]
}'::text)
)
WHERE preferences ? 'ai_preferences';

-- 記事生成プロンプトの更新
UPDATE user_settings
SET preferences = jsonb_set(
    preferences,
    '{ai_preferences,generate_article_prompt}',
    to_jsonb('あなたはプロのライターです。以下の条件で完全な記事を執筆してください。

【条件】
- テーマ: {topic}
- キーワード: {keywords}
- 対象読者: {target_audience}
- 目標文字数: {word_count}文字
- トーン: {tone}

【要求事項】
1. 記事全体をMarkdown形式で執筆してください
2. 適切な見出し（H2, H3）を使用してください
3. 導入、本文、結論の構成にしてください
4. SEOを意識した内容にしてください
5. 読者にとって価値のある具体的な情報を含めてください

**重要**: 必ず以下の形式の有効なJSONのみを返してください。コードブロック記号（```json など）や余分な説明文は一切含めず、純粋なJSON形式のみを出力してください：
{
  "title": "魅力的なタイトル",
  "content": "完全な記事本文（Markdown形式）",
  "meta_description": "SEO用のメタディスクリプション（120〜160文字）",
  "tags": ["タグ1", "タグ2", "タグ3"]
}'::text)
)
WHERE preferences ? 'ai_preferences';

-- 古いキー名(suggest_structure_prompt)を削除
UPDATE user_settings
SET preferences = preferences - 'ai_preferences' ||
    jsonb_build_object('ai_preferences',
        (preferences->'ai_preferences') - 'suggest_structure_prompt'
    )
WHERE preferences ? 'ai_preferences'
  AND preferences->'ai_preferences' ? 'suggest_structure_prompt';

-- モデル設定がない場合はデフォルト値を設定
UPDATE user_settings
SET preferences = jsonb_set(
    preferences,
    '{ai_preferences,model}',
    '"gemini-2.5-flash"'
)
WHERE preferences ? 'ai_preferences' 
  AND NOT (preferences->'ai_preferences' ? 'model');

-- 更新結果を表示
SELECT
    user_id,
    preferences->'ai_preferences'->>'model' as model,
    length(preferences->'ai_preferences'->>'proofread_prompt') as proofread_prompt_length,
    length(preferences->'ai_preferences'->>'generate_article_prompt') as generate_article_prompt_length
FROM user_settings
WHERE preferences ? 'ai_preferences';
