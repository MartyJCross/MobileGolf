extends RefCounted
## Assertion helpers shared by test files.

var failures: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func near(actual: float, expected: float, tol: float, what: String) -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: got %.3f, expected %.3f +/- %.3f" % [what, actual, expected, tol])


## Simulates a full shot on a terrain and returns the finished sim.
static func shoot(terrain: GolfTerrain, club_id: String, swing: LaunchModel.Swing = null, from := Vector3(0, BallSim.RADIUS, 0)) -> BallSim:
	if swing == null:
		swing = LaunchModel.Swing.new()
	var club := Clubs.find(club_id)
	var l := LaunchModel.compute(club, swing)
	var sim := BallSim.new(terrain)
	sim.launch(from, l.velocity, l.spin)
	sim.simulate()
	return sim


static func flat(surface: int = Surface.FAIRWAY) -> GolfTerrain:
	var t := GolfTerrain.new()
	t.surface_type = surface
	return t
