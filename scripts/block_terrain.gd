class_name BlockTerrain
extends Node3D
## Procedural block terrain with a winding grass road, mud and debris shoulders and dirt hills.

enum Ground { GRASS, MUD, DEBRIS, DIRT }

const GROUND_COUNT := 4
const TEX_SIZE := 16
const BLOCK := 1.0
const SIDE_SHADE := 0.8
const ROAD_END_MARGIN := 12.0
const FEATURE_COUNT := [14, 5, 12, 8]
const FEATURE_SIZE := [1, 2, 2, 1]

@export var map_size := 80
@export var step_height := 0.5
@export var road_half_width := 2.5
@export var world_seed := 1337

## Indexed by Ground: base, dark, light, feature.
var _palettes := [
	[Color("#4a8a36"), Color("#3d7430"), Color("#5fa548"), Color("#7fc25a")],
	[Color("#5a4030"), Color("#3e2b20"), Color("#6f5038"), Color("#2c2a26")],
	[Color("#6e6558"), Color("#4f473d"), Color("#8c8478"), Color("#a9a296")],
	[Color("#7d5f40"), Color("#5f4530"), Color("#94744f"), Color("#a08868")],
]
var _side_normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
var _side_offsets := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _heights := FastNoiseLite.new()
var _wobble := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _levels := PackedInt32Array()
var _grounds := PackedInt32Array()


func _ready() -> void:
	_rng.seed = world_seed
	_heights.seed = world_seed
	_heights.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_heights.frequency = 0.035
	_heights.fractal_octaves = 3
	_wobble.seed = world_seed + 101
	_wobble.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wobble.frequency = 0.08
	_generate_grid()
	_build_mesh()
	_build_walls()


func get_spawn_position() -> Vector3:
	var spawn := _road_point(_road_end_z())
	spawn.y += 2.0
	return spawn


func get_goal_position() -> Vector3:
	return _road_point(-_road_end_z())


func _road_end_z() -> float:
	return map_size * 0.5 - ROAD_END_MARGIN


func _road_x(z: float) -> float:
	return 7.0 * sin(z * 0.07) + 3.0 * sin(z * 0.17 + 1.3)


func _road_slope(z: float) -> float:
	return 0.49 * cos(z * 0.07) + 0.51 * cos(z * 0.17 + 1.3)


func _road_height(z: float) -> float:
	return 1.0 + 0.8 * sin(z * 0.045 + 0.6)


func _road_point(z: float) -> Vector3:
	var half := map_size * 0.5
	var x := _road_x(z)
	var i := clampi(floori(x + half), 0, map_size - 1)
	var j := clampi(floori(z + half), 0, map_size - 1)
	return Vector3(x, _levels[j * map_size + i] * step_height, z)


func _generate_grid() -> void:
	var half := map_size * 0.5
	_levels.resize(map_size * map_size)
	_grounds.resize(map_size * map_size)
	for j in map_size:
		var z := j + 0.5 - half
		var slope := _road_slope(z)
		var perpendicular := sqrt(1.0 + slope * slope)
		for i in map_size:
			var x := i + 0.5 - half
			var road_dist := absf(x - _road_x(z)) / perpendicular
			var idx := j * map_size + i
			_levels[idx] = roundi(_height_at(x, z, road_dist) / step_height)
			_grounds[idx] = _ground_at(x, z, road_dist)
	_limit_slope()


func _height_at(x: float, z: float, road_dist: float) -> float:
	var n := (_heights.get_noise_2d(x, z) + 1.0) * 0.5
	var hills := 1.5 + 8.0 * n * n
	var blend := smoothstep(road_half_width, road_half_width + 9.0, road_dist)
	var height := lerpf(_road_height(z), hills, blend)
	var edge := map_size * 0.5 - maxf(absf(x), absf(z))
	return height + 12.0 * (1.0 - smoothstep(2.0, 8.0, edge))


func _ground_at(x: float, z: float, road_dist: float) -> int:
	var d := road_dist + _wobble.get_noise_2d(x, z) * 1.5
	if d < road_half_width:
		return Ground.GRASS
	if d < road_half_width + 2.2:
		return Ground.MUD
	if d < road_half_width + 5.0:
		return Ground.DEBRIS
	return Ground.DIRT


func _limit_slope() -> void:
	# Keeps every column within one block of its neighbours so the player can always step up.
	var top := 0
	for level in _levels:
		top = maxi(top, level)
	var buckets: Array = []
	for b in top + 1:
		buckets.append([])
	for idx in _levels.size():
		buckets[_levels[idx]].append(idx)
	for level in top + 1:
		for idx in buckets[level]:
			if _levels[idx] != level:
				continue
			var i: int = idx % map_size
			@warning_ignore("integer_division")
			var j: int = idx / map_size
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					var ni: int = i + di
					var nj: int = j + dj
					if (di == 0 and dj == 0) or ni < 0 or nj < 0 or ni >= map_size or nj >= map_size:
						continue
					var n: int = nj * map_size + ni
					if _levels[n] > level + 1:
						_levels[n] = level + 1
						buckets[level + 1].append(n)


func _build_mesh() -> void:
	var tools: Array[SurfaceTool] = []
	for g in GROUND_COUNT:
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(builder)

	var half := map_size * 0.5
	for j in map_size:
		for i in map_size:
			var idx := j * map_size + i
			var tool: SurfaceTool = tools[_grounds[idx]]
			var top := _levels[idx] * step_height
			var center := Vector3(i + 0.5 - half, top, j + 0.5 - half)
			var shade := _rng.randf_range(0.9, 1.05)
			_add_top(tool, center, shade)
			for s in _side_normals.size():
				var offset: Vector2i = _side_offsets[s]
				var ni: int = i + offset.x
				var nj: int = j + offset.y
				var neighbour_top := 0.0
				if ni >= 0 and nj >= 0 and ni < map_size and nj < map_size:
					neighbour_top = _levels[nj * map_size + ni] * step_height
				if neighbour_top < top:
					_add_side(tool, center, _side_normals[s], neighbour_top, top, shade * SIDE_SHADE)
			if _grounds[idx] == Ground.DEBRIS:
				_add_debris_props(tool, center, shade)

	var mesh := ArrayMesh.new()
	for g in GROUND_COUNT:
		tools[g].commit(mesh)
		mesh.surface_set_material(g, _make_material(g))

	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var concave := mesh.create_trimesh_shape()
	concave.backface_collision = true
	collider.shape = concave
	body.add_child(collider)
	add_child(body)

	var view := MeshInstance3D.new()
	view.mesh = mesh
	add_child(view)


func _add_top(tool: SurfaceTool, c: Vector3, shade: float) -> void:
	var h := BLOCK * 0.5
	var corners := PackedVector3Array([
		Vector3(c.x - h, c.y, c.z - h),
		Vector3(c.x + h, c.y, c.z - h),
		Vector3(c.x + h, c.y, c.z + h),
		Vector3(c.x - h, c.y, c.z + h),
	])
	_add_quad(tool, corners, Vector3.UP, Color(shade, shade, shade), 1.0)


func _add_side(tool: SurfaceTool, c: Vector3, normal: Vector3, low: float, high: float, shade: float) -> void:
	var h := BLOCK * 0.5
	var along := Vector3(-normal.z, 0.0, normal.x) * h
	var edge := Vector3(c.x, 0.0, c.z) + normal * h
	var lo := edge + Vector3(0.0, low, 0.0)
	var hi := edge + Vector3(0.0, high, 0.0)
	var corners := PackedVector3Array([lo - along, lo + along, hi + along, hi - along])
	_add_quad(tool, corners, normal, Color(shade, shade, shade), high - low)


func _add_debris_props(tool: SurfaceTool, c: Vector3, shade: float) -> void:
	var roll := _rng.randf()
	var jitter := Vector3(_rng.randf_range(-0.2, 0.2), 0.0, _rng.randf_range(-0.2, 0.2))
	if roll < 0.18:
		var s := _rng.randf_range(0.25, 0.5)
		var lo := c + jitter - Vector3(s, 0.0, s) * 0.5
		_add_box(tool, lo, lo + Vector3(s, s * 0.7, s), Color(shade, shade, shade))
	elif roll < 0.3:
		var length := _rng.randf_range(0.5, 0.9)
		var size := Vector3(length, 0.08, 0.07) if _rng.randf() < 0.5 else Vector3(0.07, 0.08, length)
		var lo := c + jitter - Vector3(size.x, 0.0, size.z) * 0.5
		_add_box(tool, lo, lo + size, Color(0.75, 0.6, 0.45))


func _add_box(tool: SurfaceTool, lo: Vector3, hi: Vector3, color: Color) -> void:
	var height := hi.y - lo.y
	_add_quad(tool, PackedVector3Array([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]), Vector3.UP, color, 1.0)
	_add_quad(tool, PackedVector3Array([Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z)]), Vector3.LEFT, color, height)
	_add_quad(tool, PackedVector3Array([Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]), Vector3.RIGHT, color, height)
	_add_quad(tool, PackedVector3Array([Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]), Vector3.FORWARD, color, height)
	_add_quad(tool, PackedVector3Array([Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]), Vector3.BACK, color, height)


func _add_quad(tool: SurfaceTool, corners: PackedVector3Array, normal: Vector3, color: Color, uv_v: float) -> void:
	var uvs := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, uv_v), Vector2(0.0, uv_v)]
	var order := [0, 1, 2, 0, 2, 3]
	# Godot treats clockwise triangles as front-facing, so flip the quad when it winds the other way.
	if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	tool.set_normal(normal)
	tool.set_color(color)
	for k in order:
		tool.set_uv(uvs[k])
		tool.add_vertex(corners[k])


func _make_material(ground: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_texture(ground)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat


func _make_texture(ground: int) -> ImageTexture:
	var pal: Array = _palettes[ground]
	var feature_size: int = FEATURE_SIZE[ground]
	var img := Image.create(TEX_SIZE, TEX_SIZE, true, Image.FORMAT_RGBA8)
	img.fill(pal[0])
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var roll := _rng.randf()
			if roll < 0.2:
				img.set_pixel(x, y, pal[1])
			elif roll < 0.35:
				img.set_pixel(x, y, pal[2])
	for _n in FEATURE_COUNT[ground]:
		var fx := _rng.randi_range(0, TEX_SIZE - 1)
		var fy := _rng.randi_range(0, TEX_SIZE - 1)
		for dy in feature_size:
			for dx in feature_size:
				img.set_pixel(posmod(fx + dx, TEX_SIZE), posmod(fy + dy, TEX_SIZE), pal[3])
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_walls() -> void:
	var half := map_size * 0.5
	var t := 2.0
	var wall_height := 40.0
	var span := map_size + 2.0 * t
	var y := wall_height * 0.5
	_add_wall(Vector3(half + t * 0.5, y, 0.0), Vector3(t, wall_height, span))
	_add_wall(Vector3(-half - t * 0.5, y, 0.0), Vector3(t, wall_height, span))
	_add_wall(Vector3(0.0, y, half + t * 0.5), Vector3(span, wall_height, t))
	_add_wall(Vector3(0.0, y, -half - t * 0.5), Vector3(span, wall_height, t))


func _add_wall(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	body.position = center
	add_child(body)
