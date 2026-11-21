extends CanvasLayer
## The Esc overlay: RESUME / DEAL A NEW CASE / MAIN MENU.
## Runs while the tree is paused (process_mode ALWAYS).

const MENU := "res://scenes/menu.tscn"
const INK := Color("14121c")
const BONE := Color("ded6c7")
const SODIUM := Color("e8b366")
const FOG := Color("a79bb0")
const SLATE := Color("4a4e69")

const ITEMS := [
	{"label": "RESUME", "key": "ESC", "act": "resume"},
	{"label": "DEAL A NEW CASE - the bag shuffles", "key": "R", "act": "deal"},
	{"label": "MAIN MENU", "key": "M", "act": "menu"},
]

var _root: Control
var _labels: Array[Label] = []
var _selected := 0
var open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.05, 0.09, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var panel := ColorRect.new()
	panel.position = Vector2(190, 120)
	panel.size = Vector2(260, 130)
	panel.color = Color("1c1a2a")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)
	var edge := ColorRect.new()
	edge.position = panel.position - Vector2(2, 2)
	edge.size = panel.size + Vector2(4, 4)
	edge.color = SLATE
	edge.show_behind_parent = true
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(edge)

	_txt(Vector2(200, 128), 240, 13, "PAUSED - THE RAIN WAITS", SODIUM)
	for i in ITEMS.size():
		var l := _txt(Vector2(200, 154 + i * 24), 240, 10, "", BONE)
		_labels.append(l)
	_txt(Vector2(200, 232), 240, 8, "W/S choose    ENTER take    ESC resume", FOG)


func _txt(pos: Vector2, width: float, size: int, msg: String, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, size + 8)
	l.text = msg
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 2)
	_root.add_child(l)
	return l


func toggle() -> void:
	if open:
		close()
	else:
		open_menu()


func open_menu() -> void:
	if open:
		return
	open = true
	_selected = 0
	_root.visible = true
	get_tree().paused = true
	_refresh()


func close() -> void:
	if not open:
		return
	open = false
	_root.visible = false
	get_tree().paused = false


func _refresh() -> void:
	for i in _labels.size():
		var it: Dictionary = ITEMS[i]
		var sel := i == _selected
		_labels[i].text = "[%s] %s" % [it["key"], it["label"]]
		_labels[i].add_theme_color_override("font_color", SODIUM if sel else BONE)


func _unhandled_input(event: InputEvent) -> void:
	# The HOST scene opens this menu (it owns Esc while unpaused); here we only
	# react while open: Esc resumes, W/S + ENTER navigate, R/M are hotkeys.
	if not open:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
		_move(-1)
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
		_move(1)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_act(_selected)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		var map := {KEY_R: 1, KEY_M: 2}
		if map.has(k):
			get_viewport().set_input_as_handled()
			_act(map[k])


func _move(step: int) -> void:
	_selected = wrapi(_selected + step, 0, ITEMS.size())
	_refresh()


func _act(idx: int) -> void:
	var act: String = ITEMS[idx]["act"]
	match act:
		"resume":
			close()
		"deal":
			close()
			Run.deal_case()
			get_tree().reload_current_scene()
		"menu":
			close()
			get_tree().change_scene_to_file(MENU)
