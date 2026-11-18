# Red Harbor — Godot 4 Starter (M1 movement + P2 stealth probe + Doom-style HUD)

Neo-noir espionage roguelite. This folder continues the plan from
`Red_Harbor_Game_Development_Roadmap.docx`: gray-box movement (P1), the first
real pixel-art set (P4 starter), a Doom-style health HUD — **the portrait
is the health bar** — and now the P2 stealth probe: patrolling guards with
vision cones and a working sneak.

## Quick start

1. Open **Godot 4.x** → **Import** → select this folder's `project.godot` → **Import & Edit**.
2. If Godot mentions the project was made with an older 4.x version, just open it anyway.
3. Press **F5**. You control the PI (fedora, trench coat, cigarette); two state
   guards patrol with flashlight cones. Enter a cone and they hunt you.
4. Try the systems: press **H** a few times and watch the mugshot degrade,
   **K** to heal, **Ctrl/C** to sneak under a cone, **R** to restart after
   FLATLINED or after being caught.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Move | WASD / Arrow keys | Left stick |
| Dash | Shift / Space | A (bottom button) |
| Sneak | Ctrl / C (hold) | — |
| Hurt (debug) | H | — |
| Heal (debug) | K | — |
| Intel +1 (debug) | E | X (left button) |
| Restart | R | — |

H/K/E are gray-box probes until P2/P3 add real damage sources and pickups.
Sneak and the guards are the real P2 loop: walk speed 150 outruns a chasing
guard (110), sneak speed 78 does not — once seen, break line of sight and run.

## P2 stealth probe — guards, cones, sneak

`scripts/guard.gd` is the whole probe. Each guard walks its waypoint loop
(`patrol_points`, set per guard in `scenes/main.tscn`) holding a flashlight
cone. Detection rule, checked every physics frame:

1. **Range** — distance to the player ≤ `CONE_RANGE` (130 px),
   or `CONE_RANGE_SNEAK` (62 px) if the player is sneaking.
2. **Angle** — inside ±32° of the beam direction.
3. **Line of sight** — a raycast to the player must not hit the world layer
   first (walls and blocks block sight; the cone *art* does not occlude yet —
   that polish lands with the tileset).

Guard state machine and what you see:

| State | Cone color | Sprite | HUD line |
| --- | --- | --- | --- |
| PATROL | fog, faint | `patrol` march | (none) |
| CHASE (spotted) | surveillance red | `alert` pose, then `chase` | OBSERVED (red) |
| SEARCH (lost you) | red, dim, sweeping | `search` scan | SEARCHING (sodium) |

While chasing, the guard runs at your LAST SEEN position; if he reaches it
without seeing you again he sweeps the flashlight for 2.6 s, then resumes
patrol from the nearest waypoint. If he touches you during a chase, the night
ends (`player.capture()` → FLATLINED portrait → R to restart).

**Stealth tuning** — all in `scripts/guard.gd`:

| Constant | Default | Suggested range |
| --- | --- | --- |
| `PATROL_SPEED` | 55 | 45–70 |
| `CHASE_SPEED` | 110 | must sit between sneak 78 and walk 150 |
| `CONE_RANGE` | 130 | 100–160 |
| `CONE_RANGE_SNEAK` | 62 | 50–80 (the whole risk/reward dial) |
| `CONE_HALF_ANGLE` | 0.56 rad (~32°) | 0.45–0.7 |
| `SEARCH_TIME` | 2.6 s | 2–4 |

The probe: sneak the long way around Guard1's cone, let Guard2 see you,
then test whether breaking the wall's line of sight actually shakes him.

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
| `assets/sprites/guard_sheet.png` | 192 × 32 | 6 guard frames of 32 × 32 |
| `assets/sprites/portrait_sheet.png` | 192 × 32 | 6 health states of 32 × 32 |
| `assets/sprites/hud_frame.png` | 40 × 40 | Portrait frame, sodium rivets |
| `assets/sprites/hud_pip_empty/full.png` | 7 × 7 | Intel counter pips |
| `preview/` | — | 4× previews (ignored by Godot via `.gdignore`) |

**Guard frame map** (one row of 6 frames, left to right):

| Frames | Animation | Notes |
| --- | --- | --- |
| 0–1 | `patrol` | Heavy march, contact / pass |
| 2 | `alert` | Flashlight raised — the "spotted!" beat |
| 3–4 | `chase` | Forward lean, coat tails trailing |
| 5 | `search` | Standing scan, flashlight held low |

**Player frame map** (one row of 12 frames, left to right):

| Frames | Animation | Notes |
| --- | --- | --- |
| 0–1 | `idle` | Breathing bob + drifting cigarette smoke |
| 2–5 | `walk` | 4-frame contact/pass cycle |
| 6–7 | `dash` | Forward lean, coat tails trailing |
| 8–9 | `sneak` | Crouched 2-phase — wired to Ctrl/C in P2 |
| 10 | `hurt` | Recoil + blood pixel |
| 11 | `dead` | Lying flat, blood pool |

`player.gd` slices the sheet at runtime into named animations
(idle/walk/dash/sneak/hurt/dead) and flips horizontally for leftward movement.

The **guard** reuses the same silhouette rules with a different authority
read: peaked cap with a red band (the state marks its own), broader
greatcoat, red armband on the front arm, bone flashlight lens — the cone
comes from it. Frames: 0–1 patrol march, 2 alert (flashlight raised),
3–4 chase run with coat tails, 5 search scan. Same palette, 5 colors used.

### Editing the art in LibreSprite

- Open a sheet directly (**File ▸ Open**) and turn on a 32 × 32 grid
  (**View ▸ Grid ▸ Grid Settings**), or slice it into real frames via
  **File ▸ Import Sprite Sheet** (horizontal 12 × 1 for the player,
  6 × 1 for the guard, 6 × 1 for portraits).
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
  for state/surveillance elements — which is exactly why the guard's cap
  band, armband and alerted cone are red.

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
.gitignore             keeps .godot/ cache and OS junk out of Git
.gitattributes         EOL normalization + binary rules for art files
.gitmessage            conventional commit message template (git config commit.template .gitmessage)
scenes/main.tscn       gray-box arena (walls, blocks, goal, guards, HUD)
scenes/player.tscn     CharacterBody2D + camera
scenes/hud.tscn        CanvasLayer HUD (portrait, pips, status, alerts)
scenes/guard.tscn      patrolling guard (CharacterBody2D, floating motion)
scripts/player.gd      movement, dash, sneak, health, intel, animation
scripts/guard.gd       waypoints, vision cone, chase/search AI, capture
scripts/hud.gd         portrait state machine, intel pips, sight alerts
assets/sprites/        all PNG sheets (Godot loads these)
assets/palettes/       redharbor_noir.gpl — 7-color noir palette
assets/tiles/          empty until the first 16 × 16 tileset
assets_src/            LibreSprite .ase sources (commit these too)
audio/                 jsfxr exports (P5)
preview/               4× previews for quick looks (.gdignore'd)
```

## Version control (Git + GitHub)

The folder ships with a Godot 4 `.gitignore` (keeps the `.godot/` cache out
of history), a `.gitattributes` (line-ending hygiene + binary rules for
art), and a `.gitmessage` conventional-commit template. Enable the
template once, from inside the repository:

```bash
git config commit.template .gitmessage
```

First commit in the conventional format (full walkthrough:
`Red_Harbor_Git_and_GitHub_Guide.docx`):

```bash
cd RedHarbor_Godot4_Starter
git init
git add .
git commit -m "feat: gray-box movement, PI sprite set and Doom-style HUD"
```

## Next steps (roadmap order)

- [ ] Tune constants until the M1 gate checklist passes; record final values
- [x] P2: guard sprite (red = the state) on a waypoint loop
- [x] P2: vision-cone probe (Polygon2D fan + red flash on spotted)
- [x] Wire the existing `sneak` frames to a real sneak input (Ctrl/C)
- [ ] Give the cone art real occlusion (shadow casting) once the tileset lands
- [ ] P2 second half: goal→exit flow — reach the amber marker while unobserved
	  to bank the intel pip, then decide: extract or push deeper
- [ ] Replace rectangle walls with a real 16 × 16 tileset once the loop is fun
- [ ] P5: jsfxr passes — dash hiss, alert sting (red moment), footsteps off
