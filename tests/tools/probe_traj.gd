extends SceneTree
func _init() -> void:
	var TB = preload("res://tests/test_base.gd")
	for id in ["PW", "9i", "7i"]:
		for frac in [0.6, 0.8, 1.0]:
			for traj in [-1.0, 0.0, 1.0]:
				var sw := LaunchModel.Swing.new()
				sw.speed_frac = frac
				sw.trajectory = traj
				var l := LaunchModel.compute(Clubs.get_club(Clubs.index_of(id)), sw)
				var t := GolfTerrain.new()
				t.surface_type = Surface.GREEN
				var sim: BallSim = TB.shoot(t, id, sw)
				print("%-3s %3.0f%% traj %+.0f  launch %4.1f spin %5.0f apex %4.1f land %4.1f carry %5.1f total %5.1f roll %+5.1f" % [id, frac*100, traj, l.launch_v_deg, l.spin_rpm, sim.apex, sim.land_angle_deg, sim.carry_distance(), -sim.pos.z, -sim.pos.z - sim.carry_distance()])
	quit()
