# Red Harbor

A neo-noir espionage roguelite, rendered the PS1 way: low-poly 3D, a 480x270
frame upscaled onto the tube, vertex snapping, Gouraud light, dithered color
and film grain, on a Soviet-run alternate New York.

You are the PI. One dealt case at a time, from the bag. He looks the part:
grizzled gray-brown hair swept back with volume on top, a gray chevron
mustache and a chin beard, a light khaki shirt with a charcoal tie and
near-black braces over a leather belt and brass buckle, high-waist
chocolate slacks, a walkie-talkie and a key ring clipped at the back belt,
and a cigarette that never goes out - see `docs/character_reference.png`.

## Where the game is right now

The slice: **menu -> the office**. The office is the game loop for now -
walk the room and deal the next case at the steel door. The reading panels
and the informant's phone are out until the stealth / roguelike / horror
loop replaces them with mechanics that earn their keep. Nights (the
building, the guards, the extraction) come back as PS1 levels once the
office loop feels right.

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | walk the office |
| mouse | orbit the lens around the PI |
| `E` | use the spot you're standing at |
| `ESC` | pause |

## The look (one shader, one tube)

- `shaders/ps1_mat.gdshader` - the only surface material: per-vertex lighting,
  clip-space vertex snapping to the low-res grid, nearest textures, a tint /
  texture / glow triple that covers every surface in the game.
- `scripts/comps/ps1_view.gd` - the tube: a 480x270 SubViewport with one
  camera, upscaled nearest onto the 640x360 canvas.
- `shaders/ps1_post.gdshader` - the finish: 5-bit color with a Bayer dither,
  faint scanlines, a vignette.
- `shaders/grain.gdshader` - animated film grain above everything.

The diorama trick: the room is a sealed box - four walls and a lid - so no
camera angle inside it ever opens on the void.

## Structure

```
scripts/
  run_state.gd      autoload "Run": the case bag and tonight's dealt case
  office.gd         the office scene: world build, HUD, input
  office_room.gd    the PS1 diorama: walls, props, steel, all in boxes
  pi3d.gd           the PI: a low-poly box rig rebuilt off the reference
                    sheet - khaki shirt with pockets, proud tie/braces/buckle
                    geometry, the belt kit (walkie + keys) swinging on the
                    stride, gray mustache and chin beard as real geometry,
                    one ember accent; the stride crossfades with idle, the
                    shirt tail rides a damped spring
  ambient_events.gd autoload "Ambient": radio one-liners, city sounds,
                    shelf drops - pure atmosphere
  pause_menu.gd     the ESC overlay
  menu.gd           the title screen: the ember field off the orbit study
                    (additive loop) under the fire art title, ENTER GAME in
                    the same style, behind a CRT tube
  comps/ps1_view.gd the low-res viewport + post chain
assets_src/
  gen_textures.py   regenerates assets/tex/ (painted + Bayer dithered);
                    the PI sheets are painted per BoxMesh face cell (3x2)
tests/
  smoke.tscn        headless assertions: `godot --headless --path . res://tests/smoke.tscn`
  capture.tscn      screenshot harness: `godot --path . res://tests/capture.tscn -- --scene=office --out=/tmp/shot.png`
  pi_closeup.tscn   PI model inspector: orbit the rig idle or mid-stride for
                    body/face QA: `... pi_closeup.tscn -- --yaw=0 --look=head --out=/tmp/face.png`
```

## Run it

Open the project in Godot 4.3+ (GL Compatibility renderer) and press play.
From the CLI:

```sh
godot --path .
godot --headless --path . --import          # first import
godot --headless --path . res://tests/smoke.tscn
```

Saves live in `user://red_harbor.cfg`.
