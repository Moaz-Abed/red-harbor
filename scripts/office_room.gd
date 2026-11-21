class_name OfficeRoom
extends Node3D
## The office as a PS1 diorama: the same MAP legend the 2D room used, extruded
## into low-poly boxes. One tile = one unit. The room is a sealed box - four
## walls and a lid - so no camera angle inside it ever opens on the void. The
## walls collide as plain boxes but render as subdivided faces, so the vertex
## lighting can pool on them; every surface wears the one PS1 material.

const MAT := preload("res://shaders/ps1_mat.gdshader")
const TILE := 1.0
const WALL_H := 2.8
const INK := Color("14121c")
const OXBLOOD := Color(0.30, 0.13, 0.16)
const COAT := Color(0.27, 0.26, 0.32)
const HAT := Color(0.22, 0.21, 0.27)
const GLASS_G := Color(0.20, 0.36, 0.23)
const GLASS_B := Color(0.38, 0.24, 0.13)
const GLASS_C := Color(0.55, 0.53, 0.48)
const SLATE := Color(0.29, 0.30, 0.40)
const IRON := Color(0.16, 0.15, 0.17)
const BULB := Color("ffd9a0")
const SODIUM := Color("e8b366")
# compass of the diorama: the door faces -X, the city is north
const SOUTH := Vector3(0, 0, 1)
const WEST := Vector3(-1, 0, 0)
const EAST := Vector3(1, 0, 0)

# legend: # wall · w window · , worn floor · . planks · r rug · d desk ·
# k cabinet · c crate · i radio · ~ neon door · m mat · s scuff
const MAP: Array[String] = [
		"#######ww##########ww##########ww#######",
		"#,,..................................,,#",
		"#......................................#",
		"#..kk............................ic....#",
		"#..kk..................................#",
		"#..kk..................................#",
		"#..kk..........dddd....................#",
		"#..kk..........dddd....................#",
		"#..kk..........dddd.......s............#",
		"#......................................#",
		"#.....................................~#",
		"#.....................................~#",
		"#.....................................m#",
		"#...................rrrrrr.............#",
		"#...................rrrrrr.............#",
		"#...................rrrrrr.............#",
		"#.........s.........rrrrrr.............#",
		"#..ccc.................................#",
		"#................................s.....#",
		"#,,..................................,,#",
		"#,,..................................,,#",
		"########################################",
]

const PROPS := {
		"d": {"tex": "desk", "h": 0.95},
		"k": {"tex": "shelf", "h": 2.3},
		"c": {"tex": "crate", "h": 1.0},
		"i": {"tex": "radio", "h": 0.9},
}
const FLAT_PROPS := {"m": "mat", "s": "scuff"}

const SPOT_CELLS := {"case": Vector2i(16, 10), "drawer": Vector2i(6, 6),
				"radio": Vector2i(33, 4), "door": Vector2i(37, 11)}

# every marker sits ON its prop: the folder on the reading table, the cabinet
# face, the radio top, the door leaf - nothing floats over open floor
const SPOT_MARKS := {
		"case": Vector3(16.85, 1.12, 10.45),
		"drawer": Vector3(5.22, 1.5, 6.5),
		"radio": Vector3(33.5, 0.98, 3.5),
		"door": Vector3(38.72, 1.75, 11.0),
}

var spots := {}                 # name -> Vector3 (the SPOT_CELLS, world space)
var _markers: Array[MeshInstance3D] = []
var _fan: Node3D                # the turbine on the east wall, spinning


func _ready() -> void:
		_build_floor()
		_build_walls()
		_build_windows_and_door()
		_build_props()
		_build_dressing()
		_build_spots()
		_build_markers()


func spot(key: String) -> Vector3:
		return spots[key]


func pulse_markers(t: float) -> void:
		for m in _markers:
				(m.material_override as ShaderMaterial).set_shader_parameter(
								"glow", 0.45 + 0.2 * sin(t * 2.6))
		if _fan != null:
				_fan.rotation.x = t * 0.9        # the turbine turns, slow and heavy


# --- the material factory -------------------------------------------------------------

func _mat(tex_name := "", tint := Color.WHITE, uv := Vector2.ONE, glow := 0.0) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = MAT
		m.set_shader_parameter("tint", tint)
		if tex_name != "":
				m.set_shader_parameter("textured", true)
				m.set_shader_parameter("tex", load("res://assets/tex/%s.png" % tex_name))
		m.set_shader_parameter("uv_scale", uv)
		m.set_shader_parameter("glow", glow)
		return m


func _collider(size: Vector3, pos: Vector3) -> void:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		add_child(body)


func _box(size: Vector3, pos: Vector3, mat: ShaderMaterial, solid := true) -> void:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		add_child(mi)
		if solid:
				var body := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = size
				cs.shape = shape
				body.add_child(cs)
				body.position = pos
				add_child(body)


func _quad(size: Vector2, pos: Vector3, mat: ShaderMaterial, face: Vector3,
				div := Vector2i.ZERO, yaw := 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = size
		if div.x > 0:
				mesh.subdivide_width = div.x
				mesh.subdivide_depth = div.y
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		# spin the base plane to its compass face; the WEST/EAST turns go
		# through "up" first so textures stay upright on the wall
		if face == Vector3.UP:
				if yaw != 0.0:
						mi.rotation.y = yaw
		elif face == SOUTH:
				# upright from both sides: the shader draws backfaces too
				mi.rotation.x = PI * 0.5
		elif face == Vector3.DOWN:
				mi.rotation.x = PI
		elif face == WEST:
				mi.rotation = Vector3(PI * 0.5, -PI * 0.5, 0)
		elif face == EAST:
				mi.rotation = Vector3(PI * 0.5, PI * 0.5, 0)
		add_child(mi)
		return mi


func _cells(ch: String) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for y in MAP.size():
				for x in MAP[y].length():
						if MAP[y][x] == ch:
								out.append(Vector2i(x, y))
		return out


func _runs(ch: String) -> Array[Rect2i]:
		# merge each char's cells into horizontal runs, then stack equal runs
		var cells := _cells(ch)
		var out: Array[Rect2i] = []
		var by_row := {}
		for c in cells:
				if not by_row.has(c.y):
						by_row[c.y] = []
				by_row[c.y].append(c.x)
		for y in by_row:
				var xs: Array = by_row[y]
				xs.sort()
				var i := 0
				while i < xs.size():
						var x0: int = xs[i]
						while i + 1 < xs.size() and xs[i + 1] == xs[i] + 1:
								i += 1
						out.append(Rect2i(x0, y, xs[i] - x0 + 1, 1))
						i += 1
		return out


# --- the build ------------------------------------------------------------------------

func _build_floor() -> void:
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(40, 22)
		mesh.subdivide_width = 24
		mesh.subdivide_depth = 14
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(20, 0, 11)      # the room lives at 0..40 / 0..22
		mi.material_override = _mat("floor", Color.WHITE, Vector2(10, 5.5))
		add_child(mi)
		_collider(Vector3(40, 0.4, 22), Vector3(20, -0.2, 11))
		for r in _runs("r"):                       # the oxblood rug
				_quad(Vector2(r.size.x * TILE, r.size.y * TILE),
								Vector3(r.position.x * TILE + r.size.x * TILE * 0.5, 0.02,
								r.position.y * TILE + r.size.y * TILE * 0.5),
								_mat("rug", Color.WHITE, Vector2(r.size.x * 0.5, r.size.y * 0.5)), Vector3.UP)
		for r in _runs(","):                       # worn patches darken the boards
				_quad(Vector2(r.size.x * TILE, r.size.y * TILE),
								Vector3(r.position.x * TILE + r.size.x * TILE * 0.5, 0.01,
								r.position.y * TILE + r.size.y * TILE * 0.5),
								_mat("scuff", Color(1, 1, 1, 1), Vector2.ONE), Vector3.UP)


func _build_walls() -> void:
		# the shells carry the collisions; the look comes from subdivided inner
		# faces so the vertex lighting pools and falls off across the wall
		_collider(Vector3(40, WALL_H, 1), Vector3(20, WALL_H * 0.5, 0.5))
		_collider(Vector3(1, WALL_H, 22), Vector3(0.5, WALL_H * 0.5, 11))
		_collider(Vector3(1, WALL_H, 22), Vector3(39.5, WALL_H * 0.5, 11))
		# the room is a sealed box: four inner faces, one lid. The camera is
		# clamped inside, so no angle ever opens on the void outside.
		_collider(Vector3(40, WALL_H, 1), Vector3(20, WALL_H * 0.5, 21.5))
		_quad(Vector2(40, WALL_H), Vector3(20, WALL_H * 0.5, 20.99),
						_mat("wall", Color.WHITE, Vector2(10, 1)), SOUTH, Vector2i(16, 4))
		_quad(Vector2(40, WALL_H), Vector3(20, WALL_H * 0.5, 1.01),
						_mat("wall", Color.WHITE, Vector2(10, 1)), SOUTH, Vector2i(16, 4))
		_quad(Vector2(22, WALL_H), Vector3(1.01, WALL_H * 0.5, 11),
						_mat("wall", Color.WHITE, Vector2(5.5, 1)), EAST, Vector2i(8, 4))
		_quad(Vector2(22, WALL_H), Vector3(38.99, WALL_H * 0.5, 11),
						_mat("wall", Color.WHITE, Vector2(5.5, 1)), WEST, Vector2i(8, 4))
		_quad(Vector2(40, 22), Vector3(20, WALL_H, 11),
						_mat("ceiling", Color.WHITE, Vector2(10, 5.5)), Vector3.DOWN,
						Vector2i(24, 14))
		# the tray soffit over the north end, kept clear of the camera ray
		var ceil := _mat("ceiling", Color.WHITE, Vector2(8, 1))
		_box(Vector3(40, 0.12, 1.5), Vector3(20, WALL_H - 0.06, 0.75), ceil, false)
		_box(Vector3(1.5, 0.12, 3.0), Vector3(0.75, WALL_H - 0.06, 1.5), ceil, false)
		_box(Vector3(1.5, 0.12, 3.0), Vector3(39.25, WALL_H - 0.06, 1.5), ceil, false)


func _build_windows_and_door() -> void:
		for i in 3:                                # the rain-streaked city
				var wx: float = [8.0, 20.0, 32.0][i]
				var tex := "window2" if i == 1 else "window"
				_quad(Vector2(2.3, 1.8), Vector3(wx, 1.7, 1.02), _mat("", INK), SOUTH)
				_quad(Vector2(2.0, 1.5), Vector3(wx, 1.7, 1.03),
								_mat(tex, Color.WHITE, Vector2.ONE, 0.78 + 0.08 * i), SOUTH)
		_quad(Vector2(2.2, 2.4), Vector3(38.97, 1.2, 11.0),        # the neon door
						_mat("door", Color.WHITE, Vector2.ONE, 0.8), WEST)


func _build_props() -> void:
		for ch in PROPS:
				var p: Dictionary = PROPS[ch]
				var uv := Vector2.ONE if ch == "i" else Vector2(2, 1)
				var gl := 0.5 if ch == "i" else 0.0    # the radio dial hums
				for r in _runs(ch):
						var w := r.size.x * TILE
						var d := r.size.y * TILE
						_box(Vector3(w, p["h"], d), Vector3(
										r.position.x * TILE + w * 0.5, p["h"] * 0.5,
										r.position.y * TILE + d * 0.5),
										_mat(p["tex"], Color.WHITE, uv, gl))
		for ch in FLAT_PROPS:
				for c in _cells(ch):
						var t: String = FLAT_PROPS[ch]
						_quad(Vector2(0.55, 0.75), Vector3(c.x + 0.5, 0.03, c.y + 0.5),
										_mat(t, Color.WHITE, Vector2.ONE), Vector3.UP)


func _build_dressing() -> void:
		# the wall dressing: the corkboard over the desk, the clock, a vent
		_quad(Vector2(3.6, 1.5), Vector3(16.4, 1.75, 1.07), _mat("corkboard"), SOUTH)
		_quad(Vector2(0.55, 0.55), Vector3(24.6, 2.15, 1.07), _mat("clock"), SOUTH)
		_quad(Vector2(0.5, 0.5), Vector3(38.94, 2.1, 6.5), _mat("vent"), WEST)
		for sx in [10.0, 26.0]:                    # the brass sconces
				_box(Vector3(0.18, 0.32, 0.14), Vector3(sx, 2.0, 1.1), _mat("", SLATE))
				_quad(Vector2(0.1, 0.16), Vector3(sx, 2.0, 1.18),
								_mat("", BULB * 0.4, Vector2.ONE, 1.1), SOUTH)
		# the desk top: the typewriter, the phone, the ashtray, the lamp
		_box(Vector3(0.52, 0.16, 0.42), Vector3(16.0, 1.03, 6.6), _mat("typewriter"), false)
		_box(Vector3(0.3, 0.12, 0.26), Vector3(17.4, 1.01, 7.5), _mat("phone"), false)
		_box(Vector3(0.14, 0.05, 0.14), Vector3(17.9, 0.975, 6.3),
						_mat("", Color(0.75, 0.72, 0.66)), false)
		_box(Vector3(0.16, 0.05, 0.16), Vector3(15.5, 0.975, 7.6), _mat("", SLATE), false)
		_box(Vector3(0.05, 0.34, 0.05), Vector3(15.5, 1.2, 7.6), _mat("", SLATE), false)
		_box(Vector3(0.2, 0.12, 0.2), Vector3(15.5, 1.4, 7.6),
						_mat("", SODIUM * 0.4, Vector2.ONE, 1.1), false)
		_collider(Vector3(0.3, 1.4, 0.3), Vector3(15.5, 1.2, 7.6))
		# the reading table, the case spot's real body: legs, top, the dealt
		# folder lying open on it under its marker
		var wood := _mat("desk", Color.WHITE, Vector2.ONE)
		_box(Vector3(1.3, 0.08, 1.0), Vector3(16.7, 0.91, 10.5), wood)
		for leg in [Vector3(16.15, 0.87, 10.1), Vector3(17.25, 0.87, 10.1),
						Vector3(16.15, 0.87, 10.9), Vector3(17.25, 0.87, 10.9)]:
				_box(Vector3(0.09, 0.87, 0.09), leg, _mat("", Color(0.16, 0.12, 0.09)))
		_box(Vector3(0.42, 0.05, 0.31), Vector3(16.85, 0.975, 10.45),
						_mat("paper", Color(0.72, 0.70, 0.66), Vector2.ONE, 0.3), false)
		_quad(Vector2(0.5, 0.65), Vector3(17.1, 0.96, 10.75),
						_mat("news"), Vector3.UP, Vector2i.ZERO, 0.4)
		# the bar shelf with the bottle row, on the west wall
		_box(Vector3(0.35, 1.0, 2.2), Vector3(0.85, 0.5, 13.0), _mat("bottles"))
		for i in 4:
				var bcol: Color = [GLASS_G, GLASS_B, GLASS_C, GLASS_B][i]
				_box(Vector3(0.1, 0.26, 0.1), Vector3(0.85, 1.13, 12.3 + i * 0.5),
								_mat("", bcol), false)
		# the file wall: the cabinet bank wears a paper load on its top, so
		# the upgrade spot reads as a working drawer front, not bare boxes
		for i in 6:
				_box(Vector3(0.34, 0.14, 0.5),
								Vector3(3.6 + (i % 2) * 0.7, 2.37, 3.8 + floori(i * 0.5) * 1.9),
								_mat("paper", Color(0.62, 0.60, 0.57), Vector2.ONE, 0.12), false)
				_box(Vector3(0.1, 0.24, 0.36),
								Vector3(3.9 + (i % 2) * 0.75, 2.53, 3.9 + floori(i * 0.5) * 1.9),
								_mat("", Color(0.44, 0.42, 0.38)), false)
		# the coat rack by the neon door, still wearing yesterday's coat
		for part in [[Vector3(0.32, 0.06, 0.32), Vector3(38.3, 0.03, 14.5)],
						[Vector3(0.07, 1.66, 0.07), Vector3(38.3, 0.86, 14.5)],
						[Vector3(0.4, 0.05, 0.05), Vector3(38.3, 1.68, 14.5)],
						[Vector3(0.05, 0.05, 0.4), Vector3(38.3, 1.68, 14.5)]]:
				_box(part[0], part[1], _mat("", Color(0.2, 0.14, 0.1)), false)
		_box(Vector3(0.34, 0.55, 0.24), Vector3(38.3, 1.32, 14.5), _mat("", COAT), false)
		_box(Vector3(0.28, 0.09, 0.28), Vector3(38.3, 1.74, 14.5), _mat("", HAT), false)
		_collider(Vector3(0.4, 1.8, 0.4), Vector3(38.3, 0.9, 14.5))
		# the armchair on the rug, facing the desk
		for part in [[Vector3(0.85, 0.4, 0.85), Vector3(20.7, 0.2, 15.0)],
						[Vector3(0.25, 0.8, 0.85), Vector3(20.4, 0.6, 15.0)],
						[Vector3(0.85, 0.55, 0.2), Vector3(20.7, 0.475, 14.675)],
						[Vector3(0.85, 0.55, 0.2), Vector3(20.7, 0.475, 15.325)]]:
				_box(part[0], part[1], _mat("", OXBLOOD), false)
		_collider(Vector3(0.9, 0.9, 0.9), Vector3(20.7, 0.45, 15.0))
		# the floor lamp beside the chair, iron now, not blue
		_box(Vector3(0.3, 0.06, 0.3), Vector3(19.2, 0.03, 16.9), _mat("", IRON))
		_box(Vector3(0.06, 1.5, 0.06), Vector3(19.2, 0.78, 16.9), _mat("", IRON))
		_box(Vector3(0.26, 0.16, 0.26), Vector3(19.2, 1.63, 16.9),
						_mat("", SODIUM * 0.4, Vector2.ONE, 1.1), false)
		_collider(Vector3(0.35, 1.75, 0.35), Vector3(19.2, 0.875, 16.9))
		# the tired plant in the corner by the door
		_box(Vector3(0.34, 0.34, 0.34), Vector3(38.2, 0.17, 19.6),
						_mat("", Color(0.36, 0.2, 0.17)), false)
		for part in [[Vector3(0.44, 0.34, 0.44), Vector3(38.2, 0.5, 19.6), Color(0.18, 0.25, 0.14)],
						[Vector3(0.28, 0.3, 0.28), Vector3(38.2, 0.8, 19.6), Color(0.22, 0.28, 0.15)],
						[Vector3(0.12, 0.24, 0.12), Vector3(38.2, 1.05, 19.6), Color(0.25, 0.3, 0.16)]]:
				_box(part[0], part[1], _mat("", part[2]), false)
		_collider(Vector3(0.45, 0.6, 0.45), Vector3(38.2, 0.3, 19.6))
		# the empties left on the crate, a dropped newspaper
		for i in 3:
				var ccol: Color = [GLASS_G, GLASS_B, GLASS_C][i]
				_box(Vector3(0.09, 0.26, 0.09),
								Vector3(2.5 + i * 0.25, 1.13, 16.55 + (i % 2) * 0.2),
								_mat("", ccol), false)
		_quad(Vector2(0.5, 0.65), Vector3(5.2, 0.03, 18.4),
						_mat("news"), Vector3.UP, Vector2i.ZERO, 0.5)
		_build_industrial()


func _build_industrial() -> void:
		# the MACHINE PARTY steel: a turbine bolted to the east wall, conduit
		# runs over the north wall, drop pipes from the lid. Iron everywhere,
		# all of it solid, so the camera ray keeps the lens out of the steel.
		var iron := _mat("", IRON)
		var iron_l := _mat("", Color(0.2, 0.19, 0.22))
		# the turbine: housing ring bolted to the wall, the blade quad spins
		_box(Vector3(0.16, 1.9, 1.9), Vector3(38.9, 1.85, 16.5), iron)
		_fan = Node3D.new()
		_fan.position = Vector3(38.8, 1.85, 16.5)
		add_child(_fan)
		var blades := MeshInstance3D.new()
		var bm := PlaneMesh.new()
		bm.size = Vector2(1.7, 1.7)
		blades.mesh = bm
		blades.material_override = _mat("fan", Color.WHITE, Vector2.ONE, 0.28)
		blades.rotation = Vector3(PI * 0.5, PI * 0.5, 0)
		_fan.add_child(blades)
		_box(Vector3(0.2, 0.2, 0.2), Vector3(38.82, 1.85, 16.5), iron_l, false)
		for jy in [1.0, 2.7]:                     # the housing brackets
				_box(Vector3(0.1, 0.14, 0.3), Vector3(38.88, jy, 15.7), iron_l)
				_box(Vector3(0.1, 0.14, 0.3), Vector3(38.88, jy, 17.3), iron_l)
		# the conduit run over the north wall, three lines with junction boxes
		for k in 3:
				_box(Vector3(38.0, 0.08, 0.08),
								Vector3(20.0, 2.42 + k * 0.11, 1.32), iron)
		for jx in [8.0, 20.0, 32.0]:
				_box(Vector3(0.22, 0.34, 0.16), Vector3(jx, 2.58, 1.32), iron_l)
		# two drop pipes from the lid, with caps
		for dpx in [12.5, 27.5]:
				_box(Vector3(0.14, 1.3, 0.14), Vector3(dpx, 2.15, 1.5), iron_l)
				_box(Vector3(0.2, 0.08, 0.2), Vector3(dpx, 2.76, 1.5), iron)
		# one long feed pipe along the east wall, over the fan
		_box(Vector3(0.08, 0.08, 18.0), Vector3(38.68, 2.64, 10.0), iron)
		for bz in [3.0, 10.0, 17.0]:
				_box(Vector3(0.16, 0.2, 0.1), Vector3(38.68, 2.64, bz), iron_l)


func _build_spots() -> void:
		for key in SPOT_CELLS:
				var c: Vector2i = SPOT_CELLS[key]
				spots[key] = Vector3(c.x + 0.5, 0.0, c.y + 0.5)


func _build_markers() -> void:
		# A small sodium tag marks every thing you can use - pinned close to
		# its prop's body. The tint stays dark so the room's ambient can't
		# blow it out; the pulse rides the emission, so it glows, not glares.
		for key in SPOT_MARKS:
				var mi := _quad(Vector2(0.2, 0.2), SPOT_MARKS[key],
								_mat("", SODIUM * 0.36, Vector2.ONE, 0.45), SOUTH)
				_markers.append(mi)
