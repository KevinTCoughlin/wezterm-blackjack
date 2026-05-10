local M = {}

local ACTIONS = {
    ["hit"] = {
        id = "hit",
        control = "hit",
        label_suffix = "it",
        cli_args = { "hit" },
    },
    ["stand"] = {
        id = "stand",
        control = "stand",
        label_suffix = "tand",
        cli_args = { "stand" },
    },
    ["double"] = {
        id = "double",
        control = "double",
        label_suffix = "ouble",
        cli_args = { "double" },
    },
    ["split"] = {
        id = "split",
        control = "split",
        label_suffix = "split",
        cli_args = { "split" },
    },
    ["surrender"] = {
        id = "surrender",
        control = "surrender",
        label_suffix = "surrender",
        cli_args = { "surrender" },
    },
    ["insurance-accept"] = {
        id = "insurance-accept",
        control = "insurance_accept",
        label_suffix = "es insurance",
        cli_args = { "insurance", "--accept" },
    },
    ["insurance-decline"] = {
        id = "insurance-decline",
        control = "insurance_decline",
        label_suffix = "o insurance",
        cli_args = { "insurance" },
    },
    ["new"] = {
        id = "new",
        control = "new_game",
        label_suffix = "ew game",
        cli_args = { "new" },
    },
    ["quit"] = {
        id = "quit",
        control = "quit",
        label_suffix = "uit",
    },
}

local ORDERED_ACTION_IDS = {
    "hit",
    "stand",
    "double",
    "split",
    "surrender",
    "insurance-accept",
    "insurance-decline",
    "new",
    "quit",
}

local ALLOWED_BY_PHASE = {
    PlayerTurn = {
        ["hit"] = true,
        ["stand"] = true,
        ["double"] = true,
        ["split"] = true,
        ["surrender"] = true,
        ["quit"] = true,
    },
    Insurance = {
        ["insurance-accept"] = true,
        ["insurance-decline"] = true,
        ["quit"] = true,
    },
    Finished = {
        ["new"] = true,
        ["quit"] = true,
    },
    DealerTurn = {
        ["quit"] = true,
    },
}

local EMPTY_PHASE_ALLOWED = {
    ["new"] = true,
    ["quit"] = true,
}

local function phase_type(state)
    if type(state) ~= "table" or type(state.phase) ~= "table" then
        return nil
    end
    if type(state.phase.type) ~= "string" or state.phase.type == "" then
        return nil
    end
    return state.phase.type
end

function M.phase_type(state)
    return phase_type(state)
end

function M.get(action_id)
    return ACTIONS[action_id]
end

function M.ordered_ids()
    return ORDERED_ACTION_IDS
end

function M.allowed_set_for_state(state)
    if state == nil then
        return EMPTY_PHASE_ALLOWED
    end

    local by_phase = ALLOWED_BY_PHASE[phase_type(state)]
    if by_phase then
        return by_phase
    end

    return { ["quit"] = true }
end

function M.actions_for_state(state)
    local allowed = M.allowed_set_for_state(state)
    local result = {}
    for _, action_id in ipairs(ORDERED_ACTION_IDS) do
        if allowed[action_id] then
            result[#result + 1] = action_id
        end
    end
    return result
end

function M.is_allowed(action_id, state)
    if not ACTIONS[action_id] then
        return false
    end
    return M.allowed_set_for_state(state)[action_id] == true
end

function M.control_names()
    local controls = {}
    local seen = {}
    for _, action_id in ipairs(ORDERED_ACTION_IDS) do
        local control = ACTIONS[action_id].control
        if control and not seen[control] then
            seen[control] = true
            controls[#controls + 1] = control
        end
    end
    return controls
end

return M
