extends Node2D
## The PI's office: the walkable prep room (Hades' House of Hades).
## Gotham-tuned: cold dusk light, dark wood, rain on the glass. Read tonight's
## dealt case at the desk, buy permanent upgrades at the file wall, pick boons
## at the informant's radio, then walk out the neon door.

signal night_started

const TILE := 16
const MAP_OFFSET := Vector2(0, 4)
const ATLAS := preload("res://assets/tiles/office_tiles.png")
const GRAIN := preload("res://shaders/grain.gdshader")
const DUSK := Color(0.84, 0.88, 1.02)   # cold Gotham cast over the room
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const NIGHT := "res://scenes/night.tscn"

# legend: # wall · w window · , worn floor · . planks · r rug · d desk ·
# k cabinet · c crate · i radio · ~ neon door · p papers · m mat · s scuff
const MAP: Array[String] = [
        "#######ww##########ww##########ww#######",
        "#,,..................................,,#",
        "#......................................#",
        "#..kk............................ic....#",
        "#..kk..................................#",
        "#..kk..................................#",
        "#..kk..........dddd....................#",
        "#..kk..........dddd....................#",
        "#..kk..........dddd.......s............#",
        "#......................................#",
        "#..............p..p...................~#",
        "#...............p.....................~#",
        "#.....................................m#",
        "#...................rrrrrr.............#",
        "#...................rrrrrr.............#",
        "#...................rrrrrr.............#",
        "#.........s.........rrrrrr.............#",
        "#..ccc.................................#",
        "#................................s.....#",
        "#,,..................................,,#",
        "#,,..................................,,#",
        "########################################",
]

const SPOTS := {
        "case": {"cell": Vector2i(16, 10), "label": "READ THE CASE FILE"},
        "drawer": {"cell": Vector2i(6, 6), "label": "THE FILE WALL - UPGRADES"},
        "radio": {"cell": Vector2i(33, 4), "label": "THE INFORMANT'S RADIO"},
        "door": {"cell": Vector2i(37, 11), "label": "WORK THE NIGHT"},
}
const REACH := 20.0
const INK := Color("14121c")
const BONE := Color("ded6c7")
const SODIUM := Color("e8b366")
const RED := Color("e85145")
const FOG := Color("a79bb0")
const SLATE := Color("4a4e69")
const PANEL := Color("1c1a2a")
const DANGER_COLORS := {"LOW": BONE, "MEDIUM": SODIUM, "HIGH": RED}

var deal_seed := -1              # >= 0 pins tonight's deal (tests / QA)
var boon_offers: Array[Dictionary] = []
var _player: CharacterBody2D
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


func _ready() -> void:
        if deal_seed >= 0:
                Run.deal_night(deal_seed)
        else:
                Run.ensure_case()
        var dusk := CanvasModulate.new()
        dusk.color = DUSK
        add_child(dusk)
        _paint_tiles()
        _spawn_player()
        _build_hud()
        _pause = PAUSE_MENU.instantiate()
        add_child(_pause)


func cell_world(cell: Vector2i) -> Vector2:
        return Vector2(cell.x * TILE + 8, cell.y * TILE + 8) + MAP_OFFSET


func _spawn_player() -> void:
        _player = PLAYER_SCENE.instantiate()
        add_child(_player)
        _player.global_position = cell_world(Vector2i(20, 18))


# --- the room -----------------------------------------------------------------------

func _paint_tiles() -> void:
        var ts := TileSet.new()
        ts.tile_size = Vector2i(TILE, TILE)
        ts.add_physics_layer()
        ts.set_physics_layer_collision_layer(0, 2)
        ts.set_physics_layer_collision_mask(0, 0)
        var src := TileSetAtlasSource.new()
        src.texture = ATLAS
        src.texture_region_size = Vector2i(TILE, TILE)
        for t in 16:
                src.create_tile(Vector2i(t, 0))
        ts.add_source(src, 0)          # bind BEFORE physics (the phase-through bug)
        # wall face/top, neon door, desk, cabinet, crate, window, radio block
        for t in [3, 4, 5, 6, 7, 9, 10, 11]:
                var td := src.get_tile_data(Vector2i(t, 0), 0)
                td.add_collision_polygon(0)
                td.set_collision_polygon_points(0, 0, PackedVector2Array([
                        Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
                ]))
                assert(td.get_collision_polygons_count(0) == 1)
        var layer := TileMapLayer.new()
        layer.tile_set = ts
        layer.position = MAP_OFFSET
        add_child(layer)
        var tile_of := {
                "#": 3, "w": 10, ",": 2, ".": 0, "r": 8, "d": 6, "k": 7, "c": 9,
                "i": 11, "~": 5, "p": 13, "m": 14, "s": 12,
        }
        for y in MAP.size():
                for x in MAP[y].length():
                        var ch := MAP[y][x]
                        var t: int = tile_of.get(ch, 0)
                        if ch == "." and (x * 7 + y * 13) % 5 == 0:
                                t = 1              # plank shade variant
                        if ch == "d" and x == 16 and y == 7:
                                t = 15             # the one desk tile with the case file
                        if ch == "#" and y > 0 and MAP[y - 1][x] == "#":
                                t = 4              # covered wall gets the plain face
                        layer.set_cell(Vector2i(x, y), 0, Vector2i(t, 0))


func _draw() -> void:
        # A sodium cross marks every thing you can use.
        for key in SPOTS:
                var p: Vector2 = cell_world(SPOTS[key]["cell"])
                draw_rect(Rect2(p - Vector2(6, 2), Vector2(12, 4)), Color(0.09, 0.08, 0.12))
                draw_rect(Rect2(p - Vector2(2, 6), Vector2(4, 12)), Color(0.09, 0.08, 0.12))
                draw_rect(Rect2(p - Vector2(5, 1), Vector2(10, 2)), SODIUM)
                draw_rect(Rect2(p - Vector2(1, 5), Vector2(2, 10)), SODIUM)


# --- the HUD ------------------------------------------------------------------------

func _build_hud() -> void:
        _hud = CanvasLayer.new()
        _hud.layer = 2
        add_child(_hud)
        _add_grain()
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
        # Header: a sign on the top wall. Footer: the case on the baseboard.
        _lbl(root, Vector2(8, 6), 200, 9, "THE OFFICE", SODIUM, HORIZONTAL_ALIGNMENT_LEFT)
        _lbl(root, Vector2(400, 6), 232, 8, "23:41  ·  RAIN ON THE GLASS", FOG, HORIZONTAL_ALIGNMENT_RIGHT)
        _case_line = _lbl(root, Vector2(8, 326), 300, 8, "", SODIUM, HORIZONTAL_ALIGNMENT_LEFT)
        _foot = _lbl(root, Vector2(300, 326), 332, 8, "", FOG, HORIZONTAL_ALIGNMENT_RIGHT)
        _refresh_case_line()
        _refresh_foot()
        _hint(root)
        _prompt = _lbl(root, Vector2(0, 288), 640, 11, "", SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
        _build_panel(root)


func _hint(root: Control) -> void:
        # The controls line shows once, then fades - never a permanent overlay.
        var h := _lbl(root, Vector2(0, 296), 640, 9, "WASD walk  ·  E use  ·  ESC pause", BONE, HORIZONTAL_ALIGNMENT_CENTER)
        var tw := h.create_tween()
        tw.tween_interval(7.0)
        tw.tween_property(h, "modulate:a", 0.0, 1.2)


func _add_grain() -> void:
        # slight film grain + a Gotham vignette over the whole room
        var layer := CanvasLayer.new()
        layer.layer = 60
        add_child(layer)
        var grain := ColorRect.new()
        grain.set_anchors_preset(Control.PRESET_FULL_RECT)
        grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var mat := ShaderMaterial.new()
        mat.shader = GRAIN
        mat.set_shader_parameter("vignette", 0.55)
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
        _case_line.text = "%s  ·  %s  ·  %s" % [c["case_no"], c["title"], c["district"]]


func _refresh_foot() -> void:
        var txt := "NIGHTS %d  ·  %d PTS  ·  FAVORS %d" % [Run.nights_played, Run.session_banked, Run.favors]
        if not Run.last_result.is_empty():
                txt += "  ·  LAST +%d" % int(Run.last_result["banked"])
        for id in Run.boons:
                txt += "  ·  %s" % Run.boon_by_id(id)["name"]
        _foot.text = txt


func _process(delta: float) -> void:
        for i in _rain.size():
                var p := _rain[i]
                p.y += 340.0 * delta
                p.x -= 40.0 * delta
                if p.y > 360.0:
                        p = Vector2(randf() * 680.0, -12.0)
                _rain[i] = p
        _rain_canvas.queue_redraw()
        _update_prompt()


func _update_prompt() -> void:
        if _panel_kind != "":
                return
        var near := _near_spot()
        if near == "":
                _prompt.text = ""
        elif near == "radio" and Run.boon_picks_left <= 0:
                _prompt.text = "[E] the radio is quiet until tomorrow"
        elif near == "door":
                _prompt.text = "[E] %s  -  %s" % [SPOTS["door"]["label"], Run.case["case_no"]]
        else:
                _prompt.text = "[E] %s" % SPOTS[near]["label"]
        _prompt.add_theme_color_override("font_color", RED if near == "door" else SODIUM)


func _near_spot() -> String:
        if _player == null or _player.is_dead():
                return ""
        for key in SPOTS:
                if _player.global_position.distance_to(cell_world(SPOTS[key]["cell"])) <= REACH:
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
        _player.velocity = Vector2.ZERO
        _refresh_panel()


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
                        _panel_title.text = "TONIGHT'S CASE"
                        _panel_body.text = _case_text()
                        _panel_hint.text = "[E] put the file down"
                "shop":
                        _panel_title.text = "THE FILE WALL  -  FAVORS %d" % Run.favors
                        _panel_body.text = _shop_text()
                        _panel_hint.text = "[Z/X/C] buy   ·   [E] close"
                "boons":
                        boon_offers = Run.offer_boons(3)
                        _panel_title.text = "THE RADIO  -  CHOOSE A BOON  (%d LEFT)" % Run.boon_picks_left
                        _panel_hint.text = "A / D choose  ·  ENTER take it  ·  ESC step away"
                        for i in boon_offers.size():
                                var b: Dictionary = boon_offers[i]
                                _card_bodies[i].text = "%s\n\n%s\n\n%s\n\nLASTS THE WHOLE NIGHT" % [b["name"], b["tag"], b["text"]]
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
        var below := ("+%d PTS BELOW" % Run.evidence_potential(c)) if int(c["evidence"]) > 0 else "NO LOWER FLOOR"
        var carry := ""
        for id in Run.boons:
                carry += (" · " if carry != "" else "") + Run.boon_by_id(id)["name"]
        var carry_line := "YOU CARRY: %s\n\n" % carry if carry != "" else ""
        return "%s%s  ·  %s\n%s  ·  %s\n\n%s\n\n%s\n\nRULE: %s\n%s\n\n%d GUARDS  ·  DANGER %s\n%d PTS ON THE FLOOR  ·  %s  ·  %s" % [
                        carry_line,
                        c["case_no"], c["district"], c["title"], c["building"], c["blurb"],
                        jobs.strip_edges(), rule["name"], rule["text"],
                        c["guards"], c["danger"], Run.case_potential(c), below, _reward_text(c)]


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
                                start_night()


func _unhandled_input(event: InputEvent) -> void:
        # Esc: close the open panel, else hand it to the pause menu.
        if event.is_action_pressed("pause"):
                get_viewport().set_input_as_handled()
                if _panel_kind != "":
                        close_panel()
                else:
                        _pause.open_menu()
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


func start_night(change_scene: bool = true) -> bool:
        if Run.case.is_empty() or Run.active:
                return false
        Run.begin_night()             # carries the boons picked at the radio
        night_started.emit()
        if change_scene and get_tree().current_scene == self:
                get_tree().change_scene_to_file(NIGHT)
        return true
