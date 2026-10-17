class_name LevelMapGenerator
extends RefCounted
## Runtime procedural generator for the bezier valley sections.
## Synthesizes a single winding path forward with left and right valley walls,
## an opening green meadow funnel in section 0, a sidequest cave hole in one side wall,
## weapon pickups, and an enemy guard zone near the exit.

enum GenerationMode {
	LINEAR_PATH,
	OPEN_EXPLORATION,
	SIDE_QUEST_MAZE
}

var mode: GenerationMode = GenerationMode.LINEAR_PATH
var seed_val: int = 1337
var map_width: int = 80
var map_depth: int = 50
var step_height: float = LevelData.DEFAULT_STEP_HEIGHT
var cell_size: float = 1.0
var section_index: int = 0

const GATE_RING_RADIUS := 4
const GATE_HALF_WIDTH := 1
const GUARD_SETBACK := 2
const TRAIL_MIN_HALF_WIDTH := 1.0      # 2m minimum main trail width
const TRAIL_MAX_HALF_WIDTH := 3.0      # 6m maximum main trail width
const GREEN_CENTER_HALF_WIDTH := 2.0   # 4m average main trail width
const DIRT_AVG_SIDE_WIDTH := 5.0       # ~5m muddy/dirt side width before walls
const WALL_THICKNESS_MIN := 4.0
const WALL_THICKNESS_MAX := 7.0
const WALL_MIN_HEIGHT_INCREASE := 3.6  # 2x player height (1.8 m)
const WALL_MAX_HEIGHT_INCREASE := 9.0  # 5x player height (1.8 m)
const SECTION_0_MOUTH_Y := 10.0        # 10m from entrance to the valley mouth in section 0
const SECTION_0_REGULAR_START_Y := 16.0 # +6m until the regular valley begins in section 0
const PASSAGE_HALF_WIDTH := 1.5
const PASSAGE_BLEND_ROWS := 10.0
const SEAM_NOISE_BLEND_ROWS := 8.0

var _noise_height := FastNoiseLite.new()
var _noise_detail := FastNoiseLite.new()
var _noise_seam := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _path_curve := Curve2D.new()
var _branch_curve := Curve2D.new()
var _left_wall_curve := Curve2D.new()
var _right_wall_curve := Curve2D.new()
var _path_x_lut := PackedFloat32Array()
var _trail_half_lut := PackedFloat32Array()
var _left_wall_inner_lut := PackedFloat32Array()
var _right_wall_inner_lut := PackedFloat32Array()
var _left_wall_thick_lut := PackedFloat32Array()
var _right_wall_thick_lut := PackedFloat32Array()


func generate(p_mode: GenerationMode = GenerationMode.LINEAR_PATH, p_seed: int = 1337, p_width: int = 80, p_depth: int = 50, p_section_index: int = 0) -> LevelData:
	mode = p_mode
	seed_val = p_seed
	map_width = p_width
	map_depth = p_depth
	section_index = p_section_index

	_rng.seed = seed_val
	_setup_noise()

	var data := LevelData.new()
	data.width = map_width
	data.depth = map_depth
	data.cell_size = cell_size
	data.step_height = step_height
	data.section_index = section_index
	data.has_opening_meadow = (section_index == 0)
	data.meadow_funnel_end_y = SECTION_0_REGULAR_START_Y if data.has_opening_meadow else 0.0

	_setup_bezier_path()
	_populate_bezier_profile_data(data)
	_populate_connectors_and_spawns(data)
	data.bezier_cave_branch_points = _branch_curve.get_baked_points()
	return data


func _setup_noise() -> void:
	_noise_height.seed = seed_val
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_height.frequency = 0.035
	_noise_height.fractal_octaves = 3

	_noise_detail.seed = seed_val + 101
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.frequency = 0.08

	_noise_seam.seed = 9001
	_noise_seam.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_seam.frequency = 0.035
	_noise_seam.fractal_octaves = 3


func _setup_bezier_path() -> void:
	_path_curve.clear_points()
	_path_curve.bake_interval = 0.25
	_left_wall_curve.clear_points()
	_left_wall_curve.bake_interval = 0.25
	_right_wall_curve.clear_points()
	_right_wall_curve.bake_interval = 0.25

	var cx := float(map_width) * 0.5
	var max_y := float(maxi(1, map_depth - 1))
	var seg_count := 6
	var seg_len := max_y / float(seg_count)
	var max_sway := minf(9.0, float(map_width) * 0.14)

	var pts: Array[Vector2] = []
	for i in range(seg_count + 1):
		var y := float(i) * seg_len
		var x := cx
		if section_index == 0 and y <= SECTION_0_REGULAR_START_Y:
			x = cx
		elif i == 1 or i == seg_count - 1:
			x = cx + _rng.randf_range(-2.0, 2.0)
		elif i > 1 and i < seg_count - 1:
			var side := -1.0 if ((i + (seed_val % 2)) % 2 == 0) else 1.0
			x = cx + side * _rng.randf_range(3.5, max_sway)
		pts.append(Vector2(x, y))

	for i in range(pts.size()):
		var p := pts[i]
		var in_vec := Vector2.ZERO
		var out_vec := Vector2.ZERO
		if i == 0:
			out_vec = Vector2(0.0, seg_len * 0.45)
		elif i == pts.size() - 1:
			in_vec = Vector2(0.0, -seg_len * 0.45)
		else:
			var tangent_x := clampf((pts[i + 1].x - pts[i - 1].x) * 0.28, -5.0, 5.0)
			var handle_y := seg_len * 0.4
			in_vec = Vector2(-tangent_x, -handle_y)
			out_vec = Vector2(tangent_x, handle_y)
		_path_curve.add_point(p, in_vec, out_vec)

	_path_x_lut.resize(map_depth)
	var baked := _path_curve.get_baked_points()
	for y_idx in range(map_depth):
		_path_x_lut[y_idx] = _sample_curve_x_at_y(baked, float(y_idx), cx)

	var exit_y := float(maxi(14, map_depth - 3))
	var guard_y := exit_y - float(GATE_RING_RADIUS + GUARD_SETBACK)
	if section_index == 0:
		# First section: 10m open green meadow funneling from outer edges into the valley, +6m transition to regular valley
		var edge_margin := 6.0
		var funnel_p0_l := Vector2(edge_margin, 0.0)
		var funnel_p0_r := Vector2(float(map_width) - edge_margin, 0.0)
		var mouth_half := 13.5
		var funnel_p1_l := Vector2(cx - mouth_half, SECTION_0_MOUTH_Y)
		var funnel_p1_r := Vector2(cx + mouth_half, SECTION_0_MOUTH_Y)
		var reg_p_x := _path_center_x(SECTION_0_REGULAR_START_Y)
		var reg_half := GREEN_CENTER_HALF_WIDTH + DIRT_AVG_SIDE_WIDTH
		var funnel_p2_l := Vector2(reg_p_x - reg_half, SECTION_0_REGULAR_START_Y)
		var funnel_p2_r := Vector2(reg_p_x + reg_half, SECTION_0_REGULAR_START_Y)

		_left_wall_curve.add_point(funnel_p0_l, Vector2.ZERO, Vector2(4.0, 4.5))
		_left_wall_curve.add_point(funnel_p1_l, Vector2(-6.5, -3.5), Vector2(3.5, 2.5))
		_left_wall_curve.add_point(funnel_p2_l, Vector2(-2.0, -2.5), Vector2(0.0, 3.0))

		_right_wall_curve.add_point(funnel_p0_r, Vector2.ZERO, Vector2(-4.0, 4.5))
		_right_wall_curve.add_point(funnel_p1_r, Vector2(6.5, -3.5), Vector2(-3.5, 2.5))
		_right_wall_curve.add_point(funnel_p2_r, Vector2(2.0, -2.5), Vector2(0.0, 3.0))

		var rem_segs := 4
		var rem_len := (max_y - SECTION_0_REGULAR_START_Y) / float(rem_segs)
		var rem_l: Array[Vector2] = [funnel_p2_l]
		var rem_r: Array[Vector2] = [funnel_p2_r]
		for j in range(1, rem_segs + 1):
			var y := SECTION_0_REGULAR_START_Y + float(j) * rem_len
			var path_x := _path_center_x(y)
			var narrow := _passage_narrow_factor(y)
			var enemy_pinch := 1.0 - smoothstep(1.5, 9.5, absf(y - guard_y))
			var close_in := maxf(narrow, enemy_pinch * 0.72)
			var trail_h := lerpf(GREEN_CENTER_HALF_WIDTH, PASSAGE_HALF_WIDTH * 0.85, close_in)
			var dirt_l := lerpf(DIRT_AVG_SIDE_WIDTH + _rng.randf_range(-1.0, 1.0), 0.7, close_in)
			var dirt_r := lerpf(DIRT_AVG_SIDE_WIDTH + _rng.randf_range(-1.0, 1.0), 0.7, close_in)
			if j == rem_segs:
				trail_h = PASSAGE_HALF_WIDTH
				dirt_l = 0.0
				dirt_r = 0.0
				path_x = cx
			rem_l.append(Vector2(path_x - trail_h - dirt_l, y))
			rem_r.append(Vector2(path_x + trail_h + dirt_r, y))

		_append_smooth_wall_points(rem_l, rem_r, rem_len, 1)
	else:
		var left_pts: Array[Vector2] = []
		var right_pts: Array[Vector2] = []
		for i in range(seg_count + 1):
			var y := float(i) * seg_len
			var path_x := _path_center_x(y)
			var narrow := _passage_narrow_factor(y)
			var enemy_pinch := 1.0 - smoothstep(1.5, 9.5, absf(y - guard_y))
			var close_in := maxf(narrow, enemy_pinch * 0.72)
			var trail_h := lerpf(GREEN_CENTER_HALF_WIDTH, PASSAGE_HALF_WIDTH * 0.85, close_in)
			var dirt_l := lerpf(DIRT_AVG_SIDE_WIDTH + _rng.randf_range(-1.0, 1.0), 0.7, close_in)
			var dirt_r := lerpf(DIRT_AVG_SIDE_WIDTH + _rng.randf_range(-1.0, 1.0), 0.7, close_in)
			if i == 0 or i == seg_count:
				trail_h = PASSAGE_HALF_WIDTH
				dirt_l = 0.0
				dirt_r = 0.0
				path_x = cx
			left_pts.append(Vector2(path_x - trail_h - dirt_l, y))
			right_pts.append(Vector2(path_x + trail_h + dirt_r, y))

		_append_smooth_wall_points(left_pts, right_pts, seg_len, 0)

	_trail_half_lut.resize(map_depth)
	_left_wall_inner_lut.resize(map_depth)
	_right_wall_inner_lut.resize(map_depth)
	_left_wall_thick_lut.resize(map_depth)
	_right_wall_thick_lut.resize(map_depth)
	var baked_l := _left_wall_curve.get_baked_points()
	var baked_r := _right_wall_curve.get_baked_points()
	for y_idx in range(map_depth):
		var yf := float(y_idx)
		var narrow := _passage_narrow_factor(yf)
		var width_n := (_noise_detail.get_noise_2d(yf * 1.35, float(seed_val % 313)) + 1.0) * 0.5
		var raw_half := lerpf(TRAIL_MIN_HALF_WIDTH, TRAIL_MAX_HALF_WIDTH, clampf(width_n, 0.0, 1.0))
		_trail_half_lut[y_idx] = lerpf(raw_half, PASSAGE_HALF_WIDTH, narrow)
		_left_wall_inner_lut[y_idx] = _sample_curve_x_at_y(baked_l, yf, cx - 7.0)
		_right_wall_inner_lut[y_idx] = _sample_curve_x_at_y(baked_r, yf, cx + 7.0)
		var tl_n := (_noise_height.get_noise_2d(13.0, yf * 1.4) + 1.0) * 0.5
		var tr_n := (_noise_height.get_noise_2d(67.0, yf * 1.4) + 1.0) * 0.5
		_left_wall_thick_lut[y_idx] = lerpf(WALL_THICKNESS_MIN, WALL_THICKNESS_MAX, clampf(tl_n, 0.0, 1.0))
		_right_wall_thick_lut[y_idx] = lerpf(WALL_THICKNESS_MIN, WALL_THICKNESS_MAX, clampf(tr_n, 0.0, 1.0))


func _append_smooth_wall_points(left_pts: Array[Vector2], right_pts: Array[Vector2], seg_len: float, start_idx: int) -> void:
	for j in range(start_idx, left_pts.size()):
		var in_l := Vector2.ZERO
		var out_l := Vector2.ZERO
		var in_r := Vector2.ZERO
		var out_r := Vector2.ZERO
		if j == 0:
			out_l = Vector2(0.0, seg_len * 0.45)
			out_r = Vector2(0.0, seg_len * 0.45)
		elif j == left_pts.size() - 1:
			in_l = Vector2(0.0, -seg_len * 0.45)
			in_r = Vector2(0.0, -seg_len * 0.45)
		else:
			var tl_x := clampf((left_pts[j + 1].x - left_pts[j - 1].x) * 0.28, -5.0, 5.0)
			var tr_x := clampf((right_pts[j + 1].x - right_pts[j - 1].x) * 0.28, -5.0, 5.0)
			var hy := seg_len * 0.4
			in_l = Vector2(-tl_x, -hy)
			out_l = Vector2(tl_x, hy)
			in_r = Vector2(-tr_x, -hy)
			out_r = Vector2(tr_x, hy)
		_left_wall_curve.add_point(left_pts[j], in_l, out_l)
		_right_wall_curve.add_point(right_pts[j], in_r, out_r)


func _sample_curve_x_at_y(baked: PackedVector2Array, yf: float, fallback_x: float) -> float:
	for k in range(baked.size() - 1):
		var a := baked[k]
		var b := baked[k + 1]
		if (yf >= a.y and yf <= b.y) or (yf >= b.y and yf <= a.y):
			var dy := b.y - a.y
			var ratio := (yf - a.y) / dy if absf(dy) > 0.0001 else 0.0
			return lerpf(a.x, b.x, clampf(ratio, 0.0, 1.0))
	return fallback_x


func _trail_half_width_at_y(y: float) -> float:
	if _trail_half_lut.size() == map_depth:
		var cy := clampf(y, 0.0, float(map_depth - 1))
		var y0 := int(floor(cy))
		var y1 := mini(map_depth - 1, y0 + 1)
		return lerpf(_trail_half_lut[y0], _trail_half_lut[y1], cy - float(y0))
	return GREEN_CENTER_HALF_WIDTH


func _left_wall_inner_x(y: float) -> float:
	if _left_wall_inner_lut.size() == map_depth:
		var cy := clampf(y, 0.0, float(map_depth - 1))
		var y0 := int(floor(cy))
		var y1 := mini(map_depth - 1, y0 + 1)
		return lerpf(_left_wall_inner_lut[y0], _left_wall_inner_lut[y1], cy - float(y0))
	return _path_center_x(y) - 7.0


func _right_wall_inner_x(y: float) -> float:
	if _right_wall_inner_lut.size() == map_depth:
		var cy := clampf(y, 0.0, float(map_depth - 1))
		var y0 := int(floor(cy))
		var y1 := mini(map_depth - 1, y0 + 1)
		return lerpf(_right_wall_inner_lut[y0], _right_wall_inner_lut[y1], cy - float(y0))
	return _path_center_x(y) + 7.0


func _path_center_x(y: float) -> float:
	if _path_x_lut.size() == map_depth:
		var clamped_y := clampf(y, 0.0, float(map_depth - 1))
		var y0 := int(floor(clamped_y))
		var y1 := mini(map_depth - 1, y0 + 1)
		return lerpf(_path_x_lut[y0], _path_x_lut[y1], clamped_y - float(y0))
	return map_width * 0.5


func _seam_weight(y: float) -> float:
	var dist_to_end := minf(y, float(map_depth - 1) - y)
	return smoothstep(0.0, SEAM_NOISE_BLEND_ROWS, dist_to_end)


func _passage_narrow_factor(y: float) -> float:
	if section_index == 0 and y < float(map_depth) * 0.5:
		return 0.0
	var dist_to_end := minf(y, float(map_depth - 1) - y)
	return 1.0 - smoothstep(1.5, PASSAGE_BLEND_ROWS, dist_to_end)


func _sample_wall_noise(x: float, y: float) -> float:
	var w := _seam_weight(y)
	var local_n := (_noise_height.get_noise_2d(x, y) + 1.0) * 0.5
	var seam_n := (_noise_seam.get_noise_2d(x, 0.0) + 1.0) * 0.5
	return lerpf(seam_n, local_n, w)


func _populate_bezier_profile_data(data: LevelData) -> void:
	var count := map_depth + 1
	data.bezier_path_x.resize(count)
	data.bezier_trail_half_w.resize(count)
	data.bezier_left_wall_inner_x.resize(count)
	data.bezier_right_wall_inner_x.resize(count)
	data.bezier_left_wall_thick.resize(count)
	data.bezier_right_wall_thick.resize(count)
	data.bezier_left_wall_height.resize(count)
	data.bezier_right_wall_height.resize(count)
	data.bezier_floor_y.resize(count)

	var cx := float(map_width) * 0.5
	for i in range(count):
		var yf := clampf(float(i), 0.0, float(map_depth - 1))
		var y_idx := clampi(i, 0, map_depth - 1)
		var narrow := _passage_narrow_factor(yf)

		var px := _path_center_x(yf)
		var th := _trail_half_width_at_y(yf)
		var l_in := _left_wall_inner_x(yf)
		var r_in := _right_wall_inner_x(yf)
		var l_th := _left_wall_thick_lut[y_idx] if _left_wall_thick_lut.size() == map_depth else 4.5
		var r_th := _right_wall_thick_lut[y_idx] if _right_wall_thick_lut.size() == map_depth else 4.5

		if section_index == 0 and yf < SECTION_0_REGULAR_START_Y:
			var corridor_half := maxf(th, (r_in - l_in) * 0.5)
			var funnel_t := clampf((yf - SECTION_0_MOUTH_Y) / maxf(1.0, SECTION_0_REGULAR_START_Y - SECTION_0_MOUTH_Y), 0.0, 1.0)
			th = lerpf(corridor_half, th, smoothstep(0.0, 1.0, funnel_t))

		# Enforce exact seam values at section boundaries so adjacent sections weld seamlessly
		if i == map_depth or (i == 0 and section_index > 0):
			px = cx
			th = PASSAGE_HALF_WIDTH
			l_in = cx - PASSAGE_HALF_WIDTH
			r_in = cx + PASSAGE_HALF_WIDTH
			l_th = 4.5
			r_th = 4.5

		var nl := _sample_wall_noise(l_in - l_th * 0.5, yf)
		var nr := _sample_wall_noise(r_in + r_th * 0.5, yf)
		var ridge_l := absf(_noise_detail.get_noise_2d(l_in * 1.2, yf * 1.2)) * 1.0
		var ridge_r := absf(_noise_detail.get_noise_2d(r_in * 1.2, yf * 1.2)) * 1.0
		var h_l := clampf(lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, clampf(nl, 0.0, 1.0)) + ridge_l, WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE)
		var h_r := clampf(lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, clampf(nr, 0.0, 1.0)) + ridge_r, WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE)
		if i == map_depth or (i == 0 and section_index > 0):
			var seam_nl := (_noise_seam.get_noise_2d(l_in - 2.0, 0.0) + 1.0) * 0.5
			var seam_nr := (_noise_seam.get_noise_2d(r_in + 2.0, 0.0) + 1.0) * 0.5
			h_l = clampf(lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, seam_nl), WALL_MIN_HEIGHT_INCREASE + 1.8, WALL_MAX_HEIGHT_INCREASE)
			h_r = clampf(lerpf(WALL_MIN_HEIGHT_INCREASE, WALL_MAX_HEIGHT_INCREASE, seam_nr), WALL_MIN_HEIGHT_INCREASE + 1.8, WALL_MAX_HEIGHT_INCREASE)

		var floor_ripple := _noise_detail.get_noise_2d(px * 0.4, yf * 0.4) * (step_height * 0.25) * (1.0 - narrow)
		if i <= 2 or i >= map_depth - 2 or (section_index == 0 and yf <= SECTION_0_REGULAR_START_Y):
			floor_ripple = 0.0

		data.bezier_path_x[i] = px
		data.bezier_trail_half_w[i] = th
		data.bezier_left_wall_inner_x[i] = l_in
		data.bezier_right_wall_inner_x[i] = r_in
		data.bezier_left_wall_thick[i] = l_th
		data.bezier_right_wall_thick[i] = r_th
		data.bezier_left_wall_height[i] = h_l
		data.bezier_right_wall_height[i] = h_r
		data.bezier_floor_y[i] = 1.0 + floor_ripple


func _populate_connectors_and_spawns(data: LevelData) -> void:
	var entrance_y := 2 if section_index == 0 else 4
	var exit_y := maxi(entrance_y + 10, map_depth - 3)
	var center_start_x := int(round(_path_center_x(float(entrance_y))))
	var center_exit_x := int(round(_path_center_x(float(exit_y))))
	var start_pos := Vector2i(center_start_x, entrance_y)
	var main_exit_pos := Vector2i(center_exit_x, exit_y)

	data.entrances["start"] = start_pos

	# Cave entrance cut out directly in the left (-1) or right (+1) valley wall
	var min_cave_y := 24 if section_index == 0 else 12
	var cave_y := clampi(int(round(map_depth * 0.56 if section_index == 0 else map_depth * 0.5)), min_cave_y, maxi(min_cave_y, map_depth - 13))
	var cave_side := -1 if (_rng.randi() % 2 == 0) else 1
	var wall_inner_at_cave := _right_wall_inner_x(float(cave_y)) if cave_side > 0 else _left_wall_inner_x(float(cave_y))
	var side_exit_x := clampi(int(round(wall_inner_at_cave)), 8, map_width - 9)
	var side_exit_pos := Vector2i(side_exit_x, cave_y)

	var branch_start_y := clampf(float(cave_y) - 6.0, 8.0, float(map_depth - 9))
	_setup_cave_branch_bezier(branch_start_y, Vector2(float(side_exit_pos.x), float(side_exit_pos.y)), cave_side)

	var return_x := clampi(side_exit_pos.x - cave_side * 4, 4, map_width - 5)
	var return_id := "from_sidequest_%d" % section_index
	data.entrances["from_sidequest"] = Vector2i(return_x, cave_y)
	data.entrances[return_id] = Vector2i(return_x, cave_y)

	var main_exit := LevelExitData.new()
	main_exit.id = "exit_main"
	main_exit.grid_pos = main_exit_pos
	main_exit.label = "Next Area"
	main_exit.color = Color(0.3, 0.8, 1.0)
	data.exits.append(main_exit)

	var side_exit := LevelExitData.new()
	side_exit.id = "exit_sidequest"
	side_exit.grid_pos = side_exit_pos
	side_exit.target_level_path = "sidequest://random"
	side_exit.target_entrance_id = return_id
	side_exit.label = "Side Quest Cave"
	side_exit.color = Color(0.35, 0.85, 0.45)
	side_exit.is_cave_entrance = true
	side_exit.cave_side = cave_side
	data.exits.append(side_exit)

	# Weapon spawns
	var min_weap_y := int(SECTION_0_REGULAR_START_Y + 4.0) if section_index == 0 else 6
	var weapon_y := clampi(int(round(map_depth * 0.42 if section_index == 0 else map_depth * 0.3)), min_weap_y, map_depth - 10)
	data.weapon_spawns.append({
		"id": "relic_blade_%d" % section_index,
		"type": "ancient_blade",
		"pos": Vector2i(clampi(int(round(_path_center_x(float(weapon_y)))) + 3, 4, map_width - 5), weapon_y),
		"respawn": false
	})
	if section_index == 0:
		var practice_pos := Vector2i(clampi(int(round(map_width * 0.5 + 8.0)), 8, map_width - 9), 5)
		data.weapon_spawns.append({
			"id": "practice_slingshot_0",
			"type": "sun_pendant",
			"pos": practice_pos,
			"respawn": false
		})
	else:
		data.weapon_spawns.append({
			"id": "sacred_relic_%d" % section_index,
			"type": "sun_pendant",
			"pos": Vector2i(clampi(side_exit_pos.x - cave_side * 3, 4, map_width - 5), clampi(cave_y - 2, 4, map_depth - 5)),
			"respawn": false
		})

	# Enemy guard zone near the narrow exit chokepoint where the valley walls close in
	var ring_top := main_exit_pos.y - GATE_RING_RADIUS
	var gap: Array[Vector2i] = []
	for x in range(main_exit_pos.x - GATE_HALF_WIDTH, main_exit_pos.x + GATE_HALF_WIDTH + 1):
		gap.append(Vector2i(x, ring_top))
	var guard_pos := Vector2i(main_exit_pos.x, ring_top - GUARD_SETBACK)
	data.enemy_guard_zones.append({
		"id": "valley_guardian",
		"enemy_type": "shadow_sentinel",
		"guard_pos": guard_pos,
		"guard_radius": 5.5,
		"blocks_path": true,
		"barrier_cells": gap
	})


func _setup_cave_branch_bezier(branch_start_y: float, cave_pos: Vector2, cave_side: int) -> void:
	_branch_curve.clear_points()
	_branch_curve.bake_interval = 0.25
	var p0 := Vector2(_path_center_x(branch_start_y), branch_start_y)
	var span_x := absf(cave_pos.x - p0.x)
	var dy := cave_pos.y - p0.y
	var mid := Vector2(
		lerpf(p0.x, cave_pos.x, 0.5),
		lerpf(p0.y, cave_pos.y, 0.55)
	)
	_branch_curve.add_point(p0, Vector2.ZERO, Vector2(float(cave_side) * span_x * 0.25, dy * 0.45))
	_branch_curve.add_point(
		mid,
		Vector2(-float(cave_side) * span_x * 0.22, -dy * 0.2),
		Vector2(float(cave_side) * span_x * 0.22, dy * 0.2)
	)
	_branch_curve.add_point(cave_pos, Vector2(-float(cave_side) * span_x * 0.35, 0.0), Vector2.ZERO)
