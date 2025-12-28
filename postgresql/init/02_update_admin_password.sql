-- 管理者ユーザーのパスワードハッシュを更新
-- パスワード: admin123
-- bcryptハッシュ (cost=10)

UPDATE users
SET password_hash = '$2b$10$Yt1OM2AKndiDQcVFgb5BTOPyUAmJUGnPCtkDS8ydVFlcxxQSgoPm.'
WHERE username = 'admin';

-- 注: このパスワードハッシュは一時的なものです
-- 本番環境では必ず強力なパスワードに変更してください
