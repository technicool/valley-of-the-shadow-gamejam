class_name SidequestPlayer
extends CharacterBody2D
## Simple top-down controller for 2D sidequest maps. Reuses the project's existing
## move_forward/move_back/move_left/move_right input actions (forward = up, back = down).

const SPEED := 160.0
const ACCELERATION := 900.0

const PLAYER_LAYER := 1


func _ready() -> void:
	add_to_group("player")
	collision_layer = PLAYER_LAYER
	collision_mask = 2  # Walls.

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	add_child(shape)

	var sprite := Sprite2D.new()
	sprite.texture = SidequestVisuals.make_color_texture(Color(0.85, 0.72, 0.5), 24)
	add_child(sprite)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target := input * SPEED
	velocity = velocity.move_toward(target, ACCELERATION * delta)
	move_and_slide()
