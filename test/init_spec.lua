package.path = table.concat({
    "./?.lua",
    "./?/init.lua",
    "./plugin/?.lua",
    package.path,
}, ";")

local events = {}
local encoded_values = {}
local run_child_process_handler = function()
    return false, "", "missing bj"
end

local function encode_value(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for k, v in pairs(value) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local wezterm_stub

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

    wezterm_stub = {
        action = action,
        action_callback = function(fn)
            return { action_callback = fn }
        end,
        json_encode = function(value)
            local encoded = encode_value(value)
            encoded_values[encoded] = value
            return encoded
        end,
        json_parse = function(text)
            return encoded_values[text]
        end,
        log_error = function() end,
        log_warn = function() end,
        on = function(name, fn)
            events[name] = fn
        end,
        run_child_process = function(argv, stdin)
            if stdin ~= nil then
                error("run_child_process uses documented single-argument API")
            end
            return run_child_process_handler(argv, stdin)
        end,
        target_triple = "x86_64-unknown-linux-gnu",
    }

    return wezterm_stub
end

local blackjack = dofile("plugin/init.lua")
local wcwidth = dofile("plugin/ui/wcwidth.lua")
local bj_transport = dofile("plugin/transport/bj.lua")

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

local function assert_falsy(value, label)
    if value then
        error(label)
    end
end

local function set_child_process_handler(fn)
    run_child_process_handler = fn
end

local function pane_stub(id)
    local sink = {}
    return {
        pane_id = function()
            return id
        end,
        send_text = function(_, text)
            sink[#sink + 1] = text
        end,
        _sink = sink,
    }
end

assert_equal(bj_transport._private.base64_encode(""), "", "Base64 encodes empty input")
assert_equal(bj_transport._private.base64_encode("f"), "Zg==", "Base64 encodes one byte")
assert_equal(bj_transport._private.base64_encode("fo"), "Zm8=", "Base64 encodes two bytes")
assert_equal(bj_transport._private.base64_encode("foo"), "Zm9v", "Base64 encodes three bytes")
assert_equal(bj_transport._private.base64_encode("♠\n'&"), "4pmgCicm", "Base64 encodes UTF-8 and metacharacters")

local window_stub = {
    perform_action = function() end,
}

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
assert_equal(wcwidth.wcswidth("A♠"), 2, "wcwidth handles suit symbols")
assert_equal(wcwidth.wcswidth("你"), 2, "wcwidth handles wide CJK")
assert_equal(wcwidth.wcswidth("e" .. string.char(0xCC, 0x81)), 1, "wcwidth handles combining marks")
assert_equal(wcwidth.truncate("你A", 2), "你", "truncate keeps whole wide chars")
assert_equal(wcwidth.truncate("你A", 3), "你A", "truncate returns full text when it fits")
assert_equal(
    blackjack._private.compare_versions(
        blackjack._private.parse_version("bj 0.1.1"),
        blackjack._private.parse_version("0.1.0")
    ),
    1,
    "version compare"
)

local render_state = {
    dealer_hand = {
        cards = {
            { rank = "King", suit = "Hearts" },
            { rank = "Seven", suit = "Clubs" },
        },
    },
    player_hands = {
        {
            cards = {
                { rank = "Two", suit = "Spades" },
                { rank = "Three", suit = "Diamonds" },
            },
        },
    },
    phase = { type = "PlayerTurn", data = 0 },
}

local game = {
    state = render_state,
    stats = { wins = 0, losses = 0, pushes = 0 },
    message = "Action unavailable",
}
local output = blackjack._private.render_game(game)
assert_truthy(output:find("BLACKJACK", 1, true), "render includes title")
assert_truthy(output:find("Dealer", 1, true), "render includes dealer")
assert_truthy(output:find("Wins: 0", 1, true), "render includes stats")
assert_truthy(output:find("Action unavailable", 1, true), "render includes inline message")
assert_truthy(output:find("[2♠]", 1, true), "render includes Two as 2")
assert_truthy(output:find("[3♦]", 1, true), "render includes Three as 3")

game.state.player_hands[1] = {
    cards = {
        { rank = "Ace", suit = "Spades" },
        { rank = "King", suit = "Hearts" },
    },
    is_split = true,
}
output = blackjack._private.render_game(game)
assert_falsy(output:find("BLACKJACK!", 1, true), "split 21 is not labeled blackjack")

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

game.state.outcomes = {
    { outcome = "Surrender", payout = -0.5 },
}
game.settled_signature = nil
blackjack._private.record_finished_stats(game)
assert_equal(game.stats.losses, 1, "surrender counted as loss")

local pane = pane_stub(101)
local pane_game = blackjack._private.get_game(pane)
pane_game.state = state
pane_game.stats = { wins = 0, losses = 0, pushes = 0 }
pane_game.message = nil

local call_count = 0
set_child_process_handler(function()
    call_count = call_count + 1
    return false, "", "should not run"
end)

blackjack._private.apply_action(window_stub, pane, "insurance-decline")
assert_equal(call_count, 0, "decline outside Insurance does not invoke bj")

local encoded_player_state = wezterm_stub.json_encode(state)
set_child_process_handler(function(argv)
    assert_equal(argv[1], "sh", "Unix action uses shell stdin adapter")
    assert_equal(argv[5], encoded_player_state, "state is passed as an inert argument")
    assert_equal(argv[6], "bj", "configured executable is passed separately")
    assert_equal(argv[7], "stand", "action is passed separately")
    return true, encoded_player_state, ""
end)
blackjack._private.apply_action(window_stub, pane, "stand")

set_child_process_handler(function()
    return false, "", "\27[2Jbad\nline"
end)
blackjack._private.apply_action(window_stub, pane, "hit")
assert_falsy(pane._sink[#pane._sink]:find("\27[2J", 1, true), "subprocess errors cannot inject terminal escapes")

local windows_argv
local hostile_json = "{\"note\":\"'\\\"; Write-Output PWNED`n$(Get-ChildItem)&|\\r\\n\"}"
local hostile_path = "C:\\Program Files\\bj'; Write-Output PWNED &.exe\r\n"
local hostile_action = "stand'; Write-Output PWNED | % { $_ }\n"
local windows_state = bj_transport.run_action(
    { bj_path = hostile_path },
    {
        target_triple = "aarch64-pc-windows-msvc",
        state_domain = {
            validate_state_shape = function()
                return true
            end,
        },
        utils = {
            safe_json_encode = function()
                return hostile_json
            end,
            safe_json_parse = function()
                return state
            end,
            safe_run = function(argv)
                windows_argv = argv
                return true, "state", ""
            end,
        },
    },
    { hostile_action },
    state
)
assert_equal(windows_state, state, "Windows adapter returns parsed state")
assert_equal(windows_argv[1], "powershell.exe", "Windows action uses PowerShell stdin adapter")
assert_equal(#windows_argv, 6, "Windows adapter passes only a fixed encoded script")
assert_falsy(windows_argv[6]:find(hostile_json, 1, true), "JSON is not embedded as PowerShell source")
assert_falsy(windows_argv[6]:find(hostile_path, 1, true), "executable path is not embedded as PowerShell source")
assert_falsy(windows_argv[6]:find(hostile_action, 1, true), "action is not embedded as PowerShell source")
assert_truthy(
    windows_argv[6]:find(bj_transport._private.base64_encode(hostile_json), 1, true),
    "Windows adapter includes the encoded JSON"
)
assert_truthy(
    windows_argv[6]:find(bj_transport._private.base64_encode(hostile_path), 1, true),
    "Windows adapter includes the encoded executable path"
)
assert_truthy(
    windows_argv[6]:find(bj_transport._private.base64_encode(hostile_action), 1, true),
    "Windows adapter includes the encoded action"
)
assert_truthy(
    windows_argv[6]:match("^%$state = %[Text%.Encoding%]::UTF8%.GetString"),
    "Windows adapter starts with a fixed decoder expression"
)
assert_falsy(windows_argv[6]:find("$args", 1, true), "Windows adapter does not evaluate trailing command arguments")

local finished_state = {
    dealer_hand = state.dealer_hand,
    player_hands = state.player_hands,
    phase = { type = "Finished" },
    outcomes = {
        { outcome = "Win", payout = 1 },
    },
}

local encoded_finished_state = wezterm_stub.json_encode(finished_state)
set_child_process_handler(function(argv)
    if argv[2] == "new" then
        return true, encoded_finished_state, ""
    end
    return false, "", "unexpected command"
end)

pane_game.state = finished_state
pane_game.stats = { wins = 0, losses = 0, pushes = 0 }
pane_game.settled_signature = blackjack._private.settlement_signature(finished_state)
blackjack._private.apply_action(window_stub, pane, "new")
assert_equal(pane_game.stats.wins, 1, "new action resets signature before stats recording")

local valid_state_ok, valid_state_err = blackjack._private.validate_state_shape(state)
assert_truthy(valid_state_ok, "valid state accepted")
assert_equal(valid_state_err, nil, "valid state has no error")

local invalid_state_ok, invalid_state_err = blackjack._private.validate_state_shape({})
assert_falsy(invalid_state_ok, "invalid state rejected")
assert_truthy(type(invalid_state_err) == "string" and invalid_state_err ~= "", "invalid state has reason")

local unsafe_state = {
    dealer_hand = { cards = { { rank = "\27[2J", suit = "Hearts" } } },
    player_hands = {},
    phase = { type = "Finished" },
    outcomes = {},
}
assert_falsy(blackjack._private.validate_state_shape(unsafe_state), "unsafe card values rejected")

local bad_opts_ok = pcall(function()
    blackjack._private.normalize_config({ controls = { nope = "x" } })
end)
assert_falsy(bad_opts_ok, "unknown control option rejected")

local normalized = blackjack._private.normalize_config({
    keybind = false,
    controls = {
        hit = { "h", "Space", "h" },
    },
})
assert_equal(normalized.keybind, false, "keybind false accepted")
assert_equal(type(normalized.controls.hit), "table", "multi control normalized to list")
assert_equal(#normalized.controls.hit, 2, "duplicate control keys deduplicated")

blackjack.config.colors = false
local reset_normalized = blackjack._private.normalize_config({})
assert_equal(reset_normalized.colors, true, "normalization starts from documented defaults")

set_child_process_handler(function()
    return false, "", "missing bj"
end)

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
assert_falsy(health.error:find("\27", 1, true), "health errors are terminal-safe")

print("ok")
