# Munchies

Local macOS hole-swallow game (Godot 4). Couch multiplayer later; **Phase 2** is the solo feel / map / camera loop on `main`.

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

Controls: **WASD** / **arrows** move · **Esc** pause.

You spawn at a corner pad on the **160 × 160 m** map. Early game is litter and street props toward the parks; mid is vehicles on the roads; late is buildings and blocks at the edges.

## Headless checks

```bash
godot --headless --path . -s res://tests/test_sim.gd
```

## Layout

| Path | Role |
| --- | --- |
| `sim/sim.gd` | Pure `step` simulation (no scene tree) |
| `scripts/main.gd` | Keyboard → `step`, camera, swallow tween + blip |
| `scripts/world_view.gd` | Map + tier shapes (hole draws on top) |
| `scenes/main.tscn` | Main scene |
| `audio/swallow_blip.wav` | Swallow whoosh |
| `tests/test_sim.gd` | Headless rule checks |

## Workflow

Push straight to `main`. No feature branches or PRs unless asked.
