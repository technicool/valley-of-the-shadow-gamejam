class_name TerrainTile
extends StaticBody3D
## Standard 2 m x 2 m terrain block. The walkable top surface sits at y = 0.
## Rock walls extend above it.

const FOOTPRINT := 2.0

@export var terrain_type: String = "grass"


func _ready() -> void:
	add_to_group("terrain")
