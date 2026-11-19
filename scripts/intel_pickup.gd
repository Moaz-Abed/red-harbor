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
        sf.set_animation_speed("pulse", 6.0)   # 6 frames: bob, paper flutter, glint
        sf.set_animation_loop("pulse", true)
        for idx in 6:
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

        # FIX (the vanishing cache, ~1.5% of nights). A CharacterBody2D's
        # transform set during scene setup reaches the physics server one
        # step LATE, while Area2D transforms sync immediately - verified on
        # a failing night: for the whole first step the player's node sat at
        # its plan spawn (328, 332) while its BODY was still at the editor
        # preview spot (40, 300). A cache dealt beside that preview spot
        # (ring cells (2,17)..(2,19) land at (40, 284..316)) paired with the
        # stale body - 16 px apart, inside pickup reach - and was pocketed
        # before the first input frame. Direct PhysicsServer2D writes don't
        # close the window (the body's pending state overrides them), so the
        # cache simply stays blind through the setup step and arms once the
        # world has stepped into place. No legit pickup is lost: the deal
        # keeps caches >= 7 tiles from the PI, and ~1 px of movement by
        # frame 2 cannot cover that distance.
        monitoring = false
        body_entered.connect(_on_body_entered)
        _arm_when_settled()


func _arm_when_settled() -> void:
        # physics_frame fires at the START of each step. Two hops = armed at
        # the start of the second step after boot, by which time every body's
        # server transform has landed (the sync flush runs after step one).
        await get_tree().physics_frame
        await get_tree().physics_frame
        monitoring = true


func _on_body_entered(body: Node2D) -> void:
        if body.is_in_group("player") and body.has_method("add_intel"):
                body.add_intel(1)
                # P5 hook: paper-snatch sfx lands here with the jsfxr pass.
                queue_free()
