-- Shared utility functions for wezterm-blackjack.

local wezterm = require("wezterm")
local M = {}

M.debug_mode = os.getenv("WEZTERM_BLACKJACK_DEBUG") == "1"

function M.log(message, level)
    level = level or "INFO"
    if M.debug_mode or level == "ERROR" or level == "WARN" then
        local logger = level == "WARN" and wezterm.log_warn or wezterm.log_error
        logger(string.format("[wezterm-blackjack:%s] %s", level, message))
    end
end

function M.safe_run(cmd)
    if type(cmd) == "string" then
        error("safe_run() requires array form")
    end

    if M.debug_mode then
        M.log("running: " .. table.concat(cmd, " "), "DEBUG")
    end

    return wezterm.run_child_process(cmd)
end

function M.safe_run_with_stdin(cmd, stdin)
    if type(cmd) == "string" then
        error("safe_run_with_stdin() requires array form")
    end

    if M.debug_mode then
        M.log("running with stdin: " .. table.concat(cmd, " "), "DEBUG")
    end

    return wezterm.run_child_process(cmd, stdin)
end

function M.dirname(path)
    if type(path) ~= "string" then
        return nil
    end
    return path:match("^(.*)/[^/]*$") or "."
end

function M.mkdir_p(path)
    if not path or path == "" then
        return false
    end
    local success = M.safe_run({ "mkdir", "-p", path })
    return success
end

function M.read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

function M.write_file(path, content)
    local dir = M.dirname(path)
    if dir then
        M.mkdir_p(dir)
    end

    local file, err = io.open(path, "w")
    if not file then
        return false, err
    end

    local ok, write_err = file:write(content)
    file:close()
    if not ok then
        return false, write_err
    end
    return true
end

function M.split_args(str)
    if type(str) ~= "string" then
        return {}
    end

    local args = {}
    local current = {}
    local in_token = false
    local quote = nil
    local i = 1

    while i <= #str do
        local ch = str:sub(i, i)
        if quote then
            if ch == "\\" and i < #str then
                i = i + 1
                table.insert(current, str:sub(i, i))
                in_token = true
            elseif ch == quote then
                quote = nil
            else
                table.insert(current, ch)
                in_token = true
            end
        elseif ch == "\"" or ch == "'" then
            quote = ch
            in_token = true
        elseif ch:match("%s") then
            if in_token then
                table.insert(args, table.concat(current))
                current = {}
                in_token = false
            end
        elseif ch == "\\" and i < #str then
            i = i + 1
            table.insert(current, str:sub(i, i))
            in_token = true
        else
            table.insert(current, ch)
            in_token = true
        end
        i = i + 1
    end

    if in_token then
        table.insert(args, table.concat(current))
    end

    return args
end

function M.safe_json_parse(str)
    if not str or str == "" then
        return nil
    end

    local ok, result = pcall(wezterm.json_parse, str)
    if not ok then
        M.log("JSON parse error: " .. tostring(result), "WARN")
        return nil
    end

    return result
end

function M.safe_json_encode(value)
    local ok, result = pcall(wezterm.json_encode, value)
    if not ok then
        M.log("JSON encode error: " .. tostring(result), "ERROR")
        return nil
    end

    return result
end

return M
