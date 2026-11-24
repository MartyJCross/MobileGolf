extends SceneTree
## Grid over torque profile parameters: want optimal release -> lag ~ -5 deg,
## natural (no tap) release -> late (lag -15..-30), downswing ~0.25-0.32 s.
func _init() -> void:
	var top := SwingModel.FULL_TOP
	var cock := SwingModel.MAX_COCK
	for bt in [0.0, 60.0, 100.0]:
		for bs in [-60.0]:
			for ws in [10.0, 25.0, 45.0]:
				SwingModel.release_torque = ws
				SwingModel.wrist_strength = 30.0
				SwingModel.brake_torque = bt
				SwingModel.brake_start = deg_to_rad(bs)
				SwingModel.brake_full = deg_to_rad(bs + 50.0)
				var best := SwingModel.optimal_release_time(top, cock)
				var b := SwingModel.simulate(top, cock, best)
				var nat := SwingModel.simulate(top, cock, -1.0)
				var e20 := SwingModel.simulate(top, cock, best - 0.03)
				var l20 := SwingModel.simulate(top, cock, best + 0.03)
				print("brake %3.0f from %4.0f reltq %2.0f | best t %.3f arm@rel %5.0f lag %6.1f v %4.1f imp %.3f | nat lag %6.1f v %4.1f | -30ms lag %6.1f v %4.1f | +30ms lag %6.1f v %4.1f" % [bt, bs, ws, best, rad_to_deg(_arm_at(top, cock, best)), rad_to_deg(b.club - b.arm), b.v_raw, b.sim_t, rad_to_deg(nat.club - nat.arm), nat.v_raw, rad_to_deg(e20.club - e20.arm), e20.v_raw, rad_to_deg(l20.club - l20.arm), l20.v_raw])
	quit()

func _arm_at(top: float, cock: float, t: float) -> float:
	var m := SwingModel.simulate(top, cock, -1.0)
	# re-run to time t without release
	var m2 := SwingModel.new()
	m2.analysis = true
	m2.arm = top
	m2.club = top + cock
	m2._start_down()
	while m2.sim_t < t and m2.state == SwingModel.State.DOWNSWING:
		m2._step()
	return m2.arm
