class_name BallSim
extends RefCounted
## Golf ball flight, bounce and roll.
##
## Flight: gravity + aerodynamic drag + Magnus lift, integrated with RK4.
##   Drag and lift coefficients depend on spin ratio S = r*w/v, calibrated
##   so full shots match published tour carry / apex / landing angle.
##   Spin decays in flight. Wind uses a log profile, so it is stronger at
##   apex than near the ground.
## Impact: rigid-sphere impulse model with Coulomb friction (the ball either
##   grips and leaves rolling, or skids), restitution that falls with impact
##   speed, and Penner's "crater" correction: a ball landing fast and steep
##   sinks in, so the effective surface tilts back toward it. That plus
##   backspin is what makes the ball check or spin back.
## Ground: skidding with kinetic friction until the contact point stops
##   slipping, then rolling (5/7 g on slopes) with rolling resistance.
##
## The whole shot is deterministic, so the game simulates it to completion
## instantly and plays back the recorded frames.

enum Phase { FLIGHT, GROUND, STOPPED, WATER, HOLED }

const MASS := 0.04593 # kg
const RADIUS := 0.021335 # m
const AREA := PI * RADIUS * RADIUS
const INERTIA_K := 0.4 # I = k m r^2 (solid sphere; balls are close to this)
const INERTIA := INERTIA_K * MASS * RADIUS * RADIUS
const RHO := 1.204 # air density, kg/m^3 (20 C, sea level)
const G := 9.81
const DT := 1.0 / 240.0
const RECORD_DT := 1.0 / 60.0
const CUP_RADIUS := 0.054
const CUP_CAPTURE_SPEED := 1.3 # faster than this and the ball lips over
const MIN_BOUNCE_SPEED := 0.4 # below this normal speed the ball stays down
const SLIP_EPS := 0.03
const STOP_SPEED := 0.03
const MAX_TIME := 45.0
# Rolling resistance = roll * (ROLL_STATIC + ROLL_SPEED * v). Fitted so a
# green with roll 0.5 is Stimp 11 (1.83 m/s -> 3.35 m) and a resting ball
# only starts to move on slopes steeper than ~4.3%.
const ROLL_STATIC := 0.6
const ROLL_SPEED := 0.344
const SPIN_DECAY_PER_M := 0.00002 / RADIUS # spin e-folds per metre travelled

# Aerodynamic model, fitted to TrackMan tour averages for 3-iron..PW
# (tests/calibrate.gd). Result: carry within 2.5%, landing angle within 2 deg,
# apex a little high (up to ~20% on long irons). Spin decay is held at a
# realistic rate rather than fitted, so landing spin stays honest.
#   Cd = cd0 + cd_spin*S + cd_speed*(v-40)/40 + low-Re drag rise below ~16 m/s
#   Cl = cl0 + cl_k * S^cl_pow   (capped at cl_max)
var cd0 := 0.348
var cd_spin := 0.0
var cl0 := 0.023 # lift intercept
var cl_k := 0.519
var cl_pow := 0.506
var cl_max := 0.60
var cd_low_re := 0.121 # drag rise below the drag crisis (slow balls)
var cd_speed := -0.340 # linear Reynolds-number trend of drag around 40 m/s
var spin_decay := 1.2 # multiplier on SPIN_DECAY_PER_M

var terrain: GolfTerrain
var rng := RandomNumberGenerator.new()

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var phase: int = Phase.FLIGHT
var time := 0.0

# Recorded playback (every RECORD_DT)
var frames := PackedVector3Array()
var frame_spin := PackedVector3Array()
var frame_phase := PackedInt32Array()

# Shot stats
var start_pos := Vector3.ZERO
var landed := false
var carry_pos := Vector3.ZERO
var carry_time := 0.0
var land_angle_deg := 0.0
var land_speed := 0.0
var land_spin_rpm := 0.0
var land_surface: int = -1
var apex := 0.0
var bounces := 0
var hit_tree := false
var water_pos := Vector3.ZERO
var _trees_hit := {}
var _record_acc := 0.0


func _init(t: GolfTerrain = null) -> void:
	terrain = t if t != null else GolfTerrain.new()
	rng.seed = 12345


func launch(from: Vector3, velocity: Vector3, spin_vec: Vector3) -> void:
	pos = from
	start_pos = from
	vel = velocity
	spin = spin_vec
	phase = Phase.FLIGHT
	time = 0.0
	landed = false
	apex = 0.0
	bounces = 0
	hit_tree = false
	_trees_hit.clear()
	frames.clear()
	frame_spin.clear()
	frame_phase.clear()
	_record_acc = 0.0
	_record()


func is_done() -> bool:
	return phase == Phase.STOPPED or phase == Phase.WATER or phase == Phase.HOLED


func simulate(max_time: float = MAX_TIME) -> void:
	while not is_done() and time < max_time:
		step(DT)
	if not is_done():
		phase = Phase.STOPPED
	_record()


## Run only the flight to the first landing (used by calibration).
func simulate_flight() -> void:
	while phase == Phase.FLIGHT and not landed and time < MAX_TIME:
		step(DT)


func step(dt: float) -> void:
	match phase:
		Phase.FLIGHT:
			_flight_step(dt)
		Phase.GROUND:
			_ground_step(dt)
		_:
			return
	time += dt
	_record_acc += dt
	if _record_acc >= RECORD_DT - 1e-9:
		_record_acc -= RECORD_DT
		_record()


func _record() -> void:
	frames.append(pos)
	frame_spin.append(spin)
	frame_phase.append(phase)


func spin_rpm() -> float:
	return spin.length() / LaunchModel.RPM_TO_RADS


func carry_distance() -> float:
	var d := carry_pos - start_pos
	return Vector2(d.x, d.z).length()


func total_distance() -> float:
	var end := water_pos if phase == Phase.WATER else pos
	var d := end - start_pos
	return Vector2(d.x, d.z).length()


# ---------------------------------------------------------------- flight

func _accel(p: Vector3, v: Vector3, w: Vector3) -> Vector3:
	var a := Vector3(0.0, -G, 0.0)
	var h := p.y - terrain.get_height(p.x, p.z)
	var vrel := v - terrain.wind_at(h)
	var speed := vrel.length()
	if speed < 0.05:
		return a
	var w_perp := w - vrel * (w.dot(vrel) / (speed * speed))
	var s := RADIUS * w_perp.length() / speed
	var cd := cd0 + cd_spin * s
	var t := clampf((16.0 - speed) / 6.0, 0.0, 1.0)
	cd += cd_low_re * t * t * (3.0 - 2.0 * t)
	cd = maxf(0.05, cd + cd_speed * (speed - 40.0) / 40.0)
	var cl := minf(cl0 + cl_k * pow(s, cl_pow), cl_max)
	var q := 0.5 * RHO * AREA * speed * speed / MASS
	a -= vrel / speed * (cd * q)
	var lift := w.cross(vrel)
	var ll := lift.length()
	if ll > 1e-9:
		a += lift / ll * (cl * q)
	return a


func _flight_step(dt: float) -> void:
	var p0 := pos
	var v0 := vel
	var k1v := _accel(p0, v0, spin)
	var k1p := v0
	var k2p := v0 + k1v * (dt * 0.5)
	var k2v := _accel(p0 + k1p * (dt * 0.5), k2p, spin)
	var k3p := v0 + k2v * (dt * 0.5)
	var k3v := _accel(p0 + k2p * (dt * 0.5), k3p, spin)
	var k4p := v0 + k3v * dt
	var k4v := _accel(p0 + k3p * dt, k4p, spin)
	pos = p0 + (k1p + k2p * 2.0 + k3p * 2.0 + k4p) * (dt / 6.0)
	vel = v0 + (k1v + k2v * 2.0 + k3v * 2.0 + k4v) * (dt / 6.0)
	spin *= exp(-SPIN_DECAY_PER_M * spin_decay * v0.length() * dt)

	if not landed:
		apex = maxf(apex, pos.y - start_pos.y)

	_check_trees()

	var c0 := p0.y - RADIUS - terrain.get_contact_height(p0.x, p0.z)
	var c1 := pos.y - RADIUS - terrain.get_contact_height(pos.x, pos.z)
	if c1 <= 0.0:
		var f := 1.0
		if c0 > 0.0:
			f = c0 / (c0 - c1)
		pos = p0.lerp(pos, f)
		vel = v0.lerp(vel, f)
		pos.y = terrain.get_contact_height(pos.x, pos.z) + RADIUS
		_impact()


func _check_trees() -> void:
	for i in terrain.trees.size():
		if _trees_hit.has(i):
			continue
		var t: Dictionary = terrain.trees[i]
		if pos.distance_to(t["pos"]) < t["r"]:
			_trees_hit[i] = true
			hit_tree = true
			# Branches: kill most of the speed, scatter direction, drop it.
			var sp := vel.length() * rng.randf_range(0.1, 0.35)
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.3), rng.randf_range(-1, 1))
			vel = (vel.normalized() * 0.4 + d.normalized()).normalized() * sp
			spin *= 0.2


# ---------------------------------------------------------------- impact

## Coefficient of restitution of a golf ball on a green vs normal impact
## speed (Penner 2002). Bouncy when slow, dead when fast.
static func green_cor(vn: float) -> float:
	if vn <= 20.0:
		return 0.510 - 0.0375 * vn + 0.000903 * vn * vn
	return 0.120


func _impact() -> void:
	var s := terrain.get_surface(pos.x, pos.z)
	if not landed:
		landed = true
		carry_pos = pos
		carry_time = time
		land_speed = vel.length()
		land_angle_deg = rad_to_deg(atan2(-vel.y, Vector2(vel.x, vel.z).length()))
		land_spin_rpm = spin_rpm()
		land_surface = s

	if s == Surface.WATER:
		phase = Phase.WATER
		water_pos = pos
		return

	# Dunk: lands straight in the cup.
	if _cup_dist() < CUP_RADIUS - RADIUS * 0.5:
		phase = Phase.HOLED
		return

	var prm := terrain.surface_params(pos.x, pos.z)
	var n := terrain.get_normal(pos.x, pos.z)
	var speed := vel.length()
	var vn_true := vel.dot(n)
	if vn_true >= 0.0 or speed < 1e-4:
		return

	spin *= float(prm["spin_keep"])

	# Penner crater: effective normal tilts back toward the incoming ball.
	var theta_in := asin(clampf(-vn_true / speed, 0.0, 1.0))
	var vt_true := vel - n * vn_true
	var tdir := Vector3.ZERO
	if vt_true.length() > 1e-4:
		tdir = vt_true.normalized()
	var theta_c := deg_to_rad(15.4) * (speed / 18.6) * (theta_in / deg_to_rad(44.4)) * float(prm["crater"])
	theta_c = minf(theta_c, deg_to_rad(35.0))
	var ne := (n * cos(theta_c) - tdir * sin(theta_c)).normalized()
	var vn := vel.dot(ne)
	if vn >= 0.0:
		ne = n
		vn = vn_true

	var e := green_cor(-vn) * float(prm["restitution_scale"])
	var jn := MASS * (1.0 + e) * (-vn)
	var rc := -ne * RADIUS
	var u := (vel - ne * vn) + spin.cross(rc)
	u -= ne * u.dot(ne)
	var jt := Vector3.ZERO
	var ul := u.length()
	if ul > 1e-6:
		var stick := MASS * ul / (1.0 + 1.0 / INERTIA_K) # 2/7 m u for a solid sphere
		var limit := float(prm["friction"]) * jn
		jt = -u / ul * minf(stick, limit)
	vel += (ne * jn + jt) / MASS
	spin += rc.cross(jt) / INERTIA
	bounces += 1

	if vel.dot(n) < MIN_BOUNCE_SPEED:
		vel -= n * vel.dot(n)
		phase = Phase.GROUND
	pos.y = terrain.get_contact_height(pos.x, pos.z) + RADIUS + 0.0005


# ---------------------------------------------------------------- ground

func _cup_dist() -> float:
	return Vector2(pos.x - terrain.pin.x, pos.z - terrain.pin.z).length()


func _ground_step(dt: float) -> void:
	var s := terrain.get_surface(pos.x, pos.z)
	if s == Surface.WATER:
		phase = Phase.WATER
		water_pos = pos
		return
	var prm := terrain.surface_params(pos.x, pos.z)
	var n := terrain.get_normal(pos.x, pos.z)
	var gvec := Vector3(0.0, -G, 0.0)
	var gt := gvec - n * gvec.dot(n)
	var gn := -gvec.dot(n)
	vel -= n * vel.dot(n)
	var rc := -n * RADIUS
	var u := vel + spin.cross(rc)
	u -= n * u.dot(n)

	if u.length() > SLIP_EPS:
		# Skidding: kinetic friction drags the contact point toward rest,
		# trading speed for spin (backspin can reverse the ball here).
		var f := -u.normalized() * float(prm["friction"]) * MASS * gn
		vel += (gt + f / MASS) * dt
		spin += rc.cross(f) / INERTIA * dt
		var u2 := vel + spin.cross(rc)
		u2 -= n * u2.dot(n)
		if u2.dot(u) <= 0.0:
			spin = n.cross(vel) / RADIUS + n * spin.dot(n)
	else:
		var roll := float(prm["roll"])
		var v_new := vel + gt / (1.0 + INERTIA_K) * dt
		var sp := v_new.length()
		var dec := roll * (ROLL_STATIC + ROLL_SPEED * sp) * dt
		if sp <= dec:
			v_new = Vector3.ZERO
		else:
			v_new *= (sp - dec) / sp
		vel = v_new
		spin = n.cross(vel) / RADIUS + n * spin.dot(n)
	# Spin about the vertical (left from sidespin) dies quickly in contact.
	var wn := spin.dot(n)
	spin -= n * wn * (1.0 - exp(-6.0 * dt))

	pos += vel * dt
	pos.y = terrain.get_height(pos.x, pos.z) + RADIUS

	var cd := _cup_dist()
	if cd < CUP_RADIUS and vel.length() < CUP_CAPTURE_SPEED:
		phase = Phase.HOLED
		pos = Vector3(terrain.pin.x, terrain.get_height(terrain.pin.x, terrain.pin.z) - 0.06, terrain.pin.z)
		vel = Vector3.ZERO
		return

	var roll_now := float(prm["roll"])
	if vel.length() < STOP_SPEED and gt.length() / (1.0 + INERTIA_K) <= roll_now * ROLL_STATIC:
		phase = Phase.STOPPED
		vel = Vector3.ZERO
		spin = Vector3.ZERO
