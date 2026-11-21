class_name Pi
extends CharacterBody3D
## The PI in the flesh: a chunky PS1 box rig in the MACHINE PARTY cast - a
## dried-blood oxblood trench coat over charcoal slacks, a tan straw fedora,
## wrap-around shades baked into the face, a cigarette burning at the lip and
## white gloves on both hands. Legs and arms swing on their own pivots, the
## coat tails kick with the stride, and when he stands still he breathes and
## glances around the room. He walks where the camera looks. No combat, no
## health - the office is a place to think, not to fight.

const MAT := preload("res://shaders/ps1_mat.gdshader")
const SPEED := 4.6
const TURN := 10.0

const BAND := Color(0.24, 0.17, 0.12)   # the hat band, dark leather
const LAPEL := Color(0.13, 0.11, 0.12)  # the shadow line down the chest
const SHOE := Color(0.10, 0.09, 0.12)
const EMBER := Color(1.0, 0.45, 0.16)

var cam: Camera3D               # the office orbit cam; the walk follows it
var _t := 0.0
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
        # group is oversized the PS1 way and carries the fedora, the shades
        # read off the face texture, the cigarette hangs at the lip corner
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
        _box(_torso, Vector3(0.12, 0.3, 0.02), Vector3(0, 0.5, 0.215), "", LAPEL)
        _tails = _pivot(_torso, Vector3(0, 0.14, -0.21))
        _box(_tails, Vector3(0.5, 0.36, 0.12), Vector3(0, -0.17, 0), "pi_coat")
        _arm_l = _pivot(_torso, Vector3(-0.34, 0.62, 0))
        _arm_r = _pivot(_torso, Vector3(0.34, 0.62, 0))
        for arm in [_arm_l, _arm_r]:
                _box(arm, Vector3(0.15, 0.48, 0.18), Vector3(0, -0.24, 0), "pi_coat")
                _box(arm, Vector3(0.11, 0.12, 0.12), Vector3(0, -0.51, 0), "pi_glove")
        _head = _pivot(_torso, Vector3(0, 0.84, 0))
        _box(_head, Vector3(0.3, 0.3, 0.28), Vector3(0, 0.07, 0), "pi_face")
        _box(_head, Vector3(0.38, 0.18, 0.36), Vector3(0, 0.34, 0), "pi_hat")
        _box(_head, Vector3(0.4, 0.07, 0.38), Vector3(0, 0.27, 0), "", BAND)
        _box(_head, Vector3(0.54, 0.035, 0.52), Vector3(0, 0.225, 0), "pi_hat")
        # the cigarette: a white rod at the lip corner, an ember that pulses
        _box(_head, Vector3(0.025, 0.025, 0.1), Vector3(0.055, 0.02, 0.17),
                        "", Color(0.92, 0.9, 0.86))
        _ember = _box(_head, Vector3(0.026, 0.026, 0.025),
                        Vector3(0.055, 0.02, 0.225), "", EMBER)
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
        var moving := planar.length() > 0.4
        if moving:
                rotation.y = lerp_angle(rotation.y, atan2(planar.x, planar.y), TURN * delta)
                _t += delta * 9.5
        else:
                _t += delta * 1.6
        var sw := sin(_t)
        if moving:
                # the stride: opposite arm and leg, the coat tails kicking up
                _leg_l.rotation.x = sw * 0.55
                _leg_r.rotation.x = -sw * 0.55
                _arm_l.rotation.x = -sw * 0.42
                _arm_r.rotation.x = sw * 0.42
                _arm_l.rotation.z = 0.0
                _arm_r.rotation.z = 0.0
                _tails.rotation.x = 0.12 + sw * 0.07
                _torso.position.y = 0.52 + absf(cos(_t)) * 0.05
                _torso.rotation.z = sw * 0.04
                _head.rotation.y = sw * 0.05
        else:
                # standing: he breathes, settles, and scans the office
                var breathe := sin(_t * 1.3)
                _leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, 6.0 * delta)
                _leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, 6.0 * delta)
                _arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, 0.0, 6.0 * delta)
                _arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, 0.0, 6.0 * delta)
                _arm_l.rotation.z = 0.05 + breathe * 0.02
                _arm_r.rotation.z = -0.05 - breathe * 0.02
                _tails.rotation.x = lerp_angle(_tails.rotation.x, 0.06 + breathe * 0.015, 4.0 * delta)
                _torso.position.y = 0.52 + breathe * 0.012
                _torso.rotation.z = lerp_angle(_torso.rotation.z, 0.0, 4.0 * delta)
                _head.rotation.y = lerp_angle(_head.rotation.y, sin(_t * 0.35) * 0.35, 2.0 * delta)
        # the ember breathes on its own rhythm, whatever the body does
        if _ember != null:
                var em := _ember.material_override as ShaderMaterial
                em.set_shader_parameter("glow", 1.1 + sin(_t * 2.7) * 0.45)
