extends SceneTree

var _frame := 0
var _pop: Node3D
var _player: CharacterBody3D
var _triggered_exit_id := ""

func _initialize() -> void:
	var gen := LevelMapGenerator.new()
	var data := gen.generate(LevelMapGenerator.GenerationMode.LINEAR_PATH, 1337, 80, 50, 0)
	ResourceSaver.save(data, "res://levels/level_01.tres")

func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var gen := LevelMapGenerator.new()
		var data := gen.generate(LevelMapGenerator.GenerationMode.LINEAR_PATH, 1337, 80, 50, 0)
		assert(gen._path_curve != null and gen._path_curve.point_count >= 5, "Bezier path should have multiple segments")
		assert(gen._branch_curve != null and gen._branch_curve.point_count >= 3, "Bezier cave branch should have segments")

		# 1. Verify floor terrain height changes are minimal and cliff walls are 2-5x player height (3.6m - 9.0m above floor)
		var min_floor_elev := 999.0
		var max_floor_elev := -999.0
		var min_wall_crest_inc := 999.0
		var max_wall_crest_inc := -999.0
		for y in range(data.depth):
			for x in range(data.width):
				var t := data.get_cell_terrain(x, y)
				var h := data.get_cell_elevation(x, y) * data.step_height
				if t == LevelData.TerrainType.GRASS or t == LevelData.TerrainType.MUD:
					min_floor_elev = minf(min_floor_elev, h)
					max_floor_elev = maxf(max_floor_elev, h)
				elif t == LevelData.TerrainType.STONE:
					var inc := h - 1.0
					min_wall_crest_inc = minf(min_wall_crest_inc, inc)
					max_wall_crest_inc = maxf(max_wall_crest_inc, inc)
		print("Floor elevation range: ", min_floor_elev, " to ", max_floor_elev)
		print("Cliff wall height increase range: ", min_wall_crest_inc, " to ", max_wall_crest_inc)
		assert(max_floor_elev - min_floor_elev <= 0.35, "Floor terrain height changes should be minimal")
		assert(max_wall_crest_inc >= 3.6 and max_wall_crest_inc <= 9.1, "Cliff walls should be 2-5x player height (3.6m - 9.0m)")

		# 2. Verify cave entrance has no walls before it and has a 3m grass floor tunnel into the wall
		var cave_exit: LevelExitData = null
		for ex in data.exits:
			if ex.id == "exit_sidequest":
				cave_exit = ex
		assert(cave_exit != null, "Sidequest cave exit missing")
		var cave_pos := cave_exit.grid_pos
		var side := cave_exit.cave_side
		var center_at_cave := int(round(gen._path_center_x(float(cave_pos.y))))
		print("Cave pos: ", cave_pos, " side: ", side, " path center: ", center_at_cave)

		# Check all cells between path center and cave entrance have flat floor (no wall before cave entrance)
		var x0 := mini(center_at_cave, cave_pos.x)
		var x1 := maxi(center_at_cave, cave_pos.x)
		for x in range(x0, x1 + 1):
			var h := data.get_cell_elevation(x, cave_pos.y) * data.step_height
			assert(absf(h - 1.0) <= 0.2, "Unexpected wall before cave entrance at x=%d (h=%f)" % [x, h])
			assert(data.get_cell_object(x, cave_pos.y) == LevelData.ObjectType.NONE, "Unexpected obstacle before cave entrance at x=%d" % x)

		# Check 3 meters into cave tunnel has grass floor at floor level
		for step_in in range(0, 4):
			var tx := cave_pos.x + side * step_in
			var t_terrain := data.get_cell_terrain(tx, cave_pos.y)
			var t_elev := data.get_cell_elevation(tx, cave_pos.y) * data.step_height
			assert(t_terrain == LevelData.TerrainType.GRASS, "Tunnel cell at depth %d is not GRASS" % step_in)
			assert(absf(t_elev - 1.0) <= 0.2, "Tunnel cell at depth %d is not floor height (%f)" % [step_in, t_elev])

		# 3. Instantiate LevelMapPopulator and Player to test hit test right at cave entrance
		var pop_script: Script = load("res://scripts/level_map_populator.gd")
		_pop = pop_script.new()
		_pop.auto_rebuild_on_ready = false
		_pop.level_data = data
		root.add_child(_pop)
		_pop.rebuild_all()
		_pop.level_exit_triggered.connect(func(exit_id: String, _target_path: String, _target_ent: String):
			_triggered_exit_id = exit_id
		)

		var portal := _pop.get_node_or_null("GeneratedGameplay/Exit_exit_sidequest") as Area3D
		assert(portal != null, "Cave exit Area3D missing")
		var col := portal.get_node_or_null("ExitTriggerShape") as CollisionShape3D
		assert(col != null and col.get_parent() == portal, "ExitTriggerShape must be a child of portal_area")
		var grass_mesh := portal.get_node_or_null("CaveEntrance/CaveTunnelGrassFloor") as MeshInstance3D
		assert(grass_mesh != null, "CaveTunnelGrassFloor mesh missing")
		assert(absf((grass_mesh.mesh as BoxMesh).size.x - 3.0) < 0.01, "Cave grass floor mesh should be 3m long")

		var player_scene: PackedScene = load("res://scenes/player.tscn")
		_player = player_scene.instantiate()
		root.add_child(_player)
		# Place player at return entrance (4m before cave entrance) - should NOT trigger
		_player.global_position = _pop.get_entrance_world_pos("from_sidequest")
	elif _frame == 4:
		assert(_triggered_exit_id == "", "Cave hit test triggered too far from entrance: " + _triggered_exit_id)
		# Move player right to the cave entrance mouth
		var data: LevelData = _pop.get("level_data")
		for ex in data.exits:
			if ex.id == "exit_sidequest":
				_player.global_position = data.get_world_pos(ex.grid_pos.x, ex.grid_pos.y) + Vector3(0.0, 0.5, 0.0)
	elif _frame == 8:
		print("Triggered exit at cave mouth: ", _triggered_exit_id)
		assert(_triggered_exit_id == "exit_sidequest", "Cave hit test did not trigger right at the cave entrance")
		print("ALL CHECKS PASSED")
		quit(0)
		return true
	elif _frame > 20:
		push_error("Timed out")
		quit(1)
		return true
	return false
