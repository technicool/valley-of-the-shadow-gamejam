class_name WeaponPickup
extends Area3D
## Collectible weapon element. Spins and bobs; emits collected once when the player touches it.

signal collected(weapon_id: String)

@export var weapon_id: String = "sword"
@export var display_name: String = "Sword"
@export var damage: int = 10
@export var is_ranged: bool = false

const SPIN_SPEED := 1.5
const BOB_HEIGHT := 0.12
const BOB_RATE := 2.0

@onready var _visual: Node3D = $Visual

var _base_height := 0.0
var _elapsed := 0.0
var _collected := false


func _ready() -> void:
	add_to_group("weapon_pickup")
	_base_height = _visual.position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_elapsed += delta
	_visual.rotate_y(SPIN_SPEED * delta)
	_visual.position.y = _base_height + sin(_elapsed * BOB_RATE) * BOB_HEIGHT


func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	_collected = true
	collected.emit(weapon_id)
	queue_free()
