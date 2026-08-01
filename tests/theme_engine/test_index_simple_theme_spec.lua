-- tests/theme_engine/test_index_simple_theme_spec.lua
-- Lua専用シンプルテーマの記事一覧ページネーションのテスト

describe("Lua専用シンプルテーマ", function()
  before_each(function()
    package.loaded["theme_engine.wp_functions"] = nil
    package.loaded["wp-content.themes.luaaidiary-default.index-simple"] = nil

    package.preload["theme_engine.wp_functions"] = function()
      return {
        get_bloginfo = function(key)
          if key == "name" then
            return "LuaAIDiary"
          end

          if key == "description" then
            return "テスト用ブログ"
          end

          return ""
        end
      }
    end
  end)

  it("最終ページが10件ちょうどでも次のページリンクを表示しないこと", function()
    local template = dofile("wp-content/themes/luaaidiary-default/index-simple.lua")
    local posts = {}

    for i = 1, 10 do
      table.insert(posts, {
        id = i,
        slug = "post-" .. i,
        title = "投稿" .. i,
        content = "本文" .. i,
        excerpt = "抜粋" .. i,
        published_at = "2024-01-01 00:00:00",
        author = { display_name = "著者" }
      })
    end

    local html = template.render({
      posts = posts,
      query = {
        query_vars = { paged = 2 },
        max_num_pages = 2
      }
    })

    assert.is_nil(html:find('href="/?paged=3"', 1, true))
    assert.is_not_nil(html:find('href="/?paged=1"', 1, true))
  end)

  it("次ページに投稿が存在する場合は次のページリンクを表示すること", function()
    local template = dofile("wp-content/themes/luaaidiary-default/index-simple.lua")
    local posts = {
      {
        id = 1,
        slug = "post-1",
        title = "投稿1",
        content = "本文1",
        excerpt = "抜粋1",
        published_at = "2024-01-01 00:00:00",
        author = { display_name = "著者" }
      }
    }

    local html = template.render({
      posts = posts,
      query = {
        query_vars = { paged = 1 },
        max_num_pages = 2
      }
    })

    assert.is_not_nil(html:find('href="/?paged=2"', 1, true))
  end)
end)
