class_name Surface
extends RefCounted
## Playing surfaces and how the ball reacts to them.
##
## restitution_scale: multiplies the green's speed-dependent coefficient of
##     restitution (how much the ball bounces).
## friction: sliding friction at impact and while skidding.
## crater: how far the ball sinks in on landing. A deeper "crater" tilts the
##     effective surface back toward the ball, which is what lets a high-spin
##     wedge check or zip back on a soft green (Penner's model).
## roll: rolling resistance deceleration in m/s^2 (green ~ Stimp 11).
## spin_keep: how much spin survives landing in this surface (grass between
##     ball and ground in the rough kills it).

enum { TEE, FAIRWAY, ROUGH, FRINGE, GREEN, BUNKER, WATER }

const NAMES := {
	TEE: "Tee", FAIRWAY: "Fairway", ROUGH: "Rough", FRINGE: "Fringe",
	GREEN: "Green", BUNKER: "Bunker", WATER: "Water",
}

const PARAMS := {
	TEE: {"restitution_scale": 0.95, "friction": 0.40, "crater": 0.8, "roll": 1.0, "spin_keep": 1.0},
	FAIRWAY: {"restitution_scale": 0.95, "friction": 0.40, "crater": 0.8, "roll": 1.0, "spin_keep": 1.0},
	ROUGH: {"restitution_scale": 0.55, "friction": 0.55, "crater": 1.3, "roll": 3.5, "spin_keep": 0.35},
	FRINGE: {"restitution_scale": 0.95, "friction": 0.42, "crater": 0.9, "roll": 0.8, "spin_keep": 0.95},
	GREEN: {"restitution_scale": 1.0, "friction": 0.40, "crater": 1.0, "roll": 0.5, "spin_keep": 1.0},
	BUNKER: {"restitution_scale": 0.20, "friction": 0.80, "crater": 2.2, "roll": 9.0, "spin_keep": 0.2},
	WATER: {"restitution_scale": 0.0, "friction": 1.0, "crater": 0.0, "roll": 100.0, "spin_keep": 0.0},
}


static func params(surface: int) -> Dictionary:
	return PARAMS.get(surface, PARAMS[ROUGH])


static func name_of(surface: int) -> String:
	return NAMES.get(surface, "?")
