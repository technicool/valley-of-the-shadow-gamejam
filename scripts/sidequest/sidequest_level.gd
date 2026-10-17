@tool
class_name SidequestLevel
extends Node2D
## Root controller for a 2D sidequest TileMapLayer scene.
##
## Place a TileMapLayer named "Terrain" as a child and paint it in the editor (the tileset
## is auto-created on load). Add SidequestEntrance / SidequestExit / SidequestEnemySpawn /
## SidequestWeaponSpawn / SidequestLootSpawn nodes anywhere in the scene tree to define
## spawn points, exits, enemies, weapons, and loot.

const TILE_SIZE := 32
const CELL_FLOOR := 0
const CELL_WALL := 1
const CELL_WATER := 2
const CELL_RUBBLE := 3

const PLAYER_SCENE := preload("res://scenes/sidequests/sidequest_player.tscn")

@export_group("Default Room Autofill")
## Only used to seed a starter layout the first time the scene is opened (an empty TileMapLayer).
## Paint over it by hand afterward; a non-empty layer is never touched again.
@export var room_width: int = 20
@export var room_depth: int = 14
@export var accent_terrain: int = CELL_WATER
@export var accent_density: float = 0.06
@export var autofill_seed: int = 1

@onready var _terrain: TileMapLayer = get_node_or_null("Terrain") as TileMapLayer

var _player: SidequestPlayer


func _ready() -> void:
	_ensure_tileset()
	if _terrain and _terrain.get_used_cells().is_empty():
		_autofill_room()
	if Engine.is_editor_hint():
		return
	_spawn_player()
	_spawn_enemies()
	_spawn_pickups()


## Starter layout: wall border, floor interior, scattered accent tiles. Only runs on an
## empty layer, so hand-painted edits are never overwritten.
func _autofill_room() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = autofill_seed
	for y in range(room_depth):
		for x in range(room_width):
			var is_border := x == 0 or y == 0 or x == room_width - 1 or y == room_depth - 1
			var cell := CELL_WALL
			if not is_border:
				cell = accent_terrain if rng.randf() < accent_density else CELL_FLOOR
			_terrain.set_cell(Vector2i(x, y), 0, Vector2i(cell, 0))


func _spawn_player() -> void:
	var entrance_id := SidequestManager.consume_pending_entrance_id()
	if entrance_id.is_empty():
		entrance_id = "start"
	var spawn_pos := _find_entrance_pos(entrance_id)
	_player = PLAYER_SCENE.instantiate() as SidequestPlayer
	_player.global_position = spawn_pos
	add_child(_player)

	var cam := Camera2D.new()
	cam.zoom = Vector2(2.0, 2.0)
	cam.position_smoothing_enabled = true
	_player.add_child(cam)


func _find_entrance_pos(entrance_id: String) -> Vector2:
	for node in get_tree().get_nodes_in_group("sidequest_entrance"):
		var entrance := node as SidequestEntrance
		if entrance and is_ancestor_of(entrance) and entrance.id == entrance_id:
			return entrance.global_position
	# Fall back to any entrance so a bad id never strands the player off-map.
	for node in get_tree().get_nodes_in_group("sidequest_entrance"):
		var entrance := node as SidequestEntrance
		if entrance and is_ancestor_of(entrance):
			return entrance.global_position
	return Vector2.ZERO


func _spawn_enemies() -> void:
	for node in get_tree().get_nodes_in_group("sidequest_enemy_spawn"):
		var spawn := node as SidequestEnemySpawn
		if not spawn or not is_ancestor_of(spawn):
			continue
		var enemy := SidequestEnemy.new()
		enemy.enemy_type = spawn.enemy_type
		enemy.patrol_radius = spawn.patrol_radius
		enemy.global_position = spawn.global_position
		add_child(enemy)
		_build_enemy_visual(enemy)


func _build_enemy_visual(enemy: SidequestEnemy) -> void:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	enemy.add_child(shape)

	var sprite := Sprite2D.new()
	sprite.texture = SidequestVisuals.make_color_texture(Color(0.85, 0.15, 0.15), 24)
	enemy.add_child(sprite)


func _spawn_pickups() -> void:
	for node in get_tree().get_nodes_in_group("sidequest_weapon_spawn"):
		var spawn := node as SidequestWeaponSpawn
		if spawn and is_ancestor_of(spawn):
			_build_pickup(spawn.global_position, spawn.weapon_type, spawn.respawn, Color(1.0, 0.85, 0.3))
	for node in get_tree().get_nodes_in_group("sidequest_loot_spawn"):
		var spawn := node as SidequestLootSpawn
		if spawn and is_ancestor_of(spawn):
			_build_pickup(spawn.global_position, spawn.loot_type, false, Color(0.3, 0.6, 1.0))


func _build_pickup(pos: Vector2, pickup_type: String, respawn: bool, color: Color) -> void:
	var pickup := SidequestPickup.new()
	pickup.pickup_type = pickup_type
	pickup.respawn = respawn
	pickup.global_position = pos
	add_child(pickup)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	pickup.add_child(shape)

	var sprite := Sprite2D.new()
	sprite.texture = SidequestVisuals.make_color_texture(color, 16)
	pickup.add_child(sprite)


## Builds the shared placeholder tileset the first time a sidequest scene is opened or run.
## WALL tiles get real collision so painting walls in the editor blocks the player at runtime.
func _ensure_tileset() -> void:
	if not _terrain or _terrain.tile_set != null:
		return

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 1)

	var colors := [
		Color("#6b5a3c"), # Floor
		Color("#4a4a52"), # Wall
		Color("#2a5f8a"), # Water
		Color("#7a7366"), # Rubble
	]
	var source := TileSetAtlasSource.new()
	var img := Image.create(TILE_SIZE * colors.size(), TILE_SIZE, false, Image.FORMAT_RGBA8)
	for idx in colors.size():
		var c: Color = colors[idx]
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				img.set_pixel(idx * TILE_SIZE + px, py, c)
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for idx in colors.size():
		source.create_tile(Vector2i(idx, 0))
	ts.add_source(source)

	var wall_data := source.get_tile_data(Vector2i(CELL_WALL, 0), 0)
	var half := TILE_SIZE * 0.5
	var polygon := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)
	])
	wall_data.add_collision_polygon(0)
	wall_data.set_collision_polygon_points(0, 0, polygon)

	_terrain.tile_set = ts
