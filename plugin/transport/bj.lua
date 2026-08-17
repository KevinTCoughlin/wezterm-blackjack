local M = {}

local function append_all(target, source)
    for _, item in ipairs(source) do
        target[#target + 1] = item
    end
end

local function run_process(utils, argv)
    local success, stdout, stderr = utils.safe_run(argv)
    if not success then
        return nil, stderr or stdout or "unknown error"
    end

    return stdout
end

local function parse_and_validate_state(stdout, deps)
    local state = deps.utils.safe_json_parse(stdout)
    if not state then
        return nil, "failed to parse bj JSON output"
    end

    local ok, err = deps.state_domain.validate_state_shape(state)
    if not ok then
        return nil, "invalid bj JSON state: " .. err
    end

    return state
end

local function validate_cli_args(cli_args)
    if type(cli_args) ~= "table" or #cli_args == 0 then
        return nil, "invalid action command"
    end

    local normalized = {}
    for i, arg in ipairs(cli_args) do
        if type(arg) ~= "string" or arg == "" then
            return nil, string.format("invalid action argument at index %d", i)
        end
        normalized[#normalized + 1] = arg
    end
    return normalized
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64_char(index)
    return BASE64_ALPHABET:sub(index + 1, index + 1)
end

local function base64_encode(value)
    local encoded = {}
    local length = #value

    for i = 1, length, 3 do
        local first = value:byte(i)
        local second = value:byte(i + 1)
        local third = value:byte(i + 2)
        local combined = first * 65536 + (second or 0) * 256 + (third or 0)

        encoded[#encoded + 1] = base64_char(math.floor(combined / 262144) % 64)
        encoded[#encoded + 1] = base64_char(math.floor(combined / 4096) % 64)
        encoded[#encoded + 1] = second and base64_char(math.floor(combined / 64) % 64) or "="
        encoded[#encoded + 1] = third and base64_char(combined % 64) or "="
    end

    return table.concat(encoded)
end

local function powershell_decode(encoded)
    return "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" .. encoded .. "'))"
end

local function command_with_stdin(config, cli_args, stdin, target_triple)
    local argv
    if type(target_triple) == "string" and target_triple:find("windows", 1, true) then
        local encoded_args = {}
        for _, arg in ipairs(cli_args) do
            encoded_args[#encoded_args + 1] = powershell_decode(base64_encode(arg))
        end

        argv = {
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$state = "
                .. powershell_decode(base64_encode(stdin))
                .. "; $command = "
                .. powershell_decode(base64_encode(config.bj_path))
                .. "; $commandArgs = @("
                .. table.concat(encoded_args, ",")
                .. "); "
                .. "$state | & $command @commandArgs; exit $LASTEXITCODE",
        }
    else
        argv = {
            "sh",
            "-c",
            'state=$1; shift; printf "%s" "$state" | "$@"',
            "wezterm-blackjack",
            stdin,
            config.bj_path,
        }
        append_all(argv, cli_args)
    end
    return argv
end

function M.run_new(config, deps)
    local argv = { config.bj_path, "new" }
    if config.config_path then
        argv[#argv + 1] = "--config"
        argv[#argv + 1] = config.config_path
    end

    local stdout, err = run_process(deps.utils, argv)
    if not stdout then
        return nil, err
    end

    return parse_and_validate_state(stdout, deps)
end

function M.run_action(config, deps, cli_args, state)
    local normalized_args, args_err = validate_cli_args(cli_args)
    if not normalized_args then
        return nil, args_err
    end

    local json_state = deps.utils.safe_json_encode(state)
    if not json_state then
        return nil, "failed to encode game state"
    end

    local argv = command_with_stdin(config, normalized_args, json_state, deps.target_triple)

    local stdout, err = run_process(deps.utils, argv)
    if not stdout then
        return nil, err
    end

    return parse_and_validate_state(stdout, deps)
end

M._private = {
    base64_encode = base64_encode,
}

return M
