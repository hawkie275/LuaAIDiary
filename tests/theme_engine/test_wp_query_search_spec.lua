-- tests/theme_engine/test_wp_query_search_spec.lua
-- WP_Query検索分岐のテスト

describe("WP_Query 検索分岐", function()
  local original_ngx

  before_each(function()
    original_ngx = _G.ngx
    _G.ngx = {
      ERR = "ERR",
      log = function() end
    }

    package.loaded["theme_engine.wp_query"] = nil
    package.loaded["models.post"] = nil
  end)

  after_each(function()
    _G.ngx = original_ngx
    package.loaded["theme_engine.wp_query"] = nil
    package.loaded["models.post"] = nil
    package.preload["models.post"] = nil
  end)

  it("args.sがある場合はPost.searchとcount_searchを使い通常一覧へ流れないこと", function()
    local called_search = false
    local called_count_search = false
    local called_find_published = false

    package.preload["models.post"] = function()
      return {
        search = function(keyword, options)
          called_search = true
          assert.equals("日本語", keyword)
          assert.equals(true, options.published_only)
          assert.equals(10, options.limit)
          assert.equals(10, options.offset)
          return {
            { id = 1, title = "検索結果", status = "published" }
          }
        end,
        count_search = function(keyword, published_only)
          called_count_search = true
          assert.equals("日本語", keyword)
          assert.equals(true, published_only)
          return 21
        end,
        find_published = function()
          called_find_published = true
          return {}
        end,
        count = function()
          return 0
        end
      }
    end

    local wp_query = require("theme_engine.wp_query")
    local query = wp_query:new({
      s = "  日本語  ",
      posts_per_page = 10,
      paged = 2
    })

    assert.is_true(called_search)
    assert.is_true(called_count_search)
    assert.is_false(called_find_published)
    assert.equals(1, query.post_count)
    assert.equals(21, query.found_posts)
    assert.equals(3, query.max_num_pages)
  end)

  it("検索語を再デコードせずPost.searchに渡すこと", function()
    package.preload["models.post"] = function()
      return {
        search = function(keyword)
          assert.equals("%252F", keyword)
          return {}
        end,
        count_search = function(keyword)
          assert.equals("%252F", keyword)
          return 0
        end,
        find_published = function()
          return {}
        end,
        count = function()
          return 0
        end
      }
    end

    local wp_query = require("theme_engine.wp_query")
    local query = wp_query:new({ s = "%252F" })

    assert.is_nil(query.query_error)
    assert.equals(0, query.post_count)
  end)

  it("Post.searchのエラーをquery_errorに保持すること", function()
    package.preload["models.post"] = function()
      return {
        search = function()
          return nil, "search failed"
        end,
        count_search = function()
          error("count_search should not be called")
        end,
        find_published = function()
          return {}
        end,
        count = function()
          return 0
        end
      }
    end

    local wp_query = require("theme_engine.wp_query")
    local query = wp_query:new({ s = "lua" })

    assert.equals("search failed", query.query_error)
    assert.equals(0, query.post_count)
    assert.equals(0, query.found_posts)
    assert.equals(0, query.max_num_pages)
  end)

  it("Post.count_searchのエラーをquery_errorに保持すること", function()
    package.preload["models.post"] = function()
      return {
        search = function()
          return {
            { id = 1, title = "検索結果", status = "published" }
          }
        end,
        count_search = function()
          return nil, "count failed"
        end,
        find_published = function()
          return {}
        end,
        count = function()
          return 0
        end
      }
    end

    local wp_query = require("theme_engine.wp_query")
    local query = wp_query:new({ s = "lua" })

    assert.equals("count failed", query.query_error)
    assert.equals(1, query.post_count)
    assert.equals(0, query.found_posts)
    assert.equals(0, query.max_num_pages)
  end)

  it("空検索では検索関数を呼ばず空結果になること", function()
    local called_search = false

    package.preload["models.post"] = function()
      return {
        search = function()
          called_search = true
          return {}
        end,
        count_search = function()
          return 0
        end,
        find_published = function()
          return {}
        end,
        count = function()
          return 0
        end
      }
    end

    local wp_query = require("theme_engine.wp_query")
    local query = wp_query:new({ s = "   " })

    assert.is_false(called_search)
    assert.equals(0, query.post_count)
    assert.equals(0, query.found_posts)
    assert.equals(0, query.max_num_pages)
  end)
end)
