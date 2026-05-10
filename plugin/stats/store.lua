local M = {}

local function copy_stats(stats)
    return {
        wins = tonumber(stats and stats.wins) or 0,
        losses = tonumber(stats and stats.losses) or 0,
        pushes = tonumber(stats and stats.pushes) or 0,
    }
end

local function add_stats(target, delta)
    target.wins = (target.wins or 0) + (delta.wins or 0)
    target.losses = (target.losses or 0) + (delta.losses or 0)
    target.pushes = (target.pushes or 0) + (delta.pushes or 0)
end

function M.new(deps)
    local persisted_stats = nil

    local function get_config()
        return deps.get_config()
    end

    local function default_stats_path()
        local home = deps.wezterm.home_dir or os.getenv("HOME") or "."
        return home .. "/.local/state/wezterm-blackjack/stats.json"
    end

    local function stats_path()
        local config = get_config()
        return config.stats.path or default_stats_path()
    end

    local function load_persisted_stats()
        local config = get_config()
        if not config.stats.persist then
            persisted_stats = nil
            return copy_stats(nil)
        end

        if persisted_stats then
            return persisted_stats
        end

        local content = deps.utils.read_file(stats_path())
        local decoded = content and deps.utils.safe_json_parse(content)
        persisted_stats = copy_stats(decoded)
        return persisted_stats
    end

    local function save_persisted_stats()
        local config = get_config()
        if not config.stats.persist then
            return
        end

        persisted_stats = copy_stats(persisted_stats)
        local encoded = deps.utils.safe_json_encode(persisted_stats)
        if not encoded then
            return
        end

        local ok, err = deps.utils.write_file(stats_path(), encoded .. "\n")
        if not ok then
            deps.utils.log("failed to save stats: " .. tostring(err), "WARN")
        end
    end

    local function reset_persisted_stats()
        local config = get_config()
        if not config.stats.persist then
            persisted_stats = nil
            return
        end
        persisted_stats = copy_stats(nil)
        save_persisted_stats()
    end

    local function aggregate_stats(pane_games)
        local total = copy_stats(nil)
        for _, game in pairs(pane_games) do
            add_stats(total, game.stats or {})
        end
        return total
    end

    local function record_finished_stats(game)
        local signature = deps.state_domain.settlement_signature(game.state, deps.encode_json)
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

        local config = get_config()
        if config.stats.persist then
            add_stats(load_persisted_stats(), delta)
            save_persisted_stats()
        end

        game.settled_signature = signature
    end

    return {
        copy_stats = copy_stats,
        add_stats = add_stats,
        stats_path = stats_path,
        load_persisted_stats = load_persisted_stats,
        save_persisted_stats = save_persisted_stats,
        reset_persisted_stats = reset_persisted_stats,
        aggregate_stats = aggregate_stats,
        record_finished_stats = record_finished_stats,
    }
end

return M
