# wezterm-blackjack

Play blackjack in your terminal with WezTerm.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q11SKIOF)

## Features

- **Rich terminal UI** - Card art with Unicode box drawing and suit symbols
- **Colored output** - Red hearts/diamonds, green wins, red losses
- **Keyboard controls** - Quick single-key actions
- **Status bar integration** - Optional win/loss tracking display
- **Configurable** - Custom keybinds, triggers, and appearance

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

Or from source: [github.com/KevinTCoughlin/blackjack](https://github.com/KevinTCoughlin/blackjack)

## Usage

- Press `Leader + b` to start a game (default keybinding)
- Or type `/deal` in any terminal

### In-Game Controls

| Key | Action |
|-----|--------|
| `h` | Hit - draw another card |
| `s` | Stand - keep current hand |
| `d` | Double down |
| `p` | Split a pair |
| `u` | Surrender |
| `y` | Accept insurance |
| `n` | Decline insurance / New game |
| `q` | Quit |

## Game Display

```
┌─────────────────────────────────────────┐
│              BLACKJACK                  │
├─────────────────────────────────────────┤
│  Dealer: [??] [K♥]          Value: ?   │
│                                         │
│  You:    [A♠] [J♦]         Value: 21   │
│                           BLACKJACK!    │
├─────────────────────────────────────────┤
│  [H]it [S]tand [D]ouble [P]split [Q]uit │
└─────────────────────────────────────────┘
```

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

-- Add your own keybind
table.insert(config.keys, {
    key = "b",
    mods = "CTRL|SHIFT",
    action = blackjack.new_game(),
})
```

### Status Bar Integration

Add to your `update-status` handler to show win/loss stats:

```lua
wezterm.on("update-status", function(window, pane)
    local elements = {}

    -- Add blackjack status (shows icon and win/loss record)
    for _, e in ipairs(blackjack.get_status_elements()) do
        table.insert(elements, e)
    end

    -- Add your other status elements...

    window:set_right_status(wezterm.format(elements))
end)
```

### API

| Function | Description |
|----------|-------------|
| `apply_to_config(config, opts)` | Configure plugin with options |
| `new_game()` | Returns action to start a new game |
| `get_status_elements()` | Returns status bar elements |
| `get_stats()` | Returns `{wins, losses, pushes}` |
| `reset_stats()` | Reset win/loss statistics |

## Requirements

- [WezTerm](https://wezfurlong.org/wezterm/) with plugin support
- [`bj` CLI](https://github.com/KevinTCoughlin/blackjack) - `cargo install blackjack`

## Support

If you find this useful, consider supporting development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q11SKIOF)

## License

MIT
