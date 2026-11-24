class_name CourseView
extends Node3D
## Builds the visible hole from HoleData: terrain mesh, water, pin, trees,
## tee markers.

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")

var hole: HoleData
var flag_cloth: MeshInstance3D
var _time := 0.0


func build(h: HoleData) -> void:
	for c in get_children():
		c.queue_free()
	hole = h
	_build_terrain()
	if hole.pond != null:
		_build_water()
	_build_pin()
	_build_trees()
	_build_tee_markers()


func _process(delta: float) -> void:
	_time += delta
	if flag_cloth:
		# Flag streams with the wind.
		var w := hole.wind_at(2.0)
		var yaw := atan2(w.x, w.z) if w.length() > 0.3 else 0.0
		flag_cloth.get_parent().rotation.y = yaw
		flag_cloth.rotation.y = PI * 0.5 + sin(_time * (2.0 + w.length())) * 0.12


func _build_terrain() -> void:
	var hw := hole.hw
	var hh := hole.hh
	var verts := PackedVector3Array()
	verts.resize(hw * hh)
	for iz in hh:
		for ix in hw:
			var i := iz * hw + ix
			verts[i] = Vector3(hole.origin.x + ix * HoleData.HEIGHT_CELL, hole.heights[i], hole.origin.y + iz * HoleData.HEIGHT_CELL)
	var idx := PackedInt32Array()
	idx.resize((hw - 1) * (hh - 1) * 6)
	var k := 0
	for iz in hh - 1:
		for ix in hw - 1:
			var i := iz * hw + ix
			idx[k] = i
			idx[k + 1] = i + 1
			idx[k + 2] = i + hw
			idx[k + 3] = i + 1
			idx[k + 4] = i + hw + 1
			idx[k + 5] = i + hw
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = hole.normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("surface_map", _surface_texture())
	# Texel centres sit on the sample points, so shift by half a cell.
	mat.set_shader_parameter("map_origin", hole.origin - Vector2.ONE * HoleData.SURF_CELL * 0.5)
	mat.set_shader_parameter("map_size", Vector2(hole.sw * HoleData.SURF_CELL, hole.sh * HoleData.SURF_CELL))
	mat.set_shader_parameter("line_dir", Vector2(hole.pin.x, hole.pin.z).normalized())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.name = "Terrain"
	add_child(mi)
	var skirt := MeshInstance3D.new()
	skirt.mesh = _skirt_mesh()
	skirt.material_override = mat
	skirt.name = "Skirt"
	add_child(skirt)


## Extends the terrain's border vertices far outward (flat), so the edge of
## the playable grid disappears into the fog instead of ending in a cliff.
func _skirt_mesh() -> ArrayMesh:
	var hw := hole.hw
	var hh := hole.hh
	var ring: Array[int] = []
	for ix in hw:
		ring.append(ix) # front edge (min z)
	for iz in range(1, hh):
		ring.append(iz * hw + hw - 1) # right edge
	for ix in range(hw - 2, -1, -1):
		ring.append((hh - 1) * hw + ix) # back edge
	for iz in range(hh - 2, 0, -1):
		ring.append(iz * hw) # left edge
	var center := Vector3(hole.origin.x + (hw - 1) * 0.5, 0.0, hole.origin.y + (hh - 1) * 0.5)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	for i in ring:
		var v := Vector3(hole.origin.x + (i % hw) * HoleData.HEIGHT_CELL, hole.heights[i], hole.origin.y + (i / hw) * HoleData.HEIGHT_CELL)
		var out := Vector3(v.x - center.x, 0.0, v.z - center.z).normalized()
		verts.append(v)
		verts.append(v + out * 600.0 + Vector3(0, -2.0, 0))
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
	var idx := PackedInt32Array()
	var n := ring.size()
	for k in n:
		var a := k * 2
		var b := ((k + 1) % n) * 2
		idx.append_array([a, b, a + 1, b, b + 1, a + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _surface_texture() -> ImageTexture:
	var img := Image.create_from_data(hole.sw, hole.sh, false, Image.FORMAT_RGBA8, hole.surface_fields)
	return ImageTexture.create_from_image(img)


func _build_water() -> void:
	var box := hole.pond.bbox.grow(8.0)
	var plane := PlaneMesh.new()
	plane.size = box.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.33, 0.45, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic_specular = 0.8
	plane.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(box.get_center().x, hole.water_level, box.get_center().y)
	mi.name = "Water"
	add_child(mi)


func _build_pin() -> void:
	var pin := Node3D.new()
	pin.name = "Pin"
	pin.position = hole.pin
	add_child(pin)
	var cup := MeshInstance3D.new()
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = BallSim.CUP_RADIUS
	cup_mesh.bottom_radius = BallSim.CUP_RADIUS
	cup_mesh.height = 0.01
	cup.mesh = cup_mesh
	cup.material_override = _flat_mat(Color(0.05, 0.05, 0.05))
	cup.position.y = 0.004
	pin.add_child(cup)
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.025
	stick_mesh.bottom_radius = 0.025
	stick_mesh.height = 2.3
	stick_mesh.radial_segments = 8
	stick.mesh = stick_mesh
	stick.material_override = _flat_mat(Color(0.95, 0.95, 0.92))
	stick.position.y = 1.15
	pin.add_child(stick)
	var pivot := Node3D.new()
	pivot.position.y = 2.05
	pin.add_child(pivot)
	flag_cloth = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.75, 0.5)
	flag_cloth.mesh = q
	var fm := _flat_mat(Color(0.95, 0.85, 0.1))
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag_cloth.material_override = fm
	# The quad faces +Z; turned 90 deg it extends along the pivot's +Z, which
	# _process points downwind.
	flag_cloth.position = Vector3(0, 0, 0.38)
	flag_cloth.rotation.y = PI * 0.5
	pivot.add_child(flag_cloth)


func _build_trees() -> void:
	if hole.trees.is_empty():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.22
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.33, 0.24, 0.16)
	trunk_mesh.material = trunk_mat
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.0
	canopy_mesh.height = 2.0
	canopy_mesh.radial_segments = 10
	canopy_mesh.rings = 6
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.vertex_color_use_as_albedo = true
	canopy_mat.roughness = 1.0
	canopy_mesh.material = canopy_mat

	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.mesh = trunk_mesh
	mm_t.instance_count = hole.trees.size()
	var mm_c := MultiMesh.new()
	mm_c.transform_format = MultiMesh.TRANSFORM_3D
	mm_c.use_colors = true
	mm_c.mesh = canopy_mesh
	mm_c.instance_count = hole.trees.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hole.seed_value
	for i in hole.trees.size():
		var t: Dictionary = hole.trees[i]
		var base: Vector3 = t["base"]
		var trunk_h: float = t["trunk"]
		var r: float = t["r"]
		var tb := Basis().scaled(Vector3(1.0, trunk_h + r * 0.5, 1.0))
		mm_t.set_instance_transform(i, Transform3D(tb, base + Vector3(0, (trunk_h + r * 0.5) * 0.5, 0)))
		var cb := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(r, r * rng.randf_range(0.9, 1.25), r))
		mm_c.set_instance_transform(i, Transform3D(cb, t["pos"]))
		var g := rng.randf_range(0.0, 1.0)
		mm_c.set_instance_color(i, Color(0.09 + 0.08 * g, 0.24 + 0.12 * g, 0.08 + 0.04 * g))
	var ti := MultiMeshInstance3D.new()
	ti.multimesh = mm_t
	ti.name = "Trunks"
	add_child(ti)
	var ci := MultiMeshInstance3D.new()
	ci.multimesh = mm_c
	ci.name = "Canopies"
	add_child(ci)


func _build_tee_markers() -> void:
	var m := SphereMesh.new()
	m.radius = 0.08
	m.height = 0.16
	for side in [-2.5, 2.5]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _flat_mat(Color(0.9, 0.15, 0.1))
		var x: float = side
		mi.position = Vector3(x, hole.get_height(x, -0.5) + 0.06, -0.5)
		add_child(mi)


func _flat_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
