class_name ProfileView
extends Control
## Side-on view of the planned shot: height against distance along its path,
## with the ground and any obstacles the ball passes near drawn as
## silhouettes. Shows at a glance whether a shot goes over or under things.

var hole: HoleData
var plan: ShotPlanner.Plan
var start := Vector3.ZERO

const LATERAL_MARGIN := 1.2 # obstacles this far beside the track still show (faded)


func show_plan(h: HoleData, p: ShotPlanner.Plan, from: Vector3) -> void:
	hole = h
	plan = p
	start = from
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.04, 0.55))
	if hole == null or plan == null or plan.clear_path.size() < 2:
		return
	var path := plan.clear_path
	# Distance along the ground track for each path point.
	var dist := PackedFloat32Array()
	var acc := 0.0
	dist.append(0.0)
	for i in range(1, path.size()):
		acc += Vector2(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z).length()
		dist.append(acc)
	var total := maxf(acc, 5.0)
	var base := start.y
	var top := 3.0
	for p in path:
		top = maxf(top, p.y - base + 2.0)

	# Obstacles near the track: [s, kind, data...]
	var near: Array = []
	for o in hole.obstacles:
		var kind: int = o["kind"]
		if kind == GolfTerrain.PIN:
			continue
		var c: Vector3 = o.get("center", o.get("base", Vector3.ZERO))
		var best := 1e9
		var best_s := 0.0
		for i in path.size():
			var dd := Vector2(path[i].x - c.x, path[i].z - c.z).length()
			if dd < best:
				best = dd
				best_s = dist[i]
		var reach := 0.0
		match kind:
			GolfTerrain.CANOPY, GolfTerrain.BUSH:
				reach = o["r"]
			GolfTerrain.TRUNK:
				reach = o["r"]
			GolfTerrain.WALL:
				reach = o["half"].x
		if best > reach + LATERAL_MARGIN:
			continue
		near.append([best_s, o, best])
		if kind == GolfTerrain.CANOPY:
			top = maxf(top, c.y + float(o["r"]) - base + 1.0)

	var pad := Vector2(10, 8)
	var w := size.x - pad.x * 2.0
	var h := size.y - pad.y * 2.0
	var to_px := func(s_m: float, y_m: float) -> Vector2:
		return Vector2(pad.x + s_m / total * w, pad.y + h - (y_m - base) / top * h)

	# Ground along the track.
	var ground := PackedVector2Array()
	for i in range(0, path.size(), maxi(1, path.size() / 40)):
		var g := hole.get_height(path[i].x, path[i].z)
		ground.append(to_px.call(dist[i], g))
	var last := path[path.size() - 1]
	ground.append(to_px.call(total, hole.get_height(last.x, last.z)))
	var poly := ground.duplicate()
	poly.append(Vector2(pad.x + w, size.y))
	poly.append(Vector2(pad.x, size.y))
	draw_colored_polygon(poly, Color(0.2, 0.42, 0.18, 0.9))

	# Obstacles (faded if they're off to the side of the track).
	for n in near:
		var s_m: float = n[0]
		var o: Dictionary = n[1]
		var lateral: float = n[2]
		var kind: int = o["kind"]
		match kind:
			GolfTerrain.CANOPY, GolfTerrain.BUSH:
				var r: float = o["r"]
				var c: Vector3 = o["center"]
				var on := lateral < r
				var half := sqrt(maxf(r * r - lateral * lateral, 0.0)) if on else r * 0.5
				var col := Color(0.15, 0.4, 0.15, 0.95 if on else 0.35)
				var cx: Vector2 = to_px.call(s_m, c.y)
				var rx := maxf(half / total * w, 3.0)
				var ry := maxf(half / top * h, 3.0)
				_ellipse(cx, rx, ry, col)
			GolfTerrain.TRUNK:
				var b: Vector3 = o["base"]
				var p0: Vector2 = to_px.call(s_m, b.y)
				var p1: Vector2 = to_px.call(s_m, b.y + float(o["h"]))
				draw_line(p0, p1, Color(0.4, 0.28, 0.18, 0.9 if lateral < float(o["r"]) + 0.3 else 0.35), 3.0)
			GolfTerrain.WALL:
				var c2: Vector3 = o["center"]
				var hh: float = o["half"].y
				var q0: Vector2 = to_px.call(s_m, c2.y - hh)
				var q1: Vector2 = to_px.call(s_m, c2.y + hh)
				draw_rect(Rect2(q1.x - 3, q1.y, 6, q0.y - q1.y), Color(0.62, 0.6, 0.55))

	# The flight: white while clear, red from where it hits something.
	var pts := PackedVector2Array()
	var red_from := -1
	for i in path.size():
		pts.append(to_px.call(dist[i], path[i].y))
		if plan.blocked and red_from < 0 and path[i].distance_to(plan.block_pos) < 1.5:
			red_from = i
	if red_from < 0:
		draw_polyline(pts, Color.WHITE, 3.0, true)
	else:
		if red_from > 0:
			draw_polyline(pts.slice(0, red_from + 1), Color.WHITE, 3.0, true)
		draw_polyline(pts.slice(red_from), Color(1.0, 0.3, 0.25), 3.0, true)
		draw_circle(pts[red_from], 6.0, Color(1.0, 0.25, 0.2))
	draw_circle(pts[pts.size() - 1], 5.0, Color(0.75, 0.95, 1.0))


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var p := PackedVector2Array()
	for i in 20:
		var a := i * TAU / 20.0
		p.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(p, col)
