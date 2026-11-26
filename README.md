# Munchies

Local macOS hole-swallow game (Godot 4). **Phase 5** is couch split-screen on `main` (keyboard + bots; gamepad deferred).

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
- **← / →** (or A/D) — hole count 2–4 (pane layout follows)
- **Enter / Space** — start
- **Esc** — pause in-match (freezes the whole sim); from the end card, also returns to setup

### Split screen

| Holes | Panes |
| --- | --- |
| 2 | side by side |
| 3 | quadrants (one blank) |
| 4 | quadrants |

Each pane follows its hole with Phase 2 camera rules (damped follow, look-ahead, ~20% diameter zoom). One shared sim — every pane sees the same swallow. Claimed props show a ring in the claimer’s color; only that hole can finish the swallow.

Slot **0** is the keyboard human (**You**). Extra slots are bots that emit the same `Input` vector into `step` until pads exist.

### Modes

| Mode | Ends when | Hole respawn | Props |
| --- | --- | --- | --- |
| Timer | clock hits 0:00 (highest score) | yes (2 s) | no |
| Score target | first to **800** | yes | no |
| Map cleared | no prop left anyone can swallow | yes | no |
| Last hole standing | one hole left (or nobody can eat) | no | no |
| Unlimited | never (no end card) | n/a (no player eat) | yes |

## Headless checks

```bash
godot --headless --path . -s res://tests/test_sim.gd
```

## Layout

| Path | Role |
| --- | --- |
| `sim/sim.gd` | Pure `step` simulation (modes, swallow, exclusive claims, respawn) |
| `sim/match_config.gd` | Mode flags (`MatchConfig`) |
| `sim/bot.gd` | Bot → `Input` only |
| `scripts/main.gd` | Setup / keyboard + bots / split panes / shared pause / end card |
| `scripts/world_view.gd` | Shared World2D draw (map + holes); all panes read it |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked. Gamepad support stays deferred.
