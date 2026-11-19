extends Node2D
## Red Harbor - Harbor Row: the first real level, built from ASCII.
##
## The whole block is authored right here as a character map, so level edits
## are readable git diffs instead of binary scene churn:
##   '#'  wall (building mass / border)   - full 16x16 collision, world layer
##   '.'  wet asphalt                     ','
##   'o'  drain grate                     '~'  sodium light pool (safehouse)
## Everything is painted at runtime onto a TileMapLayer; the wall tiles carry
## TileSet physics on collision layer 2 ("world"), which is the same layer the
## player collides with, the guards' sight raycast respects, and the vision
## cone fan stops at. One map, three systems.
##
## Map is 40 x 22 tiles of 16 px = 640 x 352, nudged down 4 px to center in
## the 360 px viewport.

const TILE := 16
const ATLAS := preload("res://assets/tiles/harbor_tiles.png")

# atlas columns in harbor_tiles.png
const T_FLOOR_A := 0
const T_FLOOR_B := 1
const T_DRAIN := 2
const T_WALL := 3
const T_WALL_TOP := 4
const T_NEON := 5

const MAP := [
		"########################################",
		"#......................................#",
		"#........o................o.........~~~#",
		"#..,................................~~~#",
		"#......##########..............#####...#",
		"#......##########.##...........#####...#",
		"#......##########.##...........#####...#",
		"#......##########..............#####...#",
		"#.....,##########...........,..........#",
		"#......##########......................#",
		"#......##########................o.....#",
		"#...###................................#",
		"#...###................................#",
		"#...###..............##########........#",
		"#...###..............##########........#",
		"#...........o......,.##########........#",
		"#.o..................##########........#",
		"#....................##########........#",
		"#....................##########..,.....#",
		"#.............,........................#",
		"#.......................o..............#",
		"########################################",
]


func _ready() -> void:
		var ts := TileSet.new()
		ts.tile_size = Vector2i(TILE, TILE)
		ts.add_physics_layer()
		ts.set_physics_layer_collision_layer(0, 2)   # "world" - blocks movement + sight
		ts.set_physics_layer_collision_mask(0, 0)

		var src := TileSetAtlasSource.new()
		src.texture = ATLAS
		src.texture_region_size = Vector2i(TILE, TILE)
		for t in 6:
				src.create_tile(Vector2i(t, 0))

		# Walls block everything: one full-square collision polygon per wall tile.
		for t in [T_WALL, T_WALL_TOP]:
				var td := src.get_tile_data(Vector2i(t, 0), 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([
						Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
				]))
		ts.add_source(src, 0)

		var layer := TileMapLayer.new()
		layer.tile_set = ts
		layer.position = Vector2(0, 4)   # center the 352 px map in the 360 px view
		add_child(layer)

		for y in MAP.size():
				var row: String = MAP[y]
				for x in row.length():
						var t := _tile_for(x, y)
						if t >= 0:
								layer.set_cell(Vector2i(x, y), 0, Vector2i(t, 0))


func _tile_for(x: int, y: int) -> int:
		var row: String = MAP[y]
		match row[x]:
				"#":
						# Cells whose top edge is exposed get the bone
						# roof-cap tile. MAP is an untyped Array, so
						# MAP[y - 1] is a Variant: it must go through an
						# explicitly typed String before indexing, or the
						# parser cannot infer the type of the comparison.
						var covered := false
						if y > 0:
								var above: String = MAP[y - 1]
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
