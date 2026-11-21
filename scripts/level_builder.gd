extends Node2D
## Harbor Row, dealt fresh every night (street probe). Fixed 40x22 frame,
## one screen; the city inside is re-dealt every boot: border wall, a 2-tile
## open ring just inside it, random buildings kept apart (all floor provably
## connected - a BFS runs anyway and seals stray pockets), then the door,
## the PI, three intel caches and three patrol lines sampled from reachable
## open cells. World = cell * 16 + 8 + the map's (0, 4) offset.
##
## The wall tiles carry TileSet physics on collision layer 2 ("world"), the
## same layer the player collides with, the guards' sight raycast respects,
## and the vision cone fan stops at. One map, three systems - random map,
## same three systems.

const TILE := 16
const W := 40
const H := 22
const ATLAS := preload("res://assets/tiles/harbor_tiles.png")

# atlas columns in harbor_tiles.png
const T_FLOOR_A := 0
const T_FLOOR_B := 1
const T_DRAIN := 2
const T_WALL := 3
const T_WALL_TOP := 4
const T_NEON := 5

# Building rects live inside this window; everything between the window
# and the border stays open street (a guaranteed 2-tile perimeter ring).
const BUILD_X_MIN := 3
const BUILD_X_MAX := 36
const BUILD_Y_MIN := 3
const BUILD_Y_MAX := 18

const BUILD_AREA_TARGET := 170   # interior tiles of building mass per night
const BUILD_ATTEMPTS := 60
const DRAIN_COUNT := 8
const PUDDLE_COUNT := 12

var _rng := RandomNumberGenerator.new()
var _map: Array[String] = []
var _walls := {}    # Vector2i -> true: building / border mass
var _open := {}     # Vector2i -> true: walkable + reachable (BFS result)
var _neon := {}     # dressing: sodium pool cells near the safehouse door
var _drain := {}
var _puddle := {}


func generate(rng_seed: int = -1) -> Dictionary:
                # rng_seed >= 0 pins the deal (debug/QA); -1 = fresh random night.
                if rng_seed >= 0:
                                _rng.seed = rng_seed
                else:
                                _rng.randomize()
                var plan := _deal_level()
                _paint_tiles()
                return plan


# --- the deal -----------------------------------------------------------------

func _deal_level() -> Dictionary:
                _walls.clear()
                _neon.clear()
                _drain.clear()
                _puddle.clear()

                # 1. border mass
                for y in H:
                                for x in W:
                                                if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                                                                _walls[Vector2i(x, y)] = true

                # 2. buildings (gap-kept rects -> floor stays connected)
                _place_buildings()

                # 3. flood from the guaranteed ring corner; seal any pocket (defensive:
                #    the gap rule already makes pockets impossible, but this can never
                #    strand a cache even if the placement rules change later)
                _flood_open()
                for y in H:
                                for x in W:
                                                var cell := Vector2i(x, y)
                                                if not _walls.has(cell) and not _open.has(cell):
                                                                _walls[cell] = true

                # 4. the two fixed anchors: bottom street start, top street door
                var player_cell := Vector2i(_rng.randi_range(4, 35), 20)
                var exit_cell := _deal_exit(player_cell)
                for dx in [-1, 0, 1]:
                                _neon[Vector2i(exit_cell.x + dx, 2)] = true

                # 5. dressing (never on the door or its pool)
                _dress(exit_cell)

                # 6. patrol lines first
                var guard_routes: Array = []
                var used_waypoints: Array = []
                for i in 3:
                                var route: Array = _deal_guard_route(player_cell, exit_cell, used_waypoints)
                                guard_routes.append(route)
                                used_waypoints.append(route[0])
                                used_waypoints.append(route[1])

                # 7. intel caches, spread across the block
                var intel_cells: Array = _deal_intel(player_cell, exit_cell)

                _build_map_strings()

                # Tripwires: the plan must sit on reachable floor or the night is
                # unplayable by construction. These fire loud in debug builds; the
                # shipped smoke test re-verifies the same facts on the live map.
                assert(_open.has(player_cell))
                assert(_open.has(exit_cell))
                for c in intel_cells:
                                assert(_open.has(c))
                for route in guard_routes:
                                for wp in route:
                                                assert(_open.has(wp))

                return {
                                "player": player_cell,
                                "exit": exit_cell,
                                "intel": intel_cells,
                                "guards": guard_routes,
                }


func _place_buildings() -> void:
                var rects: Array[Rect2i] = []
                var area := 0
                for attempt in BUILD_ATTEMPTS:
                                if area >= BUILD_AREA_TARGET:
                                                break
                                var size := _pick_building_size()
                                var x := _rng.randi_range(BUILD_X_MIN, BUILD_X_MAX - size.x + 1)
                                var y := _rng.randi_range(BUILD_Y_MIN, BUILD_Y_MAX - size.y + 1)
                                var rect := Rect2i(x, y, size.x, size.y)
                                var grown := rect.grow(1)   # keeps a >= 1 tile street all around
                                var clash := false
                                for other in rects:
                                                if grown.intersects(other):
                                                                clash = true
                                                                break
                                if clash:
                                                continue
                                rects.append(rect)
                                area += rect.get_area()
                for r in rects:
                                for cy in range(r.position.y, r.end.y):
                                                for cx in range(r.position.x, r.end.x):
                                                                _walls[Vector2i(cx, cy)] = true


func _pick_building_size() -> Vector2i:
                var roll := _rng.randf()
                if roll < 0.4:
                                return Vector2i(_rng.randi_range(8, 11), _rng.randi_range(4, 6))    # city block
                if roll < 0.8:
                                return Vector2i(_rng.randi_range(4, 7), _rng.randi_range(3, 5))    # warehouse
                return Vector2i(_rng.randi_range(2, 4), _rng.randi_range(2, 3))            # planter / kiosk


func _flood_open() -> void:
                _open.clear()
                var queue: Array[Vector2i] = [Vector2i(1, 1)]
                _open[Vector2i(1, 1)] = true
                while not queue.is_empty():
                                var cur: Vector2i = queue.pop_back()
                                for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
                                                var nxt: Vector2i = cur + d
                                                if nxt.x < 1 or nxt.y < 1 or nxt.x > W - 2 or nxt.y > H - 2:
                                                                continue
                                                if _open.has(nxt) or _walls.has(nxt):
                                                                continue
                                                _open[nxt] = true
                                                queue.append(nxt)


func _deal_exit(player_cell: Vector2i) -> Vector2i:
                # Top street, at the far end of the block from the PI's start.
                var col := player_cell.x
                var tries := 0
                while tries < 40 and absi(col - player_cell.x) < 10:
                                col = _rng.randi_range(3, 36)
                                tries += 1
                if absi(col - player_cell.x) < 10:
                                col = 3 if player_cell.x >= 20 else 36
                return Vector2i(col, 1)


func _dress(exit_cell: Vector2i) -> void:
                var reserved := {exit_cell: true}
                for dx in [-1, 0, 1]:
                                reserved[Vector2i(exit_cell.x + dx, 2)] = true
                var cells: Array = _open.keys()
                var n := 0
                while n < DRAIN_COUNT:
                                var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
                                if reserved.has(c) or _drain.has(c) or _puddle.has(c):
                                                continue
                                _drain[c] = true
                                n += 1
                n = 0
                while n < PUDDLE_COUNT:
                                var p: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
                                if reserved.has(p) or _drain.has(p) or _puddle.has(p):
                                                continue
                                _puddle[p] = true
                                n += 1


func _deal_guard_route(player_cell: Vector2i, exit_cell: Vector2i, other_waypoints: Array) -> Array:
                # A straight two-waypoint patrol whose whole segment sits on open
                # floor. Rules: calm night start (>= 10 tiles from the PI), the door
                # is not babysat (>= 5 tiles from it), and guards keep >= 6 tiles
                # between each other's waypoints so they don't clump.
                for attempt in 300:
                                var a: Vector2i
                                var b: Vector2i
                                if _rng.randf() < 0.5:
                                                var row := _rng.randi_range(BUILD_Y_MIN, BUILD_Y_MAX)
                                                var length := _rng.randi_range(6, 13)
                                                var ca := _rng.randi_range(BUILD_X_MIN, BUILD_X_MAX - length)
                                                a = Vector2i(ca, row)
                                                b = Vector2i(mini(ca + length, BUILD_X_MAX), row)
                                else:
                                                var col := _rng.randi_range(BUILD_X_MIN, BUILD_X_MAX)
                                                var length := _rng.randi_range(6, 13)
                                                var ra := _rng.randi_range(BUILD_Y_MIN, BUILD_Y_MAX - length)
                                                a = Vector2i(col, ra)
                                                b = Vector2i(col, mini(ra + length, BUILD_Y_MAX))
                                if not _segment_open(a, b):
                                                continue
                                if _manhattan(a, player_cell) < 10 or _manhattan(b, player_cell) < 10:
                                                continue
                                if _manhattan(a, exit_cell) < 5 or _manhattan(b, exit_cell) < 5:
                                                continue
                                var too_close := false
                                for w in other_waypoints:
                                                if _manhattan(a, w) < 6 or _manhattan(b, w) < 6:
                                                                too_close = true
                                                                break
                                if too_close:
                                                continue
                                return [a, b]
                # Guaranteed fallback (the sampled rules are ~always satisfiable, this
                # is belt-and-suspenders): the perimeter street is ALWAYS open. Walk a
                # stretch of the top/bottom street on the far side of the door/start,
                # or one of the two ring columns.
                var side := _rng.randi_range(0, 3)
                if side == 0:
                                var far_x := 6 if exit_cell.x >= 20 else 33
                                return [Vector2i(far_x - 5, 1), Vector2i(far_x, 1)]
                if side == 1:
                                var far_x2 := 6 if player_cell.x >= 20 else 33
                                return [Vector2i(far_x2 - 5, 20), Vector2i(far_x2, 20)]
                if side == 2:
                                return [Vector2i(1, 5), Vector2i(1, 16)]
                return [Vector2i(W - 2, 5), Vector2i(W - 2, 16)]


func _deal_intel(player_cell: Vector2i, exit_cell: Vector2i) -> Array:
                # Three caches, >= 9 tiles apart, out of spawn's pocket and the
                # door's pocket. Sitting near (or on) a patrol line is FINE - that
                # is the risk the game is made of.
                var picked: Array = []
                for attempt in 600:
                                if picked.size() == 3:
                                                break
                                var cells: Array = _open.keys()
                                var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
                                if _manhattan(c, player_cell) < 7 or _manhattan(c, exit_cell) < 6:
                                                continue
                                var spread := true
                                for p in picked:
                                                if _manhattan(c, p) < 9:
                                                                spread = false
                                                                break
                                if not spread:
                                                continue
                                picked.append(c)
                if picked.size() == 3:
                                return picked
                # Fallback: nearest open cell to five spread anchors.
                var anchors := [Vector2i(6, 3), Vector2i(33, 3), Vector2i(19, 10), Vector2i(6, 18), Vector2i(33, 18)]
                for a in anchors:
                                if picked.size() == 3:
                                                break
                                if _manhattan(a, player_cell) < 8 or _manhattan(a, exit_cell) < 6:
                                                continue
                                var best := Vector2i(-1, -1)
                                var best_d := 999999
                                for c in _open.keys():
                                                var cc: Vector2i = c
                                                if picked.has(cc):
                                                                continue
                                                var d := _manhattan(cc, a)
                                                if d < best_d:
                                                                best_d = d
                                                                best = cc
                                if best_d < 999999:
                                                picked.append(best)
                return picked


func _segment_open(a: Vector2i, b: Vector2i) -> bool:
                if a.x != b.x and a.y != b.y:
                                return false
                var cur := a
                var step := (b - a).sign()
                var steps := absi(b.x - a.x) + absi(b.y - a.y)
                # Bounded walk over every cell of the segment (inclusive): a patrol
                # line is clear only if not one cell of it is wall.
                for i in steps + 1:
                                if not _open.has(cur):
                                                return false
                                if i < steps:
                                                cur += step
                return true


func _manhattan(a: Vector2i, b: Vector2i) -> int:
                return absi(a.x - b.x) + absi(a.y - b.y)


func _build_map_strings() -> void:
                _map.clear()
                for y in H:
                                var row := ""
                                for x in W:
                                                var cell := Vector2i(x, y)
                                                if _walls.has(cell):
                                                                row += "#"
                                                elif _neon.has(cell):
                                                                row += "~"
                                                elif _drain.has(cell):
                                                                row += "o"
                                                elif _puddle.has(cell):
                                                                row += ","
                                                else:
                                                                row += "."
                                _map.append(row)


# --- painting -----------------------------------------------------------------

func _paint_tiles() -> void:
                var ts := TileSet.new()
                ts.tile_size = Vector2i(TILE, TILE)
                # One physics layer carries every wall: bit 2 ("world"). The player
                # collides with it, the guards' sight raycast respects it, and the
                # vision-cone fan stops at it. One map, three systems.
                ts.add_physics_layer()
                ts.set_physics_layer_collision_layer(0, 2)
                ts.set_physics_layer_collision_mask(0, 0)

                var src := TileSetAtlasSource.new()
                src.texture = ATLAS
                src.texture_region_size = Vector2i(TILE, TILE)
                for t in 6:
                                src.create_tile(Vector2i(t, 0))

                # FIX (phase-through bug): the atlas source MUST be bound to the
                # TileSet via add_source() BEFORE any TileData touches physics.
                # TileData learns its physics layers from the TileSet it belongs to;
                # polygons added while the source is still orphaned are silently
                # dropped, and every wall shipped with zero collision. The old code
                # called add_source() last - walls looked solid and were smoke.
                ts.add_source(src, 0)

                # Walls block everything: one full-square collision polygon per wall
                # tile. Now that the source is bound, the physics layer exists on
                # every TileData and the polygon actually registers.
                for t in [T_WALL, T_WALL_TOP]:
                                var td := src.get_tile_data(Vector2i(t, 0), 0)
                                td.add_collision_polygon(0)
                                td.set_collision_polygon_points(0, 0, PackedVector2Array([
                                                Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
                                ]))
                                # Debug-build tripwire: a wall without collision fails open
                                # silently; make it loud instead. (The smoke test in
                                # tests/ guards this too, on every future build.)
                                assert(td.get_collision_polygons_count(0) == 1)

                var layer := TileMapLayer.new()
                layer.tile_set = ts
                layer.position = Vector2(0, 4)   # center the 352 px map in the 360 px view
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
                                                # Cells whose top edge is exposed get the bone
                                                # roof-cap tile. _map is typed Array[String], but the
                                                # explicit typing stays for the parser's sake.
                                                var covered := false
                                                if y > 0:
                                                                var above: String = _map[y - 1]
                                                                covered = above[x] == "#"
                                                return T_WALL if covered else T_WALL_TOP
                                ".":
                                                return T_FLOOR_A
                                ",":
                                                return T_FLOOR_B
                                "o":
                                                return T_DRAIN
                                "~":
                                                return T_NEON
                return -1
