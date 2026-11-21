extends Node3D
## The PI's office, the whole game for now: a walkable PS1-era diorama. Read
## the dealt case at the desk, buy permanent upgrades at the file wall, pick
## boons at the informant's radio, deal the next file at the neon door.

const PS1_VIEW := preload("res://scripts/comps/ps1_view.gd")
const ROOM := preload("res://scripts/office_room.gd")
const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const GRAIN := preload("res://shaders/grain.gdshader")

const SPAWN := Vector3(20.5, 0.1, 18.5)
const PIVOT := Vector3(0, 1.3, 0)       # the lens orbits the PI's chest
const CAM_DIST := 5.0
const CAM_PITCH_MIN := -0.45            # floor graze .. near the ceiling
const CAM_PITCH_MAX := 1.0
const CAM_MIN := Vector3(1.45, 0.55, 1.45)   # the lens stays in the office
const CAM_MAX := Vector3(38.55, 2.55, 20.55)
const LOOK_SENS := 0.0042
const REACH := 1.7

# legend cells carried over from the 2D room: the spots you can use.
const SPOTS := {
        "case": {"cell": Vector2i(16, 10), "label": "READ THE CASE FILE"},
        "drawer": {"cell": Vector2i(6, 6), "label": "THE FILE WALL - UPGRADES"},
        "radio": {"cell": Vector2i(33, 4), "label": "THE INFORMANT'S RADIO"},
        "door": {"cell": Vector2i(37, 11), "label": "DEAL THE NEXT CASE"},
}
const INK := Color("14121c")
const BONE := Color("ded6c7")
const SODIUM := Color("e8b366")
const RED := Color("e85145")
const FOG := Color("a79bb0")
const SLATE := Color("4a4e69")
const PANEL := Color("1c1a2a")

var deal_seed := -1              # >= 0 pins tonight's deal (tests / QA)
var boon_offers: Array[Dictionary] = []
var _player: Pi
var _pause: CanvasLayer
var _panel_kind := ""            # "" | case | shop | boons
var _selected := 0
var _hud: CanvasLayer
var _case_line: Label
var _prompt: Label
var _foot: Label
var _panel: Control
var _panel_title: Label
var _panel_body: Label
var _panel_hint: Label
var _card_edges: Array[ColorRect] = []
var _card_backs: Array[ColorRect] = []
var _card_bodies: Array[Label] = []
var _rain: Array[Vector2] = []
var _rain_canvas: Control
var _room: OfficeRoom
var _view: Ps1View
var _cam_pos: Vector3
var _yaw := 0.0
var _pitch := 0.3


func _ready() -> void:
        if deal_seed >= 0:
                Run.deal_case(deal_seed)
        else:
                Run.ensure_case()
        _build_world()
        _spawn_pi()
        _cam_pos = _cam_want()
        _view.camera.position = _cam_pos
        _view.camera.look_at(SPAWN + PIVOT)
        _build_hud()
        _pause = PAUSE_MENU.instantiate()
        add_child(_pause)
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_world() -> void:
        var env := WorldEnvironment.new()
        var e := Environment.new()
        e.background_mode = Environment.BG_COLOR
        e.background_color = Color(0.02, 0.02, 0.04)
        e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        e.ambient_light_sky_contribution = 0.0
        e.ambient_light_color = Color(0.36, 0.36, 0.40)
        e.ambient_light_energy = 14.0
        e.fog_enabled = true
        e.fog_light_color = Color(0.03, 0.03, 0.06)
        e.fog_density = 0.013
        env.environment = e
        var sun := DirectionalLight3D.new()
        sun.light_color = Color(0.72, 0.80, 1.0)
        sun.light_energy = 0.9
        sun.rotation_degrees = Vector3(-58, 165, 0)
        add_child(sun)
        var desk_lamp := OmniLight3D.new()
        desk_lamp.position = Vector3(18, 2.3, 8)
        desk_lamp.omni_range = 11.0
        desk_lamp.light_color = Color(1.0, 0.76, 0.46)
        desk_lamp.light_energy = 2.9
        add_child(desk_lamp)
        var neon := OmniLight3D.new()
        neon.position = Vector3(37.5, 1.6, 11)
        neon.omni_range = 8.0
        neon.light_color = Color(1.0, 0.45, 0.55)
        neon.light_energy = 1.7
        add_child(neon)
        var window_cold := OmniLight3D.new()
        window_cold.position = Vector3(20, 2.0, 3)
        window_cold.omni_range = 13.0
        window_cold.light_color = Color(0.55, 0.72, 0.95)
        window_cold.light_energy = 0.65
        add_child(window_cold)
        var fill := OmniLight3D.new()              # the overhead bulb, room center
        fill.position = Vector3(20, 2.8, 13)
        fill.omni_range = 16.0
        fill.light_color = Color(0.80, 0.78, 0.90)
        fill.light_energy = 3.2
        add_child(fill)
        var door_bulb := OmniLight3D.new()         # the second bulb, door half
        door_bulb.position = Vector3(20, 2.8, 18.5)
        door_bulb.omni_range = 9.0
        door_bulb.light_color = Color(0.85, 0.82, 0.95)
        door_bulb.light_energy = 2.4
        add_child(door_bulb)
        var east_bulb := OmniLight3D.new()         # the third bulb, east half
        east_bulb.position = Vector3(30, 2.8, 9)
        east_bulb.omni_range = 12.0
        east_bulb.light_color = Color(0.85, 0.82, 0.95)
        east_bulb.light_energy = 2.2
        add_child(east_bulb)
        for sx in [10.0, 26.0]:                    # the sconce pools on the north wall
                var sconce := OmniLight3D.new()
                sconce.position = Vector3(sx, 2.3, 2.0)
                sconce.omni_range = 5.5
                sconce.light_color = Color(1.0, 0.82, 0.55)
                sconce.light_energy = 1.0
                add_child(sconce)
        var lamp := OmniLight3D.new()              # the floor lamp by the chair
        lamp.position = Vector3(19.2, 2.1, 16.9)
        lamp.omni_range = 6.0
        lamp.light_color = Color(1.0, 0.80, 0.52)
        lamp.light_energy = 0.9
        add_child(lamp)
        var desk_pool := OmniLight3D.new()         # the desk lamp's own pool
        desk_pool.position = Vector3(15.5, 2.0, 7.9)
        desk_pool.omni_range = 4.0
        desk_pool.light_color = Color(1.0, 0.82, 0.55)
        desk_pool.light_energy = 0.7
        add_child(desk_pool)
        var bar := OmniLight3D.new()               # the bottle shelf, west wall
        bar.position = Vector3(1.8, 1.6, 13.0)
        bar.omni_range = 4.5
        bar.light_color = Color(0.9, 0.78, 0.55)
        bar.light_energy = 1.1
        add_child(bar)
        for wx in [8.0, 32.0]:                     # the cold pools at the outer panes
                var pane := OmniLight3D.new()
                pane.position = Vector3(wx, 1.8, 2.6)
                pane.omni_range = 6.0
                pane.light_color = Color(0.55, 0.72, 0.95)
                pane.light_energy = 0.6
                add_child(pane)
        # the three work pools: the reading table, the file wall, the radio -
        # hung high like little bench bulbs, never close enough to blow out
        # the tags or the props under vertex lighting
        var table_pool := OmniLight3D.new()
        table_pool.position = Vector3(16.85, 2.35, 10.5)
        table_pool.omni_range = 3.6
        table_pool.light_color = Color(1.0, 0.82, 0.55)
        table_pool.light_energy = 0.6
        add_child(table_pool)
        var file_pool := OmniLight3D.new()
        file_pool.position = Vector3(6.4, 2.35, 6.5)
        file_pool.omni_range = 3.6
        file_pool.light_color = Color(1.0, 0.82, 0.55)
        file_pool.light_energy = 0.6
        add_child(file_pool)
        var radio_pool := OmniLight3D.new()
        radio_pool.position = Vector3(33.5, 2.3, 3.9)
        radio_pool.omni_range = 3.2
        radio_pool.light_color = Color(0.95, 0.75, 0.5)
        radio_pool.light_energy = 0.5
        add_child(radio_pool)
        _view = PS1_VIEW.new()
        add_child(_view)
        _view.tube().add_child(env)                # the tube owns the environment
        _room = ROOM.new()
        add_child(_room)


func _spawn_pi() -> void:
        _player = Pi.new()
        add_child(_player)
        _player.position = SPAWN
        _player.rotation.y = PI               # he faces the room, lens behind
        _player.cam = _view.camera


func _process(delta: float) -> void:
        if is_instance_valid(_pause) and not _pause.open \
                        and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
                Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        if not _rain.is_empty() and is_instance_valid(_rain_canvas):
                for i in _rain.size():
                        var p := _rain[i]
                        p.y += 340.0 * delta
                        p.x -= 40.0 * delta
                        if p.y > 360.0:
                                p = Vector2(randf() * 680.0, -12.0)
                        _rain[i] = p
                _rain_canvas.queue_redraw()
        _room.pulse_markers(Time.get_ticks_msec() / 1000.0)
        _update_prompt()
        _follow_cam()


func _orbit_off() -> Vector3:
        # the lens rides a sphere around the PI: yaw spins the compass, pitch
        # lifts it from a floor graze up under the ceiling
        return Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))


func _in_room(p: Vector3) -> bool:
        return p.x > CAM_MIN.x and p.x < CAM_MAX.x and p.y > CAM_MIN.y \
                        and p.y < CAM_MAX.y and p.z > CAM_MIN.z and p.z < CAM_MAX.z


func _cam_want() -> Vector3:
        # the orbit pivot rides the PI's chest; the offset walks in until the
        # camera is inside the office, then a ray to the walls and props pulls
        # it further in, so the lens never ends up inside a solid box
        var pivot: Vector3 = _player.position + PIVOT
        var t := 1.0
        while t > 0.18 and not _in_room(pivot + _orbit_off() * (CAM_DIST * t)):
                t -= 0.05
        var want := pivot + _orbit_off() * (CAM_DIST * t)
        var space := get_world_3d().direct_space_state
        var q := PhysicsRayQueryParameters3D.create(
                        pivot, want, 1, [_player.get_rid()])
        var hit := space.intersect_ray(q)
        if hit:
                want = hit["position"] + (pivot - want).normalized() * 0.3
        return want


func _follow_cam() -> void:
        # A mouse-orbited third person: the lens swings all the way around the
        # PI and pulls in near the walls, and the drift quantizes so the frame
        # jitters the PS1 way. His body steps aside when the lens closes in.
        var want := _cam_want()
        want.x = clampf(want.x, CAM_MIN.x, CAM_MAX.x)
        want.y = clampf(want.y, CAM_MIN.y, CAM_MAX.y)
        want.z = clampf(want.z, CAM_MIN.z, CAM_MAX.z)
        _cam_pos = _cam_pos.lerp(want, 0.16)
        _view.camera.position = _cam_pos.snapped(Vector3(0.03, 0.03, 0.03))
        _view.camera.look_at(_player.position + PIVOT)
        _player.visible = _view.camera.position.distance_to(
                        _player.position + PIVOT) > 1.35


# --- the HUD ------------------------------------------------------------------------

func _build_hud() -> void:
        _hud = CanvasLayer.new()
        _hud.layer = 2
        add_child(_hud)
        var root := Control.new()
        root.set_anchors_preset(Control.PRESET_FULL_RECT)
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _hud.add_child(root)

        _rain_canvas = Control.new()
        _rain_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
        _rain_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _rain_canvas.draw.connect(_draw_rain)
        root.add_child(_rain_canvas)
        for i in 60:
                _rain.append(Vector2(randf() * 640.0, randf() * 360.0))

        # Permanent text lives ON the wall rows - the playfield stays clear.
        _lbl(root, Vector2(8, 6), 200, 9, "THE OFFICE", SODIUM, HORIZONTAL_ALIGNMENT_LEFT)
        _lbl(root, Vector2(400, 6), 232, 8, "23:41  -  RAIN ON THE GLASS", FOG, HORIZONTAL_ALIGNMENT_RIGHT)
        _case_line = _lbl(root, Vector2(8, 326), 300, 8, "", SODIUM, HORIZONTAL_ALIGNMENT_LEFT)
        _foot = _lbl(root, Vector2(300, 326), 332, 8, "", FOG, HORIZONTAL_ALIGNMENT_RIGHT)
        _refresh_case_line()
        _refresh_foot()
        _hint(root)
        _prompt = _lbl(root, Vector2(0, 288), 640, 11, "", SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
        _build_panel(root)
        _add_grain()


func _hint(root: Control) -> void:
        # The controls line shows once, then fades - never a permanent overlay.
        var h := _lbl(root, Vector2(160, 6), 320, 9, "WASD walk  -  E use  -  ESC pause", BONE, HORIZONTAL_ALIGNMENT_CENTER)
        var tw := h.create_tween()
        tw.tween_interval(7.0)
        tw.tween_property(h, "modulate:a", 0.0, 1.2)


func _add_grain() -> void:
        # animated film grain above the tube
        var layer := CanvasLayer.new()
        layer.layer = 60
        add_child(layer)
        var grain := ColorRect.new()
        grain.set_anchors_preset(Control.PRESET_FULL_RECT)
        grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mat := ShaderMaterial.new()
        mat.shader = GRAIN
        mat.set_shader_parameter("vignette", 0.0)
        grain.material = mat
        layer.add_child(grain)


func _lbl(parent: Control, pos: Vector2, width: float, size: int, msg: String, color: Color, align: int) -> Label:
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
        parent.add_child(l)
        return l


func _refresh_case_line() -> void:
        var c: Dictionary = Run.case
        _case_line.text = "%s  -  %s  -  %s" % [c["case_no"], c["title"], c["district"]]


func _refresh_foot() -> void:
        var txt := "FAVORS %d" % Run.favors
        for id in Run.boons:
                txt += "  -  %s" % Run.boon_by_id(id)["name"]
        _foot.text = txt


func _update_prompt() -> void:
        if _panel_kind != "":
                return
        var near := _near_spot()
        if near == "":
                _prompt.text = ""
        elif near == "radio" and Run.boon_picks_left <= 0:
                _prompt.text = "[E] the radio is quiet until the next file"
        else:
                _prompt.text = "[E] %s" % SPOTS[near]["label"]
        _prompt.add_theme_color_override("font_color", RED if near == "door" else SODIUM)


func _near_spot() -> String:
        if _player == null:
                return ""
        for key in SPOTS:
                if _player.position.distance_to(_room.spot(key)) <= REACH:
                        return key
        return ""


func _draw_rain() -> void:
        for p in _rain:
                _rain_canvas.draw_line(p, p + Vector2(-3, 14), Color(0.5, 0.56, 0.72, 0.22), 1.0)


# --- panels --------------------------------------------------------------------------

func _build_panel(root: Control) -> void:
        _panel = Control.new()
        _panel.set_anchors_preset(Control.PRESET_FULL_RECT)
        _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.visible = false
        root.add_child(_panel)
        var dim := ColorRect.new()
        dim.set_anchors_preset(Control.PRESET_FULL_RECT)
        dim.color = Color(0.06, 0.05, 0.09, 0.8)
        dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.add_child(dim)
        var back := ColorRect.new()
        back.position = Vector2(140, 42)
        back.size = Vector2(360, 276)
        back.color = PANEL
        back.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.add_child(back)
        var edge := ColorRect.new()
        edge.position = back.position - Vector2(2, 2)
        edge.size = back.size + Vector2(4, 4)
        edge.color = SLATE
        edge.show_behind_parent = true
        edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _panel.add_child(edge)
        _panel_title = _lbl(_panel, Vector2(152, 50), 336, 12, "", SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
        _panel_body = _lbl(_panel, Vector2(158, 72), 324, 10, "", BONE, HORIZONTAL_ALIGNMENT_LEFT)
        _panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _panel_body.size = Vector2(324, 196)
        _panel_hint = _lbl(_panel, Vector2(152, 300), 336, 8, "", FOG, HORIZONTAL_ALIGNMENT_CENTER)
        for i in 3:                    # boon cards, only shown on the radio panel
                var cx := 150.0 + i * 120.0
                var ce := ColorRect.new()
                ce.position = Vector2(cx, 78)
                ce.size = Vector2(112, 188)
                ce.color = SLATE
                ce.mouse_filter = Control.MOUSE_FILTER_IGNORE
                _panel.add_child(ce)
                _card_edges.append(ce)
                var card := ColorRect.new()
                card.position = Vector2(cx + 2, 80)
                card.size = Vector2(108, 184)
                card.color = PANEL
                card.mouse_filter = Control.MOUSE_FILTER_IGNORE
                _panel.add_child(card)
                _card_backs.append(card)
                var body := _lbl(_panel, Vector2(cx + 8, 88), 96, 9, "", BONE, HORIZONTAL_ALIGNMENT_LEFT)
                body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
                body.size = Vector2(96, 162)
                _card_bodies.append(body)


func open_panel(kind: String) -> void:
        _panel_kind = kind
        _selected = 0
        _panel.visible = true
        _player.set_physics_process(false)
        velocity_zero()
        _refresh_panel()


func velocity_zero() -> void:
        _player.velocity = Vector3.ZERO


func close_panel() -> void:
        _panel_kind = ""
        _panel.visible = false
        _player.set_physics_process(true)
        _refresh_foot()


func _refresh_panel() -> void:
        var cards := _panel_kind == "boons"
        for i in 3:
                _card_edges[i].visible = cards
                _card_backs[i].visible = cards
                _card_bodies[i].visible = cards
        _panel_body.visible = not cards
        match _panel_kind:
                "case":
                        _panel_title.text = "THE CASE FILE"
                        _panel_body.text = _case_text()
                        _panel_hint.text = "[E] put the file down"
                "shop":
                        _panel_title.text = "THE FILE WALL  -  FAVORS %d" % Run.favors
                        _panel_body.text = _shop_text()
                        _panel_hint.text = "[Z/X/C] buy   -   [E] close"
                "boons":
                        boon_offers = Run.offer_boons(3)
                        _panel_title.text = "THE RADIO  -  CHOOSE A BOON  (%d LEFT)" % Run.boon_picks_left
                        _panel_hint.text = "A / D choose  -  ENTER take it  -  ESC step away"
                        for i in boon_offers.size():
                                var b: Dictionary = boon_offers[i]
                                _card_bodies[i].text = "%s\n\n%s\n\n%s\n\nLASTS THIS CASE" % [b["name"], b["tag"], b["text"]]
                        _select(0)


func _select(i: int) -> void:
        _selected = wrapi(i, 0, maxi(boon_offers.size(), 1))
        for k in _card_edges.size():
                _card_edges[k].color = SODIUM if k == _selected else SLATE


func _case_text() -> String:
        var c: Dictionary = Run.case
        var rule: Dictionary = Run.RULES[c["rule"]]
        var tally := {}
        for t in c["tasks"]:
                tally[t] = int(tally.get(t, 0)) + 1
        var jobs := ""
        for t in tally:
                jobs += "- %s%s\n" % [Run.TASKS[t]["label"], " x%d" % int(tally[t]) if int(tally[t]) > 1 else ""]
        var carry := ""
        for id in Run.boons:
                carry += (" - " if carry != "" else "") + Run.boon_by_id(id)["name"]
        var carry_line := "YOU CARRY: %s\n\n" % carry if carry != "" else ""
        return "%s%s  -  %s\n%s  -  %s\n\n%s\n\n%s\n\nCONDITION: %s\n%s\n\nDANGER %s  -  %s" % [
                carry_line,
                c["case_no"], c["district"], c["title"], c["building"], c["blurb"],
                jobs.strip_edges(), rule["name"], rule["text"],
                c["danger"], _reward_text(c)]


static func _reward_text(c: Dictionary) -> String:
        var r: Dictionary = c["reward"]
        if r["kind"] == "favors":
                return "[+%d FAVORS]" % int(r["amount"])
        return "[2 BOONS]"


func _shop_text() -> String:
        var lines := ""
        for i in Run.SHOP.size():
                var s: Dictionary = Run.SHOP[i]
                var lvl: int = int(Run.meta[s["id"]])
                var cost := Run.shop_cost(s["id"])
                var key: String = ["Z", "X", "C"][i]
                if cost < 0:
                        lines += "[%s] %s  %s  MAX\n" % [key, s["name"], ["I", "II", "III"][lvl]]
                else:
                        lines += "[%s] %s  %s  %d FAVORS\n" % [key, s["name"], ["I", "II", "III"][lvl], cost]
                lines += s["text"] + "\n\n"
        return lines.strip_edges()


func take_boon(i: int) -> bool:
        if _panel_kind != "boons" or boon_offers.is_empty() or Run.boon_picks_left <= 0:
                return false
        var b: Dictionary = boon_offers[clampi(i, 0, boon_offers.size() - 1)]
        Run.add_boon(b["id"])
        if Run.boon_picks_left > 0:
                _refresh_panel()
        else:
                close_panel()
        _refresh_foot()
        return true


func buy(id: String) -> bool:
        var ok := Run.buy(id)
        _refresh_panel()
        _refresh_foot()
        return ok


func deal_next_case() -> bool:
        # The neon door: close this file, deal the next one from the bag.
        Run.deal_case()
        _refresh_case_line()
        _refresh_foot()
        return true


# --- input ---------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
        if _panel_kind == "" and _player != null and Input.is_action_just_pressed("interact"):
                var near := _near_spot()
                match near:
                        "case":
                                open_panel("case")
                        "shop", "drawer":
                                open_panel("shop")
                        "radio":
                                if Run.boon_picks_left > 0:
                                        open_panel("boons")
                        "door":
                                deal_next_case()


func _unhandled_input(event: InputEvent) -> void:
        if event is InputEventMouseMotion:
                # the free look: yaw spins the compass, pitch lifts the lens;
                # frozen while a panel holds the room
                if _panel_kind == "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
                        _yaw = wrapf(_yaw - event.relative.x * LOOK_SENS, -PI, PI)
                        _pitch = clampf(_pitch + event.relative.y * LOOK_SENS,
                                        CAM_PITCH_MIN, CAM_PITCH_MAX)
                return
        # Esc: close the open panel, else hand it to the pause menu.
        if event.is_action_pressed("pause"):
                get_viewport().set_input_as_handled()
                if _panel_kind != "":
                        close_panel()
                else:
                        _pause.open_menu()
                        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
                return
        if _panel_kind == "":
                return
        if event.is_action_pressed("interact"):
                get_viewport().set_input_as_handled()
                if _panel_kind == "boons" and _boon_takeable():
                        take_boon(_selected)
                else:
                        close_panel()
                return
        if _panel_kind == "boons":
                if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
                        get_viewport().set_input_as_handled()
                        _select(_selected - 1)
                elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
                        get_viewport().set_input_as_handled()
                        _select(_selected + 1)
                elif event.is_action_pressed("ui_accept"):
                        get_viewport().set_input_as_handled()
                        take_boon(_selected)
                elif event is InputEventKey and event.pressed and not event.echo:
                        var k := (event as InputEventKey).physical_keycode
                        if k == KEY_1 or k == KEY_2 or k == KEY_3:
                                get_viewport().set_input_as_handled()
                                _select(k - KEY_1)
                                take_boon(_selected)
        elif _panel_kind == "shop":
                if event is InputEventKey and event.pressed and not event.echo:
                        var k := (event as InputEventKey).physical_keycode
                        var map := {KEY_Z: "stride", KEY_X: "soles", KEY_C: "pockets"}
                        if map.has(k):
                                get_viewport().set_input_as_handled()
                                buy(map[k])


func _boon_takeable() -> bool:
        return Run.boon_picks_left > 0 and not boon_offers.is_empty()
