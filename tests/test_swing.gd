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


# ------------------------------------------------------------- control schemes

const PH := 600.0 # panel height in px


## Runs the downswing in small real-time steps; taps (or lifts, via `kind`)
## `offset_ms` on-screen ms from the perfect release.
func _downswing(c: SwingControls, offset_ms: float, kind := SwingControls.DOWN) -> SwingModel.Result:
	var m := c.model
	var tap_at := SwingModel.ideal_for(m.top).x + offset_ms / 1000.0 * m.time_scale
	while m.state == SwingModel.State.DOWNSWING:
		if not m.tapped and m.sim_t >= tap_at:
			c.handle(kind, Vector2(300, 100))
		m._step()
	return m.result


func _settle(m: SwingModel) -> void:
	for i in 200:
		m.update(1.0 / 120.0)


func _controls(scheme: int) -> SwingControls:
	var c := SwingControls.new(SwingModel.new())
	c.scheme = scheme
	c.panel_height = PH
	return c


func test_pull_tap_drag_sets_backswing_then_tap_releases() -> void:
	var c := _controls(SwingControls.Scheme.PULL_TAP)
	c.handle(SwingControls.DOWN, Vector2(300, 150))
	c.handle(SwingControls.MOVE, Vector2(300, 150 + SwingControls.PULL_RANGE * PH * 0.7))
	_settle(c.model)
	near(c.model.backswing_fraction(), 0.7, 0.01, "club follows the drag to 70%")
	c.handle(SwingControls.MOVE, Vector2(300, 150 + SwingControls.PULL_RANGE * PH * 0.5))
	_settle(c.model)
	near(c.model.backswing_fraction(), 0.5, 0.01, "sliding back up shortens the backswing")
	c.handle(SwingControls.UP, Vector2(300, 400))
	check(c.model.state == SwingModel.State.DOWNSWING, "let go starts the downswing")
	var r := _downswing(c, 0.0)
	check(r != null and r.released_by_player, "tap released the club")
	near(r.release_error_ms, 0.0, 2.0, "on time")


func test_pull_tap_tiny_drag_cancels_with_hint() -> void:
	var c := _controls(SwingControls.Scheme.PULL_TAP)
	c.handle(SwingControls.DOWN, Vector2(300, 150))
	c.handle(SwingControls.MOVE, Vector2(300, 160))
	_settle(c.model)
	c.handle(SwingControls.UP, Vector2(300, 160))
	check(c.model.state == SwingModel.State.IDLE, "no swing from a tiny drag")
	check(c.cancelled_hint != "", "tells you what to do")


func test_one_touch_push_up_swings_and_lift_releases() -> void:
	var c := _controls(SwingControls.Scheme.ONE_TOUCH)
	c.handle(SwingControls.DOWN, Vector2(300, 150))
	var bottom := 150 + SwingControls.PULL_RANGE * PH
	c.handle(SwingControls.MOVE, Vector2(300, bottom))
	_settle(c.model)
	near(c.model.backswing_fraction(), 1.0, 0.01, "full pull")
	c.handle(SwingControls.MOVE, Vector2(300, bottom - 5))
	check(c.model.state == SwingModel.State.BACKSWING, "small wobble doesn't start the swing")
	c.handle(SwingControls.MOVE, Vector2(300, bottom - SwingControls.PUSH_START * PH - 2))
	check(c.model.state == SwingModel.State.DOWNSWING, "pushing up starts the downswing")
	near(c.model.backswing_fraction(), 1.0, 0.02, "backswing kept from the deepest point")
	var r := _downswing(c, 20.0, SwingControls.UP)
	check(r.released_by_player and r.release_error_ms > 15.0, "lift released (late)")


func test_one_touch_lift_without_push_cancels() -> void:
	var c := _controls(SwingControls.Scheme.ONE_TOUCH)
	c.handle(SwingControls.DOWN, Vector2(300, 150))
	c.handle(SwingControls.MOVE, Vector2(300, 350))
	_settle(c.model)
	c.handle(SwingControls.UP, Vector2(300, 350))
	check(c.model.state == SwingModel.State.IDLE and c.cancelled_hint != "", "cancelled with a hint")


func test_hold_tap_and_three_taps() -> void:
	var h := _controls(SwingControls.Scheme.HOLD_TAP)
	h.handle(SwingControls.DOWN, Vector2.ZERO)
	for i in 120:
		h.model.update(1.0 / 120.0)
	h.handle(SwingControls.UP, Vector2.ZERO)
	check(h.model.state == SwingModel.State.DOWNSWING, "hold & let go swings")
	check(_downswing(h, 0.0).released_by_player, "tap releases")
	var t := _controls(SwingControls.Scheme.THREE_TAPS)
	t.handle(SwingControls.DOWN, Vector2.ZERO)
	t.handle(SwingControls.UP, Vector2.ZERO)
	for i in 90:
		t.model.update(1.0 / 120.0)
	check(t.model.state == SwingModel.State.BACKSWING, "backswing keeps going after the first tap")
	t.handle(SwingControls.DOWN, Vector2.ZERO)
	check(t.model.state == SwingModel.State.DOWNSWING, "second tap swings down")
	check(_downswing(t, -15.0).release_error_ms < -10.0, "third tap releases (early)")


func test_release_mark_matches_perfect_release() -> void:
	# The mark is drawn where the hands are at the perfect tap time.
	for deg in [-80.0, -120.0, -150.0]:
		var top := deg_to_rad(deg)
		var ideal := SwingModel.ideal_for(top)
		var m := SwingModel.new()
		m.analysis = true
		m.arm = top
		m.club = top + SwingModel.cock_for(top)
		m._start_down()
		while m.sim_t < ideal.x:
			m._step()
		near(rad_to_deg(m.arm), rad_to_deg(SwingModel.ideal_release_arm(top)), 3.0, "mark at top %.0f" % deg)
