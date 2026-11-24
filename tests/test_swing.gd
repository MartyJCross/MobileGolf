extends "res://tests/test_base.gd"
## Swipe gesture tests using synthetic touch tracks.

const H := 2340.0 # S24 FE screen height in px


## Pull down `back` (fraction of H), then flick up past the start in
## `flick_time` seconds. `tilt_px` shifts the end point sideways; `bend_px`
## bows the path (positive = bends right near impact).
func swipe(back: float, flick_time: float, tilt_px := 0.0, bend_px := 0.0) -> SwingGesture.Result:
	var g := SwingGesture.new(H)
	var start := Vector2(540, 1800)
	var t := 0.0
	g.touch_down(start, t)
	for i in 20:
		t += 0.02
		g.touch_move(start + Vector2(0, back * H * (i + 1) / 20.0), t)
	t += 0.15 # pause at the top
	var top := start + Vector2(0, back * H)
	var end := start + Vector2(tilt_px, -0.08 * H)
	var steps := 24
	for i in steps:
		var f := float(i + 1) / steps
		t += flick_time / steps
		var p := top.lerp(end, f)
		# Bow: bend grows toward the end (quadratic) -> path curves through impact.
		p.x += bend_px * f * f
		g.touch_move(p, t)
		if g.state == SwingGesture.State.DONE:
			break
	g.touch_up(end, t + 0.01)
	return g.result


func test_fast_flick_is_full_speed() -> void:
	var r := swipe(0.18, 0.09)
	check(r != null, "swing registered")
	if r:
		check(r.speed_frac > 0.95, "fast flick ~full (%.2f)" % r.speed_frac)


func test_slower_flick_is_slower() -> void:
	var fast := swipe(0.18, 0.09)
	var slow := swipe(0.18, 0.25)
	check(slow.speed_frac < fast.speed_frac * 0.6, "slower flick, less speed (%.2f vs %.2f)" % [slow.speed_frac, fast.speed_frac])


func test_short_backswing_caps_speed() -> void:
	var r := swipe(0.06, 0.03)
	check(r.speed_frac < 0.7, "short backswing can't make full speed (%.2f)" % r.speed_frac)


func test_straight_swipe_is_square() -> void:
	var r := swipe(0.18, 0.12)
	near(r.swing.path_deg, 0.0, 0.5, "path")
	near(r.swing.face_to_path_deg, 0.0, 0.5, "face to path")


func test_tilted_swipe_sets_path() -> void:
	var r := swipe(0.18, 0.12, 200.0)
	check(r.swing.path_deg > 2.0, "tilt right = in-to-out path (%.1f)" % r.swing.path_deg)
	near(r.swing.face_to_path_deg, 0.0, 0.5, "no bend, face matches path")
	var l := swipe(0.18, 0.12, -200.0)
	check(l.swing.path_deg < -2.0, "tilt left = out-to-in path")


func test_bent_swipe_sets_face() -> void:
	var r := swipe(0.18, 0.12, 0.0, 80.0)
	check(r.swing.face_to_path_deg > 2.0, "bend right = open face, fade (%.1f)" % r.swing.face_to_path_deg)
	var l := swipe(0.18, 0.12, 0.0, -80.0)
	check(l.swing.face_to_path_deg < -2.0, "bend left = closed face, draw (%.1f)" % l.swing.face_to_path_deg)


func test_no_backswing_does_nothing() -> void:
	var g := SwingGesture.new(H)
	g.touch_down(Vector2(500, 1800), 0.0)
	g.touch_move(Vector2(500, 1750), 0.05)
	g.touch_up(Vector2(500, 1700), 0.1)
	check(g.result == null, "tap/upward swipe is not a swing")


func test_overswing_adds_error() -> void:
	var spread := 0.0
	for i in 20:
		var r := swipe(0.2, 0.04)
		check(r.overswing, "very fast flick is an overswing")
		spread += absf(r.swing.face_to_path_deg)
	check(spread / 20.0 > 0.5, "overswing scatters the face (%.2f)" % (spread / 20.0))
