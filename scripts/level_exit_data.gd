class_name LevelExitData
extends Resource
## Defines an exit point linking to another level.

@export var id: String = "exit_main"
@export var grid_pos: Vector2i = Vector2i(40, 75)
@export var target_level_path: String = ""  ## Path to target level resource or scene (e.g. res://levels/level_02.tres)
@export var target_entrance_id: String = "start"  ## Matching entrance id on target level
@export var label: String = "To Next Area"
@export var color: Color = Color(0.3, 0.8, 1.0)
@export var is_cave_entrance: bool = false
@export var cave_side: int = 0  ## -1 for left wall, 1 for right wall, 0 for non-wall portal
