extends CanvasLayer
## Doom-style HUD: the portrait IS the health bar (6 face states at 80/60/40/20/0),
## sodium pips count intel, the top line reports guard sight states. Legibility
## contract: bright fill OVER an ink outline, colour through the theme - never
## modulate, which tints the outline too and dissolves small text. The compact
## pass keeps every art widget under 48 px (locked by the smoke test).

const PORTRAIT_SHEET := preload("res://assets/sprites/portrait_sheet.png")
const FRAME_TEX := preload("res://assets/sprites/hud_frame.png")
const PIP_EMPTY := preload("res://assets/sprites/hud_pip_empty.png")
const PIP_FULL := preload("res://assets/sprites/hud_pip_full.png")

const INK := Color("14121c")
const COLOR_BONE := Color("ded6c7")
const COLOR_SODIUM := Color("e8b366")   # sodium, screen-bright
const COLOR_RED := Color("e85145")      # alarm red, screen-bright

const STATE_LABELS := ["CLEAN", "SCRAPED", "BRUISED", "BLEEDING", "CRITICAL", "FLATLINED"]
const STATE_COLORS := [
                                COLOR_BONE, COLOR_BONE, COLOR_SODIUM,
                                COLOR_SODIUM, COLOR_RED, COLOR_RED,
]
# Compact HUD scales (P3.3): frame + face at 1x so the block stays 40 x 40
# instead of an 80 x 80 wall over the play view; intel pips keep 2x so the
# win counter stays chunky at a glance.
const PORTRAIT_SCALE := 1.0
const PIP_SCALE := 2.0

# guard.gd Sight enum values (kept as ints - scripts stay decoupled)
const SIGHT_SEEN := 1
const SIGHT_SEARCHING := 2

var _portrait: TextureRect
var _state_idx := 0
var _portrait_frame := 0
var _portrait_t := 0.0
var _status: Label
var _hint: Label
var _alert: Label
var _prompt: Label
var _pips: Array[TextureRect] = []
var _guard_sight := {}   # guard -> last reported Sight value


func _ready() -> void:
                                var root := Control.new()
                                root.set_anchors_preset(Control.PRESET_FULL_RECT)
                                root.mouse_filter = Control.MOUSE_FILTER_IGNORE
                                add_child(root)

                                # Portrait sits under the frame; the frame's 32 px window
                                # (offset 4,4) takes the face at 1x, pixel-exact.
                                _portrait = _make_rect(PORTRAIT_SHEET, Vector2(12, 12), PORTRAIT_SCALE)
                                # BUGFIX: the sheet holds all 6 health states side by side; until the
                                # first health_changed arrives we must show ONLY the CLEAN frame,
                                # not the whole strip. (Was: raw sheet texture at startup.)
                                _portrait.texture = _portrait_tex(0)
                                root.add_child(_portrait)
                                root.add_child(_make_rect(FRAME_TEX, Vector2(8, 8), PORTRAIT_SCALE))

                                for i in 3:
                                                                var pip := _make_rect(PIP_EMPTY, Vector2(52, 10 + i * 14), PIP_SCALE)
                                                                root.add_child(pip)
                                                                _pips.append(pip)

                                _status = Label.new()
                                _status.position = Vector2(70, 26)   # right of the pips, mid-height
                                _style_label(_status, 10, STATE_COLORS[0])
                                _status.text = "CLEAN"
                                root.add_child(_status)

                                _hint = Label.new()
                                _hint.position = Vector2(12, 336)
                                _style_label(_hint, 10, COLOR_BONE)
                                _hint.text = "WASD move - Ctrl/C sneak - Shift/Space dash - F takedown - E extract - H hurt - K heal - R restart"
                                root.add_child(_hint)

                                # P2: surveillance line, top centre under the wall sign. Transient,
                                # so a slim chip is enough - it never fights the play view.
                                _alert = Label.new()
                                _alert.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
                                _alert.offset_top = 22
                                _alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                                _style_label(_alert, 11, COLOR_RED, 3)
                                _alert.visible = false
                                root.add_child(_alert)

                                # P2 second half: safehouse prompt, above the hint line.
                                _prompt = Label.new()
                                _prompt.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
                                _prompt.offset_top = 300
                                _prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
                                _style_label(_prompt, 11, COLOR_SODIUM)
                                _prompt.visible = false
                                root.add_child(_prompt)

                                # The player is instanced before this HUD in main.tscn; the frame wait
                                # is a safety net for scene-order changes.
                                await get_tree().process_frame
                                if Run.active:
                                        # Night mode: intel lives in the Run ledger (night_hud.gd), not in the
                                        # three street-probe pips. night_hud owns the bottom bar too.
                                        for pip in _pips:
                                                pip.visible = false
                                        _hint.visible = false
                                var player := get_tree().get_first_node_in_group("player")
                                if player:
                                                                player.health_changed.connect(_on_health_changed)
                                                                player.intel_changed.connect(_on_intel_changed)
                                                                player.died.connect(_on_died)
                                                                # Startup sync: paint the player's CURRENT state once. The
                                                                # widgets above already show fresh-night defaults, but this
                                                                # keeps the HUD truthful if it ever attaches to a player that
                                                                # is not fresh (scene-order changes, a between-nights hub).
                                                                _on_health_changed(player.health, player.MAX_HEALTH)
                                                                _on_intel_changed(player.intel, player.MAX_INTEL)
                                for guard in get_tree().get_nodes_in_group("guards"):
                                                                guard.sight_changed.connect(_on_guard_sight.bind(guard))
                                for zone in get_tree().get_nodes_in_group("exit_zone"):
                                                                zone.extract_ready_changed.connect(_on_extract_ready)
                                                                zone.extracted.connect(_on_extracted)


func _style_label(label: Label, size: int, color: Color, outline := 2) -> void:
                                # The one styling door every HUD text walks through. Fill goes to
                                # the theme so state recolors never touch the outline; modulate is
                                # pinned white so nothing can dim the text from outside.
                                label.add_theme_font_size_override("font_size", size)
                                label.add_theme_color_override("font_color", color)
                                label.add_theme_color_override("font_outline_color", INK)
                                label.add_theme_constant_override("outline_size", outline)
                                label.modulate = Color.WHITE


func _make_rect(tex: Texture2D, pos: Vector2, art_scale: float) -> TextureRect:
                                var tr := TextureRect.new()
                                tr.texture = tex
                                tr.position = pos
                                tr.scale = Vector2(art_scale, art_scale)
                                tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
                                return tr


func _portrait_tex(idx: int, frame: int = 0) -> AtlasTexture:
                                # portrait_sheet.png is 6 health states (columns) x 4 animation
                                # frames (rows): 0 base, 1 smoke drift, 2 blink, 3 smoke further.
                                var at := AtlasTexture.new()
                                at.atlas = PORTRAIT_SHEET
                                at.region = Rect2(idx * 32, frame * 32, 32, 32)
                                return at


func _process(delta: float) -> void:
                                # The mugshot is alive: cigarette smoke drifts every 0.3 s and the
                                # PI blinks for 0.12 s every ~3.4 s. Critical and flatlined faces
                                # never blink.
                                if _portrait == null:
                                                                return
                                _portrait_t += delta
                                var smoke_seq: Array[int] = [0, 1, 3, 1]
                                var f: int = smoke_seq[int(_portrait_t / 0.3) % 4]
                                if _state_idx <= 3 and fmod(_portrait_t, 3.4) < 0.12:
                                                                f = 2
                                if f != _portrait_frame:
                                                                _portrait_frame = f
                                                                _portrait.texture = _portrait_tex(_state_idx, f)


func _state_index(current: int) -> int:
                                if current <= 0:
                                                                return 5
                                if current <= 20:
                                                                return 4
                                if current <= 40:
                                                                return 3
                                if current <= 60:
                                                                return 2
                                if current <= 80:
                                                                return 1
                                return 0


func _on_health_changed(current: int, _max_health: int) -> void:
                                var idx := _state_index(current)
                                _state_idx = idx
                                _portrait.texture = _portrait_tex(idx, _portrait_frame)
                                _status.text = STATE_LABELS[idx]
                                _status.add_theme_color_override("font_color", STATE_COLORS[idx])


func _on_intel_changed(count: int, _max_intel: int) -> void:
                                for i in _pips.size():
                                                                _pips[i].texture = PIP_FULL if i < count else PIP_EMPTY


func _on_died() -> void:
                                _hint.text = "FLATLINED - press R to restart the night" if not Run.active else "CAUGHT - the case goes cold"
                                _hint.add_theme_color_override("font_color", COLOR_RED)


func _on_guard_sight(state: int, guard) -> void:
                                _guard_sight[guard] = state
                                var values := _guard_sight.values()
                                if values.has(SIGHT_SEEN):
                                                                _alert.text = "OBSERVED"
                                                                _alert.add_theme_color_override("font_color", COLOR_RED)
                                                                _alert.visible = true
                                elif values.has(SIGHT_SEARCHING):
                                                                _alert.text = "SEARCHING"
                                                                _alert.add_theme_color_override("font_color", COLOR_SODIUM)
                                                                _alert.visible = true
                                else:
                                                                _alert.visible = false


func _on_extract_ready(inside: bool, ready: bool) -> void:
                                if inside and ready:
                                                                _prompt.text = "SAFEHOUSE - press E to extract"
                                                                _prompt.add_theme_color_override("font_color", COLOR_SODIUM)
                                                                _prompt.visible = true
                                elif inside:
                                                                _prompt.text = "SAFEHOUSE - need all 3 intel"
                                                                _prompt.add_theme_color_override("font_color", COLOR_BONE)
                                                                _prompt.visible = true
                                else:
                                                                _prompt.visible = false


func _on_extracted() -> void:
                                _prompt.visible = false
                                _alert.visible = false
                                _hint.text = "EXTRACTED - the files burn at dawn. R starts the next night"
                                _hint.add_theme_color_override("font_color", COLOR_SODIUM)
