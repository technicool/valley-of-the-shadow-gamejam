extends Node3D
## Places the player at the start of the road and marks the far end with a beacon.

@onready var terrain: BlockTerrain = $Terrain
@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	player.global_position = terrain.get_spawn_position()
	_add_beacon(terrain.get_goal_position())


func _add_beacon(at: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.3, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.35, 0.95)
	mat.emission_energy_multiplier = 2.0

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.2
	cylinder.bottom_radius = 0.3
	cylinder.height = 14.0

	var beam := MeshInstance3D.new()
	beam.mesh = cylinder
	beam.material_override = mat
	beam.position = at + Vector3(0.0, 7.0, 0.0)
	add_child(beam)

	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.45, 1.0)
	light.light_energy = 2.0
	light.omni_range = 12.0
	light.position = at + Vector3(0.0, 2.0, 0.0)
	add_child(light)
