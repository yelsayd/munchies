# Munchies

Local macOS hole-swallow game (Godot 4). Couch match on `main`: setup screen, four slots (P1 keyboard/pad + optional P2 arrows + bots; extra pads deferred), shared end card. The 3D view skins the same sim (`x, y, radius` authority) with meshes and a tilted chase camera. Solo keeps WASD + arrows + one gamepad on You; dual keyboard splits WASD/pad vs arrows with side-by-side panes.

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

**Cursor / VS Code:** open this folder, pick **Run Munchies** (compound → Godot on PATH) in Run and Debug, then press **F5**. If `godot` is missing from PATH, choose **Godot (brew cask)** instead (`/Applications/Godot.app/...` from `brew install --cask godot`).

Or open the folder in the Godot editor and press Play (`F5`).

Props have **no suction pull**. Upright props need full disc cover to swallow; once a hole crosses the center they **tip**, and after a short lean (or if fallen) CoG-in-hole + size gate finishes the eat. Swallowed meshes drop straight down into the pit.

### Setup screen

Opens with **Timer — 2:00** highlighted and four slots filled (P1 + 3 bots).

| Action | Keyboard | Gamepad |
| --- | --- | --- |
| Switch modes ↔ slots | **Tab** | **LB / RB / Select** |
| Move in focused list | **↑ / ↓** (or W/S) | **D-pad / left stick** |
| Cycle Bot / Empty / P2 (slots 2–4) | **← / →** (or A/D) | **D-pad / left stick** |
| Start | **Enter / Space** | **A** |
| Pause in-match | **Esc** | **Start / B** |

Slot **1** is always **P1 (WASD / pad)**. On slots 2–4, cycle **Bot → Empty → P2 (arrows)**. At most one P2. Empty slots stay empty; bots fill the rest until extra pads exist. Solo match: one fullscreen chase cam. Dual keyboard: side-by-side panes (P1 left, P2 right).

### In match

- **Solo:** move with **WASD / arrows** or the **left stick / D-pad**
- **Dual keyboard:** **P1 = WASD / stick**, **P2 = arrow keys**
- **Esc / Start / B** pauses; **A / Enter** confirms pause-menu choices

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
| `scripts/main.gd` | Setup / slots / dual keyboard+pad + bots / 3D pane(s) / pause / end card |
| `scripts/world_view_3d.gd` | Presentation-only Node3D meshes synced from sim each frame |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked. Extra local pads (multi-controller couch) stay deferred.
