class_name LaunchModel
extends RefCounted
## Club delivery -> ball launch, using the D-plane.
##
## Frame (matches Godot): +X right, +Y up, -Z toward the target.
## Angles in degrees. Positive path / face = pointing right of target
## (for a right-handed golfer: in-to-out path, open face).
##
## How it works:
##   * The club head travels along `c` (set by swing path + attack angle).
##   * The face points along `n` (set by face angle + dynamic loft).
##   * The angle between them is the spin loft. The plane containing them is
##     the D-plane; the ball spins about the axis perpendicular to it
##     (c x n). So face-to-path alone decides how much the spin axis tilts,
##     i.e. draw / fade / hook / slice, exactly as on a launch monitor.
##   * Launch direction lies between c and n, mostly following the face.
##   * Ball speed falls off with cos(spin loft); spin grows with
##     club speed * sin(spin loft). Both are anchored to the club's
##     published stock numbers so a stock swing reproduces them exactly.

const LAUNCH_FACE_RATIO := 0.80 # share of launch direction set by the face
const TRAJ_LOFT_DEG := 5.0 # dynamic loft change at trajectory +/-1 (ball position / shaft lean)
const TRAJ_AOA_DEG := 2.0 # attack angle change at trajectory +/-1
const STRIKE_V_LOFT_PER_MM := 0.12 # higher on the face launches higher (vertical gear effect)
const STRIKE_V_SPIN_PER_MM := 0.014 # ...and spins less; low strikes spin more
const STRIKE_H_FACE_PER_MM := 0.22 # toe strike twists face open
const STRIKE_H_AXIS_PER_MM := 0.35 # small horizontal gear effect (toe -> draw spin)
const STRIKE_SPEED_LOSS := 0.10 # fraction of ball speed lost at a 15 mm miss
const PARTIAL_SPIN_EXP := 0.6
const RPM_TO_RADS := TAU / 60.0


## Swing inputs. All optional; defaults are a stock, centred, square swing.
class Swing:
	var speed_frac: float = 1.0 # club head speed relative to stock
	var path_deg: float = 0.0 # + = right (in-to-out)
	var face_to_path_deg: float = 0.0 # + = face open to path (fade/slice spin)
	var trajectory: float = 0.0 # -1 low (ball back) .. +1 high (ball forward)
	var strike_toe_mm: float = 0.0 # + toe, - heel
	var strike_high_mm: float = 0.0 # + high on face, - thin/low
	var loft_offset_deg: float = 0.0 # shaft lean at impact: + adds loft (flip), - delofts (lag)
	var aoa_offset_deg: float = 0.0 # + shallower, - steeper
	var spin_scale: float = 1.0 # spin control: <1 a "runner" (less backspin), >1 a "spinner"


class Result:
	var velocity: Vector3 # m/s, target frame
	var spin: Vector3 # rad/s, axis * rate
	var ball_speed: float # m/s
	var club_speed: float # m/s
	var smash: float
	var launch_v_deg: float
	var launch_h_deg: float # + right
	var spin_rpm: float
	var spin_axis_deg: float # + = tilted right (fade/slice spin)
	var dynamic_loft_deg: float
	var attack_deg: float
	var spin_loft_deg: float
	var face_deg: float
	var path_deg: float


## Unit vector from yaw (+right) and pitch (+up), degrees.
static func dir_from(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(cos(p) * sin(y), sin(p), -cos(p) * cos(y))


static func yaw_of(v: Vector3) -> float:
	return rad_to_deg(atan2(v.x, -v.z))


static func pitch_of(v: Vector3) -> float:
	return rad_to_deg(atan2(v.y, Vector2(v.x, v.z).length()))


## Dynamic loft that makes a stock swing launch at the published angle.
static func stock_dynamic_loft(club: Dictionary) -> float:
	# launch direction = normalize(c*(1-k) + n*k). Solve for the loft of n by
	# bisection (exact, rather than the small-angle approximation).
	var target: float = club["launch"]
	var aoa: float = club["aoa"]
	var lo := aoa
	var hi := aoa + 60.0
	for i in 50:
		var mid := (lo + hi) * 0.5
		var c := dir_from(0.0, aoa)
		var n := dir_from(0.0, mid)
		var l := (c * (1.0 - LAUNCH_FACE_RATIO) + n * LAUNCH_FACE_RATIO).normalized()
		if pitch_of(l) < target:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func compute(club: Dictionary, swing: Swing) -> Result:
	var r := Result.new()
	var stock_club_speed: float = club["club_mph"] * Clubs.MPH
	var stock_ball_speed: float = club["ball_mph"] * Clubs.MPH
	var stock_dl := stock_dynamic_loft(club)
	var stock_aoa: float = club["aoa"]
	var stock_spin_loft := deg_to_rad(stock_dl - stock_aoa)

	var aoa := stock_aoa + swing.trajectory * TRAJ_AOA_DEG + swing.aoa_offset_deg
	var dl := stock_dl + swing.trajectory * TRAJ_LOFT_DEG + swing.strike_high_mm * STRIKE_V_LOFT_PER_MM + swing.loft_offset_deg
	var face := swing.path_deg + swing.face_to_path_deg + swing.strike_toe_mm * STRIKE_H_FACE_PER_MM

	var c := dir_from(swing.path_deg, aoa)
	var n := dir_from(face, dl)
	var spin_loft := c.angle_to(n)

	var miss_mm := Vector2(swing.strike_toe_mm, swing.strike_high_mm).length()
	var strike_speed := 1.0 - STRIKE_SPEED_LOSS * pow(miss_mm / 15.0, 2.0)
	strike_speed = maxf(strike_speed, 0.6)

	r.club_speed = stock_club_speed * swing.speed_frac
	var smash_stock := stock_ball_speed / stock_club_speed
	r.smash = smash_stock * cos(spin_loft) / cos(stock_spin_loft) * strike_speed
	r.ball_speed = r.club_speed * r.smash

	var launch_dir := (c * (1.0 - LAUNCH_FACE_RATIO) + n * LAUNCH_FACE_RATIO).normalized()
	r.velocity = launch_dir * r.ball_speed

	# Spin is not linear in club speed for partial swings: players keep the
	# face loft on and strike down, so a 60% swing keeps ~75% of the spin.
	var speed_spin := pow(swing.speed_frac, PARTIAL_SPIN_EXP) if swing.speed_frac < 1.0 else swing.speed_frac
	var spin_rpm: float = club["spin"] * speed_spin * sin(spin_loft) / sin(stock_spin_loft)
	spin_rpm *= maxf(0.4, 1.0 - swing.strike_high_mm * STRIKE_V_SPIN_PER_MM)
	spin_rpm *= swing.spin_scale
	r.spin_rpm = spin_rpm

	var axis := c.cross(n)
	if axis.length() < 1e-6:
		axis = launch_dir.cross(Vector3.UP)
	axis = axis.normalized()
	# Horizontal gear effect: rotate the axis about the launch direction.
	# (Rotating +angle about the forward axis tilts it toward fade, so negate.)
	axis = axis.rotated(launch_dir, deg_to_rad(-swing.strike_toe_mm * STRIKE_H_AXIS_PER_MM))
	r.spin = axis * spin_rpm * RPM_TO_RADS

	r.launch_v_deg = pitch_of(launch_dir)
	r.launch_h_deg = yaw_of(launch_dir)
	r.spin_axis_deg = spin_axis_tilt_deg(axis, launch_dir)
	r.dynamic_loft_deg = dl
	r.attack_deg = aoa
	r.spin_loft_deg = rad_to_deg(spin_loft)
	r.face_deg = face
	r.path_deg = swing.path_deg
	return r


## Spin axis tilt as a launch monitor reports it: 0 = pure backspin,
## positive = axis tilted right (ball curves right).
static func spin_axis_tilt_deg(axis: Vector3, launch_dir: Vector3) -> float:
	var horiz := Vector3(launch_dir.x, 0.0, launch_dir.z).normalized()
	var right := horiz.cross(Vector3.UP).normalized() # pure backspin axis
	var tilt := atan2(-axis.dot(Vector3.UP), axis.dot(right))
	return rad_to_deg(tilt)
