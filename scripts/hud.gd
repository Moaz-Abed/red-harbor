extends CanvasLayer
## Red Harbor Doom-style HUD: the portrait IS the health bar.
##
## No healthbars in this game. The PI's face degrades through 6 states
## (portrait_sheet.png), sampled at the same thresholds as the classic
## Doom mugshot: 80 / 60 / 40 / 20 / 0 percent.
## The 3 sodium pips are the intel counter (core loop: gather intel, then
## choose extraction or push deeper).
## P2: guards report their sight state; the top line shows OBSERVED (red)
## while any guard hunts you and SEARCHING (sodium) while one sweeps.

const PORTRAIT_SHEET := preload("res://assets/sprites/portrait_sheet.png")
const FRAME_TEX := preload("res://assets/sprites/hud_frame.png")
const PIP_EMPTY := preload("res://assets/sprites/hud_pip_empty.png")
const PIP_FULL := preload("res://assets/sprites/hud_pip_full.png")

const STATE_LABELS := ["CLEAN", "SCRAPED", "BRUISED", "BLEEDING", "CRITICAL", "FLATLINED"]
const STATE_COLORS := [
		Color("ded6c7"), Color("ded6c7"), Color("e0a458"),
		Color("e0a458"), Color("c1292e"), Color("c1292e"),
]
const HUD_SCALE := 2.0

# guard.gd Sight enum values (kept as ints - scripts stay decoupled)
const SIGHT_SEEN := 1
const SIGHT_SEARCHING := 2
const COLOR_SODIUM := Color("e0a458")
const COLOR_RED := Color("c1292e")

var _portrait: TextureRect
var _status: Label
var _hint: Label
var _alert: Label
var _pips: Array[TextureRect] = []
var _guard_sight := {}   # guard -> last reported Sight value


func _ready() -> void:
		var root := Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		# Portrait sits under the frame; the frame's window is transparent.
		_portrait = _make_rect(PORTRAIT_SHEET, Vector2(16, 16))
		root.add_child(_portrait)
		root.add_child(_make_rect(FRAME_TEX, Vector2(8, 8)))

		for i in 3:
				var pip := _make_rect(PIP_EMPTY, Vector2(96, 20 + i * 24))
				root.add_child(pip)
				_pips.append(pip)

		_status = Label.new()
		_status.position = Vector2(96, 96)
		_status.add_theme_font_size_override("font_size", 10)
		_status.text = "CLEAN"
		_status.modulate = STATE_COLORS[0]
		root.add_child(_status)

		_hint = Label.new()
		_hint.position = Vector2(12, 336)
		_hint.add_theme_font_size_override("font_size", 9)
		_hint.modulate = Color(0.48, 0.44, 0.5)
		_hint.text = "WASD move - Ctrl/C sneak - Shift/Space dash - H hurt - K heal - E intel - R restart"
		root.add_child(_hint)

		# P2: surveillance line, top center. Hidden until a guard reports.
		_alert = Label.new()
		_alert.position = Vector2(280, 8)
		_alert.add_theme_font_size_override("font_size", 12)
		_alert.visible = false
		root.add_child(_alert)

		# The player is instanced before this HUD in main.tscn; the frame wait
		# is a safety net for scene-order changes.
		await get_tree().process_frame
		var player := get_tree().get_first_node_in_group("player")
		if player:
				player.health_changed.connect(_on_health_changed)
				player.intel_changed.connect(_on_intel_changed)
				player.died.connect(_on_died)
		for guard in get_tree().get_nodes_in_group("guards"):
				guard.sight_changed.connect(_on_guard_sight.bind(guard))


func _make_rect(tex: Texture2D, pos: Vector2) -> TextureRect:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.position = pos
		tr.scale = Vector2(HUD_SCALE, HUD_SCALE)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr


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
		var at := AtlasTexture.new()
		at.atlas = PORTRAIT_SHEET
		at.region = Rect2(idx * 32, 0, 32, 32)
		_portrait.texture = at
		_status.text = STATE_LABELS[idx]
		_status.modulate = STATE_COLORS[idx]


func _on_intel_changed(count: int, _max_intel: int) -> void:
		for i in _pips.size():
				_pips[i].texture = PIP_FULL if i < count else PIP_EMPTY


func _on_died() -> void:
		_hint.text = "FLATLINED - press R to restart the night"
		_hint.modulate = COLOR_RED


func _on_guard_sight(state: int, guard) -> void:
		_guard_sight[guard] = state
		var values := _guard_sight.values()
		if values.has(SIGHT_SEEN):
				_alert.text = "OBSERVED"
				_alert.modulate = COLOR_RED
				_alert.visible = true
		elif values.has(SIGHT_SEARCHING):
				_alert.text = "SEARCHING"
				_alert.modulate = COLOR_SODIUM
				_alert.visible = true
		else:
				_alert.visible = false
