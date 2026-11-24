extends SceneTree
## Fits the aerodynamic coefficients in BallSim to the TrackMan tour table.
## Feeds each club's *published* launch conditions (ball speed, launch angle,
## spin) straight into the flight model and compares carry / apex / landing
## angle. Run:  godot --headless -s tests/calibrate.gd [-- report]

const KEYS := ["cd0", "cd_spin", "cl0", "cl_k", "cl_pow", "cd_low_re", "cd_speed"]
const FIXED := {"spin_decay": 1.2} # spin decay is held at a realistic rate, not fitted


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var params := {}
	var probe := BallSim.new()
	for k in KEYS:
		params[k] = probe.get(k)
	params.merge(FIXED, true)
	if "linear" in args:
		params = {"cd0": 0.171, "cd_spin": 0.62, "cl0": 0.083, "cl_k": 0.885, "cl_pow": 1.0, "cd_low_re": 0.0, "cd_speed": 0.0, "spin_decay": 1.0}
	if "report" in args:
		_report(params)
		quit()
		return
	if "fitbest" in args:
		params = {"cd0": 0.350, "cd_spin": 0.0, "cl0": 0.0, "cl_k": 0.486, "cl_pow": 0.451, "cd_low_re": 0.718, "cd_speed": -0.397}
	if "fitss" in args:
		params = {"cd0": 0.24, "cd_spin": 0.18, "cl0": 0.0, "cl_k": 0.54, "cl_pow": 0.4, "cd_low_re": 0.1, "cd_speed": -0.1, "spin_decay": 1.0}
	if "fitlinear" in args:
		params = {"cd0": 0.171, "cd_spin": 0.62, "cl0": 0.083, "cl_k": 0.885, "cl_pow": 1.0, "cd_low_re": 0.0, "cd_speed": 0.0, "spin_decay": 1.0}
	var best := _nelder_mead(params, 600)
	_report(best)
	quit()


func _vec_to_params(x: Array) -> Dictionary:
	var d := FIXED.duplicate()
	for i in KEYS.size():
		d[KEYS[i]] = x[i]
	return d


func _cost(x: Array) -> float:
	for i in x.size():
		if x[i] < 0.0 and KEYS[i] != "cd_speed":
			return 1e9
	return _error(_vec_to_params(x))


func _nelder_mead(start: Dictionary, iters: int) -> Dictionary:
	var n := KEYS.size()
	var simplex: Array = []
	var x0: Array = []
	for k in KEYS:
		x0.append(float(start[k]))
	simplex.append(x0)
	for i in n:
		var x: Array = x0.duplicate()
		x[i] = x[i] * 1.25 if absf(x[i]) > 0.01 else 0.05
		simplex.append(x)
	var costs: Array = []
	for x in simplex:
		costs.append(_cost(x))
	for it in iters:
		var order := range(n + 1)
		order.sort_custom(func(a, b): return costs[a] < costs[b])
		var s2: Array = []
		var c2: Array = []
		for i in order:
			s2.append(simplex[i])
			c2.append(costs[i])
		simplex = s2
		costs = c2
		if it % 25 == 0:
			print("iter ", it, " err ", snappedf(costs[0], 0.00001), " ", _vec_to_params(simplex[0]))
		if costs[n] - costs[0] < 1e-7:
			break
		var centroid: Array = []
		for j in n:
			var sum := 0.0
			for i in n:
				sum += simplex[i][j]
			centroid.append(sum / n)
		var refl := _lin(centroid, simplex[n], -1.0)
		var cr := _cost(refl)
		if cr < costs[0]:
			var exp_p := _lin(centroid, simplex[n], -2.0)
			var ce := _cost(exp_p)
			if ce < cr:
				simplex[n] = exp_p
				costs[n] = ce
			else:
				simplex[n] = refl
				costs[n] = cr
		elif cr < costs[n - 1]:
			simplex[n] = refl
			costs[n] = cr
		else:
			var con := _lin(centroid, simplex[n], 0.5)
			var cc := _cost(con)
			if cc < costs[n]:
				simplex[n] = con
				costs[n] = cc
			else:
				for i in range(1, n + 1):
					simplex[i] = _lin(simplex[0], simplex[i], 0.5)
					costs[i] = _cost(simplex[i])
	print("final err ", costs[0])
	return _vec_to_params(simplex[0])


## c + t * (p - c)
func _lin(c: Array, p: Array, t: float) -> Array:
	var r: Array = []
	for j in c.size():
		r.append(c[j] + t * (p[j] - c[j]))
	return r


static func fly(params: Dictionary, club: Dictionary, dt := BallSim.DT) -> Dictionary:
	var sim := BallSim.new()
	for k in params:
		sim.set(k, params[k])
	var v: float = club["ball_mph"] * Clubs.MPH
	var dir := LaunchModel.dir_from(0.0, club["launch"])
	var spin: Vector3 = Vector3.RIGHT * club["spin"] * LaunchModel.RPM_TO_RADS
	sim.launch(Vector3(0, BallSim.RADIUS, 0), dir * v, spin)
	while not sim.landed and sim.time < 20.0:
		sim.step(dt)
	return {"carry": sim.carry_distance(), "apex": sim.apex, "land": sim.land_angle_deg, "time": sim.carry_time}


static func _error(params: Dictionary) -> float:
	var err := 0.0
	for club in Clubs.SET:
		var r := fly(params, club, 1.0 / 120.0)
		var carry_t: float = club["carry_yd"] * Clubs.YARD
		var apex_t: float = club["apex_yd"] * Clubs.YARD
		err += pow((r["carry"] - carry_t) / carry_t, 2.0) * 10.0
		err += pow((r["apex"] - apex_t) / apex_t, 2.0) * 0.3
		err += pow((r["land"] - club["land"]) / 10.0, 2.0)
	return err


static func _report(params: Dictionary) -> void:
	print("params ", params)
	print("club  carry(m) tgt   apex(m) tgt  land  tgt  hang")
	for club in Clubs.SET:
		var r := fly(params, club)
		print("%-4s %7.1f %5.1f  %6.1f %5.1f  %4.1f %4.1f %4.1fs" % [club["id"], r["carry"], club["carry_yd"] * Clubs.YARD, r["apex"], club["apex_yd"] * Clubs.YARD, r["land"], club["land"], r["time"]])
