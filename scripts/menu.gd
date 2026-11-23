extends Control
## The title screen: just the neon logo and PRESS ENTER, behind a CRT tube.
## The logo springs in, ENTER punches (flash + glitch + shake), ESC quits.

const OFFICE := "res://scenes/office.tscn"
const TITLE_TEX := preload("res://assets/sprites/menu_title.png")
const PROMPT_TEX := preload("res://assets/sprites/menu_prompt.png")
const CRT := preload("res://shaders/crt_menu.gdshader")

const TITLE_REST := Vector2(320, 156)
const PROMPT_REST := Vector2(320, 248)


# A damped spring; stiff / soft is all in the two constants.
class Spring:
                var value := 0.0
                var vel := 0.0
                var target := 0.0
                var stiffness := 110.0
                var damping := 11.0

                func step(delta: float) -> void:
                                var a := (target - value) * stiffness - vel * damping
                                vel += a * delta
                                value += vel * delta


var _t := 0.0
var _punch_t := 99.0          # seconds since ENTER; 99 = not yet
var _leaving := false
var _title: TextureRect
var _prompt: TextureRect
var _stage: Control
var _crt_mat: ShaderMaterial
var _spring_y := Spring.new()
var _spring_scale := Spring.new()
var _prompt_in := Spring.new()


func _ready() -> void:
                Input.mouse_mode = Input.MOUSE_MODE_VISIBLE   # back from the office
                var bg := ColorRect.new()
                bg.set_anchors_preset(Control.PRESET_FULL_RECT)
                bg.color = Color("08090a")
                bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
                add_child(bg)

                _stage = Control.new()
                _stage.name = "Stage"
                _stage.set_anchors_preset(Control.PRESET_FULL_RECT)
                _stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
                add_child(_stage)

                _title = _tex(TITLE_TEX, 1.0)
                _title.name = "Title"
                _title.position = TITLE_REST - _title.size * 0.5
                _stage.add_child(_title)

                _prompt = _tex(PROMPT_TEX, 1.0)
                _prompt.name = "Prompt"
                _prompt.position = PROMPT_REST - _prompt.size * 0.5
                _prompt.modulate.a = 0.0
                _stage.add_child(_prompt)

                # CRT post-process above everything
                var layer := CanvasLayer.new()
                layer.layer = 100
                add_child(layer)
                var tube := ColorRect.new()
                tube.set_anchors_preset(Control.PRESET_FULL_RECT)
                tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
                _crt_mat = ShaderMaterial.new()
                _crt_mat.shader = CRT
                tube.material = _crt_mat
                layer.add_child(tube)

                # the logo slams up from below, overshoots, settles
                _spring_y.value = 240.0
                _spring_y.target = 0.0
                _spring_y.stiffness = 95.0
                _spring_y.damping = 9.0
                _spring_scale.value = 2.4
                _spring_scale.target = 1.0
                _spring_scale.stiffness = 80.0
                _spring_scale.damping = 8.0
                _prompt_in.value = 0.0
                _prompt_in.target = 1.0
                _prompt_in.stiffness = 150.0
                _prompt_in.damping = 13.0


func _tex(tex: Texture2D, alpha: float) -> TextureRect:
                var t := TextureRect.new()
                t.texture = tex
                t.stretch_mode = TextureRect.STRETCH_KEEP
                t.size = tex.get_size()
                t.mouse_filter = Control.MOUSE_FILTER_IGNORE
                t.pivot_offset = tex.get_size() * 0.5
                t.modulate.a = alpha
                return t


func _process(delta: float) -> void:
                _t += delta
                _punch_t += delta
                _spring_y.step(delta)
                _spring_scale.step(delta)
                _prompt_in.step(delta)

                # title: spring position + idle bob
                _title.scale = Vector2.ONE * maxf(0.05, _spring_scale.value)
                _title.position = TITLE_REST - _title.size * 0.5 + Vector2(0, _spring_y.value)
                _title.position.y += sin(_t * 1.7) * 3.0

                # prompt: springs in at 0.7s, then breathes
                var p_in: float = clampf(_prompt_in.value, 0.0, 1.4) if _t > 0.7 else 0.0
                _prompt.modulate = Color(1.0, 0.87, 0.68)
                _prompt.modulate.a = clampf(p_in, 0.0, 1.0) * (0.35 + 0.65 * abs(sin(_t * 2.2)))
                _prompt.scale = Vector2.ONE * clampf(p_in, 0.4, 1.05)
                _prompt.position = PROMPT_REST - _prompt.size * 0.5

                # punch decay drives the tube
                var flash := exp(-_punch_t * 9.0) * 0.9
                var glitch := exp(-_punch_t * 4.5) * 0.85
                var boot := exp(-_t * 2.6) * 0.5
                var shake := exp(-_punch_t * 6.5) * 9.0
                _crt_mat.set_shader_parameter("flash", flash)
                _crt_mat.set_shader_parameter("glitch", glitch + boot)
                _crt_mat.set_shader_parameter("aberration", 1.35 + flash * 2.5 + glitch * 4.0)
                _stage.position = Vector2(randf() - 0.5, randf() - 0.5) * shake

                if _leaving and _punch_t > 0.45:
                                _leaving = false
                                get_tree().change_scene_to_file(OFFICE)


func _unhandled_input(event: InputEvent) -> void:
                if _leaving:
                                return
                if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
                                get_viewport().set_input_as_handled()
                                _punch()
                elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
                                get_viewport().set_input_as_handled()
                                _crt_mat.set_shader_parameter("dim", 1.0)
                                get_tree().quit()


func _punch() -> void:
                # the scoring hit: white crack of the tube, glitch tear, the logo jumps
                _punch_t = 0.0
                _leaving = true
                _spring_scale.vel += 7.0
                _prompt_in.vel -= 4.0
