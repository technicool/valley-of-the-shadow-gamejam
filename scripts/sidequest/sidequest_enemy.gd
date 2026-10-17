class_name SidequestEnemy
extends CharacterBody2D
## Minimal patrol enemy spawned from a SidequestEnemySpawn marker. Wanders between
## random points within patrol_radius of its spawn position; purely an obstacle for now.

const SPEED := 60.0
const WAIT_TIME := 1.2

var enemy_type: String = "shade"
var patrol_radius: float = 48.0

var _home: Vector2
var _target: Vector2
var _wait_timer := 0.0
var _rng := RandomNumberGenerator.new()

const ENEMY_LAYER := 4


func _ready() -> void:
	add_to_group("sidequest_enemy")
	collision_layer = ENEMY_LAYER
	collision_mask = 2  # Walls.
	_rng.randomize()
	_home = global_position
	_pick_new_target()


func _physics_process(delta: float) -> void:
	if _wait_timer > 0.0:
		_wait_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_target := _target - global_position
	if to_target.length() < 4.0:
		_wait_timer = WAIT_TIME
		_pick_new_target()
		velocity = Vector2.ZERO
	else:
		velocity = to_target.normalized() * SPEED
	move_and_slide()


func _pick_new_target() -> void:
	var offset := Vector2(_rng.randf_range(-patrol_radius, patrol_radius), _rng.randf_range(-patrol_radius, patrol_radius))
	_target = _home + offset
