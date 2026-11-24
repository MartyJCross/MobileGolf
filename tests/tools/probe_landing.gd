extends SceneTree
## Prints how each club's stock shot reacts on landing (roll-out / spin-back).

func _init() -> void:
	print("club surface  soft  carry  total  rollout  landspin  bounces")
	for surf in [Surface.GREEN, Surface.FAIRWAY, Surface.ROUGH, Surface.BUNKER]:
		for soft in ([0.6, 1.0, 1.3] if surf == Surface.GREEN else [1.0]):
			for id in ["4i", "7i", "PW"]:
				var t := GolfTerrain.new()
				t.surface_type = surf
				t.green_softness = soft
				var sim := preload("res://tests/test_base.gd").shoot(t, id)
				print("%-4s %-8s %4.1f  %6.1f %6.1f  %+6.1f  %6.0f  %d" % [id, Surface.name_of(surf), soft, sim.carry_distance(), -sim.pos.z, -sim.pos.z - sim.carry_distance(), sim.land_spin_rpm, sim.bounces])
	# Partial PW (60%)
	for frac in [0.6, 0.8]:
		var sw := LaunchModel.Swing.new()
		sw.speed_frac = frac
		var t2 := GolfTerrain.new()
		t2.surface_type = Surface.GREEN
		var s2 := preload("res://tests/test_base.gd").shoot(t2, "PW", sw)
		print("PW %.0f%% green carry %.1f total %.1f landspin %.0f" % [frac * 100, s2.carry_distance(), -s2.pos.z, s2.land_spin_rpm])
	quit()
