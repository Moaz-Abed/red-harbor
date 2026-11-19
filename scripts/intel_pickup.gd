extends Area2D
## Red Harbor - one intel cache (the sodium folder).
##
## Walk into it and the PI pockets it: player.add_intel(1) fires, the HUD
## pip fills, and the folder frees itself. No key press needed - pickups
## are about routing risk, not button timing.

const SHEET := preload("res://assets/sprites/intel_sheet.png")
const FRAME_SIZE := 16


func _ready() -> void:
        add_to_group("intel_pickups")
        var sf := SpriteFrames.new()
        sf.remove_animation("default")
        sf.add_animation("pulse")
        sf.set_animation_speed("pulse", 2.0)
        sf.set_animation_loop("pulse", true)
        for idx in 2:
                var at := AtlasTexture.new()
                at.atlas = SHEET
                at.region = Rect2(idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
                sf.add_frame("pulse", at)
        var sp := AnimatedSprite2D.new()
        sp.sprite_frames = sf
        sp.play("pulse")
        sp.z_index = 2   # actor layer - pickups stand above cones and floor
        add_child(sp)

        var cs := CollisionShape2D.new()
        var sh := CircleShape2D.new()
        sh.radius = 9.0
        cs.shape = sh
        add_child(cs)

        body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
        if body.is_in_group("player") and body.has_method("add_intel"):
                body.add_intel(1)
                # P5 hook: paper-snatch sfx lands here with the jsfxr pass.
                queue_free()
