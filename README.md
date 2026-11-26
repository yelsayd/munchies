# Munchies

Local macOS hole-swallow game (Godot 4). Couch multiplayer later; **Phase 4** is match modes on `main` (keyboard + bots; gamepad deferred).

## Requirements

- macOS 13+
- [Godot 4.5+](https://godotengine.org/download) (developed on **4.7.2**)

```bash
brew install --cask godot
```

## Run

```bash
cd ~/dev/munchies
godot --path .
```

Or open the folder in the Godot editor and press Play (`F5`).

### Setup screen

- **↑ / ↓** (or W/S) — pick mode (Timer highlighted at 2:00)
- **← / →** (or A/D) — hole count 2–4 (1 keyboard + bots)
- **Enter / Space** — start
- **Esc** — pause in-match; from the end card, also returns to setup

### Modes

| Mode | Ends when | Hole respawn | Props |
| --- | --- | --- | --- |
| Timer | clock hits 0:00 (highest score) | yes (2 s) | no |
| Score target | first to **800** | yes | no |
| Map cleared | no prop left anyone can swallow | yes | no |
| Last hole standing | one hole left (or nobody can eat) | no | no |
| Unlimited | never (no end card) | n/a (no player eat) | yes |

Keyboard steers **You**. Extra holes are bots that emit the same `Input` vector into `step`.

## Headless checks

```bash
godot --headless --path . -s res://tests/test_sim.gd
```

## Layout

| Path | Role |
| --- | --- |
| `sim/sim.gd` | Pure `step` simulation (modes, swallow, respawn) |
| `sim/match_config.gd` | Mode flags (`MatchConfig`) |
| `sim/bot.gd` | Bot → `Input` only |
| `scripts/main.gd` | Setup / keyboard + bots / HUD / end card |
| `scripts/world_view.gd` | Map + holes |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked. Gamepad support stays deferred.
