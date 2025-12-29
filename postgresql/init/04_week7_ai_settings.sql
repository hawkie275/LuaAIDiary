-- Week7: AI設定用のデフォルト値追加
-- user_settingsテーブルのpreferences JSONBカラムにAI設定のデフォルト値を追加

-- 既存のユーザー設定にAI設定を追加
UPDATE user_settings
SET preferences = jsonb_set(
    COALESCE(preferences, '{}'::jsonb),
    '{ai_preferences}',
    jsonb_build_object(
        'model', 'gemini-2.5-flash',
        'default_tone', 'formal',
        'default_target_audience', '小学校6年生',
        'auto_proofread', false,
        'custom_prompts', '{}'::jsonb,
        'proofread_prompt', 'あなたは経験豊富な編集者です。以下のブログ記事を校正してください。

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
}',
        'generate_article_prompt', 'あなたはプロのライターです。以下の条件で完全な記事を執筆してください。

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
}'
    )::jsonb
)
WHERE preferences IS NULL OR NOT (preferences ? 'ai_preferences');

-- 新規ユーザー用のトリガー関数を作成（ai_preferences のデフォルト値を設定）
CREATE OR REPLACE FUNCTION set_default_ai_preferences()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.preferences IS NULL OR NOT (NEW.preferences ? 'ai_preferences') THEN
        NEW.preferences = jsonb_set(
            COALESCE(NEW.preferences, '{}'::jsonb),
            '{ai_preferences}',
            jsonb_build_object(
                'model', 'gemini-2.5-flash',
                'default_tone', 'formal',
                'default_target_audience', '小学校6年生',
                'auto_proofread', false,
                'custom_prompts', '{}'::jsonb,
                'proofread_prompt', 'あなたは経験豊富な編集者です。以下のブログ記事を校正してください。

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
}',
                'generate_article_prompt', 'あなたはプロのライターです。以下の条件で完全な記事を執筆してください。

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
}'
            )::jsonb
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- トリガーを作成（新規レコード挿入時と更新時にデフォルト値を設定）
DROP TRIGGER IF EXISTS trigger_set_default_ai_preferences ON user_settings;
CREATE TRIGGER trigger_set_default_ai_preferences
    BEFORE INSERT OR UPDATE ON user_settings
    FOR EACH ROW
    EXECUTE FUNCTION set_default_ai_preferences();

-- インデックスを追加（ai_preferences の検索を高速化）
CREATE INDEX IF NOT EXISTS idx_user_settings_ai_preferences ON user_settings USING gin ((preferences->'ai_preferences'));

COMMENT ON FUNCTION set_default_ai_preferences() IS 'user_settingsテーブルのAI設定にデフォルト値を設定するトリガー関数';
