class_name ExitNode
extends Area3D
## Exit portal element. Leads to the valley when target_sidequest is empty,
## otherwise to the named sidequest scene at target_entrance_id.

@export var target_sidequest: String = ""
@export var target_entrance_id: String = "start"
@export var label: String = "Return to the Valley"
@export var color: Color = Color(0.3, 0.8, 1.0, 1.0)

@onready var _pad: MeshInstance3D = $Pad
@onready var _beacon: MeshInstance3D = $Beacon
@onready var _light: OmniLight3D = $Light
@onready var _label: Label3D = $Label

var _triggered := false


func _ready() -> void:
	add_to_group("exit")
	body_entered.connect(_on_body_entered)
	_label.text = label
	_light.light_color = color
	_tint(_pad)
	_tint(_beacon)


# Each portal gets its own material copy so tinting one does not affect the others.
func _tint(mesh: MeshInstance3D) -> void:
	var mat := (mesh.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = color
	mat.emission = color
	mesh.material_override = mat


func _on_body_entered(body: Node3D) -> void:
	if _triggered or not body.is_in_group("player"):
		return
	_triggered = true
	_travel.call_deferred()


func _travel() -> void:
	if target_sidequest.is_empty():
		SidequestManager.exit_to_main()
	else:
		SidequestManager.exit_to_sidequest(target_sidequest, target_entrance_id)
