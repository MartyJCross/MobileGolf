class_name Stats
extends RefCounted
## Proximity stats, saved on the device.
## Water: scored as the distance from the pin to where the ball went in,
## plus a 10 m penalty (like dropping where it crossed and losing a shot).

const PATH := "user://stats.cfg"
const WATER_PENALTY := 10.0
const RECENT := 10

var shots := 0
var total := 0.0
var best := -1.0
var aces := 0
var greens_hit := 0
var recent: Array = []
var hole_number := 1
var base_seed := 0
var tempo := 0.55 # downswing slow-motion factor
var controls := 0 # SwingControls.Scheme
var show_mark := true # release mark assist


func load_stats() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		base_seed = randi()
		return
	shots = cfg.get_value("stats", "shots", 0)
	total = cfg.get_value("stats", "total", 0.0)
	best = cfg.get_value("stats", "best", -1.0)
	aces = cfg.get_value("stats", "aces", 0)
	greens_hit = cfg.get_value("stats", "greens_hit", 0)
	recent = cfg.get_value("stats", "recent", [])
	hole_number = cfg.get_value("game", "hole_number", 1)
	base_seed = cfg.get_value("game", "base_seed", randi())
	tempo = cfg.get_value("settings", "tempo", 0.55)
	controls = cfg.get_value("settings", "controls", 0)
	show_mark = cfg.get_value("settings", "show_mark", true)


func save_stats() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "shots", shots)
	cfg.set_value("stats", "total", total)
	cfg.set_value("stats", "best", best)
	cfg.set_value("stats", "aces", aces)
	cfg.set_value("stats", "greens_hit", greens_hit)
	cfg.set_value("stats", "recent", recent)
	cfg.set_value("game", "hole_number", hole_number)
	cfg.set_value("game", "base_seed", base_seed)
	cfg.set_value("settings", "tempo", tempo)
	cfg.set_value("settings", "controls", controls)
	cfg.set_value("settings", "show_mark", show_mark)
	cfg.save(PATH)


func reset() -> void:
	shots = 0
	total = 0.0
	best = -1.0
	aces = 0
	greens_hit = 0
	recent = []
	save_stats()


func record(proximity: float, on_green: bool, ace: bool) -> void:
	shots += 1
	total += proximity
	if best < 0.0 or proximity < best:
		best = proximity
	if ace:
		aces += 1
	if on_green:
		greens_hit += 1
	recent.append(proximity)
	while recent.size() > RECENT:
		recent.pop_front()
	save_stats()


func average() -> float:
	return total / shots if shots > 0 else 0.0


func recent_average() -> float:
	if recent.is_empty():
		return 0.0
	var s := 0.0
	for r in recent:
		s += r
	return s / recent.size()


func hole_seed(n: int) -> int:
	return hash([base_seed, n])
