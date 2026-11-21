extends Node2D
## One night in the building: deals the floor, plants the PI, the jobs, the
## back door and the patrols, then watches the alarm ladder, the door decision
## and the PI. Descending reloads this scene on floor 2; R re-deals the night.

const TILE := 16
const MAP_OFFSET := Vector2(0, 4)
const GUARD_SCENE := preload("res://scenes/guard.tscn")
const TASK_SCENE := preload("res://scenes/task_spot.tscn")
const RING := preload("res://scripts/noise_ring.gd")
const PAUSE_MENU := preload("res://scenes/pause_menu.tscn")
const WORLD_SCRIPT := preload("res://scripts/building_builder.gd")

signal descended
signal reinforcement_arrived(count: int)

@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $Player
@onready var _door: Node2D = $BackDoor
@onready var _hud: CanvasLayer = $NightHud

var plan: Dictionary = {}
var curfew_left := 0.0               # seconds to the next CURFEW bell (CURFEW rule)
var guards: Array = []              # every guard on this floor (patrols + reinforcements)
var reinforcements: Array = []
var tasks: Array = []
var _pause: CanvasLayer


func _ready() -> void:
        _pause = PAUSE_MENU.instantiate()
        add_child(_pause)
        if not Run.active:
                Run.ensure_case()
                Run.begin_night()           # launched straight from the editor / a test
        var lead: Dictionary = Run.case
        var lower: bool = Run.floor_no >= 2
        var params := {"floor": Run.floor_no}
        if Run.rule() == "blackout":
                params["atlas"] = WORLD_SCRIPT.ATLAS_BLACKOUT   # the darkest bake
        elif lower:
                params["atlas"] = WORLD_SCRIPT.ATLAS_DEEP       # cold lower floor
        if lower:
                var cases: Array = []
                for i in int(lead["evidence"]):
                        cases.append("evidence")
                params["tasks"] = cases
                params["guards"] = int(lead["guards"]) + 1 + Run.guard_bonus()
        else:
                params["tasks"] = lead["tasks"]
                params["guards"] = int(lead["guards"]) + Run.guard_bonus()
        plan = _world.generate(Run.debug_seed, params)   # -1 = a fresh building every night
        _apply_plan(lead)
        _hud.bind_world()
        if lower:
                _player.health = Run.carry_health
        curfew_left = Run.CURFEW_EVERY
        _player.squeeze_cells = plan["squeeze"]
        Run.noise_made.connect(_on_noise)
        Run.second_chance_used.connect(_on_second_chance)
        _player.died.connect(_on_player_died)
        _door.extracted.connect(_on_extracted)
        _door.descend_requested.connect(_on_descend)
        Run.alarm_changed.connect(_on_alarm_changed)
        # Arriving on the lower floor already ALERTED: the building is waiting.
        for i in Run.extra_guards():
                _spawn_reinforcement(false)
        print("NIGHT floor=%d rooms=%d player=%s exit=%s tasks=%s" % [
                Run.floor_no, plan["rooms"], plan["player"], plan["exit"], _task_summary(),
        ])


func _process(delta: float) -> void:
        # CURFEW: the bell tolls and the alarm climbs by itself.
        if Run.active and Run.rule() == "curfew" and not _player.is_dead() and not _player.won:
                curfew_left -= delta
                if curfew_left <= 0.0:
                        curfew_left = Run.CURFEW_EVERY
                        if Run.raise_alarm() and _hud.has_method("flash"):
                                _hud.flash("CURFEW BELL - the alarm climbs", Color("e8b366"))


func _on_noise(pos: Vector2, radius: float) -> void:
        # ON AIR: everyone within earshot (and not already hunting) goes to look.
        var ring: Node2D = RING.new()
        ring.radius = radius
        add_child(ring)
        ring.global_position = pos
        for g in guards:
                if is_instance_valid(g) and g.global_position.distance_to(pos) <= radius:
                        g.hear(pos)


func _on_second_chance() -> void:
        if _hud.has_method("flash"):
                _hud.flash("LUCKY COIN - you slip away", Color("e8b366"))


func _unhandled_input(event: InputEvent) -> void:
        if event.is_action_pressed("pause") and Run.active:
                get_viewport().set_input_as_handled()
                _pause.open_menu()


func _exit_tree() -> void:
        if Run.alarm_changed.is_connected(_on_alarm_changed):
                Run.alarm_changed.disconnect(_on_alarm_changed)


func cell_world(cell: Vector2i) -> Vector2:
        # The ONE world-position rule: cell centre + the map's (0, 4) offset.
        return Vector2(cell.x * TILE + 8, cell.y * TILE + 8) + MAP_OFFSET


func _apply_plan(lead: Dictionary) -> void:
        _player.global_position = cell_world(plan["player"])
        _player._set_facing(Vector2.RIGHT if Run.floor_no == 1 else Vector2.LEFT)
        _player._play("idle", true)
        _door.global_position = cell_world(plan["exit"])
        _door.floor_no = Run.floor_no
        _door.evidence_cases = int(lead["evidence"])
        for t in plan["tasks"]:
                var spot := TASK_SCENE.instantiate()
                spot.task_type = t["type"]
                add_child(spot)
                spot.global_position = cell_world(t["cell"])
                tasks.append(spot)
        for route in plan["guards"]:
                guards.append(_make_guard(route))


func _make_guard(route: Array) -> CharacterBody2D:
        var g: CharacterBody2D = GUARD_SCENE.instantiate()
        var pts := PackedVector2Array()
        for cell in route:
                pts.append(cell_world(cell))
        g.nav = plan["nav"]
        g.patrol_points = pts
        add_child(g)
        g.global_position = pts[0]
        return g


func _task_summary() -> String:
        var s := ""
        for t in plan["tasks"]:
                s += "%s@%s " % [t["type"], t["cell"]]
        return s.strip_edges()


# --- the alarm ladder ---------------------------------------------------------------------

func _on_alarm_changed(tier: int) -> void:
        if tier <= 0:
                return
        while reinforcements.size() < Run.extra_guards():
                _spawn_reinforcement(true)
        if tier >= Run.MAX_ALARM:
                # LOCKDOWN: every guard on the floor converges on the PI.
                for g in guards:
                        if is_instance_valid(g):
                                g.hunt(_player.global_position)
        if _hud.has_method("flash"):
                var msg := "ALARM: %s" % Run.ALARM_NAMES[tier]
                match tier:
                        1:
                                msg += " - reinforcements on the floor"
                        2:
                                msg += " - patrols are quicker, beams reach further"
                        3:
                                msg += " - the lower floor is sealed"
                _hud.flash(msg)


func _spawn_reinforcement(hunt: bool) -> void:
        # They come from the room farthest from the PI, loop three rooms, and
        # (when the ladder just climbed) start by running to where the PI is.
        var centers: Array = plan["room_centers"]
        var best: Vector2i = centers[0]
        var best_d := -1.0
        for c in centers:
                var d := cell_world(c).distance_to(_player.global_position)
                if d > best_d:
                        best_d = d
                        best = c
        var route: Array = [best]
        var tries := 0
        while route.size() < 3 and tries < 30:
                tries += 1
                var o: Vector2i = centers[randi() % centers.size()]
                if not route.has(o):
                        route.append(o)
        var g := _make_guard(route)
        guards.append(g)
        reinforcements.append(g)
        if hunt:
                g.hunt(_player.global_position)
        reinforcement_arrived.emit(reinforcements.size())


# --- the end of the night -------------------------------------------------------------------

func _on_player_died() -> void:
        Run.finish("caught")


func _on_extracted() -> void:
        Run.finish("extracted")


func _on_descend() -> void:
        Run.enter_lower_floor(_player.health)
        descended.emit()
        if _hud.has_method("fade_out"):
                _hud.fade_out()
        # Only the live scene reloads itself; the headless night test instances
        # this scene as a child and reads Run.floor_no instead.
        if get_tree().current_scene == self:
                await get_tree().create_timer(0.35).timeout
                get_tree().reload_current_scene()
