extends SceneTree
func _init() -> void:
	for seed in [4, 9]:
		var st := Stats.new()
		st.base_seed = seed
		var hole := HoleGenerator.generate(st.hole_seed(1))
		var shot := HoleGenerator.find_route(hole)
		var start := hole.tee + Vector3(0, BallSim.RADIUS + 0.012, 0)
		var plan := ShotPlanner.solve(hole, start, hole.pin, shot)
		print("seed %d dist %.1f wind %s (%.1f m/s) features %s plan blocked %s" % [seed, hole.distance, hole.wind_10m, hole.wind_10m.length(), hole.features, plan.blocked])
		for wind in [false, true]:
			var lv := ShotPlanner.launch_vectors(shot, plan.speed_frac, plan.yaw_deg)
			var sim := BallSim.new(hole)
			sim.ignore_wind = not wind
			sim.launch(start, lv[0], lv[1])
			sim.simulate()
			print("   wind=%s hit=%s at %s carry %.1f rest %.1f from pin" % [wind, sim.hit_tree, sim.first_hit_pos, sim.carry_distance(), hole.dist_to_pin(sim.pos)])
	quit()
