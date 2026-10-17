extends Node
## Autoload singleton that routes travel between the main 3D level and 2D sidequest maps.
##
## Main level exits point here via a "sidequest://<name_or_random>" target_level_path.
## Sidequest exits point back here either to return to the main level or to jump to
## another named sidequest scene.

const SIDEQUEST_PREFIX := "sidequest://"
const RANDOM_KEYWORD := "random"

## Registry of sidequest name -> scene path. Add new example maps here.
const SIDEQUEST_SCENES := {
	"ruins": "res://scenes/sidequests/sidequest_ruins.tscn",
	"crypt": "res://scenes/sidequests/sidequest_crypt.tscn",
	"grove": "res://scenes/sidequests/sidequest_grove.tscn",
}

## Emitted when the world should swap to a sidequest scene. The Game shell handles it.
signal sidequest_requested(scene_path: String)
## Emitted when the player should return to the main level at the given entrance.
signal main_requested(entrance_id: String)

var _return_entrance_id: String = "start"
var _pending_entrance_id: String = ""

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


static func is_sidequest_target(target_level_path: String) -> bool:
	return target_level_path.begins_with(SIDEQUEST_PREFIX)


## Called from the main Level when a sidequest exit portal is triggered.
func enter_sidequest(target_level_path: String, return_entrance_id: String) -> void:
	var requested := target_level_path.substr(SIDEQUEST_PREFIX.length())
	var scene_path := resolve_sidequest_path(requested)
	if scene_path.is_empty():
		push_warning("SidequestManager: no sidequest scenes registered, staying on main level.")
		return
	_return_entrance_id = return_entrance_id
	_pending_entrance_id = "start"
	sidequest_requested.emit(scene_path)


## Called from an ExitNode inside a sidequest scene.
func exit_to_main() -> void:
	main_requested.emit(_return_entrance_id)


func exit_to_sidequest(sidequest_name: String, target_entrance_id: String) -> void:
	var scene_path := resolve_sidequest_path(sidequest_name)
	if scene_path.is_empty():
		push_warning("SidequestManager: unknown sidequest '%s', returning to main instead." % sidequest_name)
		exit_to_main()
		return
	_pending_entrance_id = target_entrance_id
	sidequest_requested.emit(scene_path)


## Resolves "random" (optionally excluding the current scene) or an explicit registered name.
func resolve_sidequest_path(name_or_random: String) -> String:
	if name_or_random == RANDOM_KEYWORD or name_or_random.is_empty():
		var keys: Array = SIDEQUEST_SCENES.keys()
		if keys.is_empty():
			return ""
		return SIDEQUEST_SCENES[keys[_rng.randi_range(0, keys.size() - 1)]]
	return SIDEQUEST_SCENES.get(name_or_random, "")


## Consumed once by the next scene's _ready(). Returns "" if nothing is pending.
func consume_pending_entrance_id() -> String:
	var id := _pending_entrance_id
	_pending_entrance_id = ""
	return id
