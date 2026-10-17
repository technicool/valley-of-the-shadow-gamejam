class_name SidequestLevel3D
extends Node3D
## Builds a 3D sidequest map from a text layout by spawning the reusable elements in
## res://elements/. Each character is one 2 m cell; cell (col, row) sits at
## world x = col * 2, z = row * 2.
##
## Glyphs:
##   #        rocky wall (no ground beneath it)
##   .        grass
##   ~        mud
##   space    empty, nothing spawned
##   S        spawn point "start" (where the player arrives)
##   X        exit to the valley (exit_links["X"] can override it)
##   1-9      sidequest exits, configured in exit_links
##   s        sword
##   d        dagger
##   Y        slingshot
##   w        wolf
##   b        bear
##   G        giant
##
## Every non-wall cell gets grass or mud, and any element on that cell sits on top.
## exit_links maps an exit glyph to {target_sidequest, target_entrance_id, label, color}.
## An empty target_sidequest returns the player to the valley.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const GRASS_SCENE := preload("res://elements/terrain/grass_tile.tscn")
const MUD_SCENE := preload("res://elements/terrain/mud_tile.tscn")
const ROCK_SCENE := preload("res://elements/terrain/rocky_wall.tscn")
const SPAWN_SCENE := preload("res://elements/markers/spawn_point.tscn")
const EXIT_SCENE := preload("res://elements/markers/exit_node.tscn")

const WEAPON_SCENES := {
	"s": preload("res://elements/weapons/sword.tscn"),
	"d": preload("res://elements/weapons/dagger.tscn"),
	"Y": preload("res://elements/weapons/slingshot.tscn"),
}

const ENEMY_SCENES := {
	"w": preload("res://elements/enemies/wolf.tscn"),
	"b": preload("res://elements/enemies/bear.tscn"),
	"G": preload("res://elements/enemies/giant.tscn"),
}

const DEFAULT_EXIT_LABEL := "Return to the Valley"
const DEFAULT_EXIT_COLOR := Color(0.3, 0.8, 1.0, 1.0)
## Lifts the player slightly above the spawn marker so the capsule does not start inside the ground.
const PLAYER_LIFT := 0.5

@export_multiline var layout: String = ""
@export var exit_links: Dictionary = {}

var _spawn_markers: Dictionary = {}


func _ready() -> void:
	if layout.strip_edges().is_empty():
		push_error("SidequestLevel3D: layout is empty.")
		return
	_build_layout()
	_spawn_player()


func _build_layout() -> void:
	var terrain_root := Node3D.new()
	terrain_root.name = "Terrain"
	add_child(terrain_root)
	var elements_root := Node3D.new()
	elements_root.name = "Elements"
	add_child(elements_root)

	var rows := layout.split("\n", false)
	var cell := TerrainTile.FOOTPRINT
	for row_index in rows.size():
		var row: String = rows[row_index]
		if row.length() != rows[0].length():
			push_warning("SidequestLevel3D: row %d is %d cells wide, expected %d." % [row_index, row.length(), rows[0].length()])
		for col in row.length():
			var glyph: String = row.substr(col, 1)
			if glyph == " ":
				continue
			_place_cell(glyph, Vector3(col * cell, 0.0, row_index * cell), terrain_root, elements_root)


func _place_cell(glyph: String, pos: Vector3, terrain_root: Node3D, elements_root: Node3D) -> void:
	if glyph == "#":
		_spawn(ROCK_SCENE, pos, terrain_root)
		return
	_spawn(MUD_SCENE if glyph == "~" else GRASS_SCENE, pos, terrain_root)
	if glyph == "." or glyph == "~":
		return

	if glyph == "S":
		var marker := _spawn(SPAWN_SCENE, pos, elements_root) as SpawnPoint
		_spawn_markers[marker.spawn_id] = marker
	elif glyph == "X" or glyph.is_valid_int():
		_spawn_exit(glyph, pos, elements_root)
	elif WEAPON_SCENES.has(glyph):
		_spawn(WEAPON_SCENES[glyph], pos, elements_root)
	elif ENEMY_SCENES.has(glyph):
		_spawn(ENEMY_SCENES[glyph], pos, elements_root)
	else:
		push_warning("SidequestLevel3D: unknown glyph '%s' at %s." % [glyph, pos])


func _spawn(scene: PackedScene, pos: Vector3, parent: Node3D) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.position = pos
	parent.add_child(node)
	return node


func _spawn_exit(glyph: String, pos: Vector3, parent: Node3D) -> void:
	# Properties are set before add_child so ExitNode._ready() tints and labels with the right values.
	var config: Dictionary = exit_links.get(glyph, {})
	var portal := EXIT_SCENE.instantiate() as ExitNode
	portal.name = "Exit_" + glyph
	portal.position = pos
	portal.target_sidequest = config.get("target_sidequest", "")
	portal.target_entrance_id = config.get("target_entrance_id", "start")
	portal.label = config.get("label", DEFAULT_EXIT_LABEL)
	portal.color = config.get("color", DEFAULT_EXIT_COLOR)
	parent.add_child(portal)


func _spawn_player() -> void:
	var entrance_id: String = SidequestManager.consume_pending_entrance_id()
	if not _spawn_markers.has(entrance_id):
		entrance_id = "start"
	if not _spawn_markers.has(entrance_id):
		push_error("SidequestLevel3D: no spawn point '%s' in layout." % entrance_id)
		return
	var marker: SpawnPoint = _spawn_markers[entrance_id]
	var player := PLAYER_SCENE.instantiate() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	player.global_position = marker.global_position + Vector3(0.0, PLAYER_LIFT, 0.0)
	player.velocity = Vector3.ZERO
