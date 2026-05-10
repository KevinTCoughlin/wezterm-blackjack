-- wezterm-blackjack: A blackjack plugin for WezTerm
-- https://github.com/KevinTCoughlin/wezterm-blackjack

local wezterm = require("wezterm")

local M = {}

local EVENT_ACTION = "wezterm-blackjack-action"
local EVENT_HEALTH = "wezterm-blackjack-health"
local EVENT_RESET_STATS = "wezterm-blackjack-reset-stats"
local USER_VAR = "wezterm_blackjack"
local KEY_TABLE = "wezterm_blackjack"

local function plugin_dir()
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    return source:match("(.*/)") or "./"
end

local PLUGIN_DIR = plugin_dir()

local function load_module(require_name, relative_path)
    local ok, mod = pcall(require, require_name)
    if ok then
        return mod
    end
    return dofile(PLUGIN_DIR .. relative_path)
end

local utils = load_module("plugin.lib", "lib.lua")
local action_domain = load_module("plugin.domain.actions", "domain/actions.lua")
local state_domain = load_module("plugin.domain.state", "domain/state.lua")
local bj_transport = load_module("plugin.transport.bj", "transport/bj.lua")
local ui_renderer = load_module("plugin.ui.render", "ui/render.lua")
local stats_store_module = load_module("plugin.stats.store", "stats/store.lua")
local wezterm_events = load_module("plugin.wezterm.events", "wezterm/events.lua")

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end

    local copied = {}
    for k, v in pairs(value) do
        copied[k] = deep_copy(v)
    end
    return copied
end

local function merge_tables(base, overrides)
    local result = deep_copy(base)
    for k, v in pairs(overrides or {}) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = merge_tables(result[k], v)
        else
            result[k] = deep_copy(v)
        end
    end
    return result
end

local DEFAULT_CONFIG = {
    trigger = "/deal",
    keybind = { key = "b", mods = "LEADER" },
    bj_path = "bj",
    config_path = nil,
    min_bj_version = "0.1.0",
    colors = true,
    command_palette = true,
    controls = {
        hit = "h",
        stand = "s",
        double = "d",
        split = "p",
        surrender = "u",
        insurance_accept = "y",
        insurance_decline = "n",
        new_game = "N",
        quit = "q",
    },
    stats = {
        persist = false,
        path = nil,
    },
    status_bar = {
        enabled = false,
        icon = "BJ",
        color = "#9ece6a",
        position = "right",
    },
}

M.config = deep_copy(DEFAULT_CONFIG)

local pane_games = {}

local transport_deps = {
    utils = utils,
    state_domain = state_domain,
}

local stats_store = stats_store_module.new({
    wezterm = wezterm,
    utils = utils,
    get_config = function()
        return M.config
    end,
    state_domain = state_domain,
    encode_json = wezterm.json_encode,
})

local TOP_LEVEL_KEYS = {
    trigger = true,
    keybind = true,
    bj_path = true,
    config_path = true,
    min_bj_version = true,
    colors = true,
    command_palette = true,
    controls = true,
    stats = true,
    status_bar = true,
}

local CONTROL_KEYS = {}
for _, control_name in ipairs(action_domain.control_names()) do
    CONTROL_KEYS[control_name] = true
end

local STATS_KEYS = { persist = true, path = true }
local STATUS_BAR_KEYS = { enabled = true, icon = true, color = true, position = true }
local KEYBIND_KEYS = { key = true, mods = true }

local function assert_known_keys(tbl, allowed, section)
    for key in pairs(tbl or {}) do
        if not allowed[key] then
            error(string.format("%s has unknown key '%s'", section, tostring(key)))
        end
    end
end

local function require_non_empty_string(value, field)
    if type(value) ~= "string" or value == "" then
        error(field .. " must be a non-empty string")
    end
    return value
end

local function optional_string(value, field)
    if value == nil then
        return nil
    end
    return require_non_empty_string(value, field)
end

local function normalize_control_value(value, name)
    if type(value) == "string" then
        return require_non_empty_string(value, "controls." .. name)
    end

    if type(value) ~= "table" then
        error("controls." .. name .. " must be a string or a list of strings")
    end

    local normalized = {}
    local seen = {}
    for i, item in ipairs(value) do
        if type(item) ~= "string" or item == "" then
            error(string.format("controls.%s[%d] must be a non-empty string", name, i))
        end
        if not seen[item] then
            seen[item] = true
            normalized[#normalized + 1] = item
        end
    end

    if #normalized == 0 then
        error("controls." .. name .. " must contain at least one key")
    end
    if #normalized == 1 then
        return normalized[1]
    end
    return normalized
end

local function normalize_keybind(value)
    if value == false then
        return false
    end
    if value == nil then
        return deep_copy(DEFAULT_CONFIG.keybind)
    end
    if type(value) ~= "table" then
        error("keybind must be false or a table with key/mods")
    end

    assert_known_keys(value, KEYBIND_KEYS, "keybind")
    return {
        key = require_non_empty_string(value.key, "keybind.key"),
        mods = require_non_empty_string(value.mods, "keybind.mods"),
    }
end

local function normalize_stats(value)
    if type(value) ~= "table" then
        error("stats must be a table")
    end
    return {
        persist = not not value.persist,
        path = optional_string(value.path, "stats.path"),
    }
end

local function normalize_status_bar(value)
    if type(value) ~= "table" then
        error("status_bar must be a table")
    end
    return {
        enabled = not not value.enabled,
        icon = require_non_empty_string(value.icon, "status_bar.icon"),
        color = require_non_empty_string(value.color, "status_bar.color"),
        position = require_non_empty_string(value.position, "status_bar.position"),
    }
end

local function normalize_config(opts)
    opts = opts or {}
    assert_known_keys(opts, TOP_LEVEL_KEYS, "blackjack options")

    if opts.controls ~= nil then
        if type(opts.controls) ~= "table" then
            error("controls must be a table")
        end
        assert_known_keys(opts.controls, CONTROL_KEYS, "controls")
    end

    if opts.stats ~= nil then
        if type(opts.stats) ~= "table" then
            error("stats must be a table")
        end
        assert_known_keys(opts.stats, STATS_KEYS, "stats")
    end

    if opts.status_bar ~= nil then
        if type(opts.status_bar) ~= "table" then
            error("status_bar must be a table")
        end
        assert_known_keys(opts.status_bar, STATUS_BAR_KEYS, "status_bar")
    end

    if opts.keybind ~= nil and opts.keybind ~= false then
        if type(opts.keybind) ~= "table" then
            error("keybind must be false or a table")
        end
        assert_known_keys(opts.keybind, KEYBIND_KEYS, "keybind")
    end

    local merged = merge_tables(M.config, opts)
    local normalized = {
        trigger = require_non_empty_string(merged.trigger, "trigger"),
        keybind = normalize_keybind(merged.keybind),
        bj_path = require_non_empty_string(merged.bj_path, "bj_path"),
        config_path = optional_string(merged.config_path, "config_path"),
        min_bj_version = require_non_empty_string(merged.min_bj_version, "min_bj_version"),
        colors = not not merged.colors,
        command_palette = not not merged.command_palette,
        controls = {},
        stats = normalize_stats(merged.stats),
        status_bar = normalize_status_bar(merged.status_bar),
    }

    for _, control_name in ipairs(action_domain.control_names()) do
        normalized.controls[control_name] = normalize_control_value(merged.controls[control_name], control_name)
    end

    return normalized
end

local function pane_key(pane)
    if pane and pane.pane_id then
        local ok_id, id = pcall(function()
            return pane:pane_id()
        end)
        if ok_id and id then
            return tostring(id)
        end
    end
    return tostring(pane)
end

local function call_first_method(obj, method_names)
    for _, method_name in ipairs(method_names) do
        if type(obj[method_name]) == "function" then
            local ok, result = pcall(function()
                return obj[method_name](obj)
            end)
            if ok and type(result) == "table" then
                return result
            end
        end
    end
    return nil
end

local function collect_live_pane_keys()
    local mux = wezterm.mux
    if type(mux) ~= "table" or type(mux.all_windows) ~= "function" then
        return nil
    end

    local ok_windows, windows = pcall(function()
        return mux.all_windows()
    end)
    if not ok_windows or type(windows) ~= "table" then
        return nil
    end

    local live = {}

    local function mark_tab_panes(tab)
        local panes = call_first_method(tab, { "panes_with_info", "panes" })
        if type(panes) ~= "table" then
            return
        end

        for _, pane_info in ipairs(panes) do
            local pane = pane_info
            if type(pane_info) == "table" and pane_info.pane ~= nil then
                pane = pane_info.pane
            end
            live[pane_key(pane)] = true
        end
    end

    local function mark_window_panes(window)
        local tabs = call_first_method(window, { "tabs_with_info", "tabs" })
        if type(tabs) ~= "table" then
            return
        end

        for _, tab_info in ipairs(tabs) do
            local tab = tab_info
            if type(tab_info) == "table" and tab_info.tab ~= nil then
                tab = tab_info.tab
            end
            mark_tab_panes(tab)
        end
    end

    for _, window_info in ipairs(windows) do
        local window = window_info
        if type(window_info) == "table" and window_info.window ~= nil then
            window = window_info.window
        end
        mark_window_panes(window)
    end

    return live
end

local function prune_stale_games()
    local live = collect_live_pane_keys()
    if not live then
        return
    end

    for key in pairs(pane_games) do
        if not live[key] then
            pane_games[key] = nil
        end
    end
end

local function get_game(pane)
    prune_stale_games()
    local key = pane_key(pane)
    pane_games[key] = pane_games[key] or {
        state = nil,
        stats = { wins = 0, losses = 0, pushes = 0 },
        settled_signature = nil,
        message = nil,
    }
    return pane_games[key]
end

local function clear_and_home(pane)
    pane:send_text("\x1b[2J\x1b[H")
end

local function render_game(game)
    return ui_renderer.render_game(game, {
        actions = action_domain,
        state_domain = state_domain,
        controls = M.config.controls,
        colors_enabled = M.config.colors,
    })
end

local function render_to_pane(game, pane)
    clear_and_home(pane)
    pane:send_text(render_game(game) .. "\r\n")
end

local function activate_key_table(window, pane)
    window:perform_action(
        wezterm.action.ActivateKeyTable({
            name = KEY_TABLE,
            one_shot = false,
            prevent_fallback = true,
        }),
        pane
    )
end

local function pop_key_table(window, pane)
    window:perform_action(wezterm.action.PopKeyTable, pane)
end

local function start_game(window, pane)
    local game = get_game(pane)
    local state, err = bj_transport.run_new(M.config, transport_deps)
    if not state then
        pane:send_text("\r\nBlackjack failed to start using '" .. M.config.bj_path .. "'.\r\n")
        pane:send_text("Install with: cargo install blackjack\r\n")
        if err and err ~= "" then
            pane:send_text("bj error: " .. err .. "\r\n")
        end
        return
    end

    game.state = state
    game.settled_signature = nil
    game.message = nil
    stats_store.record_finished_stats(game)
    render_to_pane(game, pane)
    activate_key_table(window, pane)
end

local apply_action

local function key_action(action_id)
    return wezterm.action_callback(function(window, pane)
        apply_action(window, pane, action_id)
    end)
end

local function collect_control_keys(value, callback)
    if not value then
        return
    end
    if type(value) ~= "table" then
        value = { value }
    end

    local seen = {}
    for _, key in ipairs(value) do
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            callback(key)
        end
    end
end

local function build_key_table()
    local entries = {}
    local reserved = { Escape = true }
    local assigned = {}

    for _, action_id in ipairs(action_domain.ordered_ids()) do
        local action = action_domain.get(action_id)
        collect_control_keys(M.config.controls[action.control], function(key)
            reserved[key] = true
        end)
    end

    for _, action_id in ipairs(action_domain.ordered_ids()) do
        local action = action_domain.get(action_id)
        collect_control_keys(M.config.controls[action.control], function(key)
            if not assigned[key] then
                assigned[key] = true
                entries[#entries + 1] = { key = key, action = key_action(action_id) }
            end

            if #key == 1 and key:lower() == key then
                local upper = key:upper()
                if upper ~= key and not reserved[upper] then
                    reserved[upper] = true
                    assigned[upper] = true
                    entries[#entries + 1] = { key = upper, action = key_action(action_id) }
                end
            end
        end)
    end

    entries[#entries + 1] = { key = "Escape", action = key_action("quit") }
    return entries
end

apply_action = function(window, pane, action_id)
    local action = action_domain.get(action_id)
    if not action then
        return
    end

    local game = get_game(pane)

    if action_id == "quit" then
        game.state = nil
        game.settled_signature = nil
        pop_key_table(window, pane)
        pane:send_text("\r\nBlackjack closed.\r\n")
        return
    end

    if not action_domain.is_allowed(action_id, game.state) then
        return
    end

    local next_state
    local err

    if action_id == "new" then
        next_state, err = bj_transport.run_new(M.config, transport_deps)
    else
        next_state, err = bj_transport.run_action(M.config, transport_deps, action.cli_args, game.state)
    end

    if not next_state then
        game.message = "Action unavailable: " .. (err or action_id)
        render_to_pane(game, pane)
        return
    end

    if action_id == "new" then
        game.settled_signature = nil
    end

    game.state = next_state
    game.message = nil
    stats_store.record_finished_stats(game)
    render_to_pane(game, pane)
end

local function command_palette_entries()
    return {
        {
            brief = "Blackjack: New Game",
            doc = "Start blackjack in the active pane",
            action = wezterm.action.EmitEvent(EVENT_ACTION),
        },
        {
            brief = "Blackjack: Reset Stats",
            doc = "Reset blackjack statistics",
            action = wezterm.action.EmitEvent(EVENT_RESET_STATS),
        },
        {
            brief = "Blackjack: Health Check",
            doc = "Check the configured bj CLI",
            action = wezterm.action.EmitEvent(EVENT_HEALTH),
        },
    }
end

local register_events = wezterm_events.new({
    wezterm = wezterm,
    event_names = {
        action = EVENT_ACTION,
        health = EVENT_HEALTH,
        reset_stats = EVENT_RESET_STATS,
        user_var = USER_VAR,
    },
    start_game = start_game,
    reset_stats = function()
        M.reset_stats()
    end,
    get_game = get_game,
    render_to_pane = render_to_pane,
    health_check = function()
        return M.health_check()
    end,
    get_trigger = function()
        return M.config.trigger
    end,
    command_palette_enabled = function()
        return M.config.command_palette
    end,
    command_palette_entries = command_palette_entries,
})

function M.apply_to_config(config, opts)
    config = config or {}
    M.config = normalize_config(opts)
    stats_store.load_persisted_stats()
    register_events()

    config.keys = config.keys or {}
    config.key_tables = config.key_tables or {}
    config.key_tables[KEY_TABLE] = build_key_table()

    if M.config.keybind then
        config.keys[#config.keys + 1] = {
            key = M.config.keybind.key,
            mods = M.config.keybind.mods,
            action = wezterm.action.EmitEvent(EVENT_ACTION),
        }
    end

    return config
end

function M.new_game()
    return wezterm.action.EmitEvent(EVENT_ACTION)
end

function M.trigger_command()
    local encoded = M.config.trigger
    return string.format("printf '\\033]1337;SetUserVar=%s=%%s\\007' \"$(printf %%s %q | base64)\"", USER_VAR, encoded)
end

function M.get_status_elements()
    if not M.config.status_bar.enabled then
        return {}
    end

    local stats = M.get_stats()
    local elements = {
        { Foreground = { Color = M.config.status_bar.color } },
        { Text = M.config.status_bar.icon .. " " },
    }

    if stats.wins > 0 or stats.losses > 0 or stats.pushes > 0 then
        elements[#elements + 1] = { Foreground = { Color = "#9ece6a" } }
        elements[#elements + 1] = { Text = string.format("%dW ", stats.wins) }
        elements[#elements + 1] = { Foreground = { Color = "#f7768e" } }
        elements[#elements + 1] = { Text = string.format("%dL ", stats.losses) }
        if stats.pushes > 0 then
            elements[#elements + 1] = { Foreground = { Color = "#e0af68" } }
            elements[#elements + 1] = { Text = string.format("%dP ", stats.pushes) }
        end
    end

    return elements
end

function M.get_stats(pane)
    if pane then
        return stats_store.copy_stats(get_game(pane).stats)
    end

    prune_stale_games()
    if M.config.stats.persist then
        return stats_store.copy_stats(stats_store.load_persisted_stats())
    end

    return stats_store.aggregate_stats(pane_games)
end

function M.reset_stats(pane)
    if pane then
        get_game(pane).stats = stats_store.copy_stats(nil)
        return
    end

    prune_stale_games()
    for _, game in pairs(pane_games) do
        game.stats = stats_store.copy_stats(nil)
    end
    stats_store.reset_persisted_stats()
end

local function parse_version(text)
    if not text then
        return nil
    end
    local major, minor, patch = tostring(text):match("(%d+)%.(%d+)%.(%d+)")
    if not major then
        return nil
    end
    return {
        major = tonumber(major),
        minor = tonumber(minor),
        patch = tonumber(patch),
        raw = major .. "." .. minor .. "." .. patch,
    }
end

local function compare_versions(a, b)
    if not a or not b then
        return nil
    end
    for _, key in ipairs({ "major", "minor", "patch" }) do
        if a[key] < b[key] then
            return -1
        end
        if a[key] > b[key] then
            return 1
        end
    end
    return 0
end

function M.health_check()
    local success, stdout, stderr = wezterm.run_child_process({ M.config.bj_path, "--version" })
    local version = parse_version(stdout)
    local minimum = parse_version(M.config.min_bj_version)
    local version_ok = success and (not minimum or not version or compare_versions(version, minimum) >= 0)

    return {
        ok = success and version_ok,
        bj_path = M.config.bj_path,
        version = success and stdout:gsub("%s+$", "") or nil,
        detected_version = version and version.raw or nil,
        min_version = M.config.min_bj_version,
        version_ok = version_ok,
        error = success and (version_ok and nil or ("bj must be >= " .. M.config.min_bj_version)) or stderr,
        key_table = KEY_TABLE,
        trigger_user_var = USER_VAR,
        stats_path = stats_store.stats_path(),
    }
end

M._private = {
    render_game = render_game,
    hand_value = state_domain.hand_value,
    settlement_signature = function(state)
        return state_domain.settlement_signature(state, wezterm.json_encode)
    end,
    get_game = get_game,
    record_finished_stats = stats_store.record_finished_stats,
    parse_version = parse_version,
    compare_versions = compare_versions,
    apply_action = apply_action,
    build_key_table = build_key_table,
    normalize_config = normalize_config,
    validate_state_shape = state_domain.validate_state_shape,
    prune_stale_games = prune_stale_games,
}

return M
