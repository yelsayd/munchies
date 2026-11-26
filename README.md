# Munchies

Local macOS hole-swallow game (Godot 4). **Phase 6** is the first couch match on `main`: setup screen, four slots (keyboard + optional bots; pads deferred), shared end card.

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

Opens with **Timer — 2:00** highlighted and four slots filled (You + 3 bots).

- **Tab** — switch focus between modes and slots
- **↑ / ↓** (or W/S) — move in the focused list
- **← / →** (or A/D) — on slots 2–4, toggle **Bot** / **Empty**
- **Enter / Space** — start
- **Esc** — pause in-match (freezes the whole sim); from the end card, also returns to setup

Slot **1** is always the keyboard human (**You**). Empty slots stay empty; bots fill the rest until pads exist.

### Split screen

| Holes | Panes |
| --- | --- |
| 1 | fullscreen |
| 2 | side by side |
| 3 | quadrants (one blank) |
| 4 | quadrants |

Each pane follows its hole with Phase 2 camera rules. One shared sim — every pane sees the same swallow.

### Modes

| Mode | Ends when | Hole respawn | Props | End card |
| --- | --- | --- | --- | --- |
| Timer | clock hits 0:00 (highest score) | yes (2 s) | no | shared |
| Score target | first to **800** | yes | no | shared |
| Map cleared | no prop left anyone can swallow | yes | no | shared |
| Last hole standing | one hole left (or nobody can eat) | no | no | shared |
| Unlimited | never | n/a (no player eat) | yes | **none** — no clock, no target |

## Headless checks

```bash
godot --headless --path . -s res://tests/test_sim.gd
```

## Layout

| Path | Role |
| --- | --- |
| `sim/sim.gd` | Pure `step` simulation (modes, swallow, exclusive claims, respawn) |
| `sim/match_config.gd` | Mode flags + setup slots (`MatchConfig`) |
| `sim/bot.gd` | Bot → `Input` only |
| `scripts/main.gd` | Setup / slots / keyboard + bots / split panes / shared pause / end card |
| `scripts/world_view.gd` | Shared World2D draw (map + holes); all panes read it |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked. Gamepad support stays deferred.
