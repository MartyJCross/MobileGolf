extends Node3D
## Game controller: holes, aiming, swinging, shot playback, cameras, results.

enum State { LOADING, AIMING, FLYING, RESULT }

const CAM_FOV := 55.0
const BALL_VISUAL_SCALE := 0.004 # ball drawn at least this fraction of camera distance

var state: int = State.LOADING
var stats := Stats.new()
var hole: HoleData
var hole_no := 1
var club_idx := 4
var trajectory := 0.0
var aim_yaw := 0.0 # degrees, + right of straight down -Z
var map_view := false
var world_env: Environment

var course: CourseView
var cam: Camera3D
var ball: MeshInstance3D
var tracer: Tracer
var aim_line: Tracer
var carry_ring: MeshInstance3D
var hud: Hud
var swing := SwingModel.new()
var shape := 0.0
var _swing_clock := 0.0
var _table_task := -1
var _manual_swing := false # automation steps the downswing itself

var sim: BallSim
var last_launch: LaunchModel.Result
var last_swing: SwingModel.Result
var play_t := 0.0
var play_speed := 1.0
var ball_start := Vector3.ZERO
var _carry_cache := {}
var _next_task := -1
var _next_hole: HoleData
var _next_no := -1

# Automation for headless screenshots / smoke tests (cmdline user args).
var _auto := {}
var _frame := 0


func _ready() -> void:
	Input.use_accumulated_input = false
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		_auto[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_build_world()
	stats.load_stats()
	if _auto.has("seed"):
		stats.base_seed = int(_auto["seed"])
		stats.hole_number = 1
	# Perfect-release table for the swing model (used to score timing).
	_table_task = WorkerThreadPool.add_task(SwingModel.build_table, false, "swing table")
	swing.time_scale = stats.tempo
	hud.tempo_slider.set_value_no_signal(stats.tempo)
	hud.tempo_label.text = Hud.tempo_text(stats.tempo)
	hud.swing_view.model = swing
	_swing_clock = Time.get_ticks_usec() / 1.0e6
	hud.set_stats(stats)
	_load_hole(stats.hole_number)
	if not _auto.is_empty():
		_run_automation()


func _exit_tree() -> void:
	# Never leave the next-hole worker running while the engine shuts down.
	if _next_task != -1:
		WorkerThreadPool.wait_for_task_completion(_next_task)
		_next_task = -1
	if _table_task != -1:
		WorkerThreadPool.wait_for_task_completion(_table_task)
		_table_task = -1


# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.83, 0.92)
	sky_mat.ground_horizon_color = Color(0.5, 0.6, 0.5)
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.2)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.78, 0.88)
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.0
	world_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	course = CourseView.new()
	add_child(course)

	ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = BallSim.RADIUS
	sm.height = BallSim.RADIUS * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.98, 0.98, 0.98)
	bm.roughness = 0.4
	bm.emission_enabled = true
	bm.emission = Color(0.25, 0.25, 0.25)
	ball.material_override = bm
	add_child(ball)

	tracer = Tracer.new()
	add_child(tracer)
	aim_line = Tracer.new()
	aim_line.color = Color(1, 1, 1)
	aim_line.pixel_width = 0.0025
	add_child(aim_line)

	carry_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	carry_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.95, 1.0, 0.85)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	carry_ring.material_override = rm
	carry_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(carry_ring)

	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.far = 1500.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.swing_pressed.connect(_on_swing_pressed)
	hud.swing_released.connect(_on_swing_released)
	hud.shape_changed.connect(func(v): shape = v)
	hud.aim_drag.connect(_on_aim_drag)
	hud.view_tapped.connect(_on_view_tapped)
	hud.club_step.connect(_on_club_step)
	hud.trajectory_changed.connect(_on_trajectory)
	hud.next_pressed.connect(_on_next)
	hud.retry_pressed.connect(_on_retry)
	hud.map_toggled.connect(func(): map_view = not map_view; _snap_camera())
	hud.tempo_changed.connect(func(v):
		stats.tempo = v
		swing.time_scale = v
		stats.save_stats())
	hud.reset_stats_pressed.connect(func():
		stats.reset()
		hud.set_stats(stats))


# ------------------------------------------------------------------ holes

func _load_hole(n: int) -> void:
	state = State.LOADING
	hud.hide_result()
	hud.set_aiming_visible(false)
	hud.show_toast("Hole %d" % n)
	await get_tree().process_frame
	await get_tree().process_frame
	if _next_task != -1:
		WorkerThreadPool.wait_for_task_completion(_next_task)
		_next_task = -1
	if _next_hole != null and _next_no == n:
		hole = _next_hole
	else:
		hole = HoleGenerator.generate(stats.hole_seed(n))
	_next_hole = null
	hole_no = n
	course.build(hole)
	_reset_ball()
	club_idx = Clubs.suggest_for_distance(hole.distance - hole.elevation)
	hud.show_toast("")
	_enter_aiming()
	_prefetch(n + 1)


func _prefetch(n: int) -> void:
	if _auto.has("noprefetch"):
		return
	_next_no = n
	var s := stats.hole_seed(n)
	_next_task = WorkerThreadPool.add_task(func(): _next_hole = HoleGenerator.generate(s), false, "next hole")


func _reset_ball() -> void:
	ball_start = hole.tee + Vector3(0, BallSim.RADIUS + 0.012, 0) # teed up
	ball.position = ball_start
	aim_yaw = rad_to_deg(atan2(hole.pin.x, -hole.pin.z))
	tracer.clear()
	swing.reset()


func _enter_aiming() -> void:
	state = State.AIMING
	aim_line.color = Color(1, 1, 1)
	map_view = false
	hud.hide_result()
	hud.set_aiming_visible(true)
	hud.set_hole_info(hole_no, hole, aim_yaw)
	hud.set_stats(stats)
	hud.swing_view.visible = true
	swing.reset()
	_refresh_club()
	_snap_camera()


# ------------------------------------------------------------------ input

func _on_aim_drag(dx: float) -> void:
	if state != State.AIMING:
		return
	var gain := 0.02 if not map_view else 0.06
	aim_yaw = clampf(aim_yaw + dx * gain, -45.0, 45.0)
	hud.update_wind(hole, aim_yaw)
	_update_aim_visuals()


func _on_view_tapped() -> void:
	if state == State.FLYING:
		play_speed = 4.0


func _on_club_step(d: int) -> void:
	if state != State.AIMING:
		return
	club_idx = clampi(club_idx + d, 0, Clubs.count() - 1)
	_refresh_club()


func _on_trajectory(v: float) -> void:
	trajectory = v
	_refresh_club()


func _advance_swing() -> void:
	var now := Time.get_ticks_usec() / 1.0e6
	if not _manual_swing:
		swing.update(now - _swing_clock)
	_swing_clock = now
	if swing.result != null and state == State.AIMING:
		_hit(swing.result)


func _on_swing_pressed() -> void:
	if state != State.AIMING:
		return
	_advance_swing() # catch the model up to this exact moment first
	if swing.state == SwingModel.State.IDLE:
		swing.shape = shape
	swing.press()


func _on_swing_released() -> void:
	if state != State.AIMING:
		return
	_advance_swing()
	swing.lift()


func _on_next() -> void:
	if state != State.RESULT:
		return
	stats.hole_number = hole_no + 1
	stats.save_stats()
	_load_hole(hole_no + 1)


func _on_retry() -> void:
	if state != State.RESULT:
		return
	_reset_ball()
	_enter_aiming()


# ------------------------------------------------------------------ shot

func _hit(r: SwingModel.Result) -> void:
	last_swing = r
	var sw := r.swing
	sw.trajectory = trajectory
	var club := Clubs.get_club(club_idx)
	last_launch = LaunchModel.compute(club, sw)
	hud.swing_view.feedback = _swing_feedback(r)
	var yaw := -deg_to_rad(aim_yaw)
	sim = BallSim.new(hole)
	sim.rng.seed = randi()
	sim.launch(ball_start, last_launch.velocity.rotated(Vector3.UP, yaw), last_launch.spin.rotated(Vector3.UP, yaw))
	sim.simulate()
	play_t = 0.0
	play_speed = 1.0
	state = State.FLYING
	hud.set_aiming_visible(false)
	aim_line.clear()
	carry_ring.visible = false
	hud.pin_marker.visible = false
	Input.vibrate_handheld(25)


func _finish_shot() -> void:
	state = State.RESULT
	var title := ""
	var sub := ""
	var proximity := 0.0
	var on_green := false
	var ace := false
	var final_pos := sim.pos
	match sim.phase:
		BallSim.Phase.HOLED:
			title = "HOLE IN ONE!"
			sub = "Into the cup"
			ace = true
			on_green = true
		BallSim.Phase.WATER, BallSim.Phase.OUT:
			final_pos = sim.water_pos
			proximity = hole.dist_to_pin(sim.water_pos) + Stats.WATER_PENALTY
			title = "Water" if sim.phase == BallSim.Phase.WATER else "Out of bounds"
			sub = "Scored %.1f m (where it went %s + %d m)" % [proximity, "in" if sim.phase == BallSim.Phase.WATER else "out", Stats.WATER_PENALTY]
		_:
			proximity = hole.dist_to_pin(sim.pos)
			var surf := hole.get_surface(sim.pos.x, sim.pos.z)
			on_green = surf == Surface.GREEN
			title = "%.1f m" % proximity
			sub = "%s  ·  %s" % [Surface.name_of(surf), _miss_text(final_pos)]
	stats.record(proximity, on_green, ace)
	_draw_result_line(final_pos)
	hud.set_stats(stats)
	hud.show_result(title, sub, _shot_report())


func _rest_pos() -> Vector3:
	if sim.phase == BallSim.Phase.WATER or sim.phase == BallSim.Phase.OUT:
		return sim.water_pos
	return sim.pos


func _draw_result_line(from: Vector3) -> void:
	var pts := PackedVector3Array()
	var d := Vector2(hole.pin.x - from.x, hole.pin.z - from.z).length()
	var steps := maxi(2, int(d / 0.5))
	for k in steps + 1:
		var q := from.lerp(hole.pin, float(k) / steps)
		q.y = hole.get_contact_height(q.x, q.z) + 0.05
		pts.append(q)
	aim_line.color = Color(1.0, 0.9, 0.3)
	aim_line.set_points(pts)


func _miss_text(p: Vector3) -> String:
	var line := Vector2(hole.pin.x - hole.tee.x, hole.pin.z - hole.tee.z).normalized()
	var d := Vector2(p.x - hole.pin.x, p.z - hole.pin.z)
	var along := d.dot(line)
	var across := d.dot(Vector2(-line.y, line.x))
	var a := "%.1f m %s" % [absf(along), "long" if along > 0 else "short"]
	var b := "%.1f m %s" % [absf(across), "right" if across > 0 else "left"]
	return "%s, %s" % [a, b]


func _shot_report() -> String:
	var l := last_launch
	var g := last_swing
	var mph := 1.0 / Clubs.MPH
	var lines: Array[String] = []
	lines.append("Carry %.1f m   Total %.1f m   Peak %.1f m" % [sim.carry_distance(), sim.total_distance(), sim.apex])
	lines.append("Ball %.0f mph   Launch %.1f°   Spin %d rpm" % [l.ball_speed * mph, l.launch_v_deg, roundi(l.spin_rpm)])
	lines.append("Spin axis %s   Landed %.0f° at %d rpm" % [_lr(l.spin_axis_deg, "°"), sim.land_angle_deg, roundi(sim.land_spin_rpm)])
	lines.append("Backswing %d%%%s   %s" % [roundi(g.backswing * 100.0), " (over-swing!)" if g.overswing else "", _release_text(g)])
	lines.append("Club %.0f mph (%d%%)   Lag at impact %+.0f°   Smash %.2f" % [l.club_speed * mph, roundi(g.speed_frac * 100.0), g.lag_deg, l.smash])
	lines.append("Path %s   Face to path %s" % [_path_text(l.path_deg), _ftp_text(l.face_deg - l.path_deg)])
	return "\n".join(lines)


func _release_text(g: SwingModel.Result) -> String:
	if not g.released_by_player:
		return "No release: wrists gave way late"
	var ms := g.release_error_ms
	if absf(ms) < 4.0:
		return "Release: perfect"
	return "Release %d ms %s" % [roundi(absf(ms)), "late" if ms > 0 else "early"]


func _swing_feedback(g: SwingModel.Result) -> String:
	return "%s  ·  Club speed %d%%" % [_release_text(g), roundi(g.speed_frac * 100.0)]


func _lr(v: float, unit: String) -> String:
	if absf(v) < 0.05:
		return "0%s" % unit
	return "%.1f%s %s" % [absf(v), unit, "R" if v > 0 else "L"]


func _path_text(v: float) -> String:
	if absf(v) < 0.3:
		return "neutral"
	return "%.1f° %s" % [absf(v), "in-to-out" if v > 0 else "out-to-in"]


func _ftp_text(v: float) -> String:
	if absf(v) < 0.3:
		return "square"
	return "%.1f° %s" % [absf(v), "open" if v > 0 else "closed"]


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_frame += 1
	_advance_swing()
	if state == State.FLYING and swing.state == SwingModel.State.DONE:
		hud.swing_view.visible = false
	match state:
		State.AIMING:
			_update_camera(delta)
			_update_aim_visuals()
		State.FLYING:
			_play(delta)
			_update_camera(delta)
		State.RESULT:
			_update_camera(delta)
	_update_ball_scale()
	if state == State.FLYING or state == State.RESULT:
		tracer.redraw()
	if state == State.RESULT:
		aim_line.redraw()


func _play(delta: float) -> void:
	play_t += delta * play_speed
	var n := sim.frames.size()
	var f := play_t / BallSim.RECORD_DT
	var i := int(f)
	if i >= n - 1:
		ball.position = sim.frames[n - 1]
		_set_tracer(n - 1)
		_finish_shot()
		return
	ball.position = sim.frames[i].lerp(sim.frames[i + 1], f - i)
	_set_tracer(i)


func _set_tracer(i: int) -> void:
	var pts := PackedVector3Array()
	var step := 2
	for k in range(0, i + 1, step):
		pts.append(sim.frames[k])
	pts.append(ball.position)
	tracer.points = pts


func _update_ball_scale() -> void:
	var d := cam.global_position.distance_to(ball.global_position)
	var s := maxf(1.0, d * BALL_VISUAL_SCALE / BallSim.RADIUS)
	ball.scale = Vector3.ONE * s


func _aim_dir() -> Vector3:
	return LaunchModel.dir_from(aim_yaw, 0.0)


func _stock_carry() -> float:
	var key := "%d:%.2f" % [club_idx, trajectory]
	if _carry_cache.has(key):
		return _carry_cache[key]
	var sw := LaunchModel.Swing.new()
	sw.trajectory = trajectory
	var l := LaunchModel.compute(Clubs.get_club(club_idx), sw)
	var s := BallSim.new()
	s.launch(Vector3(0, BallSim.RADIUS, 0), l.velocity, l.spin)
	s.simulate_flight()
	_carry_cache[key] = s.carry_distance()
	return s.carry_distance()


func _refresh_club() -> void:
	hud.set_club(Clubs.get_club(club_idx), _stock_carry(), trajectory)
	_update_aim_visuals()


func _update_aim_visuals() -> void:
	if hole == null:
		return
	var carry := _stock_carry()
	var fwd := _aim_dir()
	var p := ball_start + fwd * carry
	p.y = hole.get_height(p.x, p.z) + 0.06
	carry_ring.position = p
	var ring_scale := maxf(1.5, cam.global_position.distance_to(p) * 0.02)
	carry_ring.scale = Vector3(ring_scale, 0.3, ring_scale)
	carry_ring.visible = true
	var pts := PackedVector3Array()
	var steps := int(carry / 2.0)
	for k in range(1, steps):
		var q := ball_start + fwd * (k * 2.0)
		q.y = hole.get_height(q.x, q.z) + 0.08
		pts.append(q)
	aim_line.set_points(pts)
	var pin_top := hole.pin + Vector3(0, 2.4, 0)
	var dist := Vector2(hole.pin.x - ball_start.x, hole.pin.z - ball_start.z).length()
	hud.place_marker(hud.pin_marker, cam, pin_top, "Pin %d m" % roundi(dist), 6.0)
	hud.place_marker(hud.carry_marker, cam, p, "%d m" % roundi(carry), -36.0)
	if hud.carry_marker.get_rect().intersects(hud.pin_marker.get_rect()):
		hud.carry_marker.position.y = hud.pin_marker.position.y + hud.pin_marker.size.y


# ------------------------------------------------------------------ cameras

func _snap_camera() -> void:
	var t := _camera_target()
	cam.global_transform = t
	_apply_projection()


func _apply_projection() -> void:
	if map_view and state == State.AIMING:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = hole.distance + 70.0
		world_env.fog_enabled = false
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = CAM_FOV
		world_env.fog_enabled = true


func _camera_target() -> Transform3D:
	var fwd := _aim_dir()
	var tee_to_pin := (hole.pin - hole.tee)
	tee_to_pin.y = 0.0
	var line := tee_to_pin.normalized()
	match state:
		State.AIMING, State.LOADING:
			if map_view:
				var center := (hole.tee + hole.green_center3()) * 0.5
				center.z -= 8.0 * line.z
				var pos := center + Vector3(0, 400, 0)
				return Transform3D(Basis.looking_at(Vector3.DOWN, line), pos)
			# Behind and above the ball; the higher the longer the hole, so the
			# green reads clearly. The ball sits low in the frame.
			var up_m := lerpf(2.2, 4.5, inverse_lerp(70.0, 200.0, hole.distance))
			var eye := ball_start - fwd * (up_m * 1.6) + Vector3(0, up_m, 0)
			var look_d := hole.distance * 0.55
			var look := ball_start + fwd * look_d
			look.y = lerpf(ball_start.y, hole.pin.y, 0.55) - 2.0
			return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
		State.FLYING:
			var t := play_t
			var land_t := sim.carry_time
			var b := ball.position
			if t < land_t - 1.6:
				# Chase: behind and above the ball, looking along the flight.
				var flat_v := sim.frames[mini(int(t / BallSim.RECORD_DT) + 1, sim.frames.size() - 1)] - b
				flat_v.y = 0.0
				var dir := flat_v.normalized() if flat_v.length() > 0.01 else line
				var eye2 := b - dir * 14.0 + Vector3(0, 3.0, 0)
				eye2.y = maxf(eye2.y, hole.get_height(eye2.x, eye2.z) + 2.0)
				return Transform3D(Basis.looking_at(b + dir * 10.0 - Vector3(0, 2.0, 0) - eye2, Vector3.UP), eye2)
			return _landing_cam(b, line)
		State.RESULT:
			# Look from behind the ball toward the pin so both sit on the
			# screen's vertical centre line (the long axis in portrait).
			var final_pos := _rest_pos()
			var to_pin := hole.pin - final_pos
			to_pin.y = 0.0
			var d := to_pin.length()
			var dir3 := to_pin.normalized() if d > 0.5 else line
			var back := maxf(d * 0.6, 3.0) + 4.0
			var eye3 := final_pos - dir3 * back + Vector3(0, maxf(d * 0.75, 3.0) + 3.0, 0)
			# Aim below the midpoint so ball and pin sit in the upper part of
			# the screen, clear of the result card.
			var look3 := final_pos.lerp(hole.pin, 0.5) - Vector3(0, maxf(d * 0.45, 2.0) + 1.5, 0) - dir3 * 1.0
			return Transform3D(Basis.looking_at(look3 - eye3, Vector3.UP), eye3)
	return cam.global_transform


func _landing_cam(look_at: Vector3, line: Vector3) -> Transform3D:
	var rest := _rest_pos()
	var focus := (sim.carry_pos + rest) * 0.5
	var side := line.cross(Vector3.UP)
	var eye := focus - line * 24.0 + side * 9.0 + Vector3(0, 9.0, 0)
	eye.y = maxf(eye.y, hole.get_height(eye.x, eye.z) + 3.0)
	return Transform3D(Basis.looking_at(look_at - eye, Vector3.UP), eye)


func _update_camera(delta: float) -> void:
	_apply_projection()
	var target := _camera_target()
	var rate := 4.0
	if state == State.FLYING:
		rate = 5.0 * play_speed
	var k := 1.0 - exp(-delta * rate)
	if map_view and state == State.AIMING:
		k = 1.0
	var o := cam.global_transform.origin.lerp(target.origin, k)
	var q := cam.global_transform.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
	cam.global_transform = Transform3D(Basis(q), o)


# ------------------------------------------------------------------ automation
# Used to drive the game headlessly for screenshots / smoke tests, e.g.
#   godot -- --seed=3 --autoswing --shots=/tmp/out --map --quit


func _run_automation() -> void:
	while state != State.AIMING:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	_screenshot("aim")
	if _auto.has("map"):
		map_view = true
		_snap_camera()
		for i in 3:
			await get_tree().process_frame
		_screenshot("map")
		map_view = false
		_snap_camera()
		await get_tree().process_frame
	if not _auto.has("autoswing"):
		if _auto.has("quit"):
			get_tree().quit()
		return
	if _auto.has("club"):
		club_idx = Clubs.index_of(_auto["club"])
		_refresh_club()
	if _auto.has("shape"):
		shape = float(_auto["shape"])
	# Real controls: hold, let go, tap (offset in on-screen ms from perfect).
	var hold := float(_auto.get("hold", "1.0"))
	var tap_ms := float(_auto.get("tap", "0"))
	_on_swing_pressed()
	var t0 := Time.get_ticks_usec() / 1.0e6
	var shot_mid := false
	while Time.get_ticks_usec() / 1.0e6 - t0 < hold:
		await get_tree().process_frame
		if not shot_mid and Time.get_ticks_usec() / 1.0e6 - t0 > hold * 0.6:
			shot_mid = true
			_screenshot("backswing")
	_on_swing_released()
	var ideal := SwingModel.ideal_for(swing.top)
	var tap_at := ideal.x + tap_ms / 1000.0 * swing.time_scale
	var lag_shot := false
	_manual_swing = true
	while state == State.AIMING:
		# Step the model ourselves so the tap lands at the exact moment even
		# at a low headless frame rate.
		if swing.state == SwingModel.State.DOWNSWING:
			if not swing.tapped and _auto.get("tap", "") != "none" and swing.sim_t >= tap_at - 0.0005:
				swing.press()
			if not lag_shot and swing.sim_t >= ideal.x * 0.85:
				lag_shot = true
				_screenshot("downswing")
		_swing_clock = Time.get_ticks_usec() / 1.0e6
		for i in 8:
			if swing.state == SwingModel.State.DOWNSWING and not swing.tapped and _auto.get("tap", "") != "none" and swing.sim_t >= tap_at - 0.0005:
				swing.press()
			swing.update(0.0025)
		if swing.result != null and state == State.AIMING:
			_hit(swing.result)
		await get_tree().process_frame
	_manual_swing = false
	print("SWING backswing %.2f speed %.3f release %.1f ms lag %.1f ftp %.2f path %.2f" % [last_swing.backswing, last_swing.speed_frac, last_swing.release_error_ms, last_swing.lag_deg, last_swing.swing.face_to_path_deg, last_swing.swing.path_deg])
	await _wait_result()


func _wait_result() -> void:
	play_speed = float(_auto.get("speed", "3"))
	while play_t < sim.carry_time * 0.6:
		await get_tree().process_frame
	_screenshot("flight")
	while state != State.RESULT:
		await get_tree().process_frame
	for i in 20:
		await get_tree().process_frame
	_screenshot("result")
	print("RESULT ", hud.result_title.text, " | ", hud.result_sub.text)
	print(hud.result_body.text)
	if _auto.has("quit"):
		get_tree().quit()


func _screenshot(tag: String) -> void:
	if not _auto.has("shots"):
		return
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_auto["shots"], tag]
	img.save_png(path)
	print("saved ", path)
