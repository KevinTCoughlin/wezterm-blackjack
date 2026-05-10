local M = {}

local function append_all(target, source)
    for _, item in ipairs(source) do
        target[#target + 1] = item
    end
end

local function run_process(utils, argv, stdin)
    local success
    local stdout
    local stderr

    if stdin ~= nil then
        success, stdout, stderr = utils.safe_run_with_stdin(argv, stdin)
    else
        success, stdout, stderr = utils.safe_run(argv)
    end

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

function M.run_new(config, deps)
    local argv = { config.bj_path, "new" }
    if config.config_path then
        argv[#argv + 1] = "--config"
        argv[#argv + 1] = config.config_path
    end

    local stdout, err = run_process(deps.utils, argv, nil)
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

    local argv = { config.bj_path }
    append_all(argv, normalized_args)

    local stdout, err = run_process(deps.utils, argv, json_state)
    if not stdout then
        return nil, err
    end

    return parse_and_validate_state(stdout, deps)
end

return M
