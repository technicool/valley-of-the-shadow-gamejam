class_name WeaponPickup
extends Area3D
## Collectible weapon element. Spins and bobs; equips the player once when touched, shows its
## scripture banner, then removes itself.

@export var weapon_id: String = "sword"
@export var display_name: String = "Sword"
@export var damage: int = 10
@export var is_ranged: bool = false
@export var scripture_quote: String = ""
@export var scripture_reference: String = ""
@export var suggestion: String = ""

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
	PlayerEquipment.equip(weapon_id)
	get_tree().call_group("hud", "show_message", scripture_quote, scripture_reference, suggestion)
	queue_free()
