local wezterm = require("wezterm")
local blackjack = dofile("plugin/init.lua")

local config = wezterm.config_builder()
config.leader = { key = "a", mods = "CTRL", timeout_milliseconds = 1000 }

blackjack.apply_to_config(config)

return config
