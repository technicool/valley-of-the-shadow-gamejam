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
const MAX_STAFF_ORBS := 12
const STAFF_HALO_OFFSET := Vector3(0.58, 2.08, -0.06)

@export var stone_speed: float = 25.0
@export var slingshot_cooldown: float = 0.5

@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var shepherd_model: Node3D = $Shepherd
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
var _staff_halo_root: Node3D
var _staff_halo_light: OmniLight3D
var _staff_orbs: Array[Node3D] = []
var _orb_velocities: Array[Vector3] = []
var _orb_phases: PackedFloat32Array = PackedFloat32Array()
var _orb_radii: PackedFloat32Array = PackedFloat32Array()
var _orb_speeds: PackedFloat32Array = PackedFloat32Array()
var _active_orb_count: int = MAX_STAFF_ORBS
var _halo_time: float = 0.0

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
	_setup_staff_orb_halo()
	PlayerStats.health_changed.connect(_on_health_changed_update_orbs)
	_on_health_changed_update_orbs(PlayerStats.health, PlayerStats.max_health)


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
	_update_staff_orb_halo(delta)


func _setup_staff_orb_halo() -> void:
	_staff_halo_root = Node3D.new()
	_staff_halo_root.name = "StaffOrbHalo"
	_staff_halo_root.position = STAFF_HALO_OFFSET
	if shepherd_model != null:
		shepherd_model.add_child(_staff_halo_root)
	else:
		add_child(_staff_halo_root)

	# Warm path illumination light centered in the halo above the shepherd's staff
	_staff_halo_light = OmniLight3D.new()
	_staff_halo_light.name = "StaffHaloWarmLight"
	_staff_halo_light.light_color = Color(1.0, 0.84, 0.58)
	_staff_halo_light.light_energy = 2.6
	_staff_halo_light.omni_range = 13.0
	_staff_halo_light.omni_attenuation = 1.15
	_staff_halo_root.add_child(_staff_halo_light)

	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.048
	orb_mesh.height = 0.096
	orb_mesh.radial_segments = 12
	orb_mesh.rings = 6

	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.095
	glow_mesh.height = 0.19
	glow_mesh.radial_segments = 10
	glow_mesh.rings = 5

	var orb_mat := StandardMaterial3D.new()
	orb_mat.albedo_color = Color(1.0, 0.94, 0.76)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.82, 0.48)
	orb_mat.emission_energy_multiplier = 4.2
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.85, 0.52, 0.32)
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.78, 0.42)
	glow_mat.emission_energy_multiplier = 2.0
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_staff_orbs.clear()
	_orb_velocities.clear()
	_orb_phases.resize(MAX_STAFF_ORBS)
	_orb_radii.resize(MAX_STAFF_ORBS)
	_orb_speeds.resize(MAX_STAFF_ORBS)

	for i in range(MAX_STAFF_ORBS):
		var orb_node := Node3D.new()
		orb_node.name = "LightOrb_%d" % i

		var core := MeshInstance3D.new()
		core.mesh = orb_mesh
		core.material_override = orb_mat
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb_node.add_child(core)

		var halo_glow := MeshInstance3D.new()
		halo_glow.mesh = glow_mesh
		halo_glow.material_override = glow_mat
		halo_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb_node.add_child(halo_glow)

		# Give every 3rd orb a small secondary warm point light to cast dancing warm highlights on the ground
		if i % 3 == 0:
			var sub_light := OmniLight3D.new()
			sub_light.light_color = Color(1.0, 0.82, 0.54)
			sub_light.light_energy = 0.55
			sub_light.omni_range = 6.5
			orb_node.add_child(sub_light)

		var phase := float(i) * (TAU / float(MAX_STAFF_ORBS))
		var radius := 0.28 + float(i % 3) * 0.08
		_orb_phases[i] = phase
		_orb_radii[i] = radius
		_orb_speeds[i] = 2.1 + float(i % 4) * 0.32
		orb_node.position = Vector3(cos(phase) * radius, sin(phase * 2.0) * 0.08, sin(phase) * radius)
		_staff_halo_root.add_child(orb_node)
		_staff_orbs.append(orb_node)
		_orb_velocities.append(Vector3(-sin(phase), 0.0, cos(phase)) * 0.8)


func _on_health_changed_update_orbs(cur_health: int, max_hp: int) -> void:
	var ratio := clampf(float(cur_health) / float(maxi(1, max_hp)), 0.0, 1.0)
	if cur_health <= 0:
		_active_orb_count = 0
	else:
		_active_orb_count = clampi(int( round(ratio * float(MAX_STAFF_ORBS)) ), 1, MAX_STAFF_ORBS)
	for i in range(_staff_orbs.size()):
		_staff_orbs[i].visible = i < _active_orb_count
	if _staff_halo_light != null:
		var light_factor := float(_active_orb_count) / float(MAX_STAFF_ORBS)
		_staff_halo_light.light_energy = lerpf(0.25, 2.8, light_factor)
		_staff_halo_light.omni_range = lerpf(4.5, 13.5, light_factor)


func _update_staff_orb_halo(delta: float) -> void:
	if _staff_halo_root == null or _staff_orbs.is_empty():
		return
	_halo_time += delta
	var active := maxi(1, _active_orb_count)

	# Compute flock centroid of active orbs
	var centroid := Vector3.ZERO
	for i in range(active):
		centroid += _staff_orbs[i].position
	centroid /= float(active)

	for i in range(active):
		var orb := _staff_orbs[i]
		var pos := orb.position
		var vel := _orb_velocities[i]
		var angle := _orb_phases[i] + _halo_time * _orb_speeds[i]
		var r := _orb_radii[i] + sin(_halo_time * 1.7 + float(i)) * 0.05

		# Target circular halo orbit with gentle vertical bobbing
		var orbit_target := Vector3(
			cos(angle) * r,
			sin(_halo_time * 2.6 + float(i) * 0.9) * 0.11 + cos(_halo_time * 1.3 + float(i)) * 0.04,
			sin(angle) * r
		)
		var accel := (orbit_target - pos) * 9.5

		# Flocking cohesion toward halo ring & separation from neighboring orbs
		accel += (centroid - pos) * 1.2
		for j in range(active):
			if i == j:
				continue
			var diff := pos - _staff_orbs[j].position
			var d_sq := diff.length_squared()
			if d_sq > 0.0001 and d_sq < 0.045:
				accel += diff.normalized() * (0.045 - d_sq) * 28.0

		vel = (vel + accel * delta). move_toward(Vector3.ZERO, 3.2 * delta)
		if vel.length() > 2.4:
			vel = vel.normalized() * 2.4
		pos += vel * delta
		orb.position = pos
		_orb_velocities[i] = vel


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
