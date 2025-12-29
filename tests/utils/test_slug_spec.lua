local slug_util = require("app.utils.slug")

describe("slugify with Japanese characters", function()
    it("should convert kanji-only titles to hex slugs", function()
        local slug = slug_util.slugify("最新記事")
        assert.is_not_nil(slug)
        assert.is_not.equal("", slug)
        -- 漢字が16進数に変換されるため、十分な長さがある
        assert.is_true(#slug > 5)
        -- 英数字とハイフンのみで構成されている
        assert.is_true(slug:match("^[a-z0-9%-]+$") ~= nil)
    end)
    
    it("should convert single kanji character to hex slug", function()
        local slug = slug_util.slugify("明")
        assert.is_not_nil(slug)
        assert.is_not.equal("", slug)
        -- 単一の漢字でも16進数に変換されるため、短くない
        assert.is_true(#slug >= 6)  -- 漢字1文字は3バイト = 6桁の16進数
        assert.is_true(slug:match("^[a-z0-9%-]+$") ~= nil)
    end)
    
    it("should handle mixed Japanese and English titles", function()
        local slug = slug_util.slugify("Test記事")
        assert.is_not_nil(slug)
        assert.is_not.equal("", slug)
        assert.is_true(#slug >= 2)
    end)
    
    it("should handle empty strings", function()
        local slug = slug_util.slugify("")
        assert.is_not_nil(slug)
        assert.is_not.equal("", slug)
        assert.is_true(slug:match("^post%-") ~= nil, "Slug should match ^post%-")
    end)
    
    it("should handle katakana-only titles", function()
        local slug = slug_util.slugify("プログラミング")
        assert.is_not_nil(slug)
        assert.is_not.equal("", slug)
        assert.is_true(#slug >= 2)
    end)
end)

describe("slug collision avoidance for Japanese titles", function()
    it("should generate different slugs for collision-prone titles", function()
        local slug1 = slug_util.slugify("明日の天気")
        local slug2 = slug_util.slugify("今日の予定")
        
        -- 両方とも有効なスラッグが生成される
        assert.is_not_nil(slug1)
        assert.is_not_nil(slug2)
        assert.is_not.equal("", slug1)
        assert.is_not.equal("", slug2)
        
        -- 異なるスラッグが生成される（衝突しない）
        assert.is_not.equal(slug1, slug2)
        
        -- 漢字が16進数に変換されているため、十分な長さがある
        assert.is_true(#slug1 > 5, "Slug1 length should be > 5, got: " .. #slug1)
        assert.is_true(#slug2 > 5, "Slug2 length should be > 5, got: " .. #slug2)
    end)
    
    it("should generate different slugs for particle-heavy titles", function()
        -- 助詞が多いタイトルでもユニークなスラッグを生成
        local test_cases = {
            {title = "AとB", desc = "AとB"},
            {title = "CとD", desc = "CとD"},
            {title = "私は学生です", desc = "私は学生です"},
            {title = "彼は先生です", desc = "彼は先生です"},
        }
        
        local slugs = {}
        for i, test in ipairs(test_cases) do
            local slug = slug_util.slugify(test.title)
            assert.is_not_nil(slug, "Slug for '" .. test.desc .. "' should not be nil")
            assert.is_not.equal("", slug, "Slug for '" .. test.desc .. "' should not be empty")
            
            -- 他のスラッグと重複していないことを確認
            for j, existing in ipairs(slugs) do
                assert.is_not.equal(slug, existing.slug,
                    "Slug collision: '" .. test.desc .. "' generated same slug as '" .. existing.desc .. "'")
            end
            
            table.insert(slugs, {slug = slug, desc = test.desc})
        end
    end)
    
    it("should generate different slugs for similar kanji titles", function()
        -- 類似した漢字タイトル
        local slug1 = slug_util.slugify("今日の話")
        local slug2 = slug_util.slugify("明日の話")
        local slug3 = slug_util.slugify("今日の件")
        
        assert.is_not_nil(slug1)
        assert.is_not_nil(slug2)
        assert.is_not_nil(slug3)
        
        -- すべて異なるスラッグが生成される
        assert.is_not.equal(slug1, slug2)
        assert.is_not.equal(slug1, slug3)
        assert.is_not.equal(slug2, slug3)
    end)
    
    it("should convert kanji to hex representation", function()
        local slug = slug_util.slugify("天気")
        
        -- 漢字が16進数に変換されていることを確認
        -- スラッグが英数字のみになっている
        assert.is_not_nil(slug)
        assert.is_true(slug:match("^[a-z0-9%-]+$") ~= nil,
            "Slug should only contain lowercase alphanumeric and hyphens")
        
        -- 16進数表現があるため、十分な長さがある
        assert.is_true(#slug > 5)
    end)
end)
