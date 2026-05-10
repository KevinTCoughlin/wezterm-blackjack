local M = {}

local function load_wcwidth()
    local ok, mod = pcall(require, "plugin.ui.wcwidth")
    if ok then
        return mod
    end

    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    local dir = source:match("(.*/)") or "./"
    return dofile(dir .. "wcwidth.lua")
end

local wcwidth = load_wcwidth()

local colors = {
    reset = "\x1b[0m",
    dim = "\x1b[2m",
    red = "\x1b[31m",
    green = "\x1b[32m",
    yellow = "\x1b[33m",
    cyan = "\x1b[36m",
    white = "\x1b[37m",
}

local function colorize(enabled, text, color)
    if not enabled then
        return text
    end
    return (colors[color] or "") .. text .. colors.reset
end

local function card_text(card)
    local ranks = {
        Ace = "A",
        Two = "2",
        Three = "3",
        Four = "4",
        Five = "5",
        Six = "6",
        Seven = "7",
        Eight = "8",
        Nine = "9",
        Ten = "10",
        Jack = "J",
        Queen = "Q",
        King = "K",
    }
    local suits = {
        Spades = "♠",
        Hearts = "♥",
        Diamonds = "♦",
        Clubs = "♣",
    }

    local rank = ranks[card.rank] or card.rank
    return rank .. (suits[card.suit] or "?")
end

local function render_card(card, colors_enabled)
    if card == "??" then
        return colorize(colors_enabled, "[??]", "dim")
    end

    local text = card_text(card)
    local suit_color = (card.suit == "Hearts" or card.suit == "Diamonds") and "red" or "white"
    return colorize(colors_enabled, "[" .. text .. "]", suit_color)
end

local function render_hand(cards, colors_enabled)
    local rendered = {}
    for _, card in ipairs(cards or {}) do
        rendered[#rendered + 1] = render_card(card, colors_enabled)
    end
    return table.concat(rendered, " ")
end

local function display_len(text)
    local plain = text:gsub("\x1b%[[0-9;]*m", "")
    return wcwidth.wcswidth(plain)
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
    local ellipsis = "…"
    local ellipsis_width = wcwidth.wcswidth(ellipsis)
    if width <= ellipsis_width then
        return wcwidth.truncate(plain, width)
    end
    return wcwidth.truncate(plain, width - ellipsis_width) .. ellipsis
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
            parts[#parts + 1] = field.label .. ": " .. tostring(field.value)
        end
    end
    if #parts == 0 then
        return nil
    end
    return label .. "  " .. table.concat(parts, "  ")
end

local function primary_control(value)
    if type(value) == "table" then
        return value[1]
    end
    return value
end

local function control_label(controls, name, label_suffix)
    local key = primary_control(controls[name])
    if not key then
        return label_suffix
    end
    local display_key = (#key == 1) and key:upper() or key
    return "[" .. display_key .. "]" .. label_suffix
end

local function render_controls_line(state, controls, actions, colors_enabled)
    local action_ids = actions.actions_for_state(state)
    local parts = {}
    for _, action_id in ipairs(action_ids) do
        local action = actions.get(action_id)
        if action and action.control and action.label_suffix then
            local text = control_label(controls, action.control, action.label_suffix)
            if action_id == "new" then
                text = colorize(colors_enabled, text, "cyan")
            end
            parts[#parts + 1] = text
        end
    end

    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "  ")
end

function M.render_game(game, opts)
    local state = game.state
    local stats = game.stats
    local actions = opts.actions
    local state_domain = opts.state_domain
    local controls = opts.controls
    local colors_enabled = opts.colors_enabled
    local lines = {}

    lines[#lines + 1] = "┌───────────────────────────────────────────────────────────┐"
    lines[#lines + 1] = row(colorize(colors_enabled, "BLACKJACK", "cyan"), colorize(colors_enabled, "modal keys active", "dim"))
    lines[#lines + 1] = "├───────────────────────────────────────────────────────────┤"

    local table_info = render_table_fields("Table", {
        { label = "Bankroll", value = first_present(state, { "bankroll", "balance", "chips" }) },
        { label = "Bet", value = first_present(state, { "bet", "wager", "current_bet" }) },
    })
    if table_info then
        lines[#lines + 1] = row(table_info)
        lines[#lines + 1] = row("")
    end

    local dealer_cards = state.dealer_hand.cards or {}
    local phase_type = actions.phase_type(state)
    local show_dealer = phase_type == "Finished" or phase_type == "DealerTurn"
    local dealer_display = ""
    local dealer_value = "Value: ?"

    if show_dealer then
        dealer_display = render_hand(dealer_cards, colors_enabled)
        dealer_value = "Value: " .. state_domain.hand_value(dealer_cards)
    elseif #dealer_cards >= 2 then
        dealer_display = render_card("??", colors_enabled) .. " " .. render_card(dealer_cards[2], colors_enabled)
    end

    lines[#lines + 1] = row("Dealer: " .. dealer_display, dealer_value)
    lines[#lines + 1] = row("")

    for i, hand in ipairs(state.player_hands or {}) do
        local cards = hand.cards or {}
        local active = phase_type == "PlayerTurn" and state.phase.data == i - 1
        local label = #state.player_hands > 1 and ("Hand " .. i .. ": ") or "You:    "
        local value = state_domain.hand_value(cards)
        local status

        if value == 21 and #cards == 2 then
            status = colorize(colors_enabled, "BLACKJACK!", "green")
        elseif value > 21 then
            status = colorize(colors_enabled, "BUST!", "red")
        else
            status = "Value: " .. value
            if active then
                status = colorize(colors_enabled, status .. " <", "cyan")
            end
        end

        lines[#lines + 1] = row(label .. render_hand(cards, colors_enabled), status)
    end

    lines[#lines + 1] = "├───────────────────────────────────────────────────────────┤"

    if phase_type == "Finished" then
        for _, outcome in ipairs(state.outcomes or {}) do
            local payout = outcome.payout or 0
            local payout_str = payout >= 0 and ("+" .. payout .. "x") or (payout .. "x")
            lines[#lines + 1] = row(colorize(colors_enabled, outcome.outcome or "Finished", outcome_color(outcome.outcome)), payout_str)
        end
    end

    local controls_line = render_controls_line(state, controls, actions, colors_enabled)
    if controls_line then
        lines[#lines + 1] = row(controls_line)
    end

    if state.insurance_bet then
        lines[#lines + 1] = row(colorize(colors_enabled, "Insurance accepted", "yellow"))
    end

    if game.message then
        lines[#lines + 1] = row(colorize(colors_enabled, game.message, "yellow"))
    end

    lines[#lines + 1] = row(string.format("Wins: %d  Losses: %d  Pushes: %d", stats.wins, stats.losses, stats.pushes))
    lines[#lines + 1] = "└───────────────────────────────────────────────────────────┘"

    return table.concat(lines, "\r\n")
end

return M
