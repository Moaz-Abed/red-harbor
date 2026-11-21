extends Node
## Red Harbor - headless ANIMATION test: the regression net for the smooth-
## animation pass (3-view sprite sheets, turning guards, takedown + KO).
##
## Run it with:
##   godot --headless --path . res://tests/anim.tscn
##
## Checks:
##   1. SHEET LAYOUT   - every frame of every player/guard/door/folder animation
##                       lies inside its sheet (a wrong row/frame count shows
##                       up here instead of as a blank sprite in game).
##   2. FACING         - held direction picks the right drawn view + mirroring.
##   3. STATE ANIMS    - dash / sneak / hurt / dead / takedown play their clips.
##   4. GUARD CLIPS    - alert -> chase -> search -> idle, KO after a takedown.
##   5. TURNING        - the beam swings at a bounded angular speed (no snap).
##
## Exits 0 with "ANIM: ALL PASS", exits 1 with a FAIL list otherwise.

var _main: Node2D
var _player: CharacterBody2D
var _fails: Array[String] = []


func _ready() -> void:
        _main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
        add_child(_main)
        await _frames(4)
        _player = _main.get_node("Player")
        for g in get_tree().get_nodes_in_group("guards"):
                g.set_physics_process(false)   # frozen until the guard phase
        _check_layout()
        await _check_facing()
        await _check_states()
        await _check_guards()
        await _check_turning()
        await _check_takedown()
        _finish()


func _frames(n: int) -> void:
        for i in n:
                await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
        if ok:
                print("ANIM PASS: ", what)
        else:
                print("ANIM FAIL: ", what)
                _fails.append(what)


func _release_all() -> void:
        for a in ["move_left", "move_right", "move_up", "move_down", "sneak", "dash", "takedown"]:
                Input.action_release(a)


# --- 1. sheet layout -------------------------------------------------------------

func _sheet_ok(sprite: AnimatedSprite2D, sheet_size: Vector2, label: String) -> void:
        var sf := sprite.sprite_frames
        var bad := 0
        var total := 0
        for anim in sf.get_animation_names():
                for i in sf.get_frame_count(anim):
                        total += 1
                        var t := sf.get_frame_texture(anim, i) as AtlasTexture
                        if t == null or t.region.position.x < 0 or t.region.position.y < 0 \
                                        or t.region.end.x > sheet_size.x or t.region.end.y > sheet_size.y:
                                bad += 1
        _check(total > 0 and bad == 0, "%s: %d frames all inside the %dx%d sheet" % [label, total, sheet_size.x, sheet_size.y])


func _check_layout() -> void:
        var ps := _sprite_of(_player)
        _sheet_ok(ps, Vector2(256, 640), "player")
        _check(ps.sprite_frames.get_frame_count("walk_side") == 8, "player walk cycle has 8 frames")
        _check(ps.sprite_frames.has_animation("dead") and ps.sprite_frames.get_frame_count("dead") == 6, "player dead clip has 6 frames")
        _check(ps.sprite_frames.has_animation("squeeze") and ps.sprite_frames.get_frame_count("squeeze") == 6, "player squeeze (tight spot crawl) clip has 6 frames")
        var g: Node = get_tree().get_first_node_in_group("guards")
        _sheet_ok(_sprite_of(g), Vector2(256, 480), "guard")
        var ex := _main.get_node("ExitZone")
        _sheet_ok(_sprite_of(ex), Vector2(192, 32), "exit door")
        var it := _main.get_node("Intel1")
        _sheet_ok(_sprite_of(it), Vector2(96, 16), "intel folder")


# --- 2. facing --------------------------------------------------------------------

func _sprite_of(n: Node) -> AnimatedSprite2D:
        # The Rig component nests the sprite one level down.
        for c in n.get_children():
                if c is AnimatedSprite2D:
                        return c
                var hit := _sprite_of(c)
                if hit != null:
                        return hit
        return null


func _check_facing() -> void:
        var ps := _sprite_of(_player)
        var cases := [
                ["move_right", "side", false], ["move_left", "side", true],
                ["move_down", "down", false], ["move_up", "up", false],
        ]
        for c in cases:
                _release_all()
                Input.action_press(c[0])
                await _frames(6)
                var name: String = ps.animation
                _check(name.ends_with("_" + c[1]), "%s -> %s view (clip '%s')" % [c[0], c[1], name])
                if c[1] == "side":
                        _check(ps.flip_h == c[2], "%s mirrors side view = %s" % [c[0], c[2]])
        _release_all()
        await _frames(2)


# --- 3. state clips ----------------------------------------------------------------

func _check_states() -> void:
        var ps := _sprite_of(_player)
        _release_all()
        Input.action_press("sneak")
        Input.action_press("move_right")
        await _frames(6)
        _check(ps.animation.begins_with("sneak_"), "sneak plays sneak clip ('%s')" % ps.animation)
        _release_all()
        await _frames(3)
        Input.action_press("move_right")
        await _frames(6)
        _check(ps.animation.begins_with("walk_") or ps.animation.begins_with("idle_"), "walk/idle clip ('%s')" % ps.animation)
        Input.action_press("dash")
        await _frames(2)
        _check(ps.animation.begins_with("dash_"), "dash plays dash clip ('%s')" % ps.animation)
        _release_all()
        await _frames(30)
        _player.take_damage(25)
        await _frames(2)
        _check(ps.animation.begins_with("hurt_"), "damage plays hurt clip ('%s')" % ps.animation)
        await _frames(40)
        _player.heal(100)


# --- 4. guard clips ----------------------------------------------------------------

func _check_guards() -> void:
        var g: Node = get_tree().get_nodes_in_group("guards")[0]
        var gs := _sprite_of(g)
        g._player = _player
        g._enter_chase()
        g._update_animation()
        _check(gs.animation.begins_with("alert_"), "spotted -> alert startle ('%s')" % gs.animation)
        g._alert_left = 0.0
        g._update_animation()
        _check(gs.animation.begins_with("chase_"), "hunting -> chase run ('%s')" % gs.animation)
        g._enter_search()
        g._update_animation()
        _check(gs.animation.begins_with("search_") or gs.animation == "idle_up", "lost you -> search clip ('%s')" % gs.animation)
        g._enter_patrol()
        g.velocity = Vector2.ZERO
        g._update_animation()
        _check(gs.animation.begins_with("idle_"), "standing -> idle clip ('%s')" % gs.animation)
        g.velocity = Vector2(50, 0)
        g._update_animation()
        _check(gs.animation.begins_with("patrol_"), "walking -> patrol clip ('%s')" % gs.animation)


# --- 5. smooth turning ---------------------------------------------------------------

func _check_turning() -> void:
        var g: Node = get_tree().get_nodes_in_group("guards")[0]
        g._facing = Vector2.RIGHT
        var before: float = g._facing.angle()
        g._turn_toward(Vector2.LEFT, g.TURN_SPEED, 1.0 / 60.0)
        var swung := absf(angle_difference(before, g._facing.angle()))
        _check(swung > 0.01 and swung <= g.TURN_SPEED / 60.0 + 0.001,
                        "beam turns %.3f rad in one frame (max %.3f), no snap" % [swung, g.TURN_SPEED / 60.0])
        for i in 120:
                g._turn_toward(Vector2.LEFT, g.TURN_SPEED, 1.0 / 60.0)
        _check(g._facing.dot(Vector2.LEFT) > 0.99, "beam finishes the 180 degree swing")


# --- 6. takedown + KO ------------------------------------------------------------------

func _check_takedown() -> void:
        var guards := get_tree().get_nodes_in_group("guards")
        var done := false
        for g in guards:
                g._player = _player
                for dir in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
                        g._facing = dir
                        g._state = g.State.PATROL
                        _player.global_position = g.global_position - dir * 14.0   # right behind him
                        if g.can_be_taken_down(_player.global_position):
                                Input.action_press("takedown")
                                await _frames(2)
                                Input.action_release("takedown")
                                await _frames(10)
                                var ps := _sprite_of(_player)
                                _check(g._down, "takedown downs the guard")
                                _check(_sprite_of(g).animation == "ko", "downed guard plays the KO clip")
                                _check(ps.animation.begins_with("takedown_"), "player plays the grab clip ('%s')" % ps.animation)
                                await _frames(60)
                                var last: int = _sprite_of(g).sprite_frames.get_frame_count("ko") - 1
                                _check(_sprite_of(g).frame == last, "KO ends on the lying frame")
                                done = true
                                break
                if done:
                        break
        _check(done, "found a guard that can be taken down from behind")
        # capture -> dead clip
        _player.global_position += Vector2(0, 0)
        _player.capture()
        await _frames(3)
        _check(_sprite_of(_player).animation == "dead", "capture plays the dead clip")


func _finish() -> void:
        _release_all()
        if _fails.is_empty():
                print("ANIM: ALL PASS")
                get_tree().quit(0)
        else:
                print("ANIM: %d FAIL" % _fails.size())
                get_tree().quit(1)
