extends Node
## Persistent game shell. Holds the HUD and the main level for the whole session.
##
## Sidequests are swapped into World on top of the main level. The main level is only
## detached (never freed) while a sidequest is active, so its state survives the trip.

const MAIN_LEVEL_SCENE := preload("res://scenes/main.tscn")

@onready var _world: Node3D = $World

var _main_level
var _sidequest: Node


func _ready() -> void:
	add_to_group("game")
	_main_level = MAIN_LEVEL_SCENE.instantiate()
	_world.add_child(_main_level)
	SidequestManager.sidequest_requested.connect(_on_sidequest_requested, CONNECT_DEFERRED)
	SidequestManager.main_requested.connect(_on_main_requested, CONNECT_DEFERRED)


func _on_sidequest_requested(scene_path: String) -> void:
	if _sidequest:
		_remove_sidequest()
	elif _main_level.get_parent() == _world:
		_world.remove_child(_main_level)
	_sidequest = (load(scene_path) as PackedScene).instantiate()
	_world.add_child(_sidequest)


func _on_main_requested(entrance_id: String) -> void:
	if _sidequest:
		_remove_sidequest()
	if _main_level.get_parent() != _world:
		_world.add_child(_main_level)
	_main_level.spawn_player(entrance_id)


func _remove_sidequest() -> void:
	_world.remove_child(_sidequest)
	_sidequest.queue_free()
	_sidequest = null
