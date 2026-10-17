class_name Lamb
extends CharacterBody3D
## Wandering lamb. Drifts around its home spot while the player is far away,
## loosely trails the player when near, and steers apart from other lambs.

const STEP_HEIGHT := 0.6
const ARRIVE_DISTANCE := 0.4
const SLOW_RADIUS := 1.5
const FOLLOW_ENTER_RANGE := 6.0
const FOLLOW_LEAVE_RANGE := 9.0
const FOLLOW_OFFSET_MIN := 2.0
const FOLLOW_OFFSET_MAX := 3.5
const SEPARATION_RADIUS := 1.4
const SEPARATION_WEIGHT := 1.6
const STUCK_TIME := 1.2
const TURN_SPEED := 6.0

@export var wander_speed := 0.9
@export var follow_speed := 2.6
@export var wander_radius := 7.0
@export var idle_min := 1.5
@export var idle_max := 4.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _wander_target := Vector3.ZERO
var _idle_left := 0.0
var _stuck_left := 0.0
var _following := false
var _follow_offset := Vector3.ZERO


func _ready() -> void:
	add_to_group("lamb")
	_rng.randomize()
	_home = global_position
	_pick_wander_target()


func _physics_process(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var intent := Vector3.ZERO
	var speed := wander_speed
	if player:
		_update_follow_state(player)
	if _following and player:
		intent = _follow_direction(player)
		speed = follow_speed
	else:
		intent = _wander_direction(delta)

	intent += _separation_vector() * SEPARATION_WEIGHT
	intent.y = 0.0
	if intent.length() > 1.0:
		intent = intent.normalized()

	if intent.length_squared() > 0.0001:
		var face := atan2(-intent.x, -intent.z)
		rotation.y = lerp_angle(rotation.y, face, minf(1.0, delta * TURN_SPEED))

	velocity.x = intent.x * speed
	velocity.z = intent.z * speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	if is_on_floor() and horizontal.length_squared() > 0.0001 and test_move(global_transform, horizontal):
		_try_step_up(horizontal)
	move_and_slide()
	_check_stuck(delta, intent)


func _update_follow_state(player: Node3D) -> void:
	var dist := global_position.distance_to(player.global_position)
	if not _following and dist <= FOLLOW_ENTER_RANGE:
		_following = true
		_follow_offset = _random_follow_offset()
	elif _following and dist > FOLLOW_LEAVE_RANGE:
		_following = false
		_home = global_position
		_idle_left = 0.0
		_pick_wander_target()


func _follow_direction(player: Node3D) -> Vector3:
	var goal := player.global_position + _follow_offset
	var to_goal := goal - global_position
	to_goal.y = 0.0
	var dist := to_goal.length()
	if dist < ARRIVE_DISTANCE:
		return Vector3.ZERO
	return to_goal / dist * clampf(dist / SLOW_RADIUS, 0.0, 1.0)


func _wander_direction(delta: float) -> Vector3:
	if _idle_left > 0.0:
		_idle_left -= delta
		return Vector3.ZERO
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() < ARRIVE_DISTANCE or is_on_wall():
		_idle_left = _rng.randf_range(idle_min, idle_max)
		_pick_wander_target()
		return Vector3.ZERO
	return to_target.normalized()


func _separation_vector() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("lamb"):
		var other_lamb := other as Lamb
		if other_lamb == null or other_lamb == self:
			continue
		var away := global_position - other_lamb.global_position
		away.y = 0.0
		var dist := away.length()
		if dist >= SEPARATION_RADIUS:
			continue
		if dist < 0.001:
			push += Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		else:
			push += away / dist * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	return push


func _check_stuck(delta: float, intent: Vector3) -> void:
	if intent.length() > 0.2 and get_real_velocity().length() < 0.1:
		_stuck_left += delta
		if _stuck_left >= STUCK_TIME:
			_stuck_left = 0.0
			if _following:
				_follow_offset = _random_follow_offset()
			else:
				_idle_left = 0.0
				_pick_wander_target()
	else:
		_stuck_left = 0.0


func _pick_wander_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := sqrt(_rng.randf()) * wander_radius
	_wander_target = _home + Vector3(cos(angle), 0.0, sin(angle)) * dist


func _random_follow_offset() -> Vector3:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(FOLLOW_OFFSET_MIN, FOLLOW_OFFSET_MAX)
	return Vector3(cos(angle), 0.0, sin(angle)) * dist


func _try_step_up(horizontal: Vector3) -> void:
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return
	var raised := Transform3D(global_transform.basis, global_transform.origin + up)
	if test_move(raised, horizontal):
		return
	global_position += up
