@tool
class_name SidequestWeaponSpawn
extends Marker2D
## Placeholder marker: a `weapon_type` pickup spawns here when the sidequest loads.

@export var weapon_type: String = "dagger"
@export var respawn: bool = false

const RADIUS := 8.0
const COLOR := Color(1.0, 0.85, 0.3)


func _enter_tree() -> void:
	add_to_group("sidequest_weapon_spawn")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)


func _ready() -> void:
	queue_redraw()
