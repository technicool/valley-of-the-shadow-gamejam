extends CharacterBody3D
## Third-person capsule controller with mouse look and automatic step-up for block terrain.

const WALK_SPEED := 5.0
const ACCELERATION := 25.0
const JUMP_VELOCITY := 5.0
const STEP_HEIGHT := 0.6
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.25
const PITCH_MAX := 0.35

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch := -0.35


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.rotation.x = _pitch


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-motion.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
		spring_arm.rotation.x = _pitch
		return

	var click := event as InputEventMouseButton
	if click and click.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera_pivot.global_transform.basis * Vector3(input.x, 0.0, input.y)
	var target := direction * WALK_SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)

	var horizontal := Vector3(velocity.x, 0.0, velocity.z) * delta
	if is_on_floor() and horizontal.length_squared() > 0.0001 and test_move(global_transform, horizontal):
		_try_step_up(horizontal)
	move_and_slide()


func _try_step_up(horizontal: Vector3) -> void:
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(global_transform, up):
		return
	var raised := Transform3D(global_transform.basis, global_transform.origin + up)
	if test_move(raised, horizontal):
		return
	global_position += up
