-- wezterm-blackjack: A blackjack plugin for WezTerm
-- https://github.com/KevinTCoughlin/wezterm-blackjack

local wezterm = require("wezterm")
local utils = require("plugin.lib")

local M = {}

-- Default configuration
M.config = {
    trigger = "/deal",
    keybind = { key = "b", mods = "LEADER" },  -- Set to false to disable
    config_path = nil,
    bj_path = "bj", -- Path to bj binary
    status_bar = {
        enabled = false,           -- Show in status bar
        icon = "🃏",               -- Icon to display
        color = "#9ece6a",         -- Icon color
        position = "right",        -- "left" or "right"
    },
}

-- Game state
local game_state = nil
local game_pane = nil
local stats = { wins = 0, losses = 0, pushes = 0 }

-- Check if bj is installed
local function check_bj_installed()
    local success, stdout, stderr = wezterm.run_child_process({ M.config.bj_path, "--version" })
    return success
end

-- Run bj command and parse JSON output
local function run_bj(args)
    local cmd = { M.config.bj_path }
    for _, arg in ipairs(args) do
        table.insert(cmd, arg)
    end

    local success, stdout, stderr = utils.safe_run(cmd)
    if not success then
        wezterm.log_error("bj command failed: " .. (stderr or "unknown error"))
        return nil
    end

    local ok, result = pcall(wezterm.json_parse, stdout)
    if not ok then
        utils.log("Failed to parse bj output: " .. tostring(result), "WARN")
        return nil, stdout -- Return raw output if not JSON
    end
    return result
end

-- Run bj command with state input (safe JSON passing via temp file)
local function run_bj_with_state(action, state)
    local json_state = wezterm.json_encode(state)
    
    if not json_state then
        wezterm.log_error("Failed to encode state to JSON")
        return nil
    end
    
    -- Write JSON to temp file instead of shell escaping
    local tmp_file = utils.get_temp_file("wezterm-bj", ".json")
    if not utils.safe_write_file(tmp_file, json_state) then
        wezterm.log_error("Failed to write state to temp file")
        return nil
    end
    
    -- Use array form to avoid shell injection
    local cmd = { M.config.bj_path, action }
    local success, stdout, stderr
    
    -- Read from file and pipe to command
    if utils.is_windows() then
        success, stdout, stderr = utils.safe_run({
            "powershell", "-Command",
            string.format("Get-Content '%s' | & '%s' %s", 
                tmp_file:gsub("'", "''"), 
                M.config.bj_path:gsub("'", "''"), 
                action:gsub("'", "''"))
        })
    else
        success, stdout, stderr = utils.safe_run({
            "sh", "-c",
            "cat " .. utils.escape_applescript(tmp_file) .. " | " .. M.config.bj_path .. " " .. action
        })
    end
    
    -- Clean up temp file
    os.remove(tmp_file)
    
    if not success then
        wezterm.log_error("bj command failed: " .. (stderr or "unknown error"))
        return nil
    end

    local ok, result = pcall(wezterm.json_parse, stdout)
    if not ok then
        return nil
    end
    return result
end

-- Render card with box drawing
local function render_card(card_str)
    if card_str == "??" then
        return "[??]"
    end
    return "[" .. card_str .. "]"
end

-- Render hand
local function render_hand(cards)
    local result = {}
    for _, card in ipairs(cards) do
        local card_str = card.rank:sub(1, 1)
        if card.rank == "Ten" then
            card_str = "10"
        end
        local suit_symbols = {
            Spades = "♠",
            Hearts = "♥",
            Diamonds = "♦",
            Clubs = "♣",
        }
        card_str = card_str .. suit_symbols[card.suit]
        table.insert(result, render_card(card_str))
    end
    return table.concat(result, " ")
end

-- Calculate hand value (simplified)
local function calculate_value(cards)
    local value = 0
    local aces = 0

    for _, card in ipairs(cards) do
        local rank = card.rank
        if rank == "Ace" then
            aces = aces + 1
            value = value + 11
        elseif rank == "Jack" or rank == "Queen" or rank == "King" then
            value = value + 10
        elseif rank == "Ten" then
            value = value + 10
        else
            -- Two through Nine
            local rank_values = {
                Two = 2,
                Three = 3,
                Four = 4,
                Five = 5,
                Six = 6,
                Seven = 7,
                Eight = 8,
                Nine = 9,
            }
            value = value + (rank_values[rank] or 0)
        end
    end

    while value > 21 and aces > 0 do
        value = value - 10
        aces = aces - 1
    end

    return value
end

-- Render game UI
local function render_game(state)
    local lines = {}

    table.insert(lines, "┌─────────────────────────────────────────┐")
    table.insert(lines, "│              BLACKJACK                  │")
    table.insert(lines, "├─────────────────────────────────────────┤")

    -- Dealer hand
    local dealer_cards = state.dealer_hand.cards or {}
    local dealer_display
    local dealer_value

    if state.phase.type == "Finished" or state.phase.type == "DealerTurn" then
        dealer_display = render_hand(dealer_cards)
        dealer_value = "Value: " .. calculate_value(dealer_cards)
    else
        -- Hide hole card
        if #dealer_cards >= 2 then
            local visible_card = dealer_cards[2]
            local card_str = visible_card.rank:sub(1, 1)
            if visible_card.rank == "Ten" then
                card_str = "10"
            end
            local suit_symbols = {
                Spades = "♠",
                Hearts = "♥",
                Diamonds = "♦",
                Clubs = "♣",
            }
            dealer_display = "[??] " .. render_card(card_str .. suit_symbols[visible_card.suit])
        else
            dealer_display = ""
        end
        dealer_value = "Value: ?"
    end

    table.insert(lines, string.format("│  Dealer: %-30s│", dealer_display))
    table.insert(lines, string.format("│%40s│", dealer_value))
    table.insert(lines, "│                                         │")

    -- Player hands
    for i, hand in ipairs(state.player_hands or {}) do
        local hand_label = #state.player_hands > 1 and ("Hand " .. i .. ": ") or "You:    "
        local cards_str = render_hand(hand.cards or {})
        table.insert(lines, string.format("│  %s%-28s│", hand_label, cards_str))

        local value = calculate_value(hand.cards or {})
        local status
        if value == 21 and #(hand.cards or {}) == 2 then
            status = "BLACKJACK!"
        elseif value > 21 then
            status = "BUST!"
        else
            status = "Value: " .. value
            if state.phase.type == "PlayerTurn" and state.phase.data == i - 1 then
                status = status .. " ◄"
            end
        end
        table.insert(lines, string.format("│%40s│", status))
    end

    table.insert(lines, "├─────────────────────────────────────────┤")

    -- Actions or outcomes
    if state.phase.type == "Finished" then
        for _, outcome in ipairs(state.outcomes or {}) do
            local result = outcome.outcome
            local payout = outcome.payout
            local payout_str = payout >= 0 and ("+" .. payout .. "x") or (payout .. "x")
            table.insert(lines, string.format("│  %-20s %17s│", result, payout_str))
        end
    else
        local actions = "[H]it [S]tand [D]ouble [P]split [Q]uit"
        table.insert(lines, string.format("│  %-39s│", actions))
    end

    table.insert(
        lines,
        string.format("│  Wins: %d  Losses: %d  Pushes: %d          │", stats.wins, stats.losses, stats.pushes)
    )
    table.insert(lines, "└─────────────────────────────────────────┘")

    return table.concat(lines, "\r\n")
end

-- Handle key input during game
local function handle_game_key(window, pane, key)
    if not game_state then
        return false
    end

    local action = nil

    if key == "h" or key == "H" then
        action = "hit"
    elseif key == "s" or key == "S" then
        action = "stand"
    elseif key == "d" or key == "D" then
        action = "double"
    elseif key == "p" or key == "P" then
        action = "split"
    elseif key == "u" or key == "U" then
        action = "surrender"
    elseif key == "y" or key == "Y" then
        game_state = run_bj_with_state("insurance --accept", game_state)
    elseif key == "n" or key == "N" then
        if game_state.phase.type == "Insurance" then
            game_state = run_bj_with_state("insurance", game_state)
        else
            -- New game
            game_state = run_bj({ "new" })
        end
    elseif key == "q" or key == "Q" then
        game_state = nil
        return true -- Exit game
    end

    if action and game_state then
        game_state = run_bj_with_state(action, game_state)
    end

    if game_state then
        -- Update stats
        if game_state.phase.type == "Finished" then
            for _, outcome in ipairs(game_state.outcomes or {}) do
                if outcome.outcome == "Win" or outcome.outcome == "Blackjack" then
                    stats.wins = stats.wins + 1
                elseif outcome.outcome == "Lose" or outcome.outcome == "Bust" then
                    stats.losses = stats.losses + 1
                elseif outcome.outcome == "Push" then
                    stats.pushes = stats.pushes + 1
                end
            end
        end

        -- Render and display
        local output = render_game(game_state)
        pane:send_text("\x1b[2J\x1b[H" .. output .. "\r\n")
    end

    return game_state ~= nil
end

-- Start a new game
local function start_game(window, pane)
    if not check_bj_installed() then
        pane:send_text("\r\n")
        pane:send_text("Blackjack requires the 'bj' CLI to be installed.\r\n")
        pane:send_text("Install with: cargo install blackjack\r\n")
        pane:send_text("\r\n")
        return
    end

    game_state = run_bj({ "new" })
    game_pane = pane

    if game_state then
        local output = render_game(game_state)
        pane:send_text("\x1b[2J\x1b[H" .. output .. "\r\n")
    else
        pane:send_text("\r\nFailed to start blackjack game.\r\n")
    end
end

-- Get status bar elements for integration
function M.get_status_elements()
    if not M.config.status_bar.enabled then
        return {}
    end

    local elements = {
        { Foreground = { Color = M.config.status_bar.color } },
        { Text = M.config.status_bar.icon .. " " },
    }

    -- Show stats if game has been played
    if stats.wins > 0 or stats.losses > 0 then
        table.insert(elements, { Foreground = { Color = "#565f89" } })
        table.insert(elements, { Text = string.format("%d/%d ", stats.wins, stats.wins + stats.losses) })
    end

    return elements
end

-- Apply configuration to WezTerm config
function M.apply_to_config(config, opts)
    opts = opts or {}

    -- Deep merge options
    for k, v in pairs(opts) do
        if type(v) == "table" and type(M.config[k]) == "table" then
            for k2, v2 in pairs(v) do
                M.config[k][k2] = v2
            end
        else
            M.config[k] = v
        end
    end

    -- Add key binding (if not disabled)
    if M.config.keybind then
        config.keys = config.keys or {}
        table.insert(config.keys, {
            key = M.config.keybind.key,
            mods = M.config.keybind.mods,
            action = wezterm.action_callback(function(window, pane)
                start_game(window, pane)
            end),
        })
    end

    return config
end

-- Toggle game (for keybinding)
function M.toggle()
    return wezterm.action_callback(function(window, pane)
        if game_state then
            game_state = nil
            pane:send_text("\r\nBlackjack closed.\r\n")
        else
            start_game(window, pane)
        end
    end)
end

-- Action for starting a new game
function M.new_game()
    return wezterm.action_callback(function(window, pane)
        start_game(window, pane)
    end)
end

-- Get current stats
function M.get_stats()
    return stats
end

-- Reset stats
function M.reset_stats()
    stats = { wins = 0, losses = 0, pushes = 0 }
end

return M
