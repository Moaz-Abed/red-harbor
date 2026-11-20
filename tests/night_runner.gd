extends Node
## Red Harbor - headless NIGHT LOOP test (roadmap 4.2).
##
##   godot --headless --path . res://tests/night_test.tscn
##
## 1. RUN STATE     tiers, points, the alarm ladder + cooldown, insurance.
## 2. THE BUILDING  80 seeded deals x 3 leads x 2 floors: 9-12 rooms, one
##                  job per room, everything reachable, entry -> back door
##                  is a real walk, patrol loops are walkable.
## 3. THE NIGHT     the scene: jobs by hold-E, the back door's two options,
##                  lockdown sealing the lower floor, caught = insurance.
## 4. GUARD NAV     a guard walks a doorway route across the building.
## 5. THE OFFICE    three leads on the desk, the choice reaches the Run.
##
## Exits 0 with "NIGHT: ALL PASS", else 1 with the FAIL list.

const NIGHT := preload("res://scenes/night.tscn")
const BRIEFING := preload("res://scenes/briefing.tscn")
const BUILDER := preload("res://scripts/building_builder.gd")

var _fails: Array[String] = []


func _ready() -> void:
	_test_run_state()
	_test_buildings()
	await _test_night()
	await _test_guard_nav()
	await _test_briefing()
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


# --- 1. run state ------------------------------------------------------------------------

func _test_run_state() -> void:
	Run.choose_lead(1)
	Run.begin_night()
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
	Run._spot_cd = 0.0
	Run.register_spot()
	_check(Run.alarm == 3, "the ladder tops out at LOCKDOWN")
	_check(Run.extra_guards() == 2 and Run.patrol_mult() > 1.4 and Run.range_mult() > 1.25, "LOCKDOWN: 2 extra guards, faster patrols, longer beams")
	var r := Run.finish("caught")
	_check(r["insurance"] == floori(12 * Run.INSURANCE) and r["banked"] == r["insurance"], "caught keeps only the insurance share (%d of 12)" % r["insurance"])
	_check(Run.patrol_mult() == 1.0 and not Run.lockdown(), "after the night every multiplier reads 1.0")
	Run.begin_night()
	Run.add_intel(Run.Tier.LEADS)
	var r2 := Run.finish("extracted")
	_check(r2["banked"] == 3 and Run.session_banked == r["banked"] + 3, "extraction banks everything carried")
	_check(Run.finish("caught") == r2, "a night ends exactly once")
	for i in Run.LEADS.size():
		var tasks: Array = Run.LEADS[i]["tasks"]
		_check(tasks.size() == 3, "lead %d deals three jobs" % i)


# --- 2. the building -----------------------------------------------------------------------

func _bfs_reach(b: Node, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var q: Array[Vector2i] = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= BUILDER.W or n.y >= BUILDER.H:
				continue
			if seen.has(n) or not b.is_open(n):
				continue
			seen[n] = true
			q.append(n)
	return seen


func _test_buildings() -> void:
	var bad: Array[String] = []
	var room_counts := {}
	var long_walks := 0
	var total := 0
	for lead_i in Run.LEADS.size():
		for floor_no in [1, 2]:
			for sd in 27:
				var lead: Dictionary = Run.LEADS[lead_i]
				var tasks: Array = lead["tasks"]
				var guards: int = lead["guards"]
				if floor_no == 2:
					tasks = []
					for i in int(lead["evidence"]):
						tasks.append("evidence")
					guards += 1
				var b: Node2D = BUILDER.new()
				add_child(b)
				var plan: Dictionary = b.generate(sd * 7 + lead_i, {"floor": floor_no, "tasks": tasks, "guards": guards})
				total += 1
				var tag := "lead%d floor%d seed%d" % [lead_i, floor_no, sd]
				var rooms: int = plan["rooms"]
				room_counts[rooms] = int(room_counts.get(rooms, 0)) + 1
				if rooms < 9 or rooms > 12:
					bad.append("%s rooms=%d" % [tag, rooms])
				var reach := _bfs_reach(b, plan["player"])
				if not reach.has(plan["exit"]):
					bad.append("%s exit unreachable" % tag)
				var rooms_used := {}
				if plan["tasks"].size() != tasks.size():
					bad.append("%s dealt %d/%d jobs" % [tag, plan["tasks"].size(), tasks.size()])
				for t in plan["tasks"]:
					if not reach.has(t["cell"]):
						bad.append("%s job %s unreachable" % [tag, t["type"]])
					if rooms_used.has(t["room"]):
						bad.append("%s two jobs share room %d" % [tag, t["room"]])
					rooms_used[t["room"]] = true
				if plan["guards"].size() != guards:
					bad.append("%s %d guard routes, wanted %d" % [tag, plan["guards"].size(), guards])
				for route in plan["guards"]:
					if route.size() < 2:
						bad.append("%s a guard route has %d stops" % [tag, route.size()])
					for c in route:
						if not reach.has(c):
							bad.append("%s guard stop %s is not floor" % [tag, c])
					for i in route.size():
						var a: Vector2i = route[i]
						var z: Vector2i = route[(i + 1) % route.size()]
						if a != z and b.path_len(a, z) < 2:
							bad.append("%s guard leg %s->%s has no path" % [tag, a, z])
				var walk: int = b.path_len(plan["player"], plan["exit"])
				if walk >= 26:
					long_walks += 1
				# the ring around every room stays open: the entry cell is open and not walled in
				if not b.is_open(plan["player"]):
					bad.append("%s entry blocked" % tag)
				b.queue_free()
	_check(bad.is_empty(), "%d generated buildings are playable (%s)" % [total, "; ".join(bad.slice(0, 4))])
	_check(room_counts.size() >= 3 and room_counts.keys().min() >= 9 and room_counts.keys().max() <= 12,
			"room counts vary inside 9-12: %s" % str(room_counts))
	_check(long_walks == total, "entry -> back door is a real walk (>= 26 steps, the open-floor minimum) in all %d (%d)" % [total, long_walks])
	# determinism: the same seed deals the same building
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


# --- 3. the night ----------------------------------------------------------------------------

func _new_night(lead: int, floor_no: int = 1, seed: int = 11) -> Node2D:
	Run.debug_seed = seed
	Run.choose_lead(lead)
	Run.begin_night()
	if floor_no == 2:
		Run.enter_lower_floor(80)
	var n: Node2D = NIGHT.instantiate()
	add_child(n)
	return n


func _drop_night(n: Node2D) -> void:
	n.queue_free()
	for a in ["interact", "descend", "takedown", "move_left", "move_right"]:
		Input.action_release(a)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_night() -> void:
	var n := _new_night(1)
	await _frames(4)
	var player: CharacterBody2D = n.get_node("Player")
	_check(n.tasks.size() == 3, "ministry night deals 3 jobs")
	_check(n.guards.size() == 3, "ministry night has 3 guards")
	for g in n.guards:
		g.set_physics_process(false)
	var hud: CanvasLayer = n.get_node("NightHud")
	_check(hud._jobs.text.count("[ ]") == 3 and hud._jobs.text.count("[x]") == 0, "the job list shows 3 open jobs")
	# --- a job by holding E ---
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
	_check(hud._jobs.text.count("[x]") == 1 and hud._ledger_pts.text.contains("%d PTS" % Run.unbanked_points()),
			"the HUD ticks the job off and shows the ledger")
	# --- alarm ladder -> reinforcements ---
	var guards_before: int = n.guards.size()
	Run._spot_cd = 0.0
	Run.register_spot()
	await _frames(3)
	_check(n.guards.size() == guards_before + 1, "ALERTED sends a reinforcement")
	_check(n.guards[-1]._state == n.guards[-1].State.CHASE, "the reinforcement hunts the PI's last position")
	# --- back door: leave now ---
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
	await _drop_night(n)

	# --- descend (alarm low) ---
	n = _new_night(1, 1, 12)
	await _frames(4)
	player = n.get_node("Player")
	door = n.get_node("BackDoor")
	for g in n.guards:
		g.set_physics_process(false)
	Run.add_intel(Run.Tier.LEADS)
	player.global_position = door.global_position
	await _frames(3)
	Input.action_press("descend")
	await _frames(3)
	Input.action_release("descend")
	_check(Run.floor_no == 2 and Run.carry_health == player.health and Run.unbanked_points() == 3 and Run.active,
			"Q descends: floor 2, health and the unbanked intel travel down")
	await _drop_night(n)
	n = _new_night(1, 2, 13)
	await _frames(4)
	player = n.get_node("Player")
	_check(n.tasks.size() == 2 and n.tasks[0].task_type == "evidence", "the lower floor deals the evidence cases")
	_check(n.guards.size() == 4, "the lower floor has one more guard than the building")
	_check(player.health == 80, "health arrived with the PI (80)")
	for g in n.guards:
		g.set_physics_process(false)
	# --- caught on the lower floor: only insurance ---
	Run.add_intel(Run.Tier.EVIDENCE)
	Run.add_intel(Run.Tier.EVIDENCE)
	player.capture()
	await _frames(3)
	_check(Run.last_result.get("outcome") == "caught" and Run.last_result.get("banked") == floori(19 * Run.INSURANCE),
			"caught below keeps only %d%% insurance (%d of %d)" % [int(Run.INSURANCE * 100.0), Run.last_result.get("banked", -1), Run.last_result.get("carried", -1)])
	await _drop_night(n)
	Run.debug_seed = -1


# --- 4. guard nav ------------------------------------------------------------------------------

func _test_guard_nav() -> void:
	var n := _new_night(2, 1, 21)
	await _frames(4)
	var player: CharacterBody2D = n.get_node("Player")
	player.global_position = Vector2(40, 40)
	var g: CharacterBody2D = n.guards[0]
	var route: Array = n.plan["guards"][0]
	var far: Vector2 = n.cell_world(route[route.size() - 1])
	if far.distance_to(g.global_position) < 80.0:
		far = n.cell_world(n.plan["exit"])
	# freeze the others, send ONE guard across the building and time him
	for o in n.guards:
		if o != g:
			o.set_physics_process(false)
	g.hunt(far)
	var start := g.global_position
	var frames := 0
	while frames < 1500 and g.global_position.distance_to(far) > 8.0:
		await get_tree().physics_frame
		frames += 1
	var direct := start.distance_to(far)
	_check(g.global_position.distance_to(far) <= 8.0, "a hunting guard threads the doorways to a far room (%d frames, %.0f px)" % [frames, direct])
	await _drop_night(n)
	Run.debug_seed = -1


# --- 5. the office -------------------------------------------------------------------------------

func _test_briefing() -> void:
	Run.choose_lead(1)
	var b: Control = BRIEFING.instantiate()
	add_child(b)
	await get_tree().process_frame
	_check(b.cards.size() == 3, "three leads are on the desk")
	_check(b.selected == 1, "the last lead stays selected")
	b._select(2)
	b.confirm(false)
	_check(Run.lead_idx == 2 and Run.active and Run.floor_no == 1, "taking a case sets the lead and begins the night")
	_check(Run.lead()["id"] == "customs", "lead 3 is the Customs House")
	b._select(5)
	_check(b.selected == 2, "selection wraps around the three cards")
	b.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _fails.is_empty():
		print("NIGHT: ALL PASS")
		get_tree().quit(0)
	else:
		print("NIGHT: %d FAIL" % _fails.size())
		get_tree().quit(1)
