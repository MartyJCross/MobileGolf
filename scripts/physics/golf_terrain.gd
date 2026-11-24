class_name GolfTerrain
extends RefCounted
## What the ball simulation needs to know about the world.
## This base class is flat ground of one surface with optional wind; the
## generated hole (HoleData) overrides the queries with real terrain.

var surface_type: int = Surface.FAIRWAY
var wind_10m: Vector3 = Vector3.ZERO # wind at 10 m height, m/s (horizontal)
var green_softness: float = 1.0 # scales the green crater depth: 0.6 firm .. 1.3 soft
var pin: Vector3 = Vector3(0, 0, -1.0e6)
var trees: Array = [] # Array of {"pos": Vector3 canopy centre, "r": canopy radius}
const WIND_Z0 := 0.03 # roughness length of mown grass, m


func get_height(_x: float, _z: float) -> float:
	return 0.0


func get_normal(_x: float, _z: float) -> Vector3:
	return Vector3.UP


func get_surface(_x: float, _z: float) -> int:
	return surface_type


func is_out_of_bounds(_x: float, _z: float) -> bool:
	return false


## Height of whatever the ball would land on (water surface for ponds).
func get_contact_height(x: float, z: float) -> float:
	return get_height(x, z)


## Wind speeds up with height (log wind profile), calm near the ground.
func wind_at(height_above_ground: float) -> Vector3:
	if wind_10m == Vector3.ZERO:
		return Vector3.ZERO
	var h := maxf(height_above_ground, WIND_Z0 * 1.5)
	var f := log(h / WIND_Z0) / log(10.0 / WIND_Z0)
	return wind_10m * clampf(f, 0.0, 1.4)


func surface_params(x: float, z: float) -> Dictionary:
	var s := get_surface(x, z)
	var p: Dictionary = Surface.params(s).duplicate()
	if s == Surface.GREEN or s == Surface.FRINGE:
		p["crater"] = p["crater"] * green_softness
	return p
