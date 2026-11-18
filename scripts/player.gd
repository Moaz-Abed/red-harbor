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
const DASH_TIME := 0.12      # dash duration, seconds
const DASH_COOLDOWN := 0.35  # seconds before the next dash is allowed

const MAX_HEALTH := 100
const MAX_INTEL := 3
const HURT_INVULN := 0.5     # seconds of i-frames after a hit
const HURT_ANIM := 0.25      # seconds the hurt pose holds

# player_sheet.png frames: 0-1 idle, 2-5 walk, 6-7 dash, 8-9 sneak, 10 hurt, 11 dead
const ANIMS := {
        "idle": {"frames": [0, 1], "fps": 2.0, "loop": true},
        "walk": {"frames": [2, 3, 4, 5], "fps": 10.0, "loop": true},
        "dash": {"frames": [6, 7], "fps": 12.0, "loop": true},
        "sneak": {"frames": [8, 9], "fps": 4.0, "loop": true},
        "hurt": {"frames": [10], "fps": 1.0, "loop": false},
        "dead": {"frames": [11], "fps": 1.0, "loop": false},
}
const FRAME_SIZE := 32
const SHEET := preload("res://assets/sprites/player_sheet.png")

var health := MAX_HEALTH
var intel := 0
var sneaking := false
var _dash_time_left := 0.0
var _dash_cooldown_left := 0.0
var _dash_dir := Vector2.ZERO
var _invuln_left := 0.0
var _hurt_anim_left := 0.0
var _dead := false
var _sprite: AnimatedSprite2D


func _ready() -> void:
        add_to_group("player")
        _sprite = AnimatedSprite2D.new()
        _sprite.sprite_frames = _build_frames()
        _sprite.play("idle")
        add_child(_sprite)


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


func take_damage(amount: int) -> void:
        if _dead or _invuln_left > 0.0:
                return
        health = clampi(health - amount, 0, MAX_HEALTH)
        _invuln_left = HURT_INVULN
        _hurt_anim_left = HURT_ANIM
        health_changed.emit(health, MAX_HEALTH)
        if health <= 0:
                _dead = true
                _sprite.play("dead")
                _sprite.visible = true
                died.emit()
        else:
                _sprite.play("hurt")


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
        health = 0
        _dead = true
        _invuln_left = 0.0
        _sprite.visible = true
        _sprite.play("dead")
        health_changed.emit(0, MAX_HEALTH)
        died.emit()


func _physics_process(delta: float) -> void:
        _dash_cooldown_left = maxf(_dash_cooldown_left - delta, 0.0)
        _invuln_left = maxf(_invuln_left - delta, 0.0)
        _hurt_anim_left = maxf(_hurt_anim_left - delta, 0.0)
        _update_debug_keys()
        if _dead:
                velocity = Vector2.ZERO
                return

        var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
        sneaking = Input.is_action_pressed("sneak") and _dash_time_left <= 0.0

        if _dash_time_left > 0.0:
                # Committed dash: direction is locked, steering is ignored.
                _dash_time_left -= delta
                velocity = _dash_dir * DASH_SPEED
        else:
                var top_speed := SNEAK_SPEED if sneaking else MOVE_SPEED
                if input_dir != Vector2.ZERO:
                        velocity = velocity.move_toward(input_dir * top_speed, ACCEL * delta)
                else:
                        velocity = velocity.move_toward(Vector2.ZERO, FRICTION * delta)

                if Input.is_action_just_pressed("dash") and _dash_cooldown_left <= 0.0:
                        _dash_dir = input_dir.normalized() if input_dir != Vector2.ZERO else Vector2.RIGHT
                        _dash_time_left = DASH_TIME
                        _dash_cooldown_left = DASH_COOLDOWN
                        # P2 hooks - deliberately NOT implemented yet (scope contract):
                        #   - EMP lighter sfx (jsfxr) + afterimage sprite
                        #   - stamina / cooldown UI

        move_and_slide()
        _update_animation(input_dir)


func _update_animation(input_dir: Vector2) -> void:
        if input_dir.x != 0.0:
                _sprite.flip_h = input_dir.x < 0.0
        if _hurt_anim_left > 0.0:
                _sprite.play("hurt")
        elif _dash_time_left > 0.0:
                _sprite.play("dash")
        elif sneaking:
                _sprite.play("sneak")   # crouched, moving or not
        elif velocity.length() > 4.0:
                _sprite.play("walk")
        else:
                _sprite.play("idle")
        # Blink while invulnerable - feedback without any healthbar flash.
        _sprite.visible = _invuln_left <= 0.0 or fmod(_invuln_left * 12.0, 2.0) < 1.0


func _update_debug_keys() -> void:
        # Gray-box probes until real damage sources exist in P2.
        if Input.is_action_just_pressed("debug_hurt"):
                take_damage(25)
        if Input.is_action_just_pressed("debug_heal"):
                heal(25)
        if Input.is_action_just_pressed("interact"):
                add_intel(1)   # placeholder for P3 intel pickups
        if Input.is_action_just_pressed("restart"):
                get_tree().reload_current_scene()
