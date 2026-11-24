class_name SwingGesture
extends RefCounted
## Turns a pull-down / flick-up swipe into a golf swing.
##
##   touch     : address (start point)
##   drag down : backswing (length caps the speed you can make)
##   flick up  : downswing; impact happens when the finger crosses back over
##               the start line
##
## Read at impact:
##   speed  - finger speed over the last ~50 ms before impact, in screen
##            heights per second, relative to FULL_SPEED_HPS (x sensitivity)
##   path   - overall angle of the downswing (tilted right = in-to-out)
##   face   - how much the swipe curves: bending right through impact opens
##            the face to the path (fade/slice), bending left closes it
##            (draw/hook). The ball curves the way your swipe curves.
## Over 100% speed the swing gets wild: random face and strike errors grow.

enum State { IDLE, BACKSWING, DOWNSWING, DONE, CANCELLED }

const FULL_SPEED_HPS := 3.0 # screen heights / second for a 100% swing
const MIN_SPEED := 0.15
const MAX_SPEED := 1.10
const MIN_BACKSWING := 0.05 # of screen height
const FULL_BACKSWING := 0.16
const REVERSAL := 0.015 # upward travel that starts the downswing
const SPEED_WINDOW := 0.05 # seconds
const PATH_GAIN := 0.35 # swipe tilt (deg) -> club path (deg)
const FACE_GAIN := 0.6 # swipe bend (deg) -> face to path (deg)
const MAX_PATH := 12.0
const MAX_FACE_TO_PATH := 14.0

class Result:
	var swing := LaunchModel.Swing.new()
	var speed_frac := 0.0
	var backswing := 0.0 # fraction of FULL_BACKSWING
	var tilt_deg := 0.0
	var bend_deg := 0.0
	var overswing := false

var state: int = State.IDLE
var screen_h := 1560.0
var sensitivity := 1.0
var rng := RandomNumberGenerator.new()

var start := Vector2.ZERO
var top := Vector2.ZERO
var points: Array[Vector2] = []
var times: Array[float] = []
var result: Result = null


func _init(height_px := 1560.0) -> void:
	screen_h = height_px
	rng.randomize()


func reset() -> void:
	state = State.IDLE
	points.clear()
	times.clear()
	result = null


func touch_down(p: Vector2, t: float) -> void:
	reset()
	state = State.BACKSWING
	start = p
	top = p


func touch_move(p: Vector2, t: float) -> void:
	match state:
		State.BACKSWING:
			if p.y > top.y:
				top = p
			elif top.y - p.y > REVERSAL * screen_h:
				if (top.y - start.y) / screen_h < MIN_BACKSWING:
					return # not a real backswing yet; keep waiting
				state = State.DOWNSWING
				points = [top]
				times = [t - 0.001]
				_add(p, t)
		State.DOWNSWING:
			_add(p, t)


func touch_up(p: Vector2, t: float) -> void:
	if state == State.DOWNSWING:
		_add(p, t)
		if state == State.DOWNSWING:
			# Released before reaching the ball: count it if nearly there.
			var travelled := (top.y - p.y) / maxf(top.y - start.y, 1.0)
			if travelled > 0.75:
				_impact(p, t)
			else:
				state = State.CANCELLED
	elif state == State.BACKSWING:
		state = State.CANCELLED


## Fraction of a full backswing reached so far (for the on-screen meter).
func backswing_amount() -> float:
	return clampf((top.y - start.y) / (FULL_BACKSWING * screen_h), 0.0, 1.0)


func _add(p: Vector2, t: float) -> void:
	var prev := points[points.size() - 1]
	var prev_t := times[times.size() - 1]
	if p.y <= start.y and prev.y > start.y:
		# Crossed the start line: interpolate the exact impact point and time.
		var f := (prev.y - start.y) / maxf(prev.y - p.y, 1e-6)
		var ip := prev.lerp(p, f)
		var it := lerpf(prev_t, t, f)
		points.append(ip)
		times.append(it)
		_impact(ip, it)
		return
	points.append(p)
	times.append(t)


func _impact(_p: Vector2, t_impact: float) -> void:
	var r := Result.new()
	var n := points.size()
	# Speed over the final window.
	var i0 := n - 1
	while i0 > 0 and t_impact - times[i0 - 1] <= SPEED_WINDOW:
		i0 -= 1
	if i0 == n - 1 and n >= 2:
		i0 = n - 2
	var dist := 0.0
	for i in range(i0, n - 1):
		dist += points[i].distance_to(points[i + 1])
	var dt := maxf(times[n - 1] - times[i0], 1e-3)
	var hps := dist / dt / screen_h
	var raw := hps / FULL_SPEED_HPS * sensitivity
	r.backswing = clampf(((top.y - start.y) / screen_h - MIN_BACKSWING) / (FULL_BACKSWING - MIN_BACKSWING), 0.0, 1.0)
	var cap := lerpf(0.55, MAX_SPEED, r.backswing)
	r.speed_frac = clampf(minf(raw, cap), MIN_SPEED, MAX_SPEED)

	# Path from the overall direction, face from the bend.
	var end_p := points[n - 1]
	var overall := end_p - top
	r.tilt_deg = rad_to_deg(atan2(overall.x, -overall.y))
	var mid := _point_at_fraction(0.5)
	var first := mid - top
	var second := end_p - mid
	if first.length() > 2.0 and second.length() > 2.0:
		r.bend_deg = rad_to_deg(wrapf(atan2(second.x, -second.y) - atan2(first.x, -first.y), -PI, PI))

	var sw := r.swing
	sw.speed_frac = r.speed_frac
	sw.path_deg = clampf(r.tilt_deg * PATH_GAIN, -MAX_PATH, MAX_PATH)
	sw.face_to_path_deg = clampf(r.bend_deg * FACE_GAIN, -MAX_FACE_TO_PATH, MAX_FACE_TO_PATH)
	if r.speed_frac > 1.0:
		r.overswing = true
		var wild := (r.speed_frac - 1.0) / (MAX_SPEED - 1.0) # 0..1
		sw.face_to_path_deg += rng.randfn(0.0, 1.0 + 5.0 * wild)
		sw.strike_toe_mm = rng.randfn(0.0, 3.0 + 10.0 * wild)
		sw.strike_high_mm = rng.randfn(0.0, 2.0 + 6.0 * wild)
	result = r
	state = State.DONE


func _point_at_fraction(f: float) -> Vector2:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var target := total * f
	var acc := 0.0
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if acc + seg >= target:
			return points[i].lerp(points[i + 1], (target - acc) / maxf(seg, 1e-6))
		acc += seg
	return points[points.size() - 1]
