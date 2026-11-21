extends CharacterBody2D
## A patrolling state guard. Composes the Rig (3-view sprite) and Vision
## (occluded flashlight) components; the AI here is the state machine
##
##   PATROL  walk the waypoint loop (straight lines, or A* through doorways
##           when night.gd hands in a nav grid)
##   CHASE   cone snaps red, alert beat, then runs at the last seen position
##   SEARCH  sweep the flashlight there, give up, resume the nearest waypoint
##
## Touching the PI during CHASE ends the night (player.capture). Sneak shrinks
## the detection range (Vision.RANGE_SNEAK); every speed / reach / pause is
## scaled by the alarm ladder in Run (all 1.0 outside a night).

signal sight_changed(state: int)  # 0 CLEAR, 1 SEEN, 2 SEARCHING
signal took_down

enum State { PATROL, CHASE, SEARCH }
enum Sight { CLEAR, SEEN, SEARCHING }

@export var patrol_points: PackedVector2Array = PackedVector2Array()
var nav: AStarGrid2D            # set by night.gd; null = walk straight (street probe)
const NAV_ORIGIN := Vector2(0, 4)   # the map's centring offset (see night.gd)

const PATROL_SPEED := 68.0     # px/s, a brisk march
const CHASE_SPEED := 150.0     # faster than sneak (92), slower than walk (185)
const ARRIVE_EPS := 5.0        # waypoint arrival threshold, px
const CAPTURE_RANGE := 14.0    # touch = caught, px
const SEARCH_TIME := 2.6       # s of sweeping before giving up
const ALERT_HOLD := 0.28       # s of the raised-flashlight "!" pose
const TURN_SPEED := 5.5        # rad/s - how fast the beam swings while patrolling
const TURN_CHASE := 12.0       # rad/s - hunting guards pivot much faster
const TURN_MOVE_ARC := 0.6     # rad - patrol walking starts once the beam is this close
const WAYPOINT_PAUSE := 0.5    # s - stop, look along the next leg, then walk
const TAKEDOWN_RANGE := 22.0   # px - how close the PI must be (OLD FRIEND adds reach)
const BODY := Vector2(10, 15)  # a hair under one tile, so cell-centre paths never graze
const TAKEDOWN_BEHIND_DOT := -0.2  # dot(beam, to-player) below this = behind him
const Z_ACTOR := 2             # body above every cone, incl. its own

# guard_sheet.png (256x480), 32x32 cells: patrol/chase/idle/alert x 3 views,
# then search side, ko, search down.
const ANIMS := {
        "patrol": {"row": 0, "frames": 8, "fps": 9.0, "loop": true, "views": true},
        "chase": {"row": 3, "frames": 8, "fps": 14.0, "loop": true, "views": true},
        "idle": {"row": 6, "frames": 4, "fps": 4.0, "loop": true, "views": true},
        "alert": {"row": 9, "frames": 4, "fps": 14.0, "loop": false, "views": true},
        "search_side": {"row": 12, "frames": 6, "fps": 5.0, "loop": true, "side": true},
        "ko": {"row": 13, "frames": 6, "fps": 10.0, "loop": false, "side": true},
        "search_down": {"row": 14, "frames": 6, "fps": 5.0, "loop": true},
}
const SHEET := preload("res://assets/sprites/guard_sheet.png")

var _rig: Rig
var _vision: Vision
var _down := false
var _state := State.PATROL
var _sight := Sight.CLEAR
var _target_wp := 0
var _last_seen := Vector2.ZERO
var _search_left := 0.0
var _alert_left := 0.0
var _pause_left := 0.0
var _sweep_t := 0.0
var _facing := Vector2.RIGHT
var _player: Node2D


func _ready() -> void:
        add_to_group("guards")
        # A real body: too bulky for a tight spot (the nav grid marks them solid).
        if get_node_or_null("Collision") == null:
                var cs := CollisionShape2D.new()
                cs.name = "Collision"
                var rs := RectangleShape2D.new()
                rs.size = BODY
                cs.shape = rs
                add_child(cs)
        _rig = Rig.new()
        add_child(_rig)
        _rig.setup(self, SHEET, 32, ANIMS, "patrol")
        _rig.sprite.z_index = Z_ACTOR
        _vision = Vision.new()
        add_child(_vision)
        _vision.setup(self)


func _physics_process(delta: float) -> void:
        if patrol_points.size() < 2:
                set_physics_process(false)
                return
        if _player == null:
                _player = get_tree().get_first_node_in_group("player")
                return
        var sees := _vision.sees(_player, beam_dir())
        match _state:
                State.PATROL:
                        if sees:
                                _enter_chase()
                        else:
                                _do_patrol(delta)
                State.CHASE:
                        if sees:
                                _last_seen = _player.global_position
                        if not sees and global_position.distance_to(_last_seen) < ARRIVE_EPS:
                                _enter_search()
                        else:
                                _do_chase(delta)   # he closes in even while he can see you
                State.SEARCH:
                        if sees:
                                _enter_chase()
                        else:
                                _do_search(delta)
        _update_sight(sees)
        _update_animation()
        _vision.update_cone(beam_dir())


# --- states -------------------------------------------------------------------

func _enter_chase() -> void:
        _state = State.CHASE
        _alert_left = ALERT_HOLD
        _last_seen = _player.global_position
        _facing = (_last_seen - global_position).normalized()
        _rig.set_facing(_facing)
        _rig.play("alert", true)   # one-shot startle: raised torch + "!"
        Run.register_spot()        # every NEW sighting climbs the alarm ladder


func _do_chase(delta: float) -> void:
        if _alert_left > 0.0:
                _alert_left = maxf(_alert_left - delta, 0.0)
                velocity = Vector2.ZERO
                _turn_toward(_last_seen - global_position, TURN_CHASE, delta)
                return
        var to_last := _last_seen - global_position
        var step := _steer(_last_seen)             # around walls when a nav grid exists
        _turn_toward(step, TURN_CHASE, delta)      # beam pivots, body runs
        velocity = step.normalized() * CHASE_SPEED * Run.chase_mult() if to_last.length() > 0.5 else Vector2.ZERO
        move_and_slide()
        if not _player.is_dead() \
                        and global_position.distance_to(_player.global_position) <= CAPTURE_RANGE:
                _player.capture()


func _enter_search() -> void:
        _state = State.SEARCH
        _search_left = SEARCH_TIME
        _sweep_t = 0.0
        velocity = Vector2.ZERO
        _pause_left = 0.0


func _do_search(delta: float) -> void:
        velocity = Vector2.ZERO
        _sweep_t += delta
        _search_left -= delta
        if _search_left <= 0.0:
                _enter_patrol()


func _enter_patrol() -> void:
        _state = State.PATROL
        # Resume from the nearest waypoint instead of backtracking the loop.
        var best := 0
        var best_d := INF
        for i in patrol_points.size():
                var d := global_position.distance_to(patrol_points[i])
                if d < best_d:
                        best_d = d
                        best = i
        _target_wp = best


func _do_patrol(delta: float) -> void:
        var goal := patrol_points[_target_wp]
        var to_t := _steer(goal)
        if _pause_left > 0.0:
                _pause_left = maxf(_pause_left - delta, 0.0)
                velocity = Vector2.ZERO
                _turn_toward(to_t, TURN_SPEED, delta)   # look along the next leg first
                return
        var to_goal := goal - global_position
        if to_goal.length() < ARRIVE_EPS:
                _target_wp = (_target_wp + 1) % patrol_points.size()
                _pause_left = WAYPOINT_PAUSE * Run.pause_mult()
                velocity = Vector2.ZERO
                return
        _turn_toward(to_t, TURN_SPEED, delta)
        if absf(angle_difference(_facing.angle(), to_t.angle())) < TURN_MOVE_ARC:
                velocity = to_t.normalized() * PATROL_SPEED * Run.patrol_mult()
                move_and_slide()
        else:
                velocity = Vector2.ZERO   # still swinging round - turn first, then walk


func hear(pos: Vector2) -> void:
        # A noise (ON AIR rule): anyone not already hunting goes to look.
        if _down or _state == State.CHASE:
                return
        hunt(pos)


func lose_track() -> void:
        # The PI slipped away (LUCKY COIN): every guard drops to searching.
        if _down:
                return
        _alert_left = 0.0
        if _state == State.CHASE:
                _enter_search()


func hunt(pos: Vector2) -> void:
        # Reinforcement / lockdown order: run to this spot as if you had just
        # lost the PI there. Sight picks the chase up again if he is in view.
        if _down:
                return
        _state = State.CHASE
        _alert_left = 0.0
        _last_seen = pos
        _pause_left = 0.0


# --- walking: straight (street) or A* around walls (building) ------------------------

func _steer(target: Vector2) -> Vector2:
        # Straight at the target when the way is clear, otherwise the farthest
        # visible point along the A* path (string-pulled, so no zig-zag).
        if nav == null or _clear_line(global_position, target):
                return target - global_position
        var from_c := _nav_cell(global_position)
        var to_c := _nav_cell(target)
        if nav.is_point_solid(from_c) or nav.is_point_solid(to_c):
                return target - global_position
        var path := nav.get_point_path(from_c, to_c)
        if path.size() < 2:
                return target - global_position
        var pick := path[1]
        for i in range(1, mini(path.size(), 8)):
                if _clear_line(global_position, path[i]):
                        pick = path[i]
                else:
                        break
        if global_position.distance_to(pick) < 3.0 and path.size() > 2:
                pick = path[2]
        return _clear_of_walls(pick) - global_position


func _clear_of_walls(p: Vector2) -> Vector2:
        # The body is 15 px tall and a row is 16: walking a row with a wall on one
        # side would graze by a pixel. Nudge toward the open side.
        var c := _nav_cell(p)
        var up := nav.is_point_solid(c + Vector2i.UP)
        var down := nav.is_point_solid(c + Vector2i.DOWN)
        if up and not down:
                return p + Vector2(0.0, 2.0)
        if down and not up:
                return p + Vector2(0.0, -2.0)
        return p


func _nav_cell(pos: Vector2) -> Vector2i:
        var c := Vector2i(floori((pos.x - NAV_ORIGIN.x) / 16.0), floori((pos.y - NAV_ORIGIN.y) / 16.0))
        return Vector2i(clampi(c.x, 0, nav.region.size.x - 1), clampi(c.y, 0, nav.region.size.y - 1))


func _clear_line(a: Vector2, b: Vector2) -> bool:
        # Three parallel rays (centre and +/- 9.5 px) so a guard never clips a corner.
        var space := get_world_2d().direct_space_state
        var dir := (b - a)
        if dir.length() < 1.0:
                return true
        var side := dir.normalized().orthogonal() * 9.5   # the body is up to 18 px across
        for off in [Vector2.ZERO, side, -side]:
                var q := PhysicsRayQueryParameters2D.create(a + off, b + off, 2)
                if not space.intersect_ray(q).is_empty():
                        return false
        return true


func _turn_toward(dir: Vector2, speed: float, delta: float) -> void:
        # Constant angular speed: the beam swings like a real flashlight.
        if dir.length() < 0.001:
                return
        var cur := _facing.angle()
        var diff := angle_difference(cur, dir.angle())
        var step := speed * delta
        _facing = Vector2.from_angle(cur + clampf(diff, -step, step))


func beam_dir() -> Vector2:
        if _state == State.SEARCH:
                return _facing.rotated(sin(_sweep_t * 2.6) * 0.9)   # flashlight sweep
        return _facing


# --- takedown ------------------------------------------------------------------

func can_be_taken_down(from: Vector2) -> bool:
        # Not down, not mid-chase, close, BEHIND the beam, no wall between you.
        if _down or _state == State.CHASE:
                return false
        var to_p := from - global_position
        if to_p.length() > TAKEDOWN_RANGE + Run.add("takedown_range_add"):
                return false
        if beam_dir().dot(to_p.normalized()) > TAKEDOWN_BEHIND_DOT + Run.add("takedown_dot_add"):
                return false
        var q := PhysicsRayQueryParameters2D.create(global_position, from, 2)
        return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func takedown() -> void:
        # Silent: out for the rest of the night, lying on the floor.
        if _down:
                return
        _down = true
        Run.note_takedown()
        remove_from_group("guards")
        set_physics_process(false)
        collision_layer = 0
        collision_mask = 0
        velocity = Vector2.ZERO
        _vision.cone.visible = false
        _sight = Sight.CLEAR
        sight_changed.emit(_sight)   # tells the HUD to drop his OBSERVED / SEARCHING state
        _rig.set_facing(_facing)
        _rig.play("ko", true)
        _rig.sprite.z_index = 1      # a body on the floor: the PI walks OVER him
        took_down.emit()


# --- presentation -------------------------------------------------------------

func _update_sight(sees: bool) -> void:
        var new_sight: int
        if sees or _state == State.CHASE:
                new_sight = Sight.SEEN
        elif _state == State.SEARCH:
                new_sight = Sight.SEARCHING
        else:
                new_sight = Sight.CLEAR
        if new_sight != _sight:
                _sight = new_sight
                sight_changed.emit(_sight)
        if sees or _state == State.CHASE:
                _vision.set_color("seen")
        elif _state == State.SEARCH:
                _vision.set_color("search")
        else:
                _vision.set_color("calm")


func _update_animation() -> void:
        _rig.set_facing(_facing)
        _rig.sprite.speed_scale = 1.0
        var speed := velocity.length()
        if _state == State.CHASE and _alert_left > 0.0:
                _play("alert")
        elif _state == State.CHASE:
                _play("chase")
                _rig.sprite.speed_scale = clampf(speed / CHASE_SPEED, 0.6, 1.4) if speed > 1.0 else 1.0
        elif _state == State.SEARCH:
                # Only side and front searches are drawn; facing away, he just idles.
                _play("search_side" if _rig.view == "side" else ("search_down" if _rig.view == "down" else "idle"))
        elif speed > 1.0:
                _play("patrol")
        else:
                _play("idle")


func _play(base: String) -> void:
        _rig.play(base)
