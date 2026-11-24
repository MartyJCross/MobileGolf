class_name Tracer
extends MeshInstance3D
## Camera-facing ribbon drawn through the ball's path, kept a roughly
## constant width on screen.

var points := PackedVector3Array()
var color := Color(1.0, 0.95, 0.55)
var pixel_width := 0.004 # fraction of distance to camera
var _im := ImmediateMesh.new()


func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func clear() -> void:
	points.clear()
	_im.clear_surfaces()


func set_points(p: PackedVector3Array) -> void:
	points = p
	redraw()


func redraw() -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or points.size() < 2:
		return
	var eye := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := points.size()
	for i in n:
		var p := points[i]
		var tangent := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)])
		if tangent.length_squared() < 1e-10:
			tangent = Vector3.FORWARD
		var to_eye := eye - p
		var side := tangent.cross(to_eye).normalized()
		var w := to_eye.length() * pixel_width
		var a := clampf(float(i) / 8.0, 0.0, 1.0) * 0.9
		var c := Color(color.r, color.g, color.b, a)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p - side * w)
		_im.surface_set_color(c)
		_im.surface_add_vertex(p + side * w)
	_im.surface_end()
