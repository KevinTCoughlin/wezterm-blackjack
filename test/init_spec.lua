package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./plugin/?.lua",
    package.path,
}, ";")

local events = {}

package.preload["wezterm"] = function()
    local action = {}

    setmetatable(action, {
        __index = function(_, key)
            return function(value)
                return { [key] = value or true }
            end
        end,
    })

    action.PopKeyTable = { PopKeyTable = true }

    return {
        action = action,
        action_callback = function(fn)
            return { action_callback = fn }
        end,
        json_encode = function(value)
            if type(value) ~= "table" then
                return tostring(value)
            end
            local parts = {}
            for k, v in pairs(value) do
                table.insert(parts, tostring(k) .. "=" .. tostring(v))
            end
            table.sort(parts)
            return table.concat(parts, ",")
        end,
        json_parse = function()
            return {}
        end,
        log_error = function() end,
        log_warn = function() end,
        on = function(name, fn)
            events[name] = fn
        end,
        run_child_process = function()
            return false, "", "missing bj"
        end,
        target_triple = "x86_64-unknown-linux-gnu",
    }
end

local blackjack = dofile("plugin/init.lua")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
    end
end

local function assert_truthy(value, label)
    if not value then
        error(label)
    end
end

local state = {
    dealer_hand = {
        cards = {
            { rank = "King", suit = "Hearts" },
            { rank = "Seven", suit = "Clubs" },
        },
    },
    player_hands = {
        {
            cards = {
                { rank = "Ace", suit = "Spades" },
                { rank = "Nine", suit = "Diamonds" },
                { rank = "Ace", suit = "Clubs" },
            },
        },
    },
    phase = { type = "PlayerTurn", data = 0 },
}

assert_equal(blackjack._private.hand_value(state.player_hands[1].cards), 21, "soft hand value")
assert_equal(blackjack._private.compare_versions(blackjack._private.parse_version("bj 0.1.1"), blackjack._private.parse_version("0.1.0")), 1, "version compare")

local game = {
    state = state,
    stats = { wins = 0, losses = 0, pushes = 0 },
    message = "Action unavailable",
}
local output = blackjack._private.render_game(game)
assert_truthy(output:find("BLACKJACK", 1, true), "render includes title")
assert_truthy(output:find("Dealer", 1, true), "render includes dealer")
assert_truthy(output:find("Wins: 0", 1, true), "render includes stats")
assert_truthy(output:find("Action unavailable", 1, true), "render includes inline message")

game.state = {
    dealer_hand = state.dealer_hand,
    player_hands = state.player_hands,
    phase = { type = "Finished" },
    outcomes = {
        { outcome = "Win", payout = 1 },
        { outcome = "Push", payout = 0 },
    },
}

blackjack._private.record_finished_stats(game)
blackjack._private.record_finished_stats(game)
assert_equal(game.stats.wins, 1, "finished win counted once")
assert_equal(game.stats.pushes, 1, "finished push counted once")

local config = {}
blackjack.apply_to_config(config)
assert_truthy(events["wezterm-blackjack-action"], "start event registered")
assert_truthy(events["wezterm-blackjack-health"], "health event registered")
assert_truthy(events["wezterm-blackjack-reset-stats"], "reset event registered")
assert_truthy(events["user-var-changed"], "user var trigger event registered")
assert_truthy(events["augment-command-palette"], "command palette event registered")
assert_truthy(config.key_tables.wezterm_blackjack, "modal key table installed")
assert_equal(#config.keys, 1, "default key binding installed")

local palette = events["augment-command-palette"]()
assert_equal(#palette, 3, "command palette entries installed")

local health = blackjack.health_check()
assert_equal(health.ok, false, "health reports missing bj")
assert_equal(health.bj_path, "bj", "health reports bj path")

print("ok")
