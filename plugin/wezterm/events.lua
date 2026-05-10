local M = {}

function M.new(deps)
    local events_registered = false

    return function()
        if events_registered then
            return
        end
        events_registered = true

        local wezterm = deps.wezterm
        local names = deps.event_names

        wezterm.on(names.action, function(window, pane)
            deps.start_game(window, pane)
        end)

        wezterm.on(names.reset_stats, function(window, pane)
            deps.reset_stats()
            local game = deps.get_game(pane)
            if game.state then
                game.message = "Stats reset"
                deps.render_to_pane(game, pane)
            elseif window.toast_notification then
                window:toast_notification("Blackjack", "Stats reset", nil, 3000)
            end
        end)

        wezterm.on(names.health, function(window, pane)
            local health = deps.health_check()
            local message
            if health.ok then
                message = "bj " .. (health.version or "installed")
            else
                message = "bj unavailable: " .. (health.error or "unknown error")
            end

            local game = deps.get_game(pane)
            if game.state then
                game.message = message
                deps.render_to_pane(game, pane)
            elseif window.toast_notification then
                window:toast_notification("Blackjack", message, nil, 5000)
            else
                pane:send_text("\r\n" .. message .. "\r\n")
            end
        end)

        wezterm.on("user-var-changed", function(window, pane, name, value)
            if name == names.user_var and value == deps.get_trigger() then
                deps.start_game(window, pane)
            end
        end)

        wezterm.on("augment-command-palette", function()
            if not deps.command_palette_enabled() then
                return {}
            end
            return deps.command_palette_entries()
        end)
    end
end

return M
