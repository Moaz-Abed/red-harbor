extends Area2D
## Red Harbor - the safehouse door (extraction).
##
## The night loop's finish line. While the PI stands in the doorway:
##   * intel not full  -> HUD shows "SAFEHOUSE - need all 3 intel"
##   * intel full      -> HUD shows "SAFEHOUSE - press E to extract"
## Pressing E with full intel ends the night: the player freezes
## (player.extract()) and the HUD switches to the EXTRACTED state.
## R starts the next night, same as after FLATLINED.

signal extract_ready_changed(inside: bool, ready: bool)
signal extracted

const SHEET := preload("res://assets/sprites/exit_sheet.png")
const FRAME_SIZE := 32

var _player: Node2D
var _inside := false
var _done := false


func _ready() -> void:
        add_to_group("exit_zone")
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        sf.add_animation("hum")
        sf.set_animation_speed("hum", 2.5)
        sf.set_animation_loop("hum", true)
        for idx in 2:
                var at := AtlasTexture.new()
                at.atlas = SHEET
                at.region = Rect2(idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
                sf.add_frame("hum", at)
        var sp := AnimatedSprite2D.new()
        sp.sprite_frames = sf
        sp.play("hum")
        add_child(sp)

        var cs := CollisionShape2D.new()
        var sh := CircleShape2D.new()
        sh.radius = 20.0
        cs.shape = sh
        add_child(cs)

        body_entered.connect(_on_body_entered)
        body_exited.connect(_on_body_exited)


func _is_ready() -> bool:
        return _player != null \
                and _player.intel >= _player.MAX_INTEL \
                and not _player.is_dead()


func _physics_process(_delta: float) -> void:
        if _done or not _inside or not _is_ready():
                return
        if Input.is_action_just_pressed("interact"):
                _done = true
                _player.extract()
                extracted.emit()
                extract_ready_changed.emit(false, true)
                set_physics_process(false)


func _on_body_entered(body: Node2D) -> void:
        if body.is_in_group("player"):
                _player = body
                _inside = true
                extract_ready_changed.emit(true, _is_ready())


func _on_body_exited(body: Node2D) -> void:
        if body == _player:
                _inside = false
                extract_ready_changed.emit(false, _is_ready())
