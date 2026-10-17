extends Node
## Autoload that owns the player's health. It lives outside any scene, so health
## survives sidequest travel. The player and the HUD both read from here.

signal health_changed(health: int, max_health: int)

const DEFAULT_MAX_HEALTH := 100

var max_health: int = DEFAULT_MAX_HEALTH
var health: int = DEFAULT_MAX_HEALTH


func take_damage(amount: int) -> void:
	_set_health(health - amount)


func heal(amount: int) -> void:
	_set_health(health + amount)


func _set_health(value: int) -> void:
	var clamped := clampi(value, 0, max_health)
	if clamped == health:
		return
	health = clamped
	health_changed.emit(health, max_health)
