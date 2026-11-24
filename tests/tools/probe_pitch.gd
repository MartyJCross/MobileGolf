extends SceneTree
func _init() -> void:
	var sw := LaunchModel.Swing.new()
	sw.speed_frac = 0.6
	var club := Clubs.get_club(Clubs.index_of("PW"))
	var l := LaunchModel.compute(club, sw)
	print("ball %.1f m/s launch %.1f spin %.0f" % [l.ball_speed, l.launch_v_deg, l.spin_rpm])
	var t := GolfTerrain.new()
	t.surface_type = Surface.GREEN
	var sim := BallSim.new(t)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	var last_phase := -1
	var last_b := 0
	while not sim.is_done() and sim.time < 40:
		sim.step(BallSim.DT)
		if sim.bounces != last_b or sim.phase != last_phase:
			print("t=%.2f phase=%d b=%d pos.z=%.2f vel=%s spin=%s rpm=%.0f" % [sim.time, sim.phase, sim.bounces, sim.pos.z, sim.vel, sim.spin, sim.spin_rpm()])
			last_b = sim.bounces
			last_phase = sim.phase
	print("land angle %.1f speed %.1f final z %.2f" % [sim.land_angle_deg, sim.land_speed, sim.pos.z])
	quit()
