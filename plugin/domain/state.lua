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

local function validate_cards(cards, path)
    if type(cards) ~= "table" then
        return nil, path .. " must be an array"
    end

    for i, card in ipairs(cards) do
        if type(card) ~= "table" then
            return nil, string.format("%s[%d] must be an object", path, i)
        end
        if type(card.rank) ~= "string" or card.rank == "" then
            return nil, string.format("%s[%d].rank must be a non-empty string", path, i)
        end
        if type(card.suit) ~= "string" or card.suit == "" then
            return nil, string.format("%s[%d].suit must be a non-empty string", path, i)
        end
    end

    return true
end

local function validate_player_hands(hands)
    if type(hands) ~= "table" then
        return nil, "player_hands must be an array"
    end

    for i, hand in ipairs(hands) do
        if type(hand) ~= "table" then
            return nil, string.format("player_hands[%d] must be an object", i)
        end
        local ok, err = validate_cards(hand.cards, string.format("player_hands[%d].cards", i))
        if not ok then
            return nil, err
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

    if state.outcomes ~= nil and type(state.outcomes) ~= "table" then
        return nil, "outcomes must be an array when present"
    end

    if state.phase.type == "Finished" and type(state.outcomes) ~= "table" then
        return nil, "outcomes must be present when phase.type is Finished"
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
