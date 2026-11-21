extends Node3D
## Model-inspection harness for the PI rig (run under xvfb, never headless).
## Drops the PI alone under office-style light and orbits a lens around him,
## idle or mid-stride, for visual QA of the body and the face.
##   xvfb-run -s "-screen 0 640x640x24" godot --path . --resolution 640x640 \
##       res://tests/pi_closeup.tscn -- --yaw=0 --look=head --dist=1.2 --out=/tmp/face.png
## User args (after `--`, key=value):
##   yaw / pitch   lens orbit in degrees (yaw 0 = in front of his face)
##   dist          lens distance from the look point
##   look          "head" (default "body"): orbit the mug or the whole rig
##   stride        1 = drive the walk cycle in place, 0 = idle breathing
##   clean         1 = no vertex snap / affine swim, crisp model read
##   wait          frames to settle before the snap (default 30)
##   out           output png path

var _args: Dictionary = {}
var _pi: Pi
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.find("=") != -1:
			var kv := a.split("=", true, 1)
			_args[kv[0].trim_prefix("--")] = kv[1]
		else:
			_args[a.trim_prefix("--")] = "1"
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var res := int(_args.get("res", 640))
	get_window().size = Vector2i(res, res)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_sky_contribution = 0.0
	e.ambient_light_color = Color(0.36, 0.36, 0.40)
	e.ambient_light_energy = 14.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.72, 0.80, 1.0)
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-58, 165, 0)
	add_child(sun)
	var bulb := OmniLight3D.new()
	bulb.position = Vector3(1.2, 2.8, 2.2)
	bulb.omni_range = 9.0
	bulb.light_color = Color(0.85, 0.82, 0.95)
	bulb.light_energy = 2.4
	add_child(bulb)

	var floor_mi := MeshInstance3D.new()
	var fm := PlaneMesh.new()
	fm.size = Vector2(12, 12)
	floor_mi.mesh = fm
	var fmat := ShaderMaterial.new()
	fmat.shader = load("res://shaders/ps1_mat.gdshader")
	fmat.set_shader_parameter("textured", true)
	fmat.set_shader_parameter("tex", load("res://assets/tex/floor.png"))
	fmat.set_shader_parameter("uv_scale", Vector2(6, 6))
	floor_mi.material_override = fmat
	add_child(floor_mi)

	_pi = Pi.new()
	add_child(_pi)
	_pi.position = Vector3.ZERO
	_pi.set_physics_process(false)          # we drive the anim clock by hand

	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)
	_pi.cam = _cam
	if _args.has("clean"):
		_clean(_pi)
		_clean(floor_mi)

	await _frames(int(_args.get("wait", 30)))
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false, 2.0)
	var img := get_viewport().get_texture().get_image()
	var out: String = _args.get("out", "/tmp/pi_closeup.png")
	img.save_png(out)
	print("CLOSEUP: saved ", out, " ", img.get_size())
	get_tree().quit()


func _process(delta: float) -> void:
	if _pi == null or _cam == null:
		return
	# drive the animation in place: full speed for the stride, zero for idle
	_pi.velocity = Vector3(0, 0, 4.6) if _args.has("stride") else Vector3.ZERO
	_pi._animate(delta)
	var look_y := 1.42 if _args.get("look", "body") == "head" else 0.95
	var pivot := _pi.position + Vector3(0, look_y, 0)
	var yaw := deg_to_rad(float(_args.get("yaw", 30.0)))
	var pitch := deg_to_rad(float(_args.get("pitch", 10.0)))
	var dist := float(_args.get("dist", 3.0 if _args.get("look", "body") == "body" else 1.2))
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.position = pivot + off * dist
	_cam.look_at(pivot)


func _clean(node: Node) -> void:
	for c in _all(node):
		if c is MeshInstance3D:
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			if m != null:
				m.set_shader_parameter("snap_grid", Vector2(4000, 4000))
				m.set_shader_parameter("affine", false)


func _all(node: Node) -> Array:
	var out := []
	var stack := [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
