extends Node
## Autoload holding the player's equipped weapon. Not part of any scene, so it survives scene changes.

signal changed(weapon_id: String)

## Empty string means unarmed.
var equipped_weapon_id: String = ""


## Replaces the current weapon. Emits changed only when the id differs.
func equip(weapon_id: String) -> void:
	if weapon_id == equipped_weapon_id:
		return
	equipped_weapon_id = weapon_id
	changed.emit(weapon_id)
