class_name ShotPlanner
extends RefCounted
## Turns "land it there, this high, with this spin and curve" into a swing.
##
## You choose a landing spot; the planner solves the swing speed and the aim
## (start direction) so that the ball's first bounce is on that spot, curving
## and (by default) blowing in the wind. It then flies the planned shot
## through the obstacles to produce the preview arc and tell you if a tree,
## hedge or wall is in the way. With `with_wind = false` it plans for still
## air and reading the wind is your job.

const MAX_SPEED := 1.08 # a little over a stock full swing
const MIN_SPEED := 0.12
const PLAN_DT := 1.0 / 90.0 # coarser than the real sim: fast, and lands within ~0.2 m
const MAX_CURVE_DEG := 12.0 # face to path at full curve

## Shot heights: trajectory setting for LaunchModel (dynamic loft/attack).
const HEIGHTS := [
	{"name": "Punch", "traj": -1.6},
	{"name": "Normal", "traj": 0.0},
	{"name": "High", "traj": 1.0},
	{"name": "Flop", "traj": 2.0},
]


class Shot:
	var club_idx := 1
	var height_idx := 1
	var spin := 0.0 # -1 runner (less backspin) .. +1 max backspin
	var curve := 0.0 # -1 draw (curves left) .. +1 fade (curves right)

	func duplicate_shot() -> Shot:
		var s := Shot.new()
		s.club_idx = club_idx
		s.height_idx = height_idx
		s.spin = spin
		s.curve = curve
		return s


class Plan:
	var speed_frac := 0.0
	var yaw_deg := 0.0
	var landing := Vector3.ZERO # first bounce of the planned shot (no obstacles)
	var path := PackedVector3Array() # flight with obstacles, for the preview
	var clear_path := PackedVector3Array() # the same flight ignoring obstacles
	var blocked := false
	var block_pos := Vector3.ZERO
	var too_far := false
	var too_short := false
	var apex := 0.0
	var iterations := 0


static func spin_scale(spin: float) -> float:
	return 0.9 + (0.35 * spin if spin > 0.0 else 0.45 * spin)


static func make_swing(shot: Shot, speed_frac: float) -> LaunchModel.Swing:
	var sw := LaunchModel.Swing.new()
	sw.speed_frac = speed_frac
	sw.trajectory = HEIGHTS[shot.height_idx]["traj"]
	sw.spin_scale = spin_scale(shot.spin)
	sw.face_to_path_deg = shot.curve * MAX_CURVE_DEG
	return sw


## Velocity and spin for the shot at this speed and aim (yaw, degrees).
static func launch_vectors(shot: Shot, speed_frac: float, yaw_deg: float) -> Array:
	var l := LaunchModel.compute(Clubs.get_club(shot.club_idx), make_swing(shot, speed_frac))
	var r := -deg_to_rad(yaw_deg)
	return [l.velocity.rotated(Vector3.UP, r), l.spin.rotated(Vector3.UP, r), l]


static func bearing(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, -(to.z - from.z)))


static func _fly(terrain: GolfTerrain, start: Vector3, shot: Shot, s: float, yaw: float, obstacles: bool, with_wind: bool) -> BallSim:
	var lv := launch_vectors(shot, s, yaw)
	var sim := BallSim.new(terrain)
	sim.ignore_wind = not with_wind
	sim.use_obstacles = obstacles
	sim.launch(start, lv[0], lv[1])
	while sim.phase == BallSim.Phase.FLIGHT and not sim.landed and sim.time < 15.0:
		if obstacles and sim.hit_tree:
			break
		sim.step(PLAN_DT)
	return sim


## Solve speed and aim to land on `target`. Pass a previous plan to warm-start.
static func solve(terrain: GolfTerrain, start: Vector3, target: Vector3, shot: Shot, warm: Plan = null, with_wind := true) -> Plan:
	var p := Plan.new()
	var want := Vector2(target.x - start.x, target.z - start.z).length()
	var s := 0.0
	var yaw := bearing(start, target)
	if warm != null and warm.speed_frac > 0.0:
		s = warm.speed_frac
		yaw = warm.yaw_deg
	else:
		var stock := Clubs.stock_carry_m(Clubs.get_club(shot.club_idx))
		s = clampf(pow(want / stock, 0.62), MIN_SPEED, MAX_SPEED)
	var land := start
	var last: BallSim = null
	for i in 12:
		p.iterations = i + 1
		var sim := _fly(terrain, start, shot, s, yaw, false, with_wind)
		last = sim
		land = sim.carry_pos if sim.landed else sim.pos
		var got := Vector2(land.x - start.x, land.z - start.z).length()
		var miss := Vector2(land.x - target.x, land.z - target.z).length()
		if miss < 0.12:
			break
		if got < 0.5:
			s = minf(s * 1.5, MAX_SPEED)
			continue
		var ns := clampf(s * pow(want / got, 0.65), MIN_SPEED, MAX_SPEED)
		yaw += wrapf(bearing(start, target) - bearing(start, land), -180.0, 180.0)
		if ns == s and (s == MAX_SPEED or s == MIN_SPEED):
			p.too_far = s == MAX_SPEED and got < want
			p.too_short = s == MIN_SPEED and got > want
			break
		s = ns
	p.speed_frac = s
	p.yaw_deg = yaw
	p.landing = land
	if last != null:
		p.clear_path = last.frames
		p.clear_path.append(land)
	var prev := _fly(terrain, start, shot, s, yaw, true, with_wind)
	p.path = prev.frames
	p.path.append(prev.pos)
	p.blocked = prev.hit_tree
	p.block_pos = prev.first_hit_pos
	p.apex = prev.apex
	return p
