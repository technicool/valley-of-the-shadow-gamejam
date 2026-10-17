class_name SidequestPickup
extends Area2D
## Generic collectible spawned from a SidequestWeaponSpawn or SidequestLootSpawn marker.

signal collected(pickup_type: String)

var pickup_type: String = ""
var respawn: bool = false

const PLAYER_LAYER := 1
var _home_position: Vector2
var _collected := false


func _ready() -> void:
	add_to_group("sidequest_pickup")
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	_home_position = global_position
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	collected.emit(pickup_type)
	if respawn:
		visible = false
		monitoring = false
		await get_tree().create_timer(5.0).timeout
		global_position = _home_position
		visible = true
		monitoring = true
		_collected = false
	else:
		queue_free()
