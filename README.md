# Red Harbor — Godot 4 Starter (Harbor Row: tileset world, stealth night, Doom-style HUD)

Neo-noir espionage roguelite. This folder continues the plan from
`Red_Harbor_Game_Development_Roadmap.docx`: gray-box movement (P1), the P2
stealth probe (patrolling guards, vision cones, sneak), the night loop —
grab 3 intel folders, then extract at the safehouse door — a Doom-style
health HUD (**the portrait is the health bar**) and, new in P3, a real
16 × 16 tileset world: **Harbor Row**, a full block whose walls block
movement, sight and the cone art alike.

## Quick start

1. Open **Godot 4.x** → **Import** → select this folder's `project.godot` → **Import & Edit**.
2. If Godot mentions the project was made with an older 4.x version, just open it anyway.
3. Press **F5**. You are standing in **Harbor Row**, a city block rendered
   from a 16 × 16 tileset. Three state guards patrol with flashlight cones
   that stop at walls; three sodium folders hold the intel; the amber door
   at the top right (under the sodium light pool) is your safehouse.
4. Win a night: collect all 3 folders, stand in the doorway, press **E**.
   Lose one: let a guard touch you (FLATLINED) or a cone catch you long
   enough. **R** restarts either way.
5. Systems to poke: **H** degrades the mugshot, **K** heals, **Ctrl/C**
   sneaks under cones.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Move | WASD / Arrow keys | Left stick |
| Dash | Shift / Space | A (bottom button) |
| Sneak | Ctrl / C (hold) | — |
| Takedown (close, from behind, unseen) | F | Y (top button) |
| Interact / Extract | E | X (left button) |
| Hurt (debug) | H | — |
| Heal (debug) | K | — |
| Restart | R | — |

H/K are gray-box probes until P2/P3 add real damage sources. E is real now:
it triggers extraction when you have all 3 intel.

## P2 stealth probe — guards, cones, sneak

`scripts/guard.gd` is the whole probe. Each guard walks its waypoint loop
(`patrol_points`, set per guard in `scenes/main.tscn`) holding a flashlight
cone. Detection rule, checked every physics frame:

1. **Range** — distance to the player ≤ `CONE_RANGE` (130 px),
   or `CONE_RANGE_SNEAK` (62 px) if the player is sneaking.
2. **Angle** — inside ±32° of the beam direction.
3. **Line of sight** — a raycast to the player must not hit the world layer
   first. Walls are real tiles now, and the cone *art* is occluded too (see
   the P3 section): what you see lit is what he can actually see.

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

The probe: sneak the left street past the pinch, let Guard2's artery cone
catch you mid-crossing, then test whether diving behind a building corner
actually shakes him — the cone art now stops exactly where his sight does.

## The night loop — intel, safehouse, win

One full "night" is now playable end to end:

1. **Collect** — walk into a sodium folder (`intel_pickup.gd`): it fills a
   HUD pip and frees itself. Three caches: top-left, bottom-left, and one
   deliberately parked above Guard1's patrol line.
2. **Extract** — the amber door (`exit_zone.gd`, top right) watches who is
   standing in it. Without full intel it prompts "need all 3 intel"; with
   full intel it prompts "press E to extract".
3. **Win** — E with 3/3 intel calls `player.extract()`: the PI freezes in
   the doorway and the HUD reads "EXTRACTED - the files burn at dawn. R
   starts the next night".
4. **Lose** — a guard touching you mid-chase (`player.capture()`) or any
   other flatline ends the night the same way it always has.

Loop tuning lives in the scenes: pickup radius (9 px) and door radius
(20 px) are the `CircleShape2D` values built in `intel_pickup.gd` /
`exit_zone.gd`; cache placement is in `scenes/main.tscn`.

## P3 — Harbor Row: the tileset world

`scripts/level_builder.gd` builds the whole block from an ASCII map (40 × 22
tiles of 16 px) at runtime, so level edits are readable git diffs:

| Char | Tile | Meaning |
| --- | --- | --- |
| `#` | `wall` / `wall_top` | Building mass and border. Full 16 × 16 collision on physics layer 2 ("world"). Cells whose top edge is exposed automatically get the bone roof-cap variant. |
| `.` | `floor_a` | Wet asphalt |
| `,` | `floor_b` | Asphalt variant, rain puddle |
| `o` | `drain` | Drain grate (dressing only) |
| `~` | `neon` | Sodium light pool — around the safehouse door |

One geometry, three systems: the wall tiles' physics layer is what the
player collides with, what the guards' sight raycast respects, and what the
cone fan clips against.

**Cone occlusion** (`guard.gd`): every frame the cone is redrawn as a
raycast fan — 20 rays across the ±32° arc (`CONE_STEPS`), each vertex
clamped to the first wall it hits. The drawn cone, the sneak-shrunk
detection range and the SEARCH sweep share one RayCast2D, so they stay in
sync by construction.

**Entity placement** lives in `scenes/main.tscn` (tile coords × 16 + 8 px
centering, +4 px for the map offset):

| Node | Position | Why there |
| --- | --- | --- |
| `Player` | (40, 300) | Bottom-left start, south of the PlanterD pinch |
| `Intel1` | (56, 44) | Top-left pocket — free while sneaking; risky to walk if Guard1 is heading west |
| `Intel2` | (584, 316) | Bottom-right, on the quiet right street — the naive route's "free" folder |
| `Intel3` | (328, 140) | Beside Guard2's artery line: sneak-grab it, or time his pass |
| `ExitZone` | (584, 28) | Top-right door pocket, under the sodium pools |
| `Guard1` | (200, 44)→(472, 44) | Sweeps the whole top street |
| `Guard2` | (296, 124)→(296, 316) | Owns the central artery, north–south |
| `Guard3` | (216, 188)→(312, 188) | Paces the mid-corridor junction — crossfire with Guard2 |

**Why this layout is hard**: any full loop must cross either Guard1's top
street or Guard2's artery, and Intel3 sits in the artery. The mid corridor
(rows 11–12 of the map) is the risky shortcut between the two halves —
Guard3 and Guard2's cones overlap at the junction, so the naive dash gets
you observed from two directions. The left street pinches to 3 tiles wide
past the planter wall (rows 11–14), a safe choke you will use a lot.

Known probe-era simplifications: guards pass through each other (they only
collide with the world), chase is slide-along-the-wall dumb (no pathfinding
yet — he rounds convex corners by sliding), and walking through a
patrolling guard is unnoticed (cones are the threat, not bodies).

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
| `assets/sprites/intel_sheet.png` | 32 × 16 | 2 intel-folder frames of 16 × 16 |
| `assets/sprites/exit_sheet.png` | 64 × 32 | 2 safehouse-door frames of 32 × 32 |
| `assets/tiles/harbor_tiles.png` | 96 × 16 | 6 tiles of 16 × 16 (P3 world set) |
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

The **intel folder** and **safehouse door** are the two sodium anchors —
"safe light" accents that pull the player's eye (roadmap color rules).
Folder: 2 frames of 16 × 16 (paper flutter). Door: 2 frames of 32 × 32
(sodium hum — one brighter flicker band).

### Editing the art in LibreSprite

- Open a sheet directly (**File ▸ Open**) and turn on a 32 × 32 grid
  (**View ▸ Grid ▸ Grid Settings**), or slice it into real frames via
  **File ▸ Import Sprite Sheet** (horizontal 12 × 1 for the player,
  6 × 1 for the guard, 2 × 1 for intel, 2 × 1 for the door, 6 × 1 for
  portraits — the intel sheet is 16 px frames, everything else 32 px).
- Load the palette via **Palette ▸ Load Palette** →
  `assets/palettes/redharbor_noir.gpl`.
- Keep edited sources in `assets_src/` as `.ase`, then **File ▸ Export**
  back to the same PNG path in `assets/sprites/` — Godot picks it up on
  the next run, no import settings to redo (Nearest filtering is
  project-wide).

### Style rules (roadmap §Art)

- 32 × 32 character, 16 × 16 world tiles, 6–10 colors per scene, noir
  palette only.
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
| Viewport | 640 × 360 | 16:9 — the Harbor Row map is exactly one screen (40 × 22 tiles of 16 px) |
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
scenes/main.tscn       Harbor Row: tilemap world, 3 intel caches, safehouse, 3 guards
scenes/player.tscn     CharacterBody2D + camera
scenes/hud.tscn        CanvasLayer HUD (portrait, pips, status, alerts, prompts)
scenes/guard.tscn      patrolling guard (CharacterBody2D, occluded cone)
scenes/intel_pickup.tscn  sodium folder (Area2D, touch to collect)
scenes/exit_zone.tscn  safehouse door (Area2D, E to extract)
scripts/player.gd      movement, dash, sneak, health, intel, extract
scripts/guard.gd       waypoints, vision cone + raycast-fan occlusion, chase AI
scripts/intel_pickup.gd  pickup pulse + collect on touch
scripts/exit_zone.gd   doorway state, extract prompt, win handoff
scripts/level_builder.gd  ASCII map -> TileMapLayer world with wall physics
scripts/hud.gd         portrait states, intel pips, sight alerts, prompts
assets/sprites/        all PNG sheets (Godot loads these)
assets/palettes/       redharbor_noir.gpl — 7-color noir palette
assets/tiles/          harbor_tiles.png — the P3 16 × 16 world set
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
- [x] P2 second half: the night loop — 3 intel caches + safehouse extraction
- [x] Make the loop hard: 3-guard Harbor Row placement that punishes the naive route
- [x] Give the cone art real occlusion (raycast fan, one geometry with detection)
- [x] Replace rectangle walls with a real 16 × 16 tileset (`level_builder.gd`)
- [ ] Roadmap Phase 3: roguelite frame — briefing choice screen, run-fail/
	  run-success states, the conspiracy board's binary night choice,
      the between-night apartment hub
- [ ] P5: jsfxr passes — dash hiss, alert sting, paper snatch, door chime
