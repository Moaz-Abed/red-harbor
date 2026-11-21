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
## Metal Gear feel (smooth pass): the beam TURNS at a fixed angular speed
## instead of snapping, guards stop at each waypoint and look toward the next
## leg before walking, and the sprite shows one of 3 drawn views
## (down / up / side) that follows the beam.
##
## Night mode (building): `nav` is an AStarGrid2D the night scene hands in, so
## patrols and chases walk THROUGH doorways around walls and furniture instead
## of in straight lines; hunt(pos) sends a guard to a spot as if he had just
## lost the PI there (reinforcements, lockdown). Every speed / reach / pause
## is scaled by the alarm ladder in the Run autoload (all 1.0 outside a night).
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
var nav: AStarGrid2D            # set by night.gd; null = walk straight (street probe)
const NAV_ORIGIN := Vector2(0, 4)   # the map's centring offset (see night.gd)

const PATROL_SPEED := 68.0     # px/s, a brisk march (the whole game runs faster)
const CHASE_SPEED := 150.0     # faster than sneak (92), slower than walk (185) and a dash
const ARRIVE_EPS := 5.0        # waypoint arrival threshold, px
const CONE_RANGE := 130.0      # flashlight reach, px
const CONE_RANGE_SNEAK := 62.0 # detection reach vs a sneaking player, px
const CONE_HALF_ANGLE := 0.56  # rad, ~32 degrees each side of the beam
const CAPTURE_RANGE := 14.0    # touch = caught, px
const SEARCH_TIME := 2.6       # seconds of sweeping before giving up
const ALERT_HOLD := 0.28       # seconds of the raised-flashlight "!" pose
const CONE_STEPS := 20         # raycast fan resolution (art occlusion)
const TURN_SPEED := 5.5        # rad/s - how fast the beam swings while patrolling
const TURN_CHASE := 12.0       # rad/s - hunting guards pivot much faster
const TURN_MOVE_ARC := 0.6     # rad - patrol walk only starts once the beam is this close
const WAYPOINT_PAUSE := 0.5    # s - the guard stops, looks along the next leg, then walks
const TAKEDOWN_RANGE := 22.0   # px - how close the PI must be (OLD FRIEND adds reach)
const BODY := Vector2(10, 15)  # a hair under one tile, so cell-centre path-following never grazes a wall
const TAKEDOWN_BEHIND_DOT := -0.2  # dot(beam, to-player) must be BELOW this = behind him

# guard_sheet.png (256 x 480): 32x32 cells, 8 columns. Rows:
#   0..2 patrol (8)   3..5 chase (8)   6..8 idle (4)   9..11 alert (4)   [x down, up, side]
#   12 search side (6)   13 ko (6, side)   14 search down (6)
# The "side" view is drawn facing RIGHT; flip_h turns it left.
const VIEWS := ["down", "up", "side"]
const ANIMS := {
        "patrol": {"row": 0, "frames": 8, "fps": 9.0, "loop": true, "views": true},
        "chase": {"row": 3, "frames": 8, "fps": 14.0, "loop": true, "views": true},
        "idle": {"row": 6, "frames": 4, "fps": 4.0, "loop": true, "views": true},
        "alert": {"row": 9, "frames": 4, "fps": 14.0, "loop": false, "views": true},
        "search_side": {"row": 12, "frames": 6, "fps": 5.0, "loop": true},
        "search_down": {"row": 14, "frames": 6, "fps": 5.0, "loop": true},
        "ko": {"row": 13, "frames": 6, "fps": 10.0, "loop": false},
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
var _pause_left := 0.0
var _view := "side"
var _face_left := false
var _anim_base := "patrol"
var _sweep_t := 0.0
var _facing := Vector2.RIGHT
var _player: Node2D
var _sprite: AnimatedSprite2D
var _cone: Polygon2D
var _ray: RayCast2D


func _ready() -> void:
        add_to_group("guards")
        # A real body: guards no longer slip through walls or furniture. The
        # collider is a hair under one tile (10 x 15) so following A* cell
        # centres never grazes a wall; what keeps them OUT of a tight spot is the
        # nav grid (squeeze cells are solid to it), exactly as they are too
        # bulky to crawl.
        if get_node_or_null("Collision") == null:
                var cs := CollisionShape2D.new()
                cs.name = "Collision"
                var rs := RectangleShape2D.new()
                rs.size = BODY
                cs.shape = rs
                add_child(cs)
        _sprite = AnimatedSprite2D.new()
        _sprite.sprite_frames = _build_frames()
        _play("patrol")
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
                if cfg.get("views", false):
                        for v in VIEWS.size():
                                _add_anim(sf, "%s_%s" % [anim_name, VIEWS[v]], cfg, int(cfg["row"]) + v)
                else:
                        _add_anim(sf, anim_name, cfg, int(cfg["row"]))
        return sf


func _add_anim(sf: SpriteFrames, anim_name: String, cfg: Dictionary, row: int) -> void:
        sf.add_animation(anim_name)
        sf.set_animation_speed(anim_name, cfg["fps"])
        sf.set_animation_loop(anim_name, cfg["loop"])
        for col in int(cfg["frames"]):
                var at := AtlasTexture.new()
                at.atlas = SHEET
                at.region = Rect2(col * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
                sf.add_frame(anim_name, at)


func _set_view(dir: Vector2) -> void:
        # Same rule as the player: near-diagonals keep the current view.
        if dir.length() < 0.1:
                return
        var ax := absf(dir.x)
        var ay := absf(dir.y)
        if ax > ay * 1.1:
                _view = "side"
        elif ay > ax * 1.1:
                _view = "down" if dir.y > 0.0 else "up"
        if ax > 0.2:
                _face_left = dir.x < 0.0


func _anim_name(base: String) -> String:
        if base == "ko":
                return "ko"
        if base == "search":
                # Only side and front searches are drawn; a guard facing away just idles.
                if _view == "side":
                        return "search_side"
                if _view == "down":
                        return "search_down"
                return "idle_up"
        return "%s_%s" % [base, _view]


func _play(base: String, force: bool = false) -> void:
        var anim := _anim_name(base)
        if force or _sprite.animation != anim:
                # Turning mid-stride keeps the walk phase (no stutter at corners).
                var keep := (not force) and base == _anim_base and (base == "patrol" or base == "chase")
                var f := _sprite.frame
                var prog := _sprite.frame_progress
                _sprite.play(anim)
                if keep:
                        _sprite.set_frame_and_progress(f, prog)
        _anim_base = base
        _sprite.flip_h = (_view == "side" or base == "ko") and _face_left


func _turn_toward(dir: Vector2, speed: float, delta: float) -> void:
        # Constant angular speed: the beam swings like a real flashlight.
        if dir.length() < 0.001:
                return
        var cur := _facing.angle()
        var diff := angle_difference(cur, dir.angle())
        var step := speed * delta
        _facing = Vector2.from_angle(cur + clampf(diff, -step, step))


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
        var eff_range := (CONE_RANGE_SNEAK if _player.is_sneaking() else CONE_RANGE) * Run.range_mult()
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
        _set_view(_facing)
        _play("alert", true)   # one-shot startle: raised torch + "!"
        Run.register_spot()    # every NEW sighting climbs the alarm ladder


func _do_chase(delta: float) -> void:
        if _alert_left > 0.0:
                # The "spotted" beat: freeze one frame-worth, cone already red.
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
        var to_goal := goal - global_position
        var to_t := _steer(goal)
        if _pause_left > 0.0:
                # Standing at a waypoint: look along the next leg (smooth turn), then go.
                _pause_left = maxf(_pause_left - delta, 0.0)
                velocity = Vector2.ZERO
                _turn_toward(to_t, TURN_SPEED, delta)
                return
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
        # A noise (ON AIR rule): anyone who is not already hunting goes to look.
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
        # lost the PI there. Sight picks the chase up again if he is still in view.
        if _down:
                return
        _state = State.CHASE
        _alert_left = 0.0
        _last_seen = pos
        _pause_left = 0.0


# --- walking: straight (street) or A* around walls (building) -----------------------

func _steer(target: Vector2) -> Vector2:
        # The direction to walk to reach `target`. No nav grid -> straight at it.
        # With one: straight if the way is clear, otherwise the farthest visible
        # point along the A* path (string-pulled, so guards don't zig-zag cell by
        # cell and stall on every 45 degree turn).
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
        # The body is 18 px tall and a row is 16: walking the CENTRE of a row that has
        # a wall on one side would graze it by a pixel and wedge. Nudge the target
        # toward the open side so there is always daylight.
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
        # Three parallel rays (centre and +/- 5 px) so a guard never clips a corner.
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


# --- takedown ------------------------------------------------------------------

func can_be_taken_down(from: Vector2) -> bool:
        # Rules: not already down, not mid-chase (he is facing you anyway),
        # close, BEHIND the beam, and no wall between you.
        if _down or _state == State.CHASE:
                return false
        var to_p := from - global_position
        if to_p.length() > TAKEDOWN_RANGE + Run.add("takedown_range_add"):
                return false
        if _cone_dir().dot(to_p.normalized()) > TAKEDOWN_BEHIND_DOT + Run.add("takedown_dot_add"):
                return false
        var q := PhysicsRayQueryParameters2D.create(global_position, from, 2)
        return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func takedown() -> void:
        # Silent: he is out for the rest of the night (roadmap 4.1). He stays on
        # the floor as a dark, lying sprite until a real KO frame exists (art TODO).
        if _down:
                return
        _down = true
        Run.note_takedown()
        remove_from_group("guards")
        set_physics_process(false)
        collision_layer = 0
        collision_mask = 0
        velocity = Vector2.ZERO
        _cone.visible = false
        _sight = Sight.CLEAR
        sight_changed.emit(_sight)   # tells the HUD to drop his OBSERVED / SEARCHING state
        _set_view(_facing)
        _play("ko", true)             # stagger, buckle, fall, lie (6 frames)
        _sprite.z_index = 1           # a body on the floor: the PI walks OVER him
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
        var reach := CONE_RANGE * Run.range_mult()
        _ray.target_position = dir * reach
        _ray.force_raycast_update()
        if _ray.is_colliding():
                return global_position.distance_to(_ray.get_collision_point())
        return reach


func _update_animation() -> void:
        _set_view(_facing)
        _sprite.speed_scale = 1.0
        var speed := velocity.length()
        if _state == State.CHASE and _alert_left > 0.0:
                _play("alert")
        elif _state == State.CHASE:
                _play("chase")
                _sprite.speed_scale = clampf(speed / CHASE_SPEED, 0.6, 1.4) if speed > 1.0 else 1.0
        elif _state == State.SEARCH:
                _play("search")
        elif speed > 1.0:
                _play("patrol")
        else:
                _play("idle")
