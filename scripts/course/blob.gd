class_name Blob
extends RefCounted
## An organic closed shape (green, bunker, pond): a rotated ellipse whose
## radius wobbles with a few random harmonics.

var center := Vector2.ZERO # world x, z
var radii := Vector2(10, 10) # half-width (local x), half-depth (local z)
var rotation := 0.0 # radians
var harmonics: Array = [] # [amplitude, frequency, phase]
var bbox := Rect2()


func _init(c := Vector2.ZERO, r := Vector2(10, 10), rot := 0.0, rng: RandomNumberGenerator = null, wobble := 0.08) -> void:
	center = c
	radii = r
	rotation = rot
	if rng != null:
		for k in [2, 3, 5]:
			harmonics.append([rng.randf_range(0.3, 1.0) * wobble, float(k), rng.randf_range(0.0, TAU)])
	var m := maxf(r.x, r.y) * (1.0 + wobble * 3.0)
	bbox = Rect2(c - Vector2(m, m), Vector2(m, m) * 2.0)


## < 1 inside, 1 on the edge, > 1 outside (roughly proportional to distance).
func norm_dist(p: Vector2) -> float:
	var d := (p - center).rotated(-rotation)
	var e := Vector2(d.x / radii.x, d.y / radii.y)
	var l := e.length()
	if l < 1e-6:
		return 0.0
	var ang := atan2(e.y, e.x)
	var scale := 1.0
	for h in harmonics:
		scale += h[0] * sin(h[1] * ang + h[2])
	return l / scale


## Approximate signed distance in metres (negative inside).
func signed_dist(p: Vector2) -> float:
	return (norm_dist(p) - 1.0) * mean_radius()


func mean_radius() -> float:
	return (radii.x + radii.y) * 0.5


func contains(p: Vector2, margin := 0.0) -> bool:
	if not bbox.grow(margin).has_point(p):
		return false
	return signed_dist(p) < margin


func overlaps(other: Blob, margin := 0.0) -> bool:
	var gap := center.distance_to(other.center) - maxf(radii.x, radii.y) * 1.25 - maxf(other.radii.x, other.radii.y) * 1.25
	return gap < margin
