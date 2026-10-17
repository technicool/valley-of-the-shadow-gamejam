class_name LevelData
extends Resource
## Stores serialized grid terrain, elevation, static objects, weapon spawns,
## enemy guard regions, and configurable entrance/exit connectors.

enum TerrainType { GRASS, MUD, DEBRIS, DIRT, STONE, WATER }
enum ObjectType { NONE, ROCK_SMALL, ROCK_LARGE, TREE, BUSH, DEBRIS_PILE, RUIN_PILLAR }

@export_group("Map Dimensions")
@export var width: int = 80
@export var depth: int = 80
@export var cell_size: float = 1.0
@export var step_height: float = 0.5

@export_group("Grid Data")
## Packed arrays of length (width * depth).
## Index = y * width + x
@export var terrain_cells: PackedInt32Array = PackedInt32Array()
@export var elevation_cells: PackedInt32Array = PackedInt32Array()
@export var object_cells: PackedInt32Array = PackedInt32Array()

@export_group("Connectors")
## Start / entrance positions keyed by entrance id (e.g. {"start": Vector2i(40, 5), "from_dungeon": Vector2i(...)})
@export var entrances: Dictionary = {
	"start": Vector2i(40, 6)
}
## List of exit connectors to other levels
@export var exits: Array[LevelExitData] = []

@export_group("Gameplay Spawns & Zones")
## Array of Dictionaries: {"id": "relic_blade_1", "type": "ancient_blade", "pos": Vector2i(x, y), "respawn": false}
@export var weapon_spawns: Array[Dictionary] = []
## Array of Dictionaries: {
##   "id": "guard_1",
##   "enemy_type": "shadow_sentinel",
##   "guard_pos": Vector2i(x, y),
##   "guard_radius": 5.0,
##   "blocks_path": true,
##   "barrier_cells": [Vector2i(x, y), ...] # Gap cells sealed by the guard gate
## }
@export var enemy_guard_zones: Array[Dictionary] = []


func ensure_size() -> void:
	var total := width * depth
	if terrain_cells.size() != total:
		terrain_cells.resize(total)
	if elevation_cells.size() != total:
		elevation_cells.resize(total)
	if object_cells.size() != total:
		object_cells.resize(total)


func get_index(x: int, y: int) -> int:
	if x < 0 or x >= width or y < 0 or y >= depth:
		return -1
	return y * width + x


func get_cell_terrain(x: int, y: int) -> int:
	var idx := get_index(x, y)
	return terrain_cells[idx] if idx >= 0 and idx < terrain_cells.size() else 0


func set_cell_terrain(x: int, y: int, val: int) -> void:
	var idx := get_index(x, y)
	if idx >= 0:
		if terrain_cells.size() <= idx:
			ensure_size()
		terrain_cells[idx] = val


func get_cell_elevation(x: int, y: int) -> int:
	var idx := get_index(x, y)
	return elevation_cells[idx] if idx >= 0 and idx < elevation_cells.size() else 0


func set_cell_elevation(x: int, y: int, val: int) -> void:
	var idx := get_index(x, y)
	if idx >= 0:
		if elevation_cells.size() <= idx:
			ensure_size()
		elevation_cells[idx] = val


func get_cell_object(x: int, y: int) -> int:
	var idx := get_index(x, y)
	return object_cells[idx] if idx >= 0 and idx < object_cells.size() else 0


func set_cell_object(x: int, y: int, val: int) -> void:
	var idx := get_index(x, y)
	if idx >= 0:
		if object_cells.size() <= idx:
			ensure_size()
		object_cells[idx] = val


func get_world_pos(x: int, y: int) -> Vector3:
	var elev := get_cell_elevation(x, y)
	var half_w := width * 0.5 * cell_size
	var half_d := depth * 0.5 * cell_size
	return Vector3(
		(x + 0.5) * cell_size - half_w,
		elev * step_height,
		(y + 0.5) * cell_size - half_d
	)


func world_to_grid(world_pos: Vector3) -> Vector2i:
	var half_w := width * 0.5 * cell_size
	var half_d := depth * 0.5 * cell_size
	var x := int(floor((world_pos.x + half_w) / cell_size))
	var y := int(floor((world_pos.z + half_d) / cell_size))
	return Vector2i(clampi(x, 0, width - 1), clampi(y, 0, depth - 1))
