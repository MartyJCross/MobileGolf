class_name SwingOverlay
extends Control
## Transparent swing zone over the lower part of the course view. Shows the
## club pulled back from where you touched, a power gauge, your swipe and,
## after a shot, the path/face it read.

signal touch(kind: int, pos: Vector2) # 0 down, 1 move, 2 up

var swing: SwipeSwing
var feedback := ""
var _fade := 0.0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.index == 0:
		touch.emit(0 if e.pressed else 2, e.position)
		accept_event()
	elif e is InputEventScreenDrag and e.index == 0:
		touch.emit(1, e.position)
		accept_event()


func _process(delta: float) -> void:
	if swing and (swing.state == SwipeSwing.State.DONE or swing.state == SwipeSwing.State.CANCELLED):
		_fade = maxf(0.0, _fade - delta)
	else:
		_fade = 1.2
	queue_redraw()


func _draw() -> void:
	if swing == null:
		return
	var f := get_theme_default_font()
	var st := swing.state
	if st == SwipeSwing.State.IDLE or (st != SwipeSwing.State.BACK and st != SwipeSwing.State.FORWARD and _fade <= 0.0):
		_center_text(f, "Pull down to swing back", size.y * 0.42, 28, Color(1, 1, 1, 0.9))
		_center_text(f, "then swipe up through the ball", size.y * 0.42 + 34, 22, Color(1, 1, 1, 0.75))
		var sub := swing.hint if swing.hint != "" else feedback
		if sub != "":
			_center_text(f, sub, size.y * 0.42 + 70, 21, Color(1.0, 0.9, 0.5, 0.95))
		return
	# The swing works in screen coordinates; this control starts lower down.
	var off := position
	var s := swing.start - off
	var reach := SwipeSwing.PULL_FULL * swing.screen_h
	# Power gauge: a track straight down from the start, filled to the pull.
	var p := swing.power()
	var full_pt := s + Vector2(0, reach)
	draw_line(s, full_pt + Vector2(0, reach * 0.05), Color(1, 1, 1, 0.18), 18.0, true)
	var col := Color(0.4, 0.9, 0.45).lerp(Color(1.0, 0.75, 0.25), clampf((p - 0.6) / 0.4, 0.0, 1.0))
	if p > 1.0:
		col = Color(1.0, 0.4, 0.3)
	draw_line(s, s + Vector2(0, reach * minf(p, SwipeSwing.MAX_POWER)), col, 18.0, true)
	draw_line(full_pt - Vector2(22, 0), full_pt + Vector2(22, 0), Color(1, 1, 1, 0.9), 3.0)
	# The ball at the start point.
	draw_circle(s, 13, Color.WHITE)
	# The club: head at the top of the backswing (or the finger), shaft trailing off.
	var head := swing.finger - off
	var shaft_dir := Vector2(-0.35, -1.0).normalized()
	draw_line(head, head + shaft_dir * 260.0, Color(0.85, 0.86, 0.9, 0.95), 6.0, true)
	draw_rect(Rect2(head - Vector2(26, 9), Vector2(40, 18)), Color(0.55, 0.57, 0.62))
	# Swipe trail.
	if swing.trail.size() > 1:
		var pts := PackedVector2Array()
		for q in swing.trail:
			pts.append(q - off)
		draw_polyline(pts, Color(1.0, 0.95, 0.6, 0.75), 5.0, true)
	var label := "Power %d%%" % roundi(p * 100.0)
	if st == SwipeSwing.State.BACK:
		_center_text(f, label, s.y - 40, 30, Color.WHITE)
	elif st == SwipeSwing.State.FORWARD:
		_center_text(f, label + "  ·  swipe through!", s.y - 40, 26, Color.WHITE)


func _center_text(f: Font, t: String, y: float, fs: int, c: Color) -> void:
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(f, Vector2((size.x - w) * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2((size.x - w) * 0.5, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
