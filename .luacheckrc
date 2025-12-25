-- Luacheck configuration for LuWordPress

-- グローバル変数の設定
std = "ngx_lua"

-- 無視するグローバル変数
globals = {
    "ngx",
    "package",
    "_G",
}

-- 読み取り専用グローバル変数
read_globals = {
    "os",
    "io",
    "math",
    "string",
    "table",
    "tonumber",
    "tostring",
    "type",
    "pairs",
    "ipairs",
    "assert",
    "error",
    "pcall",
    "xpcall",
    "select",
    "unpack",
    "require",
    "print",
    "next",
    "setmetatable",
    "getmetatable",
    "rawget",
    "rawset",
}

-- 除外するファイル・ディレクトリ
exclude_files = {
    "*/vendor/*",
    "*/node_modules/*",
    "*/.git/*",
}

-- 最大行長
max_line_length = 120

-- 最大コードの複雑度
max_cyclomatic_complexity = 15

-- 警告を無視
ignore = {
    "211",  -- 未使用のローカル変数
    "212",  -- 未使用の引数
    "213",  -- 未使用のループ変数
}

-- ファイル単位の設定
files["tests/*"] = {
    globals = {
        "describe",
        "it",
        "before_each",
        "after_each",
        "setup",
        "teardown",
        "assert",
        "spy",
        "stub",
        "mock",
    }
}

files["app/init.lua"] = {
    globals = {
        "lapis",
        "app",
    }
}

-- 環境設定
new_globals = {
    "app",
}

-- 未使用コードの検出
unused = true

-- 未定義変数の検出
undefined = true
