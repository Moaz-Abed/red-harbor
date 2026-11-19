extends CharacterBody2D
## Red Harbor - a patrolling state guard (P2 probe, occluded cone in P3).
##
## The guard walks a waypoint loop holding a flashlight (the vision cone).
## He sees the player when: inside cone range, inside the cone half-angle,
## with clear line of sight (raycast vs the world layer).
## Sneaking shrinks the EFFECTIVE detection range (the cone art stays the
## same size - you learn the safe distance by playing, not by reading the
## debug geometry).
##
## State machine:
##   PATROL  - walk the waypoint loop, cone in fog gray.
##   CHASE   - cone snaps red, brief "alert" pose, then runs to the player.
##             Keeps chasing the LAST SEEN position if sight is lost.
##   SEARCH  - reached the last seen position, sweeps the flashlight,
##             gives up after SEARCH_TIME and returns to the nearest waypoint.
##
## If he touches the player during CHASE, the night is over (player.capture).
## The cone ART is drawn with a raycast fan: every frame we cast rays across
## the arc and clip each vertex at the first wall it hits (layer 2). What you
## see lit is what he can actually see - the art and the detection share one
## geometry now that walls are real tiles (level_builder.gd).

signal sight_changed(state: int)  # 0 CLEAR, 1 SEEN (chasing), 2 SEARCHING
signal took_down

enum State { PATROL, CHASE, SEARCH }
enum Sight { CLEAR, SEEN, SEARCHING }

@export var patrol_points: PackedVector2Array = PackedVector2Array()

const PATROL_SPEED := 55.0     # px/s, deliberate march
const CHASE_SPEED := 110.0     # faster than sneak (78), slower than walk (150)
const ARRIVE_EPS := 5.0        # waypoint arrival threshold, px
const CONE_RANGE := 130.0      # flashlight reach, px
const CONE_RANGE_SNEAK := 62.0 # detection reach vs a sneaking player, px
const CONE_HALF_ANGLE := 0.56  # rad, ~32 degrees each side of the beam
const CAPTURE_RANGE := 14.0    # touch = caught, px
const SEARCH_TIME := 2.6       # seconds of sweeping before giving up
const ALERT_HOLD := 0.28       # seconds of the raised-flashlight "!" pose
const CONE_STEPS := 20         # raycast fan resolution (art occlusion)
const TAKEDOWN_RANGE := 22.0   # px - how close the PI must be
const TAKEDOWN_BEHIND_DOT := -0.2  # dot(beam, to-player) must be BELOW this = behind him

const ANIMS := {
        "patrol": {"frames": [0, 1], "fps": 3.0, "loop": true},
        "alert": {"frames": [2], "fps": 1.0, "loop": false},
        "chase": {"frames": [3, 4], "fps": 9.0, "loop": true},
        "search": {"frames": [5], "fps": 1.0, "loop": false},
}
const FRAME_SIZE := 32
const SHEET := preload("res://assets/sprites/guard_sheet.png")

# Screen layering contract (z_index): floor tiles sit at 0, the cone paints
# ABOVE the floor (1), and every actor sprite stands above the light (2).
# FIX (invisible-cone regression): the cone used z_index = -1, which is
# GLOBAL - it slid the whole flashlight UNDER the tilemap's z = 0 floor
# tiles, so the player never saw the thing that was hunting him.
const Z_CONE := 1
const Z_ACTOR := 2

# Cone fills tuned to stay READABLE on dark asphalt (the old 0.16-alpha fog
# cone vanished against the floor even after the z fix).
const CONE_COLOR_CALM := Color(0.6, 0.56, 0.65, 0.30)      # fog, screen-bright
const CONE_COLOR_SEEN := Color(0.88, 0.3, 0.26, 0.55)      # alarm red, screen-bright
const CONE_COLOR_SEARCH := Color(0.88, 0.3, 0.26, 0.35)    # red, dimmer

var _down := false
var _state := State.PATROL
var _sight := Sight.CLEAR
var _target_wp := 0
var _last_seen := Vector2.ZERO
var _search_left := 0.0
var _alert_left := 0.0
var _sweep_t := 0.0
var _facing := Vector2.RIGHT
var _player: Node2D
var _sprite: AnimatedSprite2D
var _cone: Polygon2D
var _ray: RayCast2D


func _ready() -> void:
        add_to_group("guards")
        _sprite = AnimatedSprite2D.new()
        _sprite.sprite_frames = _build_frames()
        _sprite.play("patrol")
        _sprite.z_index = Z_ACTOR   # body above every cone, incl. its own
        add_child(_sprite)

        # The cone renders above the floor but below every actor sprite.
        _cone = Polygon2D.new()
        _cone.z_index = Z_CONE
        _cone.color = CONE_COLOR_CALM
        add_child(_cone)

        # Detection raycast: only the world layer blocks sight (mask = 2).
        _ray = RayCast2D.new()
        _ray.collision_mask = 2
        _ray.enabled = false
        add_child(_ray)


func _build_frames() -> SpriteFrames:
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        for anim_name in ANIMS:
                var cfg: Dictionary = ANIMS[anim_name]
                sf.add_animation(anim_name)
                sf.set_animation_speed(anim_name, cfg["fps"])
                sf.set_animation_loop(anim_name, cfg["loop"])
                for idx in cfg["frames"]:
                        var at := AtlasTexture.new()
                        at.atlas = SHEET
                        at.region = Rect2(idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
                        sf.add_frame(anim_name, at)
        return sf


func _physics_process(delta: float) -> void:
        if patrol_points.size() < 2:
                set_physics_process(false)
                return
        if _player == null:
                _player = get_tree().get_first_node_in_group("player")
                return
        var sees := _check_vision()
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
                                # BUGFIX: he used to stand still while he could SEE you and only
                                # advanced when you were out of sight. Now he always closes in.
                                _do_chase(delta)
                State.SEARCH:
                        if sees:
                                _enter_chase()
                        else:
                                _do_search(delta)
        _update_sight(sees)
        _update_animation()
        _update_cone(delta)


# --- vision -------------------------------------------------------------------

func _check_vision() -> bool:
        if _player == null or _player.is_dead():
                return false
        var to_p := _player.global_position - global_position
        var eff_range := CONE_RANGE_SNEAK if _player.is_sneaking() else CONE_RANGE
        if to_p.length() > eff_range:
                return false
        # BUGFIX: use the drawn beam, not _facing - during SEARCH the flashlight
        # sweeps, so detection and cone art must share the same direction.
        if absf(_cone_dir().angle_to(to_p.normalized())) > CONE_HALF_ANGLE:
                return false
        _ray.target_position = _ray.to_local(_player.global_position)
        _ray.force_raycast_update()
        if _ray.is_colliding() and _ray.get_collider() != _player:
                return false   # a wall blocks the flashlight
        return true


# --- states -------------------------------------------------------------------

func _enter_chase() -> void:
        _state = State.CHASE
        _alert_left = ALERT_HOLD
        _last_seen = _player.global_position
        _facing = (_last_seen - global_position).normalized()


func _do_chase(delta: float) -> void:
        if _alert_left > 0.0:
                # The "spotted" beat: freeze one frame-worth, cone already red.
                _alert_left = maxf(_alert_left - delta, 0.0)
                velocity = Vector2.ZERO
                return
        var to_last := _last_seen - global_position
        if to_last.length() > 0.5:   # never let _facing collapse to ZERO
                _facing = to_last.normalized()
        velocity = _facing * CHASE_SPEED
        move_and_slide()
        if not _player.is_dead() \
                        and global_position.distance_to(_player.global_position) <= CAPTURE_RANGE:
                _player.capture()


func _enter_search() -> void:
        _state = State.SEARCH
        _search_left = SEARCH_TIME
        _sweep_t = 0.0
        velocity = Vector2.ZERO


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


func _do_patrol(_delta: float) -> void:
        var target := patrol_points[_target_wp]
        var to_t := target - global_position
        if to_t.length() < ARRIVE_EPS:
                _target_wp = (_target_wp + 1) % patrol_points.size()
                return   # one-frame hitch = deliberate march feel
        _facing = to_t.normalized()
        velocity = _facing * PATROL_SPEED
        move_and_slide()


# --- takedown ------------------------------------------------------------------

func can_be_taken_down(from: Vector2) -> bool:
        # Rules: not already down, not mid-chase (he is facing you anyway),
        # close, BEHIND the beam, and no wall between you.
        if _down or _state == State.CHASE:
                return false
        var to_p := from - global_position
        if to_p.length() > TAKEDOWN_RANGE:
                return false
        if _cone_dir().dot(to_p.normalized()) > TAKEDOWN_BEHIND_DOT:
                return false
        var q := PhysicsRayQueryParameters2D.create(global_position, from, 2)
        return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func takedown() -> void:
        # Silent: he is out for the rest of the night (roadmap 4.1). He stays on
        # the floor as a dark, lying sprite until a real KO frame exists (art TODO).
        if _down:
                return
        _down = true
        remove_from_group("guards")
        set_physics_process(false)
        collision_layer = 0
        collision_mask = 0
        velocity = Vector2.ZERO
        _cone.visible = false
        _sight = Sight.CLEAR
        sight_changed.emit(_sight)   # tells the HUD to drop his OBSERVED / SEARCHING state
        _sprite.play("search")
        _sprite.rotation = (PI / 2.0) * (-1.0 if _sprite.flip_h else 1.0)
        _sprite.modulate = Color(0.55, 0.55, 0.7)
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
        if sees:
                _cone.color = CONE_COLOR_SEEN
        elif _state == State.SEARCH:
                _cone.color = CONE_COLOR_SEARCH
        else:
                _cone.color = CONE_COLOR_CALM


func _cone_dir() -> Vector2:
        if _state == State.SEARCH:
                # Flashlight sweep while searching the last seen spot.
                return _facing.rotated(sin(_sweep_t * 2.6) * 0.9)
        return _facing


func _update_cone(delta: float) -> void:
        var dir := _cone_dir()
        var pts := PackedVector2Array([Vector2.ZERO])
        for i in range(CONE_STEPS + 1):
                var a := -CONE_HALF_ANGLE + 2.0 * CONE_HALF_ANGLE * i / CONE_STEPS
                var d := dir.rotated(a)
                pts.append(d * _cast_ray(d))
        _cone.polygon = pts


func _cast_ray(dir: Vector2) -> float:
        # One ray of the cone fan: range to the first wall, or full range.
        # Shares the same RayCast2D as _check_vision - calls are sequential,
        # so there is no state bleed between detection and the cone art.
        _ray.target_position = dir * CONE_RANGE
        _ray.force_raycast_update()
        if _ray.is_colliding():
                return global_position.distance_to(_ray.get_collision_point())
        return CONE_RANGE


func _update_animation() -> void:
        if _facing.x != 0.0:
                _sprite.flip_h = _facing.x < 0.0
        if _state == State.CHASE and _alert_left > 0.0:
                _sprite.play("alert")
        elif _state == State.CHASE:
                _sprite.play("chase")
        elif _state == State.SEARCH:
                _sprite.play("search")
        else:
                _sprite.play("patrol")
