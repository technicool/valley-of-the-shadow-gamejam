class_name EnemyCreature
extends CharacterBody3D
## Creature element that wanders near its spawn point and chases the player inside detect_range.
## Collider and visuals live in each creature scene; tuning values are exported per creature.

@export var creature_name: String = "Creature"
@export var max_health: int = 20
@export var attack_damage: int = 5
@export var wander_speed: float = 1.5
@export var chase_speed: float = 3.0
@export var detect_range: float = 10.0
@export var wander_radius: float = 5.0

const WAIT_TIME := 1.5
const ARRIVE_DISTANCE := 0.3

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("enemy")
	_home = global_position
	_rng.randomize()
	_pick_wander_target()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var chasing := player != null and global_position.distance_to(player.global_position) <= detect_range
	var direction := Vector3.ZERO
	var speed := wander_speed

	if chasing:
		direction = player.global_position - global_position
		speed = chase_speed
	elif _wait_timer > 0.0:
		_wait_timer -= delta
	else:
		direction = _target - global_position
		if direction.length() < ARRIVE_DISTANCE or is_on_wall():
			_wait_timer = WAIT_TIME
			_pick_wander_target()
			direction = Vector3.ZERO

	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
		rotation.y = atan2(-direction.x, -direction.z)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()


func _pick_wander_target() -> void:
	var offset := Vector3(
		_rng.randf_range(-wander_radius, wander_radius),
		0.0,
		_rng.randf_range(-wander_radius, wander_radius))
	_target = _home + offset
