-- メディアコントローラー
-- 画像アップロード、一覧、詳細、名称変更、削除APIを提供します。

local cjson = require("cjson")
local upload = require("resty.upload")
local AuthService = require("services.auth_service")
local Media = require("models.media")
local Session = require("utils.session")
local crypto = require("utils.crypto")

local MediaController = {}

local UPLOAD_ROOT = os.getenv("MEDIA_UPLOAD_ROOT") or "/app/uploads"
local MAX_FILE_SIZE = tonumber(os.getenv("MEDIA_MAX_FILE_SIZE_BYTES") or tostring(10 * 1024 * 1024))
local THUMB_WIDTH = tonumber(os.getenv("MEDIA_THUMBNAIL_WIDTH") or "720")

local allowed_extensions = { jpg = true, jpeg = true, png = true, webp = true, gif = true }
local allowed_mime_types = {
    ["image/jpeg"] = true,
    ["image/png"] = true,
    ["image/webp"] = true,
    ["image/gif"] = true
}

local function json_response(data, status)
    ngx.status = status or 200
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(data))
    return ngx.exit(ngx.OK)
end

local function get_json_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body or body == "" then
        return nil, "リクエストボディが空です"
    end
    local ok, data = pcall(cjson.decode, body)
    if not ok then
        return nil, "無効なJSON形式です"
    end
    return data, nil
end

local function get_authenticated_editor()
    local session = Session.new()
    local ok = session:start()
    if not ok or not session:is_authenticated() then
        return nil, nil, "認証が必要です", 401
    end

    local user = session:get_user()
    if not user or not AuthService.check_permission(user, "editor") then
        return nil, nil, "権限がありません", 403
    end

    return user, session, nil, nil
end

local function verify_csrf(session, json_data)
    local session_token = session and session:get("csrf_token")
    if not session_token or session_token == "" then
        return false, "CSRFトークンがセッションに存在しません"
    end

    local headers = ngx.req.get_headers()
    local request_token = headers["x-csrf-token"] or headers["X-CSRF-Token"]
    if not request_token and json_data then
        request_token = json_data._csrf_token or json_data.csrf_token
    end

    if not request_token or request_token == "" then
        return false, "CSRFトークンが提供されていません"
    end
    if request_token ~= session_token then
        return false, "CSRFトークンが一致しません"
    end
    return true, nil
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function mkdir_p(path)
    local ok = os.execute("mkdir -p " .. shell_quote(path))
    return ok == true or ok == 0
end

local function random_hex(bytes)
    local ok, random = pcall(require, "resty.random")
    if ok and random and random.bytes then
        local resty_string = require("resty.string")
        local raw = random.bytes(bytes, true)
        if raw then
            return resty_string.to_hex(raw)
        end
    end

    math.randomseed(ngx.now() * 1000000 + ngx.worker.pid())
    local parts = {}
    for _ = 1, bytes do
        table.insert(parts, string.format("%02x", math.random(0, 255)))
    end
    return table.concat(parts)
end

local function sanitize_file_name(file_name)
    local name = tostring(file_name or "image")
    name = name:gsub("[/\\]", "_"):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = "image"
    end
    return name:sub(1, 255)
end

local function sanitize_display_file_name(file_name, fallback_extension)
    local name = sanitize_file_name(file_name)
    if not name:match("%.([A-Za-z0-9]+)$") and fallback_extension then
        name = name .. "." .. fallback_extension
    end
    return name
end

local function extension_from_name(file_name)
    local ext = tostring(file_name or ""):match("%.([A-Za-z0-9]+)$")
    if not ext then
        return nil
    end
    ext = ext:lower()
    if ext == "jpg" or ext == "jpeg" then
        return ext
    end
    return ext
end

local function mime_from_magic(data)
    if not data or #data < 4 then
        return nil
    end
    local b1, b2, b3, b4 = data:byte(1, 4)
    if b1 == 0xFF and b2 == 0xD8 and b3 == 0xFF then
        return "image/jpeg"
    end
    if b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47 then
        return "image/png"
    end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then
        return "image/webp"
    end
    if data:sub(1, 6) == "GIF87a" or data:sub(1, 6) == "GIF89a" then
        return "image/gif"
    end
    return nil
end

local function mime_matches_extension(mime_type, extension)
    if extension == "jpg" or extension == "jpeg" then
        return mime_type == "image/jpeg"
    end
    return (extension == "png" and mime_type == "image/png")
        or (extension == "webp" and mime_type == "image/webp")
        or (extension == "gif" and mime_type == "image/gif")
end

local function parse_content_disposition(header)
    local name = header:match('name="([^"]+)"')
    local filename = header:match('filename="([^"]*)"')
    return name, filename
end

local function parse_part_headers(header_block)
    local headers = {}
    for line in tostring(header_block or ""):gmatch("([^\r\n]+)") do
        local key, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        if key then
            headers[key:lower()] = value
        end
    end
    return headers
end

local function read_existing_body()
    local body = ngx.req.get_body_data()
    if body then
        return body, nil
    end

    local body_file = ngx.req.get_body_file()
    if not body_file then
        return nil, "アップロードデータを取得できません"
    end

    local fh, err = io.open(body_file, "rb")
    if not fh then
        return nil, err or "アップロード一時ファイルを開けません"
    end
    body = fh:read("*a")
    fh:close()
    return body, nil
end

local function parse_multipart_from_existing_body()
    local content_type = ngx.req.get_headers()["content-type"] or ngx.req.get_headers()["Content-Type"] or ""
    local boundary = content_type:match("boundary=([^;]+)")
    if not boundary or boundary == "" then
        return nil, "multipart boundary が見つかりません"
    end
    boundary = boundary:gsub('^"', ""):gsub('"$', "")

    local body, body_err = read_existing_body()
    if not body then
        return nil, body_err
    end

    local fields = {}
    local file = nil
    local delimiter = "--" .. boundary

    for part in (body .. "\r\n"):gmatch(delimiter:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") .. "\r\n(.-)\r\n") do
        if part:sub(1, 2) ~= "--" then
            local header_block, value = part:match("^(.-)\r\n\r\n(.*)$")
            if header_block and value then
                if value:sub(-2) == "\r\n" then
                    value = value:sub(1, -3)
                end
                local headers = parse_part_headers(header_block)
                local field_name, filename = parse_content_disposition(headers["content-disposition"] or "")
                if field_name then
                    if filename and filename ~= "" and field_name == "file" then
                        if #value > MAX_FILE_SIZE then
                            return nil, "ファイルサイズが上限10MBを超えています", 413
                        end
                        file = {
                            filename = filename,
                            content_type = headers["content-type"] and headers["content-type"]:lower() or nil,
                            data = value,
                            size = #value
                        }
                    else
                        fields[field_name] = value
                    end
                end
            end
        end
    end

    return { fields = fields, file = file }, nil
end

local function parse_multipart_from_lapis_params(params)
    if not params or type(params.file) ~= "table" then
        return nil, nil
    end

    local file_param = params.file
    if not file_param.content or file_param.content == "" then
        return nil, "file は必須です"
    end
    if #file_param.content > MAX_FILE_SIZE then
        return nil, "ファイルサイズが上限10MBを超えています", 413
    end

    local fields = {}
    for key, value in pairs(params) do
        if key ~= "file" and type(value) == "string" then
            fields[key] = value
        end
    end

    return {
        fields = fields,
        file = {
            filename = file_param.filename or file_param.name or "image",
            content_type = file_param["content-type"] and file_param["content-type"]:lower() or nil,
            data = file_param.content,
            size = #file_param.content
        }
    }, nil
end

local function parse_multipart()
    local form, err = upload:new(8192)
    if not form then
        if tostring(err or ""):match("request body already exists") then
            return parse_multipart_from_existing_body()
        end
        return nil, err or "multipart解析を開始できません"
    end
    form:set_timeout(1000)

    local fields = {}
    local file = nil
    local current = nil

    while true do
        local typ, res, read_err = form:read()
        if not typ then
            return nil, read_err or "multipart解析に失敗しました"
        end

        if typ == "header" then
            local header_name = string.lower(res[1] or "")
            local header_value = res[2] or ""
            if header_name == "content-disposition" then
                local field_name, filename = parse_content_disposition(header_value)
                current = { name = field_name, filename = filename, chunks = {}, size = 0, content_type = nil }
            elseif header_name == "content-type" and current then
                current.content_type = header_value:lower()
            end
        elseif typ == "body" then
            if current then
                current.size = current.size + #res
                if current.filename and current.size > MAX_FILE_SIZE then
                    return nil, "ファイルサイズが上限10MBを超えています", 413
                end
                table.insert(current.chunks, res)
            end
        elseif typ == "part_end" then
            if current and current.name then
                local value = table.concat(current.chunks)
                if current.filename and current.filename ~= "" and current.name == "file" then
                    file = {
                        filename = current.filename,
                        content_type = current.content_type,
                        data = value,
                        size = #value
                    }
                else
                    fields[current.name] = value
                end
            end
            current = nil
        elseif typ == "eof" then
            break
        end
    end

    return { fields = fields, file = file }, nil
end

local function get_image_dimensions(path)
    local width_cmd = "vipsheader -f width " .. shell_quote(path) .. " 2>/dev/null"
    local height_cmd = "vipsheader -f height " .. shell_quote(path) .. " 2>/dev/null"
    local width_pipe = io.popen(width_cmd)
    local width = width_pipe and tonumber(width_pipe:read("*l")) or nil
    if width_pipe then width_pipe:close() end
    local height_pipe = io.popen(height_cmd)
    local height = height_pipe and tonumber(height_pipe:read("*l")) or nil
    if height_pipe then height_pipe:close() end
    return width, height
end

local function generate_thumbnail(source_path, target_path)
    local cmd = string.format(
        "vipsthumbnail %s --size %dx --output %s 2>/dev/null",
        shell_quote(source_path),
        THUMB_WIDTH,
        shell_quote(target_path .. "[Q=82]")
    )
    local ok = os.execute(cmd)
    if ok == true or ok == 0 then
        return true
    end
    return false
end

local function write_file(path, data)
    local fh, err = io.open(path, "wb")
    if not fh then
        return false, err
    end
    fh:write(data)
    fh:close()
    return true, nil
end

local function media_payload(media, deduplicated)
    return {
        success = true,
        id = tonumber(media.id),
        file_name = media.file_name,
        url = media.url,
        thumbnail_url = media.thumbnail_url,
        mime_type = media.mime_type,
        size_bytes = tonumber(media.size_bytes),
        width = tonumber(media.width),
        height = tonumber(media.height),
        alt_text = media.alt_text,
        usage_count = tonumber(media.usage_count or 0),
        in_use = media.in_use,
        deduplicated = deduplicated == true
    }
end

function MediaController.index()
    local user, _, auth_err, status = get_authenticated_editor()
    if not user then
        return json_response({ success = false, error = auth_err }, status)
    end

    local args = ngx.req.get_uri_args()
    local result, err = Media.list_active({ page = args.page, per_page = args.per_page, q = args.q })
    if not result then
        return json_response({ success = false, error = err or "メディア一覧の取得に失敗しました" }, 500)
    end
    for i, item in ipairs(result.items) do
        result.items[i] = media_payload(item, false)
    end
    result.success = true
    return json_response(result, 200)
end

function MediaController.show(id)
    local user, _, auth_err, status = get_authenticated_editor()
    if not user then
        return json_response({ success = false, error = auth_err }, status)
    end

    local media, err = Media.find_active(id)
    if not media then
        return json_response({ success = false, error = err or "メディアが見つかりません" }, 404)
    end
    return json_response({ success = true, media = media_payload(media, false) }, 200)
end

function MediaController.create(self)
    local user, session, auth_err, status = get_authenticated_editor()
    if not user then
        return json_response({ success = false, error = auth_err }, status)
    end

    local csrf_valid, csrf_err = verify_csrf(session)
    if not csrf_valid then
        return json_response({ success = false, error = csrf_err }, 403)
    end

    local parsed, parse_err, parse_status = parse_multipart_from_lapis_params(self and self.params)
    if not parsed and not parse_err then
        parsed, parse_err, parse_status = parse_multipart()
    end
    if not parsed then
        return json_response({ success = false, error = parse_err or "アップロードデータが不正です" }, parse_status or 400)
    end
    if not parsed.file then
        return json_response({ success = false, error = "file は必須です" }, 400)
    end

    local original_name = sanitize_file_name(parsed.file.filename)
    local extension = extension_from_name(original_name)
    if not extension or not allowed_extensions[extension] then
        return json_response({ success = false, error = "許可されていない拡張子です" }, 415)
    end
    if parsed.file.size <= 0 then
        return json_response({ success = false, error = "ファイルが空です" }, 400)
    end
    if parsed.file.size > MAX_FILE_SIZE then
        return json_response({ success = false, error = "ファイルサイズが上限10MBを超えています" }, 413)
    end

    local detected_mime = mime_from_magic(parsed.file.data)
    if not detected_mime or not allowed_mime_types[detected_mime] or not mime_matches_extension(detected_mime, extension) then
        return json_response({ success = false, error = "MIMEタイプと拡張子が一致しません" }, 415)
    end

    local sha256_hash = crypto.sha256(parsed.file.data)
    local existing, find_err = Media.find_active_by_hash(sha256_hash)
    if find_err then
        return json_response({ success = false, error = find_err }, 500)
    end
    if existing then
        return json_response(media_payload(existing, true), 200)
    end

    local now = os.date("!*t")
    local relative_dir = string.format("uploads/%04d/%02d/%02d", now.year, now.month, now.day)
    local absolute_dir = UPLOAD_ROOT .. string.format("/%04d/%02d/%02d", now.year, now.month, now.day)
    if not mkdir_p(absolute_dir) then
        return json_response({ success = false, error = "保存先ディレクトリを作成できません" }, 500)
    end

    local uuid = random_hex(16)
    local storage_key = string.format("%s/%s.%s", relative_dir, uuid, extension)
    local absolute_path = string.format("%s/%s.%s", absolute_dir, uuid, extension)
    local ok, write_err = write_file(absolute_path, parsed.file.data)
    if not ok then
        return json_response({ success = false, error = write_err or "ファイル保存に失敗しました" }, 500)
    end

    local width, height = get_image_dimensions(absolute_path)
    local thumb_key = nil
    local thumb_width = nil
    local thumb_height = nil
    local thumb_path = string.format("%s/%s_thumb_w%d.webp", absolute_dir, uuid, THUMB_WIDTH)
    if generate_thumbnail(absolute_path, thumb_path) then
        thumb_key = string.format("%s/%s_thumb_w%d.webp", relative_dir, uuid, THUMB_WIDTH)
        thumb_width, thumb_height = get_image_dimensions(thumb_path)
    else
        ngx.log(ngx.WARN, "サムネイル生成に失敗しました。原本URLを利用します: ", absolute_path)
    end

    local media, create_err = Media.create_media({
        storage_key = storage_key,
        file_name = original_name,
        original_file_name = original_name,
        mime_type = detected_mime,
        extension = extension,
        size_bytes = parsed.file.size,
        width = width,
        height = height,
        alt_text = parsed.fields.alt_text,
        sha256_hash = sha256_hash,
        thumbnail_storage_key = thumb_key,
        thumbnail_width = thumb_width,
        thumbnail_height = thumb_height,
        uploaded_by = tonumber(user.id),
        backup_status = "disabled"
    })
    if not media then
        os.remove(absolute_path)
        if thumb_path then os.remove(thumb_path) end
        return json_response({ success = false, error = create_err or "メディア登録に失敗しました" }, 500)
    end

    return json_response(media_payload(media, false), 201)
end

function MediaController.update(id)
    local user, session, auth_err, status = get_authenticated_editor()
    if not user then
        return json_response({ success = false, error = auth_err }, status)
    end

    local data, body_err = get_json_body()
    if not data then
        return json_response({ success = false, error = body_err }, 400)
    end
    local csrf_valid, csrf_err = verify_csrf(session, data)
    if not csrf_valid then
        return json_response({ success = false, error = csrf_err }, 403)
    end

    if not data.file_name or data.file_name == "" then
        return json_response({ success = false, error = "file_name は必須です" }, 422)
    end
    local current, current_err = Media.find_active(id)
    if not current then
        return json_response({ success = false, error = current_err or "メディアが見つかりません" }, 404)
    end
    data.file_name = sanitize_display_file_name(data.file_name, current.extension)

    local media, err = Media.update_metadata(id, { file_name = data.file_name, alt_text = data.alt_text })
    if not media then
        return json_response({ success = false, error = err or "メディア更新に失敗しました" }, 500)
    end
    return json_response({ success = true, media = media_payload(media, false) }, 200)
end

function MediaController.delete(id)
    local user, session, auth_err, status = get_authenticated_editor()
    if not user then
        return json_response({ success = false, error = auth_err }, status)
    end
    local csrf_valid, csrf_err = verify_csrf(session)
    if not csrf_valid then
        return json_response({ success = false, error = csrf_err }, 403)
    end

    local media = Media.find_active(id)
    local ok, err, delete_status = Media.soft_delete(id)
    if not ok then
        return json_response({ success = false, error = err or "メディア削除に失敗しました" }, delete_status or 500)
    end
    if media then
        if media.storage_key and media.storage_key ~= "" then
            os.remove(UPLOAD_ROOT .. "/" .. media.storage_key:gsub("^uploads/", ""))
        end
        if media.thumbnail_storage_key and media.thumbnail_storage_key ~= "" then
            os.remove(UPLOAD_ROOT .. "/" .. media.thumbnail_storage_key:gsub("^uploads/", ""))
        end
    end
    return json_response({ success = true, deleted = true }, 200)
end

return MediaController
