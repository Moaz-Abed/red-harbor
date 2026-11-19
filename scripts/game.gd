extends Node2D
## Red Harbor - the night orchestrator.
##
## Every boot of this scene deals a fresh Harbor Row: level_builder.gd
## rolls a new block, then this script plants the cast on it - the PI on
## the bottom street, the safehouse door on the top street, three intel
## caches and three guard patrols wherever the deal put them. The node
## positions in main.tscn are only editor previews; the plan is the truth.
##
## R (restart) reloads this scene, so "next night" is literally a new deal.
## The one-line NIGHT summary it prints is QA gold: run the headless smoke
## test a dozen times and diff the lines to prove the deal actually varies.

const TILE := 16
const MAP_OFFSET := Vector2(0, 4)   # level_builder centers the 352 px map

@onready var _world: Node2D = $HarborRow
@onready var _player: CharacterBody2D = $Player
@onready var _exit: Area2D = $ExitZone
@onready var _intel: Array = [$Intel1, $Intel2, $Intel3]
@onready var _guards: Array = [$Guard1, $Guard2, $Guard3]


func _ready() -> void:
        var plan: Dictionary = _world.generate()
        _apply_plan(plan)
        print("NIGHT player=%s exit=%s intel=%s guards=%s" % [
                plan["player"], plan["exit"], plan["intel"], _route_summary(plan),
        ])


func _cell_world(cell: Vector2i) -> Vector2:
        # The ONE world-position rule: cell center, plus the map's
        # (0, 4) centering offset.
        return Vector2(cell.x * TILE + 8, cell.y * TILE + 8) + MAP_OFFSET


func _apply_plan(plan: Dictionary) -> void:
        _player.global_position = _cell_world(plan["player"])
        _exit.global_position = _cell_world(plan["exit"])
        var intel_cells: Array = plan["intel"]
        for i in _intel.size():
                _intel[i].global_position = _cell_world(intel_cells[i])
        var routes: Array = plan["guards"]
        for i in _guards.size():
                var pts := PackedVector2Array()
                for cell in routes[i]:
                        pts.append(_cell_world(cell))
                _guards[i].global_position = pts[0]
                _guards[i].patrol_points = pts


func _route_summary(plan: Dictionary) -> String:
        var out := ""
        for route in plan["guards"]:
                out += "%s-%s|" % [route[0], route[1]]
        return out.trim_suffix("|")
