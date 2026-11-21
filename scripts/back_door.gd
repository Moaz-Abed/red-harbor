extends Node2D
## The back door: the signature decision. E leaves and banks everything you
## carry; Q descends for the EVIDENCE tier (unbanked - a catch below costs
## most of it). LOCKDOWN seals the stairs; below, the same door is the exit.

signal prompt_changed(text: String, kind: String)   # kind: ready | blocked | info | none
signal extracted
signal descend_requested

const SHEET := preload("res://assets/sprites/exit_sheet.png")
const FRAME_SIZE := 32
const REACH := 22.0

var floor_no := 1
var evidence_cases := 2
var _player: Node2D
var _inside := false
var _done := false
var _last_prompt := ""


func _ready() -> void:
        add_to_group("back_door")
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        sf.add_animation("hum")
        sf.set_animation_speed("hum", 7.0)
        sf.set_animation_loop("hum", true)
        for idx in 6:
                var at := AtlasTexture.new()
                at.atlas = SHEET
                at.region = Rect2(idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
                sf.add_frame("hum", at)
        var sp := AnimatedSprite2D.new()
        sp.sprite_frames = sf
        sp.play("hum")
        sp.z_index = 2
        add_child(sp)
        var glow := Lantern.new()
        add_child(glow)
        glow.setup("neon", 0.6, 1.4, 0.06)


func can_descend() -> bool:
        return floor_no == 1 and not Run.lockdown() and Run.can_descend()


func prompt_for(points: int) -> Array:
        # [text, kind] - split out so the night test can read the exact wording.
        if floor_no >= 2:
                return ["[E] SERVICE EXIT - bank %d pts" % points, "ready"]
        var leave := "[E] LEAVE NOW - bank %d pts" % points
        if not Run.can_descend():
                return [leave + "\nSEALED VAULT - nothing below", "ready"]
        if Run.lockdown():
                return [leave + "\nLOCKDOWN - the lower floor is sealed", "blocked"]
        var pts: int = Run.TIER_POINTS[Run.Tier.EVIDENCE]
        return [leave + "\n[Q] DESCEND - %d evidence cases, %d pts each" % [evidence_cases, pts], "ready"]


func _physics_process(_delta: float) -> void:
        if _player == null:
                _player = get_tree().get_first_node_in_group("player")
                return
        if _done:
                return
        var alive: bool = not _player.is_dead() and not _player.won
        _inside = alive and _player.global_position.distance_to(global_position) <= REACH
        if not _inside:
                _set_prompt("", "none")
                return
        var p := prompt_for(Run.unbanked_points())
        _set_prompt(p[0], p[1])
        if Input.is_action_just_pressed("interact"):
                _done = true
                _player.extract()
                _set_prompt("", "none")
                extracted.emit()
        elif Input.is_action_just_pressed("descend") and can_descend():
                _done = true
                _set_prompt("", "none")
                descend_requested.emit()


func _set_prompt(text: String, kind: String) -> void:
        if text != _last_prompt:
                _last_prompt = text
                prompt_changed.emit(text, kind)
