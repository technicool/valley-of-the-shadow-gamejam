class_name LevelMapGenerator
extends RefCounted
## Procedural generator utilizing FastNoiseLite to synthesize LevelData.
## Supports generation modes:
## - LINEAR_PATH: Main winding path with shoulders, hills, and side branches (tuned for ~30s run time).
## - OPEN_EXPLORATION: Open arena/plains with scattered ruins, mounds, and clearings.
## - SIDE_QUEST_MAZE: Maze-like ravine or catacomb layout with winding corridors and dead ends.

enum GenerationMode {
	LINEAR_PATH,
	OPEN_EXPLORATION,
	SIDE_QUEST_MAZE
}

var mode: GenerationMode = GenerationMode.LINEAR_PATH
var seed_val: int = 1337
var map_width: int = 80
var map_depth: int = 50
var step_height: float = LevelData.DEFAULT_STEP_HEIGHT
var cell_size: float = 1.0
var section_index: int = 0

## Guard gate: ring of ruin pillars around the guarded exit, with a gap on the start side.
const GATE_RING_RADIUS := 4
const GATE_HALF_WIDTH := 1
const GUARD_SETBACK := 2
## Max elevation step difference between neighbors on linear paths.
const LINEAR_CLIFF_MAX_STEPS := 14
## Profile tuning for the procedural valley.
const GREEN_CENTER_HALF_WIDTH := 2.5
const MUD_FLAT_OUTER_RADIUS := 7.5
const DEBRIS_OUTER_RADIUS := 9.5
const WALL_CREST_RADIUS := 13.5
const WALL_MIN_HEIGHT_INCREASE := 6.0
const WALL_MAX_HEIGHT_INCREASE := 20.0
const PASSAGE_HALF_WIDTH := 1.5
const PASSAGE_BLEND_ROWS := 10.0
const SEAM_NOISE_BLEND_ROWS := 8.0
## Ruin-site noise above this value marks a cluster of ruins on the valley shoulders.
const RUIN_SITE_THRESHOLD := 0.62
const SOLID_OBJECTS := [
	LevelData.ObjectType.TREE,
	LevelData.ObjectType.ROCK_LARGE,
	LevelData.ObjectType.ROCK_SMALL,
	LevelData.ObjectType.RUIN_PILLAR,
]

# Noise generators
var _noise_height: FastNoiseLite
var _noise_detail: FastNoiseLite
var _noise_objects: FastNoiseLite
var _noise_ruins: FastNoiseLite
var _noise_seam: FastNoiseLite
var _rng: RandomNumberGenerator


func _init() -> void:
	_noise_height = FastNoiseLite.new()
	_noise_detail = FastNoiseLite.new()
	_noise_objects = FastNoiseLite.new()
	_noise_ruins = FastNoiseLite.new()
	_noise_seam = FastNoiseLite.new()
	_rng = RandomNumberGenerator.new()


func generate(p_mode: GenerationMode, p_seed: int = 1337, p_width: int = 80, p_depth: int = 50, p_section_index: int = 0) -> LevelData:
	mode = p_mode
	seed_val = p_seed
	map_width = p_width
	map_depth = p_depth
	section_index = p_section_index

	_rng.seed = seed_val
	_setup_noise()

	var data := LevelData.new()
	data.width = map_width
	data.depth = map_depth
	data.cell_size = cell_size
	data.step_height = step_height
	data.ensure_size()

	match mode:
		GenerationMode.LINEAR_PATH:
			_generate_linear_path(data)
		GenerationMode.OPEN_EXPLORATION:
			_generate_open_area(data)
		GenerationMode.SIDE_QUEST_MAZE:
			_generate_maze(data)

	_limit_slopes(data, LINEAR_CLIFF_MAX_STEPS if mode == GenerationMode.LINEAR_PATH else 1)
	if mode == GenerationMode.LINEAR_PATH:
		_enforce_linear_seam_match(data)
	_add_guard_gates(data)
	return data


func _setup_noise() -> void:
	_noise_height.seed = seed_val
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_height.frequency = 0.035
	_noise_height.fractal_octaves = 3

	_noise_detail.seed = seed_val + 101
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.frequency = 0.08

	_noise_objects.seed = seed_val + 202
	_noise_objects.noise_type = FastNoiseLite.TYPE_CELLULAR
	_noise_objects.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_noise_objects.frequency = 0.12

	_noise_ruins.seed = seed_val + 303
	_noise_ruins.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_ruins.frequency = 0.045

	_noise_seam.seed = 9001
	_noise_seam.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_seam.frequency = 0.035
	_noise_seam.fractal_octaves = 3


func _path_center_x(y: float) -> float:
	var t := clampf(y / maxf(1.0, float(map_depth - 1)), 0.0, 1.0)
	var envelope := sin(PI * t)
	var phase1 := float(seed_val % 997) * 0.13
	var phase2 := float(seed_val % 577) * 0.29
	var sway := 6.0 * sin(t * TAU + phase1) + 2.5 * sin(t * TAU * 2.0 + phase2)
	return (map_width * 0.5) + envelope * sway


func _seam_weight(y: float) -> float:
	var dist_to_end := minf(y, float(map_depth - 1) - y)
	return smoothstep(0.0, SEAM_NOISE_BLEND_ROWS, dist_to_end)


func _passage_narrow_factor(y: float) -> float:
	var dist_to_end := minf(y, float(map_depth - 1) - y)
	return 1.0 - smoothstep(1.5, PASSAGE_BLEND_ROWS, dist_to_end)


func _sample_wall_noise(x: float, y: float) -> float:
	var w := _seam_weight(y)
	var local_n := (_noise_height.get_noise_2d(x, y) + 1.0) * 0.5
	var seam_n := (_noise_seam.get_noise_2d(x, 0.0) + 1.0) * 0.5
	return lerpf(seam_n, local_n, w)


func _sample_wobble(x: float, y: float) -> float:
	var w := _seam_weight(y)
	return _noise_detail.get_noise_2d(x, y) * 1.5 * w


func _generate_linear_path(data: LevelData) -> void:
	var entrance_y := 4
	var exit_y := maxi(entrance_y + 10, map_depth - 3)
	var center_start_x := int(round(_path_center_x(float(entrance_y))))
	var center_exit_x := int(round(_path_center_x(float(exit_y))))
	var start_pos := Vector2i(center_start_x, entrance_y)
	var main_exit_pos := Vector2i(center_exit_x, exit_y)

	data.entrances["start"] = start_pos

	# Cave entrance on the steep valley wall on the left (-1) or the right (+1).
	var cave_y := clampi(int(round(map_depth * 0.5)), 12, maxi(12, map_depth - 13))
	var cave_side := -1 if (_rng.randi() % 2 == 0) else 1
	var cave_center_x := _path_center_x(float(cave_y))
	var wall_offset := int(round(MUD_FLAT_OUTER_RADIUS + 4.0))
	var side_exit_x := clampi(int(round(cave_center_x)) + cave_side * wall_offset, 6, map_width - 7)
	var side_exit_pos := Vector2i(side_exit_x, cave_y)
	# Return point placed 4 cells toward the valley center along the green trail so returning does not re-trigger the cave.
	var return_x := clampi(side_exit_pos.x - cave_side * 4, 4, map_width - 5)
	var return_id := "from_sidequest_%d" % section_index
	data.entrances["from_sidequest"] = Vector2i(return_x, cave_y)
	data.entrances[return_id] = Vector2i(return_x, cave_y)

	var main_exit := LevelExitData.new()
	main_exit.id = "exit_main"
	main_exit.grid_pos = main_exit_pos
	main_exit.label = "Next Area"
	main_exit.color = Color(0.3, 0.8, 1.0)
	data.exits.append(main_exit)

	# Sidequest cave entrance on the steep valley wall
	var side_exit := LevelExitData.new()
	side_exit.id = "exit_sidequest"
	side_exit.grid_pos = side_exit_pos
	side_exit.target_level_path = "sidequest://random"
	side_exit.target_entrance_id = return_id
	side_exit.label = "Side Quest Cave"
	side_exit.color = Color(0.35, 0.85, 0.45)
	side_exit.is_cave_entrance = true
	side_exit.cave_side = cave_side
	data.exits.append(side_exit)

	var base_floor_elev := 1.0

	for y in range(map_depth):
		var center_x := _path_center_x(float(y))
		var narrow := _passage_narrow_factor(float(y))
		var flat_outer := lerpf(MUD_FLAT_OUTER_RADIUS, PASSAGE_HALF_WIDTH, narrow)
		var debris_outer := lerpf(DEBRIS_OUTER_RADIUS, PASSAGE_HALF_WIDTH + 1.0, narrow)
		var wall_crest := lerpf(WALL_CREST_RADIUS, PASSAGE_HALF_WIDTH + 3.0, narrow)
		var green_half := minf(GREEN_CENTER_HALF_WIDTH, flat_outer)

		for x in range(map_width):
			var dist_to_path := absf(float(x) - center_x)
			var wobble := _sample_wobble(float(x), float(y))

			# Check if cell is part of the green trail leading into the cave opening on the steep wall
			var on_cave_trail := false
			var cave_trail_dist := 999.0
			var in_cave_Span := (cave_side > 0 and float(x) >= center_x and x <= side_exit_pos.x + 1) or (cave_side < 0 and float(x) <= center_x and x >= side_exit_pos.x - 1)
			if in_cave_Span and absi(y - cave_y) <= 2:
				cave_trail_dist = absf(float(y) - float(cave_y))
				if cave_trail_dist <= 1.5 and ((cave_side > 0 and x <= side_exit_pos.x) or (cave_side < 0 and x >= side_exit_pos.x)):
					on_cave_trail = true

			var n := _sample_wall_noise(float(x), float(y))
			# Steep valley wall: 6 to 20 m height increase above the valley floor, with cliff edges.
			var wall_increase := lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, clampf(n, 0.0, 1.0))
			if narrow > 0.25 and dist_to_path > PASSAGE_HALF_WIDTH:
				wall_increase = maxf(wall_increase, 10.0)

			var wall_blend := smoothstep(flat_outer, wall_crest, dist_to_path)
			# Steepen into cliff edges
			wall_blend = pow(wall_blend, 0.65)
			var elevation := base_floor_elev + wall_increase * wall_blend

			# Carve flat green trail into the cave opening on the steep wall (leaving the rock above/around it)
			if on_cave_trail:
				elevation = base_floor_elev
			elif in_cave_Span and cave_trail_dist <= 2.5 and ((cave_side > 0 and x <= side_exit_pos.x + 1) or (cave_side < 0 and x >= side_exit_pos.x - 1)):
				# Steep cave walls framing the cave mouth
				elevation = maxf(elevation, base_floor_elev + 10.0)

			# Outer X rim walls (keep Y seams governed by the narrow passageway so sections match cleanly)
			var x_edge_dist := float(mini(x, map_width - 1 - x))
			if x_edge_dist < 6.0 and not on_cave_trail:
				elevation = maxf(elevation, base_floor_elev + WALL_MIN_HEIGHT_INCREASE + (6.0 - x_edge_dist) * 2.0)

			var max_steps := int(round(26.0 / step_height))
			var elev_int := clampi(int(round(elevation / step_height)), 0, max_steps)
			data.set_cell_elevation(x, y, elev_int)

			# Terrain type: green center same width (2.5), wider muddy flat area, then steep wall with cliff edges
			var t_dist := dist_to_path + wobble * (1.0 - narrow)
			var terrain := LevelData.TerrainType.DIRT
			if on_cave_trail or dist_to_path <= 1.25:
				terrain = LevelData.TerrainType.GRASS
			elif t_dist < green_half:
				terrain = LevelData.TerrainType.GRASS
			elif dist_to_path < flat_outer:
				terrain = LevelData.TerrainType.MUD
			elif dist_to_path < debris_outer:
				terrain = LevelData.TerrainType.DEBRIS
			elif wall_blend > 0.35:
				terrain = LevelData.TerrainType.STONE if n > 0.55 else LevelData.TerrainType.DIRT
			data.set_cell_terrain(x, y, terrain)

			# Static object placement (keep the green center, cave trail, and end passageways clear)
			var y_edge_dist := float(mini(y, map_depth - 1 - y))
			if not on_cave_trail and dist_to_path > green_half + 1.0 and x_edge_dist > 2.0 and y_edge_dist > 3.0:
				var obj_val := _noise_objects.get_noise_2d(float(x), float(y))
				if terrain == LevelData.TerrainType.DEBRIS and obj_val > 0.45:
					data.set_cell_object(x, y, LevelData.ObjectType.DEBRIS_PILE)
				elif terrain == LevelData.TerrainType.DIRT and obj_val > 0.55:
					data.set_cell_object(x, y, LevelData.ObjectType.TREE)
				elif (terrain == LevelData.TerrainType.DIRT or terrain == LevelData.TerrainType.STONE) and obj_val > 0.4:
					data.set_cell_object(x, y, LevelData.ObjectType.ROCK_LARGE)
				elif terrain == LevelData.TerrainType.MUD and obj_val > 0.62:
					data.set_cell_object(x, y, LevelData.ObjectType.BUSH)
				elif dist_to_path > flat_outer + 1.0 and _noise_ruins.get_noise_2d(float(x), float(y)) > RUIN_SITE_THRESHOLD:
					var roll := _rng.randf()
					if roll < 0.25:
						data.set_cell_object(x, y, LevelData.ObjectType.RUIN_PILLAR)
					elif roll < 0.45:
						data.set_cell_object(x, y, LevelData.ObjectType.RUIN_ARTIFACT)

	# Gameplay zones: Weapon spawns along the valley floor and near the cave trail
	var weapon_y := clampi(int(round(map_depth * 0.3)), 6, map_depth - 10)
	data.weapon_spawns.append({
		"id": "relic_blade_%d" % section_index,
		"type": "ancient_blade",
		"pos": Vector2i(clampi(int(round(_path_center_x(float(weapon_y)))) + 4, 4, map_width - 5), weapon_y),
		"respawn": false
	})
	data.weapon_spawns.append({
		"id": "sacred_relic_%d" % section_index,
		"type": "sun_pendant",
		"pos": Vector2i(clampi(side_exit_pos.x - cave_side * 2, 4, map_width - 5), cave_y),
		"respawn": false
	})


## Ensures row 0 and row (map_depth - 1) have identical elevations and terrain across all seeds
## so adjacent valley sections meet without any visible seam.
func _enforce_linear_seam_match(data: LevelData) -> void:
	var base_steps := int(round(1.0 / step_height))
	var center_x := map_width * 0.5
	for x in range(map_width):
		var dist := absf(float(x) - center_x)
		var seam_n := (_noise_seam.get_noise_2d(float(x), 0.0) + 1.0) * 0.5
		var wall_inc := maxf(10.0, lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, clampf(seam_n, 0.0, 1.0)))
		var blend := pow(smoothstep(PASSAGE_HALF_WIDTH, PASSAGE_HALF_WIDTH + 3.0, dist), 0.65)
		var elev := 1.0 + wall_inc * blend
		var elev_steps := int(round(elev / step_height))
		var terrain := LevelData.TerrainType.DIRT
		if dist <= PASSAGE_HALF_WIDTH:
			elev_steps = base_steps
			terrain = LevelData.TerrainType.GRASS
		elif dist <= PASSAGE_HALF_WIDTH + 1.0:
			terrain = LevelData.TerrainType.DEBRIS
		elif seam_n > 0.55:
			terrain = LevelData.TerrainType.STONE

		for seam_y: int in [0, map_depth - 1]:
			data.set_cell_elevation(x, seam_y, elev_steps)
			data.set_cell_terrain(x, seam_y, terrain)
			data.set_cell_object(x, seam_y, LevelData.ObjectType.NONE)
		# Keep the passageway floor level for 3 rows inside each end
		if dist <= PASSAGE_HALF_WIDTH:
			for inner_y: int in [1, 2, map_depth - 3, map_depth - 2]:
				if inner_y >= 0 and inner_y < map_depth:
					data.set_cell_elevation(x, inner_y, base_steps)
					data.set_cell_terrain(x, inner_y, LevelData.TerrainType.GRASS)
					data.set_cell_object(x, inner_y, LevelData.ObjectType.NONE)


func _generate_open_area(data: LevelData) -> void:
	var start_pos := Vector2i(map_width / 2, 8)
	data.entrances["start"] = start_pos

	var exit_north := LevelExitData.new()
	exit_north.id = "exit_north"
	exit_north.grid_pos = Vector2i(map_width / 2, map_depth - 8)
	exit_north.label = "To High Pass"
	exit_north.color = Color(0.4, 0.9, 0.4)
	data.exits.append(exit_north)

	var exit_east := LevelExitData.new()
	exit_east.id = "exit_east"
	exit_east.grid_pos = Vector2i(map_width - 8, map_depth / 2)
	exit_east.label = "To Eastern Barrens"
	exit_east.color = Color(1.0, 0.8, 0.2)
	data.exits.append(exit_east)

	for y in range(map_depth):
		for x in range(map_width):
			var n := (_noise_height.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var elev := 1.5 + n * 4.0

			var edge_dist := minf(minf(x, map_width - 1 - x), minf(y, map_depth - 1 - y))
			if edge_dist < 5.0 and not _is_near_exit_or_entrance(Vector2i(x, y), data):
				elev += (5.0 - edge_dist) * 2.0

			var elev_int := clampi(int(round(elev / step_height)), 0, 30)
			data.set_cell_elevation(x, y, elev_int)

			var t_noise := _noise_detail.get_noise_2d(float(x), float(y))
			var terrain := LevelData.TerrainType.GRASS
			if t_noise > 0.35:
				terrain = LevelData.TerrainType.DIRT
			elif t_noise < -0.35:
				terrain = LevelData.TerrainType.MUD
			elif t_noise > 0.15 and t_noise < 0.3:
				terrain = LevelData.TerrainType.DEBRIS
			data.set_cell_terrain(x, y, terrain)

			var obj_noise := _noise_objects.get_noise_2d(float(x), float(y))
			if obj_noise > 0.65:
				data.set_cell_object(x, y, LevelData.ObjectType.RUIN_PILLAR)
			elif obj_noise > 0.45:
				data.set_cell_object(x, y, LevelData.ObjectType.TREE)
			elif obj_noise > 0.3:
				data.set_cell_object(x, y, LevelData.ObjectType.ROCK_LARGE)

	data.weapon_spawns.append({
		"id": "arena_greatsword",
		"type": "greatsword",
		"pos": Vector2i(map_width / 2 + 5, map_depth / 2),
		"respawn": true
	})


func _generate_maze(data: LevelData) -> void:
	var start_pos := Vector2i(4, 4)
	data.entrances["start"] = start_pos

	var exit_end := LevelExitData.new()
	exit_end.id = "exit_depths"
	exit_end.grid_pos = Vector2i(map_width - 6, map_depth - 6)
	exit_end.label = "To Deep Sanctum"
	exit_end.color = Color(0.9, 0.2, 0.6)
	data.exits.append(exit_end)

	for y in range(map_depth):
		for x in range(map_width):
			# Maze carved using multi-frequency thresholding
			var wall_noise := _noise_detail.get_noise_2d(float(x) * 1.5, float(y) * 1.5)
			var is_wall := absf(wall_noise) > 0.18

			var edge_dist := minf(minf(x, map_width - 1 - x), minf(y, map_depth - 1 - y))
			if edge_dist < 4.0:
				is_wall = true

			if (x <= 6 and y <= 6) or (x >= map_width - 8 and y >= map_depth - 8):
				is_wall = false

			var elev := 5.0 if is_wall else 1.0
			var elev_int := int(round(elev / step_height))
			data.set_cell_elevation(x, y, elev_int)

			var terrain := LevelData.TerrainType.STONE if is_wall else LevelData.TerrainType.DIRT
			data.set_cell_terrain(x, y, terrain)

			if is_wall and _rng.randf() < 0.1:
				data.set_cell_object(x, y, LevelData.ObjectType.RUIN_PILLAR)
			elif not is_wall and _rng.randf() < 0.05:
				data.set_cell_object(x, y, LevelData.ObjectType.DEBRIS_PILE)

	data.weapon_spawns.append({
		"id": "labyrinth_dagger",
		"type": "shadow_dagger",
		"pos": Vector2i(map_width / 2, map_depth / 2),
		"respawn": false
	})


func _is_near_exit_or_entrance(pos: Vector2i, data: LevelData) -> bool:
	for ent: Vector2i in data.entrances.values():
		if pos.distance_to(ent) < 5.0:
			return true
	for exit_item: LevelExitData in data.exits:
		if pos.distance_to(exit_item.grid_pos) < 5.0:
			return true
	return false


## Rings each guarded exit with ruin pillars and leaves a 3-cell gap on the start side.
func _add_guard_gates(data: LevelData) -> void:
	match mode:
		GenerationMode.LINEAR_PATH:
			_add_guard_gate(data, "exit_main", "valley_guardian", "shadow_sentinel", 5.5)
		GenerationMode.OPEN_EXPLORATION:
			_add_guard_gate(data, "exit_north", "gatekeeper_north", "gargoyle_warlord", 6.0)
		GenerationMode.SIDE_QUEST_MAZE:
			_add_guard_gate(data, "exit_depths", "maze_stalker", "labyrinth_beast", 5.0)


## Places the guard two cells outside the gap. The ring is kept only if the gap is the sole route to the exit.
func _add_guard_gate(data: LevelData, exit_id: String, guard_id: String, enemy_type: String, guard_radius: float) -> void:
	var exit_pos := _exit_grid_pos(data, exit_id)
	if data.get_index(exit_pos.x, exit_pos.y) < 0:
		push_warning("Guard gate skipped: exit %s not found." % exit_id)
		return
	var start: Vector2i = data.entrances["start"]
	var ring_top := exit_pos.y - GATE_RING_RADIUS

	var ring: Array[Vector2i] = []
	var gap: Array = []
	for y in range(ring_top, exit_pos.y + GATE_RING_RADIUS + 1):
		for x in range(exit_pos.x - GATE_RING_RADIUS, exit_pos.x + GATE_RING_RADIUS + 1):
			if data.get_index(x, y) < 0 or maxi(absi(x - exit_pos.x), absi(y - exit_pos.y)) != GATE_RING_RADIUS:
				continue
			if mode == GenerationMode.LINEAR_PATH and y > exit_pos.y and absi(x - exit_pos.x) <= GATE_HALF_WIDTH:
				continue
			ring.append(Vector2i(x, y))
			if y == ring_top and absi(x - exit_pos.x) <= GATE_HALF_WIDTH:
				gap.append(Vector2i(x, y))

	var gap_set := {}
	for cell: Vector2i in gap:
		gap_set[cell] = true
	var saved_objects: Array[int] = []
	for cell in ring:
		saved_objects.append(data.get_cell_object(cell.x, cell.y))
		var open_cell: bool = gap_set.has(cell)
		data.set_cell_object(cell.x, cell.y, LevelData.ObjectType.NONE if open_cell else LevelData.ObjectType.RUIN_PILLAR)

	var sealed := not _route_exists(data, start, exit_pos, gap_set)
	var open_route := _route_exists(data, start, exit_pos, {})
	var others_open := true
	for exit_item: LevelExitData in data.exits:
		if exit_item.id != exit_id and not _route_exists(data, start, exit_item.grid_pos, gap_set):
			others_open = false

	if sealed and open_route and others_open and not gap.is_empty():
		var guard_pos := Vector2i(exit_pos.x, ring_top - GUARD_SETBACK)
		if _is_solid(data.get_cell_object(guard_pos.x, guard_pos.y)):
			data.set_cell_object(guard_pos.x, guard_pos.y, LevelData.ObjectType.NONE)
		data.enemy_guard_zones.append({
			"id": guard_id,
			"enemy_type": enemy_type,
			"guard_pos": guard_pos,
			"guard_radius": guard_radius,
			"blocks_path": true,
			"barrier_cells": gap
		})
		return

	for i in ring.size():
		data.set_cell_object(ring[i].x, ring[i].y, saved_objects[i])
	push_warning("Guard gate for %s is not a sealed chokepoint; no guard placed." % exit_id)


func _exit_grid_pos(data: LevelData, exit_id: String) -> Vector2i:
	for exit_item: LevelExitData in data.exits:
		if exit_item.id == exit_id:
			return exit_item.grid_pos
	return Vector2i(-1, -1)


func _is_solid(object_type: int) -> bool:
	return object_type in SOLID_OBJECTS


## True if `to` is reachable from `from` over walkable cells, ignoring `blocked` cells.
func _route_exists(data: LevelData, from: Vector2i, to: Vector2i, blocked: Dictionary) -> bool:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			return true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nb := cur + Vector2i(dx, dy)
				if (dx == 0 and dy == 0) or seen.has(nb) or blocked.has(nb):
					continue
				if _can_step(data, cur, nb, to):
					seen[nb] = true
					queue.append(nb)
	return false


func _can_step(data: LevelData, from: Vector2i, to: Vector2i, goal: Vector2i) -> bool:
	if data.get_index(to.x, to.y) < 0:
		return false
	if to != goal and _is_solid(data.get_cell_object(to.x, to.y)):
		return false
	var max_climb_steps := maxi(1, int(floor(0.6 / maxf(0.01, data.step_height))))
	if absi(data.get_cell_elevation(to.x, to.y) - data.get_cell_elevation(from.x, from.y)) > max_climb_steps:
		return false
	if from.x != to.x and from.y != to.y:
		for corner: Vector2i in [Vector2i(to.x, from.y), Vector2i(from.x, to.y)]:
			if data.get_index(corner.x, corner.y) < 0 or _is_solid(data.get_cell_object(corner.x, corner.y)):
				return false
	return true


## Clamps each cell so it is at most `max_step_diff` steps above any neighbor.
func _limit_slopes(data: LevelData, max_step_diff: int) -> void:
	var total := data.width * data.depth
	var top := 0
	for i in total:
		top = maxi(top, data.elevation_cells[i])
	var buckets: Array = []
	for b in top + 1:
		buckets.append([])
	for idx in total:
		buckets[data.elevation_cells[idx]].append(idx)
	for level in top + 1:
		for idx in buckets[level]:
			if data.elevation_cells[idx] != level:
				continue
			var i: int = idx % data.width
			@warning_ignore("integer_division")
			var j: int = idx / data.width
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ni: int = i + di
					var nj: int = j + dj
					if (di == 0 and dj == 0) or ni < 0 or nj < 0 or ni >= data.width or nj >= data.depth:
						continue
					var n: int = nj * data.width + ni
					if data.elevation_cells[n] > level + max_step_diff:
						data.elevation_cells[n] = level + max_step_diff
						buckets[level + max_step_diff].append(n)
