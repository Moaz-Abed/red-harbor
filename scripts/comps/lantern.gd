class_name Lantern
extends Node
## One additive pool of light on the floor: task = a job's glow, neon = the
## back door sign. Floor 0 < lights 1 < actors 2, so a pool never rides a
## character - the actors stay glow-free.

const Z_LIGHT := 1
const TEXTURES := {
		"task": preload("res://assets/lights/light_task.png"),
		"neon": preload("res://assets/lights/light_neon.png"),
}

var glow: Sprite2D
var flicker := 0.0            # 0 = steady, else the wobble amplitude
var _base := 1.0
var _t := 0.0


func setup(kind: String, power := 1.0, reach := 1.0, wobble := 0.0, drop := 0.0) -> void:
		_base = power
		flicker = wobble
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow = Sprite2D.new()
		glow.texture = TEXTURES.get(kind, TEXTURES["task"])
		glow.scale = Vector2(reach, reach)
		glow.z_index = Z_LIGHT           # a pool on the floor, not on the owner
		glow.material = mat
		glow.modulate = Color(1, 1, 1, power)
		glow.position = Vector2(0, drop)
		host().add_child(glow)


func host() -> Node2D:
		return get_parent() as Node2D


func pulse(power: float) -> void:
		_base = power


func _process(delta: float) -> void:
		if glow == null or flicker <= 0.0:
				return
		_t += delta
		glow.modulate.a = _base * (1.0 - flicker * (0.5 + 0.5 * sin(_t * 9.0) * sin(_t * 3.7)))
