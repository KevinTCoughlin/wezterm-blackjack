# wezterm-blackjack

Play blackjack in your terminal with WezTerm.

## Installation

Add to your `wezterm.lua`:

```lua
local blackjack = wezterm.plugin.require("https://github.com/KevinTCoughlin/wezterm-blackjack")

-- Apply to config
blackjack.apply_to_config(config)
```

### Prerequisites

Install the `bj` CLI:

```bash
cargo install blackjack
```

## Usage

- Press `Leader + b` to start a game (default keybinding)
- Or type `/deal` in any terminal to trigger a game

### In-Game Controls

| Key | Action |
|-----|--------|
| h | Hit |
| s | Stand |
| d | Double down |
| p | Split |
| u | Surrender |
| y | Accept insurance |
| n | Decline insurance / New game |
| q | Quit |

## Configuration

```lua
blackjack.apply_to_config(config, {
    trigger = "/deal",           -- Command to start game
    keybind = { key = "b", mods = "LEADER" },  -- Set to false to disable
    bj_path = "bj",              -- Path to bj binary
    status_bar = {
        enabled = true,          -- Show in status bar
        icon = "🃏",             -- Icon to display
        color = "#9ece6a",       -- Icon color
    },
})
```

### Custom Keybinding

```lua
-- Disable default keybind and use custom
blackjack.apply_to_config(config, {
    keybind = false,  -- Disable default Leader+b
})

-- Add your own
table.insert(config.keys, {
    key = "b",
    mods = "CTRL|SHIFT",
    action = blackjack.new_game(),
})
```

### Status Bar Integration

Add to your `update-status` handler:

```lua
wezterm.on("update-status", function(window, pane)
    local elements = {}

    -- Add blackjack status
    for _, e in ipairs(blackjack.get_status_elements()) do
        table.insert(elements, e)
    end

    -- Add your other status elements...

    window:set_right_status(wezterm.format(elements))
end)
```

## Game Display

```
┌─────────────────────────────────────────┐
│              BLACKJACK                  │
├─────────────────────────────────────────┤
│  Dealer: [??] [K♥]          Value: ?   │
│                                         │
│  You:    [A♠] [J♦]     Value: 21       │
│                        BLACKJACK!       │
├─────────────────────────────────────────┤
│  [H]it [S]tand [D]ouble [P]split [Q]uit │
│  Wins: 5  Losses: 3  Pushes: 1          │
└─────────────────────────────────────────┘
```

## Requirements

- WezTerm with plugin support
- `bj` CLI from [blackjack](https://github.com/KevinTCoughlin/blackjack)

## Sponsor

If you find this useful, consider [sponsoring](https://github.com/sponsors/kevintcoughlin).

## License

MIT
