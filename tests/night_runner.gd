extends Node
## Headless NIGHT LOOP test (roadmap 4.2, Hades-style run).
##
##   godot --headless --path . res://tests/night_test.tscn
##
## 1. RUN STATE   tiers, the alarm ladder, insurance, the style chain.
## 2. THE DEAL    one case a night, dealt from a bag (all six before a
##                repeat); rules bend the numbers; boons and favors stack.
## 3. BUILDINGS   162 seeded deals: 9-12 rooms, one job per room, everything
##                reachable WITHOUT squeezing, tight spots marked and solid
##                for guards.
## 4. THE NIGHT   the scene end to end: jobs, ON AIR noise, CURFEW bells,
##                BLACKOUT, SEALED VAULT, lockdown, leave / descend / caught,
##                LUCKY COIN.
## 5. TIGHT SPOTS the PI crawls through a 1-tile slot (and a standing body
##                cannot); guards have a real collider and never enter one.
## 6. THE OFFICE  the walkable prep room: case file, file wall, radio, door.
## 7. MENU+PAUSE  the title screen boots; ESC pauses and resumes.
##
## Exits 0 with "NIGHT: ALL PASS", else 1 with the FAIL list.

const NIGHT := preload("res://scenes/night.tscn")
const OFFICE_SCENE := preload("res://scenes/office.tscn")
const MENU := preload("res://scenes/menu.tscn")
const BUILDER := preload("res://scripts/building_builder.gd")

var _fails: Array[String] = []


func _ready() -> void:
        Run.save_path = "user://night_test_save.cfg"   # never touch the real save
        Run.favors = 0
        _test_run_state()
        _test_the_deal()
        _test_boons_and_shop()
        _test_buildings()
        await _test_night()
        await _test_rules_in_the_night()
        await _test_tight_spots()
        await _test_guard_body()
        await _test_menu_pause()
        await _test_office()
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://night_test_save.cfg"))
        _finish()


func _check(ok: bool, what: String) -> void:
        if ok:
                print("NIGHT PASS: ", what)
        else:
                print("NIGHT FAIL: ", what)
                _fails.append(what)


func _frames(n: int) -> void:
        for i in n:
                await get_tree().physics_frame


func _press(a: String) -> void:
        # action_press only updates polling state headless; parse_input_event
        # actually dispatches to _unhandled_input (what the menus listen to).
        var ev := InputEventAction.new()
        ev.action = a
        ev.pressed = true
        Input.parse_input_event(ev)


func _release_action(a: String) -> void:
        var ev := InputEventAction.new()
        ev.action = a
        ev.pressed = false
        Input.parse_input_event(ev)


func _arch(id: String) -> Dictionary:
        for a in Run.ARCHETYPES:
                if a["id"] == id:
                        var c: Dictionary = a.duplicate(true)
                        c["case_no"] = "CASE 100"
                        c["danger"] = Run.danger_of(c)
                        return c
        return {}


func _take(id: String) -> void:
        Run.case = _arch(id)
        Run.need_new_case = false
        Run.begin_night()


# --- 1. run state ------------------------------------------------------------------------

func _test_run_state() -> void:
        _take("ministry")
        _check(Run.unbanked_points() == 0 and Run.alarm == 0, "a night starts empty and CALM")
        Run.add_intel(Run.Tier.GOSSIP)
        Run.add_intel(Run.Tier.LEADS)
        Run.add_intel(Run.Tier.EVIDENCE)
        _check(Run.unbanked_points() == 1 + 3 + 8, "tiers score 1 / 3 / 8 (got %d)" % Run.unbanked_points())
        _check(Run.register_spot() and Run.alarm == 1, "first spotting climbs the ladder to ALERTED")
        _check(not Run.register_spot() and Run.alarm == 1, "a second spotting inside the 4 s cooldown does not")
        Run._spot_cd = 0.0
        Run.register_spot()
        Run._spot_cd = 0.0
        Run.register_spot()
        _check(Run.alarm == 3 and Run.lockdown(), "three sightings = LOCKDOWN")
        _check(Run.extra_guards() == 2 and Run.patrol_mult() > 1.4 and Run.range_mult() > 1.25, "LOCKDOWN: 2 extra guards, faster patrols, longer beams")
        var r := Run.finish("caught")
        _check(r["insurance"] == floori(12 * Run.INSURANCE) and r["banked"] == r["insurance"], "caught keeps only the insurance share (%d of 12)" % r["insurance"])
        _check(Run.patrol_mult() == 1.0 and not Run.lockdown(), "after the night every multiplier reads 1.0")
        _take("ministry")
        Run.add_intel(Run.Tier.LEADS)
        var before_session: int = Run.session_banked
        var r2 := Run.finish("extracted")
        _check(r2["banked"] == 3 and Run.session_banked == before_session + 3, "extraction banks everything carried")
        _check(Run.finish("caught") == r2, "a night ends exactly once")
        # style chain
        _take("ministry")
        Run.note_style(100)
        Run.note_style(100)
        _check(Run.chain == 2 and Run.style == 100 * 1 + 100 * 2, "a second link inside the window doubles its score (style %d)" % Run.style)
        Run._chain_t = 0.01
        Run._process(0.05)
        _check(Run.chain == 0, "the chain breaks when the window closes")
        Run.finish("caught")


# --- 2. the deal and the rules ---------------------------------------------------------------

func _test_the_deal() -> void:
        # the bag: all six files before a repeat, never the same one twice in a row
        Run._bag = []
        Run._last_id = ""
        var ids: Array[String] = []
        for i in 8:
                Run.deal_night()
                ids.append(String(Run.case["id"]))
        var first_six := {}
        for i in 6:
                first_six[ids[i]] = true
        _check(first_six.size() == 6, "one pass deals all six case files (%d distinct)" % first_six.size())
        _check(ids[6] != ids[5] and ids[7] != ids[6], "a refill never repeats the case you just played")
        _check(not Run.need_new_case and Run.boon_picks_left >= 1, "a deal arms the radio picks")
        Run._last_id = ""
        Run.deal_night(7)
        var a: String = String(Run.case["id"])
        var no: String = String(Run.case["case_no"])
        Run._last_id = ""
        Run.deal_night(7)
        _check(String(Run.case["id"]) == a and String(Run.case["case_no"]) == no, "the same deal seed deals the same case")
        var rules := {}
        var rewards := {}
        var reach := 0
        for c in Run.ARCHETYPES:
                rules[c["rule"]] = true
                rewards[c["reward"]["kind"]] = true
                reach += (c["tasks"] as Array).size()
        _check(rules.size() == 6, "the pool carries all six district rules")
        _check(rewards.has("favors") and rewards.has("boon"), "the pool offers favors and boon rewards")
        _check(reach >= 6 * 3, "every case file carries at least three jobs")
        # rules bend the numbers
        _take("customs")
        Run.add_intel(Run.Tier.LEADS)
        _check(Run.unbanked_points() == 6, "CURFEW pays double (3 -> %d)" % Run.unbanked_points())
        Run.finish("caught")
        _take("archive")
        Run.add_intel(Run.Tier.LEADS)
        Run.add_intel(Run.Tier.LEADS)
        _check(Run.unbanked_points() == 9 and Run.guard_bonus() == 1, "HIGH SECURITY: x1.5 intel and +1 guard")
        Run.finish("caught")
        _take("telegraph")
        _check(Run.range_mult() < 0.7 and Run.patrol_mult() > 1.2, "BLACKOUT: short beams, faster patrols")
        Run.finish("caught")
        _take("deaddrop")
        _check(not Run.can_descend() and _arch("deaddrop")["tasks"].has("evidence"), "SEALED VAULT: no lower floor, evidence on floor 1")
        Run.finish("caught")
        _take("radio")
        var heard := [0]
        var cb := func(_p: Vector2, _r: float) -> void: heard[0] += 1
        Run.noise_made.connect(cb)
        Run.make_noise(Vector2.ZERO, 100.0)
        _check(heard[0] == 1, "ON AIR: noise is broadcast")
        Run.finish("caught")
        _take("ministry")
        Run.make_noise(Vector2.ZERO, 100.0)
        _check(heard[0] == 1, "other rules are silent")
        Run.noise_made.disconnect(cb)
        Run.finish("caught")


# --- boons + the desk drawer -----------------------------------------------------------------

func _test_boons_and_shop() -> void:
        _take("ministry")
        _check(Run.mult("dash_time_mult") == 1.0 and Run.add("takedown_range_add") == 0.0, "no boons: every modifier is neutral")
        Run.add_boon("long_coat")
        Run.add_boon("soft_soles")
        Run.add_boon("long_coat")
        _check(Run.boons.size() == 2, "a boon cannot be taken twice")
        _check(absf(Run.mult("dash_time_mult") - 1.35) < 0.001 and absf(Run.mult("sneak_mult") - 1.35) < 0.001, "boons scale the dash and the sneak")
        var offer := Run.offer_boons(3)
        var seen := {}
        for o in offer:
                seen[o["id"]] = true
        _check(offer.size() == 3 and seen.size() == 3 and not seen.has("long_coat") and not seen.has("soft_soles"),
                        "a boon offer is 3 different boons you do not own")
        Run.add_boon("silver_tongue")
        Run.add_intel(Run.Tier.EVIDENCE)
        var r := Run.finish("caught")
        _check(r["insurance"] == floori(8 * 0.5), "SILVER TONGUE: caught keeps 50%% (%d of 8)" % r["insurance"])
        _take("ministry")
        Run.add_boon("lucky_coin")
        _check(Run.consume_second_chance() and not Run.consume_second_chance(), "LUCKY COIN saves you exactly once")
        Run.finish("caught")
        _take("ministry")
        Run.add_boon("greed")
        _check(Run.guard_bonus() == 1 and absf(Run.score_mult() - 1.25) < 0.001, "GREED: +25%% intel and +1 guard")
        Run.begin_night()
        _check(Run.boons.has("greed"), "a restart keeps your boons")
        Run.deal_night()
        _check(Run.boons.is_empty(), "a fresh deal clears the boons")
        Run.finish("caught")
        # the desk drawer
        Run.favors = 5
        _check(not Run.buy("stride"), "five favors cannot buy a 6-favor upgrade")
        Run.favors = 20
        _check(Run.buy("stride") and Run.meta["stride"] == 1 and Run.favors == 14, "buying LONG STRIDE I costs 6 favors")
        _check(absf(Run.mult("dash_time_mult") - 1.12) < 0.001, "LONG STRIDE I: dash +12%%")
        Run.favors = 100
        Run.buy("stride")
        Run.buy("stride")
        _check(Run.meta["stride"] == 3 and not Run.buy("stride"), "an upgrade tops out at level III")
        Run.buy("pockets")
        _check(absf(Run.insurance_share() - 0.3) < 0.001, "DEEP POCKETS I: insurance 20%% -> 30%%")
        Run.save_game()
        var saved_favors: int = Run.favors
        Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
        Run.favors = 0
        Run.load_game()
        _check(Run.favors == saved_favors and Run.meta["stride"] == 3 and Run.meta["pockets"] == 1, "favors and upgrades survive a save + load")
        Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
        Run.favors = 0


# --- 3. the buildings -------------------------------------------------------------------------

func _bfs(b: Node, start: Vector2i, avoid: Dictionary) -> Dictionary:
        var seen := {start: true}
        var q: Array[Vector2i] = [start]
        while not q.is_empty():
                var c: Vector2i = q.pop_back()
                for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
                        var n: Vector2i = c + d
                        if n.x < 0 or n.y < 0 or n.x >= BUILDER.W or n.y >= BUILDER.H:
                                continue
                        if seen.has(n) or not b.is_open(n) or avoid.has(n):
                                continue
                        seen[n] = true
                        q.append(n)
        return seen


func _test_buildings() -> void:
        var bad: Array[String] = []
        var room_counts := {}
        var with_holes := 0
        var total := 0
        for ai in 3:
                for floor_no in [1, 2]:
                        for sd in 27:
                                var a: Dictionary = Run.ARCHETYPES[ai * 2]
                                var tasks: Array = a["tasks"]
                                var guards: int = a["guards"]
                                if floor_no == 2:
                                        tasks = []
                                        for i in int(a["evidence"]):
                                                tasks.append("evidence")
                                        guards += 1
                                var b: Node2D = BUILDER.new()
                                add_child(b)
                                var plan: Dictionary = b.generate(sd * 7 + ai, {"floor": floor_no, "tasks": tasks, "guards": guards})
                                total += 1
                                var tag := "arch%d floor%d seed%d" % [ai, floor_no, sd]
                                var rooms: int = plan["rooms"]
                                room_counts[rooms] = int(room_counts.get(rooms, 0)) + 1
                                if rooms < 9 or rooms > 12:
                                        bad.append("%s rooms=%d" % [tag, rooms])
                                var squeeze: Dictionary = plan["squeeze"]
                                if int(plan["crawl_holes"]) >= 1:
                                        with_holes += 1
                                var stand := _bfs(b, plan["player"], squeeze)
                                if squeeze.has(plan["player"]) or squeeze.has(plan["exit"]):
                                        bad.append("%s starts or ends in a tight spot" % tag)
                                if not stand.has(plan["exit"]):
                                        bad.append("%s exit needs a crawl" % tag)
                                var rooms_used := {}
                                if plan["tasks"].size() != tasks.size():
                                        bad.append("%s dealt %d/%d jobs" % [tag, plan["tasks"].size(), tasks.size()])
                                for t in plan["tasks"]:
                                        if not stand.has(t["cell"]):
                                                bad.append("%s job %s needs a crawl" % [tag, t["type"]])
                                        if rooms_used.has(t["room"]):
                                                bad.append("%s two jobs share room %d" % [tag, t["room"]])
                                        rooms_used[t["room"]] = true
                                if plan["guards"].size() != guards:
                                        bad.append("%s %d guard routes, wanted %d" % [tag, plan["guards"].size(), guards])
                                for route in plan["guards"]:
                                        if route.size() < 2:
                                                bad.append("%s a guard route has %d stops" % [tag, route.size()])
                                        for i in route.size():
                                                var c: Vector2i = route[i]
                                                if not stand.has(c):
                                                        bad.append("%s guard stop %s needs a crawl" % [tag, c])
                                                var z: Vector2i = route[(i + 1) % route.size()]
                                                if c != z and b.path_len(c, z) < 2:
                                                        bad.append("%s guard leg %s->%s has no path" % [tag, c, z])
                                var nav: AStarGrid2D = plan["nav"]
                                for c in squeeze:
                                        if not nav.is_point_solid(c):
                                                bad.append("%s a tight spot is open to guards" % tag)
                                                break
                                if b.path_len(plan["player"], plan["exit"]) < 26:
                                        bad.append("%s entry -> exit is too short" % tag)
                                b.queue_free()
        _check(bad.is_empty(), "%d generated buildings are fair (%s)" % [total, "; ".join(bad.slice(0, 4))])
        _check(room_counts.size() >= 3 and room_counts.keys().min() >= 9 and room_counts.keys().max() <= 12,
                        "room counts vary inside 9-12: %s" % str(room_counts))
        _check(with_holes >= total * 0.8, "most buildings carry a crawl hole (%d of %d)" % [with_holes, total])
        var b1: Node2D = BUILDER.new()
        add_child(b1)
        var p1: Dictionary = b1.generate(1234, {"floor": 1})
        var m1: Array = b1.map_strings().duplicate()
        var b2: Node2D = BUILDER.new()
        add_child(b2)
        var p2: Dictionary = b2.generate(1234, {"floor": 1})
        _check(m1 == b2.map_strings() and p1["exit"] == p2["exit"], "the same seed deals the same building")
        var b3: Node2D = BUILDER.new()
        add_child(b3)
        b3.generate(4321, {"floor": 1})
        _check(m1 != b3.map_strings(), "a different seed deals a different building")
        for n in [b1, b2, b3]:
                n.queue_free()
        await get_tree().process_frame


# --- 4. the night -------------------------------------------------------------------------------

func _new_night(id: String, floor_no: int = 1, seed: int = 11, boons_in: Array = []) -> Node2D:
        Run.debug_seed = seed
        _take(id)
        for b in boons_in:
                Run.add_boon(b)
        if floor_no == 2:
                Run.enter_lower_floor(80)
        var n: Node2D = NIGHT.instantiate()
        add_child(n)
        return n


func _drop_night(n: Node2D) -> void:
        n.queue_free()
        for a in ["interact", "descend", "takedown", "move_left", "move_right", "dash", "pause"]:
                Input.action_release(a)
        await get_tree().process_frame
        await get_tree().process_frame


func _freeze_guards(n: Node2D) -> void:
        for g in n.guards:
                g.set_physics_process(false)


func _test_night() -> void:
        var n := _new_night("ministry")
        await _frames(4)
        var player: CharacterBody2D = n.get_node("Player")
        _check(n.tasks.size() == 3, "ministry night deals 3 jobs")
        _check(n.guards.size() == 3, "ministry night has 3 guards")
        # the night is dark: a baked-dark atlas, and NO glow rides the actors
        var baked := ""
        for c in n.get_node("World").get_children():
                if c is TileMapLayer:
                        var tset: TileSet = c.tile_set
                        baked = tset.get_source(0).texture.resource_path
        _check(baked.contains("_night") or baked.contains("_deep") or baked.contains("_blackout"),
                        "the night floor uses the dark bake")
        var riding := 0
        for c in player.get_children():
                if c is Lantern:
                        riding += 1
        for g in n.guards:
                for c in g.get_children():
                        if c is Lantern:
                                riding += 1
        _check(riding == 0, "no glow rides the PI or the guards")
        _freeze_guards(n)
        var hud: CanvasLayer = n.get_node("NightHud")
        _check(hud._jobs.text.count("[ ]") == 2 and hud._jobs.text.contains("x2"), "the job list groups the pairs")
        var spot: Node2D = n.tasks[0]
        player.global_position = spot.global_position
        var tier: int = spot.tier()
        var before: int = Run.unbanked_points()
        Input.action_press("interact")
        await _frames(10)
        _check(spot.progress > 0.0 and spot.progress < 1.0 and is_instance_valid(spot), "holding E fills the job bar (%.2f)" % spot.progress)
        Input.action_release("interact")
        await _frames(20)
        _check(spot.progress < 0.4, "letting go bleeds the progress back")
        Input.action_press("interact")
        await _frames(int(spot.hold_time() * 60.0) + 20)
        Input.action_release("interact")
        await _frames(2)
        _check(Run.unbanked_points() == before + Run.TIER_POINTS[tier] and Run.unbanked[tier] == 1, "a finished job adds its tier's points (+%d)" % Run.TIER_POINTS[tier])
        _check(Run.chain == 1 and Run.style == 100, "a finished job starts the style chain")
        _check(hud._jobs.text.count("[x]") + hud._jobs.text.count("[/]") == 1
                        and hud._ledger_pts.text.contains("%d PTS" % Run.unbanked_points()), "the HUD ticks the finished job and shows the ledger")
        _check(hud._jobs.text.count("[ ]") == 1, "one open job line stays on the list")
        var guards_before: int = n.guards.size()
        Run._spot_cd = 0.0
        Run.register_spot()
        await _frames(3)
        _check(n.guards.size() == guards_before + 1, "ALERTED sends a reinforcement")
        _check(n.guards[-1]._state == n.guards[-1].State.CHASE, "the reinforcement hunts the PI's last position")
        var door: Node2D = n.get_node("BackDoor")
        player.global_position = door.global_position
        await _frames(3)
        var prompt: Array = door.prompt_for(Run.unbanked_points())
        _check(prompt[0].contains("[E] LEAVE NOW") and prompt[0].contains("[Q] DESCEND"), "the back door offers LEAVE NOW and DESCEND")
        _check(door.can_descend(), "below LOCKDOWN the lower floor is open")
        Run._spot_cd = 0.0
        Run.register_spot()
        Run._spot_cd = 0.0
        Run.register_spot()
        _check(Run.lockdown() and not door.can_descend(), "LOCKDOWN seals the lower floor")
        _check(door.prompt_for(0)[0].contains("sealed"), "the sealed door says so")
        var carried: int = Run.unbanked_points()
        Input.action_press("interact")
        await _frames(3)
        Input.action_release("interact")
        _check(player.won and Run.last_result.get("outcome") == "extracted" and Run.last_result.get("banked") == carried,
                        "E at the back door banks all %d points" % carried)
        _check(Run.last_result.get("style", 0) >= 100 and Run.last_result.has("favors"), "the debrief records style and favors")
        await _drop_night(n)

        n = _new_night("ministry", 1, 12)
        await _frames(4)
        player = n.get_node("Player")
        door = n.get_node("BackDoor")
        _freeze_guards(n)
        Run.add_intel(Run.Tier.LEADS)
        player.global_position = door.global_position
        await _frames(3)
        Input.action_press("descend")
        await _frames(3)
        Input.action_release("descend")
        _check(Run.floor_no == 2 and Run.carry_health == player.health and Run.unbanked_points() == 3 and Run.active,
                        "Q descends: floor 2, health and the unbanked intel travel down")
        await _drop_night(n)
        n = _new_night("ministry", 2, 13)
        await _frames(4)
        player = n.get_node("Player")
        _check(n.tasks.size() == 2 and n.tasks[0].task_type == "evidence", "the lower floor deals the evidence cases")
        _check(n.guards.size() == 4, "the lower floor has one more guard than the building")
        _check(player.health == 80, "health arrived with the PI (80)")
        _freeze_guards(n)
        Run.add_intel(Run.Tier.EVIDENCE)
        Run.add_intel(Run.Tier.EVIDENCE)
        player.capture()
        await _frames(3)
        _check(Run.last_result.get("outcome") == "caught" and Run.last_result.get("banked") == floori(16 * Run.INSURANCE),
                        "caught below keeps only %d%% insurance (%d of %d)" % [int(Run.INSURANCE * 100.0), Run.last_result.get("banked", -1), Run.last_result.get("carried", -1)])
        await _drop_night(n)
        Run.debug_seed = -1


# --- 4b. rules inside a night ----------------------------------------------------------------------

func _test_rules_in_the_night() -> void:
        # HIGH SECURITY: +1 guard. GREED stacks on top.
        var n := _new_night("archive", 1, 31)
        await _frames(3)
        _check(n.guards.size() == 4, "HIGH SECURITY night walks 4 guards (3 + 1)")
        await _drop_night(n)
        n = _new_night("ministry", 1, 31, ["greed"])
        await _frames(3)
        _check(n.guards.size() == 4, "GREED adds a guard too")
        await _drop_night(n)

        # ON AIR: a dash is heard; guards inside the ring come to look
        n = _new_night("radio", 1, 32)
        await _frames(3)
        var player: CharacterBody2D = n.get_node("Player")
        for g in n.guards:
                g.set_physics_process(false)
        var ear: CharacterBody2D = n.guards[0]
        ear.global_position = player.global_position + Vector2(60, 0)
        var far: CharacterBody2D = n.guards[1]
        far.global_position = player.global_position + Vector2(300, -200)
        Input.action_press("move_right")
        Input.action_press("dash")
        await _frames(3)
        Input.action_release("dash")
        Input.action_release("move_right")
        await _frames(2)
        _check(ear._state == ear.State.CHASE, "ON AIR: a dash pulls the guard 60 px away")
        _check(far._state != far.State.CHASE, "ON AIR: a guard far outside the ring does not hear it")
        var rings := 0
        for c in n.get_children():
                if c.get_script() == n.RING:
                        rings += 1
        _check(rings >= 1, "ON AIR: the noise ring is drawn")
        await _drop_night(n)

        # CURFEW: the bell raises the alarm by itself
        n = _new_night("customs", 1, 33)
        await _frames(3)
        for g in n.guards:
                g.set_physics_process(false)
        _check(Run.alarm == 0, "CURFEW starts CALM")
        n.curfew_left = 0.05
        await _frames(8)
        _check(Run.alarm == 1, "CURFEW: the bell raised the alarm on its own")
        await _drop_night(n)

        # BLACKOUT: the lights are down (the darkest tile bake)
        n = _new_night("telegraph", 1, 34)
        await _frames(3)
        var dark_bake := ""
        for c in n.get_node("World").get_children():
                if c is TileMapLayer:
                        dark_bake = c.tile_set.get_source(0).texture.resource_path
        _check(dark_bake.contains("blackout"), "BLACKOUT dims the world")
        await _drop_night(n)

        # SEALED VAULT: evidence on floor 1, no way down
        n = _new_night("deaddrop", 1, 35)
        await _frames(3)
        var kinds := {}
        for t in n.tasks:
                kinds[t.task_type] = true
        _check(kinds.has("evidence"), "SEALED VAULT deals an evidence case on floor 1")
        var door: Node2D = n.get_node("BackDoor")
        _check(not door.can_descend() and door.prompt_for(0)[0].contains("SEALED"), "SEALED VAULT: the back door has no stairs")
        await _drop_night(n)

        # LUCKY COIN: the first capture slips away, the second does not
        n = _new_night("ministry", 1, 36, ["lucky_coin"])
        await _frames(3)
        player = n.get_node("Player")
        _freeze_guards(n)
        player.capture()
        await _frames(2)
        _check(not player.is_dead() and Run.active, "LUCKY COIN: the first capture is shrugged off")
        player.capture()
        _check(not player.is_dead(), "LUCKY COIN: the grace window protects the PI")
        await _frames(100)
        player.capture()
        await _frames(2)
        _check(player.is_dead() and Run.last_result.get("outcome") == "caught", "LUCKY COIN: the second capture ends the night")
        await _drop_night(n)

        # boons change the body
        n = _new_night("ministry", 1, 37, ["long_coat", "runners_high"])
        await _frames(3)
        player = n.get_node("Player")
        _freeze_guards(n)
        Input.action_press("dash")
        await _frames(2)
        Input.action_release("dash")
        _check(player._dash_time_left > player.DASH_TIME * 1.2, "LONG COAT lengthens the dash (%.3f s)" % player._dash_time_left)
        await _drop_night(n)
        Run.debug_seed = -1


# --- 5. tight spots --------------------------------------------------------------------------------------

func _find_slot(n: Node2D) -> Vector2i:
        # a 1-cell slot with open, non-squeeze floor on both sides
        var sq: Dictionary = n.plan["squeeze"]
        var world: Node = n.get_node("World")
        for c in sq:
                var l: Vector2i = c + Vector2i.LEFT
                var r: Vector2i = c + Vector2i.RIGHT
                if world.is_open(l) and world.is_open(r) and not sq.has(l) and not sq.has(r):
                        if not world.is_open(c + Vector2i.UP) and not world.is_open(c + Vector2i.DOWN):
                                return c
        return Vector2i(-1, -1)


func _test_tight_spots() -> void:
        var n := _new_night("ministry", 1, 41)
        await _frames(3)
        _freeze_guards(n)
        var player: CharacterBody2D = n.get_node("Player")
        var slot := _find_slot(n)
        _check(slot.x >= 0, "the building has a 1-tile crawl slot (%s)" % slot)
        var left := slot + Vector2i.LEFT
        var edge: float = n.cell_world(slot).x + 8.0
        # control: a standing body cannot get through a 16 px slot
        player.squeeze_cells = {}
        player.global_position = n.cell_world(left)
        await _frames(2)
        Input.action_press("move_right")
        await _frames(80)
        Input.action_release("move_right")
        _check(player.global_position.x < edge - 4.0 and not player.squeezing, "control: a standing PI is stopped at the slot (x=%.0f)" % player.global_position.x)
        # the real thing: the crawl
        player.squeeze_cells = n.plan["squeeze"]
        player.global_position = n.cell_world(left)
        await _frames(2)
        Input.action_press("move_right")
        var saw_crawl := false
        var saw_clip := false
        var small := false
        for i in 120:
                await get_tree().physics_frame
                if player.squeezing:
                        saw_crawl = true
                        var spr: AnimatedSprite2D = null
                        for c in player.get_children():
                                if c is AnimatedSprite2D:
                                        spr = c
                        saw_clip = saw_clip or spr.animation == "squeeze"
                        small = small or (player._col.shape is RectangleShape2D and player._col.shape.size.y <= 10.0)
                if player.global_position.x > edge + 10.0:
                        break
        Input.action_release("move_right")
        _check(saw_crawl and saw_clip, "the PI drops into the squeeze animation at the slot")
        _check(small, "the crawl uses the small collider")
        _check(player.global_position.x > edge + 8.0, "the PI crawls THROUGH the slot (x=%.0f > %.0f)" % [player.global_position.x, edge])
        await _frames(20)
        _check(not player.squeezing and player._col.shape == player._stand_shape, "back on two feet on the far side")
        _check(player.is_sneaking() == false, "standing again: no longer counted as crouched")
        await _drop_night(n)

        # a crawling PI counts as hidden (sneak-grade visibility)
        n = _new_night("ministry", 1, 41)
        await _frames(3)
        _freeze_guards(n)
        player = n.get_node("Player")
        player.squeezing = true
        _check(player.is_sneaking(), "crawling counts as sneaking for the guards' eyes")
        player.squeezing = false
        await _drop_night(n)
        Run.debug_seed = -1


# --- 5b. guards have a body --------------------------------------------------------------------------------

func _test_guard_body() -> void:
        var worst_frames := 0
        var stuck := 0
        var walls := 0
        var slots := 0
        var runs := 0
        for sd in [51, 52, 53, 54, 55]:
                var n := _new_night("ministry", 1, sd)
                await _frames(3)
                var g: CharacterBody2D = n.guards[0]
                if sd == 51:
                        var col: CollisionShape2D = g.get_node_or_null("Collision")
                        _check(col != null and col.shape is RectangleShape2D and col.shape.size == Vector2(10, 15), "guards carry a real 10 x 15 body")
                var player: CharacterBody2D = n.get_node("Player")
                player.global_position = Vector2(40, 40)
                for o in n.guards:
                        if o != g:
                                o.set_physics_process(false)
                var nav: AStarGrid2D = n.plan["nav"]
                var sq: Dictionary = n.plan["squeeze"]
                for target_cell in [n.plan["exit"], n.plan["player"]]:
                        var far: Vector2 = n.cell_world(target_cell)
                        g.hunt(far)
                        runs += 1
                        var frames := 0
                        while frames < 1500 and g.global_position.distance_to(far) > 10.0:
                                await get_tree().physics_frame
                                frames += 1
                                var c: Vector2i = g._nav_cell(g.global_position)
                                if nav.is_point_solid(c) and not sq.has(c):
                                        walls += 1
                                if sq.has(c):
                                        slots += 1
                        worst_frames = maxi(worst_frames, frames)
                        if frames >= 1500:
                                stuck += 1
                await _drop_night(n)
        _check(stuck == 0, "%d cross-building hunts all arrive (slowest %d frames)" % [runs, worst_frames])
        _check(walls == 0, "guards never stand inside a wall or furniture (%d frames)" % walls)
        _check(slots == 0, "guards never enter a tight spot (%d frames)" % slots)
        Run.debug_seed = -1


# --- 6. the office: the walkable prep room ---------------------------------------------------

func _test_office() -> void:
        # the office deals tonight's single case
        Run._bag = []
        Run._last_id = ""
        var o: Node2D = OFFICE_SCENE.instantiate()
        o.deal_seed = 3
        add_child(o)
        await get_tree().process_frame
        _check(not Run.case.is_empty() and not Run.need_new_case, "the office deals tonight's single case")
        var dealt_id: String = String(Run.case["id"])
        var dealt_no: String = String(Run.case["case_no"])
        Run._last_id = ""
        Run.need_new_case = true
        Run.deal_night(3)
        _check(String(Run.case["id"]) == dealt_id and String(Run.case["case_no"]) == dealt_no, "a pinned deal seed deals the same case again")

        # the case file reads
        o.open_panel("case")
        _check(o._panel_kind == "case" and o._panel_body.text.contains(dealt_no)
                        and o._panel_body.text.contains(Run.RULES[Run.case["rule"]]["name"]), "the case file reads tonight's case")
        var backs_hidden := true
        for cb in o._card_backs:
                backs_hidden = backs_hidden and not cb.visible
        _check(o._panel_body.visible and backs_hidden, "the case file panel hides the boon cards")
        o.close_panel()

        # the PI walks the office
        var p: CharacterBody2D = o.get_node("Player")
        var x0: float = p.global_position.x
        Input.action_press("move_right")
        await _frames(30)
        Input.action_release("move_right")
        _check(p.global_position.x > x0 + 20.0, "the PI walks the office")
        _check(o._near_spot() == "", "walking away clears the spot prompt")

        # the file wall sells permanent upgrades
        Run.favors = 12
        Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
        o.open_panel("shop")
        _check(o._panel_kind == "shop" and o.buy("soles") and Run.meta["soles"] == 1 and Run.favors == 6, "the file wall sells upgrades")
        _check(not o.buy("soles") and Run.meta["soles"] == 1, "a poor PI cannot afford level II")
        o.close_panel()
        Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
        Run.favors = 0
        o.queue_free()
        await get_tree().process_frame

        # the radio: a boon-reward case gives two picks
        Run.case = _arch("ministry")
        Run.need_new_case = false
        Run.boons = []
        Run.boon_picks_left = 2
        var o2: Node2D = OFFICE_SCENE.instantiate()
        add_child(o2)
        await get_tree().process_frame
        _check(String(Run.case["id"]) == "ministry" and Run.boon_picks_left == 2, "a boon-reward case offers two radio picks")
        o2.open_panel("boons")
        _check(o2.boon_offers.size() == 3, "the radio offers three boons")
        _check(o2._card_backs[0].visible and o2._card_backs[2].visible, "the boon cards show on the radio")
        var first_boon: String = String(o2.boon_offers[1]["id"])
        o2.take_boon(1)
        _check(Run.boons == [first_boon] and Run.boon_picks_left == 1 and o2._panel_kind == "boons", "the first pick is carried, the radio stays on")
        o2.take_boon(0)
        _check(Run.boons.size() == 2 and Run.boon_picks_left == 0 and o2._panel_kind == "", "the second pick closes the radio")
        o2.open_panel("boons")
        _check(not o2.take_boon(0) and Run.boons.size() == 2, "the radio is quiet once the picks are spent")
        o2.close_panel()
        o2._select(5)
        _check(o2._selected >= 0 and o2._selected < 3, "boon selection stays on the cards")

        # the street door starts the night
        _check(o2.start_night(false) and Run.active and Run.boons.size() == 2, "the street door starts the night with the boons you picked")
        Run.finish("caught")
        o2.queue_free()
        await get_tree().process_frame


# --- 7. main menu + pause ----------------------------------------------------------------------

func _test_menu_pause() -> void:
        _check(InputMap.has_action("pause"), "the pause action exists")
        var m: Control = MENU.instantiate()
        add_child(m)
        await get_tree().process_frame
        await get_tree().process_frame
        _check(m.get_node_or_null("Stage/Title") != null, "the menu hangs the neon logo")
        _check(m.get_node_or_null("Stage/Prompt") != null, "the menu asks ENTER")
        var txt := 0
        for c in m.find_children("*", "Label", true, false):
                txt += 1
        _check(txt == 0, "the menu shows nothing but the logo and the prompt")
        m.queue_free()
        await get_tree().process_frame

        # ESC pauses and resumes the night
        var n := _new_night("ministry")
        await _frames(3)
        _check(not get_tree().paused, "the night runs unpaused")
        _press("pause")
        await _frames(2)
        _check(get_tree().paused, "ESC pauses the night")
        _release_action("pause")
        await _frames(1)
        _press("pause")
        await _frames(2)
        _check(not get_tree().paused, "ESC resumes the night")
        _release_action("pause")
        await _drop_night(n)

        # ESC pauses and resumes the office
        Run.need_new_case = true
        var o: Node2D = OFFICE_SCENE.instantiate()
        add_child(o)
        await get_tree().process_frame
        _press("pause")
        await _frames(2)
        _check(get_tree().paused, "ESC pauses the office")
        _release_action("pause")
        await _frames(1)
        _press("pause")
        await _frames(2)
        _check(not get_tree().paused, "ESC resumes the office")
        _release_action("pause")
        o.queue_free()
        await get_tree().process_frame
        Run.finish("caught")


func _finish() -> void:
        Run.begin_night()
        Run.finish("caught")
        if _fails.is_empty():
                print("NIGHT: ALL PASS")
                get_tree().quit(0)
        else:
                print("NIGHT: %d FAIL" % _fails.size())
                get_tree().quit(1)
