extends SceneTree
## Compares control schemes with simulated players.
##
## Each scheme is modelled by the human error it introduces (one standard
## deviation, from typical motor-timing figures):
##   lift_ms   : letting go of a held touch at a target moment (~40 ms)
##   tap_ms    : tapping when a moving meter hits a mark (~30 ms)
##   cue_ms    : tapping as a visible marker reaches a target zone (~22 ms)
##   blind_ms  : tapping at a moment with nothing on screen to aim at (~45 ms)
##   drag_frac : positioning the thumb to set backswing length (~3% of a full swing)
##   liftcue   : lifting the thumb as a visible marker reaches a zone (~30 ms;
##               releases are less precise than taps)
## Every simulated swing runs through the real swing model and ball flight;
## we measure where the ball stops relative to where a perfect swing stops.
##   godot --headless -s tests/tools/experiment_controls.gd

const N := 160
const SCALE := 0.55 # on-screen slow motion of the downswing

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7
	SwingModel.build_table()
	var schemes := [
		{"name": "Hold & Tap (v0.2, no cue)", "back": "lift", "release": "blind"},
		{"name": "Hold & Tap + release mark", "back": "lift", "release": "cue"},
		{"name": "Three Taps + release mark", "back": "tap", "release": "cue"},
		{"name": "Pull & Tap (no cue)", "back": "drag", "release": "blind"},
		{"name": "Pull & Tap + release mark", "back": "drag", "release": "cue"},
		{"name": "One Touch + release mark", "back": "drag", "release": "liftcue"},
	]
	var sd := {"lift": 0.040, "tap": 0.030, "cue": 0.022, "blind": 0.045, "drag": 0.03, "liftcue": 0.030}
	print("%-28s | %-26s | %-26s" % ["scheme", "full 7-iron (avg / <5m / <10m)", "70% 9-iron (avg / <5m / <10m)"])
	for sc in schemes:
		var cells := []
		for target in [[1.0, "7i"], [0.7, "9i"]]:
			var perfect := _rest(target[0], 0.0, target[1])
			var errs: Array[float] = []
			for i in N:
				var frac := _backswing(target[0], sc["back"], sd)
				var tap_err: float = rng.randfn(0.0, sd[sc["release"]])
				var p := _rest(frac, tap_err, target[1])
				errs.append(Vector2(p.x - perfect.x, p.z - perfect.z).length())
			cells.append(_summ(errs))
		print("%-28s | %-30s | %-30s" % [sc["name"], cells[0], cells[1]])
	quit()


func _summ(errs: Array[float]) -> String:
	var s := 0.0
	var in5 := 0
	var in10 := 0
	for e in errs:
		s += e
		if e < 5.0:
			in5 += 1
		if e < 10.0:
			in10 += 1
	return "%5.1f m  %3d%%  %3d%%" % [s / errs.size(), in5 * 100 / errs.size(), in10 * 100 / errs.size()]


## Backswing fraction actually achieved when aiming for `target`.
func _backswing(target: float, how: String, sd: Dictionary) -> float:
	if how == "drag":
		return maxf(0.2, target + rng.randfn(0.0, sd["drag"]))
	# Hold/tap on a meter: the error is in time along the backswing ramp.
	var t_target := acos(1.0 - 2.0 * minf(target, 0.999)) / PI * SwingModel.FULL_TIME
	var t := t_target + rng.randfn(0.0, sd[how])
	return SwingModel.backswing_arm(maxf(t, 0.2)) / SwingModel.FULL_TOP


## Where the ball stops (flat fairway, no wind) for a swing.
func _rest(frac: float, tap_err_real_s: float, club_id: String) -> Vector3:
	var top := frac * SwingModel.FULL_TOP
	var m := SwingModel.new()
	m.rng.seed = rng.randi()
	m.arm = top
	m.club = top + SwingModel.cock_for(top)
	m._start_down()
	var ideal := SwingModel.ideal_for(top)
	var tap_at := ideal.x + tap_err_real_s * SCALE
	while m.state == SwingModel.State.DOWNSWING:
		if not m.tapped and m.sim_t >= tap_at:
			m.release_club()
		m._step()
	var r: SwingModel.Result = m.result
	var l := LaunchModel.compute(Clubs.get_club(Clubs.index_of(club_id)), r.swing)
	var t := GolfTerrain.new()
	t.surface_type = Surface.FAIRWAY
	var sim := BallSim.new(t)
	sim.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	sim.simulate()
	return sim.pos
