extends SceneTree
func _init() -> void:
	SwingModel.build_table()
	for deg in [-60, -90, -120, -150, -165]:
		var top := deg_to_rad(deg)
		print("top %4d  release arm %6.1f deg  best t %.3f" % [deg, rad_to_deg(SwingModel.ideal_release_arm(top)), SwingModel.ideal_for(top).x])
	quit()
