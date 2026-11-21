class_name Pi
extends CharacterBody3D
## The PI in the flesh: a chunky PS1 box rig in the MACHINE PARTY cast - a
## dried-blood oxblood trench coat over charcoal slacks, a tan straw fedora,
## wrap-around shades, a cigarette burning at the lip corner and white gloves.
## Every box face reads its own cell of the texture atlas (Godot's BoxMesh
## UVs): the mug on the front of the skull, hair on the back, buttons down
## the coat's chest. A nose, ears and a neck give the head real depth.
## The stride crossfades with the idle breath, cadence follows actual speed,
## he banks into turns and leans into the walk, and the coat tails ride a
## damped spring so they follow through on every start and stop.
## He walks where the camera looks. No combat, no health - the office is a
## place to think, not to fight.

const MAT := preload("res://shaders/ps1_mat.gdshader")
const SPEED := 4.6
const TURN := 10.0

const BAND := Color(0.24, 0.17, 0.12)   # the hat band, dark leather
const SHOE := Color(0.10, 0.09, 0.12)
const EMBER := Color(1.0, 0.45, 0.16)
const CIG := Color(0.92, 0.9, 0.86)

var cam: Camera3D               # the office orbit cam; the walk follows it
var _idle_t := 0.0              # the breath / glance clock, always running
var _walk_t := 0.0              # the stride clock, advances with real speed
var _blend := 0.0               # 0 = idle pose, 1 = stride pose, crossfaded
var _lean := 0.0                # the bank into a turn, smoothed
var _fwd_lean := 0.0            # the lean into the walk, smoothed
var _tail_a := 0.06             # coat tail spring angle
var _tail_v := 0.0              # coat tail spring velocity
var _torso: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _tails: Node3D
var _head: Node3D
var _ember: MeshInstance3D


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.3
	cs.shape = shape
	cs.position = Vector3(0, 0.65, 0)
	add_child(cs)
	_build_rig()


func _build_rig() -> void:
	# the hips sit at 0.52: legs swing from there under the coat, the head
	# group is oversized the PS1 way and carries the fedora, the shades and
	# the mug read off the face atlas, the cigarette droops at the lip corner
	_torso = Node3D.new()
	add_child(_torso)
	_torso.position.y = 0.52
	_leg_l = _pivot(_torso, Vector3(-0.12, 0.02, 0))
	_leg_r = _pivot(_torso, Vector3(0.12, 0.02, 0))
	for leg in [_leg_l, _leg_r]:
		_box(leg, Vector3(0.18, 0.5, 0.22), Vector3(0, -0.25, 0), "pi_slacks")
		_box(leg, Vector3(0.18, 0.1, 0.3), Vector3(0, -0.475, 0.04), "", SHOE)
	# the hips fill the gap so no slit opens between the coat and the legs
	_box(_torso, Vector3(0.46, 0.24, 0.32), Vector3(0, 0.14, 0), "pi_slacks")
	_box(_torso, Vector3(0.56, 0.62, 0.4), Vector3(0, 0.48, 0), "pi_coat")
	_tails = _pivot(_torso, Vector3(0, 0.14, -0.21))
	_box(_tails, Vector3(0.5, 0.36, 0.12), Vector3(0, -0.17, 0), "pi_coat")
	_arm_l = _pivot(_torso, Vector3(-0.34, 0.62, 0))
	_arm_r = _pivot(_torso, Vector3(0.34, 0.62, 0))
	for arm in [_arm_l, _arm_r]:
		_box(arm, Vector3(0.15, 0.48, 0.18), Vector3(0, -0.24, 0), "pi_sleeve")
		_box(arm, Vector3(0.11, 0.12, 0.12), Vector3(0, -0.51, 0), "pi_glove")
	_head = _pivot(_torso, Vector3(0, 0.84, 0))
	# the neck plugs the skull into the coat so a glance never opens a gap
	_box(_head, Vector3(0.14, 0.12, 0.14), Vector3(0, -0.1, 0), "pi_skin")
	_box(_head, Vector3(0.3, 0.3, 0.28), Vector3(0, 0.07, 0), "pi_face")
	# the nose under the shades and the ears under the temple arms, tinted
	# a touch shy so they sit in the face instead of flashing white
	var skin_shy := Color(0.93, 0.9, 0.87)
	_box(_head, Vector3(0.045, 0.055, 0.04), Vector3(0, 0.03, 0.15), "pi_skin", skin_shy)
	_box(_head, Vector3(0.03, 0.07, 0.06), Vector3(-0.16, 0.075, 0), "pi_skin", skin_shy)
	_box(_head, Vector3(0.03, 0.07, 0.06), Vector3(0.16, 0.075, 0), "pi_skin", skin_shy)
	# the fedora rides a touch forward, brim dipped over the shades
	var hat := _pivot(_head, Vector3.ZERO)
	hat.rotation.x = 0.04
	_box(hat, Vector3(0.38, 0.18, 0.36), Vector3(0, 0.34, 0), "pi_hat")
	_box(hat, Vector3(0.4, 0.07, 0.38), Vector3(0, 0.27, 0), "", BAND)
	_box(hat, Vector3(0.54, 0.035, 0.52), Vector3(0, 0.225, 0), "pi_hat")
	# the cigarette: a white rod drooping from the lip corner, an ember that
	# pulses on its own rhythm and flares in the walk's wind
	var cig := _pivot(_head, Vector3(0.055, -0.012, 0.14))
	cig.rotation.x = -0.12
	_box(cig, Vector3(0.025, 0.025, 0.1), Vector3(0, 0, 0.05), "", CIG)
	_ember = _box(cig, Vector3(0.026, 0.026, 0.025), Vector3(0, 0, 0.105), "", EMBER)
	var em := _ember.material_override as ShaderMaterial
	em.set_shader_parameter("glow", 1.3)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _box(parent: Node3D, size: Vector3, pos: Vector3, tex := "", tint := Color.WHITE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := ShaderMaterial.new()
	m.shader = MAT
	if tex != "":
		m.set_shader_parameter("textured", true)
		m.set_shader_parameter("tex", load("res://assets/tex/%s.png" % tex))
	m.set_shader_parameter("tint", tint)
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var basis := Basis.IDENTITY
	if cam != null:
		basis = cam.global_basis
	var fwd := -basis.z
	fwd.y = 0.0
	var right := basis.x
	right.y = 0.0
	var wish := right * dir.x + fwd * -dir.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	wish *= SPEED
	wish.x *= Run.mult("move_mult")
	velocity.x = move_toward(velocity.x, wish.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, wish.z, 30.0 * delta)
	velocity.y = -4.0
	move_and_slide()
	_animate(delta)


func _animate(delta: float) -> void:
	var planar := Vector2(velocity.x, velocity.z)
	var speed := planar.length()
	var moving := speed > 0.4
	var frac := clampf(speed / SPEED, 0.0, 1.0)
	# two clocks: the stride advances with real speed so the feet never
	# slide, the breath keeps running underneath so idle is always alive
	_walk_t += delta * 9.5 * frac
	_idle_t += delta * 1.6
	# the walk <-> idle crossfade: quick to pick up, soft to settle
	_blend = _damp(_blend, 1.0 if moving else 0.0, 10.0 if moving else 6.0, delta)
	var amp := frac * _blend
	if moving:
		var prev := rotation.y
		rotation.y = lerp_angle(rotation.y, atan2(planar.x, planar.y), TURN * delta)
		var yaw_rate := wrapf(rotation.y - prev, -PI, PI) / maxf(delta, 0.0001)
		_lean = _damp(_lean, clampf(-yaw_rate * 0.06, -0.18, 0.18), 6.0, delta)
	else:
		_lean = _damp(_lean, 0.0, 6.0, delta)
	_fwd_lean = _damp(_fwd_lean, 0.07 * frac, 5.0, delta)
	var sw := sin(_walk_t)
	var breathe := sin(_idle_t * 1.3)
	var b := _blend
	# the stride pose crossfaded with the idle settle - no snaps either way
	_leg_l.rotation.x = sw * 0.55 * amp
	_leg_r.rotation.x = -sw * 0.55 * amp
	_arm_l.rotation.x = -sw * 0.42 * amp
	_arm_r.rotation.x = sw * 0.42 * amp
	_arm_l.rotation.z = lerpf(0.05 + breathe * 0.02, 0.07, b)
	_arm_r.rotation.z = lerpf(-0.05 - breathe * 0.02, -0.07, b)
	# torso: bob on the stride beat, breath at rest, bank and lean smoothed
	_torso.position.y = 0.52 + lerpf(breathe * 0.012, absf(cos(_walk_t)) * 0.05 * frac, b)
	_torso.rotation.z = sw * 0.04 * amp + _lean
	_torso.rotation.x = _fwd_lean
	# head: scans the office at rest, steady on the move, counter-rolls a
	# little so the shades stay level while the body banks
	_head.rotation.y = lerpf(sin(_idle_t * 0.35) * 0.35, sw * 0.05, b)
	_head.rotation.x = lerpf(breathe * 0.012, 0.03 * frac, b) - _fwd_lean * 0.6
	_head.rotation.z = -_torso.rotation.z * 0.55
	# coat tails: a damped spring chasing the stride kick - they overshoot
	# and settle on their own when he starts, stops, or swings around
	var tail_target := 0.06 + breathe * 0.015 * (1.0 - b) + (0.16 + sw * 0.07) * amp
	_tail_v += (tail_target - _tail_a) * 42.0 * delta
	_tail_v *= exp(-7.0 * delta)
	_tail_a += _tail_v * delta
	_tails.rotation.x = _tail_a
	_tails.rotation.z = _damp(_tails.rotation.z, _lean * 1.6, 5.0, delta)
	# the ember breathes on its own rhythm and flares a little in the wind
	if _ember != null:
		var em := _ember.material_override as ShaderMaterial
		em.set_shader_parameter("glow", 1.1 + sin(_idle_t * 2.7) * 0.45 + frac * 0.25)


func _damp(a: float, b: float, k: float, dt: float) -> float:
	# frame-rate independent exponential settle
	return lerpf(a, b, 1.0 - exp(-k * dt))
