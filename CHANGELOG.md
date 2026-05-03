# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Modal `wezterm_blackjack` key table for in-game controls.
- Pane-scoped game state with aggregate or per-pane statistics.
- Shell trigger support through WezTerm user variables.
- Configurable in-game controls.
- Optional persistent statistics.
- WezTerm command palette entries for new game, reset stats, and health check.
- Flexible table/betting display when the `bj` state exposes bankroll or wager fields.
- CI contract test against the real `bj` CLI.
- `health_check()` and `trigger_command()` plugin APIs.
- Lua test harness and GitHub Actions CI.
- Demo board fixture in `docs/demo.txt`.

### Changed
- Rendered game output now includes ANSI colors and wider, more resilient rows.
- Status bar stats now include pushes and aggregate across active pane sessions.

### Fixed
- Prevent duplicate win/loss/push accounting for the same finished game state.
- Avoid leaking in-game key presses to the underlying shell while a game is active.

## [0.1.0] - 2025-01-18

### Added
- Initial release
- Integration with `bj` CLI for game logic
- In-terminal blackjack UI with Unicode card rendering
- Keyboard controls for all blackjack actions
- Session statistics tracking (wins/losses/pushes)
- Configurable keybindings
- Leader+b default keybinding
