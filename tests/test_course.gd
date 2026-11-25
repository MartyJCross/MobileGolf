extends "res://tests/test_base.gd"
## Hole generator tests.

const SEEDS := 60


func test_holes_are_fair_across_many_seeds() -> void:
	var t0 := Time.get_ticks_msec()
	for s in SEEDS:
		var hole := HoleGenerator.generate(s * 7919 + 13)
		var problems := HoleGenerator.validate(hole)
		check(problems.is_empty(), "seed %d: %s" % [s, problems])
		check(hole.distance >= 30.0 and hole.distance <= 100.0, "seed %d distance" % s)
		check(HoleGenerator.find_route(hole) != null, "seed %d has a playable route" % s)
		near(hole.dist_to_pin(hole.tee), hole.distance, 0.05, "seed %d tee-to-pin" % s)
	var ms := Time.get_ticks_msec() - t0
	print("         (%d holes in %d ms, %.0f ms each)" % [SEEDS, ms, float(ms) / SEEDS])


func test_same_seed_same_hole() -> void:
	var a := HoleGenerator.generate(4242)
	var b := HoleGenerator.generate(4242)
	check(a.pin == b.pin, "pin")
	check(a.heights == b.heights, "heights")
	check(a.surfaces == b.surfaces, "surfaces")
	check(a.wind_10m == b.wind_10m, "wind")
	check(a.obstacles.size() == b.obstacles.size() and a.features == b.features, "same obstacles and features")
	var c := HoleGenerator.generate(4243)
	check(a.pin != c.pin, "different seed differs")


func test_hazards_and_variety_appear() -> void:
	var ponds := 0
	var bunkers := 0
	var short := 0
	var long := 0
	var uphill := 0
	var downhill := 0
	for s in SEEDS:
		var h := HoleGenerator.generate(s * 31 + 7)
		if h.pond != null:
			ponds += 1
		bunkers += h.bunkers.size()
		if h.distance < 50.0:
			short += 1
		if h.distance > 80.0:
			long += 1
		if h.elevation > 1.5:
			uphill += 1
		if h.elevation < -1.5:
			downhill += 1
	check(ponds > SEEDS * 0.15 and ponds < SEEDS * 0.6, "ponds on a share of holes (%d)" % ponds)
	check(bunkers > SEEDS, "bunkers common (%d)" % bunkers)
	check(short > 5 and long > 5, "spread of distances (%d short, %d long)" % [short, long])
	check(uphill > 3 and downhill > 3, "uphill and downhill holes (%d/%d)" % [uphill, downhill])


func test_surfaces_match_shapes() -> void:
	var h := HoleGenerator.generate(99)
	check(h.get_surface(h.pin.x, h.pin.z) == Surface.GREEN, "pin on green")
	for b in h.bunkers:
		check(h.get_surface(b.center.x, b.center.y) == Surface.BUNKER, "bunker centre is sand")
		check(h.get_height(b.center.x, b.center.y) < h.get_height(b.center.x + 25.0, b.center.y) + 3.0, "bunker is a depression-ish")


func test_pond_holds_water_and_ball_splashes() -> void:
	var hole: HoleData = null
	for s in 200:
		var h := HoleGenerator.generate(s)
		if h.pond != null:
			hole = h
			break
	check(hole != null, "found a hole with a pond")
	if hole == null:
		return
	var c := hole.pond.center
	check(hole.get_surface(c.x, c.y) == Surface.WATER, "pond centre is water")
	check(hole.get_height(c.x, c.y) < hole.water_level, "pond bed below water level")
	near(hole.get_contact_height(c.x, c.y), hole.water_level, 0.001, "ball meets the water surface")
	# Drop a ball onto the pond.
	var sim := BallSim.new(hole)
	sim.launch(Vector3(c.x, hole.water_level + 5.0, c.y), Vector3(0, -5, -5), Vector3.ZERO)
	sim.simulate()
	check(sim.phase == BallSim.Phase.WATER, "ball splashes in the pond")


func test_ball_finishes_on_generated_terrain() -> void:
	for s in 10:
		var hole := HoleGenerator.generate(500 + s)
		var club := Clubs.suggest_for_distance(hole.distance)
		var sw := LaunchModel.Swing.new()
		var l := LaunchModel.compute(Clubs.get_club(club), sw)
		var sim := BallSim.new(hole)
		sim.launch(hole.tee + Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
		sim.simulate()
		check(sim.is_done(), "seed %d: shot finished" % s)
		if sim.phase == BallSim.Phase.STOPPED:
			var ground := hole.get_height(sim.pos.x, sim.pos.z)
			near(sim.pos.y, ground + BallSim.RADIUS, 0.05, "seed %d ball rests on the ground" % s)


func test_wild_slice_goes_out_of_bounds() -> void:
	var hole := HoleGenerator.generate(11)
	hole.trees = [] # trees could legitimately stop it first
	hole.obstacles = []
	var sw := LaunchModel.Swing.new()
	sw.face_to_path_deg = 14.0
	sw.path_deg = 12.0
	var l := LaunchModel.compute(Clubs.get_club(0), sw)
	# Aimed hard right so a short wedge hole's boundary is reachable.
	l.velocity = l.velocity.rotated(Vector3.UP, -0.9)
	l.spin = l.spin.rotated(Vector3.UP, -0.9)
	var sim := BallSim.new(hole)
	sim.launch(hole.tee + Vector3(0, BallSim.RADIUS, 0), l.velocity.rotated(Vector3.UP, -0.6), l.spin.rotated(Vector3.UP, -0.6))
	sim.simulate()
	check(sim.phase == BallSim.Phase.OUT, "huge slice is out of bounds (phase %d)" % sim.phase)


func test_features_block_the_ordinary_shot_but_a_route_exists() -> void:
	var puzzles := 0
	var kinds := {}
	for s in 40:
		var h := HoleGenerator.generate(7000 + s * 13)
		var tree_feature := false
		for f in h.features:
			kinds[f] = true
			if f == HoleGenerator.Feature.GUARD_TREE or f == HoleGenerator.Feature.HIGH_TREE or f == HoleGenerator.Feature.TREE_GATE:
				tree_feature = true
		if not tree_feature:
			continue
		var plain := ShotPlanner.Shot.new()
		plain.club_idx = 1
		var p := ShotPlanner.solve(h, h.tee + Vector3(0, BallSim.RADIUS + 0.012, 0), h.pin, plain)
		if p.blocked:
			puzzles += 1
		check(HoleGenerator.find_route(h) != null, "tree hole %d still has a route" % s)
	check(puzzles >= 8, "tree features usually block the plain 55 shot (%d)" % puzzles)
	check(kinds.size() >= 4, "variety of features (%d kinds)" % kinds.size())
