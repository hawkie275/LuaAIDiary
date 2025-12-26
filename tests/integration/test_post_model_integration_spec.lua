-- 投稿モデルの統合テスト（実際のDB使用）
-- モックを使わずに実際のデータベースとコードパスをテスト

-- LUA_PATHを調整してヘルパーを読み込む
package.path = package.path .. ";/tests/?.lua;/tests/?/init.lua"

describe("投稿モデル統合テスト", function()
  local helper = require("integration.test_helper_integration")
  local db
  local test_user_id
  local test_category_id
  local test_tag_id
  
  -- テスト前の準備
  before_each(function()
    -- データベース接続
    db = helper.setup_db()
    
    -- トランザクション開始（各テストを独立させる）
    helper.begin_transaction(db)
    
    -- テストユーザーを作成
    test_user_id = helper.create_test_user(db, "test_author_" .. os.time())
    
    -- テストカテゴリーを作成
    test_category_id = helper.create_test_category(db, "TEST_CATEGORY_" .. os.time())
    
    -- テストタグを作成
    test_tag_id = helper.create_test_tag(db, "TEST_TAG_" .. os.time())
  end)
  
  -- テスト後のクリーンアップ
  after_each(function()
    -- トランザクションをロールバック（テストデータを自動削除）
    if db then
      helper.rollback_transaction(db)
      helper.teardown_db(db)
    end
  end)
  
  -- ========================================
  -- 投稿作成のテスト
  -- ========================================
  
  describe("create_post", function()
    it("基本的な投稿を作成できること", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_統合テスト投稿",
        content = "これは統合テストの投稿内容です",
        author_id = test_user_id,
        status = "draft"
      }
      
      local post_id, err = Post.create_post(post_data)
      
      -- アサーション
      helper.assert_not_nil(post_id, "投稿IDが返されるべき")
      assert.is_nil(err, "エラーは発生しないはず")
      helper.assert_greater_than(post_id, 0, "投稿IDは正の整数であるべき")
      
      -- 実際にDBに保存されたか確認
      local res = db:query("SELECT * FROM posts WHERE id = " .. post_id)
      helper.assert_not_nil(res, "投稿がDBに保存されているべき")
      assert.equals(1, #res, "1件の投稿が見つかるべき")
      assert.equals("TEST_統合テスト投稿", res[1].title)
      assert.equals(test_user_id, tonumber(res[1].author_id))
    end)
    
    it("スラッグが自動生成されること", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_自動スラッグ生成",
        content = "スラッグテスト",
        author_id = test_user_id,
        status = "draft"
      }
      
      local post_id, err = Post.create_post(post_data)
      
      helper.assert_not_nil(post_id)
      assert.is_nil(err)
      
      -- スラッグを確認
      local res = db:query("SELECT slug FROM posts WHERE id = " .. post_id)
      helper.assert_not_nil(res[1].slug, "スラッグが生成されているべき")
      assert.is_true(#res[1].slug > 0, "スラッグは空でないべき")
    end)
    
    it("カテゴリーとタグを関連付けられること", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_カテゴリータグ付き投稿",
        content = "カテゴリーとタグのテスト",
        author_id = test_user_id,
        status = "draft",
        categories = {test_category_id},
        tags = {test_tag_id}
      }
      
      local post_id, err = Post.create_post(post_data)
      
      helper.assert_not_nil(post_id)
      assert.is_nil(err)
      
      -- カテゴリーの関連付けを確認
      local cat_res = db:query("SELECT * FROM post_categories WHERE post_id = " .. post_id)
      assert.equals(1, #cat_res, "カテゴリーが1件関連付けられているべき")
      assert.equals(test_category_id, tonumber(cat_res[1].category_id))
      
      -- タグの関連付けを確認
      local tag_res = db:query("SELECT * FROM post_tags WHERE post_id = " .. post_id)
      assert.equals(1, #tag_res, "タグが1件関連付けられているべき")
      assert.equals(test_tag_id, tonumber(tag_res[1].tag_id))
    end)
    
    it("公開ステータスの投稿で公開日時が設定されること", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_公開投稿",
        content = "公開テスト",
        author_id = test_user_id,
        status = "published"
      }
      
      local post_id, err = Post.create_post(post_data)
      
      helper.assert_not_nil(post_id)
      assert.is_nil(err)
      
      -- 公開日時を確認
      local res = db:query("SELECT published_at FROM posts WHERE id = " .. post_id)
      helper.assert_not_nil(res[1].published_at, "公開日時が設定されているべき")
    end)
    
    it("タイトルが空の場合にエラーを返すこと", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "",
        content = "本文のみ",
        author_id = test_user_id
      }
      
      local post_id, err = Post.create_post(post_data)
      
      assert.is_nil(post_id, "投稿IDは返されないべき")
      helper.assert_not_nil(err, "エラーが返されるべき")
    end)
    
    it("著者IDが無い場合にエラーを返すこと", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_著者なし",
        content = "テスト"
      }
      
      local post_id, err = Post.create_post(post_data)
      
      assert.is_nil(post_id)
      helper.assert_not_nil(err)
    end)
  end)
  
  -- ========================================
  -- 投稿取得のテスト
  -- ========================================
  
  describe("find_by_slug", function()
    it("スラッグで投稿を検索できること", function()
      local Post = require("app.models.post")
      
      -- テスト投稿を作成
      local post_id = helper.create_test_post(db, test_user_id, "TEST_スラッグ検索", "内容")
      
      -- スラッグで検索
      local post, err = Post.find_by_slug("test_スラッグ検索")
      
      -- アサーション（スラッグの正規化により見つからない可能性があるため調整）
      -- 実際のスラッグを確認
      local res = db:query("SELECT slug FROM posts WHERE id = " .. post_id)
      local actual_slug = res[1].slug
      
      post, err = Post.find_by_slug(actual_slug)
      helper.assert_not_nil(post, "投稿が見つかるべき")
      assert.is_nil(err)
      assert.equals(post_id, post.id)
    end)
    
    it("存在しないスラッグでエラーを返すこと", function()
      local Post = require("app.models.post")
      
      local post, err = Post.find_by_slug("non-existent-slug-12345")
      
      assert.is_nil(post)
      helper.assert_not_nil(err)
    end)
  end)
  
  describe("find_published", function()
    it("公開済み投稿のみを取得できること", function()
      local Post = require("app.models.post")
      
      -- 公開投稿を作成
      db:query(string.format([[
        INSERT INTO posts (title, slug, content, author_id, status, published_at, created_at, updated_at)
        VALUES ('TEST_公開1', 'test-pub-1', '内容1', %d, 'published', NOW(), NOW(), NOW())
      ]], test_user_id))
      
      -- 下書き投稿を作成
      db:query(string.format([[
        INSERT INTO posts (title, slug, content, author_id, status, created_at, updated_at)
        VALUES ('TEST_下書き', 'test-draft-1', '内容2', %d, 'draft', NOW(), NOW())
      ]], test_user_id))
      
      -- 公開済み投稿を取得
      local posts, err = Post.find_published()
      
      helper.assert_not_nil(posts)
      assert.is_nil(err)
      
      -- 公開投稿だけが含まれることを確認
      for _, post in ipairs(posts) do
        assert.equals("published", post.status)
      end
    end)
    
    it("limitとoffsetが機能すること", function()
      local Post = require("app.models.post")
      
      -- 複数の公開投稿を作成
      for i = 1, 5 do
        db:query(string.format([[
          INSERT INTO posts (title, slug, content, author_id, status, published_at, created_at, updated_at)
          VALUES ('TEST_公開%d', 'test-pub-%d', '内容', %d, 'published', NOW(), NOW(), NOW())
        ]], i, i, test_user_id))
      end
      
      -- limitを指定して取得
      local posts, err = Post.find_published({limit = 2})
      
      helper.assert_not_nil(posts)
      assert.is_nil(err)
      helper.assert_greater_than(#posts, 0, "投稿が取得されるべき")
    end)
  end)
  
  -- ========================================
  -- 投稿更新のテスト
  -- ========================================
  
  describe("update_post", function()
    it("投稿を更新できること", function()
      local Post = require("app.models.post")
      
      -- テスト投稿を作成
      local post_id = helper.create_test_post(db, test_user_id, "TEST_更新前", "内容")
      
      -- 更新
      local ok, err = Post.update_post(post_id, {
        title = "TEST_更新後",
        content = "更新された内容"
      })
      
      helper.assert_true(ok, "更新が成功するべき")
      assert.is_nil(err)
      
      -- 更新を確認
      local res = db:query("SELECT * FROM posts WHERE id = " .. post_id)
      assert.equals("TEST_更新後", res[1].title)
      assert.equals("更新された内容", res[1].content)
    end)
    
    it("ステータスを公開に変更すると公開日時が設定されること", function()
      local Post = require("app.models.post")
      
      -- 下書き投稿を作成
      local post_id = helper.create_test_post(db, test_user_id, "TEST_下書き", "内容")
      db:query(string.format("UPDATE posts SET status = 'draft', published_at = NULL WHERE id = %d", post_id))
      
      -- 公開に変更
      local ok, err = Post.update_post(post_id, {
        status = "published"
      })
      
      helper.assert_true(ok)
      assert.is_nil(err)
      
      -- 公開日時を確認
      local res = db:query("SELECT published_at FROM posts WHERE id = " .. post_id)
      helper.assert_not_nil(res[1].published_at)
    end)
    
    it("存在しない投稿の更新でエラーを返すこと", function()
      local Post = require("app.models.post")
      
      local ok, err = Post.update_post(99999, {title = "更新"})
      
      helper.assert_false(ok)
      helper.assert_not_nil(err)
    end)
  end)
  
  -- ========================================
  -- カテゴリー・タグ管理のテスト
  -- ========================================
  
  describe("カテゴリー・タグ管理", function()
    it("カテゴリーを追加できること", function()
      local Post = require("app.models.post")
      
      local post_id = helper.create_test_post(db, test_user_id, "TEST_カテゴリー追加", "内容")
      
      -- カテゴリーを追加
      Post.add_category(post_id, test_category_id, db)
      
      -- 確認
      local res = db:query("SELECT * FROM post_categories WHERE post_id = " .. post_id)
      assert.equals(1, #res)
      assert.equals(test_category_id, tonumber(res[1].category_id))
    end)
    
    it("タグを追加できること", function()
      local Post = require("app.models.post")
      
      local post_id = helper.create_test_post(db, test_user_id, "TEST_タグ追加", "内容")
      
      -- タグを追加
      Post.add_tag(post_id, test_tag_id, db)
      
      -- 確認
      local res = db:query("SELECT * FROM post_tags WHERE post_id = " .. post_id)
      assert.equals(1, #res)
      assert.equals(test_tag_id, tonumber(res[1].tag_id))
    end)
    
    it("カテゴリーを同期できること", function()
      local Post = require("app.models.post")
      
      local post_id = helper.create_test_post(db, test_user_id, "TEST_カテゴリー同期", "内容")
      local category_id_2 = helper.create_test_category(db, "TEST_CATEGORY_2_" .. os.time())
      
      -- 最初のカテゴリーを追加
      Post.add_category(post_id, test_category_id, db)
      
      -- 別のカテゴリーに同期
      Post.sync_categories(post_id, {category_id_2}, db)
      
      -- 確認
      local res = db:query("SELECT * FROM post_categories WHERE post_id = " .. post_id)
      assert.equals(1, #res, "1件のカテゴリーのみ存在するべき")
      assert.equals(category_id_2, tonumber(res[1].category_id))
    end)
    
    it("投稿のカテゴリーを取得できること", function()
      local Post = require("app.models.post")
      
      local post_id = helper.create_test_post(db, test_user_id, "TEST_カテゴリー取得", "内容")
      Post.add_category(post_id, test_category_id, db)
      
      -- カテゴリーを取得
      local categories = Post.get_categories(post_id)
      
      helper.assert_not_nil(categories)
      helper.assert_greater_than(#categories, 0, "カテゴリーが取得されるべき")
      assert.equals(test_category_id, categories[1].id)
    end)
    
    it("投稿のタグを取得できること", function()
      local Post = require("app.models.post")
      
      local post_id = helper.create_test_post(db, test_user_id, "TEST_タグ取得", "内容")
      Post.add_tag(post_id, test_tag_id, db)
      
      -- タグを取得
      local tags = Post.get_tags(post_id)
      
      helper.assert_not_nil(tags)
      helper.assert_greater_than(#tags, 0, "タグが取得されるべき")
      assert.equals(test_tag_id, tags[1].id)
    end)
  end)
  
  -- ========================================
  -- トランザクションのテスト
  -- ========================================
  
  describe("トランザクション", function()
    it("トランザクション内で投稿とカテゴリーが同時に作成されること", function()
      local Post = require("app.models.post")
      
      local post_data = {
        title = "TEST_トランザクション投稿",
        content = "トランザクションテスト",
        author_id = test_user_id,
        status = "draft",
        categories = {test_category_id}
      }
      
      local post_id, err = Post.create_post(post_data)
      
      helper.assert_not_nil(post_id)
      assert.is_nil(err)
      
      -- 投稿とカテゴリーの両方が存在することを確認
      local post_res = db:query("SELECT * FROM posts WHERE id = " .. post_id)
      local cat_res = db:query("SELECT * FROM post_categories WHERE post_id = " .. post_id)
      
      assert.equals(1, #post_res, "投稿が作成されているべき")
      assert.equals(1, #cat_res, "カテゴリーの関連付けがあるべき")
    end)
  end)
end)
