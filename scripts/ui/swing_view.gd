class_name SwingView
extends Control
## Face-on view of the golfer, drawn from the SwingModel every frame.
## Target is to the left (as on TV, right-handed golfer). Touches are passed
## to SwingControls, which maps them for the chosen control scheme.
## The release mark shows where the hands are at the perfect release for the
## current backswing (from the physics); after a swing, a second marker
## shows where you actually released.

signal touch(kind: int, pos: Vector2)

var model: SwingModel
var controls: SwingControls
var show_mark := true
var feedback := "" # shown after a swing
var _trail: Array[Vector2] = [] # recent clubhead positions (metres, model space)
const TRAIL_MAX := 40


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.index == 0:
		touch.emit(SwingControls.DOWN if e.pressed else SwingControls.UP, e.position)
		accept_event()
	elif e is InputEventScreenDrag and e.index == 0:
		touch.emit(SwingControls.MOVE, e.position)
		accept_event()


func _process(_d: float) -> void:
	if model == null:
		return
	if model.state == SwingModel.State.DOWNSWING or model.state == SwingModel.State.FOLLOW:
		_trail.append(model.head())
		while _trail.size() > TRAIL_MAX:
			_trail.pop_front()
	elif model.state == SwingModel.State.IDLE or model.state == SwingModel.State.BACKSWING:
		_trail.clear()
	queue_redraw()


# Model metres -> panel pixels.
func _scale() -> float:
	return minf(size.y / 2.75, size.x / 3.6)


func _hub() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.06 + 1.12 * _scale())


func _px(p: Vector2) -> Vector2:
	# Model x is toward the target; the target is on the viewer's left.
	return _hub() + Vector2(-p.x, -p.y) * _scale()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.11, 0.07, 0.86))
	if model == null:
		return
	var s := _scale()
	var hub := _hub()
	var reach := SwingModel.L_ARM + SwingModel.L_CLUB
	var ground_y := hub.y + reach * s + 4.0
	var body := Color(0.92, 0.95, 0.9, 0.95)
	var shirt := Color(0.35, 0.62, 0.85)
	var pants := Color(0.2, 0.24, 0.32)

	# Ground and ball.
	draw_line(Vector2(0, ground_y), Vector2(size.x, ground_y), Color(0.4, 0.7, 0.35, 0.8), 3.0)
	var ball_p := Vector2(hub.x, ground_y - 6.0)
	if model.state != SwingModel.State.FOLLOW and model.state != SwingModel.State.DONE:
		draw_circle(ball_p, 6.0, Color.WHITE)

	# Body: legs, torso, head (face-on, slight knee flex).
	var hips := hub + Vector2(0, 0.52 * s)
	var turn := clampf(-model.arm / deg_to_rad(150.0), -1.0, 1.0) # + in backswing
	var hip_shift := Vector2(turn * 0.05 * s, 0)
	var foot_l := Vector2(hub.x - 0.24 * s, ground_y)
	var foot_r := Vector2(hub.x + 0.24 * s, ground_y)
	var knee_l := (hips + hip_shift).lerp(foot_l, 0.5) + Vector2(0.03 * s, 0)
	var knee_r := (hips + hip_shift).lerp(foot_r, 0.5) - Vector2(0.03 * s, 0)
	for leg in [[hips + hip_shift, knee_l, foot_l], [hips + hip_shift, knee_r, foot_r]]:
		draw_polyline(PackedVector2Array(leg), pants, 0.11 * s, true)
	var neck := hub + Vector2(turn * 0.03 * s, -0.12 * s)
	draw_line(hips + hip_shift, neck, shirt, 0.24 * s, true)
	draw_circle(neck + Vector2(0, -0.13 * s), 0.1 * s, body)

	# Shoulders turn: narrower in the backswing (seen side-on).
	var sh_w := 0.2 * (1.0 - 0.55 * absf(turn))
	var lead_sh := hub + Vector2(-sh_w * s, 0) # lead (left) shoulder, target side
	var trail_sh := hub + Vector2(sh_w * s, 0)

	_draw_release_mark()

	# Arms and club from the model.
	var hands := _px(model.hands())
	var head := _px(model.head())
	draw_line(trail_sh, hands, shirt.darkened(0.15), 0.075 * s, true)
	draw_line(lead_sh, hands, shirt, 0.08 * s, true)

	# Clubhead trail (shows the whip after release).
	if _trail.size() > 1:
		for i in _trail.size() - 1:
			var a := float(i) / _trail.size()
			draw_line(_px(_trail[i]), _px(_trail[i + 1]), Color(1.0, 0.9, 0.5, a * 0.6), 4.0 + 6.0 * a, true)

	draw_line(hands, head, Color(0.85, 0.85, 0.88), 4.0, true)
	var shaft_dir := (head - hands).normalized()
	draw_line(head - shaft_dir * 0.02 * s, head + shaft_dir * 0.05 * s, Color(0.62, 0.64, 0.68), 11.0, true)
	draw_circle(hands, 0.05 * s, body)

	_draw_text(ground_y)


## Glowing arc on the hands' path at the perfect release point, sized to
## about +/-10 ms of on-screen time. Shown from the start of the backswing
## (for the backswing so far) through the downswing.
func _draw_release_mark() -> void:
	var st := model.state
	var top := 0.0
	match st:
		SwingModel.State.BACKSWING:
			top = minf(model.arm, deg_to_rad(-40.0))
		SwingModel.State.DOWNSWING, SwingModel.State.FOLLOW, SwingModel.State.DONE:
			top = model.top
		_:
			return
	if not show_mark and st != SwingModel.State.FOLLOW and st != SwingModel.State.DONE:
		return
	if not SwingModel.table_ready():
		return
	var ra := SwingModel.ideal_release_arm(top)
	var sc := _scale()
	# Faint track of the hands' path from the top down to the ball.
	var track := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var a := lerpf(top, 0.0, float(i) / steps)
		track.append(_px(Vector2(sin(a), -cos(a)) * SwingModel.L_ARM))
	draw_polyline(track, Color(1, 1, 1, 0.13), 0.09 * sc, true)
	# The gate: a bold line across the track where the hands should be when
	# you release.
	var dir := Vector2(sin(ra), -cos(ra))
	var g0 := _px(dir * (SwingModel.L_ARM - 0.16))
	var g1 := _px(dir * (SwingModel.L_ARM + 0.16))
	var glow := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.014) if st == SwingModel.State.DOWNSWING else 0.8
	draw_line(g0, g1, Color(0.4, 1.0, 0.45, 0.35 * glow), 0.13 * sc, true)
	draw_line(g0, g1, Color(0.55, 1.0, 0.55, glow), 0.045 * sc, true)
	# After the swing: where you actually released.
	if (st == SwingModel.State.FOLLOW or st == SwingModel.State.DONE) and model.tapped:
		var tp := _px(Vector2(sin(model.tap_arm), -cos(model.tap_arm)) * SwingModel.L_ARM)
		draw_circle(tp, 11.0, Color(1.0, 0.5, 0.3, 0.95))
		draw_circle(tp, 5.0, Color(1, 1, 1))


func _draw_text(ground_y: float) -> void:
	var f := get_theme_default_font()
	var msg := ""
	var sub := ""
	if model.state == SwingModel.State.IDLE or model.state == SwingModel.State.BACKSWING or model.state == SwingModel.State.DOWNSWING:
		var h: Array = controls.hint() if controls else ["", ""]
		msg = h[0]
		sub = h[1]
		if model.state == SwingModel.State.IDLE:
			if controls and controls.cancelled_hint != "":
				sub = controls.cancelled_hint
			elif feedback != "":
				sub = feedback
	else:
		sub = feedback
	if msg != "":
		_centered(f, msg, 30, 34.0, Color(1, 1, 1, 0.95))
	if sub != "":
		_centered(f, sub, 21, 66.0, Color(0.85, 0.92, 0.86, 0.9))
	# Backswing meter (left edge) with a full-swing mark.
	var mh := size.y * 0.62
	var mx := 22.0
	var my := size.y * 0.2
	draw_rect(Rect2(mx, my, 14, mh), Color(1, 1, 1, 0.15))
	var frac := clampf(model.backswing_fraction() / (SwingModel.MAX_TOP / SwingModel.FULL_TOP), 0.0, 1.0) if model.state == SwingModel.State.BACKSWING else (model.top / SwingModel.MAX_TOP if model.state != SwingModel.State.IDLE else 0.0)
	var full_mark := SwingModel.FULL_TOP / SwingModel.MAX_TOP
	draw_rect(Rect2(mx, my + mh * (1.0 - frac), 14, mh * frac), Color(1.0, 0.82, 0.3, 0.9))
	draw_line(Vector2(mx - 4, my + mh * (1.0 - full_mark)), Vector2(mx + 18, my + mh * (1.0 - full_mark)), Color(1, 1, 1, 0.9), 2.0)


func _centered(f: Font, text: String, fs: int, y: float, c: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(f, Vector2((size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2((size.x - w) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
