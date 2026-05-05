# MIKU 音速疾跑 — Subway Runner 3D

A Godot 4.3 3D endless runner inspired by subway-style lane runners, rebuilt with a Miku live-stage visual direction: neon rails, rhythm coins, train rooftop routes, combo scoring, and power-up effects.

🎮 **Play Online**: https://heidongzitugou.github.io/godot-subway-runner/

## Controls

| Key | Action |
|-----|--------|
| ← → / A D | Switch lanes |
| ↑ / W / Space | Jump |
| ↓ / S | Slide |
| P / double tap | Pause |

## Current Gameplay

- Three-lane runner with trains, moving trains, gates, barriers, crates, cones, and rooftop train routes.
- Coin paths include straight lines, jump arcs, lane-change curves, and rooftop rewards.
- Power-ups include Miku Shield, Leek Magnet, Rhythm Dash, and score multiplier.
- Miku-themed UI, neon rails, LED track panels, stage arches, live signs, glow, particles, and status effects.

## Development

Built with [Godot 4.3](https://godotengine.org/).

### Export for Web

```bash
godot --headless --path . --export-release "Web"
```

If Godot cannot create its default log file in this Windows/OneDrive path, pass a local log file:

```bash
godot --headless --path . --log-file godot-export.log --export-release "Web"
```
