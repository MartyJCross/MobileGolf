extends "res://tests/test_base.gd"
## Ball physics and launch model tests.


func test_stock_launch_matches_tour_numbers() -> void:
	for club in Clubs.TOUR_IRONS:
		var l := LaunchModel.compute(club, LaunchModel.Swing.new())
		near(l.ball_speed, club["ball_mph"] * Clubs.MPH, 0.01 * club["ball_mph"] * Clubs.MPH, "%s ball speed" % club["id"])
		near(l.launch_v_deg, club["launch"], 0.3, "%s launch" % club["id"])
		near(l.spin_rpm, club["spin"], 0.01 * club["spin"], "%s spin" % club["id"])
		near(l.launch_h_deg, 0.0, 0.01, "%s start line" % club["id"])
		near(l.spin_axis_deg, 0.0, 0.01, "%s spin axis" % club["id"])


func test_stock_flight_matches_tour_carry_and_landing() -> void:
	for club in Clubs.TOUR_IRONS:
		var l := LaunchModel.compute(club, LaunchModel.Swing.new())
		var sim := BallSim.new(flat())
		sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
		sim.simulate_flight()
		var carry_t: float = club["carry_yd"] * Clubs.YARD
		near(sim.carry_distance(), carry_t, carry_t * 0.03, "%s carry" % club["id"])
		near(sim.land_angle_deg, club["land"], 2.5, "%s landing angle" % club["id"])
		var apex_t: float = club["apex_yd"] * Clubs.YARD
		near(sim.apex, apex_t, apex_t * 0.25, "%s apex" % club["id"])
		check(sim.land_spin_rpm < club["spin"] and sim.land_spin_rpm > club["spin"] * 0.6, "%s spin decays moderately in flight (%.0f)" % [club["id"], sim.land_spin_rpm])


func test_longer_clubs_go_further() -> void:
	var prev := 1e9
	for club in Clubs.TOUR_IRONS:
		var sim := shoot(flat(Surface.ROUGH), club["id"])
		check(sim.carry_distance() < prev, "%s should carry less than the longer club" % club["id"])
		prev = sim.carry_distance()


func test_overswing_gains_little() -> void:
	for id in ["3i", "7i", "PW"]:
		var stock := shoot(flat(Surface.ROUGH), id)
		var sw := LaunchModel.Swing.new()
		sw.speed_frac = 1.15
		var hard := shoot(flat(Surface.ROUGH), id, sw)
		var gain := hard.carry_distance() / stock.carry_distance()
		# Real carry rises roughly in step with ball speed (~118% here); this
		# guards against drag extrapolating to nothing at high speed.
		check(gain > 1.08 and gain < 1.26, "%s at 115%% carries %.0f%% of stock" % [id, gain * 100.0])


func test_square_face_on_path_flies_straight() -> void:
	var sim := shoot(flat(), "7i")
	near(sim.pos.x, 0.0, 0.05, "straight shot lateral")


func test_face_closed_to_path_draws_left() -> void:
	var sw := LaunchModel.Swing.new()
	sw.path_deg = 3.0
	sw.face_to_path_deg = -3.0 # face square to target, closed to the in-to-out path
	var l := LaunchModel.compute(Clubs.find("7i"), sw)
	check(l.spin_axis_deg < -3.0, "draw spin axis tilts left (%.1f)" % l.spin_axis_deg)
	check(l.launch_h_deg > 0.0, "starts right of target, toward the path")
	var t := flat(Surface.ROUGH)
	var sim := BallSim.new(t)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	sim.simulate_flight()
	var start_line_x := tan(deg_to_rad(l.launch_h_deg)) * -sim.carry_pos.z
	check(sim.carry_pos.x < start_line_x - 5.0, "curves left of its start line (x %.1f vs %.1f)" % [sim.carry_pos.x, start_line_x])


func test_face_open_to_path_fades_right() -> void:
	var sw := LaunchModel.Swing.new()
	sw.path_deg = -3.0
	sw.face_to_path_deg = 3.0
	var l := LaunchModel.compute(Clubs.find("7i"), sw)
	check(l.spin_axis_deg > 3.0, "fade spin axis tilts right (%.1f)" % l.spin_axis_deg)
	var sim := BallSim.new(flat(Surface.ROUGH))
	sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	sim.simulate_flight()
	var start_line_x := tan(deg_to_rad(l.launch_h_deg)) * -sim.carry_pos.z
	check(sim.carry_pos.x > start_line_x + 5.0, "curves right of its start line")


func test_bigger_face_to_path_curves_more() -> void:
	var prev := 0.0
	for ftp in [2.0, 4.0, 8.0]:
		var sw := LaunchModel.Swing.new()
		sw.face_to_path_deg = ftp
		var sim := shoot(flat(Surface.ROUGH), "6i", sw)
		check(sim.carry_pos.x > prev, "more open face curves further right (%.1f)" % ftp)
		prev = sim.carry_pos.x


func test_push_with_square_face_to_path_is_straight_right() -> void:
	var sw := LaunchModel.Swing.new()
	sw.path_deg = 4.0
	var l := LaunchModel.compute(Clubs.find("8i"), sw)
	near(l.spin_axis_deg, 0.0, 0.2, "no curve spin when face == path")
	near(l.launch_h_deg, 4.0, 0.1, "starts on the path")


func test_partial_swing_shorter_with_less_spin() -> void:
	var full := shoot(flat(Surface.ROUGH), "PW")
	var sw := LaunchModel.Swing.new()
	sw.speed_frac = 0.6
	var l := LaunchModel.compute(Clubs.find("PW"), sw)
	var half := shoot(flat(Surface.ROUGH), "PW", sw)
	check(half.carry_distance() < full.carry_distance() * 0.6, "60% swing carries well under 60% of full")
	check(l.spin_rpm < 9304.0 and l.spin_rpm > 9304.0 * 0.6, "partial swing keeps most of its spin (%.0f)" % l.spin_rpm)


func test_high_trajectory_launches_higher_with_more_spin() -> void:
	var club := Clubs.find("8i")
	var sw_hi := LaunchModel.Swing.new()
	sw_hi.trajectory = 1.0
	var sw_lo := LaunchModel.Swing.new()
	sw_lo.trajectory = -1.0
	var hi := LaunchModel.compute(club, sw_hi)
	var lo := LaunchModel.compute(club, sw_lo)
	check(hi.launch_v_deg > lo.launch_v_deg + 5.0, "high launches higher")
	check(hi.spin_rpm > lo.spin_rpm, "high spins more")
	check(lo.ball_speed > hi.ball_speed, "low compresses more (ball speed)")


func test_off_centre_strike_loses_speed() -> void:
	var club := Clubs.find("7i")
	var sw := LaunchModel.Swing.new()
	sw.strike_toe_mm = 12.0
	var toe := LaunchModel.compute(club, sw)
	var pure := LaunchModel.compute(club, LaunchModel.Swing.new())
	check(toe.ball_speed < pure.ball_speed * 0.96, "toe strike loses ball speed")
	sw = LaunchModel.Swing.new()
	sw.strike_high_mm = -8.0
	var thin := LaunchModel.compute(club, sw)
	check(thin.spin_rpm > pure.spin_rpm and thin.launch_v_deg < pure.launch_v_deg, "low strike: lower launch, more spin")


func test_headwind_shortens_tailwind_lengthens() -> void:
	var calm := shoot(flat(Surface.ROUGH), "7i")
	var head := flat(Surface.ROUGH)
	head.wind_10m = Vector3(0, 0, 6) # blowing toward the golfer
	var tail := flat(Surface.ROUGH)
	tail.wind_10m = Vector3(0, 0, -6)
	var h := shoot(head, "7i")
	var t := shoot(tail, "7i")
	check(h.carry_distance() < calm.carry_distance() - 8.0, "6 m/s headwind costs > 8 m (%.1f vs %.1f)" % [h.carry_distance(), calm.carry_distance()])
	check(t.carry_distance() > calm.carry_distance() + 4.0, "6 m/s tailwind adds > 4 m")
	check(calm.carry_distance() - h.carry_distance() > t.carry_distance() - calm.carry_distance(), "headwind hurts more than tailwind helps")


func test_crosswind_pushes_ball() -> void:
	var t := flat(Surface.ROUGH)
	t.wind_10m = Vector3(5, 0, 0) # left-to-right
	var sim := shoot(t, "6i")
	check(sim.carry_pos.x > 5.0, "left-to-right wind moves ball right (%.1f)" % sim.carry_pos.x)


func test_wedge_spins_back_on_soft_green() -> void:
	var t := flat(Surface.GREEN)
	t.green_softness = 1.2
	var sim := shoot(t, "PW")
	check(-sim.pos.z < sim.carry_distance() - 1.0, "full PW spins back on a soft green (carry %.1f, final %.1f)" % [sim.carry_distance(), -sim.pos.z])


func test_long_iron_releases_on_firm_green() -> void:
	var t := flat(Surface.GREEN)
	t.green_softness = 0.6
	var sim := shoot(t, "4i")
	check(-sim.pos.z > sim.carry_distance() + 5.0, "4i releases on a firm green (rollout %.1f)" % (-sim.pos.z - sim.carry_distance()))


func test_firm_green_rolls_further_than_soft() -> void:
	var firm := flat(Surface.GREEN)
	firm.green_softness = 0.6
	var soft := flat(Surface.GREEN)
	soft.green_softness = 1.3
	check(shoot(firm, "7i").pos.z < shoot(soft, "7i").pos.z - 3.0, "7i finishes further on firm green")


func test_rough_and_sand_stop_ball() -> void:
	var r := shoot(flat(Surface.ROUGH), "5i")
	check(-r.pos.z - r.carry_distance() < 6.0, "rough stops the ball quickly")
	var b := shoot(flat(Surface.BUNKER), "5i")
	check(absf(-b.pos.z - b.carry_distance()) < 1.5, "ball plugs / stops in sand")


func test_water_ends_shot() -> void:
	var sim := shoot(flat(Surface.WATER), "8i")
	check(sim.phase == BallSim.Phase.WATER, "ball in water")
	near(sim.water_pos.z, sim.carry_pos.z, 0.01, "water entry is landing point")


func test_ball_rolls_downhill_and_stops_on_flat() -> void:
	var slope := SlopeTerrain.new()
	slope.surface_type = Surface.GREEN
	var sim := BallSim.new(slope)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, 0.01), Vector3.ZERO)
	sim.phase = BallSim.Phase.GROUND
	sim.simulate()
	check(sim.pos.x > 0.5, "ball rolls down a 6%% slope to +x (%.2f)" % sim.pos.x)
	var flat_t := flat(Surface.GREEN)
	var still := BallSim.new(flat_t)
	still.launch(Vector3(0, BallSim.RADIUS, 0), Vector3.ZERO, Vector3.ZERO)
	still.phase = BallSim.Phase.GROUND
	still.simulate()
	check(still.phase == BallSim.Phase.STOPPED and still.pos.length() < 0.05, "ball at rest on flat stays put")
	var gentle := SlopeTerrain.new()
	gentle.grade = 0.03
	gentle.surface_type = Surface.GREEN
	var rest := BallSim.new(gentle)
	rest.launch(Vector3(0, BallSim.RADIUS, 0), Vector3.ZERO, Vector3.ZERO)
	rest.phase = BallSim.Phase.GROUND
	rest.simulate()
	check(rest.pos.x < 0.05, "ball at rest on a 3%% green slope stays put")


func test_green_stimp_roll_distance() -> void:
	# Stimpmeter: ball released at 1.83 m/s; Stimp 11 rolls ~3.35 m.
	var sim := BallSim.new(flat(Surface.GREEN))
	sim.launch(Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -1.83), Vector3(-1.83 / BallSim.RADIUS, 0, 0))
	sim.phase = BallSim.Phase.GROUND
	sim.simulate()
	near(-sim.pos.z, 3.35, 0.3, "stimp roll distance")


func test_slow_ball_over_cup_drops() -> void:
	var t := flat(Surface.GREEN)
	t.pin = Vector3(0, 0, -2.0)
	var sim := BallSim.new(t)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -1.6), Vector3(-1.6 / BallSim.RADIUS, 0, 0))
	sim.phase = BallSim.Phase.GROUND
	sim.simulate()
	check(sim.phase == BallSim.Phase.HOLED, "slow putt drops")
	var fast := BallSim.new(t)
	fast.launch(Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -6.0), Vector3(-6.0 / BallSim.RADIUS, 0, 0))
	fast.phase = BallSim.Phase.GROUND
	fast.simulate()
	check(fast.phase == BallSim.Phase.STOPPED, "fast ball rolls over the cup")


func test_deterministic() -> void:
	var a := shoot(flat(Surface.GREEN), "7i")
	var b := shoot(flat(Surface.GREEN), "7i")
	check(a.pos == b.pos, "same inputs, same result")


class SlopeTerrain extends GolfTerrain:
	var grade := 0.06 # down toward +x

	func get_height(x: float, _z: float) -> float:
		return -x * grade

	func get_normal(_x: float, _z: float) -> Vector3:
		return Vector3(grade, 1.0, 0.0).normalized()


# ------------------------------------------------------------- wedges, planner, obstacles

func test_wedges_carry_their_listed_distances() -> void:
	var prev := 1e9
	for club in Clubs.SET:
		var l := LaunchModel.compute(club, LaunchModel.Swing.new())
		var sim := BallSim.new(flat())
		sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
		sim.simulate_flight()
		var want := Clubs.stock_carry_m(club)
		near(sim.carry_distance(), want, want * 0.02, "%s carry" % club["id"])
		check(sim.carry_distance() < prev, "%s shorter than the stronger wedge" % club["id"])
		prev = sim.carry_distance()


func test_planner_lands_on_target_for_every_shot_type() -> void:
	var t := flat(Surface.GREEN)
	t.wind_10m = Vector3(3, 0, 2)
	for h in ShotPlanner.HEIGHTS.size():
		for curve in [-1.0, 0.0, 1.0]:
			var shot := ShotPlanner.Shot.new()
			shot.club_idx = 2
			shot.height_idx = h
			shot.curve = curve
			var target := Vector3(4, 0, -45)
			var p := ShotPlanner.solve(t, Vector3(0, BallSim.RADIUS, 0), target, shot)
			# Fly it for real (fine time step, wind on).
			var lv := ShotPlanner.launch_vectors(shot, p.speed_frac, p.yaw_deg)
			var sim := BallSim.new(t)
			sim.launch(Vector3(0, BallSim.RADIUS, 0), lv[0], lv[1])
			sim.simulate_flight()
			near(Vector2(sim.carry_pos.x - target.x, sim.carry_pos.z - target.z).length(), 0.0, 0.4, "%s curve %.0f lands on the ring" % [ShotPlanner.HEIGHTS[h]["name"], curve])


func test_planner_reports_out_of_range() -> void:
	var shot := ShotPlanner.Shot.new()
	shot.club_idx = 2 # 60 degree
	shot.height_idx = 3 # flop
	var p := ShotPlanner.solve(flat(), Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -110), shot)
	check(p.too_far, "110 m flop with a 60 degree is out of range")


func test_heights_and_spin_change_the_shot() -> void:
	var t := flat(Surface.GREEN)
	var apex := []
	var rest := []
	for h in [0, 3]:
		var shot := ShotPlanner.Shot.new()
		shot.height_idx = h
		var p := ShotPlanner.solve(t, Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -40), shot)
		apex.append(p.apex)
		var lv := ShotPlanner.launch_vectors(shot, p.speed_frac, p.yaw_deg)
		var sim := BallSim.new(t)
		sim.launch(Vector3(0, BallSim.RADIUS, 0), lv[0], lv[1])
		sim.simulate()
		rest.append(-sim.pos.z - 40.0)
	check(apex[1] > apex[0] * 2.0, "flop goes much higher than a punch (%.1f vs %.1f)" % [apex[1], apex[0]])
	check(rest[0] > rest[1] + 5.0, "punch runs out, flop stops (%.1f vs %.1f m past)" % [rest[0], rest[1]])
	var roll := []
	for sp in [-1.0, 1.0]:
		var shot2 := ShotPlanner.Shot.new()
		shot2.spin = sp
		var p2 := ShotPlanner.solve(t, Vector3(0, BallSim.RADIUS, 0), Vector3(0, 0, -60), shot2)
		var lv2 := ShotPlanner.launch_vectors(shot2, p2.speed_frac, p2.yaw_deg)
		var sim2 := BallSim.new(t)
		sim2.launch(Vector3(0, BallSim.RADIUS, 0), lv2[0], lv2[1])
		sim2.simulate()
		roll.append(-sim2.pos.z - 60.0)
	check(roll[0] > roll[1] + 3.0, "runner releases, max spin checks (%.1f vs %.1f)" % [roll[0], roll[1]])


func test_solid_obstacles_bounce_soft_ones_grab() -> void:
	var t := flat(Surface.FAIRWAY)
	t.obstacles = [{"kind": GolfTerrain.WALL, "center": Vector3(0, 0.6, -10), "half": Vector3(5, 0.6, 0.3), "yaw": 0.0}]
	var sim := BallSim.new(t)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), Vector3(0, 2, -15), Vector3.ZERO)
	sim.simulate()
	check(sim.hit_tree and sim.pos.z > -10.0, "low ball bounces back off the wall (z %.1f)" % sim.pos.z)
	var t2 := flat(Surface.FAIRWAY)
	t2.obstacles = [{"kind": GolfTerrain.CANOPY, "center": Vector3(0, 6, -20), "r": 3.0}]
	var s2 := BallSim.new(t2)
	s2.launch(Vector3(0, BallSim.RADIUS, 0), LaunchModel.dir_from(0, 20) * 30.0, Vector3(300, 0, 0))
	s2.simulate()
	check(s2.hit_tree and -s2.pos.z < 30.0, "ball into a canopy drops short (z %.1f)" % s2.pos.z)
	var t3 := flat(Surface.GREEN)
	t3.pin = Vector3(0, 0, -30)
	t3.obstacles = [{"kind": GolfTerrain.PIN, "base": Vector3(0, 0, -30), "h": 2.2, "r": 0.0125}]
	var s3 := BallSim.new(t3)
	s3.launch(Vector3(0, 1.0, -28), Vector3(0, -2, -12), Vector3.ZERO)
	s3.simulate()
	check(not s3.hit_tree, "the flagstick isn't counted as an obstacle")
	check(Vector2(s3.pos.x, s3.pos.z + 30).length() < 3.0, "ball hitting the flagstick drops near it")
