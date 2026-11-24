extends SceneTree
func _init() -> void:
	SwingModel.brake_torque = 0.0
	SwingModel.release_torque = 25.0
	var top := SwingModel.FULL_TOP
	var cock := SwingModel.MAX_COCK
	var best := SwingModel.optimal_release_time(top, cock)
	var bv := SwingModel.simulate(top, cock, best).v_raw
	for ws in [31.0, 33.0, 35.0, 37.0, 39.0, 41.0, 43.0]:
		SwingModel.wrist_strength = ws
		var nat := SwingModel.simulate(top, cock, -1.0)
		print("wrist %.0f natural release %+d ms lag %.0f speed %.0f%%" % [ws, roundi((nat.release_t - best) * 1000) if nat.release_t > 0 else 9999, rad_to_deg(nat.club - nat.arm), nat.v_raw / bv * 100])
	quit()
