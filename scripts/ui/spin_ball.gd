class_name SpinBall
extends Control
## Drag the dot on the ball to choose spin.
##   down  = more backspin (checks, can spin back)
##   up    = less backspin (a "runner" that releases)
##   left  = draw (curves left)   right = fade (curves right)
## Double-tap to reset to the middle.

signal changed(value: Vector2) # x: curve -1..1, y: spin -1 (runner) .. +1 (max back)

var value := Vector2.ZERO
var _last_tap := 0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed:
		var now := Time.get_ticks_msec()
		if now - _last_tap < 300:
			_apply(Vector2.ZERO)
		else:
			_set_from(e.position)
		_last_tap = now
		accept_event()
	elif e is InputEventScreenDrag:
		_set_from(e.position)
		accept_event()


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 24.0


func _set_from(p: Vector2) -> void:
	var v := (p - size * 0.5) / _radius()
	if v.length() > 1.0:
		v = v.normalized()
	# Snap near the middle and the axes so "straight" is easy to pick.
	if absf(v.x) < 0.08:
		v.x = 0.0
	if absf(v.y) < 0.08:
		v.y = 0.0
	_apply(v)


func _apply(v: Vector2) -> void:
	value = v
	queue_redraw()
	changed.emit(Vector2(v.x, v.y))


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	var f := get_theme_default_font()
	draw_circle(c, r + 4, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Color(0.96, 0.96, 0.94))
	# Dimple hint rings.
	for k in [0.33, 0.66]:
		draw_arc(c, r * k, 0, TAU, 40, Color(0.75, 0.75, 0.75, 0.6), 1.5, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Color(0.7, 0.7, 0.7, 0.7), 1.5)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Color(0.7, 0.7, 0.7, 0.7), 1.5)
	var dot := c + value * r
	draw_circle(dot, 15, Color(0.85, 0.15, 0.15))
	draw_circle(dot, 6, Color(1, 1, 1))
	_label(f, "Runner", c + Vector2(0, -r - 6), true)
	_label(f, "Spin", c + Vector2(0, r + 20), true)
	_label(f, "Draw", c + Vector2(-r * 0.62, -8), true, false, Color(0.35, 0.35, 0.35))
	_label(f, "Fade", c + Vector2(r * 0.62, -8), true, false, Color(0.35, 0.35, 0.35))


func _label(f: Font, t: String, at: Vector2, centered: bool, right_align := false, inside := Color(0, 0, 0, 0)) -> void:
	var fs := 18
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := at.x - w * 0.5 if centered else (at.x - w if right_align else at.x)
	if inside.a > 0.0:
		draw_string(f, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, inside)
		return
	draw_string_outline(f, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(x, at.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9))


## Human-readable summary of a spin value.
static func describe(v: Vector2) -> String:
	var spin := "Stock spin"
	if v.y > 0.66:
		spin = "Max spin"
	elif v.y > 0.2:
		spin = "Extra spin"
	elif v.y < -0.66:
		spin = "Big runner"
	elif v.y < -0.2:
		spin = "Runner"
	var curve := ""
	if v.x < -0.5:
		curve = " · Big draw"
	elif v.x < -0.01:
		curve = " · Draw"
	elif v.x > 0.5:
		curve = " · Big fade"
	elif v.x > 0.01:
		curve = " · Fade"
	return spin + curve
