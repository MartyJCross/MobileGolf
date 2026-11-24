extends "res://tests/test_base.gd"
## Swing model (double pendulum with lag and release timing) tests.

const TOP := SwingModel.FULL_TOP
const COCK := SwingModel.MAX_COCK


## Plays a swing through the real controls: hold for `hold_s`, lift, then
## tap `tap_offset_ms` (on-screen ms) relative to the perfect release
## (null = never tap).
func play(hold_s: float, tap_offset_ms, shape := 0.0) -> SwingModel.Result:
	var m := SwingModel.new()
	m.shape = shape
	m.press()
	var dt := 1.0 / 240.0
	var t := 0.0
	while t < hold_s:
		m.update(dt)
		t += dt
	m.lift()
	var ideal := SwingModel.ideal_for(m.top)
	var tap_at: float = -1.0 if tap_offset_ms == null else ideal.x + tap_offset_ms / 1000.0 * m.time_scale
	while m.state == SwingModel.State.DOWNSWING:
		if tap_at >= 0.0 and not m.tapped and m.sim_t + dt * m.time_scale > tap_at:
			# Advance exactly to the tap moment, then tap.
			while m.sim_t < tap_at and m.state == SwingModel.State.DOWNSWING:
				m._step()
			m.press()
		m.update(dt)
	return m.result


func test_perfect_full_swing_is_full_speed_and_square() -> void:
	var r := play(1.0, 0.0)
	check(r != null, "swing finished")
	near(r.speed_frac, 1.0, 0.01, "speed")
	near(r.swing.face_to_path_deg, 0.0, 0.3, "face to path")
	near(r.swing.path_deg, 0.0, 0.3, "path")
	near(r.swing.strike_high_mm, 0.0, 0.5, "centred strike")
	near(r.release_error_ms, 0.0, 3.0, "release error")


func test_club_in_line_at_impact_with_perfect_timing() -> void:
	var best := SwingModel.optimal_release_time(TOP, COCK)
	var m := SwingModel.simulate(TOP, COCK, best)
	check(absf(rad_to_deg(m.club - m.arm)) < 8.0, "club roughly in line with arms (%.1f deg)" % rad_to_deg(m.club - m.arm))
	var speed_mph := m.v_raw / Clubs.MPH
	check(speed_mph > 80.0 and speed_mph < 100.0, "realistic iron head speed (%.0f mph)" % speed_mph)
	# Best release: lead arm a bit below horizontal.
	var probe := SwingModel.simulate(TOP, COCK, -1.0)
	check(best < probe.sim_t, "release happens before impact")


func test_early_release_flips_closes_face_and_loses_speed() -> void:
	var r := play(1.0, -40.0)
	check(r.speed_frac < 0.995, "early release loses speed (%.3f)" % r.speed_frac)
	check(r.lag_deg > 5.0, "club flipped past the hands (%.1f)" % r.lag_deg)
	check(r.swing.face_to_path_deg < -1.5, "face closed: hook (%.1f)" % r.swing.face_to_path_deg)
	check(r.swing.path_deg < 0.0, "out-to-in path")
	check(r.swing.loft_offset_deg > 1.0, "adds loft")


func test_late_release_lags_opens_face_and_loses_speed() -> void:
	var r := play(1.0, 40.0)
	check(r.speed_frac < 0.97, "late release loses speed (%.3f)" % r.speed_frac)
	check(r.swing.face_to_path_deg > 1.5, "face open: slice (%.1f)" % r.swing.face_to_path_deg)
	check(r.swing.path_deg > 0.0, "in-to-out path")
	check(r.swing.loft_offset_deg < -1.0, "delofted (shaft leaning forward)")


func test_timing_error_grows_with_offset() -> void:
	var prev := 0.0
	for off in [10.0, 25.0, 50.0]:
		var r := play(1.0, off)
		check(absf(r.swing.face_to_path_deg) > prev, "%.0f ms late opens the face more" % off)
		prev = absf(r.swing.face_to_path_deg)


func test_no_tap_is_a_weak_late_release() -> void:
	var r := play(1.0, null)
	check(not r.released_by_player, "wrists gave way on their own")
	check(r.speed_frac < 0.85, "weak (%.2f)" % r.speed_frac)
	check(r.swing.face_to_path_deg > 4.0, "big push-slice face (%.1f)" % r.swing.face_to_path_deg)


func test_backswing_length_controls_speed() -> void:
	var prev := 0.0
	for hold in [0.45, 0.6, 0.75, 1.0]:
		var r := play(hold, 0.0)
		check(r.speed_frac > prev + 0.05, "longer backswing, more speed (hold %.2f -> %.2f)" % [hold, r.speed_frac])
		near(r.swing.face_to_path_deg, 0.0, 0.5, "perfect timing is square at any length (hold %.2f)" % hold)
		prev = r.speed_frac
	var half := play(0.55, 0.0)
	check(half.speed_frac > 0.5 and half.speed_frac < 0.75, "about a half swing (%.2f)" % half.speed_frac)


func test_overswing_is_a_bit_faster_but_wild() -> void:
	var r := play(1.35, 0.0)
	check(r.overswing, "flagged as overswing")
	check(r.speed_frac > 1.0 and r.speed_frac < 1.12, "a little extra speed (%.2f)" % r.speed_frac)


func test_shape_sets_path_and_face() -> void:
	var draw := play(1.0, 0.0, -1.0)
	check(draw.swing.path_deg > 3.0 and draw.swing.face_to_path_deg < -2.0, "draw set-up: in-to-out, face closed to path")
	var l := LaunchModel.compute(Clubs.get_club(4), draw.swing)
	check(l.spin_axis_deg < -2.0 and l.launch_h_deg > 0.0, "starts right, draws left")
	var fade := play(1.0, 0.0, 1.0)
	check(fade.swing.path_deg < -3.0 and fade.swing.face_to_path_deg > 2.0, "fade set-up")


func test_cancel_tiny_backswing() -> void:
	var m := SwingModel.new()
	m.press()
	m.update(0.1)
	m.lift()
	check(m.state == SwingModel.State.IDLE, "tiny backswing cancels")
