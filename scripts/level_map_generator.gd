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
var map_depth: int = 80
var step_height: float = 0.5
var cell_size: float = 1.0

## Guard gate: ring of ruin pillars around the guarded exit, with a gap on the start side.
const GATE_RING_RADIUS := 4
const GATE_HALF_WIDTH := 1
const GUARD_SETBACK := 2
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
var _rng: RandomNumberGenerator


func _init() -> void:
	_noise_height = FastNoiseLite.new()
	_noise_detail = FastNoiseLite.new()
	_noise_objects = FastNoiseLite.new()
	_rng = RandomNumberGenerator.new()


func generate(p_mode: GenerationMode, p_seed: int = 1337, p_width: int = 80, p_depth: int = 80) -> LevelData:
	mode = p_mode
	seed_val = p_seed
	map_width = p_width
	map_depth = p_depth

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

	_limit_slopes(data)
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


func _path_center_x(y: float) -> float:
	var half_d := map_depth * 0.5
	var z := y - half_d
	return (map_width * 0.5) + 7.0 * sin(z * 0.07) + 3.0 * sin(z * 0.17 + 1.3)


func _generate_linear_path(data: LevelData) -> void:
	var entrance_y := 6
	var exit_y := map_depth - 7
	var start_pos := Vector2i(int(_path_center_x(entrance_y)), entrance_y)
	var main_exit_pos := Vector2i(int(_path_center_x(exit_y)), exit_y)

	data.entrances["start"] = start_pos
	# Return point used when the player comes back from a sidequest map.
	data.entrances["from_sidequest"] = Vector2i(clampi(int(_path_center_x(40)) + 26, 4, map_width - 5), 41)

	var main_exit := LevelExitData.new()
	main_exit.id = "exit_main"
	main_exit.grid_pos = main_exit_pos
	main_exit.label = "Next Area"
	main_exit.color = Color(0.3, 0.8, 1.0)
	data.exits.append(main_exit)

	# Optional side quest branch exit halfway through
	var side_exit_pos := Vector2i(clampi(int(_path_center_x(40)) + 26, 4, map_width - 5), 40)
	var side_exit := LevelExitData.new()
	side_exit.id = "exit_sidequest"
	side_exit.grid_pos = side_exit_pos
	side_exit.target_level_path = "sidequest://random"
	side_exit.target_entrance_id = "from_sidequest"
	side_exit.label = "Side Quest: The Sunken Ruins"
	side_exit.color = Color(1.0, 0.6, 0.2)
	data.exits.append(side_exit)

	for y in range(map_depth):
		var center_x := _path_center_x(y)
		for x in range(map_width):
			var dist_to_path := absf(float(x) - center_x)
			var wobble := _noise_detail.get_noise_2d(float(x), float(y)) * 1.5

			# Connect side branch at y ~ 40
			if y >= 37 and y <= 43 and x >= center_x and x <= side_exit_pos.x:
				dist_to_path = minf(dist_to_path, absf(float(y) - 40.0))

			var n := (_noise_height.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var hills := 2.0 + 8.0 * n * n
			var path_elev := 1.0 + 0.8 * sin(float(y) * 0.08)
			var blend := smoothstep(2.5, 9.0, dist_to_path)
			var elevation := lerpf(path_elev, hills, blend)

			# Perimeter rim walls
			var edge_dist := minf(minf(x, map_width - 1 - x), minf(y, map_depth - 1 - y))
			if edge_dist < 6.0 and not _is_near_exit_or_entrance(Vector2i(x, y), data):
				elevation += (6.0 - edge_dist) * 1.8

			var elev_int := clampi(int(round(elevation / step_height)), 0, 30)
			data.set_cell_elevation(x, y, elev_int)

			# Terrain type
			var t_dist := dist_to_path + wobble
			var terrain := LevelData.TerrainType.DIRT
			if t_dist < 2.5:
				terrain = LevelData.TerrainType.GRASS
			elif t_dist < 4.5:
				terrain = LevelData.TerrainType.MUD
			elif t_dist < 7.5:
				terrain = LevelData.TerrainType.DEBRIS
			data.set_cell_terrain(x, y, terrain)

			# Static object placement
			if t_dist > 2.0 and edge_dist > 2.0:
				var obj_val := _noise_objects.get_noise_2d(float(x), float(y))
				if terrain == LevelData.TerrainType.DEBRIS and obj_val > 0.45:
					data.set_cell_object(x, y, LevelData.ObjectType.DEBRIS_PILE)
				elif terrain == LevelData.TerrainType.DIRT and obj_val > 0.55:
					data.set_cell_object(x, y, LevelData.ObjectType.TREE)
				elif terrain == LevelData.TerrainType.DIRT and obj_val > 0.4:
					data.set_cell_object(x, y, LevelData.ObjectType.ROCK_LARGE)
				elif terrain == LevelData.TerrainType.MUD and obj_val > 0.6:
					data.set_cell_object(x, y, LevelData.ObjectType.BUSH)

	# Gameplay zones: Weapon spawn midway along side branch or shoulder
	data.weapon_spawns.append({
		"id": "relic_blade_1",
		"type": "ancient_blade",
		"pos": Vector2i(clampi(int(_path_center_x(25)) + 4, 0, map_width - 1), 25),
		"respawn": false
	})
	data.weapon_spawns.append({
		"id": "sacred_relic_2",
		"type": "sun_pendant",
		"pos": Vector2i(side_exit_pos.x - 2, 40),
		"respawn": false
	})


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
	if absi(data.get_cell_elevation(to.x, to.y) - data.get_cell_elevation(from.x, from.y)) > 1:
		return false
	if from.x != to.x and from.y != to.y:
		for corner: Vector2i in [Vector2i(to.x, from.y), Vector2i(from.x, to.y)]:
			if data.get_index(corner.x, corner.y) < 0 or _is_solid(data.get_cell_object(corner.x, corner.y)):
				return false
	return true


func _limit_slopes(data: LevelData) -> void:
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
					if data.elevation_cells[n] > level + 1:
						data.elevation_cells[n] = level + 1
						buckets[level + 1].append(n)
