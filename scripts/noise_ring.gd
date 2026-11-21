extends Node2D
## A ring that spreads from where the PI made noise (ON AIR rule) and fades:
## the player SEES how far guards could hear that dash.

var radius := 100.0
var _t := 0.0
const LIFE := 0.5
const COLOR := Color(0.91, 0.32, 0.27)


func _process(delta: float) -> void:
	_t += delta
	if _t >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := _t / LIFE
	var col := COLOR
	col.a = 0.7 * (1.0 - k)
	draw_arc(Vector2.ZERO, radius * (0.25 + 0.75 * k), 0.0, TAU, 48, col, 2.0)
