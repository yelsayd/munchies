# Munchies

Local macOS hole-swallow game (Godot 4). Couch multiplayer later; **Phase 1** is a single-player core loop.

## Requirements

- macOS 13+
- [Godot 4.5+](https://godotengine.org/download) (developed on **4.7.2**)

Install via Homebrew:

```bash
brew install --cask godot
```

## Run (Phase 1)

From this repo:

```bash
godot --path .
```

Or open the folder in the Godot editor and press Play (`F5`).

Controls:

- **WASD** or **arrow keys** — move the hole
- **Esc** — pause / resume

## Phase 1 goals

- Start at radius `1.0` / score `10`
- Sweep tier 0 litter; feel movement slow as you grow
- Fail to eat oversized props until you grow past them (eat ratio `0.95`)
- All movement and swallows go through `sim/sim.gd` → `step()`, not physics nodes

## Headless checks

```bash
godot --headless --path . -s res://tests/test_sim.gd
```

## Layout

| Path | Role |
| --- | --- |
| `sim/sim.gd` | Pure `step` simulation (no scene tree) |
| `scripts/main.gd` | Keyboard → `step`, camera follow + 20% zoom |
| `scripts/world_view.gd` | Circle drawing |
| `scenes/main.tscn` | Main scene |
| `tests/test_sim.gd` | Headless rule checks |
