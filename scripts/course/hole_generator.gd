class_name HoleGenerator
extends RefCounted
## Builds a random but fair short wedge hole from a seed.
##
## Layout (target is -Z): tee at the origin, pin `distance` metres away within
## a few degrees of straight. A small green (sometimes tiered or with a
## backstop), fringe, approach strip, greenside bunkers, an occasional pond,
## and 0-2 "puzzle" features you have to work the ball over, under or around:
## a guarding tree, a tree with high branches, a hedge, a stone wall, or a
## pair of trees. Every hole is test-played with the ShotPlanner and only kept
## if some shot (club x height x curve) lands at the pin without hitting
## anything. Wind and green firmness vary per hole.

const MIN_DIST := 30.0
const MAX_DIST := 100.0
enum Feature { GUARD_TREE, HIGH_TREE, HEDGE, WALL, TREE_GATE }
const FEATURE_NAMES := ["Guarding tree", "High branches", "Hedge", "Stone wall", "Tree gate"]
const MAX_PIN_SLOPE := 0.03
const MAX_ATTEMPTS := 20


static func generate(seed_value: int) -> HoleData:
	for attempt in MAX_ATTEMPTS:
		var hole := _try_generate(seed_value, attempt)
		if validate(hole).is_empty() and find_route(hole) != null:
			return hole
	# Last resort: the same layout without hazards is always fair.
	return _try_generate(seed_value, 0, true)


## Test-plays the hole: tries shots from the most ordinary to the most
## creative and returns the first that lands at the pin without touching an
## obstacle (or null if none does).
static func find_route(hole: HoleData) -> ShotPlanner.Shot:
	var start := hole.tee + Vector3(0, BallSim.RADIUS + 0.012, 0)
	var heights := [1, 2, 0, 3]
	var curves := [0.0, -0.8, 0.8]
	for h in heights:
		for c in curves:
			for club in [1, 0, 2]:
				var shot := ShotPlanner.Shot.new()
				shot.club_idx = club
				shot.height_idx = h
				shot.curve = c
				var plan := ShotPlanner.solve(hole, start, hole.pin, shot)
				if plan.too_far or plan.too_short or plan.blocked:
					continue
				if Vector2(plan.landing.x - hole.pin.x, plan.landing.z - hole.pin.z).length() > 1.0:
					continue
				return shot
	return null


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
	for o in hole.obstacles:
		var c: Vector3 = o.get("center", o.get("base", Vector3.ZERO))
		if Vector2(c.x, c.z).length() < 9.0:
			problems.append("obstacle too close to the tee")
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
	hole.elevation = rng.randf_range(-5.0, 3.0) * clampf(hole.distance / 80.0, 0.4, 1.0)

	# --- Green: random size, shape and orientation, offset so the pin isn't central.
	var depth := rng.randf_range(8.0, 13.0)
	var width := rng.randf_range(7.0, 12.0)
	var g_rot := yaw + rng.randf_range(-0.45, 0.45)
	var pin_off := Vector2(rng.randf_range(-0.45, 0.45) * width, rng.randf_range(-0.45, 0.45) * depth).rotated(g_rot)
	hole.green = Blob.new(pin2 - pin_off, Vector2(width, depth), g_rot, rng, 0.10)

	# --- Approach strip in front of the green.
	var fwd := Vector2(sin(yaw), -cos(yaw))
	var front := hole.green.center - fwd * (depth * 0.9)
	hole.approach_end = front
	var app_len := clampf(rng.randf_range(6.0, 22.0), 0.0, hole.distance - 22.0)
	hole.approach_start = front - fwd * app_len
	hole.approach_half_width = width * rng.randf_range(0.6, 0.9)

	# --- Pond.
	if not no_hazards and rng.randf() < 0.4:
		var kind := rng.randi_range(0, 2) # 0 front, 1 left, 2 right
		if kind == 0 and hole.distance > 50.0:
			var back_edge := depth + hole.green.mean_radius() * 0.25 + rng.randf_range(3.0, 7.0)
			var pz := rng.randf_range(5.0, 9.0)
			var c := hole.green.center - fwd * (back_edge + pz)
			hole.pond = Blob.new(c, Vector2(rng.randf_range(16.0, 28.0), pz), yaw + rng.randf_range(-0.2, 0.2), rng, 0.12)
			hole.approach_start = hole.approach_end # no approach strip through water
		elif kind != 0:
			var side := -1.0 if kind == 1 else 1.0
			var px := rng.randf_range(6.0, 11.0)
			var right := Vector2(cos(yaw), sin(yaw))
			var c2 := hole.green.center + right * side * (width + px + rng.randf_range(3.0, 6.0)) - fwd * rng.randf_range(0.0, 10.0)
			hole.pond = Blob.new(c2, Vector2(px, rng.randf_range(14.0, 22.0)), yaw, rng, 0.12)

	# --- Bunkers around the green (slots relative to the line of play).
	if not no_hazards:
		var slots := [-150.0, 150.0, -100.0, 100.0, -60.0, 60.0, 0.0, 180.0]
		var n_bunkers := rng.randi_range(1, 3)
		for i in n_bunkers:
			if slots.is_empty():
				break
			var si := rng.randi_range(0, slots.size() - 1)
			var ang_deg: float = slots[si]
			slots.remove_at(si)
			var br := Vector2(rng.randf_range(2.5, 5.5), rng.randf_range(2.0, 3.5))
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

	# --- Conditions.
	var wind_speed := 7.0 * pow(rng.randf(), 1.6)
	var wind_dir := rng.randf_range(0.0, TAU)
	hole.wind_10m = Vector3(cos(wind_dir), 0.0, sin(wind_dir)) * wind_speed
	hole.green_softness = rng.randf_range(0.65, 1.25)

	hole.pin = Vector3(pin2.x, 0.0, pin2.y)
	_build_grids(hole, rng, pin2, fwd)

	hole.tee = Vector3(0.0, hole.get_height(0.0, 0.0), 0.0)
	hole.pin = Vector3(pin2.x, hole.get_height(pin2.x, pin2.y), pin2.y)
	hole.elevation = hole.pin.y - hole.tee.y
	# The flagstick: the ball can hit it (a landing on the pin is knocked
	# away rather than dunked; a slow one can still drop).
	hole.obstacles.append({"kind": GolfTerrain.PIN, "base": hole.pin, "h": 2.2, "r": 0.0125})
	_place_trees(hole, rng, fwd)
	if not no_hazards:
		_place_features(hole, rng, fwd)
	return hole


static func _build_grids(hole: HoleData, rng: RandomNumberGenerator, pin2: Vector2, fwd: Vector2) -> void:
	var half_w := 42.0 + hole.distance * 0.15
	var z_min := minf(pin2.y, hole.green.center.y) - 40.0
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
	var green_tilt := Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(0.008, 0.028)
	# Green character: 0 plain, 1 two tiers, 2 backstop (rises at the back).
	var green_kind := rng.randi_range(0, 2) if rng.randf() < 0.6 else 0
	var tier_dir := Vector2.from_angle(rng.randf_range(0.0, TAU))
	var tier_off := rng.randf_range(-2.5, 2.5)
	var tier_h := rng.randf_range(0.35, 0.7)
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
				if green_kind == 1:
					gh += tier_h * smoothstep(-1.2, 1.2, gp.dot(tier_dir) - tier_off)
				elif green_kind == 2:
					var back := gp.dot(fwd) - hole.green.radii.y * 0.45
					gh += 0.9 * smoothstep(0.0, 4.0, back) * smoothstep(0.0, 4.0, back)
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
	hole.surface_fields.resize(hole.sw * hole.sh * 4)
	for iz in hole.sh:
		var z := hole.origin.y + iz * HoleData.SURF_CELL
		for ix in hole.sw:
			var x := hole.origin.x + ix * HoleData.SURF_CELL
			var i := iz * hole.sw + ix
			hole.surfaces[i] = _classify(hole, Vector2(x, z))
			_fields(hole, Vector2(x, z), i * 4)


## Natural rolling ground: a ramp from tee level to green level plus noise
## (quieter near the line of play).
static func _natural(p: Vector2, hole: HoleData, noise: FastNoiseLite, amp: float) -> float:
	var t := clampf(-p.y / maxf(hole.distance, 1.0), 0.0, 1.2)
	var base := lerpf(0.0, hole.elevation, smoothstep(0.1, 0.85, t))
	var lateral := absf(p.x - (-p.y) * hole.pin.x / maxf(-hole.pin.z, 1.0)) if hole.pin.z < -1.0 else absf(p.x)
	var quiet := lerpf(0.45, 1.0, smoothstep(10.0, 40.0, lateral))
	return base + noise.get_noise_2d(p.x, p.y) * amp * quiet


static func _classify(hole: HoleData, p: Vector2) -> int:
	if hole.pond != null and hole.pond.bbox.grow(8.0).has_point(p):
		# Water is wherever the ground dips below the pond's surface, so the
		# drawn water and the physics always agree.
		if hole.get_height(p.x, p.y) < hole.water_level:
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


## Rendering fields: smooth distance-based values (not hard IDs) so the
## shader can draw clean, anti-aliased edges with bilinear filtering.
## Each channel crosses its threshold exactly on the physics boundary:
##   R green/fringe: 0.6 at the green edge, 0.312 at the fringe edge
##   G fairway/tee:  0.5 at the edge
##   B bunker:       0.5 at the edge
##   A water:        0.5 at the waterline
static func _fields(hole: HoleData, p: Vector2, o: int) -> void:
	var r := 0.0
	if hole.green.bbox.grow(hole.fringe_width + 4.0).has_point(p):
		r = clampf(0.6 - hole.green.signed_dist(p) * 0.18, 0.0, 1.0)
	var fd := maxf(absf(p.x) - 5.0, absf(p.y) - 4.0)
	if hole.approach_start != hole.approach_end:
		var q := Geometry2D.get_closest_point_to_segment(p, hole.approach_start, hole.approach_end)
		fd = minf(fd, q.distance_to(p) - hole.approach_half_width)
	var g := clampf(0.5 - fd * 0.25, 0.0, 1.0)
	var bd := 99.0
	for b in hole.bunkers:
		if b.bbox.grow(3.0).has_point(p):
			bd = minf(bd, b.signed_dist(p))
	var bl := clampf(0.5 - bd * 0.25, 0.0, 1.0)
	var a := 0.0
	if hole.pond != null and hole.pond.bbox.grow(8.0).has_point(p):
		a = clampf(0.5 + (hole.water_level - hole.get_height(p.x, p.y)) * 1.5, 0.0, 1.0)
	hole.surface_fields[o] = int(r * 255.0)
	hole.surface_fields[o + 1] = int(g * 255.0)
	hole.surface_fields[o + 2] = int(bl * 255.0)
	hole.surface_fields[o + 3] = int(a * 255.0)


static func _place_trees(hole: HoleData, rng: RandomNumberGenerator, fwd: Vector2) -> void:
	var right := Vector2(-fwd.y, fwd.x)
	var length := hole.distance + 30.0
	var corridor := 24.0 + hole.distance * 0.08
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
	if hole.green.signed_dist(p) < 12.0:
		return
	var r := rng.randf_range(2.8, 5.0)
	var on_line := Geometry2D.get_closest_point_to_segment(p, Vector2.ZERO, Vector2(hole.pin.x, hole.pin.z))
	if on_line.distance_to(p) < r + 13.0:
		return
	add_tree(hole, p, r, rng.randf_range(3.0, 6.0))


## A tree that's also an obstacle: a solid trunk and a soft canopy.
## `trunk_h` is the height of the bottom of the canopy.
static func add_tree(hole: HoleData, p: Vector2, r: float, trunk_h: float) -> void:
	var ground := hole.get_height(p.x, p.y)
	var center := Vector3(p.x, ground + trunk_h + r * 0.8, p.y)
	hole.trees.append({"pos": center, "r": r, "base": Vector3(p.x, ground, p.y), "trunk": trunk_h})
	hole.obstacles.append({"kind": GolfTerrain.CANOPY, "center": center, "r": r})
	hole.obstacles.append({"kind": GolfTerrain.TRUNK, "base": Vector3(p.x, ground, p.y), "h": trunk_h + r * 0.5, "r": 0.22 + r * 0.03})


## The ordinary shot (55 degree, normal height, straight) to the pin, flown
## without obstacles. Features are placed on its path so it doesn't work.
static func _ordinary_path(hole: HoleData) -> PackedVector3Array:
	var shot := ShotPlanner.Shot.new()
	shot.club_idx = 1
	var saved := hole.obstacles
	hole.obstacles = []
	var plan := ShotPlanner.solve(hole, hole.tee + Vector3(0, BallSim.RADIUS + 0.012, 0), hole.pin, shot)
	hole.obstacles = saved
	return plan.path


## Point on a flight path at a fraction of the way to the pin (horizontally).
static func _along(path: PackedVector3Array, hole: HoleData, frac: float) -> Vector3:
	var want := hole.distance * frac
	for i in path.size():
		if Vector2(path[i].x - hole.tee.x, path[i].z - hole.tee.z).length() >= want:
			return path[i]
	return path[path.size() - 1]


## The puzzle: 0-2 features that stop the ordinary shot from working.
static func _place_features(hole: HoleData, rng: RandomNumberGenerator, fwd: Vector2) -> void:
	var right := Vector2(-fwd.y, fwd.x)
	var roll := rng.randf()
	var count := 0 if roll < 0.1 else (1 if roll < 0.72 else 2)
	if count == 0:
		return
	# Shuffle with the hole's own RNG so a seed always gives the same hole.
	var kinds := range(Feature.size())
	for i in range(kinds.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	var path := _ordinary_path(hole)
	var front := hole.green.center - fwd * (hole.green.radii.y + hole.fringe_width)
	var front_d := front.length() # tee to the front of the green
	for k in count:
		var kind: int = kinds[k]
		hole.features.append(kind)
		match kind:
			Feature.GUARD_TREE:
				# Canopy right where the ordinary shot flies: go over it, curve
				# around it, or (if it's high enough) under it.
				var bp := _along(path, hole, rng.randf_range(0.35, 0.6))
				var r := rng.randf_range(2.5, 3.8)
				var g := hole.get_height(bp.x, bp.z)
				var trunk := maxf(1.2, bp.y - g - r * 0.8 + rng.randf_range(-1.0, 1.0))
				var p := Vector2(bp.x, bp.z) + right * rng.randf_range(-1.0, 1.0)
				add_tree(hole, p, r, trunk)
			Feature.HIGH_TREE:
				# Low branches cross the ordinary flight; there's room under them
				# for a punch.
				var bp2 := _along(path, hole, rng.randf_range(0.3, 0.5))
				var g2 := hole.get_height(bp2.x, bp2.z)
				var r2 := rng.randf_range(3.5, 5.0)
				var trunk2 := clampf(bp2.y - g2 - r2 * 0.4, 3.0, 7.0)
				add_tree(hole, Vector2(bp2.x, bp2.z), r2, trunk2)
			Feature.HEDGE:
				# A row of bushes just short of the green: no bump-and-run.
				var d := clampf(front_d - rng.randf_range(2.0, 6.0), 10.0, hole.distance - 5.0)
				var c := fwd * d
				var half := rng.randf_range(6.0, 11.0)
				var br := rng.randf_range(0.8, 1.2)
				var x := -half
				while x <= half:
					var q := c + right * x
					var gq := hole.get_height(q.x, q.y)
					hole.obstacles.append({"kind": GolfTerrain.BUSH, "center": Vector3(q.x, gq + br * 0.75, q.y), "r": br})
					hole.bushes.append(Vector4(q.x, gq + br * 0.75, q.y, br))
					x += br * 1.5
			Feature.WALL:
				# A dry-stone wall across the approach.
				var d2 := clampf(front_d - rng.randf_range(2.0, 8.0), 10.0, hole.distance - 5.0)
				var c2 := fwd * d2 + right * rng.randf_range(-3.0, 3.0)
				var gw := hole.get_height(c2.x, c2.y)
				var h := rng.randf_range(0.9, 1.5)
				var half_len := rng.randf_range(9.0, 16.0)
				# The wall's local +X runs across the line of play (BallSim
				# maps local X to world (cos yaw, 0, -sin yaw)).
				var wyaw := atan2(-right.y, right.x) + rng.randf_range(-0.3, 0.3)
				var w := {"kind": GolfTerrain.WALL, "center": Vector3(c2.x, gw + h * 0.5 - 0.15, c2.y), "half": Vector3(half_len, h * 0.5 + 0.15, 0.3), "yaw": wyaw}
				hole.obstacles.append(w)
				hole.walls.append(w)
			Feature.TREE_GATE:
				# Two trees with the gap off to one side of the line: curve the
				# ball through it, or go over.
				var bp3 := _along(path, hole, rng.randf_range(0.35, 0.55))
				var gap := rng.randf_range(2.5, 3.5)
				var side := -1.0 if rng.randf() < 0.5 else 1.0
				var gap_c := Vector2(bp3.x, bp3.z) + right * side * rng.randf_range(3.5, 5.0)
				for sgn in [-1.0, 1.0]:
					var r4 := rng.randf_range(2.5, 3.3)
					var g4 := hole.get_height(gap_c.x, gap_c.y)
					add_tree(hole, gap_c + right * sgn * (gap + r4), r4, maxf(1.5, bp3.y - g4 - r4 * 0.6))
