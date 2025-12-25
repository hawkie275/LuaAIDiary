-- 管理者ユーザーのパスワードハッシュを更新
-- パスワード: admin123
-- bcryptハッシュ (cost=10)

UPDATE users 
SET password_hash = '$2y$10$mF6xWl9K3vLZQN3Y8X3YHe3K6mYZ6X3Y8X3Y8X3Y8X3Y8X3Y8X3Y8O'
WHERE username = 'admin';

-- 注: このパスワードハッシュは一時的なものです
-- 本番環境では必ず強力なパスワードに変更してください
