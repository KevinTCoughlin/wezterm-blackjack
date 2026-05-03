-- wezterm-blackjack: A blackjack plugin for WezTerm
-- https://github.com/KevinTCoughlin/wezterm-blackjack

local wezterm = require("wezterm")

local ok, utils = pcall(require, "plugin.lib")
if not ok then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    local plugin_dir = source:match("(.*/)") or "./"
    utils = dofile(plugin_dir .. "lib.lua")
end

local M = {}

local EVENT_ACTION = "wezterm-blackjack-action"
local EVENT_HEALTH = "wezterm-blackjack-health"
local EVENT_RESET_STATS = "wezterm-blackjack-reset-stats"
local USER_VAR = "wezterm_blackjack"
local KEY_TABLE = "wezterm_blackjack"

M.config = {
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

local pane_games = {}
local persisted_stats = nil
local events_registered = false

local colors = {
    reset = "\x1b[0m",
    dim = "\x1b[2m",
    red = "\x1b[31m",
    green = "\x1b[32m",
    yellow = "\x1b[33m",
    cyan = "\x1b[36m",
    white = "\x1b[37m",
}

local function colorize(text, color)
    if not M.config.colors then
        return text
    end
    return (colors[color] or "") .. text .. colors.reset
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

local function get_game(pane)
    local key = pane_key(pane)
    pane_games[key] = pane_games[key] or {
        state = nil,
        stats = { wins = 0, losses = 0, pushes = 0 },
        settled_signature = nil,
        message = nil,
    }
    return pane_games[key]
end

local function default_stats_path()
    local home = wezterm.home_dir or os.getenv("HOME") or "."
    return home .. "/.local/state/wezterm-blackjack/stats.json"
end

local function copy_stats(stats)
    return {
        wins = tonumber(stats and stats.wins) or 0,
        losses = tonumber(stats and stats.losses) or 0,
        pushes = tonumber(stats and stats.pushes) or 0,
    }
end

local function stats_path()
    return M.config.stats.path or default_stats_path()
end

local function load_persisted_stats()
    if not M.config.stats.persist then
        persisted_stats = nil
        return { wins = 0, losses = 0, pushes = 0 }
    end
    if persisted_stats then
        return persisted_stats
    end

    local content = utils.read_file(stats_path())
    local decoded = content and utils.safe_json_parse(content)
    persisted_stats = copy_stats(decoded)
    return persisted_stats
end

local function save_persisted_stats()
    if not M.config.stats.persist then
        return
    end

    persisted_stats = copy_stats(persisted_stats)
    local encoded = utils.safe_json_encode(persisted_stats)
    if encoded then
        local ok, err = utils.write_file(stats_path(), encoded .. "\n")
        if not ok then
            utils.log("failed to save stats: " .. tostring(err), "WARN")
        end
    end
end

local function add_stats(target, delta)
    target.wins = (target.wins or 0) + (delta.wins or 0)
    target.losses = (target.losses or 0) + (delta.losses or 0)
    target.pushes = (target.pushes or 0) + (delta.pushes or 0)
end

local function clear_and_home(pane)
    pane:send_text("\x1b[2J\x1b[H")
end

local function run_bj(args)
    local cmd = { M.config.bj_path }
    for _, arg in ipairs(args) do
        table.insert(cmd, arg)
    end
    if args[1] == "new" and M.config.config_path then
        table.insert(cmd, "--config")
        table.insert(cmd, M.config.config_path)
    end

    local success, stdout, stderr = utils.safe_run(cmd)
    if not success then
        return nil, stderr or stdout or "unknown error"
    end

    local result = utils.safe_json_parse(stdout)
    if not result then
        return nil, "failed to parse bj JSON output"
    end
    return result
end

local function run_bj_with_state(action, state)
    local json_state = utils.safe_json_encode(state)
    if not json_state then
        return nil, "failed to encode game state"
    end

    local argv = utils.split_args(action)
    table.insert(argv, 1, M.config.bj_path)

    local success, stdout, stderr = utils.safe_run_with_stdin(argv, json_state)
    if not success then
        return nil, stderr or stdout or "unknown error"
    end

    local result = utils.safe_json_parse(stdout)
    if not result then
        return nil, "failed to parse bj JSON output"
    end
    return result
end

local function hand_value(cards)
    local value = 0
    local aces = 0
    local rank_values = {
        Two = 2,
        Three = 3,
        Four = 4,
        Five = 5,
        Six = 6,
        Seven = 7,
        Eight = 8,
        Nine = 9,
        Ten = 10,
        Jack = 10,
        Queen = 10,
        King = 10,
    }

    for _, card in ipairs(cards or {}) do
        if card.rank == "Ace" then
            aces = aces + 1
            value = value + 11
        else
            value = value + (rank_values[card.rank] or 0)
        end
    end

    while value > 21 and aces > 0 do
        value = value - 10
        aces = aces - 1
    end

    return value
end

local function card_text(card)
    local ranks = {
        Ace = "A",
        Jack = "J",
        Queen = "Q",
        King = "K",
        Ten = "10",
    }
    local suits = {
        Spades = "♠",
        Hearts = "♥",
        Diamonds = "♦",
        Clubs = "♣",
    }

    local rank = ranks[card.rank] or card.rank:sub(1, 1)
    return rank .. (suits[card.suit] or "?")
end

local function render_card(card)
    if card == "??" then
        return colorize("[??]", "dim")
    end

    local text = card_text(card)
    local suit_color = (card.suit == "Hearts" or card.suit == "Diamonds") and "red" or "white"
    return colorize("[" .. text .. "]", suit_color)
end

local function render_hand(cards)
    local rendered = {}
    for _, card in ipairs(cards or {}) do
        table.insert(rendered, render_card(card))
    end
    return table.concat(rendered, " ")
end

local function display_len(text)
    return #(text:gsub("\x1b%[[0-9;]*m", ""))
end

local function fit(text, width)
    local len = display_len(text)
    if len == width then
        return text
    end
    if len < width then
        return text .. string.rep(" ", width - len)
    end

    local plain = text:gsub("\x1b%[[0-9;]*m", "")
    return plain:sub(1, math.max(0, width - 1)) .. "…"
end

local function right(text, width)
    local len = display_len(text)
    if len >= width then
        return fit(text, width)
    end
    return string.rep(" ", width - len) .. text
end

local function row(left, right_text)
    local content_width = 57
    right_text = right_text or ""
    local gap = content_width - display_len(left) - display_len(right_text)
    if gap < 1 then
        return "│ " .. fit(left .. " " .. right_text, content_width) .. " │"
    end
    return "│ " .. left .. string.rep(" ", gap) .. right_text .. " │"
end

local function outcome_color(outcome)
    if outcome == "Win" or outcome == "Blackjack" then
        return "green"
    end
    if outcome == "Lose" or outcome == "Bust" then
        return "red"
    end
    return "yellow"
end

local function first_present(state, keys)
    for _, key in ipairs(keys) do
        local value = state[key]
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function render_table_fields(label, fields)
    local parts = {}
    for _, field in ipairs(fields) do
        if field.value ~= nil then
            table.insert(parts, field.label .. ": " .. tostring(field.value))
        end
    end
    if #parts == 0 then
        return nil
    end
    return label .. "  " .. table.concat(parts, "  ")
end

local function control_value(name)
    return M.config.controls[name]
end

local function primary_control(name)
    local value = control_value(name)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function control_label(name, label)
    local key = primary_control(name)
    if not key then
        return label
    end
    local display_key = (#key == 1) and key:upper() or key
    return "[" .. display_key .. "]" .. label
end

local function render_game(game)
    local state = game.state
    local stats = game.stats
    local lines = {}

    table.insert(lines, "┌───────────────────────────────────────────────────────────┐")
    table.insert(lines, row(colorize("BLACKJACK", "cyan"), colorize("modal keys active", "dim")))
    table.insert(lines, "├───────────────────────────────────────────────────────────┤")

    local table_info = render_table_fields("Table", {
        { label = "Bankroll", value = first_present(state, { "bankroll", "balance", "chips" }) },
        { label = "Bet", value = first_present(state, { "bet", "wager", "current_bet" }) },
    })
    if table_info then
        table.insert(lines, row(table_info))
        table.insert(lines, row(""))
    end

    local dealer_cards = state.dealer_hand.cards or {}
    local show_dealer = state.phase.type == "Finished" or state.phase.type == "DealerTurn"
    local dealer_display = ""
    local dealer_value = "Value: ?"

    if show_dealer then
        dealer_display = render_hand(dealer_cards)
        dealer_value = "Value: " .. hand_value(dealer_cards)
    elseif #dealer_cards >= 2 then
        dealer_display = render_card("??") .. " " .. render_card(dealer_cards[2])
    end

    table.insert(lines, row("Dealer: " .. dealer_display, dealer_value))
    table.insert(lines, row(""))

    for i, hand in ipairs(state.player_hands or {}) do
        local cards = hand.cards or {}
        local active = state.phase.type == "PlayerTurn" and state.phase.data == i - 1
        local label = #state.player_hands > 1 and ("Hand " .. i .. ": ") or "You:    "
        local value = hand_value(cards)
        local status

        if value == 21 and #cards == 2 then
            status = colorize("BLACKJACK!", "green")
        elseif value > 21 then
            status = colorize("BUST!", "red")
        else
            status = "Value: " .. value
            if active then
                status = colorize(status .. " <", "cyan")
            end
        end

        table.insert(lines, row(label .. render_hand(cards), status))
    end

    table.insert(lines, "├───────────────────────────────────────────────────────────┤")

    if state.phase.type == "Finished" then
        for _, outcome in ipairs(state.outcomes or {}) do
            local payout = outcome.payout or 0
            local payout_str = payout >= 0 and ("+" .. payout .. "x") or (payout .. "x")
            table.insert(lines, row(colorize(outcome.outcome or "Finished", outcome_color(outcome.outcome)), payout_str))
        end
        table.insert(lines, row(colorize(control_label("new_game", "ew game"), "cyan") .. "  " .. control_label("quit", "uit")))
    elseif state.phase.type == "Insurance" then
        table.insert(
            lines,
            row(
                control_label("insurance_accept", "es insurance")
                    .. "  "
                    .. control_label("insurance_decline", "o insurance")
                    .. "  "
                    .. control_label("quit", "uit")
            )
        )
    else
        table.insert(
            lines,
            row(
                control_label("hit", "it")
                    .. "  "
                    .. control_label("stand", "tand")
                    .. "  "
                    .. control_label("double", "ouble")
                    .. "  "
                    .. control_label("split", "split")
                    .. "  "
                    .. control_label("surrender", "surrender")
                    .. "  "
                    .. control_label("quit", "uit")
            )
        )
    end

    if state.insurance_bet then
        table.insert(lines, row(colorize("Insurance accepted", "yellow")))
    end

    if game.message then
        table.insert(lines, row(colorize(game.message, "yellow")))
    end

    table.insert(lines, row(string.format("Wins: %d  Losses: %d  Pushes: %d", stats.wins, stats.losses, stats.pushes)))
    table.insert(lines, "└───────────────────────────────────────────────────────────┘")

    return table.concat(lines, "\r\n")
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

local function render_to_pane(game, pane)
    clear_and_home(pane)
    pane:send_text(render_game(game) .. "\r\n")
end

local function settlement_signature(state)
    if not state or state.phase.type ~= "Finished" then
        return nil
    end
    return wezterm.json_encode(state.outcomes or {})
end

local function record_finished_stats(game)
    local signature = settlement_signature(game.state)
    if not signature or signature == game.settled_signature then
        return
    end

    local delta = { wins = 0, losses = 0, pushes = 0 }
    for _, outcome in ipairs(game.state.outcomes or {}) do
        if outcome.outcome == "Win" or outcome.outcome == "Blackjack" then
            delta.wins = delta.wins + 1
        elseif outcome.outcome == "Lose" or outcome.outcome == "Bust" then
            delta.losses = delta.losses + 1
        elseif outcome.outcome == "Push" then
            delta.pushes = delta.pushes + 1
        end
    end

    add_stats(game.stats, delta)
    if M.config.stats.persist then
        add_stats(load_persisted_stats(), delta)
        save_persisted_stats()
    end

    game.settled_signature = signature
end

local function start_game(window, pane)
    local game = get_game(pane)
    local state, err = run_bj({ "new" })
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
    record_finished_stats(game)
    render_to_pane(game, pane)
    activate_key_table(window, pane)
end

local function apply_action(window, pane, action)
    local game = get_game(pane)
    if not game.state and action ~= "new" then
        return
    end

    if action == "quit" then
        game.state = nil
        game.settled_signature = nil
        pop_key_table(window, pane)
        pane:send_text("\r\nBlackjack closed.\r\n")
        return
    end

    local next_state
    local err

    if action == "new" then
        next_state, err = run_bj({ "new" })
    elseif action == "insurance-accept" then
        next_state, err = run_bj_with_state("insurance --accept", game.state)
    elseif action == "insurance-decline" then
        if game.state.phase.type == "Insurance" then
            next_state, err = run_bj_with_state("insurance", game.state)
        else
            next_state, err = run_bj({ "new" })
        end
    else
        next_state, err = run_bj_with_state(action, game.state)
    end

    if not next_state then
        game.message = "Action unavailable: " .. (err or action)
        render_to_pane(game, pane)
        return
    end

    game.state = next_state
    game.message = nil
    record_finished_stats(game)
    render_to_pane(game, pane)
end

local function key_action(action)
    return wezterm.action_callback(function(window, pane)
        apply_action(window, pane, action)
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
    local table_entries = {}
    local reserved = { Escape = true }
    local assigned = {}
    local actions = {
        hit = "hit",
        stand = "stand",
        double = "double",
        split = "split",
        surrender = "surrender",
        insurance_accept = "insurance-accept",
        insurance_decline = "insurance-decline",
        new_game = "new",
        quit = "quit",
    }

    for control in pairs(actions) do
        collect_control_keys(M.config.controls[control], function(key)
            reserved[key] = true
        end)
    end

    for control, action in pairs(actions) do
        collect_control_keys(M.config.controls[control], function(key)
            if not assigned[key] then
                assigned[key] = true
                table.insert(table_entries, { key = key, action = key_action(action) })
            end

            if #key == 1 and key:lower() == key then
                local upper = key:upper()
                if upper ~= key and not reserved[upper] then
                    reserved[upper] = true
                    assigned[upper] = true
                    table.insert(table_entries, { key = upper, action = key_action(action) })
                end
            end
        end)
    end

    table.insert(table_entries, { key = "Escape", action = key_action("quit") })
    return table_entries
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

local function register_events()
    if events_registered then
        return
    end
    events_registered = true

    wezterm.on(EVENT_ACTION, function(window, pane)
        start_game(window, pane)
    end)

    wezterm.on(EVENT_RESET_STATS, function(window, pane)
        M.reset_stats()
        local game = get_game(pane)
        if game.state then
            game.message = "Stats reset"
            render_to_pane(game, pane)
        elseif window.toast_notification then
            window:toast_notification("Blackjack", "Stats reset", nil, 3000)
        end
    end)

    wezterm.on(EVENT_HEALTH, function(window, pane)
        local health = M.health_check()
        local message
        if health.ok then
            message = "bj " .. (health.version or "installed")
        else
            message = "bj unavailable: " .. (health.error or "unknown error")
        end

        local game = get_game(pane)
        if game.state then
            game.message = message
            render_to_pane(game, pane)
        elseif window.toast_notification then
            window:toast_notification("Blackjack", message, nil, 5000)
        else
            pane:send_text("\r\n" .. message .. "\r\n")
        end
    end)

    wezterm.on("user-var-changed", function(window, pane, name, value)
        if name == USER_VAR and value == M.config.trigger then
            start_game(window, pane)
        end
    end)

    wezterm.on("augment-command-palette", function()
        if not M.config.command_palette then
            return {}
        end
        return command_palette_entries()
    end)
end

local function merge_options(opts)
    for k, v in pairs(opts or {}) do
        if type(v) == "table" and type(M.config[k]) == "table" then
            for k2, v2 in pairs(v) do
                M.config[k][k2] = v2
            end
        else
            M.config[k] = v
        end
    end
end

function M.apply_to_config(config, opts)
    merge_options(opts)
    load_persisted_stats()
    register_events()

    config.keys = config.keys or {}
    config.key_tables = config.key_tables or {}
    config.key_tables[KEY_TABLE] = build_key_table()

    if M.config.keybind then
        table.insert(config.keys, {
            key = M.config.keybind.key,
            mods = M.config.keybind.mods,
            action = wezterm.action.EmitEvent(EVENT_ACTION),
        })
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
        table.insert(elements, { Foreground = { Color = "#9ece6a" } })
        table.insert(elements, { Text = string.format("%dW ", stats.wins) })
        table.insert(elements, { Foreground = { Color = "#f7768e" } })
        table.insert(elements, { Text = string.format("%dL ", stats.losses) })
        if stats.pushes > 0 then
            table.insert(elements, { Foreground = { Color = "#e0af68" } })
            table.insert(elements, { Text = string.format("%dP ", stats.pushes) })
        end
    end

    return elements
end

function M.get_stats(pane)
    if pane then
        local stats = get_game(pane).stats
        return { wins = stats.wins, losses = stats.losses, pushes = stats.pushes }
    end

    if M.config.stats.persist then
        return copy_stats(load_persisted_stats())
    end

    local total = { wins = 0, losses = 0, pushes = 0 }
    for _, game in pairs(pane_games) do
        total.wins = total.wins + game.stats.wins
        total.losses = total.losses + game.stats.losses
        total.pushes = total.pushes + game.stats.pushes
    end
    return total
end

function M.reset_stats(pane)
    if pane then
        get_game(pane).stats = { wins = 0, losses = 0, pushes = 0 }
        return
    end

    for _, game in pairs(pane_games) do
        game.stats = { wins = 0, losses = 0, pushes = 0 }
    end

    if M.config.stats.persist then
        persisted_stats = { wins = 0, losses = 0, pushes = 0 }
        save_persisted_stats()
    end
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
        stats_path = stats_path(),
    }
end

M._private = {
    render_game = render_game,
    hand_value = hand_value,
    settlement_signature = settlement_signature,
    get_game = get_game,
    record_finished_stats = record_finished_stats,
    parse_version = parse_version,
    compare_versions = compare_versions,
}

return M
