extends Node3D
## Level controller coordinating LevelMapPopulator, player positioning,
## and seamless transition between levels with multiple entrance and exit points.

@export var level_populator: LevelMapPopulator
@export var current_entrance_id: String = "start"

@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	if not level_populator:
		level_populator = get_node_or_null("LevelMapPopulator") as LevelMapPopulator

	if level_populator:
		level_populator.level_exit_triggered.connect(_on_level_exit_triggered)
		var pending := SidequestManager.consume_pending_entrance_id()
		spawn_player(pending if not pending.is_empty() else current_entrance_id)


func spawn_player(entrance_id: String) -> void:
	if level_populator and player:
		player.global_position = level_populator.get_entrance_world_pos(entrance_id)
		player.velocity = Vector3.ZERO


func _on_level_exit_triggered(exit_id: String, target_level_path: String, target_entrance_id: String) -> void:
	# Exits fire inside the physics step, where rebuilding the level is not safe.
	_change_level.call_deferred(exit_id, target_level_path, target_entrance_id)


func _change_level(exit_id: String, target_level_path: String, target_entrance_id: String) -> void:
	print("Reached exit: ", exit_id, " -> Target: ", target_level_path, " [Entrance: ", target_entrance_id, "]")

	if SidequestManager.is_sidequest_target(target_level_path):
		# target_entrance_id here names the entrance to use on this main level on return.
		SidequestManager.enter_sidequest(target_level_path, target_entrance_id)
		return

	if target_level_path != "" and ResourceLoader.exists(target_level_path):
		var res: Resource = load(target_level_path)
		if res is LevelData:
			level_populator.level_data = res as LevelData
			level_populator.rebuild_all()
			spawn_player(target_entrance_id)
			return
		elif res is PackedScene:
			get_tree().change_scene_to_packed(res as PackedScene)
			return

	# No valid target: return the player to the target entrance on this level.
	spawn_player(target_entrance_id)

