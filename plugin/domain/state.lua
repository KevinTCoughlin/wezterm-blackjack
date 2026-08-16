local M = {}

local RANK_VALUES = {
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

local VALID_RANKS = {
    Ace = true,
    Two = true,
    Three = true,
    Four = true,
    Five = true,
    Six = true,
    Seven = true,
    Eight = true,
    Nine = true,
    Ten = true,
    Jack = true,
    Queen = true,
    King = true,
}

local VALID_SUITS = {
    Spades = true,
    Hearts = true,
    Diamonds = true,
    Clubs = true,
}

local VALID_PHASES = {
    Betting = true,
    Insurance = true,
    PlayerTurn = true,
    DealerTurn = true,
    Finished = true,
}

local VALID_OUTCOMES = {
    Win = true,
    Lose = true,
    Push = true,
    Blackjack = true,
    Bust = true,
    Surrender = true,
}

local function validate_array(value, path)
    if type(value) ~= "table" then
        return nil, path .. " must be an array"
    end

    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return nil, path .. " must be an array"
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if maximum ~= count then
        return nil, path .. " must not contain gaps"
    end
    return true
end

local function validate_cards(cards, path)
    local array_ok, array_err = validate_array(cards, path)
    if not array_ok then
        return nil, array_err
    end

    for i, card in ipairs(cards) do
        if type(card) ~= "table" then
            return nil, string.format("%s[%d] must be an object", path, i)
        end
        if not VALID_RANKS[card.rank] then
            return nil, string.format("%s[%d].rank is invalid", path, i)
        end
        if not VALID_SUITS[card.suit] then
            return nil, string.format("%s[%d].suit is invalid", path, i)
        end
    end

    return true
end

local function validate_player_hands(hands)
    local array_ok, array_err = validate_array(hands, "player_hands")
    if not array_ok then
        return nil, array_err
    end

    for i, hand in ipairs(hands) do
        if type(hand) ~= "table" then
            return nil, string.format("player_hands[%d] must be an object", i)
        end
        local ok, err = validate_cards(hand.cards, string.format("player_hands[%d].cards", i))
        if not ok then
            return nil, err
        end
        for _, field in ipairs({ "is_split", "is_doubled", "is_surrendered", "is_standing" }) do
            if hand[field] ~= nil and type(hand[field]) ~= "boolean" then
                return nil, string.format("player_hands[%d].%s must be a boolean", i, field)
            end
        end
    end

    return true
end

local function validate_outcomes(outcomes)
    local array_ok, array_err = validate_array(outcomes, "outcomes")
    if not array_ok then
        return nil, array_err
    end

    for i, outcome in ipairs(outcomes) do
        if type(outcome) ~= "table" then
            return nil, string.format("outcomes[%d] must be an object", i)
        end
        if not VALID_OUTCOMES[outcome.outcome] then
            return nil, string.format("outcomes[%d].outcome is invalid", i)
        end
        if
            type(outcome.payout) ~= "number"
            or outcome.payout ~= outcome.payout
            or outcome.payout == math.huge
            or outcome.payout == -math.huge
        then
            return nil, string.format("outcomes[%d].payout must be a finite number", i)
        end
    end
    return true
end

function M.validate_state_shape(state)
    if type(state) ~= "table" then
        return nil, "state must be an object"
    end

    if type(state.phase) ~= "table" then
        return nil, "phase must be an object"
    end
    if type(state.phase.type) ~= "string" or state.phase.type == "" then
        return nil, "phase.type must be a non-empty string"
    end
    if not VALID_PHASES[state.phase.type] then
        return nil, "phase.type is unsupported"
    end

    if type(state.dealer_hand) ~= "table" then
        return nil, "dealer_hand must be an object"
    end
    local ok_dealer, err_dealer = validate_cards(state.dealer_hand.cards, "dealer_hand.cards")
    if not ok_dealer then
        return nil, err_dealer
    end

    local ok_hands, err_hands = validate_player_hands(state.player_hands)
    if not ok_hands then
        return nil, err_hands
    end

    if state.phase.type == "PlayerTurn" then
        local hand_index = state.phase.data
        if type(hand_index) ~= "number" or hand_index % 1 ~= 0 or hand_index < 0 or hand_index >= #state.player_hands then
            return nil, "phase.data must identify an existing player hand"
        end
    end

    if state.phase.type == "Finished" and state.outcomes == nil then
        return nil, "outcomes must be present when phase.type is Finished"
    end
    if state.outcomes ~= nil then
        local ok_outcomes, err_outcomes = validate_outcomes(state.outcomes)
        if not ok_outcomes then
            return nil, err_outcomes
        end
    end

    return true
end

function M.hand_value(cards)
    local value = 0
    local aces = 0

    for _, card in ipairs(cards or {}) do
        if card.rank == "Ace" then
            aces = aces + 1
            value = value + 11
        else
            value = value + (RANK_VALUES[card.rank] or 0)
        end
    end

    while value > 21 and aces > 0 do
        value = value - 10
        aces = aces - 1
    end

    return value
end

function M.settlement_signature(state, encode_json)
    if type(state) ~= "table" or type(state.phase) ~= "table" or state.phase.type ~= "Finished" then
        return nil
    end
    if type(state.outcomes) ~= "table" then
        return nil
    end
    if type(encode_json) ~= "function" then
        return nil
    end

    local ok, signature = pcall(encode_json, state.outcomes)
    if not ok then
        return nil
    end
    return signature
end

return M
