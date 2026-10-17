class_name LevelMapPopulator
extends Node3D
## Generates and populates a bezier valley section at runtime before rendering:
## - Single obvious winding green grass trail forward
## - Textured muddy floor covering the valley ground level between the walls
## - Left and right valley cliff walls with a cave entrance cut out directly into the wall
## - Opening meadow sheep pen & target practice in section 0, weapon pickups, and enemy guard zone

signal level_exit_triggered(exit_id: String, target_level_path: String, target_entrance_id: String)

const PLAYER_LAYER := 2
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
const PRACTICE_TARGET_SCRIPT := preload("res://elements/weapons/practice_target.gd")
const LAMB_COUNT := 5
const CAVE_HOLE_HEIGHT := 3.1
const CAVE_HOLE_HALF_Z := 1.4
const CAVE_TUNNEL_DEPTH := 3.2

@export_group("Data & Generation")
@export var level_data: LevelData
@export var generation_mode: LevelMapGenerator.GenerationMode = LevelMapGenerator.GenerationMode.LINEAR_PATH
@export var world_seed: int = 1337
@export var section_index: int = 0
@export var section_length: int = 50
@export var section_width: int = 80
@export var auto_rebuild_on_ready: bool = true

@export_group("Scenery Prefabs / Meshes")
@export var weapon_item_scene: PackedScene
@export var enemy_guard_scene: PackedScene

var _terrain_node: Node3D
var _props_node: Node3D
var _gameplay_node: Node3D


func _ready() -> void:
	_ensure_subnodes()
	if auto_rebuild_on_ready:
		if level_data == null or level_data.bezier_path_x.is_empty():
			generate_level_data()
		else:
			rebuild_all()


func _ensure_subnodes() -> void:
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


## Generates LevelData at runtime right before building the 3D geometry
func generate_level_data() -> void:
	_ensure_subnodes()
	var gen := LevelMapGenerator.new()
	level_data = gen.generate(generation_mode, world_seed, section_width, section_length, section_index)
	rebuild_all()


## Rebuilds the 3D valley: bezier terrain & walls, cave hole cutout, and gameplay elements
func rebuild_all() -> void:
	_ensure_subnodes()
	if level_data == null or level_data.bezier_path_x.is_empty():
		var gen := LevelMapGenerator.new()
		level_data = gen.generate(generation_mode, world_seed, section_width, section_length, section_index)
	_build_3d_terrain()
	_clear_children(_props_node)
	_populate_gameplay_elements()


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Builds the single bezier path forward, muddy valley floor, left & right cliff walls, and cutout cave hole
func _build_3d_terrain() -> void:
	_clear_children(_terrain_node)
	var w := level_data.width
	var d := level_data.depth
	var block_size := level_data.cell_size
	var half_w := w * 0.5 * block_size
	var half_d := d * 0.5 * block_size

	var grass_st := SurfaceTool.new()
	var mud_st := SurfaceTool.new()
	var stone_st := SurfaceTool.new()
	var void_st := SurfaceTool.new()
	grass_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	mud_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	stone_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	void_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Locate cave entrance row & side so the hole is carved directly out of that side wall
	var cave_y := -999.0
	var cave_side := 0
	for exit_item: LevelExitData in level_data.exits:
		if exit_item.is_cave_entrance or SidequestManager.is_sidequest_target(exit_item.target_level_path):
			cave_y = float(exit_item.grid_pos.y) + 0.5
			cave_side = exit_item.cave_side
			if cave_side == 0:
				cave_side = -1 if exit_item.grid_pos.x < w / 2 else 1
			break

	var sub_steps := 4
	var total_slices := d * sub_steps
	var cave_z_min_t := cave_y - CAVE_HOLE_HALF_Z
	var cave_z_max_t := cave_y + CAVE_HOLE_HALF_Z

	for s in range(total_slices):
		var t0 := float(s) / float(sub_steps)
		var t1 := float(s + 1) / float(sub_steps)
		var mid_t := (t0 + t1) * 0.5
		var z0 := t0 * block_size - half_d
		var z1 := t1 * block_size - half_d

		var p0 := _eval_catmull_x(level_data.bezier_path_x, t0, d) * block_size - half_w
		var p1 := _eval_catmull_x(level_data.bezier_path_x, t1, d) * block_size - half_w
		var th0 := _eval_catmull_x(level_data.bezier_trail_half_w, t0, d) * block_size
		var th1 := _eval_catmull_x(level_data.bezier_trail_half_w, t1, d) * block_size

		var li0 := _eval_catmull_x(level_data.bezier_left_wall_inner_x, t0, d) * block_size - half_w
		var li1 := _eval_catmull_x(level_data.bezier_left_wall_inner_x, t1, d) * block_size - half_w
		var ri0 := _eval_catmull_x(level_data.bezier_right_wall_inner_x, t0, d) * block_size - half_w
		var ri1 := _eval_catmull_x(level_data.bezier_right_wall_inner_x, t1, d) * block_size - half_w

		var lo0 := -half_w
		var lo1 := -half_w
		var ro0 := half_w
		var ro1 := half_w

		var fy0 := _eval_catmull_x(level_data.bezier_floor_y, t0, d)
		var fy1 := _eval_catmull_x(level_data.bezier_floor_y, t1, d)

		var lh0 := fy0 + maxf(CAVE_HOLE_HEIGHT + 1.4, _eval_catmull_x(level_data.bezier_left_wall_height, t0, d))
		var lh1 := fy1 + maxf(CAVE_HOLE_HEIGHT + 1.4, _eval_catmull_x(level_data.bezier_left_wall_height, t1, d))
		var rh0 := fy0 + maxf(CAVE_HOLE_HEIGHT + 1.4, _eval_catmull_x(level_data.bezier_right_wall_height, t0, d))
		var rh1 := fy1 + maxf(CAVE_HOLE_HEIGHT + 1.4, _eval_catmull_x(level_data.bezier_right_wall_height, t1, d))

		var tl0 := maxf(li0, p0 - th0)
		var tr0 := minf(ri0, p0 + th0)
		var tl1 := maxf(li1, p1 - th1)
		var tr1 := minf(ri1, p1 + th1)

		var g_col0 := _sample_grass_vcol(t0)
		var g_col1 := _sample_grass_vcol(t1)
		var m_col := Color(0.95, 0.92, 0.88)

		# 1. Full muddy ground base covering the entire valley floor from left wall to right wall (with under-wall margin)
		_add_strip_quad(
			mud_st,
			Vector3(li0 - 1.5, fy0, z0),
			Vector3(ri0 + 1.5, fy0, z0),
			Vector3(ri1 + 1.5, fy1, z1),
			Vector3(li1 - 1.5, fy1, z1),
			m_col,
			m_col,
			0.25
		)

		# 2. Single obvious textured green grass path forward down the valley (plus opening meadow in section 0)
		_add_strip_quad(
			grass_st,
			Vector3(tl0, fy0 + 0.015, z0),
			Vector3(tr0, fy0 + 0.015, z0),
			Vector3(tr1, fy1 + 0.015, z1),
			Vector3(tl1, fy1 + 0.015, z1),
			g_col0,
			g_col1,
			0.25
		)

		var in_cave_hole := mid_t >= cave_z_min_t and mid_t <= cave_z_max_t

		# 3. Left valley wall (with cutout hole if cave is on the left side)
		var l_crest0 := li0 - 1.2
		var l_crest1 := li1 - 1.2
		if in_cave_hole and cave_side < 0:
			var hole_top0 := fy0 + CAVE_HOLE_HEIGHT
			var hole_top1 := fy1 + CAVE_HOLE_HEIGHT
			var recess0 := li0 - CAVE_TUNNEL_DEPTH
			var recess1 := li1 - CAVE_TUNNEL_DEPTH
			# Upper cliff wall bridging over the cutout cave hole
			_add_strip_quad(
				stone_st,
				Vector3(l_crest0, lh0, z0),
				Vector3(li0, hole_top0, z0),
				Vector3(li1, hole_top1, z1),
				Vector3(l_crest1, lh1, z1),
				Color(0.90, 0.88, 0.86),
				Color(0.90, 0.88, 0.86),
				lh0 - hole_top0
			)
			# Cutout cave ceiling inside the wall
			_add_strip_quad(
				stone_st,
				Vector3(li0, hole_top0, z0),
				Vector3(recess0, hole_top0, z0),
				Vector3(recess1, hole_top1, z1),
				Vector3(li1, hole_top1, z1),
				Color(0.65, 0.63, 0.60),
				Color(0.65, 0.63, 0.60),
				0.25
			)
			# Grass floor extending 3m into the cutout cave hole
			_add_strip_quad(
				grass_st,
				Vector3(recess0, fy0 + 0.018, z0),
				Vector3(li0 + 0.4, fy0 + 0.018, z0),
				Vector3(li1 + 0.4, fy1 + 0.018, z1),
				Vector3(recess1, fy1 + 0.018, z1),
				g_col0,
				g_col1,
				0.25
			)
			# Dark back wall inside the cave cutout
			_add_strip_quad(
				void_st,
				Vector3(recess0, hole_top0, z0),
				Vector3(recess0, fy0, z0),
				Vector3(recess1, fy1, z1),
				Vector3(recess1, hole_top1, z1),
				Color.BLACK,
				Color.BLACK,
				1.0
			)
		else:
			_add_strip_quad(
				stone_st,
				Vector3(l_crest0, lh0, z0),
				Vector3(li0, fy0 - 0.15, z0),
				Vector3(li1, fy1 - 0.15, z1),
				Vector3(l_crest1, lh1, z1),
				Color(0.92, 0.90, 0.88),
				Color(0.92, 0.90, 0.88),
				lh0 - fy0
			)

		# Left wall rocky plateau extending to the left edge of the section
		_add_strip_quad(
			stone_st,
			Vector3(lo0, lh0 + 0.6, z0),
			Vector3(l_crest0, lh0, z0),
			Vector3(l_crest1, lh1, z1),
			Vector3(lo1, lh1 + 0.6, z1),
			Color(0.78, 0.76, 0.73),
			Color(0.78, 0.76, 0.73),
			0.25
		)

		# 4. Right valley wall (with cutout hole if cave is on the right side)
		var r_crest0 := ri0 + 1.2
		var r_crest1 := ri1 + 1.2
		if in_cave_hole and cave_side > 0:
			var hole_top0 := fy0 + CAVE_HOLE_HEIGHT
			var hole_top1 := fy1 + CAVE_HOLE_HEIGHT
			var recess0 := ri0 + CAVE_TUNNEL_DEPTH
			var recess1 := ri1 + CAVE_TUNNEL_DEPTH
			# Upper cliff wall bridging over the cutout cave hole
			_add_strip_quad(
				stone_st,
				Vector3(ri0, hole_top0, z0),
				Vector3(r_crest0, rh0, z0),
				Vector3(r_crest1, rh1, z1),
				Vector3(ri1, hole_top1, z1),
				Color(0.90, 0.88, 0.86),
				Color(0.90, 0.88, 0.86),
				rh0 - hole_top0
			)
			# Cutout cave ceiling inside the wall
			_add_strip_quad(
				stone_st,
				Vector3(recess0, hole_top0, z0),
				Vector3(ri0, hole_top0, z0),
				Vector3(ri1, hole_top1, z1),
				Vector3(recess1, hole_top1, z1),
				Color(0.65, 0.63, 0.60),
				Color(0.65, 0.63, 0.60),
				0.25
			)
			# Grass floor extending 3m into the cutout cave hole
			_add_strip_quad(
				grass_st,
				Vector3(ri0 - 0.4, fy0 + 0.018, z0),
				Vector3(recess0, fy0 + 0.018, z0),
				Vector3(recess1, fy1 + 0.018, z1),
				Vector3(ri1 - 0.4, fy1 + 0.018, z1),
				g_col0,
				g_col1,
				0.25
			)
			# Dark back wall inside the cave cutout
			_add_strip_quad(
				void_st,
				Vector3(recess0, fy0, z0),
				Vector3(recess0, hole_top0, z0),
				Vector3(recess1, hole_top1, z1),
				Vector3(recess1, fy1, z1),
				Color.BLACK,
				Color.BLACK,
				1.0
			)
		else:
			_add_strip_quad(
				stone_st,
				Vector3(ri0, fy0 - 0.15, z0),
				Vector3(r_crest0, rh0, z0),
				Vector3(r_crest1, rh1, z1),
				Vector3(ri1, fy1 - 0.15, z1),
				Color(0.92, 0.90, 0.88),
				Color(0.92, 0.90, 0.88),
				rh0 - fy0
			)

		# Right wall rocky plateau extending to the right edge of the section
		_add_strip_quad(
			stone_st,
			Vector3(r_crest0, rh0, z0),
			Vector3(ro0, rh0 + 0.6, z0),
			Vector3(ro1, rh1 + 0.6, z1),
			Vector3(r_crest1, rh1, z1),
			Color(0.78, 0.76, 0.73),
			Color(0.78, 0.76, 0.73),
			0.25
		)

	# 5. Side jamb walls sealing the Z-sides of the cutout cave hole inside the cliff wall
	if cave_side != 0 and cave_y > 0.0:
		for boundary_t: float in [cave_z_min_t, cave_z_max_t]:
			var bz := boundary_t * block_size - half_d
			var bfy := _eval_catmull_x(level_data.bezier_floor_y, boundary_t, d)
			var btop := bfy + CAVE_HOLE_HEIGHT
			if cave_side < 0:
				var bli := _eval_catmull_x(level_data.bezier_left_wall_inner_x, boundary_t, d) * block_size - half_w
				var brec := bli - CAVE_TUNNEL_DEPTH
				_add_strip_quad(
					stone_st,
					Vector3(brec, bfy, bz),
					Vector3(bli, bfy, bz),
					Vector3(bli, btop, bz),
					Vector3(brec, btop, bz),
					Color(0.72, 0.70, 0.67),
					Color(0.72, 0.70, 0.67),
					CAVE_HOLE_HEIGHT
				)
			else:
				var bri := _eval_catmull_x(level_data.bezier_right_wall_inner_x, boundary_t, d) * block_size - half_w
				var brec := bri + CAVE_TUNNEL_DEPTH
				_add_strip_quad(
					stone_st,
					Vector3(bri, bfy, bz),
					Vector3(brec, bfy, bz),
					Vector3(brec, btop, bz),
					Vector3(bri, btop, bz),
					Color(0.72, 0.70, 0.67),
					Color(0.72, 0.70, 0.67),
					CAVE_HOLE_HEIGHT
				)

	# 6. Smooth bezier grass branch ribbon connecting the main trail to the cave cutout hole
	_append_cave_branch_ribbon(grass_st, half_w, half_d, block_size)

	var mesh := ArrayMesh.new()
	var mats := _create_terrain_materials()
	var st_list: Array[SurfaceTool] = [grass_st, mud_st, stone_st, void_st]
	var surface_idx := 0
	for i in range(st_list.size()):
		var prev_count := mesh.get_surface_count()
		st_list[i].commit(mesh)
		if mesh.get_surface_count() > prev_count:
			mesh.surface_set_material(surface_idx, mats[i])
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

	_populate_grass_blades()


## Catmull-Rom spline evaluation on a (d + 1) profile array for smooth C1 bezier curves
func _eval_catmull_x(arr: PackedFloat32Array, t: float, d: int) -> float:
	if arr.is_empty():
		return 0.0
	var clamped := clampf(t, 0.0, float(d))
	var i1 := clampi(int(floor(clamped)), 0, d)
	var i2 := clampi(i1 + 1, 0, d)
	var i0 := clampi(i1 - 1, 0, d)
	var i3 := clampi(i2 + 1, 0, d)
	var f := clamped - float(i1)
	var p0 := arr[i0]
	var p1 := arr[i1]
	var p2 := arr[i2]
	var p3 := arr[i3]
	var f2 := f * f
	var f3 := f2 * f
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f3)


func _sample_grass_vcol(t: float) -> Color:
	var wave := sin(t * 0.45 + float(world_seed % 71)) * 0.06
	return Color(
		clampf(0.88 + wave * 0.35, 0.78, 1.02),
		clampf(0.97 + wave, 0.86, 1.06),
		clampf(0.96 - wave * 0.5, 0.84, 1.08)
	)


func _add_strip_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, c0: Color, c1: Color, uv_v: float) -> void:
	var n := (v1 - v0).cross(v3 - v0).normalized()
	if n.length_squared() < 0.0001:
		n = Vector3.UP
	var uv0 := Vector2(v0.x * 0.35, v0.z * 0.35)
	var uv1 := Vector2(v1.x * 0.35, v1.z * 0.35)
	var uv2 := Vector2(v2.x * 0.35, v2.z * 0.35)
	var uv3 := Vector2(v3.x * 0.35, v3.z * 0.35)
	if absf(n.y) < 0.5:
		uv0 = Vector2(0.0, 0.0)
		uv1 = Vector2(1.0, 0.0)
		uv2 = Vector2(1.0, maxf(1.0, uv_v * 0.35))
		uv3 = Vector2(0.0, maxf(1.0, uv_v * 0.35))

	st.set_normal(n)
	st.set_color(c0)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_color(c1)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_color(c0)
	st.set_uv(uv1)
	st.add_vertex(v1)

	st.set_normal(n)
	st.set_color(c0)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_color(c1)
	st.set_uv(uv3)
	st.add_vertex(v3)
	st.set_color(c1)
	st.set_uv(uv2)
	st.add_vertex(v2)


func _append_cave_branch_ribbon(grass_st: SurfaceTool, half_w: float, half_d: float, block_size: float) -> void:
	var pts := level_data.bezier_cave_branch_points
	if pts.size() < 2:
		return
	var d := level_data.depth
	var half_branch := 1.45
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var wa := Vector3((a.x + 0.5) * block_size - half_w, _eval_catmull_x(level_data.bezier_floor_y, a.y, d) + 0.016, (a.y + 0.5) * block_size - half_d)
		var wb := Vector3((b.x + 0.5) * block_size - half_w, _eval_catmull_x(level_data.bezier_floor_y, b.y, d) + 0.016, (b.y + 0.5) * block_size - half_d)
		var dir := (wb - wa)
		dir.y = 0.0
		if dir.length_squared() < 0.0001:
			continue
		dir = dir.normalized()
		var perp := Vector3(-dir.z, 0.0, dir.x) * half_branch
		_add_strip_quad(
			grass_st,
			wa - perp,
			wa + perp,
			wb + perp,
			wb - perp,
			Color(0.92, 1.0, 0.98),
			Color(0.92, 1.0, 0.98),
			0.25
		)


func _create_terrain_materials() -> Array[StandardMaterial3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 777

	# 0: Textured blue-green grass
	var grass_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var grass_palette := [
		Color("#1b8266"),
		Color("#239676"),
		Color("#176e57"),
		Color("#2da884"),
		Color("#1e8b6c"),
	]
	for py in range(16):
		for px in range(16):
			var idx := (px * 3 + py * 5 + rng.randi_range(0, 4)) % grass_palette.size()
			var base_c: Color = grass_palette[idx]
			if (px + py) % 4 == 0:
				base_c = base_c.lightened(0.06)
			elif (px * py) % 7 == 0:
				base_c = base_c.darkened(0.07)
			grass_img.set_pixel(px, py, base_c)
	var grass_tex := ImageTexture.create_from_image(grass_img)

	# 1: Textured muddy floor covering ground level around the grass trail
	var mud_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for py in range(16):
		for px in range(16):
			var d_var := rng.randf_range(-0.07, 0.07)
			var puddle := -0.05 if ((px * 5 + py * 3) % 7 == 0) else 0.0
			mud_img.set_pixel(px, py, Color(0.48 + d_var + puddle, 0.36 + d_var * 0.8 + puddle, 0.25 + d_var * 0.6 + puddle))
	var mud_tex := ImageTexture.create_from_image(mud_img)

	# 2: Striated rocky cliff wall texture
	var stone_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for py in range(16):
		var band := sin(float(py) * 0.9) * 0.07
		for px in range(16):
			var grain := rng.randf_range(-0.04, 0.04)
			var c := Color(0.47 + band + grain, 0.43 + band + grain, 0.39 + band + grain)
			if py < 2:
				c = c.lerp(Color("#1f8a6c"), 0.55)
			stone_img.set_pixel(px, py, c)
	var stone_tex := ImageTexture.create_from_image(stone_img)

	var grass_mat := StandardMaterial3D.new()
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.albedo_color = Color("#249878")
	grass_mat.albedo_texture = grass_tex
	grass_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	grass_mat.roughness = 0.86

	var mud_mat := StandardMaterial3D.new()
	mud_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mud_mat.vertex_color_use_as_albedo = true
	mud_mat.albedo_color = Color("#7d5c3f")
	mud_mat.albedo_texture = mud_tex
	mud_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mud_mat.roughness = 0.90

	var stone_mat := StandardMaterial3D.new()
	stone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	stone_mat.vertex_color_use_as_albedo = true
	stone_mat.albedo_color = Color("#7c736a")
	stone_mat.albedo_texture = stone_tex
	stone_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	stone_mat.roughness = 0.92

	var void_mat := StandardMaterial3D.new()
	void_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	void_mat.albedo_color = Color(0.02, 0.02, 0.03)
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	return [grass_mat, mud_mat, stone_mat, void_mat]


## Scatters simple 3D triangle/polygon grass blades directly across the bezier grass path
func _populate_grass_blades() -> void:
	var w := level_data.width
	var d := level_data.depth
	var block_size := level_data.cell_size
	var half_w := w * 0.5 * block_size
	var half_d := d * 0.5 * block_size
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 313

	var transforms: Array[Transform3D] = []
	var colors: Array[Color] = []

	for y in range(d):
		var z_world := (float(y) + 0.5) * block_size - half_d
		var fy := _eval_catmull_x(level_data.bezier_floor_y, float(y) + 0.5, d)
		var px := _eval_catmull_x(level_data.bezier_path_x, float(y) + 0.5, d) * block_size - half_w
		var th := _eval_catmull_x(level_data.bezier_trail_half_w, float(y) + 0.5, d) * block_size
		var li := _eval_catmull_x(level_data.bezier_left_wall_inner_x, float(y) + 0.5, d) * block_size - half_w
		var ri := _eval_catmull_x(level_data.bezier_right_wall_inner_x, float(y) + 0.5, d) * block_size - half_w

		var tl := maxf(li, px - th)
		var tr := minf(ri, px + th)
		var span := maxf(0.0, tr - tl)
		var blade_count := clampi(int(span * 2.2), 6, 40)
		for i in range(blade_count):
			var wx := rng.randf_range(tl + 0.15, tr - 0.15)
			var wz := z_world + rng.randf_range(-0.45, 0.45)
			var yaw := rng.randf_range(0.0, TAU)
			var tilt := rng.randf_range(-0.18, 0.18)
			var s_xz := rng.randf_range(0.75, 1.35)
			var s_y := rng.randf_range(0.70, 1.45)
			var basis := Basis.from_euler(Vector3(tilt, yaw, 0.0)).scaled(Vector3(s_xz, s_y, s_xz))
			transforms.append(Transform3D(basis, Vector3(wx, fy + 0.015, wz)))

			var hue_var := rng.randf_range(0.43, 0.50)
			var sat_var := rng.randf_range(0.62, 0.84)
			var val_var := rng.randf_range(0.46, 0.74)
			colors.append(Color.from_hsv(hue_var, sat_var, val_var))

	if transforms.is_empty():
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blade_angles := [0.0, PI * 0.33, PI * 0.66]
	for i in range(blade_angles.size()):
		var ang: float = blade_angles[i]
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var bw := 0.09
		var bh := 0.34 + float(i % 2) * 0.08
		var lean := perp * 0.05
		var v0 := -dir * bw
		var v1 := dir * bw
		var v2 := Vector3(lean.x, bh, lean.z)
		var n := (v1 - v0).cross(v2 - v0).normalized()
		st.set_normal(n)
		st.set_color(Color(0.72, 0.82, 0.80))
		st.add_vertex(v0)
		st.set_color(Color(0.72, 0.82, 0.80))
		st.add_vertex(v1)
		st.set_color(Color(1.08, 1.15, 1.12))
		st.add_vertex(v2)

	var blade_mesh := st.commit()
	var blade_mat := StandardMaterial3D.new()
	blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade_mat.vertex_color_use_as_albedo = true
	blade_mat.albedo_color = Color.WHITE
	blade_mat.roughness = 0.78
	blade_mesh.surface_set_material(0, blade_mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = blade_mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassBladesMultiMesh"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_node.add_child(mmi)


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


func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	return s


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

	# 4. Opening meadow features (section 0): gated sheep pen on left & slingshot target practice on right
	if level_data.has_opening_meadow or level_data.section_index == 0:
		_build_opening_meadow_features()
	else:
		_populate_lambs()


func _build_opening_meadow_features() -> void:
	var half_d := level_data.depth * 0.5 * level_data.cell_size
	var floor_y := _eval_catmull_x(level_data.bezier_floor_y, 6.0, level_data.depth)

	# Left side of the 10m opening meadow: gated wooden sheep pen with several sheep inside
	var pen_center := Vector3(-11.0, floor_y, 6.2 * level_data.cell_size - half_d)
	_build_gated_sheep_pen(pen_center)

	# Right side of the 10m opening meadow: slingshot target practice range
	var range_center := Vector3(10.5, floor_y, 6.2 * level_data.cell_size - half_d)
	_build_target_practice_range(range_center)


func _build_gated_sheep_pen(center: Vector3) -> void:
	var pen_root := Node3D.new()
	pen_root.name = "GatedSheepPen"
	pen_root.position = center
	_gameplay_node.add_child(pen_root)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#5d4028")
	wood_mat.roughness = 0.88

	var dark_wood_mat := StandardMaterial3D.new()
	dark_wood_mat.albedo_color = Color("#3e2817")
	dark_wood_mat.roughness = 0.92

	var latch_mat := StandardMaterial3D.new()
	latch_mat.albedo_color = Color("#3a3d40")
	latch_mat.metallic = 0.6
	latch_mat.roughness = 0.45

	var half_x := 4.2
	var half_z := 2.8
	var fence_h := 1.15

	var fence_body := StaticBody3D.new()
	fence_body.name = "SheepPenFenceBody"
	pen_root.add_child(fence_body)

	# Corner and intermediate fence posts around the perimeter
	var post_positions: Array[Vector3] = [
		Vector3(-half_x, 0.0, -half_z),
		Vector3(0.0, 0.0, -half_z),
		Vector3(half_x, 0.0, -half_z),
		Vector3(-half_x, 0.0, 0.0),
		Vector3(-half_x, 0.0, half_z),
		Vector3(0.0, 0.0, half_z),
		Vector3(half_x, 0.0, half_z),
		# Gate posts on the right side (+X facing the player / center meadow)
		Vector3(half_x, 0.0, -1.05),
		Vector3(half_x, 0.0, 1.05),
	]
	for p in post_positions:
		_add_part(fence_body, _cylinder_mesh(0.11, 0.13, fence_h), dark_wood_mat, p + Vector3(0.0, fence_h * 0.5, 0.0))

	# Overhead gate arch crossbar above the gate posts
	_add_part(fence_body, _cylinder_mesh(0.11, 0.13, 1.65), dark_wood_mat, Vector3(half_x, 0.825, -1.05))
	_add_part(fence_body, _cylinder_mesh(0.11, 0.13, 1.65), dark_wood_mat, Vector3(half_x, 0.825, 1.05))
	_add_part(fence_body, _box_mesh(Vector3(0.18, 0.14, 2.35)), dark_wood_mat, Vector3(half_x, 1.62, 0.0))

	# Horizontal rails (top and bottom) for North (-Z), South (+Z), West (-X), and East (+X) side segments
	for rail_y in [0.38, 0.86]:
		# Back (-Z) and Front (+Z) rails
		_add_part(fence_body, _box_mesh(Vector3(half_x * 2.0, 0.09, 0.08)), wood_mat, Vector3(0.0, rail_y, -half_z))
		_add_part(fence_body, _box_mesh(Vector3(half_x * 2.0, 0.09, 0.08)), wood_mat, Vector3(0.0, rail_y, half_z))
		# Outer left (-X) rail
		_add_part(fence_body, _box_mesh(Vector3(0.08, 0.09, half_z * 2.0)), wood_mat, Vector3(-half_x, rail_y, 0.0))
		# East (+X) side rails flanking the central gate
		var wing_len := half_z - 1.05
		var wing_mid := 1.05 + wing_len * 0.5
		_add_part(fence_body, _box_mesh(Vector3(0.08, 0.09, wing_len)), wood_mat, Vector3(half_x, rail_y, -wing_mid))
		_add_part(fence_body, _box_mesh(Vector3(0.08, 0.09, wing_len)), wood_mat, Vector3(half_x, rail_y, wing_mid))

	# Closed wooden gate with diagonal cross-brace and iron latch between the gate posts (z = -1.05..1.05)
	var gate_node := Node3D.new()
	gate_node.name = "SheepPenGate"
	gate_node.position = Vector3(half_x, 0.0, 0.0)
	fence_body.add_child(gate_node)
	_add_part(gate_node, _box_mesh(Vector3(0.07, 0.09, 2.04)), wood_mat, Vector3(0.0, 0.34, 0.0))
	_add_part(gate_node, _box_mesh(Vector3(0.07, 0.09, 2.04)), wood_mat, Vector3(0.0, 0.88, 0.0))
	_add_part(gate_node, _box_mesh(Vector3(0.07, 0.68, 0.10)), wood_mat, Vector3(0.0, 0.61, -0.92))
	_add_part(gate_node, _box_mesh(Vector3(0.07, 0.68, 0.10)), wood_mat, Vector3(0.0, 0.61, 0.92))
	_add_part(gate_node, _box_mesh(Vector3(0.06, 0.08, 1.95)), wood_mat, Vector3(0.0, 0.61, 0.0), Vector3(0.28, 0.0, 0.0))
	_add_part(gate_node, _box_mesh(Vector3(0.14, 0.10, 0.18)), latch_mat, Vector3(0.02, 0.88, 0.95))

	# Physics colliders for all 4 walls of the gated pen so sheep stay safely penned
	_add_collider(fence_body, _box_shape(Vector3(half_x * 2.0, fence_h, 0.25)), Vector3(0.0, fence_h * 0.5, -half_z))
	_add_collider(fence_body, _box_shape(Vector3(half_x * 2.0, fence_h, 0.25)), Vector3(0.0, fence_h * 0.5, half_z))
	_add_collider(fence_body, _box_shape(Vector3(0.25, fence_h, half_z * 2.0)), Vector3(-half_x, fence_h * 0.5, 0.0))
	_add_collider(fence_body, _box_shape(Vector3(0.25, fence_h, half_z * 2.0)), Vector3(half_x, fence_h * 0.5, 0.0))

	# Spawn 5 sheep inside the gated pen
	var sheep_offsets: Array[Vector3] = [
		Vector3(-1.8, 0.05, -1.2),
		Vector3(1.4, 0.05, -1.1),
		Vector3(-0.3, 0.05, 0.1),
		Vector3(-1.9, 0.05, 1.3),
		Vector3(1.5, 0.05, 1.2),
	]
	for i in range(sheep_offsets.size()):
		var lamb := LAMB_SCENE.instantiate() as Lamb
		lamb.name = "Lamb_%d" % i
		lamb.penned = true
		lamb.wander_radius = 2.1
		lamb.position = center + sheep_offsets[i]
		lamb.rotation.y = float(i) * 1.25
		_gameplay_node.add_child(lamb)


func _build_target_practice_range(center: Vector3) -> void:
	var range_root := Node3D.new()
	range_root.name = "TargetPracticeRange"
	range_root.position = center
	_gameplay_node.add_child(range_root)

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color("#63442b")
	wood_mat.roughness = 0.86

	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_color = Color("#c8a24a")
	hay_mat.roughness = 0.92

	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color("#f2ece1")
	white_mat.roughness = 0.75

	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color("#c9302c")
	red_mat.roughness = 0.72

	var blue_mat := StandardMaterial3D.new()
	blue_mat.albedo_color = Color("#2e6da4")
	blue_mat.roughness = 0.75

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color("#f0ad4e")
	gold_mat.emission_enabled = true
	gold_mat.emission = Color("#d9822b")
	gold_mat.emission_energy_multiplier = 0.45

	# Wooden shooting table / rack near the firing line (where the slingshot pickup sits at x=+8, y=5 -> local x=-2.5, z=-1.2)
	var table_body := StaticBody3D.new()
	table_body.name = "SlingshotRackTable"
	table_body.position = Vector3(-2.5, 0.0, -1.2)
	range_root.add_child(table_body)
	_add_part(table_body, _box_mesh(Vector3(1.5, 0.08, 0.9)), wood_mat, Vector3(0.0, 0.65, 0.0))
	for lx in [-0.62, 0.62]:
		for lz in [-0.35, 0.35]:
			_add_part(table_body, _cylinder_mesh(0.06, 0.06, 0.65), wood_mat, Vector3(lx, 0.325, lz))
	_add_collider(table_body, _box_shape(Vector3(1.5, 0.7, 0.9)), Vector3(0.0, 0.35, 0.0))

	# Elevate the slingshot pickup so it rests cleanly above the wooden practice table
	var slingshot_pickup := _gameplay_node.get_node_or_null("Weapon_practice_slingshot_0") as Node3D
	if slingshot_pickup:
		slingshot_pickup.position = table_body.global_position if is_inside_tree() else (center + table_body.position)
		slingshot_pickup.position.y += 0.85

	# Low wooden firing line rail & hay bales
	var rail_body := StaticBody3D.new()
	rail_body.name = "FiringLineRail"
	range_root.add_child(rail_body)
	_add_part(rail_body, _box_mesh(Vector3(0.10, 0.10, 4.8)), wood_mat, Vector3(-1.4, 0.45, 0.2))
	_add_part(rail_body, _cylinder_mesh(0.08, 0.09, 0.6), wood_mat, Vector3(-1.4, 0.3, -2.1))
	_add_part(rail_body, _cylinder_mesh(0.08, 0.09, 0.6), wood_mat, Vector3(-1.4, 0.3, 2.5))
	# Hay bales flanking the targets
	_add_part(rail_body, _box_mesh(Vector3(0.9, 0.55, 1.3)), hay_mat, Vector3(1.6, 0.275, -2.2), Vector3(0.0, 0.15, 0.0))
	_add_part(rail_body, _box_mesh(Vector3(0.9, 0.55, 1.3)), hay_mat, Vector3(2.2, 0.275, 2.4), Vector3(0.0, -0.2, 0.0))

	# 3 Bullseye Practice Targets at staggered distances & heights on the right side
	var target_specs := [
		{"name": "PracticeTarget_0", "pos": Vector3(2.2, 0.0, -1.6), "height": 1.35, "yaw": -0.22},
		{"name": "PracticeTarget_1", "pos": Vector3(3.6, 0.0, 0.2), "height": 1.55, "yaw": 0.0},
		{"name": "PracticeTarget_2", "pos": Vector3(2.5, 0.0, 1.9), "height": 1.25, "yaw": 0.22},
	]
	for spec: Dictionary in target_specs:
		var t_body := PRACTICE_TARGET_SCRIPT.new() as StaticBody3D
		t_body.name = spec["name"]
		t_body.position = spec["pos"]
		t_body.rotation.y = float(spec["yaw"])
		t_body.collision_layer = 5 # Layers 1 (world) + 3 (enemy) so StoneProjectile mask 5 collides & triggers enemy_struck
		range_root.add_child(t_body)

		var post_h: float = spec["height"]
		# Wooden stand post & base
		_add_part(t_body, _box_mesh(Vector3(0.7, 0.1, 0.7)), wood_mat, Vector3(0.0, 0.05, 0.0))
		_add_part(t_body, _cylinder_mesh(0.08, 0.10, post_h), wood_mat, Vector3(0.0, post_h * 0.5, 0.0))

		# Hinged bullseye disc pivot so hitting it with a stone knocks it back & springs it upright
		var pivot := Node3D.new()
		pivot.name = "BullseyePivot"
		pivot.position = Vector3(0.0, post_h, 0.0)
		t_body.add_child(pivot)

		# Concentric bullseye rings facing -X (toward the firing line / center meadow)
		var face_rot := Vector3(0.0, 0.0, PI * 0.5)
		_add_part(pivot, _cylinder_mesh(0.58, 0.58, 0.10), hay_mat, Vector3(0.0, 0.0, 0.0), face_rot)
		_add_part(pivot, _cylinder_mesh(0.50, 0.50, 0.12), white_mat, Vector3(-0.01, 0.0, 0.0), face_rot)
		_add_part(pivot, _cylinder_mesh(0.36, 0.36, 0.14), blue_mat, Vector3(-0.02, 0.0, 0.0), face_rot)
		_add_part(pivot, _cylinder_mesh(0.23, 0.23, 0.16), red_mat, Vector3(-0.03, 0.0, 0.0), face_rot)
		_add_part(pivot, _cylinder_mesh(0.10, 0.10, 0.18), gold_mat, Vector3(-0.04, 0.0, 0.0), face_rot)

		_add_collider(t_body, _cylinder_shape(0.62, 0.35), Vector3(0.0, post_h, 0.0), face_rot)
		t_body.setup(pivot)


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


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


## Scatters lambs along the green trail in non-opening sections
func _populate_lambs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 417
	for i in range(LAMB_COUNT):
		var y_row := clampi(7 + i * 3 + rng.randi_range(-1, 1), 6, level_data.depth - 14)
		var px := _eval_catmull_x(level_data.bezier_path_x, float(y_row), level_data.depth)
		var cell_x := clampi(int(round(px + rng.randf_range(-1.5, 1.5))), 4, level_data.width - 5)
		var lamb := LAMB_SCENE.instantiate() as Node3D
		lamb.name = "Lamb_%d" % i
		lamb.position = level_data.get_world_pos(cell_x, y_row)
		_gameplay_node.add_child(lamb)


func _create_exit_portal(exit_item: LevelExitData) -> void:
	var world_pos := level_data.get_world_pos(exit_item.grid_pos.x, exit_item.grid_pos.y)

	var portal_area := Area3D.new()
	portal_area.name = "Exit_" + exit_item.id
	portal_area.position = world_pos
	portal_area.collision_mask = PLAYER_LAYER

	var is_cave := exit_item.is_cave_entrance or SidequestManager.is_sidequest_target(exit_item.target_level_path)
	var col := CollisionShape3D.new()
	col.name = "ExitTriggerShape"
	if is_cave:
		var side := exit_item.cave_side if exit_item.cave_side != 0 else (-1 if exit_item.grid_pos.x < level_data.width / 2 else 1)
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(2.4, CAVE_HOLE_HEIGHT, CAVE_HOLE_HALF_Z * 2.0)
		col.shape = box_shape
		col.position = Vector3(float(side) * 0.9, CAVE_HOLE_HEIGHT * 0.5, 0.0)

		var cave_light := OmniLight3D.new()
		cave_light.light_color = Color(0.45, 0.85, 0.5)
		cave_light.light_energy = 1.4
		cave_light.omni_range = 7.0
		cave_light.position = Vector3(-float(side) * 0.4, 2.0, 0.0)
		portal_area.add_child(cave_light)
	else:
		var shape := CylinderShape3D.new()
		shape.radius = 2.0
		shape.height = 4.0
		col.shape = shape
		col.position = Vector3(0.0, 2.0, 0.0)

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

		var light := OmniLight3D.new()
		light.light_color = exit_item.color
		light.light_energy = 2.5
		light.omni_range = 14.0
		light.position = Vector3(0, 2.5, 0)
		portal_area.add_child(light)

	portal_area.add_child(col)
	portal_area.body_entered.connect(func(body: Node3D):
		if body is CharacterBody3D and body.is_in_group("player"):
			level_exit_triggered.emit(exit_item.id, exit_item.target_level_path, exit_item.target_entrance_id)
	)

	_gameplay_node.add_child(portal_area)


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
