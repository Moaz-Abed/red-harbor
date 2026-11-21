extends Node
## Red Harbor - headless NIGHT LOOP test (roadmap 4.2, Hades-style run).
##
##   godot --headless --path . res://tests/night_test.tscn
##
## 1. RUN STATE   tiers, the alarm ladder, insurance, the style chain.
## 2. THE BOARD   every board deals 3 DIFFERENT cases (rules, jobs, rewards);
##                rules bend the numbers; boons and favors upgrades stack;
##                the desk drawer saves and loads.
## 3. BUILDINGS   162 seeded deals: 9-12 rooms, one job per room, everything
##                reachable WITHOUT squeezing, tight spots marked and solid
##                for guards.
## 4. THE NIGHT   the scene end to end: jobs, ON AIR noise, CURFEW bells,
##                BLACKOUT, SEALED VAULT, lockdown, leave / descend / caught,
##                LUCKY COIN.
## 5. TIGHT SPOTS the PI crawls through a 1-tile slot (and a standing body
##                cannot); guards have a real collider and never enter one.
## 6. THE OFFICE  board -> case -> boon pick(s) -> night; the desk drawer.
##
## Exits 0 with "NIGHT: ALL PASS", else 1 with the FAIL list.

const NIGHT := preload("res://scenes/night.tscn")
const BRIEFING := preload("res://scenes/briefing.tscn")
const BUILDER := preload("res://scripts/building_builder.gd")

var _fails: Array[String] = []


func _ready() -> void:
	Run.save_path = "user://night_test_save.cfg"   # never touch the real save
	Run.favors = 0
	_test_run_state()
	_test_board_and_rules()
	_test_boons_and_shop()
	_test_buildings()
	await _test_night()
	await _test_rules_in_the_night()
	await _test_tight_spots()
	await _test_guard_body()
	await _test_briefing()
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


func _arch(id: String) -> Dictionary:
	for a in Run.ARCHETYPES:
		if a["id"] == id:
			var c: Dictionary = a.duplicate(true)
			c["case_no"] = "CASE 100"
			c["danger"] = Run.danger_of(c)
			return c
	return {}


func _take(id: String, keep_boons: bool = false) -> void:
	Run.case = _arch(id)
	Run.begin_night(keep_boons)


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


# --- 2. the board and the rules ---------------------------------------------------------------

func _test_board_and_rules() -> void:
	var all_rules := {}
	var reward_kinds := {}
	var bad: Array[String] = []
	for sd in 40:
		var o := Run.roll_offers(sd)
		if o.size() != 3:
			bad.append("seed %d dealt %d" % [sd, o.size()])
			continue
		var rules := {}
		var ids := {}
		var sigs := {}
		for c in o:
			rules[c["rule"]] = true
			ids[c["id"]] = true
			var t: Array = c["tasks"].duplicate()
			t.sort()
			sigs[str(t)] = true
			all_rules[c["rule"]] = true
			reward_kinds[c["reward"]["kind"]] = true
			if c["reward"]["kind"] == "favors" and int(c["reward"]["amount"]) < 2:
				bad.append("seed %d favors reward < 2" % sd)
		if rules.size() != 3 or ids.size() != 3:
			bad.append("seed %d boards repeat a rule/case" % sd)
		if sigs.size() < 2:
			bad.append("seed %d boards have the same jobs" % sd)
	_check(bad.is_empty(), "40 boards: 3 different cases, 3 different rules each (%s)" % "; ".join(bad.slice(0, 3)))
	_check(all_rules.size() == 6, "all six district rules turn up across boards")
	_check(reward_kinds.has("favors") and reward_kinds.has("boon"), "boards offer both favors and boon rewards")
	var a := Run.roll_offers(7)
	var b := Run.roll_offers(7)
	_check(str(a) == str(b), "the same board seed deals the same board")
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
	var reach := 0
	for c in Run.ARCHETYPES:
		var tasks: Array = c["tasks"]
		reach += tasks.size()
	_check(reach >= 6 * 3, "every case deals at least 3 jobs")


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
	Run.begin_night(true)
	_check(Run.boons.has("greed"), "a restart keeps your boons")
	Run.begin_night()
	_check(Run.boons.is_empty(), "a new night starts with none")
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
	for a in ["interact", "descend", "takedown", "move_left", "move_right", "dash"]:
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
	_freeze_guards(n)
	var hud: CanvasLayer = n.get_node("NightHud")
	_check(hud._jobs.text.count("[ ]") == 3 and hud._jobs.text.count("[x]") == 0, "the job list shows 3 open jobs")
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
	_check(hud._jobs.text.count("[x]") == 1 and hud._ledger_pts.text.contains("%d PTS" % Run.unbanked_points()), "the HUD ticks the job off and shows the ledger")
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

	# BLACKOUT: the lights are down
	n = _new_night("telegraph", 1, 34)
	await _frames(3)
	var dark := false
	for c in n.get_children():
		if c is CanvasModulate and c.color.r < 0.6:
			dark = true
	_check(dark, "BLACKOUT dims the world")
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


# --- 6. the office ---------------------------------------------------------------------------------------------

func _test_briefing() -> void:
	var b: Control = BRIEFING.instantiate()
	b.board_seed = 3
	add_child(b)
	await get_tree().process_frame
	_check(b.cards.size() == 3, "three cases are on the desk")
	var rules := {}
	for c in Run.offers:
		rules[c["rule"]] = true
	_check(rules.size() == 3, "the desk shows three different rules")
	var picked: String = Run.offers[2]["id"]
	b._select(2)
	b.confirm(false)
	_check(b.stage == "boons" and b.boon_offers.size() == 3 and Run.active and Run.lead()["id"] == picked, "taking a case opens the boon pick")
	var first_boon: String = b.boon_offers[1]["id"]
	b.pick_boon(1, false)
	var expect_two: bool = Run.lead()["reward"]["kind"] == "boon"
	if expect_two:
		_check(b.stage == "boons" and Run.boons == [first_boon], "a boon reward case gives a SECOND pick")
		b.pick_boon(0, false)
		_check(Run.boons.size() == 2, "two boons are carried into the night")
	else:
		_check(Run.boons == [first_boon], "the picked boon is carried into the night")
	b._select(5)
	_check(b.selected == 2 or b.selected == 5 % b.cards.size(), "selection wraps around the cards")
	b.queue_free()
	await get_tree().process_frame
	# a board with a boon reward: two picks
	var found := false
	for sd in 40:
		Run.roll_offers(sd)
		for i in 3:
			if Run.offers[i]["reward"]["kind"] == "boon":
				var b2: Control = BRIEFING.instantiate()
				b2.board_seed = sd
				add_child(b2)
				await get_tree().process_frame
				b2._select(i)
				b2.confirm(false)
				b2.pick_boon(0, false)
				found = b2.stage == "boons" and b2.picks_left == 1
				b2.pick_boon(0, false)
				found = found and Run.boons.size() == 2
				b2.queue_free()
				await get_tree().process_frame
				break
		if found:
			break
	_check(found, "a boon-reward case offers two boon picks in a row")
	# the desk drawer
	var b3: Control = BRIEFING.instantiate()
	b3.board_seed = 9
	add_child(b3)
	await get_tree().process_frame
	Run.favors = 12
	Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
	_check(b3.buy("soles") and Run.meta["soles"] == 1 and Run.favors == 6, "Z X C spend favors in the desk drawer")
	_check(not b3.buy("soles") and Run.meta["soles"] == 1, "a poor PI cannot afford level II")
	Run.meta = {"stride": 0, "soles": 0, "pockets": 0}
	Run.favors = 0
	b3.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	Run.begin_night()
	Run.finish("caught")
	if _fails.is_empty():
		print("NIGHT: ALL PASS")
		get_tree().quit(0)
	else:
		print("NIGHT: %d FAIL" % _fails.size())
		get_tree().quit(1)
