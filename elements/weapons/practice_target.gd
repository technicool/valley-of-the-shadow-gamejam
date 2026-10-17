extends StaticBody3D
## Target practice bullseye in the opening meadow.
## Added to group "enemy" so StoneProjectile strikes trigger die() via Player._on_enemy_struck.

var _pivot: Node3D
var _is_hit := false


func setup(pivot: Node3D) -> void:
	_pivot = pivot
	add_to_group("enemy")
	add_to_group("practice_target")


func die() -> void:
	if _is_hit:
		return
	_is_hit = true
	if _pivot and is_instance_valid(_pivot):
		var tw := create_tween()
		tw.tween_property(_pivot, "rotation:x", -PI * 0.44, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(1.2)
		tw.tween_property(_pivot, "rotation:x", 0.0, 0.28).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): _is_hit = false)
	else:
		_is_hit = false
