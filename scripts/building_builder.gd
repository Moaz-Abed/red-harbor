extends Node2D
## Red Harbor - the building: one night's 9-12 rooms, assembled from templates
## (roadmap 4.2: "a hand-arranged building of 8-12 rooms assembled from
## templates").
##
## The frame is the same one-screen 40 x 22 tile map as the street block,
## which is EXACTLY a 3 x 3 grid of rooms (interior 12 x 6, walls 1 thick):
##
##   x walls at 0, 13, 26, 39      y walls at 0, 7, 14, 21
##
## The deal, in order:
##   1. Everything starts solid; the nine room interiors are carved out.
##   2. 0-3 rooms (never the entry or the back-door room) are split in two
##      by a partition wall with a doorway, so a building has 9-12 rooms.
##   3. A random spanning tree over the 3 x 3 grid + 2-3 extra edges decides
##      which neighbouring rooms get a 2-tile doorway (always connected,
##      sometimes with loops so a chase has more than one way round).
##   4. Each room is dressed from a furniture TEMPLATE. Templates only
##      touch the room's inner area; the 1-tile ring around every interior
##      stays open, so every doorway always reaches every other doorway.
##   5. The PI starts in one corner room, the back door is in the opposite
##      corner room, the jobs are dealt one per room next to furniture, and
##      each guard gets a patrol loop through three rooms (A* does the
##      walking, so patrols and chases go through doorways, not walls).
##
## TIGHT SPOTS. A body is 12 x 18 px, so a 1-tile-tall slot (16 px, wall above
## AND below) is too low to walk through standing. Those cells are "squeeze"
## cells: the PI can CRAWL through them (player.gd, the squeeze animation) but
## guards cannot - the guard nav grid marks them solid, so patrols and chases
## route around. Deliberate crawl holes (a 1-tile gap in a wall between two
## rooms) give the PI shortcuts guards cannot use; furniture can create more by
## accident. A deal is only kept if every room, job and the back door is
## reachable WITHOUT squeezing, so a crawl hole is always a shortcut, never a
## requirement. Squeeze cells are drawn with the crawlspace tile.
##
## Floor 1 enters bottom-left and leaves top-right; the lower floor mirrors
## that (enter bottom-right, leave top-left) and is dressed from the denser
## archive / storeroom templates.
##
## generate() paints the TileMapLayer and returns the placement plan in grid
## cells. World position = cell * 16 + 8, plus the map's (0, 4) centering
## offset (night.gd owns that conversion). Walls AND furniture carry TileSet
## physics on collision layer 2 ("world"): the player collides with them,
## guard sight rays stop at them, and the cone fan is cut by them.

const TILE := 16
const W := 40
const H := 22
const COLS := 3
const ROWS := 3
const ROOM_W := 12
const ROOM_H := 6
const PITCH_X := 13
const PITCH_Y := 7
const MAP_OFFSET := Vector2(0, 4)
const ATLAS := preload("res://assets/tiles/harbor_tiles.png")

# atlas columns in harbor_tiles.png (0-5 street set, 6-9 building set)
const T_FLOOR_A := 0
const T_FLOOR_B := 1
const T_DRAIN := 2
const T_WALL := 3
const T_WALL_TOP := 4
const T_NEON := 5
const T_DESK := 6
const T_CABINET := 7
const T_RUG := 8
const T_CRATE := 9
const T_CRAWL := 10
const SOLID_TILES := [T_WALL, T_WALL_TOP, T_DESK, T_CABINET, T_CRATE]

# Furniture templates for a whole room: 10 wide x 2 tall, stamped on the
# MIDDLE two rows of the 6-row interior. That leaves two open rows above and
# two below, so no wall-hugging corridor is ever a 1-tile slot - the tight
# spots in a building are the deliberate crawl holes, not accidents.
#   .  floor   r  rug (walkable)   d  desk   k  filing cabinet   c  crate
const FULL_TEMPLATES := [
	["k.k.k.k.k.", "k.k.k.k.k."],   # 0 records office
	[".dd..dd...", ".dd..dd..."],   # 1 office pool
	["..dddddd..", "..dddddd.."],   # 2 boardroom
	["kk.kk.kk.k", "kk.kk.kk.k"],   # 3 archive stacks
	["cc....cc..", "cc.cc.cc.c"],   # 4 storeroom
	["rrrrrr....", "rrrrrr..d."],   # 5 lounge
	["kk....dd..", "kk....dd.."],   # 6 switchboard
	["..k....k..", "..k....k.."],   # 7 open hall
]
const VAULT_TEMPLATES := [0, 3, 4, 7]        # indices used on the lower floor

# Small templates for the two halves of a split room (4 wide; the narrower
# right half crops the last column).
const HALF_TEMPLATES := [
	["d..k", "d..k"],
	["k..k", "...."],
	["..cc", "r.cc"],
]

var _rng := RandomNumberGenerator.new()
var _solid := {}        # Vector2i -> true: walls + furniture
var _furn := {}         # Vector2i -> "d" | "k" | "c"
var _rug := {}
var _neon := {}
var _puddle := {}
var _open := {}         # reachable walkable cells (BFS from the entry), squeeze cells included
var _squeeze := {}      # open cells with wall/furniture above AND below: crawl only
var _stand := {}        # cells reachable WITHOUT squeezing (what guards can use)
var _holes := 0
var _rooms: Array[Dictionary] = []     # {rect: Rect2i, grid: Vector2i}
var _edges: Array = []                 # [Vector2i, Vector2i] doorways between grid rooms
var _map: Array[String] = []
var nav: AStarGrid2D


func generate(rng_seed: int = -1, params: Dictionary = {}) -> Dictionary:
	# rng_seed >= 0 pins the deal (debug / QA); -1 = a fresh random night.
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var plan := _deal(params)
	_build_map_strings()
	_paint_tiles()
	return plan


# --- the deal ------------------------------------------------------------------------

func _deal(params: Dictionary) -> Dictionary:
	# Keep dealing until the building is fair (see TIGHT SPOTS above).
	for attempt in 80:
		var plan := _deal_once(params)
		if not plan.is_empty():
			return plan
	assert(false, "building_builder: no fair deal in 80 tries")
	return {}


func _deal_once(params: Dictionary) -> Dictionary:
	var floor_no: int = params.get("floor", 1)
	var tasks: Array = params.get("tasks", ["documents", "bug", "ledger"])
	var guard_count: int = params.get("guards", 3)
	var lower := floor_no >= 2
	_solid.clear()
	_furn.clear()
	_rug.clear()
	_neon.clear()
	_puddle.clear()
	_rooms.clear()
	_edges.clear()

	# 1. everything solid, then carve the nine interiors
	for y in H:
		for x in W:
			_solid[Vector2i(x, y)] = true
	for ry in ROWS:
		for rx in COLS:
			var r := _interior(Vector2i(rx, ry))
			for cy in range(r.position.y, r.end.y):
				for cx in range(r.position.x, r.end.x):
					_solid.erase(Vector2i(cx, cy))

	var entry_grid := Vector2i(COLS - 1, ROWS - 1) if lower else Vector2i(0, ROWS - 1)
	var exit_grid := Vector2i(0, 0) if lower else Vector2i(COLS - 1, 0)

	# 2. which rooms get split (never the entry or exit room)
	var split := {}
	var candidates: Array = []
	for ry in ROWS:
		for rx in COLS:
			var g := Vector2i(rx, ry)
			if g != entry_grid and g != exit_grid:
				candidates.append(g)
	_shuffle(candidates)
	var n_split := _rng.randi_range(0, 3)
	for i in n_split:
		split[candidates[i]] = true

	# 3. doorways: random spanning tree + a few loops
	_build_graph()
	for e in _edges:
		_carve_door(e[0], e[1], split)

	# partition walls (after doors, so no doorway can land in one)
	var split_gap := {}
	for g in split:
		var r := _interior(g)
		var wx := r.position.x + 6
		var gy := r.position.y + _rng.randi_range(1, 3)
		split_gap[g] = gy
		for cy in range(r.position.y, r.end.y):
			if cy != gy and cy != gy + 1:
				_solid[Vector2i(wx, cy)] = true

	_carve_crawl_holes()

	# the room list: one rect per room, two per split room
	for ry in ROWS:
		for rx in COLS:
			var g := Vector2i(rx, ry)
			var r := _interior(g)
			if split.has(g):
				_rooms.append({"rect": Rect2i(r.position.x, r.position.y, 6, ROOM_H), "grid": g})
				_rooms.append({"rect": Rect2i(r.position.x + 7, r.position.y, 5, ROOM_H), "grid": g})
			else:
				_rooms.append({"rect": r, "grid": g})

	# 4. furniture templates
	for room in _rooms:
		_dress_room(room["rect"], lower)

	# 5. the two anchors
	var entry_rect := _interior(entry_grid)
	var exit_rect := _interior(exit_grid)
	var entry_cell := Vector2i(entry_rect.position.x + (9 if lower else 2), entry_rect.end.y - 1)
	var exit_cell := Vector2i(exit_rect.position.x + _rng.randi_range(2, 9), exit_rect.position.y)
	for dx in [-1, 0, 1]:
		var nc := Vector2i(exit_cell.x + dx, exit_cell.y + 1)
		if not _solid.has(nc):
			_neon[nc] = true

	# reachability (defensive: seal any pocket a template might have made)
	_flood_open(entry_cell)
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if not _solid.has(c) and not _open.has(c):
				_solid[c] = true

	# tight spots: only the PI can crawl through them; the deal must not need them
	_find_squeeze()
	if _squeeze.has(entry_cell) or _squeeze.has(exit_cell):
		return {}
	_flood_stand(entry_cell)
	if not _stand.has(exit_cell):
		return {}
	_build_nav()

	var centers := _room_centers()
	if centers.size() != _rooms.size():
		return {}                           # a room only reachable by crawling
	# 6. jobs, one per room, next to furniture
	var task_list := _deal_tasks(tasks, entry_cell, exit_cell)
	if task_list.size() != tasks.size():
		return {}
	# 7. patrols
	var routes := _deal_routes(guard_count, entry_cell, centers)

	_dress_floor(exit_cell)

	# Tripwires: the plan must sit on reachable floor or the night is
	# unplayable by construction. The shipped night test re-verifies it.
	assert(_open.has(entry_cell) and _open.has(exit_cell))
	for t in task_list:
		assert(_open.has(t["cell"]))

	return {
		"floor": floor_no,
		"player": entry_cell,
		"exit": exit_cell,
		"tasks": task_list,
		"guards": routes,
		"rooms": _rooms.size(),
		"room_centers": centers,
		"nav": nav,
		"squeeze": _squeeze.duplicate(),
		"crawl_holes": _holes,
	}


func _interior(g: Vector2i) -> Rect2i:
	return Rect2i(1 + PITCH_X * g.x, 1 + PITCH_Y * g.y, ROOM_W, ROOM_H)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _grid_neighbors(g: Vector2i) -> Array:
	var out: Array = []
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		var n: Vector2i = g + d
		if n.x >= 0 and n.y >= 0 and n.x < COLS and n.y < ROWS:
			out.append(n)
	return out


func _has_edge(a: Vector2i, b: Vector2i) -> bool:
	for e in _edges:
		if (e[0] == a and e[1] == b) or (e[0] == b and e[1] == a):
			return true
	return false


func _build_graph() -> void:
	# Random DFS spanning tree (always connected) + 2-3 extra doorways.
	var start := Vector2i(_rng.randi_range(0, COLS - 1), _rng.randi_range(0, ROWS - 1))
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: Vector2i = stack.back()
		var fresh: Array = []
		for n in _grid_neighbors(cur):
			if not seen.has(n):
				fresh.append(n)
		if fresh.is_empty():
			stack.pop_back()
			continue
		var nxt: Vector2i = fresh[_rng.randi_range(0, fresh.size() - 1)]
		_edges.append([cur, nxt])
		seen[nxt] = true
		stack.append(nxt)
	var spare: Array = []
	for ry in ROWS:
		for rx in COLS:
			var g := Vector2i(rx, ry)
			for n in _grid_neighbors(g):
				if (n.x > g.x or n.y > g.y) and not _has_edge(g, n):
					spare.append([g, n])
	_shuffle(spare)
	for i in mini(_rng.randi_range(2, 3), spare.size()):
		_edges.append(spare[i])


func _carve_door(a: Vector2i, b: Vector2i, split: Dictionary) -> void:
	var ra := _interior(a)
	if a.y == b.y:
		# side by side: doorway in the shared vertical wall, 2 tiles tall
		var left := a if a.x < b.x else b
		var rl := _interior(left)
		var wx := rl.end.x               # the wall column between the rooms
		var y := rl.position.y + _rng.randi_range(1, 3)
		_solid.erase(Vector2i(wx, y))
		_solid.erase(Vector2i(wx, y + 1))
	else:
		# stacked: doorway in the shared horizontal wall, 2 tiles wide. The
		# columns must clear the partition of a split room above or below.
		var top := a if a.y < b.y else b
		var rt := _interior(top)
		var wy := rt.end.y               # the wall row between the rooms
		var options: Array = []
		for x in range(ra.position.x + 1, ra.position.x + 10):
			if (split.has(a) or split.has(b)) and (x + 1 >= ra.position.x + 6 and x <= ra.position.x + 6):
				continue
			options.append(x)
		var dx: int = options[_rng.randi_range(0, options.size() - 1)]
		_solid.erase(Vector2i(dx, wy))
		_solid.erase(Vector2i(dx + 1, wy))


func _dress_room(rect: Rect2i, lower: bool) -> void:
	var inner := rect.grow(-1)
	var tpl: Array
	if rect.size.x == ROOM_W:
		if lower:
			tpl = FULL_TEMPLATES[VAULT_TEMPLATES[_rng.randi_range(0, VAULT_TEMPLATES.size() - 1)]]
		else:
			tpl = FULL_TEMPLATES[_rng.randi_range(0, FULL_TEMPLATES.size() - 1)]
	else:
		tpl = HALF_TEMPLATES[_rng.randi_range(0, HALF_TEMPLATES.size() - 1)]
	var flip := _rng.randf() < 0.5
	for ty in tpl.size():
		var row: String = tpl[ty]
		for tx in row.length():
			if tx >= inner.size.x:
				continue
			var ch := row[row.length() - 1 - tx] if flip and rect.size.x == ROOM_W else row[tx]
			var cell := Vector2i(inner.position.x + tx, inner.position.y + 1 + ty)   # middle two rows
			match ch:
				"d", "k", "c":
					_solid[cell] = true
					_furn[cell] = ch
				"r":
					_rug[cell] = true


func _flood_open(start: Vector2i) -> void:
	_open.clear()
	var queue: Array[Vector2i] = [start]
	_open[start] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= W or nxt.y >= H:
				continue
			if _open.has(nxt) or _solid.has(nxt):
				continue
			_open[nxt] = true
			queue.append(nxt)


func _build_nav() -> void:
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, W, H)
	nav.cell_size = Vector2(TILE, TILE)
	# path points come back as world positions of cell centres
	nav.offset = Vector2(TILE / 2.0, TILE / 2.0) + MAP_OFFSET
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for c in _solid:
		nav.set_point_solid(c, true)
	for c in _squeeze:
		nav.set_point_solid(c, true)        # guards are too bulky to crawl


# --- tight spots ------------------------------------------------------------------------

func _carve_crawl_holes() -> void:
	# A 1-tile hole through a wall between side-by-side rooms: a slot 16 px
	# tall, too low to walk through but fine to crawl (and guards cannot).
	_holes = 0
	var pairs: Array = []
	for ry in ROWS:
		for rx in range(COLS - 1):
			pairs.append(Vector2i(rx, ry))
	_shuffle(pairs)
	var want := _rng.randi_range(1, 2)
	for g in pairs:
		if _holes >= want:
			break
		var r := _interior(g)
		var wx := r.end.x
		var ys: Array = []
		for y in range(r.position.y + 1, r.end.y - 1):
			if _solid.has(Vector2i(wx, y)) and _solid.has(Vector2i(wx, y - 1)) and _solid.has(Vector2i(wx, y + 1)):
				ys.append(y)
		if ys.is_empty():
			continue
		_solid.erase(Vector2i(wx, ys[_rng.randi_range(0, ys.size() - 1)]))
		_holes += 1


func _find_squeeze() -> void:
	_squeeze.clear()
	for c in _open.keys():
		if _solid.has(c + Vector2i.UP) and _solid.has(c + Vector2i.DOWN):
			_squeeze[c] = true


func _flood_stand(start: Vector2i) -> void:
	_stand.clear()
	var queue: Array[Vector2i] = [start]
	_stand[start] = true
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var nxt: Vector2i = cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= W or nxt.y >= H:
				continue
			if _stand.has(nxt) or _solid.has(nxt) or _squeeze.has(nxt):
				continue
			_stand[nxt] = true
			queue.append(nxt)


func is_squeeze(c: Vector2i) -> bool:
	return _squeeze.has(c)


# --- jobs ------------------------------------------------------------------------------

func _room_of(cell: Vector2i) -> int:
	for i in _rooms.size():
		if _rooms[i]["rect"].has_point(cell):
			return i
	return -1


func _deal_tasks(tasks: Array, entry_cell: Vector2i, exit_cell: Vector2i) -> Array:
	var avoid := [_room_of(entry_cell), _room_of(exit_cell)]
	var pool: Array = []
	for i in _rooms.size():
		if not avoid.has(i):
			pool.append(i)
	_shuffle(pool)
	var out: Array = []
	var order: Array = tasks.duplicate()
	_shuffle(order)
	for type in order:
		var placed := false
		for pi in pool.size():
			var ri: int = pool[pi]
			var cell := _task_cell(_rooms[ri]["rect"])
			if cell.x >= 0:
				out.append({"cell": cell, "type": type, "room": ri})
				pool.remove_at(pi)
				placed = true
				break
		if not placed:
			return []
	return out


func _task_cell(rect: Rect2i) -> Vector2i:
	# An open cell beside furniture (a desk to bug, a cabinet to rifle).
	var good: Array = []
	var any: Array = []
	for cy in range(rect.position.y, rect.end.y):
		for cx in range(rect.position.x, rect.end.x):
			var c := Vector2i(cx, cy)
			if _solid.has(c) or not _stand.has(c):
				continue
			any.append(c)
			for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				if _furn.has(c + d):
					good.append(c)
					break
	if not good.is_empty():
		return good[_rng.randi_range(0, good.size() - 1)]
	if not any.is_empty():
		return any[_rng.randi_range(0, any.size() - 1)]
	return Vector2i(-1, -1)


# --- patrols -----------------------------------------------------------------------------

func _room_centers() -> Array:
	var out: Array = []
	for room in _rooms:
		var rect: Rect2i = room["rect"]
		var mid := rect.position + rect.size / 2
		var best := mid
		var best_d := 9999
		for cy in range(rect.position.y, rect.end.y):
			for cx in range(rect.position.x, rect.end.x):
				var c := Vector2i(cx, cy)
				if _stand.has(c) and not _solid.has(c):
					var d := absi(c.x - mid.x) + absi(c.y - mid.y)
					if d < best_d:
						best_d = d
						best = c
		if best_d < 9999:
			out.append(best)
	return out


func path_len(a: Vector2i, b: Vector2i) -> int:
	return nav.get_id_path(a, b).size()


func _deal_routes(count: int, entry_cell: Vector2i, centers: Array) -> Array:
	# A patrol is a loop through three room centres. Guards start at least
	# a room away from the PI, and each guard walks a different loop.
	var routes: Array = []
	var starts_used: Array = []
	var entry_room := _room_of(entry_cell)
	for g in count:
		var route: Array = []
		for attempt in 200:
			var s: int = _rng.randi_range(0, centers.size() - 1)
			if s == entry_room or starts_used.has(s):
				continue
			if path_len(entry_cell, centers[s]) < 14:
				continue
			var legs: Array = [centers[s]]
			var tries := 0
			while legs.size() < 3 and tries < 40:
				tries += 1
				var o: int = _rng.randi_range(0, centers.size() - 1)
				var oc: Vector2i = centers[o]
				if legs.has(oc):
					continue
				var d := path_len(centers[s], oc)
				if d < 8 or d > 36:
					continue
				legs.append(oc)
			if legs.size() >= 2:
				route = legs
				starts_used.append(s)
				break
		if route.is_empty():
			# belt and braces: first two room centres far from the entry
			var far: Array = []
			for c in centers:
				if path_len(entry_cell, c) >= 10:
					far.append(c)
			if far.size() < 2:
				far = centers.duplicate()
			route = [far[g % far.size()], far[(g + 1) % far.size()]]
		routes.append(route)
	return routes


# --- dressing + painting ---------------------------------------------------------------

func _dress_floor(exit_cell: Vector2i) -> void:
	var cells: Array = _stand.keys()
	var n := 0
	var guard := 0
	while n < 14 and guard < 400:
		guard += 1
		var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
		if _neon.has(c) or _puddle.has(c) or _rug.has(c) or c == exit_cell:
			continue
		_puddle[c] = true
		n += 1


func _build_map_strings() -> void:
	_map.clear()
	for y in H:
		var row := ""
		for x in W:
			var c := Vector2i(x, y)
			if _furn.has(c) and _solid.has(c):
				row += _furn[c]
			elif _solid.has(c):
				row += "#"
			elif _squeeze.has(c):
				row += "="
			elif _neon.has(c):
				row += "~"
			elif _rug.has(c):
				row += "r"
			elif _puddle.has(c):
				row += ","
			else:
				row += "."
		_map.append(row)


func map_strings() -> Array[String]:
	return _map


func is_open(c: Vector2i) -> bool:
	return _open.has(c)


func _paint_tiles() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)

	var src := TileSetAtlasSource.new()
	src.texture = ATLAS
	src.texture_region_size = Vector2i(TILE, TILE)
	for t in 11:
		src.create_tile(Vector2i(t, 0))
	# The source must be bound to the TileSet BEFORE any TileData touches
	# physics (see level_builder.gd: the phase-through bug).
	ts.add_source(src, 0)
	for t in SOLID_TILES:
		var td := src.get_tile_data(Vector2i(t, 0), 0)
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, PackedVector2Array([
			Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
		]))
		assert(td.get_collision_polygons_count(0) == 1)

	var layer := TileMapLayer.new()
	layer.tile_set = ts
	layer.position = MAP_OFFSET   # centre the 352 px map in the 360 px view
	add_child(layer)
	for y in H:
		for x in W:
			var t := _tile_for(x, y)
			if t >= 0:
				layer.set_cell(Vector2i(x, y), 0, Vector2i(t, 0))


func _tile_for(x: int, y: int) -> int:
	var row: String = _map[y]
	match row[x]:
		"#":
			var covered := false
			if y > 0:
				var above: String = _map[y - 1]
				covered = above[x] == "#"
			return T_WALL if covered else T_WALL_TOP
		".":
			return T_FLOOR_A
		",":
			return T_FLOOR_B
		"~":
			return T_NEON
		"r":
			return T_RUG
		"d":
			return T_DESK
		"k":
			return T_CABINET
		"c":
			return T_CRATE
		"=":
			return T_CRAWL
	return -1
