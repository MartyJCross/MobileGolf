extends SceneTree
## Explores the swing model: timing window and backswing length.
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var ref := SwingModel.reference_speed()
	print("ref speed %.1f m/s (%.0f mph), computed in %d ms" % [ref, ref / Clubs.MPH, Time.get_ticks_msec() - t0])
	var top := SwingModel.FULL_TOP
	var cock := SwingModel.MAX_COCK
	var nat := SwingModel.simulate(top, cock, -1.0)
	print("natural release at t=%.3f  impact t=%.3f  speed %.1f lag %.1f" % [nat.release_t, nat.sim_t, nat.v_raw, rad_to_deg(nat.club - nat.arm)])
	var best := SwingModel.optimal_release_time(top, cock)
	var b := SwingModel.simulate(top, cock, best)
	print("best release t=%.3f (arm %.0f deg)  impact t=%.3f speed %.1f lag %.1f" % [best, 0.0, b.sim_t, b.v_raw, rad_to_deg(b.club - b.arm)])
	print("offset_ms(physical)  speed%%  lag_deg  shortfall_mm")
	for off in [-80, -60, -40, -30, -20, -10, 0, 10, 20, 30, 40]:
		var m := SwingModel.simulate(top, cock, best + off / 1000.0)
		var sf := (SwingModel.L_ARM + SwingModel.L_CLUB - m.head().length()) * 1000.0
		print("%5d   %5.1f   %6.1f   %5.1f%s" % [off, m.v_raw / ref * 100.0, rad_to_deg(m.club - m.arm), sf, "  (auto)" if m._auto_released else ""])
	print("backswing  top_deg  best_speed%%")
	for frac in [0.3, 0.45, 0.6, 0.75, 0.9, 1.0]:
		var hold := acos(1.0 - 2.0 * frac) / PI * SwingModel.FULL_TIME
		var a := SwingModel.backswing_arm(hold)
		var c := SwingModel.cock_for(a)
		var bt := SwingModel.optimal_release_time(a, c)
		var mm := SwingModel.simulate(a, c, bt)
		print("%4.2f  %6.0f  %5.1f   hold %.2fs" % [frac, rad_to_deg(a), mm.v_raw / ref * 100.0, hold])
	for over in [1.2, 1.35]:
		var a2 := SwingModel.backswing_arm(over)
		var c2 := SwingModel.cock_for(a2)
		var m2 := SwingModel.simulate(a2, c2, SwingModel.optimal_release_time(a2, c2))
		print("over hold %.2fs top %.0f speed %.1f%%" % [over, rad_to_deg(a2), m2.v_raw / ref * 100.0])
	quit()
