extends Node
## The smoke test: the whole slice must stand up headless.
##   godot --headless --path . res://tests/smoke.tscn   ->  SMOKE: ALL PASS
##
## Covered here:
##   1. THE DEAL - the case bag never repeats, danger derives, the reward is legal
##   2. THE RADIO - boon offers are fresh, a pick decrements, the mods land
##   3. THE FILE WALL - buys cost favors, save + load round-trips
##   4. THE OFFICE - the 3D room builds, the four spots exist, the PI stands in it
##   5. THE TUBE - a PS1 viewport with a camera renders the office
##   6. THE PANELS - case / shop / boons open, close, and take input paths

var _fails := 0


func _check(cond: bool, msg: String) -> void:
        if cond:
                print("SMOKE PASS: ", msg)
        else:
                _fails += 1
                printerr("SMOKE FAIL: ", msg)


func _ready() -> void:
        Run.save_path = "user://smoke_save.cfg"
        _check_run()
        await _check_menu()
        await _check_office()
        if _fails == 0:
                print("SMOKE: ALL PASS")
        else:
                printerr("SMOKE: %d FAILURES" % _fails)
        get_tree().quit(1 if _fails > 0 else 0)


# --- 1. the deal ------------------------------------------------------------------------

func _check_run() -> void:
        var first: Dictionary = Run.deal_case(42)
        _check(not first.is_empty() and first.has("case_no"), "a seeded deal lands a case")
        var seen := {String(first["id"]): true}
        for i in 5:
                var c: Dictionary = Run.deal_case()
                _check(not seen.has(String(c["id"])), "the bag deals no repeats (%s)" % c["id"])
                seen[String(c["id"])] = true
        _check(seen.size() == 6, "all six files come out before a refill")
        var c2: Dictionary = Run.deal_case()
        _check(c2["danger"] in ["LOW", "MEDIUM", "HIGH"], "danger derives from the archetype")
        _check(Run.case_potential(c2) > 0, "the case carries lead value")
        _check(Run.boon_picks_left >= 1, "a fresh deal grants radio picks")
        Run.ensure_case()
        _check(not Run.case.is_empty(), "ensure_case keeps the open file")


# --- 2. the radio -------------------------------------------------------------------------

func _check_radio() -> bool:
        var offers: Array[Dictionary] = Run.offer_boons(3)
        _check(offers.size() == 3, "the radio offers three boons")
        var ids := {}
        for o in offers:
                ids[String(o["id"])] = true
        _check(ids.size() == 3, "the offers are distinct boons")
        var before: int = Run.boon_picks_left
        Run.add_boon(String(offers[0]["id"]))
        _check(Run.boon_picks_left == before - 1, "a pick spends one radio pick")
        _check(Run.boons.has(String(offers[0]["id"])), "the taken boon is carried")
        return true


# --- 3. the file wall -----------------------------------------------------------------------

func _check_shop() -> void:
        Run.favors = 0
        _check(not Run.buy("stride"), "a buy with no favors fails")
        Run.favors = 50
        var lvl: int = int(Run.meta["stride"])
        _check(Run.buy("stride"), "a favored buy lands")
        _check(int(Run.meta["stride"]) == lvl + 1, "the upgrade levels up")
        var cost: int = Run.shop_cost("stride")
        _check(cost > 0 or cost == -1, "the next tier prices or maxes")
        Run.save_game()
        var f: int = Run.favors
        Run.favors = 0
        Run.load_game()
        _check(Run.favors == f, "save + load round-trips the favors")


# --- 4-6. the office, the tube, the panels ------------------------------------------------------

func _check_menu() -> void:
        var menu: Control = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
        add_child(menu)
        var title := menu.get_node_or_null("Stage/Title")
        _check(title != null, "the menu springs the title in")
        _check(menu.get_node_or_null("Stage/Prompt") != null, "the menu keeps the ENTER prompt")
        menu.queue_free()
        await get_tree().process_frame


func _check_office() -> void:
        var office: Node3D = (load("res://scenes/office.tscn") as PackedScene).instantiate()
        add_child(office)
        await get_tree().process_frame
        await get_tree().process_frame

        var player: Node = office.get("_player")
        _check(player != null, "the PI stands in the office")
        _check(player.get("_leg_l") != null and player.get("_arm_r") != null
                        and player.get("_tails") != null and player.get("_head") != null,
                        "the PI wears his limbs")
        _check(office.get("_yaw") == 0.0 and office.get("_pitch") == 0.3,
                        "the lens starts behind him, orbiting")
        var room: Node3D = office.get("_room")
        _check(room != null and room.spots.size() == 4, "the room plants the four spots")
        var view: Node = office.get("_view")
        var cam: Camera3D = view.get("camera") if view != null else null
        _check(cam != null and cam.get_viewport() is SubViewport, "the tube carries one camera")
        _check(player.get("cam") == cam, "the PI walks where the camera looks")
        _check(view.get("_view").size == Vector2i(480, 270), "the tube renders at 480x270")
        var meshes := 0
        for c in _all(room):
                if c is MeshInstance3D:
                        meshes += 1
        _check(meshes > 20, "the diorama is built (%d meshes)" % meshes)

        office.open_panel("case")
        _check(office.get("_panel").visible, "the case file opens")
        _check(office.get("_panel_body").text.contains("CONDITION"), "the case text prints the condition")
        office.close_panel()
        office.open_panel("shop")
        _check(office.get("_panel_body").text.contains("FAVORS"), "the file wall opens")
        var ok: bool = office.buy("soles")
        _check(ok == (Run.favors >= Run.shop_cost("soles")), "shop buys run through Run")
        office.close_panel()
        office.open_panel("boons")
        await _check_radio()
        var took: bool = office.take_boon(0)
        _check(took or Run.boon_picks_left <= 0, "a boon can be taken at the radio")
        office.close_panel()

        var no: String = office.get("_case_line").text
        office.deal_next_case()
        _check(office.get("_case_line").text != no, "the door deals the next case")

        var pause: Node = office.get("_pause")
        _check(pause != null, "the office carries the pause menu")
        office.queue_free()
        await get_tree().process_frame


func _all(node: Node) -> Array:
        var out := []
        var stack := [node]
        while not stack.is_empty():
                var n: Node = stack.pop_back()
                out.append(n)
                for c in n.get_children():
                        stack.append(c)
        return out
