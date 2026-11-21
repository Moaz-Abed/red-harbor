extends Control
## Red Harbor - the PI's office: the board (roadmap 4.2, Hades-style).
##
## Every visit deals THREE DIFFERENT cases. They are not three labels on one
## night: each has its own jobs, its own district RULE (ON AIR, CURFEW,
## BLACKOUT, HIGH SECURITY, SEALED VAULT, QUIET HOURS) and its own REWARD
## (favors, or an extra boon). Take one, then pick a BOON - a run-long
## modifier - and the night starts. A boon's reward case gives you two picks.
##
##   A / D, arrows   move across the cards      1 / 2 / 3   jump to a card
##   ENTER / E / SPACE or a click   take it
##   Z / X / C       spend favors in the desk drawer (permanent upgrades)
##
## Stage 1 = the board, stage 2 = the boon pick. The score line shows the
## session total and your favors; the drawer upgrades persist between launches.

const NIGHT := "res://scenes/night.tscn"
const INK := Color("14121c")
const PANEL := Color("1c1a2a")
const COLOR_BONE := Color("ded6c7")
const COLOR_SODIUM := Color("e8b366")
const COLOR_RED := Color("e85145")
const COLOR_FOG := Color("a79bb0")
const COLOR_SLATE := Color("4a4e69")
const CARD_W := 192.0
const CARD_H := 222.0
const CARD_Y := 56.0
const DANGER_COLORS := {"LOW": COLOR_BONE, "MEDIUM": COLOR_SODIUM, "HIGH": COLOR_RED}
const RULE_COLORS := {
	"quiet": COLOR_BONE, "noise": COLOR_RED, "curfew": COLOR_SODIUM,
	"blackout": COLOR_FOG, "heavy": COLOR_RED, "sealed": COLOR_FOG,
}

signal lead_confirmed(index: int)
signal boon_picked(id: String)

var board_seed := -1              # >= 0 pins the dealt board (tests / QA)
var stage := "cases"              # "cases" | "boons"
var selected := 0
var cards: Array[Control] = []
var picks_left := 0
var boon_offers: Array[Dictionary] = []
var _edges: Array[ColorRect] = []
var _card_root: Control
var _title: Label
var _sub: Label
var _prompt: Label
var _shop: Array[Label] = []
var _foot: Label
var _rain: Array[Vector2] = []
var _rain_canvas: Control


func _ready() -> void:
	Run.roll_offers(board_seed)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0e0d15")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_rain_canvas = Control.new()
	_rain_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain_canvas.draw.connect(_draw_rain)
	add_child(_rain_canvas)
	for i in 60:
		_rain.append(Vector2(randf() * 640.0, randf() * 360.0))

	_title = _text(Vector2(0, 2), 640, 18, "THE OFFICE", COLOR_BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_sub = _text(Vector2(0, 24), 640, 10, "23:40 - RAIN ON THE GLASS - THREE FILES ON THE DESK", COLOR_FOG, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt = _text(Vector2(0, 38), 640, 11, "WHICH CASE DO YOU TAKE TONIGHT?", COLOR_SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
	_card_root = Control.new()
	_card_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_root)
	for i in 3:
		_shop.append(_text(Vector2(20 + i * 212.0, 284), 196, 9, "", COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, null, true, 28.0))
	_foot = _text(Vector2(0, 318), 640, 10, "", COLOR_BONE, HORIZONTAL_ALIGNMENT_CENTER, null, false, 30.0)
	_show_cases()
	_refresh_shop()


func _text(pos: Vector2, width: float, size: int, msg: String, color: Color, align: int, parent: Node = null, wrap: bool = false, height: float = -1.0) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_constant_override("line_spacing", -3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # BEFORE the text: else the label grows to one long line
	l.custom_minimum_size = Vector2(width, 0)
	l.text = msg
	(parent if parent != null else self).add_child(l)
	l.position = pos
	l.size = Vector2(width, height if height > 0.0 else size + 8.0)
	return l


func _clear_cards() -> void:
	for c in _card_root.get_children():
		c.queue_free()
	cards.clear()
	_edges.clear()


func _make_card(i: int) -> ColorRect:
	var x := 20.0 + i * (CARD_W + 12.0)
	var edge := ColorRect.new()
	edge.position = Vector2(x - 2, CARD_Y - 2)
	edge.size = Vector2(CARD_W + 4, CARD_H + 4)
	edge.color = COLOR_SLATE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_root.add_child(edge)
	_edges.append(edge)
	var card := ColorRect.new()
	card.position = Vector2(x, CARD_Y)
	card.size = Vector2(CARD_W, CARD_H)
	card.color = PANEL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_input.bind(i))
	_card_root.add_child(card)
	cards.append(card)
	return card


# --- stage 1: the board -------------------------------------------------------------

func _show_cases() -> void:
	stage = "cases"
	_clear_cards()
	_prompt.text = "WHICH CASE DO YOU TAKE TONIGHT?"
	_sub.text = "23:40 - RAIN ON THE GLASS - THREE FILES ON THE DESK"
	for i in 3:
		_build_case_card(i)
	var res: Dictionary = Run.last_result
	var recap := "NIGHTS %d   SESSION %d PTS   FAVORS %d" % [Run.nights_played, Run.session_banked, Run.favors]
	if not res.is_empty():
		recap += "   LAST: %s +%d" % [("EXTRACTED" if res["outcome"] == "extracted" else "CAUGHT"), res["banked"]]
	_foot.text = recap + "\nA / D choose    1 2 3 jump    ENTER take it    Z X C desk drawer"
	_select(selected)
	_refresh_shop()


func _build_case_card(i: int) -> void:
	var c: Dictionary = Run.offers[i]
	var card := _make_card(i)
	var rule: Dictionary = Run.RULES[c["rule"]]
	var w := CARD_W - 16.0
	_text(Vector2(8, 3), 40, 14, "%d" % (i + 1), COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(30, 6), CARD_W - 38, 9, c["case_no"], COLOR_FOG, HORIZONTAL_ALIGNMENT_RIGHT, card)
	_text(Vector2(8, 19), w, 12, c["title"], COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 38), w, 9, c["district"], COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 50), w, 9, c["building"], COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 65), w, 9, c["blurb"], COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card, true, 28.0)
	var jobs := ""
	for t in c["tasks"]:
		jobs += "- %s\n" % Run.TASKS[t]["label"]
	_text(Vector2(8, 96), w, 9, jobs.strip_edges(), COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card, false, 54.0)
	var rc: Color = RULE_COLORS[c["rule"]]
	_text(Vector2(8, 150), w, 10, "RULE: %s" % rule["name"], rc, HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 163), w, 9, rule["text"], COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT, card, true, 28.0)
	var d: String = c["danger"]
	_text(Vector2(8, 194), w, 9, "%d GUARDS   DANGER %s" % [c["guards"], d], DANGER_COLORS[d], HORIZONTAL_ALIGNMENT_LEFT, card)
	_text(Vector2(8, 206), w, 9, "%s    %d PTS%s" % [reward_text(c), Run.case_potential(c), (" +%d BELOW" % Run.evidence_potential(c)) if int(c["evidence"]) > 0 else ""], COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)


static func reward_text(c: Dictionary) -> String:
	var r: Dictionary = c["reward"]
	if r["kind"] == "favors":
		return "[+%d FAVORS]" % int(r["amount"])
	return "[2 BOONS]"


# --- stage 2: the boon pick ---------------------------------------------------------

func _show_boons() -> void:
	stage = "boons"
	_clear_cards()
	boon_offers = Run.offer_boons(3)
	var total := 2 if Run.lead()["reward"]["kind"] == "boon" else 1
	_prompt.text = "CHOOSE A BOON (%d of %d)" % [total - picks_left + 1, total]
	_sub.text = "%s - %s" % [Run.lead()["case_no"], Run.lead()["title"]]
	var w := CARD_W - 16.0
	for i in boon_offers.size():
		var b: Dictionary = boon_offers[i]
		var card := _make_card(i)
		_text(Vector2(8, 3), 40, 14, "%d" % (i + 1), COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card)
		_text(Vector2(30, 6), CARD_W - 38, 9, b["tag"], COLOR_FOG, HORIZONTAL_ALIGNMENT_RIGHT, card)
		_text(Vector2(8, 44), w, 15, b["name"], COLOR_BONE, HORIZONTAL_ALIGNMENT_LEFT, card, true, 40.0)
		_text(Vector2(8, 92), w, 11, b["text"], COLOR_SODIUM, HORIZONTAL_ALIGNMENT_LEFT, card, true, 90.0)
		_text(Vector2(8, 198), w, 9, "LASTS THE WHOLE NIGHT", COLOR_FOG, HORIZONTAL_ALIGNMENT_LEFT, card)
	var owned := ""
	for id in Run.boons:
		owned += Run.boon_by_id(id)["name"] + "   "
	_foot.text = ("YOU CARRY: %s\n" % owned if owned != "" else "") + "A / D choose    1 2 3 jump    ENTER take it"
	_foot.size.y = 26
	_foot.position.y = 322
	for l in _shop:
		l.visible = false
	selected = 0
	_select(0)


# --- selection + input ----------------------------------------------------------------

func _select(i: int) -> void:
	if cards.is_empty():
		return
	selected = wrapi(i, 0, cards.size())
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
		if stage == "cases" and (k == KEY_Z or k == KEY_X or k == KEY_C):
			var idx: int = {KEY_Z: 0, KEY_X: 1, KEY_C: 2}[k]
			buy(Run.SHOP[idx]["id"])
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
	# Stage 1: take the selected case and start a fresh night (boons reset).
	# Stage 2: take the selected boon; when none are left the night begins.
	if stage == "cases":
		Run.choose_case(selected)
		Run.begin_night()
		lead_confirmed.emit(selected)
		picks_left = 2 if Run.lead()["reward"]["kind"] == "boon" else 1
		_show_boons()
	else:
		pick_boon(selected, change_scene)


func pick_boon(i: int, change_scene: bool = true) -> void:
	if boon_offers.is_empty():
		return
	var b: Dictionary = boon_offers[clampi(i, 0, boon_offers.size() - 1)]
	Run.add_boon(b["id"])
	boon_picked.emit(b["id"])
	picks_left -= 1
	if picks_left > 0:
		_show_boons()
	elif change_scene and get_tree().current_scene == self:
		get_tree().change_scene_to_file(NIGHT)


# --- the desk drawer -----------------------------------------------------------------------

func buy(id: String) -> bool:
	var ok := Run.buy(id)
	_refresh_shop()
	return ok


func _refresh_shop() -> void:
	for i in Run.SHOP.size():
		var s: Dictionary = Run.SHOP[i]
		var lvl: int = int(Run.meta[s["id"]])
		var cost := Run.shop_cost(s["id"])
		var key: String = ["Z", "X", "C"][i]
		var line: String
		if cost < 0:
			line = "[%s] %s  MAX" % [key, s["name"]]
		else:
			line = "[%s] %s %s  %d FAVORS" % [key, s["name"], ["I", "II", "III"][lvl], cost]
		_shop[i].text = line + "\n" + s["text"]
		_shop[i].add_theme_color_override("font_color", COLOR_SODIUM if (cost >= 0 and Run.favors >= cost) else COLOR_FOG)
	if stage == "cases" and _foot != null:
		var res: Dictionary = Run.last_result
		var recap := "NIGHTS %d   SESSION %d PTS   FAVORS %d" % [Run.nights_played, Run.session_banked, Run.favors]
		if not res.is_empty():
			recap += "   LAST: %s +%d" % [("EXTRACTED" if res["outcome"] == "extracted" else "CAUGHT"), res["banked"]]
		_foot.text = recap + "\nA / D choose    1 2 3 jump    ENTER take it    Z X C desk drawer"
	for l in _shop:
		l.visible = stage == "cases"


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
