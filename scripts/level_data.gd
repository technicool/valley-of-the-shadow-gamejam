class_name LevelData
extends Resource
## Stores runtime bezier profile arrays for the valley path and side walls,
## plus entrances, exits, weapon spawns, and enemy guard zones.

enum TerrainType { GRASS, MUD, DEBRIS, DIRT, STONE, WATER }
enum ObjectType { NONE, ROCK_SMALL, ROCK_LARGE, TREE, BUSH, DEBRIS_PILE, RUIN_PILLAR, RUIN_ARTIFACT }

const DEFAULT_STEP_HEIGHT: float = 0.5 / 3.0

@export_group("Map Dimensions")
@export var width: int = 80
@export var depth: int = 50
@export var cell_size: float = 1.0
@export var step_height: float = DEFAULT_STEP_HEIGHT
@export var section_index: int = 0
@export var has_opening_meadow: bool = false
@export var meadow_funnel_end_y: float = 16.0

@export_group("Bezier 3D Profile Data")
## Sampled along Z from 0 to depth (inclusive, size = depth + 1) for pure 3D bezier terrain & wall generation.
@export var bezier_path_x: PackedFloat32Array = PackedFloat32Array()
@export var bezier_trail_half_w: PackedFloat32Array = PackedFloat32Array()
@export var bezier_left_wall_inner_x: PackedFloat32Array = PackedFloat32Array()
@export var bezier_right_wall_inner_x: PackedFloat32Array = PackedFloat32Array()
@export var bezier_left_wall_thick: PackedFloat32Array = PackedFloat32Array()
@export var bezier_right_wall_thick: PackedFloat32Array = PackedFloat32Array()
@export var bezier_left_wall_height: PackedFloat32Array = PackedFloat32Array()
@export var bezier_right_wall_height: PackedFloat32Array = PackedFloat32Array()
@export var bezier_floor_y: PackedFloat32Array = PackedFloat32Array()
@export var bezier_cave_branch_points: PackedVector2Array = PackedVector2Array()

@export_group("Connectors")
@export var entrances: Dictionary = {
	"start": Vector2i(40, 6)
}
@export var exits: Array[LevelExitData] = []

@export_group("Gameplay Spawns & Zones")
@export var weapon_spawns: Array[Dictionary] = []
@export var enemy_guard_zones: Array[Dictionary] = []


func get_floor_height_at_row(y: int) -> float:
	if bezier_floor_y.is_empty():
		return 1.0
	var idx := clampi(y, 0, bezier_floor_y.size() - 1)
	return bezier_floor_y[idx]


func get_world_pos(x: int, y: int) -> Vector3:
	var half_w := width * 0.5 * cell_size
	var half_d := depth * 0.5 * cell_size
	return Vector3(
		(float(x) + 0.5) * cell_size - half_w,
		get_floor_height_at_row(y),
		(float(y) + 0.5) * cell_size - half_d
	)


func world_to_grid(world_pos: Vector3) -> Vector2i:
	var half_w := width * 0.5 * cell_size
	var half_d := depth * 0.5 * cell_size
	var x := int(floor((world_pos.x + half_w) / cell_size))
	var y := int(floor((world_pos.z + half_d) / cell_size))
	return Vector2i(clampi(x, 0, width - 1), clampi(y, 0, depth - 1))
