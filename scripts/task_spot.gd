extends Node2D
## One job on the night's list: stand next to the prop and HOLD E. Let go and
## the progress bleeds back, so a guard's footsteps cost real decisions.
## Completing a job adds one UNBANKED intel (banked only at the back door).

signal completed(task_type: String)

const TASK_SHEET := preload("res://assets/sprites/task_sheet.png")
const INTEL_SHEET := preload("res://assets/sprites/intel_sheet.png")
const FRAME_SIZE := 16
const REACH := 15.0          # px from the prop to the PI's centre
const DECAY := 1.5           # progress lost per second of not holding
const COLOR_BAR := Color("e8b366")
const COLOR_INK := Color("14121c")
const COLOR_BONE := Color("ded6c7")

@export var task_type := "documents"

var progress := 0.0          # 0..1
var _near := false
var _player: Node2D
var _sprite: AnimatedSprite2D
var _glow: Lantern


func _ready() -> void:
        add_to_group("task_spots")
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        sf.add_animation("idle")
        sf.set_animation_speed("idle", 6.0)
        sf.set_animation_loop("idle", true)
        var sheet: Texture2D = INTEL_SHEET if task_type == "documents" else TASK_SHEET
        var row := 0
        match task_type:
                "ledger":
                        row = 1
                "evidence":
                        row = 2
        for idx in 6:
                var at := AtlasTexture.new()
                at.atlas = sheet
                at.region = Rect2(idx * FRAME_SIZE, row * FRAME_SIZE, FRAME_SIZE, FRAME_SIZE)
                sf.add_frame("idle", at)
        _sprite = AnimatedSprite2D.new()
        _sprite.sprite_frames = sf
        _sprite.play("idle")
        _sprite.z_index = 2   # actor layer: props stand above the floor and the cones
        add_child(_sprite)
        _glow = Lantern.new()
        add_child(_glow)
        _glow.setup("task", 0.5, 1.15)


func tier() -> int:
        return Run.TASKS[task_type]["tier"]


func hold_time() -> float:
        return Run.TASKS[task_type]["time"] * Run.mult("job_time_mult")


func _physics_process(delta: float) -> void:
        if _player == null:
                _player = get_tree().get_first_node_in_group("player")
                return
        var alive: bool = not _player.is_dead() and not _player.won
        var was_near := _near
        _near = alive and _player.global_position.distance_to(global_position) <= REACH
        var holding := _near and Input.is_action_pressed("interact")
        var before := progress
        if holding:
                progress = minf(progress + delta / hold_time(), 1.0)
        else:
                progress = maxf(progress - delta * DECAY, 0.0)
        if progress >= 1.0:
                _complete()
                return
        if progress != before or _near != was_near:
                queue_redraw()
        _glow.pulse(0.45 + progress * 0.4 + (0.15 if _near else 0.0))


func _complete() -> void:
        set_physics_process(false)
        var t := tier()
        Run.add_intel(t)
        Run.note_style(100)
        if _player != null and _player.has_method("shake"):
                _player.shake(1.5, 0.12)
        _float_text("+%d %s - %s" % [Run.TIER_POINTS[t], Run.TIER_NAMES[t], Run.TASKS[task_type]["done"]])
        completed.emit(task_type)
        queue_free()


func _float_text(msg: String) -> void:
        # A short rising caption in the world, in the sodium "safe light" colour.
        var host := get_parent()
        if host == null:
                return
        var lbl := Label.new()
        lbl.text = msg
        lbl.add_theme_font_size_override("font_size", 10)
        lbl.add_theme_color_override("font_color", COLOR_BAR)
        lbl.add_theme_color_override("font_outline_color", COLOR_INK)
        lbl.add_theme_constant_override("outline_size", 3)
        lbl.z_index = 20
        lbl.position = global_position + Vector2(-70, -26)
        lbl.size = Vector2(140, 14)
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        host.add_child(lbl)
        var tw := lbl.create_tween()
        tw.set_parallel(true)
        tw.tween_property(lbl, "position:y", lbl.position.y - 18.0, 1.4)
        tw.tween_property(lbl, "modulate:a", 0.0, 1.4).set_delay(0.6)
        tw.chain().tween_callback(lbl.queue_free)


func _draw() -> void:
        if not _near and progress <= 0.0:
                return
        # progress bar above the prop
        var bar := Rect2(-9, -17, 18, 4)
        draw_rect(bar.grow(1), COLOR_INK)
        draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), COLOR_BAR)
        if progress <= 0.0:
                # "hold E" cue while you are close and not yet working
                var f := ThemeDB.fallback_font
                draw_string_outline(f, Vector2(-3, -21), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, COLOR_INK)
                draw_string(f, Vector2(-3, -21), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_BONE)
