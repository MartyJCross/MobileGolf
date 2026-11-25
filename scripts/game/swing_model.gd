class_name SwingModel
extends RefCounted
## A golf swing as a double pendulum: arms (hub at the shoulders -> hands)
## and club (hands -> clubhead), hinged at the wrists. This is the classic
## model from golf research (Cochran & Stobbs, Jorgensen).
##
## Controls:
##   hold  : backswing. Arms turn back and the wrists cock. Hold longer for a
##           longer swing (half, three-quarter, full, over-swing).
##   lift  : transition. The body's torque drives the arms down; the wrists
##           hold the club cocked (lag), so arms + club turn as one piece.
##   tap   : release. The wrists unhinge and fire the club through (an
##           active wrist torque on top of the arms' whip; no scripted
##           animation, it's the physics). No tap: the wrists give way on
##           their own when the torque needed to keep the lag exceeds their
##           strength (~40 ms late) and the club only swings through
##           passively: a weak push-slice.
##
## Impact is when the clubhead reaches the bottom of its arc (the ball).
## What timing does, all from the physics:
##   * Clubhead speed peaks for one release moment. Early (casting) or late
##     both lose speed (late more: 20 ms late ~ -4%, 50 ms late ~ -13%).
##   * Early: the club has passed the hands at impact (flip) -> added loft,
##     face closing, path out-to-in (pull / hook).
##   * Late: the club still lags the hands (shaft leaning forward) ->
##     delofted, face open, path in-to-out (push / slice).
##   * Either extreme bends the arm-club line, so the clubhead arrives short
##     of the full radius: a thin strike low on the face.
##
## Angles: radians, measured from straight down (address), positive toward
## the target, in the face-on swing plane.

enum State { IDLE, BACKSWING, DOWNSWING, FOLLOW, DONE }

# Body (approximate adult golfer, after Jorgensen "The Physics of Golf").
const L_ARM := 0.62 # hub (between the shoulders) to hands, m
const I_ARM := 1.15 # arms + shoulder turn about the hub, kg m^2
const M_CLUB := 0.40 # kg
const L_CLUB := 0.95 # hands to clubhead (an iron), m
const A_CLUB := 0.72 # hands to club centre of mass, m
const J_CLUB := 0.012 # club about its own centre of mass, kg m^2
const TORQUE_RAMP := 0.06 # s
# Optional "kinematic sequence" braking of the arms into impact. Tuning found
# the active wrist release alone gives the most realistic timing window
# (best release with the lead arm just below horizontal, club in line with
# the arms at impact, ~90 mph with a 7-iron), so braking is off.
static var body_torque := 95.0 # N m
static var brake_start := deg_to_rad(-80.0) # arm angle where braking begins
static var brake_full := deg_to_rad(-25.0) # arm angle where braking is full
static var brake_torque := 0.0 # N m (applied against the arms; 0 = active wrist release does the work)
static var wrist_strength := 37.0 # max torque the wrists hold the lag with, N m (gives way ~40 ms late)
static var release_torque := 25.0 # active wrist torque driving the club through after the tap, N m
const FLIP_STOP := deg_to_rad(55.0) # wrists can't flip the club further than this
const DT := 0.0005 # physics step, s

# Backswing (real time while holding).
const FULL_TOP := deg_to_rad(-150.0) # arms at the top of a full swing
const MAX_TOP := deg_to_rad(-170.0) # furthest over-swing
const FULL_TIME := 1.0 # s of holding to reach a full backswing
const MAX_COCK := deg_to_rad(-90.0) # wrist cock at the top (club lags the arms)

# Mapping impact geometry to the strike.
const FACE_PER_LAG := 0.22 # deg face-to-path per deg of lag error (late = open)
const PATH_PER_LAG := 0.10 # deg path per deg of lag error (late = in-to-out)
const LOFT_PER_LAG := 0.45 # deg dynamic loft per deg (late = delofted)
const AOA_PER_LAG := 0.15 # deg attack angle per deg (late = steeper)
const THIN_PER_MM := 0.12 # strike height (mm low) per mm radius shortfall
const MAX_THIN_MM := 12.0 # worst thin strike (golfers still get the club to the ball)
const LOFT_LIMITS := Vector2(-12.0, 10.0) # deg
const AOA_LIMITS := Vector2(-5.0, 4.0) # deg

class Result:
	var swing := LaunchModel.Swing.new()
	var speed_frac := 0.0 # clubhead speed vs a perfect full swing
	var backswing := 0.0 # 1.0 = full
	var lag_deg := 0.0 # club angle relative to arms at impact (- = lagging)
	var release_error_ms := 0.0 # vs the fastest release, in on-screen time (+ late)
	var released_by_player := true
	var overswing := false

var state: int = State.IDLE
var time_scale := 0.55 # downswing plays in slow motion so humans can time it
var shape := 0.0 # -1 draw .. +1 fade (stance / path set-up)
var rng := RandomNumberGenerator.new()

# Pendulum state
var arm := 0.0 # arm angle
var club := 0.0 # absolute club angle
var w_arm := 0.0
var w_club := 0.0
var released := false # wrists unlocked (by a tap, or giving way)
var tapped := false # player fired the release
var tap_t := -1.0
var tap_arm := 0.0 # arm angle when the player released (for feedback)
var sim_t := 0.0 # downswing time (physical)
var release_t := -1.0
var top := 0.0
var cock_at_top := 0.0
var hold_t := 0.0
var auto_backswing := true # true: backswing grows with hold time; false: follows backswing_target
var backswing_target := 0.0 # arm angle the backswing moves toward (when not auto)
const FOLLOW_RATE := deg_to_rad(320.0) # how fast the arms follow a dragged target, rad/s
var follow_t := 0.0
var result: Result = null


func _init() -> void:
	rng.randomize()


func reset() -> void:
	state = State.IDLE
	arm = 0.0
	club = 0.0
	w_arm = 0.0
	w_club = 0.0
	released = false
	release_t = -1.0
	sim_t = 0.0
	hold_t = 0.0
	result = null
	_auto_released = false
	tapped = false
	tap_t = -1.0


# ------------------------------------------------------------------ controls
# Low-level actions; the control schemes in main.gd map touches onto them.

func begin_backswing(auto := true) -> void:
	if state != State.IDLE:
		return
	state = State.BACKSWING
	hold_t = 0.0
	auto_backswing = auto
	backswing_target = 0.0


## Backswing length as a fraction of a full swing (over 1.0 = over-swing).
func set_backswing_target(frac: float) -> void:
	backswing_target = clampf(frac, 0.0, MAX_TOP / FULL_TOP) * FULL_TOP


## Start the downswing from wherever the arms are. Returns false (and
## cancels) if the club has barely moved.
func start_downswing() -> bool:
	if state != State.BACKSWING:
		return false
	if arm > deg_to_rad(-20.0):
		reset()
		return false
	_start_down()
	return true


func release_club() -> void:
	if state == State.DOWNSWING and not tapped:
		tap_t = sim_t
		tap_arm = arm
		tapped = true
		if not released:
			_release()


func press() -> void:
	if state == State.IDLE:
		state = State.BACKSWING
		hold_t = 0.0
	elif state == State.DOWNSWING and not tapped:
		tap_t = sim_t
		tapped = true
		if not released:
			_release()


func lift() -> void:
	if state == State.BACKSWING:
		if arm > deg_to_rad(-20.0):
			reset() # barely moved: cancel
			return
		_start_down()


## Advance by real (wall-clock) seconds.
func update(real_dt: float) -> void:
	match state:
		State.BACKSWING:
			hold_t += real_dt
			if auto_backswing:
				arm = backswing_arm(hold_t)
			else:
				arm = move_toward(arm, backswing_target, FOLLOW_RATE * real_dt)
			club = arm + cock_for(arm)
		State.DOWNSWING:
			var target := sim_t + real_dt * time_scale
			while state == State.DOWNSWING and sim_t < target:
				_step()
		State.FOLLOW:
			# Let the club swing on to a finish (visual only).
			follow_t += real_dt
			var k := clampf(follow_t / 0.6, 0.0, 1.0)
			var ease := 1.0 - pow(1.0 - k, 3.0)
			arm = lerpf(_follow_from.x, deg_to_rad(150.0), ease)
			club = lerpf(_follow_from.y, deg_to_rad(250.0), ease)
			if k >= 1.0:
				state = State.DONE

var _follow_from := Vector2.ZERO


static func backswing_arm(t: float) -> float:
	if t <= FULL_TIME:
		var k := t / FULL_TIME
		return FULL_TOP * (0.5 - 0.5 * cos(k * PI))
	var over := clampf((t - FULL_TIME) / 0.35, 0.0, 1.0)
	return lerpf(FULL_TOP, MAX_TOP, sin(over * PI * 0.5))


## Wrist cock as the arms go back: none at first, full by arms ~horizontal.
static func cock_for(arm_angle: float) -> float:
	var k := clampf((-arm_angle - deg_to_rad(20.0)) / deg_to_rad(90.0), 0.0, 1.0)
	return MAX_COCK * k * k * (3.0 - 2.0 * k)


func backswing_fraction() -> float:
	return arm / FULL_TOP


# ------------------------------------------------------------------ physics

func _start_down() -> void:
	top = arm
	cock_at_top = club - arm
	state = State.DOWNSWING
	sim_t = 0.0
	w_arm = 0.0
	w_club = 0.0
	released = false
	release_t = -1.0
	_auto_released = false
	tapped = false
	tap_t = -1.0


func _release() -> void:
	released = true
	release_t = sim_t


func _torque(t: float) -> float:
	var k := clampf((arm - brake_start) / (brake_full - brake_start), 0.0, 1.0)
	return lerpf(body_torque, -brake_torque, k) * minf(1.0, t / TORQUE_RAMP)


## Mass-matrix terms of the double pendulum.
static func _a() -> float:
	return I_ARM + M_CLUB * L_ARM * L_ARM


static func _b() -> float:
	return M_CLUB * L_ARM * A_CLUB


static func _c() -> float:
	return J_CLUB + M_CLUB * A_CLUB * A_CLUB


func _step() -> void:
	var prev_hx := head().x
	var prev := [arm, club, w_arm, w_club, sim_t]
	var tau := _torque(sim_t)
	var a := _a()
	var b := _b()
	var c := _c()
	var d := club - arm
	if not released:
		# Wrists locked: arms + club rotate as one body.
		var acc := tau / (a + c + 2.0 * b * cos(d))
		# Torque the wrists need to keep the lag; if beyond their strength
		# they give way (natural release).
		var hold := (b * cos(d) + c) * acc + b * sin(d) * w_arm * w_arm
		if hold < -wrist_strength:
			_auto_released = true
			_release()
		else:
			w_arm += acc * DT
			w_club = w_arm
			arm += w_arm * DT
			club = arm + d
	if released:
		var cd := cos(d)
		var sd := sin(d)
		# [a, b cd; b cd, c] [arm''; club''] = [tau + b sd wc^2; -b sd wa^2]
		# Active release: the wrists drive the club until it lines up with the
		# arms (only when the player released; a natural release is passive).
		var tw := release_torque if (tapped and d < 0.0) else 0.0
		var r1 := tau - tw + b * sd * w_club * w_club
		var r2 := tw - b * sd * w_arm * w_arm
		var det := a * c - b * b * cd * cd
		var acc_a := (r1 * c - b * cd * r2) / det
		var acc_c := (a * r2 - b * cd * r1) / det
		w_arm += acc_a * DT
		w_club += acc_c * DT
		arm += w_arm * DT
		club += w_club * DT
		if club - arm > FLIP_STOP:
			# Wrists at their limit: club and arms move together.
			club = arm + FLIP_STOP
			var shared := (w_arm * (a + b) + w_club * (c + b)) / (a + c + 2.0 * b)
			w_arm = shared
			w_club = shared
	sim_t += DT
	var hp := head()
	if prev_hx < 0.0 and hp.x >= 0.0 and hp.y < 0.0:
		# Clubhead passes under the hub (the ball): interpolate to that moment.
		var f := -prev_hx / (hp.x - prev_hx)
		arm = lerpf(prev[0], arm, f)
		club = lerpf(prev[1], club, f)
		w_arm = lerpf(prev[2], w_arm, f)
		w_club = lerpf(prev[3], w_club, f)
		sim_t = lerpf(prev[4], sim_t, f)
		_impact()
	elif sim_t > 2.0:
		_impact()


func hands() -> Vector2:
	return Vector2(sin(arm), -cos(arm)) * L_ARM


func head() -> Vector2:
	return hands() + Vector2(sin(club), -cos(club)) * L_CLUB


## Angle of the clubhead around the hub (0 = at the ball).
func head_angle() -> float:
	var h := head()
	return atan2(h.x, -h.y)


func head_speed() -> float:
	var hv := Vector2(cos(arm), sin(arm)) * L_ARM * w_arm
	var cv := Vector2(cos(club), sin(club)) * L_CLUB * w_club
	return (hv + cv).length()


func _impact() -> void:
	if analysis:
		state = State.DONE
		return
	var r := Result.new()
	var ideal := ideal_for(top)
	r.speed_frac = head_speed() / reference_speed()
	r.backswing = top / FULL_TOP
	r.overswing = top < FULL_TOP - deg_to_rad(5.0)
	r.released_by_player = tapped
	var lag := club - arm
	r.lag_deg = rad_to_deg(lag)
	# Error vs the lag a perfectly timed release gives for this backswing:
	# + = early (club flipped past the hands), - = late (still lagging).
	var e := rad_to_deg(lag - ideal.y)
	var shortfall_mm := maxf(0.0, (ideal.z - head().length()) * 1000.0)
	r.release_error_ms = ((tap_t - ideal.x) / time_scale * 1000.0) if tapped else INF

	var sw := r.swing
	sw.speed_frac = r.speed_frac
	sw.path_deg = -4.0 * shape - PATH_PER_LAG * e
	sw.face_to_path_deg = 3.0 * shape - FACE_PER_LAG * e
	sw.strike_high_mm = -minf(shortfall_mm * THIN_PER_MM, MAX_THIN_MM)
	sw.loft_offset_deg = clampf(LOFT_PER_LAG * e, LOFT_LIMITS.x, LOFT_LIMITS.y)
	sw.aoa_offset_deg = clampf(AOA_PER_LAG * e, AOA_LIMITS.x, AOA_LIMITS.y)
	if r.overswing:
		var wild := clampf((FULL_TOP - top) / (FULL_TOP - MAX_TOP), 0.0, 1.0)
		sw.face_to_path_deg += rng.randfn(0.0, 1.5 * wild)
		sw.strike_toe_mm = rng.randfn(0.0, 6.0 * wild)
	result = r
	_follow_from = Vector2(arm, club)
	follow_t = 0.0
	state = State.FOLLOW

var analysis := false # headless run used for optimisation: no result
var _auto_released := false


# ------------------------------------------------------------------ analysis

## Runs a whole downswing headlessly. release_at < 0 = never tap.
static func simulate(top_angle: float, cock: float, release_at: float, scale := 1.0) -> SwingModel:
	var m := SwingModel.new()
	m.time_scale = scale
	m.arm = top_angle
	m.club = top_angle + cock
	m.analysis = true
	m._start_down()
	m.top = top_angle
	m.cock_at_top = cock
	while m.state == State.DOWNSWING:
		if release_at >= 0.0 and not m.tapped and m.sim_t >= release_at:
			m.tapped = true
			m.tap_t = m.sim_t
			if not m.released:
				m._release()
		m._step()
	return m


## Physical release time that gives the most clubhead speed.
static func optimal_release_time(top_angle: float, cock: float) -> float:
	var natural := simulate(top_angle, cock, -1.0)
	var hi: float = natural.release_t if natural.release_t > 0.0 else natural.sim_t
	var lo := 0.0
	# Golden-section search on clubhead speed.
	var g := 0.6180339887
	var x1 := hi - g * (hi - lo)
	var x2 := lo + g * (hi - lo)
	var f1 := _speed_at(top_angle, cock, x1)
	var f2 := _speed_at(top_angle, cock, x2)
	for i in 22:
		if f1 > f2:
			hi = x2
			x2 = x1
			f2 = f1
			x1 = hi - g * (hi - lo)
			f1 = _speed_at(top_angle, cock, x1)
		else:
			lo = x1
			x1 = x2
			f1 = f2
			x2 = lo + g * (hi - lo)
			f2 = _speed_at(top_angle, cock, x2)
	return (lo + hi) * 0.5


static func _speed_at(top_angle: float, cock: float, t: float) -> float:
	var m := simulate(top_angle, cock, t)
	return m.v_raw


## The perfect release for each backswing length, precomputed once
## (build_table, ideally on a worker thread at start-up) and interpolated.
## Each entry: Vector4(top angle, best tap time, lag at impact, head radius).
const TABLE_STEP := deg_to_rad(10.0)
static var _table: Array = []
static var _release_arms: Array = [] # arm angle at the perfect release, per table entry
static var _ref_cache := -1.0
static var _table_mutex := Mutex.new()


static func build_table() -> void:
	var t: Array = []
	var ra: Array = []
	var a := deg_to_rad(-30.0)
	while a >= MAX_TOP - 0.001:
		var cock := cock_for(a)
		var best := optimal_release_time(a, cock)
		var m := simulate(a, cock, best)
		t.append(Vector4(a, best, m.club - m.arm, m.head().length()))
		ra.append(_arm_at_time(a, cock, best))
		a -= TABLE_STEP
	var full := simulate(FULL_TOP, MAX_COCK, optimal_release_time(FULL_TOP, MAX_COCK)).v_raw
	_table_mutex.lock()
	_table = t
	_release_arms = ra
	_ref_cache = full
	_table_mutex.unlock()


static func table_ready() -> bool:
	return not _table.is_empty()


## Arm angle after `t` seconds of downswing with the wrists still locked.
static func _arm_at_time(top_angle: float, cock: float, t: float) -> float:
	var m := SwingModel.new()
	m.analysis = true
	m.arm = top_angle
	m.club = top_angle + cock
	m._start_down()
	while m.sim_t < t and m.state == State.DOWNSWING:
		m._step()
	return m.arm


## Where the hands should be when you release (arm angle), for a top angle.
static func ideal_release_arm(top_angle: float) -> float:
	if _table.is_empty():
		build_table()
	var t := _table
	if top_angle >= t[0].x:
		return _release_arms[0]
	for i in t.size() - 1:
		if top_angle <= t[i].x and top_angle >= t[i + 1].x:
			var f: float = (top_angle - t[i].x) / (t[i + 1].x - t[i].x)
			return lerpf(_release_arms[i], _release_arms[i + 1], f)
	return _release_arms[_release_arms.size() - 1]


## Vector3(best tap time, ideal lag, head radius) for a given top angle.
static func ideal_for(top_angle: float) -> Vector3:
	if _table.is_empty():
		build_table()
	var t := _table
	if top_angle >= t[0].x:
		return Vector3(t[0].y, t[0].z, t[0].w)
	for i in t.size() - 1:
		var p: Vector4 = t[i]
		var q: Vector4 = t[i + 1]
		if top_angle <= p.x and top_angle >= q.x:
			var f := (top_angle - p.x) / (q.x - p.x)
			var v := p.lerp(q, f)
			return Vector3(v.y, v.z, v.w)
	var l: Vector4 = t[t.size() - 1]
	return Vector3(l.y, l.z, l.w)


## Clubhead speed of the best possible full swing (normalises speed_frac).
static func reference_speed() -> float:
	if _ref_cache < 0.0:
		build_table()
	return _ref_cache


var v_raw: float:
	get:
		return head_speed()
