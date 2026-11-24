class_name HoleGenerator
extends RefCounted
## Builds a random but fair par 3 from a seed.
##
## Layout (target is -Z): tee at the origin, pin `distance` metres away within
## a few degrees of straight. A green of random size/shape with gentle tilt
## and undulation, a fringe, an approach strip, 1-4 greenside bunkers, an
## occasional pond (front or side), tree lines, wind and green firmness.
## Each hole is checked and regenerated (next sub-seed) if it is unfair.

const MIN_DIST := 70.0
const MAX_DIST := 200.0
const MAX_PIN_SLOPE := 0.03
const MAX_ATTEMPTS := 20


static func generate(seed_value: int) -> HoleData:
	for attempt in MAX_ATTEMPTS:
		var hole := _try_generate(seed_value, attempt)
		if validate(hole).is_empty():
			return hole
	# Last resort: the same layout without hazards is always fair.
	return _try_generate(seed_value, 0, true)


## Returns a list of problems (empty = fair hole).
static func validate(hole: HoleData) -> Array[String]:
	var problems: Array[String] = []
	if hole.distance < MIN_DIST - 0.5 or hole.distance > MAX_DIST + 0.5:
		problems.append("distance %.1f out of range" % hole.distance)
	if hole.get_surface(hole.pin.x, hole.pin.z) != Surface.GREEN:
		problems.append("pin not on green")
	if hole.slope_at(hole.pin.x, hole.pin.z) > MAX_PIN_SLOPE:
		problems.append("pin slope %.3f too steep" % hole.slope_at(hole.pin.x, hole.pin.z))
	# Area around the pin must be green and not too steep (a fair landing).
	for a in 8:
		var off := Vector2.from_angle(a * TAU / 8.0) * 2.5
		var p := Vector2(hole.pin.x, hole.pin.z) + off
		if hole.get_surface(p.x, p.y) != Surface.GREEN:
			problems.append("pin too close to green edge")
			break
	if hole.get_surface(hole.tee.x, hole.tee.z) != Surface.TEE:
		problems.append("tee not on tee box")
	for t in hole.trees:
		var tp: Vector3 = t["pos"]
		# No tree may overhang the line from tee to pin.
		var line := Vector2(hole.pin.x, hole.pin.z)
		var q := Geometry2D.get_closest_point_to_segment(Vector2(tp.x, tp.z), Vector2.ZERO, line)
		if q.distance_to(Vector2(tp.x, tp.z)) < t["r"] + 12.0:
			problems.append("tree blocks the line")
			break
	return problems


static func _try_generate(seed_value: int, attempt: int, no_hazards := false) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, attempt])
	var hole := HoleData.new()
	hole.seed_value = seed_value
	hole.distance = snappedf(rng.randf_range(MIN_DIST, MAX_DIST), 0.1)
	var yaw := deg_to_rad(rng.randf_range(-6.0, 6.0))
	var pin2 := Vector2(sin(yaw), -cos(yaw)) * hole.distance
	hole.elevation = rng.randf_range(-12.0, 6.0) * clampf(hole.distance / 120.0, 0.4, 1.0)

	# --- Green: random size, shape and orientation, offset so the pin isn't central.
	var depth := rng.randf_range(11.0, 17.0)
	var width := rng.randf_range(9.0, 15.0)
	var g_rot := yaw + rng.randf_range(-0.45, 0.45)
	var pin_off := Vector2(rng.randf_range(-0.45, 0.45) * width, rng.randf_range(-0.45, 0.45) * depth).rotated(g_rot)
	hole.green = Blob.new(pin2 - pin_off, Vector2(width, depth), g_rot, rng, 0.10)

	# --- Approach strip in front of the green.
	var fwd := Vector2(sin(yaw), -cos(yaw))
	var front := hole.green.center - fwd * (depth * 0.9)
	hole.approach_end = front
	var app_len := clampf(rng.randf_range(10.0, 35.0), 0.0, hole.distance - 40.0)
	hole.approach_start = front - fwd * app_len
	hole.approach_half_width = width * rng.randf_range(0.6, 0.9)

	# --- Pond.
	if not no_hazards and rng.randf() < 0.4:
		var kind := rng.randi_range(0, 2) # 0 front, 1 left, 2 right
		if kind == 0 and hole.distance > 105.0:
			var back_edge := depth + hole.green.mean_radius() * 0.25 + rng.randf_range(4.0, 10.0)
			var pz := rng.randf_range(8.0, 14.0)
			var c := hole.green.center - fwd * (back_edge + pz)
			hole.pond = Blob.new(c, Vector2(rng.randf_range(22.0, 40.0), pz), yaw + rng.randf_range(-0.2, 0.2), rng, 0.12)
			hole.approach_start = hole.approach_end # no approach strip through water
		elif kind != 0:
			var side := -1.0 if kind == 1 else 1.0
			var px := rng.randf_range(8.0, 16.0)
			var right := Vector2(cos(yaw), sin(yaw))
			var c2 := hole.green.center + right * side * (width + px + rng.randf_range(3.0, 7.0)) - fwd * rng.randf_range(0.0, 15.0)
			hole.pond = Blob.new(c2, Vector2(px, rng.randf_range(20.0, 32.0)), yaw, rng, 0.12)

	# --- Bunkers around the green (slots relative to the line of play).
	if not no_hazards:
		var slots := [-150.0, 150.0, -100.0, 100.0, -60.0, 60.0, 0.0, 180.0]
		var n_bunkers := rng.randi_range(1, 4)
		for i in n_bunkers:
			if slots.is_empty():
				break
			var si := rng.randi_range(0, slots.size() - 1)
			var ang_deg: float = slots[si]
			slots.remove_at(si)
			var br := Vector2(rng.randf_range(3.0, 7.0), rng.randf_range(2.5, 4.5))
			var dir := fwd.rotated(deg_to_rad(ang_deg + 180.0)) # 0 = short of the green, 180 = long
			# Push out until clear of the green + fringe.
			var c3 := hole.green.center
			var b := Blob.new(c3, br, dir.angle() + PI * 0.5, rng, 0.15)
			for step in 60:
				b.center = hole.green.center + dir * (step * 1.0)
				if hole.green.signed_dist(b.center) > b.mean_radius() * 1.15 + hole.fringe_width + 1.0:
					break
			b.bbox = Rect2(b.center - Vector2.ONE * maxf(br.x, br.y) * 1.5, Vector2.ONE * maxf(br.x, br.y) * 3.0)
			if hole.pond != null and b.overlaps(hole.pond, 2.0):
				continue
			hole.bunkers.append(b)
		# Occasionally a bunker short of the green on longer holes.
		if hole.distance > 140.0 and rng.randf() < 0.3:
			var c4 := hole.green.center - fwd * rng.randf_range(30.0, 45.0) + Vector2(cos(yaw), sin(yaw)) * rng.randf_range(-12.0, 12.0)
			var fb := Blob.new(c4, Vector2(rng.randf_range(4.0, 8.0), rng.randf_range(3.0, 5.0)), yaw, rng, 0.15)
			if hole.pond == null or not fb.overlaps(hole.pond, 2.0):
				hole.bunkers.append(fb)

	# --- Conditions.
	var wind_speed := 9.0 * pow(rng.randf(), 1.6)
	var wind_dir := rng.randf_range(0.0, TAU)
	hole.wind_10m = Vector3(cos(wind_dir), 0.0, sin(wind_dir)) * wind_speed
	hole.green_softness = rng.randf_range(0.65, 1.25)

	hole.pin = Vector3(pin2.x, 0.0, pin2.y)
	_build_grids(hole, rng, pin2, fwd)

	hole.tee = Vector3(0.0, hole.get_height(0.0, 0.0), 0.0)
	hole.pin = Vector3(pin2.x, hole.get_height(pin2.x, pin2.y), pin2.y)
	hole.elevation = hole.pin.y - hole.tee.y
	_place_trees(hole, rng, fwd)
	return hole


static func _build_grids(hole: HoleData, rng: RandomNumberGenerator, pin2: Vector2, fwd: Vector2) -> void:
	var half_w := 55.0 + hole.distance * 0.18
	var z_min := minf(pin2.y, hole.green.center.y) - 55.0
	var z_max := 25.0
	hole.origin = Vector2(-half_w + pin2.x * 0.5, z_min)
	hole.hw = int(ceil(half_w * 2.0 / HoleData.HEIGHT_CELL)) + 1
	hole.hh = int(ceil((z_max - z_min) / HoleData.HEIGHT_CELL)) + 1
	hole.sw = int(ceil(half_w * 2.0 / HoleData.SURF_CELL)) + 1
	hole.sh = int(ceil((z_max - z_min) / HoleData.SURF_CELL)) + 1

	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var green_noise := FastNoiseLite.new()
	green_noise.seed = rng.randi()
	green_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	green_noise.frequency = 0.045
	green_noise.fractal_octaves = 1
	var rough_amp := rng.randf_range(1.5, 3.5)
	var green_tilt := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.006, 0.022)
	var green_und := rng.randf_range(0.10, 0.28)
	var green_raise := rng.randf_range(0.2, 1.2)
	var green_c := hole.green.center
	var green_level := hole.elevation + green_raise
	var tee_level := 0.4

	# Water level: below the natural ground all around the pond's edge.
	if hole.pond != null:
		var lowest := 1e9
		for i in 32:
			var a := i * TAU / 32.0
			var p := hole.pond.center + Vector2(cos(a) * hole.pond.radii.x * 1.3, sin(a) * hole.pond.radii.y * 1.3).rotated(hole.pond.rotation)
			lowest = minf(lowest, _natural(p, hole, noise, rough_amp))
		hole.water_level = lowest - 0.35

	hole.heights.resize(hole.hw * hole.hh)
	for iz in hole.hh:
		var z := hole.origin.y + iz * HoleData.HEIGHT_CELL
		for ix in hole.hw:
			var x := hole.origin.x + ix * HoleData.HEIGHT_CELL
			var p := Vector2(x, z)
			var h := _natural(p, hole, noise, rough_amp)
			# Tee box: flat pad.
			var tee_d := maxf(absf(x) - 5.0, absf(z) - 4.0)
			h = lerpf(tee_level, h, smoothstep(0.0, 6.0, tee_d))
			# Green: tilted, gently rolling surface blended into its surrounds.
			var gd := hole.green.signed_dist(p) if hole.green.bbox.grow(12.0).has_point(p) else 99.0
			if gd < 10.0:
				var gp := p - green_c
				var gh := green_level + gp.dot(green_tilt) + green_noise.get_noise_2d(x, z) * green_und
				h = lerpf(gh, h, smoothstep(hole.fringe_width, 9.0, gd))
			# Bunkers: depressions with a lip.
			for b in hole.bunkers:
				if not b.bbox.grow(2.0).has_point(p):
					continue
				var bd := b.signed_dist(p)
				h -= 0.75 * (1.0 - smoothstep(-2.0, 0.6, bd))
				h += 0.15 * (1.0 - smoothstep(0.0, 1.5, absf(bd - 0.6)))
			# Pond bed.
			if hole.pond != null and hole.pond.bbox.grow(8.0).has_point(p):
				var pd := hole.pond.signed_dist(p)
				var bed := hole.water_level - 1.2 * (1.0 - smoothstep(-6.0, 0.0, pd)) - 0.25
				h = lerpf(bed, h, smoothstep(-0.5, 5.0, pd))
			hole.heights[iz * hole.hw + ix] = h
	hole.compute_normals()

	hole.surfaces.resize(hole.sw * hole.sh)
	for iz in hole.sh:
		var z := hole.origin.y + iz * HoleData.SURF_CELL
		for ix in hole.sw:
			var x := hole.origin.x + ix * HoleData.SURF_CELL
			hole.surfaces[iz * hole.sw + ix] = _classify(hole, Vector2(x, z))


## Natural rolling ground: a ramp from tee level to green level plus noise
## (quieter near the line of play).
static func _natural(p: Vector2, hole: HoleData, noise: FastNoiseLite, amp: float) -> float:
	var t := clampf(-p.y / maxf(hole.distance, 1.0), 0.0, 1.2)
	var base := lerpf(0.0, hole.elevation, smoothstep(0.1, 0.85, t))
	var lateral := absf(p.x - (-p.y) * hole.pin.x / maxf(-hole.pin.z, 1.0)) if hole.pin.z < -1.0 else absf(p.x)
	var quiet := lerpf(0.45, 1.0, smoothstep(10.0, 40.0, lateral))
	return base + noise.get_noise_2d(p.x, p.y) * amp * quiet


static func _classify(hole: HoleData, p: Vector2) -> int:
	if hole.pond != null and hole.pond.contains(p):
		return Surface.WATER
	for b in hole.bunkers:
		if b.contains(p):
			return Surface.BUNKER
	if hole.green.bbox.grow(hole.fringe_width + 1.0).has_point(p):
		var gd := hole.green.signed_dist(p)
		if gd < 0.0:
			return Surface.GREEN
		if gd < hole.fringe_width:
			return Surface.FRINGE
	if absf(p.x) < 5.0 and absf(p.y) < 4.0:
		return Surface.TEE
	if hole.approach_start != hole.approach_end:
		var q := Geometry2D.get_closest_point_to_segment(p, hole.approach_start, hole.approach_end)
		if q.distance_to(p) < hole.approach_half_width:
			return Surface.FAIRWAY
	return Surface.ROUGH


static func _place_trees(hole: HoleData, rng: RandomNumberGenerator, fwd: Vector2) -> void:
	var right := Vector2(-fwd.y, fwd.x)
	var length := hole.distance + 40.0
	var corridor := 32.0 + hole.distance * 0.08
	var s := 15.0
	while s < length:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.25:
				continue
			var off: float = side * (corridor + rng.randf_range(0.0, 18.0) + s * 0.06)
			var p := fwd * s + right * off
			_add_tree(hole, rng, p)
		s += rng.randf_range(7.0, 14.0)
	# A few behind the green.
	for i in rng.randi_range(3, 7):
		var p2 := hole.green.center + fwd * rng.randf_range(32.0, 48.0) + right * rng.randf_range(-35.0, 35.0)
		_add_tree(hole, rng, p2)


static func _add_tree(hole: HoleData, rng: RandomNumberGenerator, p: Vector2) -> void:
	var size_m := hole.size_m()
	if p.x < hole.origin.x + 3.0 or p.x > hole.origin.x + size_m.x - 3.0 or p.y < hole.origin.y + 3.0 or p.y > 20.0:
		return
	var surf := hole.get_surface(p.x, p.y)
	if surf != Surface.ROUGH:
		return
	if hole.green.signed_dist(p) < 14.0:
		return
	var r := rng.randf_range(2.8, 5.0)
	var on_line := Geometry2D.get_closest_point_to_segment(p, Vector2.ZERO, Vector2(hole.pin.x, hole.pin.z))
	if on_line.distance_to(p) < r + 13.0:
		return
	var trunk_h := rng.randf_range(3.0, 6.0)
	var ground := hole.get_height(p.x, p.y)
	hole.trees.append({"pos": Vector3(p.x, ground + trunk_h + r * 0.8, p.y), "r": r, "base": Vector3(p.x, ground, p.y), "trunk": trunk_h})
