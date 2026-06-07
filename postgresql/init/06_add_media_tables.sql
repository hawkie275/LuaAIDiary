-- メディアアップロード機能 Phase 1: メディア管理テーブル追加
-- 既存の初期テーブル定義を変更せず、追加マイグレーションとして管理します。

CREATE TABLE IF NOT EXISTS media (
    id BIGSERIAL PRIMARY KEY,
    storage_disk VARCHAR(20) NOT NULL DEFAULT 'local',
    storage_key VARCHAR(512) UNIQUE NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    extension VARCHAR(10) NOT NULL,
    size_bytes BIGINT NOT NULL CHECK (size_bytes > 0),
    width INTEGER NULL CHECK (width IS NULL OR width > 0),
    height INTEGER NULL CHECK (height IS NULL OR height > 0),
    alt_text TEXT NULL,
    sha256_hash CHAR(64) NULL,
    thumbnail_storage_key VARCHAR(512) NULL,
    thumbnail_width INTEGER NULL CHECK (thumbnail_width IS NULL OR thumbnail_width > 0),
    thumbnail_height INTEGER NULL CHECK (thumbnail_height IS NULL OR thumbnail_height > 0),
    uploaded_by INTEGER NOT NULL,
    backup_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    backup_attempts INTEGER NOT NULL DEFAULT 0 CHECK (backup_attempts >= 0),
    backup_last_error TEXT NULL,
    deleted_at TIMESTAMP NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_media_uploaded_by
        FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT chk_media_storage_disk
        CHECK (storage_disk IN ('local', 's3', 'r2')),
    CONSTRAINT chk_media_extension
        CHECK (extension IN ('jpg', 'jpeg', 'png', 'webp', 'gif')),
    CONSTRAINT chk_media_mime_type
        CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/gif')),
    CONSTRAINT chk_media_sha256_hash
        CHECK (sha256_hash IS NULL OR sha256_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT chk_media_backup_status
        CHECK (backup_status IN ('pending', 'synced', 'failed', 'disabled'))
);

CREATE TABLE IF NOT EXISTS media_post_usages (
    media_id BIGINT NOT NULL,
    post_id INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (media_id, post_id),
    CONSTRAINT fk_media_post_usages_media
        FOREIGN KEY (media_id) REFERENCES media(id) ON DELETE CASCADE,
    CONSTRAINT fk_media_post_usages_post
        FOREIGN KEY (post_id) REFERENCES posts(id) ON DELETE CASCADE
);

-- 重複検知用。論理削除済みは再利用対象から除外します。
CREATE UNIQUE INDEX IF NOT EXISTS idx_media_sha256_hash_active
    ON media(sha256_hash)
    WHERE sha256_hash IS NOT NULL AND deleted_at IS NULL;

-- 保存キーから公開URLに対応するメディアを解決します。
CREATE INDEX IF NOT EXISTS idx_media_storage_key
    ON media(storage_key);

-- 一覧取得時に論理削除済みを除外し、作成日時順で取得しやすくします。
CREATE INDEX IF NOT EXISTS idx_media_active_created_at
    ON media(created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_media_deleted_at
    ON media(deleted_at);

-- ファイル名前方一致検索の補助に利用します。
CREATE INDEX IF NOT EXISTS idx_media_file_name
    ON media(file_name);

-- 記事保存時の利用状況洗い替えと、メディア削除時の利用中判定に利用します。
CREATE INDEX IF NOT EXISTS idx_media_post_usages_post_id
    ON media_post_usages(post_id);

CREATE INDEX IF NOT EXISTS idx_media_post_usages_media_id
    ON media_post_usages(media_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'trigger_media_updated_at'
          AND tgrelid = 'media'::regclass
    ) THEN
        CREATE TRIGGER trigger_media_updated_at
            BEFORE UPDATE ON media
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column();
    END IF;
END;
$$;
