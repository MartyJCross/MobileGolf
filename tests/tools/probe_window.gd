extends SceneTree
func _init() -> void:
	SwingModel.brake_torque = 0.0
	SwingModel.release_torque = 25.0
	var top := SwingModel.FULL_TOP
	var cock := SwingModel.MAX_COCK
	for ws in [45.0, 60.0, 80.0]:
		SwingModel.wrist_strength = ws
		var best := SwingModel.optimal_release_time(top, cock)
		var b := SwingModel.simulate(top, cock, best)
		var nat := SwingModel.simulate(top, cock, -1.0)
		print("wrist %.0f: best %.3f impact %.3f v %.1f lag %.1f | natural release %.3f (+%d ms) lag %.1f v %.1f (%.0f%%)" % [ws, best, b.sim_t, b.v_raw, rad_to_deg(b.club - b.arm), nat.release_t, roundi((nat.release_t - best) * 1000), rad_to_deg(nat.club - nat.arm), nat.v_raw, nat.v_raw / b.v_raw * 100])
		var line := ""
		for off in [-50, -40, -30, -20, -10, -5, 0, 5, 10, 20, 30, 40, 50]:
			var m := SwingModel.simulate(top, cock, best + off / 1000.0)
			line += "  %+d:%.0f%%/%+.0f" % [off, m.v_raw / b.v_raw * 100, rad_to_deg(m.club - m.arm)]
		print(line)
	quit()
