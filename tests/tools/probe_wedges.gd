extends SceneTree
## Solves each wedge's stock ball speed so the flight model carries it to the
## listed typical distance; prints results.
func _carry(club: Dictionary, mph: float) -> Array:
	var c := club.duplicate()
	c["ball_mph"] = mph
	var l := LaunchModel.compute(c, LaunchModel.Swing.new())
	var sim := BallSim.new()
	sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	sim.simulate_flight()
	return [sim.carry_distance(), sim.apex, sim.land_angle_deg]

func _init() -> void:
	for club in Clubs.SET:
		var target: float = club["carry_yd"] * Clubs.YARD
		var lo := 60.0
		var hi := 110.0
		for i in 30:
			var mid := (lo + hi) * 0.5
			if _carry(club, mid)[0] < target:
				lo = mid
			else:
				hi = mid
		var r := _carry(club, lo)
		print("%s ball %.1f mph (smash %.2f) carry %.1f apex %.1f land %.1f" % [club["id"], lo, lo / club["club_mph"], r[0], r[1], r[2]])
	quit()
