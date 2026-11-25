extends SceneTree
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var counts := {}
	for i in 30:
		var t1 := Time.get_ticks_msec()
		var h := HoleGenerator.generate(1000 + i)
		var r := HoleGenerator.find_route(h)
		var names := []
		for f in h.features:
			names.append(HoleGenerator.FEATURE_NAMES[f])
		print("seed %d  %5.1f m  features %s  route %s  (%d ms)" % [1000 + i, h.distance, names, ("%s %s curve %+.1f" % [Clubs.get_club(r.club_idx)["id"], ShotPlanner.HEIGHTS[r.height_idx]["name"], r.curve]) if r else "NONE", Time.get_ticks_msec() - t1])
	print("total %d ms" % (Time.get_ticks_msec() - t0))
	quit()
