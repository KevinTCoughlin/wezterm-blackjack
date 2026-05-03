# wezterm-blackjack

Play blackjack in your terminal with WezTerm.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q11SKIOF)

## Features

- **Rich terminal UI** - Card art with Unicode box drawing and suit symbols
- **Colored output** - Red hearts/diamonds, green wins, red losses, and active-hand highlights
- **Modal keyboard controls** - Quick single-key actions without sending those keys to your shell
- **Status bar integration** - Optional win/loss tracking display
- **Configurable** - Custom keybinds, shell triggers, CLI path, and appearance
- **Pane-aware sessions** - Each pane can run its own game state

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

WezTerm note: the plugin sends game state to `bj` via stdin (no shell piping),
which avoids quoting/escaping issues and is more consistent across platforms.

Or from source: [github.com/KevinTCoughlin/blackjack](https://github.com/KevinTCoughlin/blackjack)

## Usage

- Press `Leader + b` to start a game (default keybinding)
- Use the optional shell trigger integration below to start from your prompt

### In-Game Controls

Starting a game activates a temporary `wezterm_blackjack` key table. Press `q`
or `Escape` to leave the game and return keyboard input to the shell.

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
┌───────────────────────────────────────────────────────────┐
│ BLACKJACK                                modal keys active │
├───────────────────────────────────────────────────────────┤
│ Dealer: [??] [K♥]                                  Value: ? │
│                                                           │
│ You:    [A♠] [J♦]                              BLACKJACK! │
├───────────────────────────────────────────────────────────┤
│ [H]it  [S]tand  [D]ouble  s[P]lit  s[U]rrender  [Q]uit    │
│ Wins: 0  Losses: 0  Pushes: 0                             │
└───────────────────────────────────────────────────────────┘
```

## Configuration

```lua
blackjack.apply_to_config(config, {
    trigger = "/deal",           -- Shell trigger payload
    keybind = { key = "b", mods = "LEADER" },  -- Set to false to disable
    bj_path = "bj",              -- Path to bj binary
    config_path = nil,           -- Optional bj TOML rules config
    min_bj_version = "0.1.0",    -- Warn if bj is older than this version
    colors = true,               -- ANSI color output in the game board
    command_palette = true,      -- Add Blackjack commands to WezTerm's palette
    controls = {
        hit = "h",
        stand = "s",
        double = "d",
        split = "p",
        surrender = "u",
        insurance_accept = "y",
        insurance_decline = "n",
        new_game = "N",
        quit = "q",
    },
    stats = {
        persist = false,         -- Set true to preserve stats across restarts
        path = nil,              -- Defaults to ~/.local/state/wezterm-blackjack/stats.json
    },
    status_bar = {
        enabled = true,          -- Show in status bar
        icon = "BJ",             -- Icon to display
        color = "#9ece6a",       -- Icon color
    },
})
```

Control values may also be lists:

```lua
blackjack.apply_to_config(config, {
    controls = {
        hit = { "h", "Space" },
        stand = { "s", "Enter" },
    },
})
```

Lowercase single-character controls automatically register their uppercase
variant. Use an uppercase value such as `"N"` when the lowercase key should do
something else.

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

### Shell Trigger

WezTerm plugins cannot intercept arbitrary bytes typed into your shell, so the
`trigger` option is implemented through WezTerm's `user-var-changed` escape
sequence support. Add a shell helper like this:

```sh
deal() {
  printf '\033]1337;SetUserVar=wezterm_blackjack=%s\007' "$(printf %s /deal | base64)"
}
```

Then run `deal` from your shell to start blackjack in that pane. If you customize
`trigger`, change `/deal` in the helper to the same value.

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

### Command Palette

When `command_palette` is enabled, WezTerm's command palette includes:

- `Blackjack: New Game`
- `Blackjack: Reset Stats`
- `Blackjack: Health Check`

Health checks report the configured `bj_path`, detected version, minimum version,
and stats path.

### API

| Function | Description |
|----------|-------------|
| `apply_to_config(config, opts)` | Configure plugin with options |
| `new_game()` | Returns action to start a new game |
| `trigger_command()` | Returns a shell command that emits the configured trigger |
| `get_status_elements()` | Returns status bar elements |
| `get_stats(pane?)` | Returns `{wins, losses, pushes}` for one pane or all panes |
| `reset_stats(pane?)` | Reset one pane's statistics or all statistics |
| `health_check()` | Returns `bj` path/version diagnostics |

## Development

Run the local smoke check with a WezTerm config load:

```bash
/Applications/WezTerm.app/Contents/MacOS/wezterm --config-file test/wezterm-smoke.lua show-keys
```

CI runs the Lua test harness in `test/init_spec.lua` and a real `bj` JSON
contract check in `test/bj-contract.sh`.

## Requirements

- [WezTerm](https://wezfurlong.org/wezterm/) with plugin support
- [`bj` CLI](https://github.com/KevinTCoughlin/blackjack) - `cargo install blackjack`

## Support

If you find this useful, consider supporting development:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q11SKIOF)

## License

MIT
