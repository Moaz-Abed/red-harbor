class_name Health
extends Node
## Damageable hit points: a clamped value plus changed / died signals.

signal changed(current: int, max_health: int)
signal died

var max_health := 100
var health := 100


func setup(points: int) -> void:
	max_health = points
	health = points


func damage(amount: int) -> void:
	if health <= 0:
		return
	health = clampi(health - amount, 0, max_health)
	changed.emit(health, max_health)
	if health <= 0:
		died.emit()


func heal(amount: int) -> void:
	if health <= 0:
		return
	health = clampi(health + amount, 0, max_health)
	changed.emit(health, max_health)


func kill() -> void:
	# Capture: no i-frame debate, the night is simply over.
	if health <= 0:
		return
	health = 0
	changed.emit(0, max_health)
	died.emit()


func set_health(points: int) -> void:
	health = clampi(points, 0, max_health)
	changed.emit(health, max_health)


func is_dead() -> bool:
	return health <= 0
