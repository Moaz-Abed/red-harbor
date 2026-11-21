# Red Harbor — Godot 4 Starter (Harbor Row: tileset world, stealth night, Doom-style HUD)

Neo-noir espionage roguelite. This folder continues the plan from
`Red_Harbor_Game_Development_Roadmap.docx`: gray-box movement (P1), the P2
stealth probe (patrolling guards, vision cones, sneak), the night loop —
grab 3 intel folders, then extract at the safehouse door — a Doom-style
health HUD (**the portrait is the health bar**) and, new in P3, a real
16 × 16 tileset world: **Harbor Row** — now dealt fresh every night, whose
walls block movement, sight and the cone art alike.

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
| Takedown | F (close, behind a guard) | — |
| Interact / Extract | E | X (left button) |
| Hurt (debug) | H | — |
| Heal (debug) | K | — |
| Restart | R | — |

H/K are gray-box probes until P2/P3 add real damage sources. E is real now:
it triggers extraction when you have all 3 intel. F is real: see the
**silent takedown** section below.

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

While chasing, the guard runs at your LAST SEEN position and keeps closing
while he can see you; if he reaches it without seeing you again he sweeps
the flashlight for 2.6 s, then resumes patrol from the nearest waypoint.
If he touches you during a chase, the night ends (`player.capture()` →
FLATLINED portrait → R to restart). During SEARCH the detection direction
follows the *sweeping beam*, not the body — what you see lit is what he
sees.

**Silent takedown (F)** — sneak up BEHIND a patrolling guard and press F:
he must not be mid-chase, you must be within 22 px, behind his beam
(dot < −0.2) with no wall between. He goes down for the whole night
(darkened lying sprite), 60 ms hit-stop + screen shake sells the thump.
Downed guards report CLEAR to the HUD, so OBSERVED / SEARCHING drop
honestly.

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

## The Night Loop (roadmap 4.2) — a Hades-style run

The game boots into **the office** (`scenes/briefing.tscn`). Every visit deals
**three different cases** and every night deals a **different building**, so
no two runs play alike:

**OFFICE (case + boon) → FLOOR 1 → back-door decision → [FLOOR 2] → DEBRIEF → OFFICE**

### The board: three cases that are *not* the same night

Each case has its own **jobs**, its own **district rule** and its own **reward**.
A board always shows three *different* rules (`Run.roll_offers`):

| Rule | What it does to the night |
| --- | --- |
| **QUIET HOURS** | No rule. The clean heist. |
| **ON AIR** | Dashes and takedowns are *loud*: a ring shows how far, and guards inside it come to look. |
| **CURFEW** | The alarm climbs by itself every 40 s (a countdown on screen). Intel pays **double**. |
| **BLACKOUT** | Lights out: short beams, but patrols run 25 % faster. |
| **HIGH SECURITY** | +1 guard on every floor. Intel pays ×1.5. |
| **SEALED VAULT** | No lower floor. The 8-point evidence case is on *this* floor. |

The six case archetypes (`Run.ARCHETYPES`) pair a rule with a job set — e.g.
*Voices on the Wire* (3 bug/doc jobs, ON AIR, favors), *The Red Tide Ledger*
(ledger photos, CURFEW), *The Dead Drop* (one evidence case, SEALED VAULT) — and
a **reward**: **favors** (permanent upgrades) or **2 boon picks**.

### Boons: your build for the night (Hades' boons)

After you take a case you pick **one boon of three** (two if the case rewards a
boon). A boon lasts the whole night; R keeps them, a new case resets them.
`Run.BOONS`: SOFT SOLES, ADRENALINE, LONG COAT, FAST HANDS, ESCAPE ARTIST,
SILVER TONGUE, OLD FRIEND, GREED, RUNNER'S HIGH, COLD SHOULDER, LUCKY COIN
(slip away from the first capture, like Katana ZERO's one-hit tension with a
second chance). Add one to the array and it is dealt.

### The desk drawer: permanent upgrades (Dead Cells' loop)

Favors persist in `user://red_harbor.cfg`. Spend them in the office (**Z / X /
C**): LONG STRIDE (dash +12 %), MUFFLED SOLES (sneak +8 %, noise −20 %), DEEP
POCKETS (insurance +10 %), three levels each.

### Tight spots

A body is 12 × 18 px; a 1-tile-tall slot is 16 px, so a *standing* PI cannot
walk through it. Those slots are marked with a **chevron floor tile**. Walk
into one and the PI drops into a **belly crawl** (the `squeeze` animation, a
10 px collider, sneak-grade visibility, a magnet that centres you on the slot);
stand up again on the far side. **Guards cannot**: they have a real collider now
(they no longer slip through walls) and the guard nav grid treats every tight
spot as solid, so patrols and chases route around. Each building has 1–2
deliberate crawl holes through walls between rooms — shortcuts only you can
use. The generator only keeps a deal if every room, job and the back door is
reachable *without* crawling.

### Fast

Hotline Miami pace: walk 185 px/s, dash 520 px/s over 0.125 s (still ~4
tiles), 0.24 s dash cooldown, snappy accel and stop, a quicker camera, faster
guards (patrol 68, chase 150), a 0.12 s fade-in so **R** restarts instantly
(same case, same boons, a fresh building) and a style **chain**: takedowns and
jobs inside 6 s link up and score ×chain (shown on the HUD, totalled in the
debrief; a ghost run — never spotted — adds a bonus).

### The rest of the loop

| Step | What happens | Where |
| --- | --- | --- |
| The building | 9–12 rooms from furniture templates in a 3×3 grid, 0–3 split rooms, doorways from a spanning tree + loops. | `building_builder.gd` |
| The jobs | Hold **E** beside the prop: bug a phone, steal documents, photograph a ledger, secure evidence. | `task_spot.gd` |
| Intel tiers | GOSSIP 1 · LEADS 3 · EVIDENCE 8 pts, unbanked until you leave. | `run_state.gd` |
| Alarm ladder | Each new sighting climbs a tier: ALERTED +1 guard · HUNT faster patrols, longer beams · LOCKDOWN +1 guard, every guard hunts, lower floor sealed. | `run_state.gd`, `night.gd`, `guard.gd` |
| The back door | **E** leave and bank everything · **Q** descend for EVIDENCE (not on SEALED VAULT, not in LOCKDOWN). | `back_door.gd` |
| Caught | Keep only the insurance share (20 % + upgrades/boons) of what you carried, plus a few favors. | `Run.finish` |
| Debrief | Carried / banked, alarm peak, style, favors. **R** again · **Enter** office. | `night_hud.gd` |

**Tuning knobs.** Points, hold times, alarm multipliers, rules, boons, shop
costs, insurance and the chain window are constants at the top of
`run_state.gd`. Furniture layouts are the `FULL_TEMPLATES` / `HALF_TEMPLATES`
ASCII arrays in `building_builder.gd` (10 × 2, stamped on the middle two rows so
walls never form accidental slots). `Run.debug_seed = N` pins the building deal
for QA.

**Tests.** `godot --headless --path . res://tests/night_test.tscn` covers the
run state; 40 boards (always 3 different rules); boons, upgrades and the save /
load; 162 generated buildings (9–12 rooms, one job per room, reachable *without*
crawling, tight spots solid for guards); the night end to end (jobs, ON AIR
noise, CURFEW bell, BLACKOUT, SEALED VAULT, lockdown, leave / descend / caught,
LUCKY COIN); the PI crawling through a slot while a standing PI is stopped;
guards crossing the building in 10 hunts without entering a wall or a slot; and
the office (case → boon picks → shop).

**Not in this slice (roadmap Phase 3 / backlog):** the conspiracy board and the
binary choice after a night, the camera drone and EMP lighter, and the
soundtrack (the mood-driven part of the Hotline Miami reference).

## The street-probe night — intel, safehouse, win

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

### P3.2 — every night is a new block (procedural Harbor Row)

Opening the scene — and every R restart — now deals a fresh 40 × 22 block.
`scripts/game.gd` orchestrates: `level_builder.gd` rolls the city, returns
a placement *plan* (grid cells), and game.gd plants the cast on it. The
positions in `main.tscn` are editor previews only.

Generator invariants (all locked by the smoke test):

- The border is wall; the 2-tile ring inside it is **always open street**,
  so the block can always be circled.
- Buildings are random rectangles (city blocks / warehouses / planters)
  kept ≥ 1 tile apart — which provably connects all floor. A BFS runs
  anyway and seals any stray pocket, so intel can never be stranded.
- You spawn on the bottom street; the safehouse door + sodium pool land on
  the top street at the far end of the block.
- 3 caches: ≥ 9 tiles apart, ≥ 7 from your spawn, ≥ 6 from the door.
- 3 straight patrol lines: ≥ 10 tiles from your spawn (calm night start),
  ≥ 5 from the door, ≥ 6 between guards, every segment on open floor —
  with a guaranteed perimeter-street fallback.

Tuning lives at the top of `level_builder.gd` (`BUILD_AREA_TARGET`,
`DRAIN_COUNT`, `PUDDLE_COUNT`, the distance rules in `_deal_guard_route` /
`_deal_intel`). game.gd prints a one-line `NIGHT` summary on boot — run
the smoke test a dozen times and diff the lines to watch the deals vary.

### P3.1 — hardening pass (walls, cones, HUD)

Three bugs from the first Harbor Row playtest, each reproduced with a
real Godot binary and locked behind a regression check in `tests/`:

| Symptom | Root cause | Fix |
| --- | --- | --- |
| Player phases through walls | `level_builder.gd` bound the atlas source to the TileSet AFTER writing per-tile collision polygons. TileData only learns its physics layers once its source is bound, so every polygon was silently dropped — walls shipped with zero collision. | `add_source()` now runs before any TileData physics, with a debug `assert` tripwire. |
| Guard cones invisible | The cone Polygon2D sat at `z_index = -1`, which is global — it slid the light UNDER the tilemap's z = 0 floor tiles. What you never saw could still catch you. | Screen z contract: floor 0 < cone 1 < actors 2 (`Z_CONE` / `Z_ACTOR` in `guard.gd`). Cone alphas raised to 0.30 / 0.55 / 0.35 so the fog cone reads on dark asphalt. |
| HUD words barely readable | Tiny labels used art-grade fills (fog gray, ink-red) with no outline and were recolored via `modulate`, which dims whatever is behind the glyphs too. | Every label goes through `_style_label()`: bright text-variant palette fill over a 2–3 px ink outline; recolors go through the theme, never modulate; OBSERVED / SEARCHING are centered at 14 px. |

**Self-test** — boots the real main scene headless, pushes real input, and
asserts all three contracts:

```bash
godot --headless --path . res://tests/smoke.tscn
```

`SMOKE: ALL PASS` (exit 0) means: walls stop the body at the predicted
spot, sight rays stop at wall faces, cones paint above the floor with
readable alpha and a full ray fan, every HUD label carries its ink
outline with a bright fill, and no HUD art widget exceeds 48 px on a
side. Run it after any physics, guard or HUD change
(or press F6 on `tests/smoke.tscn` in the editor).

### P3.3 — compact HUD pass

The portrait block drew at a flat 2x: an 80 × 80 frame wall in the
top-left corner with the status word reaching ~110 px down the left
edge — a fifth of the 640 × 360 view dead before you took a step, right
where intel caches and the safehouse door like to spawn.

| Change | Before | After |
| --- | --- | --- |
| Frame + face | 2× → 80 × 80 block | 1× → 40 × 40 block; the 32 px face is now literally the size of the PI's sprite on screen |
| Intel pips | floating at x 96 under the frame | 2× column right of the frame at (52, 10/24/38) — still chunky, still the win counter |
| Status word | (96, 96), 11 px | (70, 26), 10 px — beside the pips, mid-height |

The whole cluster now fits in the top 52 px of the left edge. The
contract is locked by the smoke test: collect every `TextureRect` under
the HUD root and fail if any scaled widget exceeds 48 px on a side
(`HUD art stays compact`). Integer scales only — the project ships with
nearest-neighbor filtering, so 1.5× would smear the pixels.

### P3.4 — the vanishing cache (~1.5% of nights)

A rare race the early P3.2 playtests could not pin: every few dozen
boots, one intel cache was simply gone before the first input frame —
the smoke test failed with `three intel caches found (got 2)` while the
player stood nowhere near any cache.

Root cause, verified with a node-vs-physics-server probe: when
`game.gd` applies the night plan during scene setup, Area2D transforms
reach the physics server immediately, but a `CharacterBody2D`'s
transform does not — the player's **body** kept its editor-preview
transform through the first physics step (node at the plan spawn, body
still at (40, 300)). Any cache dealt beside the preview spot (ring
cells land at (40, 284…316), 16 px away — inside the 9 px pickup
radius) paired with that stale body and was pocketed before frame 2.
Neither `call_deferred` nor a direct `PhysicsServer2D.body_set_state`
push closes the window; the body's pending state overrides both.

Fix: intel caches arm **late**. `intel_pickup.gd` starts with
`monitoring = false` and arms two physics frames after boot, once every
body has stepped into place. No legit pickup is lost (the deal keeps
caches ≥ 7 tiles from the PI, and ~1 px of movement by frame 2). The
pinned seed sweep — 400 deals that reproduced the bug at 1.5% — now
reports zero vanishing caches, and all six previously-failing seeds
pass.

The smoke test's border walk was hardened in the same pass: it now runs
260 frames (~650 px) so the player always ends ON a border face, and
the assertion demands real contact (`x <= 24` west / `x >= 616` east).
The old 120-frame walk covered ~300 px, so the wall check had quietly
gone vacuous — it could no longer catch a phase-through regression.

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
beside the portrait are the **intel counter** (core loop — press E to
preview). Since P3.3 the whole portrait block draws compact (frame 40 ×
40 at 1×, pips at 2×) so it stops eating the top-left of the play view —
see `preview/preview_portrait_hud.png`.

## Sprite sheets & animation (smooth pass)

All art is 1:1 pixels using exactly the 7-color noir palette
(`assets/palettes/redharbor_noir.gpl`). The character, folder, door and
portrait sheets are generated by `python3 assets_src/gen_sprites.py` from one
small rig (legs, coat, arms, head, hat), so every walk/sneak/dash cycle stays
consistent and a proportion or palette tweak is one edit. (Hand-editing a
sheet in LibreSprite works too, but re-running the generator overwrites it.)

| File | Size | Contents |
| --- | --- | --- |
| `assets/sprites/player_sheet.png` | 256 × 640 | 20 rows × up to 8 frames of 32 × 32 (map below) |
| `assets/sprites/guard_sheet.png` | 256 × 480 | 15 rows × up to 8 frames of 32 × 32 (map below) |
| `assets/sprites/intel_sheet.png` | 96 × 16 | 6 folder frames of 16 × 16: bob, paper flutter, glint |
| `assets/sprites/exit_sheet.png` | 192 × 32 | 6 door frames of 32 × 32: lamp flicker + scanline sweep |
| `assets/tiles/harbor_tiles.png` | 176 × 16 | 6 street tiles + desk, cabinet, rug, crate, crawlspace (building set) |
| `assets/sprites/task_sheet.png` | 96 × 48 | job props, 6 frames each: bug phone, ledger, evidence case (documents reuse the folder) |
| `assets/sprites/portrait_sheet.png` | 192 × 128 | 6 health states (columns) × 4 frames (rows) |
| `assets/sprites/hud_frame.png` | 40 × 40 | Portrait frame, sodium rivets |
| `assets/sprites/hud_pip_empty/full.png` | 7 × 7 | Intel counter pips |
| `preview/` | — | enlarged previews (ignored by Godot via `.gdignore`) |

**Metal Gear-style views.** Characters are drawn from three views — `down`
(front), `up` (back) and `side` (faces right; mirrored for left). 8-direction
input picks the view (`_set_facing` in `player.gd`, `_set_view` in
`guard.gd`); near-diagonals keep the current view so the sprite never
flickers, and a view change mid-walk keeps the stride phase.

**Player sheet** — rows are `anim × view`, view order down / up / side:

| Rows | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0–2 | `idle` | 4 | Breathing bob + drifting cigarette smoke |
| 3–5 | `walk` | 8 | Contact / pass cycle; playback speed follows real velocity |
| 6–8 | `sneak` | 6 | Crouched, lower and shorter stride; holds a pose when still |
| 9–11 | `dash` | 4 | Launch crouch, stretch, recover (~ `DASH_TIME`) + afterimage |
| 12–14 | `takedown` | 4 | Reach, grab + lunge, hold, release; feet plant briefly |
| 15–17 | `hurt` | 2 | Recoil + blood pixel |
| 18 | `dead` | 6 | Stagger, buckle, fall, lie, blood pool grows |
| 19 | `squeeze` | 6 | Belly crawl through a 1-tile slot (side view, mirrored for left) |

**Guard sheet** — peaked cap with a red band, broader greatcoat, red armband,
flashlight in the hand that the beam comes from:

| Rows | Animation | Frames | Notes |
| --- | --- | --- | --- |
| 0–2 | `patrol` | 8 | Heavy march |
| 3–5 | `chase` | 8 | Forward lean, coat tails trailing |
| 6–8 | `idle` | 4 | Waiting at a waypoint |
| 9–11 | `alert` | 4 | Torch up + "!" — the "spotted" beat |
| 12 / 14 | `search` | 6 | Side / front head sweep (facing away just idles) |
| 13 | `ko` | 6 | Takedown: stagger, buckle, fall, lie (no blood) |

The **intel folder** and **safehouse door** are the two sodium anchors —
"safe light" accents that pull the player's eye (roadmap color rules).

**Guard feel (Metal Gear pass).** The beam now *turns* at a fixed angular
speed (`TURN_SPEED` 5.5 rad/s patrolling, `TURN_CHASE` 12 rad/s hunting)
instead of snapping, and a guard stops at every waypoint for
`WAYPOINT_PAUSE` (0.7 s), looks along the next leg, then walks — so there is a
readable window to slip past. The cone is red for the whole chase.

**Tests.** `godot --headless --path . res://tests/anim.tscn` checks every
animation frame lies inside its sheet, that held directions pick the right
view and mirroring, dash/sneak/hurt/dead/takedown clips, the guard state
clips, bounded beam turning and the KO clip. `tests/smoke.tscn` is unchanged.

### Editing the art in LibreSprite

- Open a sheet directly (**File ▸ Open**) and turn on a 32 × 32 grid
  (**View ▸ Grid ▸ Grid Settings**), or slice it into real frames via
  **File ▸ Import Sprite Sheet** (player 8 × 19, guard 8 × 15, intel 6 × 1 of 16 px, door 6 × 1,
  portraits 6 × 4 — everything except the intel folder is 32 px cells).
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
scenes/briefing.tscn   THE OFFICE - the boot scene: pick one of three leads
scenes/night.tscn      the night: building world, PI, back door, HUDs (guards + jobs are dealt in code)
scenes/task_spot.tscn  one job prop (hold E)    scenes/back_door.tscn  the leave / descend door
scenes/main.tscn       street probe (legacy P3): Harbor Row, 3 intel caches, safehouse, 3 guards
scenes/player.tscn     CharacterBody2D + camera
scenes/hud.tscn        CanvasLayer HUD (portrait, pips, status, alerts, prompts)
scenes/guard.tscn      patrolling guard (CharacterBody2D, occluded cone)
scenes/intel_pickup.tscn  sodium folder (Area2D, touch to collect)
scenes/exit_zone.tscn  safehouse door (Area2D, E to extract)
scripts/player.gd      movement, dash, sneak, health, intel, extract
scripts/guard.gd       waypoints, vision cone + raycast-fan occlusion, chase AI
scripts/intel_pickup.gd  pickup pulse + collect on touch
scripts/exit_zone.gd   doorway state, extract prompt, win handoff
scripts/level_builder.gd  procedural Harbor Row: random block -> TileMapLayer with wall physics
scripts/game.gd         night orchestrator: deals the block, plants the cast
scripts/hud.gd         portrait states, intel pips, sight alerts, prompts
scripts/run_state.gd   AUTOLOAD "Run": the board, rules, boons, favors + shop, intel tiers, alarm ladder, style chain
scripts/building_builder.gd  9-12 room building from templates, crawl holes, A* nav grid (guards avoid tight spots)
scripts/noise_ring.gd  the ON AIR noise ring
scripts/night.gd       night orchestrator: deals a floor, alarm reactions, extract / descend / caught
scripts/task_spot.gd   hold-E job (bug / documents / ledger / evidence)
scripts/back_door.gd   the signature decision: leave now or descend
scripts/night_hud.gd   ledger, alarm ladder, job list, door prompt, debrief
scripts/briefing.gd    the office: the board, the boon pick, the desk drawer
tests/smoke.tscn       headless smoke test (F6, or the godot command above)
tests/smoke_runner.gd  asserts walls, sight rays, cone layering, HUD legibility
tests/anim.tscn        headless animation test (sheet layout, views, clips, turning)
tests/night_test.tscn  headless night-loop test (run state, 162 buildings, the night, nav, office)
assets/sprites/        all PNG sheets (Godot loads these)
assets/palettes/       redharbor_noir.gpl — 7-color noir palette
assets/tiles/          harbor_tiles.png — 6 street tiles + desk, cabinet, rug, crate (16 × 16)
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
- [x] P3.1 hardening: walls actually collide, cones paint above the floor,
	  HUD text outlined — all locked by the headless smoke test in `tests/`
- [x] Phase 1 feel pass (community merge): F takedown, hit-stop + shake,
	  dash afterimage, dash buffer, dash i-frames, chase close-in fix
- [x] P3.2: procedural Harbor Row — a fresh block every boot and restart
	  (`game.gd` + `level_builder.gd` generator, variance-checked in QA)
- [ ] Roadmap Phase 3: roguelite frame — briefing choice screen, run-fail/
	  run-success states, the conspiracy board's binary night choice,
      the between-night apartment hub
- [ ] P5: jsfxr passes — dash hiss, alert sting, paper snatch, door chime
