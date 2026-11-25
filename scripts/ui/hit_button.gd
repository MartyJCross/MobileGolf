class_name HitButton
extends Control
## The swing: a big HIT button with an accuracy needle sweeping across a bar.
## Tap when the needle is in the green middle for a pure strike. Off-centre
## pushes or pulls the shot a little (right = pushed and a touch long, left
## = pulled and a touch short). With the meter turned off every strike is pure.

signal hit(error: float) # -1..1, 0 = perfect

const PERIOD := 1.7 # seconds for a full left-right-left sweep
const PERFECT := 0.12 # half-width of the green zone

var meter_on := true
var enabled := true
var _t := 0.0


func _process(delta: float) -> void:
	if visible and enabled:
		_t += delta
		queue_redraw()


func needle() -> float:
	if not meter_on:
		return 0.0
	# Triangle wave -1..1.
	var ph := fposmod(_t / PERIOD, 1.0)
	return 4.0 * absf(ph - 0.5) - 1.0


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch and e.pressed and enabled:
		var n := needle()
		hit.emit(0.0 if absf(n) < PERFECT else n)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var col := Color(0.82, 0.3, 0.18) if enabled else Color(0.35, 0.35, 0.35)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(20)
	sb.border_color = Color(1, 1, 1, 0.5)
	sb.set_border_width_all(3)
	draw_style_box(sb, r)
	var f := get_theme_default_font()
	var t := "HIT"
	var fs := 46
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.47), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if not meter_on:
		return
	# Accuracy bar.
	var bar := Rect2(18, size.y * 0.62, size.x - 36, 22)
	draw_rect(bar, Color(0, 0, 0, 0.45))
	var zone_w := bar.size.x * PERFECT
	draw_rect(Rect2(bar.position.x + bar.size.x * 0.5 - zone_w, bar.position.y, zone_w * 2.0, bar.size.y), Color(0.35, 0.9, 0.4, 0.9))
	var x := bar.position.x + bar.size.x * (0.5 + 0.5 * needle())
	draw_line(Vector2(x, bar.position.y - 6), Vector2(x, bar.end.y + 6), Color.WHITE, 5.0)
