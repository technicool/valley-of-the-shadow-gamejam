@tool
class_name SidequestEnemySpawn
extends Marker2D
## Placeholder marker: an enemy of `enemy_type` spawns here when the sidequest loads.

@export var enemy_type: String = "shade"
@export var patrol_radius: float = 48.0

const RADIUS := 10.0
const COLOR := Color(0.9, 0.15, 0.15)


func _enter_tree() -> void:
	add_to_group("sidequest_enemy_spawn")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)


func _ready() -> void:
	queue_redraw()
