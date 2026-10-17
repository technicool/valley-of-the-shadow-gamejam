extends CharacterBody3D
## Third-person capsule controller with mouse look and automatic step-up for block terrain.

signal enemy_struck(enemy: Node3D)

const WALK_SPEED := 5.0
const ACCELERATION := 25.0
const STEP_HEIGHT := 0.6
const MOUSE_SENSITIVITY := 0.003
const PITCH_MIN := -1.25
const PITCH_MAX := 0.35
const STONE_SCENE := preload("res://elements/weapons/stone_projectile.tscn")

@export var stone_speed: float = 25.0
@export var slingshot_cooldown: float = 0.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var left_hand: Node3D = $Shepherd/LeftHand
@onready var held_weapons: Dictionary = {
	"sword": $Shepherd/LeftHand/HeldSword,
	"dagger": $Shepherd/LeftHand/HeldDagger,
	"slingshot": $Shepherd/LeftHand/HeldSlingshot,
}
@onready var hip_sword: Node3D = $Shepherd/Sword
@onready var melee: MeleeWeapon = $MeleeWeapon

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch := -0.35
var _stone_cooldown_left := 0.0

## Health is owned by PlayerStats. The player reads it live and changes it only through there.
var health: int:
	get:
		return PlayerStats.health


func take_damage(amount: int) -> void:
	PlayerStats.take_damage(amount)


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	spring_arm.rotation.x = _pitch
	PlayerEquipment.changed.connect(_show_held_weapon)
	_show_held_weapon(PlayerEquipment.equipped_weapon_id)
	melee.enemy_struck.connect(_on_enemy_struck)


func _show_held_weapon(weapon_id: String) -> void:
	for id in held_weapons:
		held_weapons[id].visible = id == weapon_id
	hip_sword.visible = weapon_id != "sword"


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
	_stone_cooldown_left = maxf(_stone_cooldown_left - delta, 0.0)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("attack"):
		if PlayerEquipment.equipped_weapon_id == "slingshot":
			_fire_stone()
		else:
			melee.try_swing(PlayerEquipment.equipped_weapon_id)

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


func _fire_stone() -> void:
	if _stone_cooldown_left > 0.0:
		return
	_stone_cooldown_left = slingshot_cooldown
	var stone := STONE_SCENE.instantiate() as StoneProjectile
	get_parent().add_child(stone)
	stone.global_position = left_hand.global_position
	stone.launch(-camera.global_transform.basis.z * stone_speed)
	stone.enemy_struck.connect(_on_enemy_struck)


func _on_enemy_struck(enemy: Node3D) -> void:
	enemy_struck.emit(enemy)
	if enemy.has_method("die"):
		enemy.call("die")
