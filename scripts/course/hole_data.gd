class_name HoleData
extends GolfTerrain
## A generated par 3. Heights live on a 1 m grid (bilinear), surfaces on a
## 0.5 m grid. Physics and rendering read the same data, so the ball always
## reacts to exactly what is drawn.

const HEIGHT_CELL := 1.0
const SURF_CELL := 0.5

var seed_value: int = 0
var distance := 150.0 # tee to pin, horizontal, m
var tee := Vector3.ZERO
var elevation := 0.0 # pin height relative to tee, m
var green: Blob
var fringe_width := 1.6
var approach_start := Vector2.ZERO # fairway strip in front of the green
var approach_end := Vector2.ZERO
var approach_half_width := 0.0
var bunkers: Array[Blob] = []
var pond: Blob = null
var water_level := -1000.0

# Grid
var origin := Vector2.ZERO # world x, z of grid cell (0,0)
var hw := 0 # height grid size
var hh := 0
var heights := PackedFloat32Array()
var normals := PackedVector3Array()
var sw := 0 # surface grid size
var sh := 0
var surfaces := PackedByteArray()


func size_m() -> Vector2:
	return Vector2((hw - 1) * HEIGHT_CELL, (hh - 1) * HEIGHT_CELL)


func _hidx(ix: int, iz: int) -> int:
	return clampi(iz, 0, hh - 1) * hw + clampi(ix, 0, hw - 1)


func get_height(x: float, z: float) -> float:
	var fx := (x - origin.x) / HEIGHT_CELL
	var fz := (z - origin.y) / HEIGHT_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var h00 := heights[_hidx(ix, iz)]
	var h10 := heights[_hidx(ix + 1, iz)]
	var h01 := heights[_hidx(ix, iz + 1)]
	var h11 := heights[_hidx(ix + 1, iz + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func get_normal(x: float, z: float) -> Vector3:
	var fx := (x - origin.x) / HEIGHT_CELL
	var fz := (z - origin.y) / HEIGHT_CELL
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var n00 := normals[_hidx(ix, iz)]
	var n10 := normals[_hidx(ix + 1, iz)]
	var n01 := normals[_hidx(ix, iz + 1)]
	var n11 := normals[_hidx(ix + 1, iz + 1)]
	return n00.lerp(n10, tx).lerp(n01.lerp(n11, tx), tz).normalized()


func get_surface(x: float, z: float) -> int:
	var ix := clampi(int((x - origin.x) / SURF_CELL), 0, sw - 1)
	var iz := clampi(int((z - origin.y) / SURF_CELL), 0, sh - 1)
	return surfaces[iz * sw + ix]


func get_contact_height(x: float, z: float) -> float:
	var h := get_height(x, z)
	if pond != null and h < water_level and get_surface(x, z) == Surface.WATER:
		return water_level
	return h


func compute_normals() -> void:
	normals.resize(hw * hh)
	for iz in hh:
		for ix in hw:
			var dx := heights[_hidx(ix + 1, iz)] - heights[_hidx(ix - 1, iz)]
			var dz := heights[_hidx(ix, iz + 1)] - heights[_hidx(ix, iz - 1)]
			var sx := 2.0 if ix > 0 and ix < hw - 1 else 1.0
			var sz := 2.0 if iz > 0 and iz < hh - 1 else 1.0
			normals[iz * hw + ix] = Vector3(-dx / (sx * HEIGHT_CELL), 1.0, -dz / (sz * HEIGHT_CELL)).normalized()


## Slope (rise over run) at a point.
func slope_at(x: float, z: float) -> float:
	var n := get_normal(x, z)
	return Vector2(n.x, n.z).length() / maxf(n.y, 1e-3)


## Horizontal distance from a point to the pin.
func dist_to_pin(p: Vector3) -> float:
	return Vector2(p.x - pin.x, p.z - pin.z).length()


func green_firmness_label() -> String:
	if green_softness < 0.8:
		return "Firm"
	if green_softness > 1.1:
		return "Soft"
	return "Medium"
