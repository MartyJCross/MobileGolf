class_name SwipeSwing
extends RefCounted
## Pull-back-and-swipe swing.
##
##   touch     : address (S)
##   drag down : backswing. How far you pull = power (speed doesn't matter).
##               The deepest point is the top of the backswing (B).
##   swipe up  : downswing; impact when the finger crosses back over S.
##
## Shot shape comes from the two directions:
##   path = direction from B back up to S (the line you pulled along)
##   face = direction of the forward swipe from B to where it crosses S
## Straight back and straight through = straight. Through to the right of
## your backswing line = face open to the path = fade (left = draw). Pulled
## back to one side and swiped straight through the same line = a push or
## pull that doesn't curve.

enum State { IDLE, BACK, FORWARD, DONE, CANCELLED }

const PULL_FULL := 0.24 # of screen height pulled for 100% power
const MAX_POWER := 1.05 # pulling past full gives a touch more
const MIN_PULL := 0.03 # less than this isn't a swing
const REVERSAL := 0.015 # upward movement from the deepest point that starts the downswing
const PATH_GAIN := 0.35 # screen angle -> club path (deg per deg)
const FACE_GAIN := 0.35 # screen angle -> face angle
const MAX_ANGLE := 12.0

class Result:
	var power := 0.0
	var path_deg := 0.0 # + right
	var face_deg := 0.0 # + right (relative to the aim line)
	var face_to_path_deg := 0.0

var state: int = State.IDLE
var screen_h := 1560.0
var start := Vector2.ZERO # S
var top := Vector2.ZERO # B
var finger := Vector2.ZERO
var trail: Array[Vector2] = []
var result: Result = null
var hint := ""


func _init(h := 1560.0) -> void:
	screen_h = h


func reset() -> void:
	state = State.IDLE
	trail.clear()
	result = null


func touch_down(p: Vector2) -> void:
	reset()
	hint = ""
	state = State.BACK
	start = p
	top = p
	finger = p
	trail.append(p)


func touch_move(p: Vector2) -> void:
	finger = p
	match state:
		State.BACK:
			trail.append(p)
			if p.y >= top.y:
				top = p
			elif top.y - p.y > REVERSAL * screen_h and _pull() >= MIN_PULL:
				state = State.FORWARD
		State.FORWARD:
			var prev: Vector2 = trail[trail.size() - 1]
			trail.append(p)
			if p.y <= start.y and prev.y > start.y:
				var f := (prev.y - start.y) / maxf(prev.y - p.y, 1e-6)
				_impact(prev.lerp(p, f))


func touch_up(p: Vector2) -> void:
	match state:
		State.BACK:
			state = State.CANCELLED
			hint = "Pull back, then swipe up through the ball"
		State.FORWARD:
			touch_move(p)
			if state == State.FORWARD:
				# Let go before reaching the ball: count it if nearly there.
				if (top.y - p.y) / maxf(top.y - start.y, 1.0) > 0.7:
					_impact(Vector2(p.x, start.y))
				else:
					state = State.CANCELLED
					hint = "Swipe all the way up through the ball"


func _pull() -> float:
	return (top.y - start.y) / screen_h


## Power of the backswing so far (1.0 = full).
func power() -> float:
	if state == State.IDLE:
		return 0.0
	return clampf(_pull() / PULL_FULL, 0.0, MAX_POWER)


static func screen_angle(v: Vector2) -> float:
	# Angle of an upward movement from straight up, degrees, + = to the right.
	return rad_to_deg(atan2(v.x, -v.y))


func _impact(c: Vector2) -> void:
	var r := Result.new()
	r.power = power()
	r.path_deg = clampf(screen_angle(start - top) * PATH_GAIN, -MAX_ANGLE, MAX_ANGLE)
	r.face_deg = clampf(screen_angle(c - top) * FACE_GAIN, -MAX_ANGLE, MAX_ANGLE)
	r.face_to_path_deg = r.face_deg - r.path_deg
	result = r
	state = State.DONE
