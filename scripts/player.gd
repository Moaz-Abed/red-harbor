extends CharacterBody2D
## The PI: fast arcade movement (walk 185 / dash 520 for 4 tiles), sneak, the
## belly crawl through tight spots, takedowns with hit-stop and shake, and the
## Doom-style portrait health (no healthbar). Composes the Health and Rig
## components; boons and drawer upgrades scale everything through Run.mult().

signal health_changed(current: int, max_health: int)
signal intel_changed(count: int, max_intel: int)
signal died

const MOVE_SPEED := 185.0    # walk speed, px/s - fast, arcade
const SNEAK_SPEED := 92.0    # crouch speed, px/s
const CRAWL_SPEED := 78.0    # belly-crawl speed through a tight spot, px/s
const ACCEL := 3200.0        # px/s^2 to reach walk speed
const FRICTION := 3600.0     # px/s^2 to stop - snappy arcade stop
const DASH_SPEED := 520.0    # px/s
const DASH_TIME := 0.125     # s - 520 * 0.125 = 65 px = 4 tiles (roadmap)
const DASH_COOLDOWN := 0.24  # s before the next dash
const DASH_BUFFER := 0.12    # a dash pressed this early still fires on cooldown end
const DASH_IFRAMES := true   # nothing catches / hurts you mid-dash
const GHOST_EVERY := 0.03    # s between dash afterimages
const GHOST_FADE := 0.18     # s an afterimage lingers
const HITSTOP_TAKEDOWN := 0.06
const HITSTOP_CAPTURE := 0.08
const SHAKE_TAKEDOWN := 3.0
const SHAKE_CAPTURE := 4.0
const SHAKE_HURT := 2.0
const MAX_HEALTH := 100
const MAX_INTEL := 3
const HURT_INVULN := 0.5     # s of i-frames after a hit
const HURT_ANIM := 0.25      # s the hurt pose holds
const TAKEDOWN_ANIM := 0.2   # s of the grab animation
const MAP_OFFSET := Vector2(0, 4)   # the building map is centred 4 px down
const GRACE := 1.4           # s nothing can catch you after LUCKY COIN saves you
const TAKEDOWN_MOVE_MULT := 0.25    # feet plant while the grab plays
const Z_ACTOR := 2           # actor layer - see comps/vision.gd for the z contract

# player_sheet.png (256x640), 32x32 cells: rows are anim x view
# (idle, walk, sneak, dash, takedown, hurt) x (down, up, side), then dead and
# squeeze (side-drawn). Regenerate with assets_src/gen_sprites.py.
const ANIMS := {
	"idle": {"row": 0, "frames": 4, "fps": 4.0, "loop": true, "views": true},
	"walk": {"row": 3, "frames": 8, "fps": 12.0, "loop": true, "views": true},
	"sneak": {"row": 6, "frames": 6, "fps": 8.0, "loop": true, "views": true},
	"dash": {"row": 9, "frames": 4, "fps": 32.0, "loop": false, "views": true},
	"takedown": {"row": 12, "frames": 4, "fps": 16.0, "loop": false, "views": true},
	"hurt": {"row": 15, "frames": 2, "fps": 8.0, "loop": false, "views": true},
	"dead": {"row": 18, "frames": 6, "fps": 9.0, "loop": false, "side": true},
	"squeeze": {"row": 19, "frames": 6, "fps": 10.0, "loop": true, "side": true},
}
const SHEET := preload("res://assets/sprites/player_sheet.png")

var intel := 0
var sneaking := false
var squeeze_cells: Dictionary = {}   # Vector2i -> true; night.gd hands the tight spots in
var squeezing := false
var won := false                    # extraction succeeded - the night is over
var _hp: Health
var _rig: Rig
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _col: CollisionShape2D
var _stand_shape: Shape2D
var _crawl_shape: RectangleShape2D
var _grace_left := 0.0
var _dash_dir := Vector2.ZERO
var _dash_buffer_left := 0.0
var _ghost_timer := 0.0
var _last_dir := Vector2.RIGHT
var _hitstop_active := false
var _shake_tween: Tween
var _shake_base := Vector2.ZERO
var _invuln_left := 0.0
var _hurt_anim_left := 0.0
var _takedown_anim_left := 0.0
var _dead := false


func _ready() -> void:
	Engine.time_scale = 1.0   # a restart mid hit-stop must never leave the game slowed
	add_to_group("player")
	_hp = Health.new()
	_hp.setup(MAX_HEALTH)
	_hp.changed.connect(func(cur: int, mx: int) -> void: health_changed.emit(cur, mx))
	_hp.died.connect(_on_died)
	add_child(_hp)
	_rig = Rig.new()
	add_child(_rig)
	_rig.setup(self, SHEET, 32, ANIMS, "idle")
	_rig.sprite.z_index = Z_ACTOR   # body above cones, floor and pickups
	_col = get_node_or_null("Collision")
	if _col != null:
		_stand_shape = _col.shape
		_crawl_shape = RectangleShape2D.new()
		_crawl_shape.size = Vector2(12, 10)   # fits a 16 px slot with room to spare


# --- health facade (the HUD, night.gd and the tests speak these names) ---------

var health: int:
	get:
		return _hp.health
	set(points):
		_hp.set_health(points)


func is_dead() -> bool:
	return _dead


func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_invuln_left = 0.0
	_rig.play("dead", true)
	_rig.sprite.visible = true
	died.emit()


func take_damage(amount: int) -> void:
	if _dead or _invuln_left > 0.0:
		return
	if DASH_IFRAMES and _dash_time_left > 0.0:
		return
	_invuln_left = HURT_INVULN
	_hurt_anim_left = HURT_ANIM
	shake(SHAKE_HURT, 0.12)
	_hp.damage(amount)
	if not _dead:
		_rig.play("hurt", true)


func heal(amount: int) -> void:
	if _dead:
		return
	_hp.heal(amount)


func add_intel(amount: int = 1) -> void:
	intel = clampi(intel + amount, 0, MAX_INTEL)
	intel_changed.emit(intel, MAX_INTEL)


func is_sneaking() -> bool:
	return (sneaking or squeezing) and not _dead


func capture() -> void:
	# A guard reached us: the night ends. Bypasses i-frames on purpose -
	# capture is not a hit, it is a reset.
	if _dead or _grace_left > 0.0:
		return
	if DASH_IFRAMES and _dash_time_left > 0.0:
		return   # slipped through mid-dash
	if Run.consume_second_chance():
		# LUCKY COIN: everyone loses track of you for a beat.
		_grace_left = GRACE
		_invuln_left = GRACE
		_hit_stop(0.1)
		shake(SHAKE_CAPTURE, 0.3)
		for g in get_tree().get_nodes_in_group("guards"):
			if g.has_method("lose_track"):
				g.lose_track()
		return
	_hp.kill()
	_hit_stop(HITSTOP_CAPTURE)
	shake(SHAKE_CAPTURE, 0.25)


func extract() -> void:
	# Called by the doors when we step out with the goods.
	won = true
	_rig.set_facing(Vector2.DOWN)
	_rig.play("idle", true)    # calm, front-facing beat before the fade


# --- movement ----------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
	_invuln_left = maxf(_invuln_left - delta, 0.0)
	_hurt_anim_left = maxf(_hurt_anim_left - delta, 0.0)
	_takedown_anim_left = maxf(_takedown_anim_left - delta, 0.0)
	_grace_left = maxf(_grace_left - delta, 0.0)
	_update_debug_keys()
	if _dead or won:
		velocity = Vector2.ZERO
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir != Vector2.ZERO:
		_last_dir = input_dir.normalized()
	sneaking = Input.is_action_pressed("sneak") and _dash_time_left <= 0.0
	if _dash_time_left <= 0.0:
		input_dir = _update_squeeze(input_dir, delta)

	_dash_buffer_left = maxf(_dash_buffer_left - delta, 0.0)
	if Input.is_action_just_pressed("dash"):
		_dash_buffer_left = DASH_BUFFER

	if _dash_time_left > 0.0:
		_dash_time_left -= delta
		velocity = _dash_dir * DASH_SPEED          # committed: direction locked
		_ghost_timer -= delta
		if _ghost_timer <= 0.0:
			_ghost_timer = GHOST_EVERY
			_spawn_ghost()
	else:
		var top_speed := MOVE_SPEED * Run.mult("move_mult")
		if sneaking:
			top_speed = SNEAK_SPEED * Run.mult("sneak_mult")
		if squeezing:
			top_speed = CRAWL_SPEED * Run.mult("crawl_mult")
		if _takedown_anim_left > 0.0:
			top_speed *= TAKEDOWN_MOVE_MULT
		if input_dir != Vector2.ZERO:
			velocity = velocity.move_toward(input_dir * top_speed, ACCEL * delta)
		else:
			velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

		if _dash_buffer_left > 0.0 and _dash_cooldown_left <= 0.0 and not squeezing:
			_dash_dir = input_dir.normalized() if input_dir != Vector2.ZERO else _last_dir
			_dash_buffer_left = 0.0
			_dash_time_left = DASH_TIME * Run.mult("dash_time_mult")
			_dash_cooldown_left = DASH_COOLDOWN * Run.mult("dash_cd_mult")
			Run.make_noise(global_position, Run.NOISE_DASH)
			_ghost_timer = 0.0   # first afterimage on the same frame
			_rig.set_facing(_dash_dir)
			_rig.play("dash", true)

		if Input.is_action_just_pressed("takedown") and not squeezing:
			_try_takedown()

	move_and_slide()
	_update_animation(input_dir)


# --- tight spots: the belly crawl ---------------------------------------------------

func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori((pos.x - MAP_OFFSET.x) / 16.0), floori((pos.y - MAP_OFFSET.y) / 16.0))


func _update_squeeze(input_dir: Vector2, delta: float) -> Vector2:
	# A 1-tile slot (wall above AND below) is too low for a standing body;
	# walking into one drops the PI into a crawl: small collider, the squeeze
	# clip, sneak-grade visibility. The row is magnetised so you do not have
	# to thread it pixel-perfectly.
	if squeeze_cells.is_empty() or _col == null:
		return input_dir
	var here := _cell_of(global_position)
	var ahead := here
	if absf(input_dir.x) > 0.3:
		ahead = _cell_of(global_position + Vector2(signf(input_dir.x) * 10.0, 0.0))
	var in_slot: bool = squeeze_cells.has(here) or squeeze_cells.has(ahead)
	if in_slot and not squeezing:
		squeezing = true
		_col.shape = _crawl_shape
		_dash_buffer_left = 0.0
	elif squeezing and not in_slot:
		_col.shape = _stand_shape       # stand up only where the body fits
		if test_move(global_transform, Vector2.ZERO):
			_col.shape = _crawl_shape
		else:
			squeezing = false
	if squeezing:
		_rig.view = "side"
		var cell: Vector2i = here if squeeze_cells.has(here) else ahead
		if squeeze_cells.has(cell):
			var row_y := cell.y * 16.0 + 8.0 + MAP_OFFSET.y
			global_position.y = move_toward(global_position.y, row_y, 120.0 * delta)
			input_dir.y = 0.0
	return input_dir


# --- feel: takedown, hit-stop, shake, afterimage ------------------------------------

func _try_takedown() -> void:
	var best: Node = null
	var best_d := INF
	for g in get_tree().get_nodes_in_group("guards"):
		if g.has_method("can_be_taken_down") and g.can_be_taken_down(global_position):
			var d := global_position.distance_to(g.global_position)
			if d < best_d:
				best_d = d
				best = g
	if best == null:
		return
	best.takedown()
	Run.make_noise(global_position, Run.NOISE_TAKEDOWN)
	_rig.set_facing(best.global_position - global_position)   # face the man you grab
	_takedown_anim_left = TAKEDOWN_ANIM
	_rig.play("takedown", true)
	await _hit_stop(HITSTOP_TAKEDOWN)
	shake(SHAKE_TAKEDOWN, 0.15)   # freeze first, THEN the thump


func _hit_stop(seconds: float) -> void:
	# Freeze almost everything for `seconds` of REAL time. The timer ignores
	# Engine.time_scale (4th arg) or it would freeze itself too.
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = 0.02
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


func shake(strength: float, duration: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()          # restart, but keep the ORIGINAL base offset
	else:
		_shake_base = cam.offset
	_shake_tween = create_tween()
	_shake_tween.tween_method(_shake_step.bind(cam, strength), 0.0, 1.0, duration)
	_shake_tween.tween_callback(_shake_end.bind(cam))


func _shake_step(t: float, cam: Camera2D, strength: float) -> void:
	cam.offset = _shake_base + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * (1.0 - t)


func _shake_end(cam: Camera2D) -> void:
	cam.offset = _shake_base


func _spawn_ghost() -> void:
	# Dash afterimage: a fog-gray copy of the current frame that fades out.
	var tex := _rig.sprite.sprite_frames.get_frame_texture(_rig.sprite.animation, _rig.sprite.frame)
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = _rig.sprite.flip_h
	ghost.modulate = Color(0.478, 0.439, 0.5, 0.55)   # palette fog
	get_parent().add_child(ghost)
	get_parent().move_child(ghost, get_index())       # draw just UNDER the player
	ghost.global_position = global_position
	var tw := ghost.create_tween()
	tw.tween_property(ghost, "modulate:a", 0.0, GHOST_FADE)
	tw.tween_callback(ghost.queue_free)


func _update_animation(input_dir: Vector2) -> void:
	if _dash_time_left > 0.0:
		_rig.set_facing(_dash_dir)
	elif input_dir != Vector2.ZERO:
		_rig.set_facing(input_dir)
	_rig.sprite.speed_scale = 1.0
	var speed := velocity.length()
	if squeezing:
		_rig.play("squeeze")
		if absf(velocity.x) > 3.0:
			_rig.face_left = velocity.x < 0.0
			_rig.sprite.flip_h = _rig.face_left
			_rig.sprite.speed_scale = clampf(absf(velocity.x) / CRAWL_SPEED, 0.5, 2.0)
		else:
			_rig.sprite.speed_scale = 0.0     # stuck in the slot: hold the pose
		_rig.sprite.visible = true
		return
	if _hurt_anim_left > 0.0:
		_rig.play("hurt")
	elif _takedown_anim_left > 0.0:
		_rig.play("takedown")
	elif _dash_time_left > 0.0:
		_rig.play("dash")
	elif sneaking:
		_rig.play("sneak")
		if speed > 4.0:
			_rig.sprite.speed_scale = clampf(speed / SNEAK_SPEED, 0.5, 1.4)
		else:
			_rig.sprite.speed_scale = 0.0    # crouched and still: hold the pose
			_rig.sprite.frame = 0
	elif speed > 4.0:
		_rig.play("walk")
		_rig.sprite.speed_scale = clampf(speed / MOVE_SPEED, 0.5, 1.5)
	else:
		_rig.play("idle")
	# Blink while invulnerable - feedback without a healthbar flash.
	_rig.sprite.visible = _invuln_left <= 0.0 or fmod(_invuln_left * 12.0, 2.0) < 1.0


# --- the two hooks the orchestrators call ------------------------------------------

func _set_facing(dir: Vector2) -> void:
	_rig.set_facing(dir)


func _play(base: String, force := false) -> void:
	_rig.play(base, force)


func _update_debug_keys() -> void:
	if Input.is_action_just_pressed("debug_hurt"):
		take_damage(25)
	if Input.is_action_just_pressed("debug_heal"):
		heal(25)
	if Input.is_action_just_pressed("restart"):
		Run.on_restart()   # mid-night: forfeit it (nothing banked), deal a fresh one
		get_tree().reload_current_scene()
