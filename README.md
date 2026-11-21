# Red Harbor

A neo-noir espionage roguelite, rendered the PS1 way: low-poly 3D, a 480x270
frame upscaled onto the tube, vertex snapping, Gouraud light, dithered color
and film grain. Think Buckshot Roulette / MACHINE PARTY energy on a Soviet-run
alternate New York.

You are the PI. One dealt case at a time, from the bag.

## Where the game is right now

The slice: **menu -> the office**. The office is the game loop for now -
read the case file at the desk, buy permanent upgrades at the file wall,
pick boons at the informant's radio, deal the next case at the neon door.
Nights (the building, the guards, the extraction) come back as PS1 levels
once the office loop feels right.

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | walk the office |
| `E` | use the spot you're standing at |
| `A/D` + `ENTER`, `1/2/3` | pick a boon at the radio |
| `Z/X/C` | buy an upgrade at the file wall |
| `ESC` | close a panel / pause |

## The look (one shader, one tube)

- `shaders/ps1_mat.gdshader` - the only surface material: per-vertex lighting,
  clip-space vertex snapping to the low-res grid, nearest textures, a tint /
  texture / glow triple that covers every surface in the game.
- `scripts/comps/ps1_view.gd` - the tube: a 480x270 SubViewport with one
  camera, upscaled nearest onto the 640x360 canvas.
- `shaders/ps1_post.gdshader` - the finish: 5-bit color with a Bayer dither,
  faint scanlines, a vignette.
- `shaders/grain.gdshader` - animated film grain above everything.

The diorama trick: the camera-side wall is a cutaway, the top is open, so a
simple fixed-angle follow camera always sees the action.

## Structure

```
scripts/
  run_state.gd      autoload "Run": the case bag, boons, favors, shop, save file
  office.gd         the office scene: world build, HUD, panels, input
  office_room.gd    the PS1 diorama: the MAP legend extruded into boxes
  pi3d.gd           the PI: a low-poly box rig, WASD + move_and_slide; the
                    stride crossfades with idle, tails ride a damped spring
  pause_menu.gd     the ESC overlay
  menu.gd           the title screen: spring logo behind a CRT tube
  comps/ps1_view.gd the low-res viewport + post chain
assets_src/
  gen_ps1_textures.py   regenerates assets/tex/ (painted + Bayer dithered);
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

Saves live in `user://red_harbor.cfg` (favors + shop levels).
