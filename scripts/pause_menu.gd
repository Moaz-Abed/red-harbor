extends CanvasLayer
## The Esc overlay: RESUME / RESTART NIGHT / ABANDON TO OFFICE / MAIN MENU.
## Runs while the tree is paused (process_mode ALWAYS).

const OFFICE := "res://scenes/office.tscn"
const MENU := "res://scenes/menu.tscn"
const INK := Color("14121c")
const BONE := Color("ded6c7")
const SODIUM := Color("e8b366")
const FOG := Color("a79bb0")
const SLATE := Color("4a4e69")

const ITEMS := [
        {"label": "RESUME", "key": "ESC", "night": false},
        {"label": "RESTART NIGHT - same case, new building", "key": "R", "night": true},
        {"label": "ABANDON - keep the insurance share, go home", "key": "O", "night": true},
        {"label": "MAIN MENU", "key": "M", "night": false},
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
        panel.position = Vector2(190, 96)
        panel.size = Vector2(260, 176)
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

        _txt(Vector2(200, 104), 240, 13, "PAUSED - THE RAIN WAITS", SODIUM)
        for i in ITEMS.size():
                var l := _txt(Vector2(200, 130 + i * 30), 240, 10, "", BONE)
                _labels.append(l)
        _txt(Vector2(200, 254), 240, 8, "W/S choose    ENTER take    ESC resume", FOG)


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


func _shown() -> Array[int]:
        # Item indices visible in this context (night items only mid-night).
        var out: Array[int] = []
        for i in ITEMS.size():
                if not ITEMS[i]["night"] or Run.active:
                        out.append(i)
        return out


func toggle() -> void:
        if open:
                close()
        else:
                open_menu()


func open_menu() -> void:
        if open or not _can_pause():
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


func _can_pause() -> bool:
        # Not over the debrief: once the night ended, ENTER/R own the keyboard.
        var host := get_parent()
        return host == null or Run.active or not (host is Node2D and host.get("plan") != null)


func _refresh() -> void:
        var shown := _shown()
        for i in _labels.size():
                if shown.has(i):
                        var it: Dictionary = ITEMS[i]
                        var sel := i == _selected
                        _labels[i].text = "[%s] %s" % [it["key"], it["label"]]
                        _labels[i].add_theme_color_override("font_color", SODIUM if sel else BONE)
                        _labels[i].visible = true
                else:
                        _labels[i].visible = false


func _unhandled_input(event: InputEvent) -> void:
        # The HOST scene opens this menu (it owns Esc while unpaused); here we only
        # react while open: Esc resumes, W/S + ENTER navigate, R/O/M are hotkeys.
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
                var map := {KEY_R: 1, KEY_O: 2, KEY_M: 3}
                if map.has(k) and _shown().has(map[k]):
                        get_viewport().set_input_as_handled()
                        _act(map[k])


func _move(step: int) -> void:
        var shown := _shown()
        if shown.is_empty():
                return
        var pos := shown.find(_selected)
        pos = wrapi(pos + step, 0, shown.size())
        _selected = shown[pos]
        _refresh()


func _act(idx: int) -> void:
        if not _shown().has(idx):
                return
        match idx:
                0:
                        close()
                1:
                        close()
                        Run.on_restart()               # forfeit this attempt, same case re-dealt
                        get_tree().reload_current_scene()
                2:
                        close()
                        Run.finish("caught")           # the case goes cold; keep the insurance share
                        get_tree().change_scene_to_file(OFFICE)
                3:
                        close()
                        get_tree().change_scene_to_file(MENU)
