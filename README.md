# Munchies

Local macOS hole-swallow game (Godot 4). **Phase 6** is the first couch match on `main`: setup screen, four slots (keyboard + optional bots; pads deferred), shared end card. A **3D presentation spike** skins the same 2D sim with meshes + a tilted camera (default view).

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

### 2D / 3D view toggle

Default is **3D** (single pane following You). Sim `step`, claims, and modes stay 2D (`x, y, radius` authority). Props have **no suction pull**. Upright props need full disc cover to swallow; once a hole crosses the center they **tip**, and after a short lean (or if fallen) CoG-in-hole + size gate finishes the eat. The 3D view drops the mesh straight down into the pit.

| How | Effect |
| --- | --- |
| **F3** | Toggle 2D ↔ 3D (setup or in-match) |
| `godot --path . -- --view=2d` | Start in classic split-screen 2D |
| `godot --path . -- --view=3d` | Start in 3D spike (default) |

**Still 2D:** `sim/sim.gd` step, exclusive claims, modes, bots, setup/HUD/end card, swallow tweens logic, and the full multi-pane split when in 2D mode. **3D deferred:** multi-pane / shared World3D split-screen, pit shader, falling-prop animation beyond scale-out ghosts.

### Setup screen

Opens with **Timer — 2:00** highlighted and four slots filled (You + 3 bots).

- **Tab** — switch focus between modes and slots
- **↑ / ↓** (or W/S) — move in the focused list
- **← / →** (or A/D) — on slots 2–4, toggle **Bot** / **Empty**
- **F3** — toggle 2D / 3D presentation
- **Enter / Space** — start
- **Esc** — pause in-match (freezes the whole sim); from the end card, also returns to setup

Slot **1** is always the keyboard human (**You**). Empty slots stay empty; bots fill the rest until pads exist.

### Split screen (2D view)

| Holes | Panes |
| --- | --- |
| 1 | fullscreen |
| 2 | side by side |
| 3 | quadrants (one blank) |
| 4 | quadrants |

Each 2D pane follows its hole with Phase 2 camera rules. One shared sim — every pane sees the same swallow. **3D mode** always uses one pane (keyboard hole); multi-pane 3D is deferred.

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
| `scripts/main.gd` | Setup / slots / keyboard + bots / 2D split or 3D single pane / pause / end card |
| `scripts/world_view.gd` | Shared World2D draw (painted ground, roads/parks, prop silhouettes) |
| `scripts/world_view_3d.gd` | Presentation-only Node3D meshes synced from sim each frame |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked. Gamepad support stays deferred.
