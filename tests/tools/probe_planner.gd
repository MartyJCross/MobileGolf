extends SceneTree
func _init() -> void:
	var t := GolfTerrain.new()
	t.surface_type = Surface.GREEN
	for h in 4:
		for d in [30.0, 60.0, 90.0]:
			var shot := ShotPlanner.Shot.new()
			shot.club_idx = 1
			shot.height_idx = h
			shot.curve = 0.6
			var target := Vector3(5, 0, -d)
			var t0 := Time.get_ticks_usec()
			var p := ShotPlanner.solve(t, Vector3(0, BallSim.RADIUS, 0), target, shot)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			# Real shot (fine dt, no wind) to compare
			var lv := ShotPlanner.launch_vectors(shot, p.speed_frac, p.yaw_deg)
			var sim := BallSim.new(t)
			sim.launch(Vector3(0, BallSim.RADIUS, 0), lv[0], lv[1])
			sim.simulate()
			print("%-6s d=%3.0f speed %.2f yaw %+.1f iters %d  plan-miss %.2f  real-land-miss %.2f  rest %.1f m from target  apex %.1f  %.0f ms" % [ShotPlanner.HEIGHTS[h]["name"], d, p.speed_frac, p.yaw_deg, p.iterations, Vector2(p.landing.x - 5, p.landing.z + d).length(), Vector2(sim.carry_pos.x - 5, sim.carry_pos.z + d).length(), Vector2(sim.pos.x - 5, sim.pos.z + d).length(), p.apex, ms])
	quit()
