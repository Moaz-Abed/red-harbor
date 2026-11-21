class_name Vision
extends Node
## A flashlight: the ray-fan cone ART and the occluded detection that shares
## its geometry. What you see lit is what the owner can actually see.

const Z_CONE := 1                 # floor 0 < cone 1 < actors 2 (world z contract)
const RANGE := 130.0              # flashlight reach, px
const RANGE_SNEAK := 62.0         # detection reach vs a sneaking target, px
const HALF_ANGLE := 0.56          # rad, ~32 degrees each side of the beam
const STEPS := 20                 # raycast fan resolution
const COLOR_CALM := Color(0.62, 0.58, 0.68, 0.30)
const COLOR_SEEN := Color(0.9, 0.3, 0.26, 0.55)
const COLOR_SEARCH := Color(0.9, 0.3, 0.26, 0.38)

var cone: Polygon2D
var _ray: RayCast2D
var _owner: Node2D


func setup(host: Node2D) -> void:
        _owner = host
        cone = Polygon2D.new()
        cone.z_index = Z_CONE
        cone.color = COLOR_CALM
        var mat := CanvasItemMaterial.new()      # a cone reads as light, not fog
        mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
        cone.material = mat
        host.add_child(cone)
        _ray = RayCast2D.new()
        _ray.collision_mask = 2        # only the world layer blocks sight
        _ray.enabled = false
        host.add_child(_ray)


func sees(target: Node2D, beam: Vector2) -> bool:
        if target == null or target.is_dead():
                return false
        var to_p: Vector2 = target.global_position - _owner.global_position
        var eff := (RANGE_SNEAK if target.is_sneaking() else RANGE) * Run.range_mult()
        if to_p.length() > eff:
                return false
        if absf(beam.angle_to(to_p.normalized())) > HALF_ANGLE:
                return false
        _ray.target_position = _ray.to_local(target.global_position)
        _ray.force_raycast_update()
        return not (_ray.is_colliding() and _ray.get_collider() != target)


func update_cone(beam: Vector2) -> void:
        # One Polygon2D fan: every vertex is clipped at the first wall its ray
        # hits, so the cone art stops exactly where the sight does.
        var pts := PackedVector2Array([Vector2.ZERO])
        for i in range(STEPS + 1):
                var a := -HALF_ANGLE + 2.0 * HALF_ANGLE * i / STEPS
                var d := beam.rotated(a)
                _ray.target_position = d * RANGE * Run.range_mult()
                _ray.force_raycast_update()
                var reach := RANGE * Run.range_mult()
                if _ray.is_colliding():
                        reach = _owner.global_position.distance_to(_ray.get_collision_point())
                pts.append(d * reach)
        cone.polygon = pts


func set_color(kind: String) -> void:
        match kind:
                "seen":
                        cone.color = COLOR_SEEN
                "search":
                        cone.color = COLOR_SEARCH
                _:
                        cone.color = COLOR_CALM
