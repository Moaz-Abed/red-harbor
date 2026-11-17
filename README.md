# Red Harbor — Godot 4 Starter (M1 movement + sprites + Doom-style HUD)

Neo-noir espionage roguelite. This folder continues the plan from
`Red_Harbor_Game_Development_Roadmap.docx`: gray-box movement (P1), the first
real pixel-art set (P4 starter), and a Doom-style health HUD — **the portrait
is the health bar**.

## Quick start

1. Open **Godot 4.x** → **Import** → select this folder's `project.godot` → **Import & Edit**.
2. If Godot mentions the project was made with an older 4.x version, just open it anyway.
3. Press **F5**. You control the PI (fedora, trench coat, cigarette) in the gray-box arena.
4. Try the health system: press **H** a few times and watch the mugshot degrade,
   **K** to heal, **R** to restart after FLATLINED.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Move | WASD / Arrow keys | Left stick |
| Dash | Shift / Space | A (bottom button) |
| Hurt (debug) | H | — |
| Heal (debug) | K | — |
| Intel +1 (debug) | E | X (left button) |
| Restart | R | — |

H/K/E are gray-box probes until P2/P3 add real damage sources and pickups.

## The health system (Doom-style, no healthbar)

Health is 0–100 internally but is **only ever shown through the portrait**,
which cycles through 6 states at the classic Doom mugshot thresholds:

| State | Health | What the face shows |
| --- | --- | --- |
| CLEAN | 81–100 | Calm PI, cigarette smoke drifting |
| SCRAPED | 61–80 | Cut above the brow, frown |
| BRUISED | 41–60 | Dark bruise on the cheek, gritted teeth |
| BLEEDING | 21–40 | Blood streak from the forehead, squint |
| CRITICAL | 1–20 | Two streaks, eye swollen shut, mouth open |
| FLATLINED | 0 | X eyes, gray skin, hat knocked askew, blood pool |

Implementation: `player.gd` owns health and emits `health_changed`;
`hud.gd` maps the value to a portrait region and a status word
(CLEAN…FLATLINED). Extra feedback: the sprite blinks during i-frames, the
hurt pose plays on hit, death plays a lying-dead frame. The 3 sodium pips
beside the portrait are the **intel counter** (core loop — press E to preview).

## Sprite sheets (LibreSprite-ready)

All art is 1:1 pixels using exactly the 7-color noir palette
(`assets/palettes/redharbor_noir.gpl`):

| File | Size | Contents |
| --- | --- | --- |
| `assets/sprites/player_sheet.png` | 384 × 32 | 12 frames of 32 × 32 |
| `assets/sprites/portrait_sheet.png` | 192 × 32 | 6 health states of 32 × 32 |
| `assets/sprites/hud_frame.png` | 40 × 40 | Portrait frame, sodium rivets |
| `assets/sprites/hud_pip_empty/full.png` | 7 × 7 | Intel counter pips |
| `preview/` | — | 4× previews (ignored by Godot via `.gdignore`) |

**Player frame map** (one row of 12 frames, left to right):

| Frames | Animation | Notes |
| --- | --- | --- |
| 0–1 | `idle` | Breathing bob + drifting cigarette smoke |
| 2–5 | `walk` | 4-frame contact/pass cycle |
| 6–7 | `dash` | Forward lean, coat tails trailing |
| 8–9 | `sneak` | Crouched 2-phase (frames exist, not yet wired to input) |
| 10 | `hurt` | Recoil + blood pixel |
| 11 | `dead` | Lying flat, blood pool |

`player.gd` slices the sheet at runtime into named animations
(idle/walk/dash/sneak/hurt/dead) and flips horizontally for leftward movement.

### Editing the art in LibreSprite

- Open a sheet directly (**File ▸ Open**) and turn on a 32 × 32 grid
  (**View ▸ Grid ▸ Grid Settings**), or slice it into real frames via
  **File ▸ Import Sprite Sheet** (horizontal 12 × 1 for the player,
  6 × 1 for portraits).
- Load the palette via **Palette ▸ Load Palette** →
  `assets/palettes/redharbor_noir.gpl`.
- Keep edited sources in `assets_src/` as `.ase`, then **File ▸ Export**
  back to the same PNG path in `assets/sprites/` — Godot picks it up on
  the next run, no import settings to redo (Nearest filtering is
  project-wide).

### Style rules (roadmap §Art)

- 32 × 32 character, 6–10 colors per scene, noir palette only.
- Bone = skin/highlights, shadow/slate = coat, ink = outlines and hat.
- Sodium amber is for "safe light" accents (tie, match, extraction).
- **Red is reserved**: blood on the HUD portrait and, in the world, only
  for state/surveillance elements.

## Tuning the feel — still your main job in P1

All feel numbers live at the top of `scripts/player.gd`:

| Constant | Default | Suggested range |
| --- | --- | --- |
| `MOVE_SPEED` | 150 | 130–180 |
| `ACCEL` / `FRICTION` | 2000 / 2600 | higher = snappier |
| `DASH_SPEED` | 430 | 380–500 |
| `DASH_TIME` | 0.12 s | 0.10–0.15 |
| `DASH_COOLDOWN` | 0.35 s | 0.25–0.50 |
| `MAX_HEALTH` | 100 | keep 100 for the Doom thresholds |

**M1 gate:** dash answers on the same frame you press, stopping is
immediate, diagonals are not faster than straights, and you can thread the
two blocks at full speed. Then run the roadmap's tester ritual
(3 testers × 2 runs) and log notes with the final constant values.

## Project settings that matter

| Setting | Value | Why |
| --- | --- | --- |
| Viewport | 640 × 360 | 16:9, ~20 × 11 tiles of 32 px characters |
| Stretch mode | `canvas_items`, keep aspect | Crisp pixel scaling |
| Texture filter | Nearest | No blur on any sprite or HUD element |
| Renderer | GL Compatibility | Best 2D performance, easy itch.io web export |
| Physics layers | 1 player / 2 world / 3 enemies | Ready for guards and drones |

## Folder layout

```
project.godot          viewport, input map, layers, rendering
scenes/main.tscn       gray-box arena (walls, blocks, goal marker, HUD)
scenes/player.tscn     CharacterBody2D + camera
scenes/hud.tscn        CanvasLayer HUD (portrait, pips, status, hints)
scripts/player.gd      movement, dash, health, intel, animation
scripts/hud.gd         portrait state machine, intel pips, status text
assets/sprites/        all PNG sheets (Godot loads these)
assets/palettes/       redharbor_noir.gpl — 7-color noir palette
assets/tiles/          empty until the first 16 × 16 tileset (P2)
assets_src/            LibreSprite .ase sources (commit these too)
audio/                 jsfxr exports (P5)
preview/               4× previews for quick looks (.gdignore'd)
```

## Suggested commit

```bash
cd RedHarbor_Godot4_Starter
git init
git add .
git commit -m "P1: gray-box movement + PI sprite set + Doom-style HUD"
```

## Next steps (roadmap order)

- [ ] Tune constants until the M1 gate checklist passes; record final values
- [ ] P2: guard sprite (red = the state) on a waypoint loop
- [ ] P2: vision-cone probe (Polygon2D fan + "seen" flash) before any real AI
- [ ] Wire the existing `sneak` frames to a real sneak input (walk slower + crouch)
- [ ] Replace rectangle walls with a real 16 × 16 tileset once the loop is fun
