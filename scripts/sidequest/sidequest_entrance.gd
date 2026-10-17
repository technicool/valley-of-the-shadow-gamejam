@tool
@icon("res://icon.svg")
class_name SidequestEntrance
extends Marker2D
## Marks a spawn point inside a sidequest TileMapLayer scene. Drag in the 2D editor to place.

@export var id: String = "start"

const RADIUS := 10.0
const COLOR := Color(0.3, 1.0, 0.4)


func _enter_tree() -> void:
	add_to_group("sidequest_entrance")


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, COLOR)


func _ready() -> void:
	queue_redraw()
