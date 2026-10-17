@tool
class_name LevelMapPopulator
extends Node3D
## Level Populator and Editor Tool for Godot.
##
## Syncs a 2D TileMapLayer (used in editor for painting terrain, debris, and objects)
## with the 3D game world and LevelData resource.
## Also builds the procedural 3D block terrain, spawns static scenery (trees, rocks, debris),
## places weapon pickups, and instantiates enemy guard zones with barrier gates.

signal level_exit_triggered(exit_id: String, target_level_path: String, target_entrance_id: String)

const PLAYER_LAYER := 2  # Matches collision_layer in scenes/player.tscn.
const WEAPON_SCENES := {
	"ancient_blade": preload("res://elements/weapons/sword.tscn"),
	"greatsword": preload("res://elements/weapons/sword.tscn"),
	"shadow_dagger": preload("res://elements/weapons/dagger.tscn"),
	"sun_pendant": preload("res://elements/weapons/slingshot.tscn"),
}
const GUARD_CREATURE_SCENES: Array[PackedScene] = [
	preload("res://elements/enemies/shadow_creature.tscn"),
	preload("res://elements/enemies/wolf.tscn"),
	preload("res://elements/enemies/bear.tscn"),
]
const LAMB_SCENE := preload("res://elements/npcs/lamb.tscn")
const LAMB_COUNT := 6
const LAMB_MIN_SPACING := 3.0
const LAMB_MIN_START_DIST := 4.0
const LAMB_MAX_START_DIST := 16.0
const LAMB_GUARD_CLEARANCE := 8.0

@export_group("Data & Generation")
@export var level_data: LevelData:
	set(val):
		level_data = val
		if Engine.is_editor_hint() and level_data:
			sync_to_tilemap()

@export var generation_mode: LevelMapGenerator.GenerationMode = LevelMapGenerator.GenerationMode.LINEAR_PATH
@export var world_seed: int = 1337
@export var section_index: int = 0
@export var section_length: int = 50
@export var auto_rebuild_on_ready: bool = true

@export_group("Editor Actions")
@export var generate_level_button: bool = false:
	set(_v):
		generate_level_data()

@export var rebuild_3d_world_button: bool = false:
	set(_v):
		rebuild_all()

@export var sync_from_tilemap_button: bool = false:
	set(_v):
		sync_from_tilemap()
		rebuild_all()

@export_group("Scenery Prefabs / Meshes")
@export var weapon_item_scene: PackedScene
@export var enemy_guard_scene: PackedScene

# Internal node references
var _terrain_node: Node3D
var _props_node: Node3D
var _gameplay_node: Node3D
var _tilemap_layer: TileMapLayer


func _ready() -> void:
	_ensure_subnodes()
	if level_data == null:
		generate_level_data()
		return
	# Only fill an empty paint layer so saved paint is not overwritten.
	if Engine.is_editor_hint() and _tilemap_layer and _tilemap_layer.get_used_cells().is_empty():
		sync_to_tilemap()
	if auto_rebuild_on_ready:
		rebuild_all()


func _ensure_subnodes() -> void:
	if not _tilemap_layer:
		_tilemap_layer = get_node_or_null("TerrainTileMap") as TileMapLayer
		if not _tilemap_layer and Engine.is_editor_hint():
			_tilemap_layer = TileMapLayer.new()
			_tilemap_layer.name = "TerrainTileMap"
			add_child(_tilemap_layer)
			_tilemap_layer.owner = get_tree().edited_scene_root
	# A 2D layer would draw over the 3D view at runtime.
	if _tilemap_layer and not Engine.is_editor_hint():
		_tilemap_layer.visible = false

	if not _terrain_node:
		_terrain_node = _get_or_add_container("GeneratedTerrain")
	if not _props_node:
		_props_node = _get_or_add_container("GeneratedProps")
	if not _gameplay_node:
		_gameplay_node = _get_or_add_container("GeneratedGameplay")


func _get_or_add_container(container_name: String) -> Node3D:
	var container := get_node_or_null(container_name) as Node3D
	if not container:
		container = Node3D.new()
		container.name = container_name
		add_child(container)
	return container


## Generate LevelData procedurally using FastNoiseLite and current mode
func generate_level_data() -> void:
	_ensure_subnodes()
	var gen := LevelMapGenerator.new()
	var w := 80
	var d := section_length
	if level_data:
		w = level_data.width
		d = level_data.depth
	level_data = gen.generate(generation_mode, world_seed, w, d, section_index)
	sync_to_tilemap()
	rebuild_all()


## Sync LevelData into 2D TileMapLayer for visual inspection/editing in Godot editor
func sync_to_tilemap() -> void:
	if not _tilemap_layer or not level_data:
		return
	_ensure_tileset()
	_tilemap_layer.clear()

	for y in range(level_data.depth):
		for x in range(level_data.width):
			var terrain := level_data.get_cell_terrain(x, y)
			# Atlas coordinate maps to terrain type
			_tilemap_layer.set_cell(Vector2i(x, y), 0, Vector2i(terrain, 0))


## Read changes painted by designer in TileMapLayer back into LevelData
func sync_from_tilemap() -> void:
	if not _tilemap_layer or not level_data:
		return
	for y in range(level_data.depth):
		for x in range(level_data.width):
			var atlas_coord := _tilemap_layer.get_cell_atlas_coords(Vector2i(x, y))
			if atlas_coord != Vector2i(-1, -1):
				level_data.set_cell_terrain(x, y, atlas_coord.x)


func _ensure_tileset() -> void:
	if _tilemap_layer.tile_set != null:
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var source := TileSetAtlasSource.new()
	var img := Image.create(16 * 6, 16, false, Image.FORMAT_RGBA8)
	var colors := [
		Color("#6f7a3b"), # Grass (olive moss)
		Color("#4a3828"), # Mud
		Color("#8c7152"), # Debris
		Color("#a57048"), # Dirt (ochre)
		Color("#7f766c"), # Stone
		Color("#3d5a70"), # Water
	]
	for idx in range(colors.size()):
		var c: Color = colors[idx]
		for py in range(16):
			for px in range(16):
				img.set_pixel(idx * 16 + px, py, c)
	var tex := ImageTexture.create_from_image(img)
	source.texture = tex
	source.texture_region_size = Vector2i(16, 16)
	for idx in range(6):
		source.create_tile(Vector2i(idx, 0))
	ts.add_source(source)
	_tilemap_layer.tile_set = ts


## Rebuilds the entire 3D level: terrain geometry, static scenery, weapons, enemies, and exits
func rebuild_all() -> void:
	_ensure_subnodes()
	if level_data == null:
		return
	_build_3d_terrain()
	_populate_static_objects()
	_populate_gameplay_elements()


func _clear_children(node: Node) -> void:
	# Detach immediately so stale colliders are gone before the rebuild.
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Builds the 3D block mesh with stepped heights and custom terrain textures
func _build_3d_terrain() -> void:
	_clear_children(_terrain_node)
	var w := level_data.width
	var d := level_data.depth
	var step_h := level_data.step_height
	var block_size := level_data.cell_size
	var half_w := w * 0.5 * block_size
	var half_d := d * 0.5 * block_size

	var num_types := 6
	var tools: Array[SurfaceTool] = []
	for i in num_types:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)

	var side_normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var side_offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	for y in range(d):
		for x in range(w):
			var t_type := clampi(level_data.get_cell_terrain(x, y), 0, num_types - 1)
			var elev := level_data.get_cell_elevation(x, y)
			var top_y := elev * step_h
			var center := Vector3((x + 0.5) * block_size - half_w, top_y, (y + 0.5) * block_size - half_d)
			var st: SurfaceTool = tools[t_type]
			var shade := rng.randf_range(0.9, 1.05)

			# Top quad
			var half := block_size * 0.5
			var corners := PackedVector3Array([
				Vector3(center.x - half, center.y, center.z - half),
				Vector3(center.x + half, center.y, center.z - half),
				Vector3(center.x + half, center.y, center.z + half),
				Vector3(center.x - half, center.y, center.z + half),
			])
			_add_quad_to_tool(st, corners, Vector3.UP, Color(shade, shade, shade), 1.0)

			# Side quads
			for s in side_normals.size():
				var offset: Vector2i = side_offsets[s]
				var nx := x + offset.x
				var ny := y + offset.y
				var neighbor_elev := 0
				if nx >= 0 and nx < w and ny >= 0 and ny < d:
					neighbor_elev = level_data.get_cell_elevation(nx, ny)
				elif nx >= 0 and nx < w and (ny < 0 or ny >= d):
					neighbor_elev = elev
				var neighbor_top := neighbor_elev * step_h
				if neighbor_top < top_y:
					var normal: Vector3 = side_normals[s]
					var along := Vector3(-normal.z, 0.0, normal.x) * half
					var edge := Vector3(center.x, 0.0, center.z) + normal * half
					var lo := edge + Vector3(0.0, neighbor_top, 0.0)
					var hi := edge + Vector3(0.0, top_y, 0.0)
					var side_corners := PackedVector3Array([lo - along, lo + along, hi + along, hi - along])
					_add_quad_to_tool(st, side_corners, normal, Color(shade * 0.8, shade * 0.8, shade * 0.8), top_y - neighbor_top)

	var mesh := ArrayMesh.new()
	var colors := [
		Color("#6f7a3b"), Color("#4a3828"), Color("#8c7152"),
		Color("#a57048"), Color("#7f766c"), Color("#3d5a70")
	]
	var surface_idx := 0
	for i in num_types:
		var initial_surf_count := mesh.get_surface_count()
		tools[i].commit(mesh)
		if mesh.get_surface_count() > initial_surf_count:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = colors[i]
			mat.roughness = 0.85
			mesh.surface_set_material(surface_idx, mat)
			surface_idx += 1

	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var col := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape()
	trimesh.backface_collision = true
	col.shape = trimesh
	body.add_child(col)
	_terrain_node.add_child(body)

	var visual := MeshInstance3D.new()
	visual.name = "TerrainMeshInstance"
	visual.mesh = mesh
	_terrain_node.add_child(visual)


func _add_quad_to_tool(st: SurfaceTool, corners: PackedVector3Array, normal: Vector3, color: Color, uv_v: float) -> void:
	var uvs := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, uv_v), Vector2(0.0, uv_v)]
	var order := [0, 1, 2, 0, 2, 3]
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	st.set_normal(normal)
	st.set_color(color)
	for idx in order:
		st.set_uv(uvs[idx])
		st.add_vertex(corners[idx])


## Populates static scenery (debris, trees, rocks, pillars)
func _populate_static_objects() -> void:
	_clear_children(_props_node)
	var w := level_data.width
	var d := level_data.depth
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99

	# Materials for scenery
	var tree_trunk_mat := StandardMaterial3D.new()
	tree_trunk_mat.albedo_color = Color("#4a3322")
	var tree_leaves_mat := StandardMaterial3D.new()
	tree_leaves_mat.albedo_color = Color("#6b7a3f")
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color("#6f6a64")
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("#d9c9a5")
	var artifact_clay_mat := StandardMaterial3D.new()
	artifact_clay_mat.albedo_color = Color("#b8784c")
	var artifact_stone_mat := StandardMaterial3D.new()
	artifact_stone_mat.albedo_color = Color("#e4d7b6")

	for y in range(d):
		for x in range(w):
			var obj := level_data.get_cell_object(x, y)
			if obj == LevelData.ObjectType.NONE:
				continue

			var base_pos := level_data.get_world_pos(x, y)
			var jitter := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
			var spawn_pos := base_pos + jitter

			match obj:
				LevelData.ObjectType.TREE:
					_spawn_tree(spawn_pos, tree_trunk_mat, tree_leaves_mat, rng)
				LevelData.ObjectType.ROCK_LARGE:
					_spawn_rock(spawn_pos, rock_mat, 0.8, rng)
				LevelData.ObjectType.ROCK_SMALL:
					_spawn_rock(spawn_pos, rock_mat, 0.4, rng)
				LevelData.ObjectType.DEBRIS_PILE:
					_spawn_debris_pile(spawn_pos, rock_mat, rng)
				LevelData.ObjectType.RUIN_PILLAR:
					_spawn_pillar(spawn_pos, pillar_mat, rng)
				LevelData.ObjectType.RUIN_ARTIFACT:
					_spawn_artifact(spawn_pos, artifact_clay_mat, artifact_stone_mat, rng)
				LevelData.ObjectType.BUSH:
					_spawn_bush(spawn_pos, tree_leaves_mat, rng)


func _spawn_tree(pos: Vector3, trunk_mat: Material, leaves_mat: Material, _rng: RandomNumberGenerator) -> void:
	var tree_root := Node3D.new()
	tree_root.position = pos

	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.3
	cyl.height = 2.4
	trunk.mesh = cyl
	trunk.material_override = trunk_mat
	trunk.position = Vector3(0, 1.2, 0)
	tree_root.add_child(trunk)

	var leaves := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.2
	cone.height = 2.2
	leaves.mesh = cone
	leaves.material_override = leaves_mat
	leaves.position = Vector3(0, 2.8, 0)
	tree_root.add_child(leaves)

	# Collision
	var sb := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 2.4
	col.shape = shape
	col.position = Vector3(0, 1.2, 0)
	sb.add_child(col)
	tree_root.add_child(sb)

	_props_node.add_child(tree_root)


func _spawn_rock(pos: Vector3, mat: Material, scale_factor: float, rng: RandomNumberGenerator) -> void:
	var rock := MeshInstance3D.new()
	var box := BoxMesh.new()
	var s := scale_factor * rng.randf_range(0.8, 1.2)
	box.size = Vector3(s, s * 0.7, s)
	rock.mesh = box
	rock.material_override = mat
	rock.position = pos + Vector3(0, s * 0.35, 0)
	rock.rotation.y = rng.randf_range(0, TAU)

	var sb := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	sb.add_child(col)
	rock.add_child(sb)
	_props_node.add_child(rock)


func _spawn_debris_pile(pos: Vector3, mat: Material, rng: RandomNumberGenerator) -> void:
	for i in range(3):
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.3, 0.6), rng.randf_range(0.1, 0.25), rng.randf_range(0.2, 0.5))
		piece.mesh = box
		piece.material_override = mat
		var offset := Vector3(rng.randf_range(-0.3, 0.3), box.size.y * 0.5, rng.randf_range(-0.3, 0.3))
		piece.position = pos + offset
		piece.rotation.y = rng.randf_range(0, TAU)
		_props_node.add_child(piece)


## Ruin column: intact, broken, or fallen, chosen at random. Every variant is solid.
func _spawn_pillar(pos: Vector3, mat: Material, rng: RandomNumberGenerator) -> void:
	var root := StaticBody3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var variant := rng.randi() % 3
	if variant == 0:
		_build_intact_column(root, mat, rng.randf_range(2.6, 4.2))
	elif variant == 1:
		_build_broken_column(root, mat, rng.randf_range(1.0, 2.0))
	else:
		_build_fallen_column(root, mat)
	_props_node.add_child(root)


func _build_intact_column(root: StaticBody3D, mat: Material, shaft_h: float) -> void:
	var base_h := 0.3
	var capital_h := 0.22
	var total := base_h + shaft_h + capital_h
	_add_part(root, _box_mesh(Vector3(0.95, base_h, 0.95)), mat, Vector3(0, base_h * 0.5, 0))
	_add_part(root, _cylinder_mesh(0.28, 0.32, shaft_h), mat, Vector3(0, base_h + shaft_h * 0.5, 0))
	_add_part(root, _box_mesh(Vector3(0.8, capital_h, 0.8)), mat, Vector3(0, total - capital_h * 0.5, 0))
	_add_collider(root, _cylinder_shape(0.34, total), Vector3(0, total * 0.5, 0))


## Broken column: short shaft with a jagged top chunk and a fallen block at its foot.
func _build_broken_column(root: StaticBody3D, mat: Material, shaft_h: float) -> void:
	var base_h := 0.3
	var top_y := base_h + shaft_h
	_add_part(root, _box_mesh(Vector3(0.95, base_h, 0.95)), mat, Vector3(0, base_h * 0.5, 0))
	_add_part(root, _cylinder_mesh(0.28, 0.32, shaft_h), mat, Vector3(0, base_h + shaft_h * 0.5, 0))
	_add_part(root, _box_mesh(Vector3(0.5, 0.35, 0.45)), mat, Vector3(0.12, top_y + 0.05, 0), Vector3(0, 0, 0.35))
	_add_part(root, _box_mesh(Vector3(0.6, 0.25, 0.55)), mat, Vector3(-0.75, 0.13, 0.35), Vector3(0, 0.5, 0))
	_add_collider(root, _cylinder_shape(0.32, top_y), Vector3(0, top_y * 0.5, 0))


## Fallen column: shaft lying on the ground with a broken capital beside it.
func _build_fallen_column(root: StaticBody3D, mat: Material) -> void:
	var length := 3.0
	var radius := 0.3
	var lay := Vector3(0, 0, PI * 0.5)
	_add_part(root, _cylinder_mesh(radius, radius, length), mat, Vector3(0, radius, 0), lay)
	_add_part(root, _box_mesh(Vector3(0.7, 0.3, 0.7)), mat, Vector3(1.9, 0.15, 0.2))
	_add_collider(root, _cylinder_shape(radius, length), Vector3(0, radius, 0), lay)


## Small ruin artifacts: urn, tablet, statue head, or cracked bowl. Decor only, with no collision, so they never block routes.
func _spawn_artifact(pos: Vector3, clay_mat: Material, stone_mat: Material, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rng.randf_range(0.0, TAU)
	var kind := rng.randi() % 4
	if kind == 0:
		# Clay urn: squat body with a narrow neck
		_add_part(root, _sphere_mesh(0.22, 0.44), clay_mat, Vector3(0, 0.22, 0))
		_add_part(root, _cylinder_mesh(0.1, 0.1, 0.14), clay_mat, Vector3(0, 0.51, 0))
	elif kind == 1:
		# Standing inscribed tablet, tilted
		_add_part(root, _box_mesh(Vector3(0.5, 0.6, 0.12)), stone_mat, Vector3(0, 0.3, 0), Vector3(-0.12, 0, 0))
	elif kind == 2:
		# Broken statue head on a stub
		_add_part(root, _box_mesh(Vector3(0.3, 0.2, 0.3)), stone_mat, Vector3(0, 0.1, 0))
		_add_part(root, _sphere_mesh(0.2, 0.4), stone_mat, Vector3(0, 0.4, 0))
	else:
		# Cracked bowl with a shard beside it
		_add_part(root, _cylinder_mesh(0.45, 0.28, 0.3), clay_mat, Vector3(0, 0.15, 0))
		_add_part(root, _box_mesh(Vector3(0.18, 0.1, 0.14)), stone_mat, Vector3(0.55, 0.05, 0.2), Vector3(0, 0.6, 0))
	_props_node.add_child(root)


func _add_part(root: Node3D, mesh: Mesh, mat: Material, offset: Vector3, euler: Vector3 = Vector3.ZERO) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = mat
	part.position = offset
	part.rotation = euler
	root.add_child(part)


func _add_collider(root: StaticBody3D, shape: Shape3D, offset: Vector3, euler: Vector3 = Vector3.ZERO) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = offset
	col.rotation = euler
	root.add_child(col)


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cylinder_mesh(top_r: float, bottom_r: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	return m


func _sphere_mesh(radius: float, height: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	return m


func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


func _spawn_bush(pos: Vector3, mat: Material, _rng: RandomNumberGenerator) -> void:
	var bush := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 0.7
	bush.mesh = sphere
	bush.material_override = mat
	bush.position = pos + Vector3(0, 0.35, 0)
	_props_node.add_child(bush)


## Populates weapon spawns, enemy guard regions, and level exits
func _populate_gameplay_elements() -> void:
	_clear_children(_gameplay_node)

	# 1. Weapon spawns
	for weapon_data: Dictionary in level_data.weapon_spawns:
		_create_weapon_pickup(weapon_data)

	# 2. Enemy guard zones & blocking barriers
	for guard_data: Dictionary in level_data.enemy_guard_zones:
		_create_enemy_guard_zone(guard_data)

	# 3. Level Exits
	for exit_item: LevelExitData in level_data.exits:
		_create_exit_portal(exit_item)

	# 4. Wandering lambs
	_populate_lambs()


func _create_weapon_pickup(info: Dictionary) -> void:
	var weapon_type: String = info.get("type", "")
	if not WEAPON_SCENES.has(weapon_type):
		push_warning("LevelMapPopulator: no pickup scene for weapon type '%s'." % weapon_type)
		return
	var grid_pos: Vector2i = info.get("pos", Vector2i.ZERO)
	var scene: PackedScene = WEAPON_SCENES[weapon_type]
	var pickup := scene.instantiate() as Node3D
	pickup.name = "Weapon_" + str(info.get("id", "pickup"))
	pickup.position = level_data.get_world_pos(grid_pos.x, grid_pos.y)
	_gameplay_node.add_child(pickup)


func _create_enemy_guard_zone(info: Dictionary) -> void:
	var guard_grid: Vector2i = info.get("guard_pos", Vector2i.ZERO)
	var radius: float = info.get("guard_radius", 5.0)
	var blocks_path: bool = info.get("blocks_path", true)
	var barrier_cells: Array = info.get("barrier_cells", [])

	var guard_world := level_data.get_world_pos(guard_grid.x, guard_grid.y)

	var zone_node := Node3D.new()
	zone_node.name = "GuardZone_" + str(info.get("id", "zone"))
	zone_node.position = guard_world

	# Guard creature, randomly picked on every load (enemy_guard_scene overrides when set)
	var enemy_body := _instantiate_guard_creature(info)
	zone_node.add_child(enemy_body)

	# Guard area radius visual / detection circle
	var guard_circle := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.1
	torus.outer_radius = radius
	guard_circle.mesh = torus
	var circle_mat := StandardMaterial3D.new()
	circle_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.6)
	circle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	circle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guard_circle.material_override = circle_mat
	guard_circle.position = Vector3(0, 0.1, 0)
	zone_node.add_child(guard_circle)

	# One sealing slab per gap cell, so the gate matches the chokepoint width
	if blocks_path:
		var cell_size := level_data.cell_size
		var b_size := Vector3(cell_size, 3.0, cell_size)
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.7, 0.1, 0.1, 0.45)
		b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		b_mat.emission_enabled = true
		b_mat.emission = Color(0.9, 0.2, 0.2)
		b_mat.emission_energy_multiplier = 1.0
		for i in barrier_cells.size():
			var cell: Vector2i = barrier_cells[i]
			var barrier := StaticBody3D.new()
			barrier.name = "GuardBarrier_%d" % i
			barrier.position = level_data.get_world_pos(cell.x, cell.y) - guard_world + Vector3(0, 1.5, 0)

			var b_col := CollisionShape3D.new()
			var b_shape := BoxShape3D.new()
			b_shape.size = b_size
			b_col.shape = b_shape
			barrier.add_child(b_col)

			var b_mesh := MeshInstance3D.new()
			var b_box := BoxMesh.new()
			b_box.size = b_size
			b_mesh.mesh = b_box
			b_mesh.material_override = b_mat
			barrier.add_child(b_mesh)
			zone_node.add_child(barrier)

	enemy_body.tree_exiting.connect(func():
		for child in zone_node.get_children():
			if child != enemy_body and is_instance_valid(child):
				if child is CollisionObject3D:
					for sub in child.get_children():
						if sub is CollisionShape3D:
							sub.set_deferred("disabled", true)
				child.queue_free()
	)

	_gameplay_node.add_child(zone_node)


func _instantiate_guard_creature(info: Dictionary) -> CharacterBody3D:
	var scene: PackedScene = enemy_guard_scene
	if scene == null:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		scene = GUARD_CREATURE_SCENES[rng.randi() % GUARD_CREATURE_SCENES.size()]
	var enemy_body := scene.instantiate() as CharacterBody3D
	enemy_body.name = "Enemy_" + str(info.get("id", "guard"))
	return enemy_body


## Scatters lambs on open grass near the start, away from guard zones and each other.
func _populate_lambs() -> void:
	var start: Vector2i = level_data.entrances.get("start", Vector2i.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 417

	var candidates: Array[Vector2i] = []
	for y in level_data.depth:
		for x in level_data.width:
			if level_data.get_cell_terrain(x, y) != LevelData.TerrainType.GRASS:
				continue
			if level_data.get_cell_object(x, y) != LevelData.ObjectType.NONE:
				continue
			var from_start := Vector2(x - start.x, y - start.y).length()
			if from_start < LAMB_MIN_START_DIST or from_start > LAMB_MAX_START_DIST:
				continue
			if _is_near_guard(Vector2i(x, y)):
				continue
			candidates.append(Vector2i(x, y))

	var placed: Array[Vector2i] = []
	var attempts := 0
	while placed.size() < LAMB_COUNT and not candidates.is_empty() and attempts < 500:
		attempts += 1
		var pick: Vector2i = candidates[rng.randi() % candidates.size()]
		if _is_too_close(pick, placed):
			continue
		placed.append(pick)

	for i in placed.size():
		var cell: Vector2i = placed[i]
		var lamb := LAMB_SCENE.instantiate() as Node3D
		lamb.name = "Lamb_%d" % i
		lamb.position = level_data.get_world_pos(cell.x, cell.y)
		_gameplay_node.add_child(lamb)


func _is_near_guard(cell: Vector2i) -> bool:
	for guard_data: Dictionary in level_data.enemy_guard_zones:
		var guard_pos: Vector2i = guard_data.get("guard_pos", Vector2i.ZERO)
		if Vector2(cell).distance_to(Vector2(guard_pos)) < LAMB_GUARD_CLEARANCE:
			return true
	return false


func _is_too_close(cell: Vector2i, others: Array[Vector2i]) -> bool:
	for other in others:
		if Vector2(cell).distance_to(Vector2(other)) < LAMB_MIN_SPACING:
			return true
	return false


func _create_exit_portal(exit_item: LevelExitData) -> void:
	var world_pos := level_data.get_world_pos(exit_item.grid_pos.x, exit_item.grid_pos.y)

	var portal_area := Area3D.new()
	portal_area.name = "Exit_" + exit_item.id
	portal_area.position = world_pos
	portal_area.collision_mask = PLAYER_LAYER

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 4.0
	col.shape = shape
	col.position = Vector3(0, 2.0, 0)
	var is_cave := exit_item.is_cave_entrance or SidequestManager.is_sidequest_target(exit_item.target_level_path)
	if is_cave:
		_build_cave_entrance_visual(portal_area, exit_item)
	else:
		# Visual beacon beam
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.5
		cyl.height = 16.0
		beam.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = exit_item.color
		mat.emission_enabled = true
		mat.emission = exit_item.color
		mat.emission_energy_multiplier = 3.0
		beam.material_override = mat
		beam.position = Vector3(0, 8.0, 0)
		portal_area.add_child(beam)

		# Light
		var light := OmniLight3D.new()
		light.light_color = exit_item.color
		light.light_energy = 2.5
		light.omni_range = 14.0
		light.position = Vector3(0, 2.5, 0)
		portal_area.add_child(light)

	# Connect area body entered
	portal_area.body_entered.connect(func(body: Node3D):
		if body is CharacterBody3D and body.is_in_group("player"):
			level_exit_triggered.emit(exit_item.id, exit_item.target_level_path, exit_item.target_entrance_id)
	)

	_gameplay_node.add_child(portal_area)


func _build_cave_entrance_visual(portal_area: Area3D, exit_item: LevelExitData) -> void:
	var side := exit_item.cave_side
	if side == 0:
		side = -1 if exit_item.grid_pos.x < level_data.width / 2 else 1

	var cave_root := Node3D.new()
	cave_root.name = "CaveEntrance"
	# Face the opening toward the valley center: if on right wall (+1), cave goes +X; if on left wall (-1), cave goes -X.
	cave_root.rotation.y = 0.0 if side > 0 else PI
	portal_area.add_child(cave_root)

	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color("#4d4843")
	rock_mat.roughness = 0.95

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.02, 0.02, 0.03)
	dark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var moss_mat := StandardMaterial3D.new()
	moss_mat.albedo_color = Color("#5f7a38")
	moss_mat.roughness = 0.9

	# Left & right rock pillars framing the cave mouth along Z
	_add_part(cave_root, _box_mesh(Vector3(2.6, 4.8, 1.3)), rock_mat, Vector3(0.4, 2.4, -2.1), Vector3(0.05, 0.0, -0.08))
	_add_part(cave_root, _box_mesh(Vector3(2.6, 4.8, 1.3)), rock_mat, Vector3(0.4, 2.4, 2.1), Vector3(-0.05, 0.0, -0.08))
	# Arch lintel / cliff overhang above the cave opening
	_add_part(cave_root, _box_mesh(Vector3(3.0, 2.2, 5.6)), rock_mat, Vector3(0.5, 4.9, 0.0), Vector3(0.0, 0.0, 0.1))
	_add_part(cave_root, _box_mesh(Vector3(2.2, 1.6, 4.4)), moss_mat, Vector3(0.2, 5.9, 0.0))
	# Dark cave interior void inside the wall
	_add_part(cave_root, _box_mesh(Vector3(1.4, 3.8, 3.0)), dark_mat, Vector3(1.1, 1.9, 0.0))

	var light := OmniLight3D.new()
	light.light_color = Color(0.45, 0.85, 0.5)
	light.light_energy = 1.6
	light.omni_range = 8.0
	light.position = Vector3(-0.5, 2.2, 0.0)
	cave_root.add_child(light)


## Query helper for player spawn location
func get_entrance_world_pos(entrance_id: String = "start") -> Vector3:
	if not level_data:
		return global_position + Vector3(0, 3.0, 0)
	var key := entrance_id if level_data.entrances.has(entrance_id) else "start"
	if not level_data.entrances.has(key):
		return global_position + Vector3(0, 3.0, 0)
	var grid: Vector2i = level_data.entrances[key]
	var pos := level_data.get_world_pos(grid.x, grid.y)
	pos.y += 1.5
	return global_transform * pos
