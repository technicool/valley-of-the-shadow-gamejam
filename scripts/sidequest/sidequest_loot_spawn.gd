@tool
class_name SidequestLootSpawn
extends Marker2D
## Placeholder marker: a `loot_type` pickup spawns here when the sidequest loads.

@export var loot_type: String = "coin_pouch"
@export var quantity: int = 1

const RADIUS := 8.0
const COLOR := Color(0.3, 0.6, 1.0)


func _enter_tree() -> void:
	add_to_group("sidequest_loot_spawn")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)


func _ready() -> void:
	queue_redraw()
