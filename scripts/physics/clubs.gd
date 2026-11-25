class_name Clubs
extends RefCounted
## Club data.
##
## SET is what you play with: three wedges (50, 55, 60 degrees). Their stock
## numbers are typical tour-level wedge launch conditions; ball speed is set so
## the flight model carries each to a typical tour wedge distance.
##
## TOUR_IRONS are the widely published TrackMan PGA Tour averages for 3-iron
## to PW. They are not playable; the aerodynamic model is calibrated and
## tested against them (tests/calibrate.gd, tests/test_physics.gd).
## Imperial values are kept as published and converted on read.

const MPH := 0.44704
const YARD := 0.9144

const SET: Array[Dictionary] = [
	# ball_mph solved (tests/tools/probe_wedges.gd) for ~100 / 88 / 76 m carries.
	{"id": "50", "name": "50° Wedge", "loft": 50.0, "club_mph": 79.0, "aoa": -5.2, "ball_mph": 88.0, "launch": 26.5, "spin": 9600.0, "carry_yd": 109.0, "apex_yd": 27.0, "land": 50.0},
	{"id": "55", "name": "55° Wedge", "loft": 55.0, "club_mph": 73.0, "aoa": -5.5, "ball_mph": 81.1, "launch": 29.5, "spin": 10000.0, "carry_yd": 96.0, "apex_yd": 25.0, "land": 50.5},
	{"id": "60", "name": "60° Wedge", "loft": 60.0, "club_mph": 67.0, "aoa": -5.8, "ball_mph": 74.0, "launch": 32.5, "spin": 10300.0, "carry_yd": 83.0, "apex_yd": 23.0, "land": 51.0},
]

const TOUR_IRONS: Array[Dictionary] = [
	{"id": "3i", "name": "3 Iron", "loft": 21.0, "club_mph": 98.0, "aoa": -3.1, "ball_mph": 142.0, "launch": 10.4, "spin": 4630.0, "carry_yd": 212.0, "apex_yd": 27.0, "land": 46.0},
	{"id": "4i", "name": "4 Iron", "loft": 24.0, "club_mph": 96.0, "aoa": -3.4, "ball_mph": 137.0, "launch": 11.0, "spin": 4836.0, "carry_yd": 203.0, "apex_yd": 28.0, "land": 48.0},
	{"id": "5i", "name": "5 Iron", "loft": 27.0, "club_mph": 94.0, "aoa": -3.7, "ball_mph": 132.0, "launch": 12.1, "spin": 5361.0, "carry_yd": 194.0, "apex_yd": 31.0, "land": 49.0},
	{"id": "6i", "name": "6 Iron", "loft": 30.0, "club_mph": 92.0, "aoa": -4.1, "ball_mph": 127.0, "launch": 14.1, "spin": 6231.0, "carry_yd": 183.0, "apex_yd": 30.0, "land": 50.0},
	{"id": "7i", "name": "7 Iron", "loft": 34.0, "club_mph": 90.0, "aoa": -4.3, "ball_mph": 120.0, "launch": 16.3, "spin": 7097.0, "carry_yd": 172.0, "apex_yd": 32.0, "land": 50.0},
	{"id": "8i", "name": "8 Iron", "loft": 38.0, "club_mph": 87.0, "aoa": -4.5, "ball_mph": 115.0, "launch": 18.1, "spin": 7998.0, "carry_yd": 160.0, "apex_yd": 31.0, "land": 50.0},
	{"id": "9i", "name": "9 Iron", "loft": 42.0, "club_mph": 85.0, "aoa": -4.7, "ball_mph": 109.0, "launch": 20.4, "spin": 8647.0, "carry_yd": 148.0, "apex_yd": 30.0, "land": 51.0},
	{"id": "PW", "name": "Pitching Wedge", "loft": 46.0, "club_mph": 83.0, "aoa": -5.0, "ball_mph": 102.0, "launch": 24.2, "spin": 9304.0, "carry_yd": 136.0, "apex_yd": 29.0, "land": 52.0},
]


static func count() -> int:
	return SET.size()


static func get_club(index: int) -> Dictionary:
	return SET[clampi(index, 0, SET.size() - 1)]


## Any club by id, playable or tour reference (used by tests/tools).
static func find(id: String) -> Dictionary:
	for c in SET + TOUR_IRONS:
		if c["id"] == id:
			return c
	return {}


static func index_of(id: String) -> int:
	for i in SET.size():
		if SET[i]["id"] == id:
			return i
	return -1


## Stock carry in metres (published tour average).
static func stock_carry_m(club: Dictionary) -> float:
	return club["carry_yd"] * YARD


## Club whose stock carry is closest to (but preferably not short of) a distance.
static func suggest_for_distance(distance_m: float) -> int:
	var best := SET.size() - 1
	for i in range(SET.size() - 1, -1, -1):
		if stock_carry_m(SET[i]) >= distance_m - 3.0:
			return i
		best = i
	return best
