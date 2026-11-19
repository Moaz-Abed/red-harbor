extends CharacterBody2D
## Red Harbor - M1 movement probe + Doom-style health (roadmap P1, P2 prep).
##
## Health is shown by the HUD portrait (hud.gd), never a healthbar:
## 6 face states sampled at 80/60/40/20/0 like the classic Doom mugshot.
## Until P2 adds real damage sources, H (hurt) / K (heal) drive the system.
##
## Sneak (P2): hold Ctrl/C to crouch. Slower, but guards' cones must be much
## closer before they detect you (see guard.gd CONE_RANGE_SNEAK).
##
## Night loop (P2 second half): touch sodium folders to pocket intel,
## then stand in the safehouse door and press E. exit_zone.gd calls
## extract() when the night is won.
##
## Phase 1 feel pass: silent takedown (F), 60 ms hit-stop + screen shake,
## dash afterimage, dash input buffer, dash i-frames, and a dash that covers
## the roadmap's four tiles (DASH_SPEED * DASH_TIME ~= 64 px).
##
## Movement acceptance targets from the roadmap:
##   * Dash must answer within 100 ms  -> it starts on the same physics frame.
##   * 8-direction movement; walls must block cleanly.
##   * Diagonal speed must match straight speed (Input.get_vector normalizes).

signal health_changed(current: int, max_health: int)
signal intel_changed(count: int, max_intel: int)
signal died

const MOVE_SPEED := 150.0    # walk speed, px/s
const SNEAK_SPEED := 78.0    # crouch speed, px/s - past a cone at the right distance
const ACCEL := 2000.0        # how fast we reach walk speed, px/s^2
const FRICTION := 2600.0     # how fast we stop - high value = snappy arcade stop
const DASH_SPEED := 430.0    # dash speed, px/s
const DASH_TIME := 0.15      # dash duration, s - 430 * 0.15 = ~64 px = 4 tiles (roadmap)
const DASH_COOLDOWN := 0.35  # seconds before the next dash is allowed

const DASH_BUFFER := 0.12    # a dash pressed this early still fires when the cooldown ends
const DASH_IFRAMES := true   # guards can't catch / hurt you mid-dash (roadmap: dash has i-frames)
const GHOST_EVERY := 0.03    # seconds between dash afterimages
const GHOST_FADE := 0.18     # how long an afterimage lingers
const HITSTOP_TAKEDOWN := 0.06   # roadmap feel checklist: ~60 ms
const HITSTOP_CAPTURE := 0.08
const SHAKE_TAKEDOWN := 3.0      # px of camera offset
const SHAKE_CAPTURE := 4.0
const SHAKE_HURT := 2.0

const MAX_HEALTH := 100
const MAX_INTEL := 3
const HURT_INVULN := 0.5     # seconds of i-frames after a hit
const HURT_ANIM := 0.25      # seconds the hurt pose holds
const TAKEDOWN_ANIM := 0.26  # seconds of the grab animation
const TAKEDOWN_MOVE_MULT := 0.25  # feet plant while the grab plays

# player_sheet.png (256 x 608): 32x32 cells, 8 columns. Rows are anim x view:
#   rows 0..17 = [idle, walk, sneak, dash, takedown, hurt] x [down, up, side]
#   row  18    = dead (side view, 6 frames)
# The "side" view is drawn facing RIGHT; flip_h turns it left. Regenerate the
# sheet with assets_src/gen_sprites.py (every frame comes from one rig).
const VIEWS := ["down", "up", "side"]
const ANIMS := {
        "idle": {"row": 0, "frames": 4, "fps": 4.0, "loop": true},
        "walk": {"row": 3, "frames": 8, "fps": 12.0, "loop": true},    # fps scales with speed
        "sneak": {"row": 6, "frames": 6, "fps": 8.0, "loop": true},
        "dash": {"row": 9, "frames": 4, "fps": 26.0, "loop": false},   # 4 frames ~= DASH_TIME
        "takedown": {"row": 12, "frames": 4, "fps": 16.0, "loop": false},
        "hurt": {"row": 15, "frames": 2, "fps": 8.0, "loop": false},
}
const DEAD_ANIM := {"row": 18, "frames": 6, "fps": 9.0, "loop": false}
const FRAME_SIZE := 32
const SHEET := preload("res://assets/sprites/player_sheet.png")
const Z_ACTOR := 2   # actor layer - see guard.gd for the world z contract

var health := MAX_HEALTH
var intel := 0
var sneaking := false
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_dir := Vector2.ZERO
var _dash_buffer_left := 0.0
var _ghost_timer := 0.0
var _last_dir := Vector2.RIGHT   # last non-zero input, used when you dash standing still
var _hitstop_active := false
var _shake_tween: Tween
var _shake_base := Vector2.ZERO
var _invuln_left := 0.0
var _hurt_anim_left := 0.0
var _takedown_anim_left := 0.0
var _view := "down"          # which of the 3 drawn views is showing
var _face_left := false      # mirror the side view
var _anim_base := "idle"
var _dead := false
var won := false            # extraction succeeded - the night is over
var _sprite: AnimatedSprite2D


func _ready() -> void:
        Engine.time_scale = 1.0   # safety: a restart mid hit-stop must never leave the game slowed
        add_to_group("player")
        _sprite = AnimatedSprite2D.new()
        _sprite.sprite_frames = _build_frames()
        _play("idle")
        _sprite.z_index = Z_ACTOR   # body above cones, floor and pickups
        add_child(_sprite)


func _build_frames() -> SpriteFrames:
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        for anim_name in ANIMS:
                var cfg: Dictionary = ANIMS[anim_name]
                for v in VIEWS.size():
                        _add_anim(sf, "%s_%s" % [anim_name, VIEWS[v]], cfg, int(cfg["row"]) + v)
        _add_anim(sf, "dead", DEAD_ANIM, int(DEAD_ANIM["row"]))
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


func _set_facing(dir: Vector2) -> void:
        # 8-direction input -> one of 3 drawn views. Near-diagonals keep the
        # current view so the sprite never flickers while you steer around a corner.
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


func _play(base: String, force: bool = false) -> void:
        var anim := "dead" if base == "dead" else "%s_%s" % [base, _view]
        if force or _sprite.animation != anim:
                # Changing view mid-walk keeps the stride phase (no stutter at corners).
                var keep := (not force) and base == _anim_base and base != "dead"
                var f := _sprite.frame
                var prog := _sprite.frame_progress
                _sprite.play(anim)
                if keep:
                        _sprite.set_frame_and_progress(f, prog)
        _anim_base = base
        _sprite.flip_h = (_view == "side" or base == "dead") and _face_left


func take_damage(amount: int) -> void:
        if _dead or _invuln_left > 0.0:
                return
        if DASH_IFRAMES and _dash_time_left > 0.0:
                return
        health = clampi(health - amount, 0, MAX_HEALTH)
        shake(SHAKE_HURT, 0.12)
        _invuln_left = HURT_INVULN
        _hurt_anim_left = HURT_ANIM
        health_changed.emit(health, MAX_HEALTH)
        if health <= 0:
                _dead = true
                _play("dead", true)
                _sprite.visible = true
                died.emit()
        else:
                _play("hurt", true)


func heal(amount: int) -> void:
        if _dead:
                return
        health = clampi(health + amount, 0, MAX_HEALTH)
        health_changed.emit(health, MAX_HEALTH)


func add_intel(amount: int = 1) -> void:
        intel = clampi(intel + amount, 0, MAX_INTEL)
        intel_changed.emit(intel, MAX_INTEL)


func is_sneaking() -> bool:
        return sneaking and not _dead


func is_dead() -> bool:
        return _dead


func capture() -> void:
        # A guard reached us (P2) - the night ends no matter what.
        # Bypasses i-frames on purpose: capture is not a hit, it is a reset.
        if _dead:
                return
        if DASH_IFRAMES and _dash_time_left > 0.0:
                return   # slipped through mid-dash
        health = 0
        _dead = true
        _invuln_left = 0.0
        _sprite.visible = true
        _play("dead", true)
        health_changed.emit(0, MAX_HEALTH)
        died.emit()
        _hit_stop(HITSTOP_CAPTURE)
        shake(SHAKE_CAPTURE, 0.25)


func extract() -> void:
        # Called by exit_zone.gd when we step out with full intel.
        won = true
        _sprite.visible = true
        _set_facing(Vector2.DOWN)
        _play("idle", true)    # calm, front-facing beat before the fade


func _physics_process(delta: float) -> void:
        _dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
        _invuln_left = maxf(_invuln_left - delta, 0.0)
        _hurt_anim_left = maxf(_hurt_anim_left - delta, 0.0)
        _takedown_anim_left = maxf(_takedown_anim_left - delta, 0.0)
        _update_debug_keys()
        if _dead or won:
                velocity = Vector2.ZERO
                return

        var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
        if input_dir != Vector2.ZERO:
                _last_dir = input_dir.normalized()
        sneaking = Input.is_action_pressed("sneak") and _dash_time_left <= 0.0

        # Input buffer: remember a dash press for DASH_BUFFER seconds so mashing
        # during the cooldown still fires the instant it ends.
        _dash_buffer_left = maxf(_dash_buffer_left - delta, 0.0)
        if Input.is_action_just_pressed("dash"):
                _dash_buffer_left = DASH_BUFFER

        if _dash_time_left > 0.0:
                # Committed dash: direction is locked, steering is ignored.
                _dash_time_left -= delta
                velocity = _dash_dir * DASH_SPEED
                _ghost_timer -= delta
                if _ghost_timer <= 0.0:
                        _ghost_timer = GHOST_EVERY
                        _spawn_ghost()
        else:
                var top_speed := SNEAK_SPEED if sneaking else MOVE_SPEED
                if _takedown_anim_left > 0.0:
                        top_speed *= TAKEDOWN_MOVE_MULT   # feet plant during the grab
                if input_dir != Vector2.ZERO:
                        velocity = velocity.move_toward(input_dir * top_speed, ACCEL * delta)
                else:
                        velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

                if _dash_buffer_left > 0.0 and _dash_cooldown_left <= 0.0:
                        _dash_dir = input_dir.normalized() if input_dir != Vector2.ZERO else _last_dir
                        _dash_buffer_left = 0.0
                        _dash_time_left = DASH_TIME
                        _dash_cooldown_left = DASH_COOLDOWN
                        _ghost_timer = 0.0   # first afterimage on the same frame: no wind-up
                        _set_facing(_dash_dir)
                        _play("dash", true)
                        # P2 hooks - deliberately NOT implemented yet (scope contract):
                        #   - EMP lighter sfx (jsfxr)
                        #   - stamina / cooldown UI

                if Input.is_action_just_pressed("takedown"):
                        _try_takedown()

        move_and_slide()
        _update_animation(input_dir)


# --- feel: takedown, hit-stop, shake, afterimage ---------------------------------

func _try_takedown() -> void:
        # Nearest guard that says we are close enough, behind him, with no wall
        # between us (the rules live in guard.gd can_be_taken_down).
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
        _set_facing(best.global_position - global_position)   # face the man you grab
        _takedown_anim_left = TAKEDOWN_ANIM
        _play("takedown", true)
        await _hit_stop(HITSTOP_TAKEDOWN)
        shake(SHAKE_TAKEDOWN, 0.15)   # freeze first, THEN the thump
        # P5 hooks: takedown thud sfx + particles land here.


func _hit_stop(seconds: float) -> void:
        # Freeze almost everything for `seconds` of REAL time. The timer ignores
        # Engine.time_scale (4th arg), otherwise it would freeze itself too.
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
        var tex := _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
        var ghost := Sprite2D.new()
        ghost.texture = tex
        ghost.flip_h = _sprite.flip_h
        ghost.modulate = Color(0.478, 0.439, 0.5, 0.55)   # palette fog
        get_parent().add_child(ghost)
        get_parent().move_child(ghost, get_index())       # draw just UNDER the player
        ghost.global_position = global_position
        var tw := ghost.create_tween()
        tw.tween_property(ghost, "modulate:a", 0.0, GHOST_FADE)
        tw.tween_callback(ghost.queue_free)


func _update_animation(input_dir: Vector2) -> void:
        if _dash_time_left > 0.0:
                _set_facing(_dash_dir)
        elif input_dir != Vector2.ZERO:
                _set_facing(input_dir)
        _sprite.speed_scale = 1.0
        var speed := velocity.length()
        if _hurt_anim_left > 0.0:
                _play("hurt")
        elif _takedown_anim_left > 0.0:
                _play("takedown")
        elif _dash_time_left > 0.0:
                _play("dash")
        elif sneaking:
                _play("sneak")
                if speed > 4.0:
                        _sprite.speed_scale = clampf(speed / SNEAK_SPEED, 0.5, 1.4)   # feet match the floor
                else:
                        _sprite.speed_scale = 0.0    # crouched and still: hold the pose
                        _sprite.frame = 0
        elif speed > 4.0:
                _play("walk")
                _sprite.speed_scale = clampf(speed / MOVE_SPEED, 0.5, 1.5)
        else:
                _play("idle")
        # Blink while invulnerable - feedback without any healthbar flash.
        _sprite.visible = _invuln_left <= 0.0 or fmod(_invuln_left * 12.0, 2.0) < 1.0


func _update_debug_keys() -> void:
        # Gray-box probes. Intel is REAL now (pickups), so E is free for the
        # safehouse (exit_zone.gd reads it directly).
        if Input.is_action_just_pressed("debug_hurt"):
                take_damage(25)
        if Input.is_action_just_pressed("debug_heal"):
                heal(25)
        if Input.is_action_just_pressed("restart"):
                get_tree().reload_current_scene()
