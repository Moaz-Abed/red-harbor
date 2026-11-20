extends Control
## Red Harbor - the PI's office: the briefing (roadmap 4.2).
##
## A night opens here. Three leads are on the desk, each tied to a district
## and a case file; pick one and the night starts. The lead decides which
## jobs are dealt (steal documents / bug a phone / photograph a ledger), how
## many guards walk the building and how much evidence waits on the lower
## floor - so the choice is a bet on how much risk you want to carry.
##
##   A / D, arrows   move across the cards      1 / 2 / 3   jump to a lead
##   ENTER / E / SPACE or a click   take the case
##
## The score line at the bottom is the session total of banked points.

const NIGHT := "res://scenes/night.tscn"
const INK := Color("14121c")
const PANEL := Color("1c1a2a")
const COLOR_BONE := Color("ded6c7")
const COLOR_SODIUM := Color("e8b366")
const COLOR_RED := Color("e85145")
const COLOR_FOG := Color("a79bb0")
const COLOR_SLATE := Color("4a4e69")
const CARD_W := 192.0
const CARD_H := 214.0
const CARD_Y := 86.0
const DANGER_COLORS := {"LOW": COLOR_BONE, "MEDIUM": COLOR_SODIUM, "HIGH": COLOR_RED}

signal lead_confirmed(index: int)

var selected := 1
var cards: Array[Control] = []
var _edges: Array[ColorRect] = []
var _rain: Array[Vector2] = []
var _rain_canvas: Control


func _ready() -> void:
	selected = Run.lead_idx
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0e0d15")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# rain on the office window
	_rain_canvas = Control.new()
	_rain_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_canvas.draw.connect(_draw_rain)
	add_child(_rain_canvas)
	for i in 60:
		_rain.append(Vector2(randf() * 640.0, randf() * 360.0))

	_text(Vector2(0, 10), 640, 20, "THE OFFICE", COLOR_BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(0, 36), 640, 10, "23:40 - RAIN ON THE GLASS - THREE FILES ON THE DESK", COLOR_FOG, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(0, 56), 640, 11, "WHICH CASE DO YOU TAKE TONIGHT?", COLOR_SODIUM, HORIZONTAL_ALIGNMENT_CENTER)

	for i in Run.LEADS.size():
		_build_card(i)

	var res: Dictionary = Run.last_result
	var recap := "NIGHTS %d   SESSION BANKED %d PTS" % [Run.nights_played, Run.session_banked]
	if not res.is_empty():
		recap += "   LAST: %s +%d" % [("EXTRACTED" if res["outcome"] == "extracted" else "CAUGHT"), res["banked"]]
	_text(Vector2(0, 318), 640, 10, recap, COLOR_FOG, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(0, 336), 640, 10, "A / D  choose      1 2 3  jump      ENTER  take the case", COLOR_BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_select(selected)


func _text(pos: Vector2, width: float, size: int, msg: String, color: Color, align: int, parent: Node = null) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, size + 8)
	l.text = msg
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l


func _build_card(i: int) -> void:
	var lead: Dictionary = Run.LEADS[i]
	var x := 20.0 + i * (CARD_W + 12.0)
	var edge := ColorRect.new()
	edge.position = Vector2(x - 2, CARD_Y - 2)
	edge.size = Vector2(CARD_W + 4, CARD_H + 4)
	edge.color = COLOR_SLATE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)
	_edges.append(edge)
	var card := ColorRect.new()
	card.position = Vector2(x, CARD_Y)
	card.size = Vector2(CARD_W, CARD_H)
	card.color = PANEL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(i))
	add_child(card)
	cards.append(card)

	_text(Vector2(8, 6), 40, 14, "%d" % (i + 1), COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(30, 9), CARD_W - 38, 9, lead["case_no"], COLOR_FOG, HORIZONTAL_ALIGNMENT_RIGHT, card)
	var title := _text(Vector2(8, 26), CARD_W - 16, 12, lead["title"], COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text(Vector2(8, 58), CARD_W - 16, 9, lead["district"], COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 70), CARD_W - 16, 9, lead["building"], COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT, card)
	var blurb := _text(Vector2(8, 88), CARD_W - 16, 9, lead["blurb"], COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size.y = 52
	var jobs := ""
	for t in lead["tasks"]:
		jobs += "- %s\n" % Run.TASKS[t]["label"]
	_text(Vector2(8, 142), CARD_W - 16, 9, jobs.strip_edges(), COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card)
	var d: String = lead["danger"]
	_text(Vector2(8, 184), CARD_W - 16, 9, "%d GUARDS   DANGER %s" % [lead["guards"], d], DANGER_COLORS[d], HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 196), CARD_W - 16, 9, "%d PTS  +%d BELOW" % [Run.lead_potential(i), Run.evidence_potential(i)], COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)


func _select(i: int) -> void:
	selected = wrapi(i, 0, Run.LEADS.size())
	for k in _edges.size():
		_edges[k].color = COLOR_SODIUM if k == selected else COLOR_SLATE
		cards[k].color = Color("26233a") if k == selected else PANEL


func _on_card_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseMotion:
		if selected != i:
			_select(i)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(i)
		confirm()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_1 or k == KEY_2 or k == KEY_3:
			_select(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		_select(selected - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		_select(selected + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		confirm()


func confirm(change_scene: bool = true) -> void:
	# Take the selected case: the night begins on floor 1.
	Run.choose_lead(selected)
	Run.begin_night()
	lead_confirmed.emit(selected)
	if change_scene and get_tree().current_scene == self:
		get_tree().change_scene_to_file(NIGHT)


func _process(delta: float) -> void:
	for i in _rain.size():
		var p := _rain[i]
		p.y += 340.0 * delta
		p.x -= 40.0 * delta
		if p.y > 360.0:
			p = Vector2(randf() * 680.0, -12.0)
		_rain[i] = p
	_rain_canvas.queue_redraw()


func _draw_rain() -> void:
	for p in _rain:
		_rain_canvas.draw_line(p, p + Vector2(-2, 9), Color(0.48, 0.44, 0.5, 0.22), 1.0)
