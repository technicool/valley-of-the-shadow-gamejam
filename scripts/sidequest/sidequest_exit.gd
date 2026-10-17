@tool
class_name SidequestExit
extends Area2D
## Exit trigger placed on a sidequest TileMapLayer. Default behavior returns to the
## main 3D level; set target to SIDEQUEST to link to another named sidequest map.

enum Target { RETURN_TO_MAIN, SIDEQUEST }

@export var id: String = "exit_return"
@export var target: Target = Target.RETURN_TO_MAIN
@export var target_sidequest_name: String = ""  ## Used only when target == SIDEQUEST. Matches SidequestManager.SIDEQUEST_SCENES keys.
@export var target_entrance_id: String = "start"  ## Entrance id to spawn at on the target sidequest map.
@export var label: String = "Leave"
@export var color: Color = Color(0.3, 0.8, 1.0)

const RADIUS := 16.0

var _triggered := false


func _enter_tree() -> void:
	add_to_group("sidequest_exit")
	collision_layer = 0
	collision_mask = 1  # Player body layer.


func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	body_entered.connect(_on_body_entered)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, color)


func _on_body_entered(body: Node2D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	# Area2D signals fire mid-physics-step; defer the scene change.
	_trigger.call_deferred()


func _trigger() -> void:
	if target == Target.SIDEQUEST and not target_sidequest_name.is_empty():
		SidequestManager.exit_to_sidequest(target_sidequest_name, target_entrance_id)
	else:
		SidequestManager.exit_to_main()
