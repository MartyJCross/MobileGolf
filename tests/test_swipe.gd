extends "res://tests/test_base.gd"
## Pull-back-and-swipe swing tests (synthetic touches).

const H := 2340.0


func swipe(pull_frac: float, back_dx := 0.0, through_dx := 0.0) -> SwipeSwing:
	var g := SwipeSwing.new(H)
	var s := Vector2(540, 1500)
	g.touch_down(s)
	var top := s + Vector2(back_dx, pull_frac * H)
	for i in 10:
		g.touch_move(s.lerp(top, (i + 1) / 10.0))
	var end := s + Vector2(through_dx, -60)
	for i in 10:
		g.touch_move(top.lerp(end, (i + 1) / 10.0))
	g.touch_up(end)
	return g


func test_pull_distance_sets_power_not_speed() -> void:
	var full := swipe(SwipeSwing.PULL_FULL)
	check(full.state == SwipeSwing.State.DONE, "swing registered")
	near(full.result.power, 1.0, 0.01, "full pull = 100%")
	near(swipe(SwipeSwing.PULL_FULL * 0.5).result.power, 0.5, 0.01, "half pull = 50%")
	near(swipe(SwipeSwing.PULL_FULL * 2.0).result.power, SwipeSwing.MAX_POWER, 0.001, "over-pull capped")


func test_straight_back_and_through_is_straight() -> void:
	var r := swipe(0.15).result
	near(r.path_deg, 0.0, 0.01, "path")
	near(r.face_to_path_deg, 0.0, 0.01, "face to path")


func test_through_right_of_line_fades_left_draws() -> void:
	var fade := swipe(0.15, 0.0, 80.0).result
	check(fade.face_to_path_deg > 2.0, "through to the right = open face (%.1f)" % fade.face_to_path_deg)
	var draw := swipe(0.15, 0.0, -80.0).result
	check(draw.face_to_path_deg < -2.0, "through to the left = closed face")


func test_angled_line_is_a_push_or_pull() -> void:
	# Pull back down-left, come through on the same line (up-right).
	var push := swipe(0.15, -60.0, 60.0 * 60.0 / (0.15 * H)).result
	check(push.path_deg > 2.0, "path to the right (%.1f)" % push.path_deg)
	near(push.face_to_path_deg, 0.0, 0.6, "no curve when face follows the path")


func test_no_forward_swipe_cancels() -> void:
	var g := SwipeSwing.new(H)
	g.touch_down(Vector2(500, 1500))
	g.touch_move(Vector2(500, 1800))
	g.touch_up(Vector2(500, 1800))
	check(g.state == SwipeSwing.State.CANCELLED and g.hint != "", "lifting at the top cancels with a hint")
	var tiny := SwipeSwing.new(H)
	tiny.touch_down(Vector2(500, 1500))
	tiny.touch_move(Vector2(500, 1520))
	tiny.touch_move(Vector2(500, 1400))
	check(tiny.state != SwipeSwing.State.DONE, "a tiny wiggle isn't a swing")


func test_power_maps_to_carry() -> void:
	for club in 3:
		var shot := ShotPlanner.Shot.new()
		shot.club_idx = club
		var full := ShotPlanner.full_carry(shot)
		for pw in [0.4, 0.7, 1.0]:
			var sp := ShotPlanner.speed_for_power(shot, pw)
			var lv := ShotPlanner.launch_vectors(shot, sp, 0.0)
			var sim := BallSim.new(flat())
			sim.launch(Vector3(0, BallSim.RADIUS, 0), lv[0], lv[1])
			sim.simulate_flight()
			near(sim.carry_distance(), full * pw, full * 0.03, "club %d at %d%% carries %d%% of full" % [club, pw * 100, pw * 100])
			near(ShotPlanner.power_for_speed(shot, sp), pw, 0.01, "power round-trips")
