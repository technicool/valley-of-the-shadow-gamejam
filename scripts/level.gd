extends Node3D
## Level controller coordinating procedural valley section streaming, player positioning,
## seamless transitions between sections, and health loss when retreating into old sections.

@export var level_populator: LevelMapPopulator
@export var current_entrance_id: String = "start"
@export var section_length: int = 50
@export var section_width: int = 80
@export var base_seed: int = 1337
@export var randomize_base_seed: bool = false
@export var spawn_ahead_distance: float = 20.0
@export var old_section_damage: int = 10
@export var old_section_damage_interval: float = 1.0

@onready var player: CharacterBody3D = $Player

## Active LevelMapPopulator nodes keyed by integer section index (0, 1, 2, ...).
var active_sections: Dictionary = {}
var furthest_section_reached: int = 0
var _generator: LevelMapGenerator = LevelMapGenerator.new()
var _backtrack_damage_timer: float = 0.0
var _retreat_floor: StaticBody3D


func _ready() -> void:
	if randomize_base_seed:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		base_seed = int(rng.randi() % 100000)

	if not level_populator:
		level_populator = get_node_or_null("LevelMapPopulator") as LevelMapPopulator

	_setup_retreat_floor()
	_initialize_first_section()
	# Pre-spawn section 1 if spawn_ahead_distance already reaches it, or keep ready
	_update_streaming(0.0)

	var pending := SidequestManager.consume_pending_entrance_id()
	spawn_player(pending if not pending.is_empty() else current_entrance_id)


func _initialize_first_section() -> void:
	var depth := maxi(20, section_length)
	var width := maxi(40, section_width)
	var seed_0 := _seed_for_section(0)
	var data_0 := _generator.generate(LevelMapGenerator.GenerationMode.LINEAR_PATH, seed_0, width, depth, 0)

	if level_populator:
		level_populator.section_index = 0
		level_populator.section_length = depth
		level_populator.world_seed = seed_0
		level_populator.position = Vector3(0.0, 0.0, 0.0)
		level_populator.level_data = data_0
		level_populator.rebuild_all()
		if not level_populator.level_exit_triggered.is_connected(_on_level_exit_triggered):
			level_populator.level_exit_triggered.connect(_on_level_exit_triggered)
		active_sections[0] = level_populator
	else:
		_spawn_section(0)


func _physics_process(delta: float) -> void:
	if not player:
		return
	_update_streaming(delta)


func _update_streaming(delta: float) -> void:
	var sec_len_world := _section_world_length()
	var current_idx := get_section_index_at_z(player.global_position.z)

	if current_idx > furthest_section_reached and active_sections.has(current_idx):
		furthest_section_reached = current_idx

	# 1. Add a new section into the active base scene when the player gets close to the end of the latest section
	var max_active_idx := _max_active_section_index()
	var max_section_end_z := (float(max_active_idx) + 0.5) * sec_len_world
	if player.global_position.z >= max_section_end_z - spawn_ahead_distance:
		_spawn_section(max_active_idx + 1)

	# Also ensure current and next section exist when moving forward
	if current_idx >= 0:
		if not active_sections.has(current_idx):
			_spawn_section(current_idx)
		var current_end_z := (float(current_idx) + 0.5) * sec_len_world
		if player.global_position.z >= current_end_z - spawn_ahead_distance and not active_sections.has(current_idx + 1):
			_spawn_section(current_idx + 1)

	# 2. Remove old sections once the player is over 1 section away
	var to_remove: Array[int] = []
	for idx_var in active_sections.keys():
		var idx: int = int(idx_var)
		if idx >= furthest_section_reached:
			continue
		var section_max_z := (float(idx) + 0.5) * sec_len_world
		# Over 1 section away past the old section's end (or more than 1 section index behind)
		if (player.global_position.z - section_max_z) > sec_len_world or (furthest_section_reached - idx) > 1:
			to_remove.append(idx)

	for idx in to_remove:
		_remove_section(idx)

	# 3. Lose health when the player goes back into an old section
	if _is_in_old_section(player.global_position.z, current_idx):
		if _backtrack_damage_timer <= 0.0:
			if player.has_method("take_damage"):
				player.take_damage(old_section_damage)
			else:
				PlayerStats.take_damage(old_section_damage)
			_backtrack_damage_timer = old_section_damage_interval
		else:
			_backtrack_damage_timer -= delta
	else:
		_backtrack_damage_timer = 0.0


func _is_in_old_section(world_z: float, section_idx: int) -> bool:
	if section_idx < 0:
		return true
	if section_idx < furthest_section_reached:
		return true
	var min_active_idx := _min_active_section_index()
	var min_active_start_z := (float(min_active_idx) - 0.5) * _section_world_length()
	return world_z < min_active_start_z


func get_section_index_at_z(world_z: float) -> int:
	var sec_len := _section_world_length()
	return int(floor((world_z + sec_len * 0.5) / sec_len))


func _section_world_length() -> float:
	var cell := 1.0
	if level_populator and level_populator.level_data:
		cell = level_populator.level_data.cell_size
	return float(maxi(20, section_length)) * cell


func _seed_for_section(idx: int) -> int:
	return base_seed + idx * 7919


func _spawn_section(idx: int) -> LevelMapPopulator:
	if active_sections.has(idx):
		return active_sections[idx] as LevelMapPopulator

	var depth := maxi(20, section_length)
	var width := maxi(40, section_width)
	var sec_seed := _seed_for_section(idx)
	var data := _generator.generate(LevelMapGenerator.GenerationMode.LINEAR_PATH, sec_seed, width, depth, idx)

	var pop := LevelMapPopulator.new()
	pop.name = "LevelSection_%d" % idx
	pop.auto_rebuild_on_ready = false
	pop.generation_mode = LevelMapGenerator.GenerationMode.LINEAR_PATH
	pop.section_index = idx
	pop.section_length = depth
	pop.world_seed = sec_seed
	pop.position = Vector3(0.0, 0.0, float(idx) * _section_world_length())
	pop.level_data = data
	add_child(pop)
	pop.rebuild_all()
	pop.level_exit_triggered.connect(_on_level_exit_triggered)

	active_sections[idx] = pop
	if level_populator == null or not is_instance_valid(level_populator):
		level_populator = pop
	return pop


func _remove_section(idx: int) -> void:
	if not active_sections.has(idx):
		return
	var pop: LevelMapPopulator = active_sections[idx]
	active_sections.erase(idx)
	if is_instance_valid(pop):
		if pop.get_parent() == self:
			remove_child(pop)
		pop.queue_free()
	if level_populator == pop:
		var min_idx := _min_active_section_index()
		level_populator = active_sections.get(min_idx, null)


func _min_active_section_index() -> int:
	if active_sections.is_empty():
		return 0
	var min_idx: int = int(active_sections.keys()[0])
	for k in active_sections.keys():
		min_idx = mini(min_idx, int(k))
	return min_idx


func _max_active_section_index() -> int:
	if active_sections.is_empty():
		return 0
	var max_idx: int = int(active_sections.keys()[0])
	for k in active_sections.keys():
		max_idx = maxi(max_idx, int(k))
	return max_idx


## Invisible floor at valley base height so if the player walks back into a removed old section
## they stay supported while taking damage instead of falling into the void.
func _setup_retreat_floor() -> void:
	if _retreat_floor:
		return
	_retreat_floor = StaticBody3D.new()
	_retreat_floor.name = "RetreatSafetyFloor"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 4000.0)
	col.shape = box
	col.position = Vector3(0.0, 0.5, 1000.0)
	_retreat_floor.add_child(col)
	add_child(_retreat_floor)


func spawn_player(entrance_id: String) -> void:
	if not player:
		return
	# Find the active section containing this entrance_id
	for idx_var in active_sections.keys():
		var pop: LevelMapPopulator = active_sections[idx_var]
		if is_instance_valid(pop) and pop.level_data and pop.level_data.entrances.has(entrance_id):
			player.global_position = pop.get_entrance_world_pos(entrance_id)
			player.velocity = Vector3.ZERO
			return
	if level_populator and is_instance_valid(level_populator):
		player.global_position = level_populator.get_entrance_world_pos(entrance_id)
		player.velocity = Vector3.ZERO


func _on_level_exit_triggered(exit_id: String, target_level_path: String, target_entrance_id: String) -> void:
	# Exits fire inside the physics step, where rebuilding or swapping the level is not safe.
	_change_level.call_deferred(exit_id, target_level_path, target_entrance_id)


func _change_level(exit_id: String, target_level_path: String, target_entrance_id: String) -> void:
	print("Reached exit: ", exit_id, " -> Target: ", target_level_path, " [Entrance: ", target_entrance_id, "]")

	if SidequestManager.is_sidequest_target(target_level_path):
		# target_entrance_id here names the entrance to use on this main level on return.
		SidequestManager.enter_sidequest(target_level_path, target_entrance_id)
		return

	if exit_id == "exit_main" and target_level_path == "":
		# In streaming valley mode, reaching the end of a section ensures the next section is spawned
		# and lets the player walk seamlessly across the boundary without teleporting back.
		var cur_idx := get_section_index_at_z(player.global_position.z) if player else _max_active_section_index()
		_spawn_section(cur_idx + 1)
		return

	if target_level_path != "" and ResourceLoader.exists(target_level_path):
		var res: Resource = load(target_level_path)
		if res is LevelData and level_populator and is_instance_valid(level_populator):
			level_populator.level_data = res as LevelData
			level_populator.rebuild_all()
			spawn_player(target_entrance_id)
			return
		push_warning("Level: exit target '%s' is not LevelData; ignoring." % target_level_path)

	# No valid target: return the player to the target entrance on this level.
	spawn_player(target_entrance_id)
