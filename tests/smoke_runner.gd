extends Node
## The smoke test: the whole slice must stand up headless.
##   godot --headless --path . res://tests/smoke.tscn   ->  SMOKE: ALL PASS
##
## Covered here:
##   1. THE DEAL - the case bag never repeats, all six files deal before a refill
##   2. THE OFFICE - the 3D room builds, the door spot exists, the PI stands in it
##   3. THE DOOR - the door deals the next file
##   4. THE MENU - the title and the ENTER prompt exist
##   5. THE AMBIENT - the event clock runs without a scene

var _fails := 0


func _check(cond: bool, msg: String) -> void:
        if cond:
                print("SMOKE PASS: ", msg)
        else:
                _fails += 1
                printerr("SMOKE FAIL: ", msg)


func _ready() -> void:
        _check_run()
        await _check_office()
        await _check_menu()
        _check_ambient()
        if _fails == 0:
                print("SMOKE: ALL PASS")
        else:
                printerr("SMOKE: %d FAILURES" % _fails)
        get_tree().quit(1 if _fails > 0 else 0)


# --- 1. the deal ------------------------------------------------------------------------

func _check_run() -> void:
        var first: Dictionary = Run.deal_case(42)
        _check(not first.is_empty() and first.has("no"), "a seeded deal lands a case")
        var seen := {String(first["id"]): true}
        for i in 5:
                var c: Dictionary = Run.deal_case()
                _check(not seen.has(String(c["id"])), "the bag deals no repeats (%s)" % c["id"])
                seen[String(c["id"])] = true
        _check(seen.size() == 6, "all six files come out before a refill")
        var c2: Dictionary = Run.deal_case()
        _check(c2["danger"] in ["LOW", "MEDIUM", "HIGH"], "danger derives from the file")
        for field in ["no", "title", "district", "building", "blurb", "danger", "fee"]:
                _check(c2.has(field), "the case carries %s" % field)
        Run.ensure_case()
        _check(not Run.case.is_empty(), "ensure_case keeps the open file")


# --- 2-3. the office and the door -------------------------------------------------------

func _check_office() -> void:
        var office: Node3D = (load("res://scenes/office.tscn") as PackedScene).instantiate()
        office.set("deal_seed", 7)
        add_child(office)
        await get_tree().process_frame
        await get_tree().process_frame

        var player: Node = office.get("_player")
        _check(player != null, "the PI stands in the office")
        _check(player.get("_leg_l") != null and player.get("_fore_r") != null
                        and player.get("_tails") != null and player.get("_head") != null,
                        "the PI wears his limbs")
        _check(office.get("_yaw") == 0.0 and office.get("_pitch") == 0.22,
                        "the lens starts behind him, orbiting")
        var room: Node3D = office.get("_room")
        _check(room != null and room.spots.size() == 1,
                        "the room plants the one spot (the door)")
        var view: Node = office.get("_view")
        var cam: Camera3D = view.get("camera") if view != null else null
        _check(cam != null and cam.get_viewport() is SubViewport, "the tube carries one camera")
        _check(player.get("cam") == cam, "the PI walks where the camera looks")
        _check(view.get("_view").size == Vector2i(480, 270), "the tube renders at 480x270")
        var meshes := 0
        for c in _all(room):
                if c is MeshInstance3D:
                        meshes += 1
        _check(meshes > 30, "the diorama is built (%d meshes)" % meshes)

        var no: String = office.get("_case_line").text
        office.deal_next_case()
        _check(office.get("_case_line").text != no, "the door deals the next case")

        var pause: Node = office.get("_pause")
        _check(pause != null, "the office carries the pause menu")
        office.queue_free()
        await get_tree().process_frame


# --- 4. the menu -------------------------------------------------------------------------

func _check_menu() -> void:
        var menu: Control = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
        add_child(menu)
        var title := menu.get_node_or_null("Stage/Title")
        _check(title != null, "the menu springs the title in")
        _check(menu.get_node_or_null("Stage/Prompt") != null, "the menu keeps the ENTER prompt")
        menu.queue_free()
        await get_tree().process_frame


# --- 5. the ambient ----------------------------------------------------------------------

func _check_ambient() -> void:
        Ambient.end_office()
        _check(not Ambient.get("_office_active"), "end_office quiets the room")
        Ambient.begin_office()
        _check(Ambient.get("_office_active"), "begin_office arms the event clock")
        Ambient.end_office()


func _all(node: Node) -> Array:
        var out := []
        var stack := [node]
        while not stack.is_empty():
                var n: Node = stack.pop_back()
                out.append(n)
                for c in n.get_children():
                        stack.append(c)
        return out
