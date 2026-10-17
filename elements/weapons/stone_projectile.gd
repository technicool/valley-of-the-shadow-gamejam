class_name StoneProjectile
extends CharacterBody3D
## Slingshot stone. Flies straight until it hits an enemy or terrain, or times out.

signal enemy_struck(enemy: Node3D)

@export var lifetime: float = 3.0

var _life_left := 0.0


func launch(launch_velocity: Vector3) -> void:
	velocity = launch_velocity
	_life_left = lifetime


func _physics_process(delta: float) -> void:
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var body := collision.get_collider() as Node3D
	if body and body.is_in_group("enemy"):
		enemy_struck.emit(body)
	queue_free()
