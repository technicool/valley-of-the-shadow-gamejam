class_name MeleeWeapon
extends Area3D
## Melee hit box on the player. A swing strikes each enemy in reach once, then goes on cooldown.

signal enemy_struck(enemy: Node3D)

const CHEST_HEIGHT := 0.9

@export var swing_window: float = 0.25
@export var hit_width: float = 1.2
@export var hit_height: float = 1.6
@export var sword_reach: float = 2.0
@export var sword_cooldown: float = 0.9
@export var dagger_reach: float = 1.2
@export var dagger_cooldown: float = 0.4

@onready var _hitbox: CollisionShape3D = $Hitbox

var _box := BoxShape3D.new()
var _window_left := 0.0
var _cooldown_left := 0.0
var _struck: Array[Node3D] = []


func _ready() -> void:
	_hitbox.shape = _box
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _window_left > 0.0:
		_window_left -= delta
		if _window_left <= 0.0:
			monitoring = false


## Starts a swing with the weapon id. Returns false for non-melee weapons or while on cooldown.
func try_swing(weapon_id: String) -> bool:
	if _cooldown_left > 0.0:
		return false
	var reach := 0.0
	match weapon_id:
		"sword":
			reach = sword_reach
			_cooldown_left = sword_cooldown
		"dagger":
			reach = dagger_reach
			_cooldown_left = dagger_cooldown
		_:
			return false
	_box.size = Vector3(hit_width, hit_height, reach)
	position = Vector3(0.0, CHEST_HEIGHT, -reach * 0.5)
	_struck.clear()
	_window_left = swing_window
	monitoring = true
	return true


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemy") and not _struck.has(body):
		_struck.append(body)
		enemy_struck.emit(body)
