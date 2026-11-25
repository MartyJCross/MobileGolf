extends Node3D
## Game controller: holes, shot planning, hitting, playback, cameras, results.
##
## The skill is seeing the shot: you drag a landing spot onto the course,
## pick a wedge, a height and spin/curve, and the ShotPlanner shows the
## flight, wind included (white = clear, red = hits something). Slopes,
## green firmness and how the ball releases or checks after landing are
## yours to read (and the wind too, in the "still air" pro setting). HIT has
## a forgiving accuracy needle.

enum State { LOADING, AIMING, FLYING, RESULT }

const CAM_FOV := 55.0
const BALL_VISUAL_SCALE := 0.004 # ball drawn at least this fraction of camera distance
const PLAN_INTERVAL := 0.06 # seconds between re-plans while dragging
const MAX_TARGET_DIST := 120.0
const DRAG_GAIN := 0.65 # the landing spot moves a little slower than your thumb, for fine placement
const ERR_YAW_DEG := 1.8 # full needle miss: start direction error
const ERR_SPEED := 0.035 # full needle miss: speed error

var state: int = State.LOADING
var stats := Stats.new()
var hole: HoleData
var hole_no := 1
var map_view := false
var world_env: Environment

var course: CourseView
var cam: Camera3D
var ball: MeshInstance3D
var tracer: Tracer
var aim_line: Tracer # planned flight (clear part)
var block_line: Tracer # planned flight after it hits something
var carry_ring: MeshInstance3D
var block_marker: MeshInstance3D
var hud: Hud

var shot := ShotPlanner.Shot.new()
var target := Vector3.ZERO
var plan: ShotPlanner.Plan
var _plan_dirty := true
var _plan_wait := 0.0

var sim: BallSim
var last_launch: LaunchModel.Result
var last_error := 0.0
var last_target := Vector3.ZERO
var play_t := 0.0
var play_speed := 1.0
var ball_start := Vector3.ZERO
var _next_task := -1
var _next_hole: HoleData
var _next_no := -1

# Automation for headless screenshots / smoke tests (cmdline user args).
var _auto := {}


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
	hud.hit_button.meter_on = stats.meter
	hud.meter_check.set_pressed_no_signal(stats.meter)
	hud.still_air_check.set_pressed_no_signal(not stats.plan_wind)
	hud.set_stats(stats)
	_load_hole(stats.hole_number)
	if not _auto.is_empty():
		_run_automation()


func _exit_tree() -> void:
	# Never leave the next-hole worker running while the engine shuts down.
	if _next_task != -1:
		WorkerThreadPool.wait_for_task_completion(_next_task)
		_next_task = -1


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
	sun.directional_shadow_max_distance = 120.0
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
	aim_line.pixel_width = 0.003
	add_child(aim_line)
	block_line = Tracer.new()
	block_line.color = Color(1.0, 0.3, 0.25)
	block_line.pixel_width = 0.003
	add_child(block_line)

	carry_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	carry_ring.mesh = torus
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.75, 0.95, 1.0, 0.9)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.no_depth_test = true
	carry_ring.material_override = rm
	carry_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(carry_ring)

	block_marker = MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 1.0
	bs.height = 2.0
	block_marker.mesh = bs
	var bmm := StandardMaterial3D.new()
	bmm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmm.albedo_color = Color(1.0, 0.2, 0.15, 0.85)
	bmm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmm.no_depth_test = true
	block_marker.material_override = bmm
	block_marker.visible = false
	add_child(block_marker)

	cam = Camera3D.new()
	cam.fov = CAM_FOV
	cam.far = 1500.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.target_drag.connect(_on_target_drag)
	hud.view_tapped.connect(_on_view_tapped)
	hud.club_selected.connect(func(i): shot.club_idx = i; _replan(true))
	hud.height_selected.connect(func(i): shot.height_idx = i; _replan(true))
	hud.spin_changed.connect(func(v: Vector2):
		shot.curve = v.x
		shot.spin = v.y
		_replan(false))
	hud.hit_pressed.connect(_on_hit)
	hud.next_pressed.connect(_on_next)
	hud.retry_pressed.connect(_on_retry)
	hud.map_toggled.connect(func(): map_view = not map_view; _snap_camera())
	hud.meter_toggled.connect(func(on):
		stats.meter = on
		hud.hit_button.meter_on = on
		stats.save_stats())
	hud.still_air_toggled.connect(func(on):
		stats.plan_wind = not on
		stats.save_stats()
		_replan(true))
	hud.reset_stats_pressed.connect(func():
		stats.reset()
		hud.set_stats(stats))


# ------------------------------------------------------------------ holes

func _load_hole(n: int) -> void:
	state = State.LOADING
	hud.hide_result()
	hud.set_shot_visible(false)
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
	shot = ShotPlanner.Shot.new()
	shot.club_idx = _default_club()
	hud.spin_ball.value = Vector2.ZERO
	hud.spin_ball.queue_redraw()
	_reset_ball()
	hud.show_toast("")
	_enter_aiming()
	_prefetch(n + 1)


## The wedge whose stock carry suits the distance (shortest that gets there).
func _default_club() -> int:
	for i in range(Clubs.count() - 1, -1, -1):
		if Clubs.stock_carry_m(Clubs.get_club(i)) >= hole.distance + 2.0:
			return i
	return 0


func _prefetch(n: int) -> void:
	if _auto.has("noprefetch"):
		return
	_next_no = n
	var s := stats.hole_seed(n)
	_next_task = WorkerThreadPool.add_task(func(): _next_hole = HoleGenerator.generate(s), false, "next hole")


func _reset_ball() -> void:
	ball_start = hole.tee + Vector3(0, BallSim.RADIUS + 0.012, 0) # teed up
	ball.position = ball_start
	target = hole.pin
	plan = null
	tracer.clear()


func _enter_aiming() -> void:
	state = State.AIMING
	map_view = false
	hud.hide_result()
	hud.set_shot_visible(true)
	hud.set_selection(shot.club_idx, shot.height_idx)
	hud.set_hole_info(hole_no, hole, _aim_yaw())
	hud.set_stats(stats)
	_replan(true)
	_update_plan_now()
	_snap_camera()


# ------------------------------------------------------------------ input

## Drag on the course: the landing spot moves with your thumb (relative, so
## your thumb never covers it).
func _on_target_drag(pos: Vector2, rel: Vector2) -> void:
	if state != State.AIMING or hud.settings_panel.visible:
		return
	var a = _ground_at(pos - rel)
	var b = _ground_at(pos)
	if a == null or b == null:
		return
	var d: Vector3 = (b - a) * DRAG_GAIN
	var t := target + Vector3(d.x, 0, d.z)
	var off := Vector2(t.x - ball_start.x, t.z - ball_start.z)
	if off.length() > MAX_TARGET_DIST:
		off = off.normalized() * MAX_TARGET_DIST
	t = Vector3(ball_start.x + off.x, 0, ball_start.z + off.y)
	if hole.is_out_of_bounds(t.x, t.z):
		return
	t.y = hole.get_contact_height(t.x, t.z)
	target = t
	_replan(false)


## Where a screen point's ray meets the ground (null if it doesn't).
func _ground_at(screen: Vector2):
	var o := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var t := 0.0
	var prev_t := 0.0
	for i in 400:
		var p := o + dir * t
		var h := hole.get_height(p.x, p.z)
		if p.y <= h:
			# Refine between prev_t and t.
			var lo := prev_t
			var hi := t
			for k in 12:
				var mid := (lo + hi) * 0.5
				var q := o + dir * mid
				if q.y <= hole.get_height(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return o + dir * hi
		prev_t = t
		t += maxf(0.25, (p.y - h) * 0.5)
		if t > 3000.0:
			break
	return null


func _on_view_tapped() -> void:
	if state == State.FLYING:
		play_speed = 4.0


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
	target = last_target
	_enter_aiming()


# ------------------------------------------------------------------ planning

func _replan(reset_warm: bool) -> void:
	_plan_dirty = true
	if reset_warm:
		plan = null


func _update_plan_now() -> void:
	if hole == null:
		return
	plan = ShotPlanner.solve(hole, ball_start, target, shot, plan, stats.plan_wind)
	_plan_dirty = false
	_plan_wait = PLAN_INTERVAL
	_draw_plan()


func _draw_plan() -> void:
	if plan == null:
		return
	aim_line.set_points(plan.path)
	if plan.blocked:
		# Continue the flight in red from where it hits.
		var red := PackedVector3Array()
		var started := false
		for p in plan.clear_path:
			if not started and p.distance_to(plan.block_pos) < 1.5:
				started = true
			if started:
				red.append(p)
		if red.size() < 2:
			red = PackedVector3Array([plan.block_pos, plan.landing])
		block_line.set_points(red)
		block_marker.position = plan.block_pos
		block_marker.visible = true
	else:
		block_line.clear()
		block_marker.visible = false
	hud.profile.show_plan(hole, plan, ball_start)
	var info := "Carry %d m · Peak %d m · %s" % [roundi(Vector2(plan.landing.x - ball_start.x, plan.landing.z - ball_start.z).length()), roundi(plan.apex), SpinBall.describe(Vector2(shot.curve, shot.spin))]
	if plan.too_far:
		info = "Too far for the %s: pick a stronger wedge or lower shot" % Clubs.get_club(shot.club_idx)["name"]
	elif plan.too_short:
		info = "Too short to plan with this club"
	elif plan.blocked:
		info += "\nBlocked! Go over, under or around it"
	hud.shot_info.text = info
	hud.update_wind(hole, _aim_yaw())


func _aim_yaw() -> float:
	return ShotPlanner.bearing(ball_start, target)


# ------------------------------------------------------------------ shot

func _on_hit(err: float) -> void:
	if state != State.AIMING:
		return
	if _plan_dirty or plan == null:
		_update_plan_now()
	if plan.too_far:
		hud.show_toast("Too far: pick a stronger wedge or a lower shot")
		get_tree().create_timer(1.5).timeout.connect(func(): hud.show_toast(""))
		return
	last_error = err
	last_target = target
	var s := plan.speed_frac * (1.0 + ERR_SPEED * err)
	var yaw := plan.yaw_deg + ERR_YAW_DEG * err
	var lv := ShotPlanner.launch_vectors(shot, s, yaw)
	last_launch = lv[2]
	sim = BallSim.new(hole)
	sim.rng.seed = randi()
	sim.launch(ball_start, lv[0], lv[1])
	sim.simulate()
	play_t = 0.0
	play_speed = 1.0
	state = State.FLYING
	hud.set_shot_visible(false)
	aim_line.clear()
	block_line.clear()
	carry_ring.visible = false
	block_marker.visible = false
	hud.pin_marker.visible = false
	Input.vibrate_handheld(25)


func _finish_shot() -> void:
	state = State.RESULT
	var title := ""
	var sub := ""
	var proximity := 0.0
	var on_green := false
	var ace := false
	var final_pos := _rest_pos()
	match sim.phase:
		BallSim.Phase.HOLED:
			title = "HOLE IN ONE!"
			sub = "Into the cup"
			ace = true
			on_green = true
		BallSim.Phase.WATER, BallSim.Phase.OUT:
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
	var mph := 1.0 / Clubs.MPH
	var lines: Array[String] = []
	var land_miss := Vector2(sim.carry_pos.x - last_target.x, sim.carry_pos.z - last_target.z).length()
	var strike := "Pure strike" if absf(last_error) < 0.01 else ("Pushed a touch" if last_error > 0 else "Pulled a touch")
	lines.append("Landed %.1f m from your spot  ·  %s" % [land_miss, strike])
	if sim.hit_tree:
		lines.append("Clipped an obstacle!")
	var roll := sim.total_distance() - sim.carry_distance()
	lines.append("Carry %.1f m   %s %.1f m   Peak %.1f m" % [sim.carry_distance(), "Rolled" if roll >= 0 else "Spun back", absf(roll), sim.apex])
	lines.append("Ball %.0f mph   Launch %.1f°   Spin %d rpm" % [l.ball_speed * mph, l.launch_v_deg, roundi(l.spin_rpm)])
	lines.append("Landed at %.0f° with %d rpm" % [sim.land_angle_deg, roundi(sim.land_spin_rpm)])
	return "\n".join(lines)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	match state:
		State.AIMING:
			_plan_wait -= delta
			if _plan_dirty and _plan_wait <= 0.0:
				_update_plan_now()
			_update_camera(delta)
			_update_aim_visuals()
		State.FLYING:
			_play(delta)
			_update_camera(delta)
		State.RESULT:
			_update_camera(delta)
	_update_ball_scale()
	if state == State.AIMING:
		aim_line.redraw()
		block_line.redraw()
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
	for k in range(0, i + 1, 2):
		pts.append(sim.frames[k])
	pts.append(ball.position)
	tracer.points = pts


func _update_ball_scale() -> void:
	var d := cam.global_position.distance_to(ball.global_position)
	ball.scale = Vector3.ONE * maxf(1.0, d * BALL_VISUAL_SCALE / BallSim.RADIUS)


func _update_aim_visuals() -> void:
	if hole == null:
		return
	var p := target
	p.y = hole.get_contact_height(p.x, p.z) + 0.05
	carry_ring.position = p
	var ring_scale := clampf(cam.global_position.distance_to(p) * 0.03, 1.0, 5.0)
	carry_ring.scale = Vector3(ring_scale, 0.25, ring_scale)
	carry_ring.visible = true
	if block_marker.visible:
		block_marker.scale = Vector3.ONE * clampf(cam.global_position.distance_to(block_marker.position) * 0.012, 0.3, 1.5)
	var pin_top := hole.pin + Vector3(0, 2.4, 0)
	var dist := Vector2(hole.pin.x - ball_start.x, hole.pin.z - ball_start.z).length()
	hud.place_marker(hud.pin_marker, cam, pin_top, "Pin %d m" % roundi(dist), 6.0)
	var td := Vector2(target.x - ball_start.x, target.z - ball_start.z).length()
	hud.place_marker(hud.target_marker, cam, p, "%d m" % roundi(td), -44.0)
	if hud.target_marker.get_rect().intersects(hud.pin_marker.get_rect()):
		hud.target_marker.position.y = hud.pin_marker.position.y + hud.pin_marker.size.y


# ------------------------------------------------------------------ cameras

func _snap_camera() -> void:
	cam.global_transform = _camera_target()
	_apply_projection()


func _apply_projection() -> void:
	if map_view and state == State.AIMING:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = hole.distance + 45.0
		world_env.fog_enabled = false
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = CAM_FOV
		world_env.fog_enabled = true


func _line() -> Vector3:
	var v := hole.pin - hole.tee
	v.y = 0.0
	return v.normalized()


func _camera_target() -> Transform3D:
	var line := _line()
	match state:
		State.AIMING, State.LOADING:
			if map_view:
				# Top-down, tee at the bottom, green at the top; the shot panel
				# covers the bottom third, so shift the view down a little.
				var center := (hole.tee + hole.green_center3()) * 0.5 - line * (hole.distance * 0.18)
				return Transform3D(Basis.looking_at(Vector3.DOWN, line), center + Vector3(0, 300, 0))
			return _aim_cam(line)
		State.FLYING:
			# Short holes: stay high behind the tee watching the whole flight,
			# then cut close to see the ball check or release.
			var b := ball.position
			if play_t < sim.carry_time - 0.5:
				var dd := hole.distance
				var eye2 := ball_start - line * (9.0 + dd * 0.22) + Vector3(0, 7.0 + dd * 0.2, 0)
				var look2 := (ball_start + line * (dd * 0.55)).lerp(b, 0.5)
				return Transform3D(Basis.looking_at(look2 - eye2, Vector3.UP), eye2)
			return _landing_cam(b, line)
		State.RESULT:
			var final_pos := _rest_pos()
			var to_pin := hole.pin - final_pos
			to_pin.y = 0.0
			var dd := to_pin.length()
			var dir3 := to_pin.normalized() if dd > 0.5 else line
			var back := maxf(dd * 0.6, 3.0) + 4.0
			var eye3 := final_pos - dir3 * back + Vector3(0, maxf(dd * 0.75, 3.0) + 3.0, 0)
			var look3 := final_pos.lerp(hole.pin, 0.5) - Vector3(0, maxf(dd * 0.45, 2.0) + 1.5, 0) - dir3 * 1.0
			return Transform3D(Basis.looking_at(look3 - eye3, Vector3.UP), eye3)
	return cam.global_transform


## High behind the tee, looking down over the obstacles, framed so the whole
## planned flight sits in the band between the info bar and the shot panel.
func _aim_cam(line: Vector3) -> Transform3D:
	var d := maxf(hole.distance, Vector2(target.x - ball_start.x, target.z - ball_start.z).length())
	var apex := plan.apex if plan != null else d * 0.2
	var eye := ball_start - line * (9.0 + d * 0.22) + Vector3(0, 9.0 + d * 0.24 + apex * 0.4, 0)
	var focus := ball_start + line * (d * 0.62)
	focus.y = lerpf(ball_start.y, hole.pin.y, 0.6) + apex * 0.2
	var basis := Basis.looking_at(focus - eye, Vector3.UP)
	# Pitch down a little more so the focus sits ~40% from the top of the
	# screen, above the shot panel.
	basis = basis.rotated(basis.x, deg_to_rad(-6.0))
	return Transform3D(basis, eye)


func _landing_cam(look_at: Vector3, line: Vector3) -> Transform3D:
	var rest := _rest_pos()
	var focus := (sim.carry_pos + rest) * 0.5
	var side := line.cross(Vector3.UP)
	var eye := focus - line * 16.0 + side * 7.0 + Vector3(0, 7.0, 0)
	eye.y = maxf(eye.y, hole.get_height(eye.x, eye.z) + 3.0)
	return Transform3D(Basis.looking_at(look_at - eye, Vector3.UP), eye)


func _update_camera(delta: float) -> void:
	_apply_projection()
	var tgt := _camera_target()
	var rate := 4.0
	if state == State.FLYING:
		rate = 5.0 * play_speed
	var k := 1.0 - exp(-delta * rate)
	if map_view and state == State.AIMING:
		k = 1.0
	var o := cam.global_transform.origin.lerp(tgt.origin, k)
	var q := cam.global_transform.basis.get_rotation_quaternion().slerp(tgt.basis.get_rotation_quaternion(), k)
	cam.global_transform = Transform3D(Basis(q), o)


# ------------------------------------------------------------------ automation
# Drives the game headlessly for screenshots / smoke tests, e.g.
#   godot -- --seed=3 --route --shots=/tmp/out --map --quit
# --route plays the generator's found route; --err=0.5 hits off-centre.


func _run_automation() -> void:
	while state != State.AIMING:
		await get_tree().process_frame
	if _auto.has("route"):
		var r := HoleGenerator.find_route(hole)
		if r != null:
			shot = r
			hud.set_selection(shot.club_idx, shot.height_idx)
			hud.spin_ball.value = Vector2(shot.curve, shot.spin)
			hud.spin_ball.queue_redraw()
	if _auto.has("straight"):
		shot = ShotPlanner.Shot.new()
		shot.club_idx = _default_club()
	_replan(true)
	_update_plan_now()
	for i in 30:
		await get_tree().process_frame
	_screenshot("aim")
	print("PLAN club %s height %s spin %.1f curve %.1f power %.2f blocked %s too_far %s" % [Clubs.get_club(shot.club_idx)["id"], ShotPlanner.HEIGHTS[shot.height_idx]["name"], shot.spin, shot.curve, plan.speed_frac, plan.blocked, plan.too_far])
	if _auto.has("drag"):
		# Drag the landing spot through the real input path (screen pixels).
		var xy: PackedStringArray = _auto["drag"].split(",")
		var total := Vector2(float(xy[0]), float(xy[1]))
		var before := target
		var p0 := cam.unproject_position(target)
		for i in 10:
			hud.target_drag.emit(p0 + total * (i + 1) / 10.0, total / 10.0)
			await get_tree().process_frame
		_update_plan_now()
		print("DRAG moved target %.1f m right, %.1f m further; plan blocked %s power %.2f" % [target.x - before.x, -(target.z - before.z), plan.blocked, plan.speed_frac])
		for i in 5:
			await get_tree().process_frame
		_screenshot("dragged")
	if _auto.has("map"):
		map_view = true
		_snap_camera()
		for i in 3:
			await get_tree().process_frame
		_screenshot("map")
		map_view = false
		_snap_camera()
		await get_tree().process_frame
	if _auto.has("settings"):
		hud.settings_panel.visible = true
		for i in 3:
			await get_tree().process_frame
		_screenshot("settings")
		hud.settings_panel.visible = false
	if not _auto.has("hit"):
		if _auto.has("quit"):
			get_tree().quit()
		return
	_on_hit(float(_auto.get("err", "0")))
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
