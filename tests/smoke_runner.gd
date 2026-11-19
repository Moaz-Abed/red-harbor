extends Node
## Red Harbor - headless smoke test: the regression net for the P3 bug class,
## updated for the P3.2 procedural block (every boot deals a random map).
##
## Run it with:
##   godot --headless --path . res://tests/smoke.tscn
## (or press F6 on tests/smoke.tscn inside the editor).
##
## It boots the real main scene (which deals a FRESH random Harbor Row),
## pushes real input through the Input singleton, then asserts the contracts
## the shipped builds broke - all generation-agnostic:
##   1. WALLS STOP THE BODY - tile collision polygons must be registered on
##      a TileSet the atlas source is bound to (level_builder.gd ordering).
##   2. SIGHT RAYS STOP AT WALLS - a ray due west from the spawn must end on
##      a grid-aligned wall face, wherever the buildings landed.
##   3. THE DEAL IS PLAYABLE - BFS over the live tilemap: the exit and all
##      three intel caches are reachable, no floor is stranded, and every
##      patrol waypoint sits on open ground.
##   4. WHAT IS LIT IS VISIBLE - the z contract (floor 0 < cone 1 < actors 2)
##      and cone alphas keep the flashlight readable on screen.
##   5. HUD TEXT IS LEGIBLE - ink outline behind a bright fill, and the
##      takedown action the scripts reference actually exists.
##   6. THE HUD STAYS OUT OF THE WAY - no HUD art widget exceeds 48 px on
##      a side, so the portrait block can never grow back into an 80 x 80
##      wall over the top-left of the play view (P3.3 compact pass).
##
## Guards are frozen during the walk phase so a patrol can never interfere
## with the wall test (they thaw for the cone checks). The walk runs 260
## frames (~650 px) so the player always ends ON a border wall face.
##
## Exits 0 with "SMOKE: ALL PASS", exits 1 with a FAIL list otherwise.

const WORLD_MASK := 2          # "world" physics layer (see project.godot)
const TILE := 16
const MAP_OFFSET_Y := 4.0      # level_builder centers the 352 px map
const MAP_W := 40
const MAP_H := 22

var _main: Node2D
var _player: CharacterBody2D
var _tile_layer: TileMapLayer
var _ray: RayCast2D
var _frames := 0
var _phase := 0
var _fails: PackedStringArray = []
var _walk_dir := -1.0       # -1 = push west, +1 = push east (nearest border)
var _walk_from_x := 0.0     # spawn x, recorded when the walk starts


func _ready() -> void:
        var packed: PackedScene = load("res://scenes/main.tscn")
        _main = packed.instantiate()
        add_child(_main)
        _player = get_tree().get_first_node_in_group("player")
        if _player == null:
                _fail("player found in group")
        var row := _main.get_node_or_null("HarborRow")
        if row:
                for child in row.get_children():
                        if child is TileMapLayer:
                                _tile_layer = child
        if _tile_layer == null:
                _fail("TileMapLayer found under HarborRow")
        _ray = RayCast2D.new()
        _ray.collision_mask = WORLD_MASK
        _ray.enabled = false
        add_child(_ray)


func _physics_process(_delta: float) -> void:
        _frames += 1
        if _frames > 600:          # hard timeout - never hang CI
                _finish()
                return
        if _player == null or _tile_layer == null:
                return
        if _phase == 0:
                if _frames == 2:
                        # Push toward the NEAREST border wall: the spawn is
                        # random (col 4..35), so a fixed 100-frame walk west
                        # cannot always reach the wall first.
                        _walk_dir = -1.0 if _player.global_position.x >= 320.0 else 1.0
                        _walk_from_x = _player.global_position.x
                        Input.action_press("move_left" if _walk_dir < 0.0 else "move_right")
                elif _frames == 4:
                        # Freeze AFTER the guards completed a full tick. Their
                        # first tick only grabs the player reference; the cone
                        # fan builds on the second. Frozen patrols cannot
                        # interfere with the wall walk. Pickups are muted too:
                        # the walk sweeps the whole bottom street and must not
                        # collect a cache parked beside it.
                        for g in get_tree().get_nodes_in_group("guards"):
                                g.set_physics_process(false)
                        for it in get_tree().get_nodes_in_group("intel_pickups"):
                                it.monitoring = false
                elif _frames == 262:
                        # 260 frames of walking (~650 px at walk speed) - the
                        # spawn can sit up to 546 px from its nearest border
                        # face, so the walk ALWAYS ends in real wall contact.
                        # (The old 120-frame walk covered ~300 px and the
                        # border assertion passed vacuously on nearly every
                        # deal - it could no longer catch a phase-through.)
                        Input.action_release("move_left")
                        Input.action_release("move_right")
                        for g in get_tree().get_nodes_in_group("guards"):
                                g.set_physics_process(true)
                        for it in get_tree().get_nodes_in_group("intel_pickups"):
                                it.monitoring = true
                        _check_wall_collision()
                        _check_tile_physics()
                        _check_sight_ray()
                        _check_deal()
                        _check_layering()
                        _check_hud()
                        _check_inputs()
                        _finish()


# --- checks -------------------------------------------------------------------

func _check(cond: bool, what: String) -> void:
        if cond:
                print("SMOKE PASS: " + what)
        else:
                _fail(what)


func _peak(c: Color) -> float:
        # Brightness of the brightest channel - honest for red text, where
        # perceptual luminance would read a clear alarm red as "dark".
        return maxf(c.r, maxf(c.g, c.b))


func _fail(what: String) -> void:
        _fails.append(what)
        print("SMOKE FAIL: " + what)


func _cell_of(p: Vector2) -> Vector2i:
        return Vector2i(int(floor(p.x / TILE)), int(floor((p.y - MAP_OFFSET_Y) / TILE)))


func _is_wall_cell(cell: Vector2i) -> bool:
        # Atlas slots (3,0) and (4,0) are the wall bricks (T_WALL / T_WALL_TOP).
        var c := _tile_layer.get_cell_atlas_coords(cell)
        return c == Vector2i(3, 0) or c == Vector2i(4, 0)


func _bfs_reachable(from: Vector2i) -> Dictionary:
        var seen := {from: true}
        var queue: Array[Vector2i] = [from]
        while not queue.is_empty():
                var cur: Vector2i = queue.pop_back()
                for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
                        var nxt: Vector2i = cur + d
                        if nxt.x < 0 or nxt.y < 0 or nxt.x >= MAP_W or nxt.y >= MAP_H:
                                continue
                        if seen.has(nxt) or _is_wall_cell(nxt):
                                continue
                        seen[nxt] = true
                        queue.append(nxt)
        return seen


func _check_wall_collision() -> void:
        # Pushed for 260 physics frames along the bottom ring street toward
        # the nearest border. The ring street is guaranteed open, so a body
        # that respects walls parks ON the border's inner face (x = 22 west,
        # x = 618 east, body half-width 6). A body that phases through sails
        # past the face. The movement check demands the body actually moved,
        # so a dead input simulation can never fake a pass.
        var x := _player.global_position.x
        var moved := absf(x - _walk_from_x)
        _check(moved > 100.0, "player actually walked (dx=%.1f)" % moved)
        if _walk_dir < 0.0:
                # REAL contact: resting on the west face at x ~ 22 (face 16
                # + half-width 6). Vacuous ranges (mid-map x) are failures
                # now - the walk is long enough to always reach the wall.
                _check(x <= 24.0, "west border stops the player (x=%.1f, need <= 24)" % x)
        else:
                _check(x >= 616.0, "east border stops the player (x=%.1f, need >= 616)" % x)


func _check_tile_physics() -> void:
        var ts := _tile_layer.tile_set
        if ts == null:
                _fail("TileSet assigned to TileMapLayer")
                return
        var src := ts.get_source(0) as TileSetAtlasSource
        if src == null:
                _fail("atlas source 0 found on TileSet")
                return
        # Source-level get_tile_data speaks ATLAS coordinates, not map cells:
        # slot (3,0) of harbor_tiles.png is the wall brick (level_builder T_WALL).
        var td := src.get_tile_data(Vector2i(3, 0), 0)
        _check(td != null, "wall tile (atlas 3,0) exposes TileData")
        if td != null:
                var n: int = td.get_collision_polygons_count(0)
                _check(n >= 1, "wall TileData carries a collision polygon (got %d)" % n)


func _check_sight_ray() -> void:
        # Due west from the spawn across open ring street: the same ray class
        # every guard cone uses must stop at SOME wall face, and every wall
        # face in this game is grid-aligned (x is a multiple of 16).
        _ray.global_position = _player.global_position
        _ray.target_position = Vector2(-700, 0)
        _ray.force_raycast_update()
        _check(_ray.is_colliding(), "sight ray hits the world layer")
        if _ray.is_colliding():
                var hit_x := _ray.get_collision_point().x
                var m := fmod(hit_x, float(TILE))
                _check(m < 1.5 or m > TILE - 1.5,
                        "sight ray stops on a grid-aligned wall face (x=%.1f)" % hit_x)


func _check_deal() -> void:
        # The night must be beatable wherever the deal put things.
        var guards := get_tree().get_nodes_in_group("guards")
        _check(guards.size() >= 3, "three guards found (got %d)" % guards.size())
        var intel := get_tree().get_nodes_in_group("intel_pickups")
        _check(intel.size() == 3, "three intel caches found (got %d)" % intel.size())
        var zones := get_tree().get_nodes_in_group("exit_zone")
        _check(zones.size() == 1, "safehouse door found (got %d)" % zones.size())
        var reach := _bfs_reachable(_cell_of(_player.global_position))
        # No stranded floor: every walkable cell drains into the spawn's region.
        var floor_count := 0
        for y in MAP_H:
                for x in MAP_W:
                        if not _is_wall_cell(Vector2i(x, y)):
                                floor_count += 1
        _check(reach.size() == floor_count,
                "no pocket floor (reachable %d of %d walkable)" % [reach.size(), floor_count])
        for it in intel:
                _check(reach.has(_cell_of(it.global_position)),
                        "intel cache reachable at %s" % _cell_of(it.global_position))
        if zones.size() == 1:
                _check(reach.has(_cell_of(zones[0].global_position)),
                        "safehouse door reachable at %s" % _cell_of(zones[0].global_position))
        # Every patrol waypoint sits on open ground.
        for g in guards:
                var pts: PackedVector2Array = g.patrol_points
                _check(pts.size() >= 2, "guard has a patrol route (%d waypoints)" % pts.size())
                for wp in pts:
                        var cell := _cell_of(wp)
                        _check(not _is_wall_cell(cell),
                                "patrol waypoint %s on open floor" % cell)


func _check_layering() -> void:
        # z contract: floor tiles 0 < cone 1 < actor sprites 2. The old
        # cone z_index = -1 tucked the whole flashlight UNDER the tilemap.
        var guards := get_tree().get_nodes_in_group("guards")
        for g in guards:
                var cone: Polygon2D = null
                var sprite: AnimatedSprite2D = null
                for c in g.get_children():
                        if c is Polygon2D:
                                cone = c
                        elif c is AnimatedSprite2D:
                                sprite = c
                _check(cone != null, "guard has a cone Polygon2D")
                if cone != null:
                        _check(cone.z_index >= 1, "cone paints above the floor (z=%d)" % cone.z_index)
                        _check(cone.polygon.size() >= 20, "cone fan built (%d pts)" % cone.polygon.size())
                        _check(cone.color.a >= 0.25, "cone alpha readable (a=%.2f)" % cone.color.a)
                if sprite != null:
                        _check(sprite.z_index >= 2, "guard sprite above its cone (z=%d)" % sprite.z_index)
        if _player != null:
                for c in _player.get_children():
                        if c is AnimatedSprite2D:
                                _check(c.z_index >= 2, "player sprite above cones (z=%d)" % c.z_index)


func _check_hud() -> void:
        var hud := _main.get_node_or_null("HudLayer")
        if hud == null or hud.get_child_count() == 0:
                _fail("HudLayer with a root Control found")
                return
        var labels: Array[Label] = []
        _collect_labels(hud.get_child(0), labels)
        _check(labels.size() >= 4, "HUD labels found (got %d)" % labels.size())
        var hint: Label = null
        for l in labels:
                # Legibility contract: ink outline behind a bright fill.
                var outline := l.get_theme_constant("outline_size")
                _check(outline >= 2, "'%s...' has an ink outline (size=%d)" % [l.text.left(10), outline])
                var oc: Color = l.get_theme_color("font_outline_color")
                _check(_peak(oc) <= 0.25, "'%s...' outline is dark (peak=%.2f)" % [l.text.left(10), _peak(oc)])
                var fill: Color = l.get_theme_color("font_color") * l.modulate
                if l.position.y > 300.0:   # the bottom controls line
                        hint = l
                        _check(_peak(fill) >= 0.75,
                                "controls line is bright (peak=%.2f, was fog-gray)" % _peak(fill))
        if hint == null:
                _fail("bottom controls line found")
        # Compact-HUD contract (P3.3): the portrait block once painted at a
        # flat 2x - an 80 x 80 frame wall plus labels down to y ~110, a fifth
        # of the view dead. Frame (40), face (32) and pips (14) now all stay
        # under 48 px on a side.
        var rects: Array[TextureRect] = []
        _collect_rects(hud.get_child(0), rects)
        _check(rects.size() >= 5, "HUD art widgets found (got %d)" % rects.size())
        var biggest := 0.0
        for r in rects:
                if r.texture != null:
                        var s: Vector2 = r.texture.get_size() * r.scale
                        biggest = maxf(biggest, maxf(s.x, s.y))
        _check(biggest <= 48.0,
                "HUD art stays compact (largest widget %.0f px, need <= 48)" % biggest)


func _check_inputs() -> void:
        # The scripts reference "takedown" (F); a missing action would spam
        # errors every physics frame.
        _check(InputMap.has_action("takedown"), "input action 'takedown' exists")
        _check(InputMap.has_action("move_left"), "input action 'move_left' exists")


func _collect_labels(node: Node, out: Array[Label]) -> void:
        for c in node.get_children():
                if c is Label:
                        out.append(c)
                else:
                        _collect_labels(c, out)


func _collect_rects(node: Node, out: Array[TextureRect]) -> void:
        for c in node.get_children():
                if c is TextureRect:
                        out.append(c)
                else:
                        _collect_rects(c, out)


func _finish() -> void:
        if _fails.is_empty():
                print("SMOKE: ALL PASS")
                get_tree().quit(0)
        else:
                print("SMOKE: %d FAILURE(S)" % _fails.size())
                get_tree().quit(1)
