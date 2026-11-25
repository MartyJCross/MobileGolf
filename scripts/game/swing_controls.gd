class_name SwingControls
extends RefCounted
## Maps touches in the swing panel onto the SwingModel, for each control
## scheme. Chosen in Settings; PULL_TAP is the default (best in
## tests/tools/experiment_controls.gd).
##
##   PULL_TAP   drag down to pull the club back (it follows your thumb; slide
##              back up to shorten), let go to swing, tap at the release mark.
##   ONE_TOUCH  drag down to pull back, push up to swing (keep your thumb
##              down), lift your thumb at the release mark.
##   HOLD_TAP   hold to swing back (longer = further), let go to swing, tap at
##              the release mark.
##   THREE_TAPS tap to start the backswing, tap at the top, tap at the green line.

enum Scheme { PULL_TAP, ONE_TOUCH, HOLD_TAP, THREE_TAPS }
enum { DOWN, MOVE, UP }

const NAMES := ["Pull & Tap", "One Touch", "Hold & Tap", "Three Taps"]
const DESCRIPTIONS := [
	"Drag down to pull the club back, let go to swing, tap as the hands cross the green line.",
	"Drag down to pull back, push up to swing, lift your thumb at the green line.",
	"Hold to swing back, let go to swing, tap as the hands cross the green line.",
	"Tap to start the backswing, tap at the top, tap at the green line.",
]
const PULL_RANGE := 0.42 # of the panel height for a full backswing
const PUSH_START := 0.035 # of the panel height pushed back up starts the downswing

var scheme: int = Scheme.PULL_TAP
var model: SwingModel
var panel_height := 600.0
var _start_y := 0.0
var _max_y := 0.0
var cancelled_hint := "" # shown when a gesture was cancelled


func _init(m: SwingModel = null) -> void:
	model = m


## Feed one touch event. Positions are in panel pixels (y grows downward).
func handle(kind: int, pos: Vector2) -> void:
	if model == null:
		return
	var st := model.state
	match scheme:
		Scheme.PULL_TAP:
			if kind == DOWN:
				if st == SwingModel.State.IDLE:
					_begin_pull(pos)
				elif st == SwingModel.State.DOWNSWING:
					model.release_club()
			elif kind == MOVE and st == SwingModel.State.BACKSWING:
				model.set_backswing_target((pos.y - _start_y) / (PULL_RANGE * panel_height))
			elif kind == UP and st == SwingModel.State.BACKSWING:
				_go_down("Drag further down to swing")
		Scheme.ONE_TOUCH:
			if kind == DOWN and st == SwingModel.State.IDLE:
				_begin_pull(pos)
			elif kind == MOVE and st == SwingModel.State.BACKSWING:
				if pos.y > _max_y:
					_max_y = pos.y
				if _max_y - pos.y > PUSH_START * panel_height:
					_go_down("Drag further down before pushing up")
				else:
					model.set_backswing_target((_max_y - _start_y) / (PULL_RANGE * panel_height))
			elif kind == UP:
				if st == SwingModel.State.DOWNSWING:
					model.release_club()
				elif st == SwingModel.State.BACKSWING:
					model.reset() # lifted without pushing up: no swing
					cancelled_hint = "Push up to swing, then lift at the green line"
		Scheme.HOLD_TAP:
			if kind == DOWN:
				if st == SwingModel.State.IDLE:
					cancelled_hint = ""
					model.begin_backswing(true)
				elif st == SwingModel.State.DOWNSWING:
					model.release_club()
			elif kind == UP and st == SwingModel.State.BACKSWING:
				_go_down("Hold a little longer to swing")
		Scheme.THREE_TAPS:
			if kind == DOWN:
				if st == SwingModel.State.IDLE:
					cancelled_hint = ""
					model.begin_backswing(true)
				elif st == SwingModel.State.BACKSWING:
					_go_down("Let the club go back further before tapping")
				elif st == SwingModel.State.DOWNSWING:
					model.release_club()


func _begin_pull(pos: Vector2) -> void:
	cancelled_hint = ""
	_start_y = pos.y
	_max_y = pos.y
	model.begin_backswing(false)


func _go_down(hint_if_cancelled: String) -> void:
	if not model.start_downswing():
		cancelled_hint = hint_if_cancelled


## On-screen instruction for the current moment: [headline, detail].
func hint() -> Array:
	var st := model.state
	var bs := "Backswing %d%%" % roundi(model.backswing_fraction() * 100.0)
	if model.backswing_fraction() > 1.02:
		bs += " (over-swing!)"
	match scheme:
		Scheme.PULL_TAP:
			match st:
				SwingModel.State.IDLE:
					return ["Drag down to pull the club back", "Let go to swing · tap as the hands cross the green line"]
				SwingModel.State.BACKSWING:
					return [bs, "Let go to swing"]
				SwingModel.State.DOWNSWING:
					return ["Tap at the green line!", ""]
		Scheme.ONE_TOUCH:
			match st:
				SwingModel.State.IDLE:
					return ["Drag down to pull the club back", "Push up to swing · lift your thumb at the green line"]
				SwingModel.State.BACKSWING:
					return [bs, "Push up to swing"]
				SwingModel.State.DOWNSWING:
					return ["Lift at the green line!", ""]
		Scheme.HOLD_TAP:
			match st:
				SwingModel.State.IDLE:
					return ["Hold to swing back", "Let go to swing · tap as the hands cross the green line"]
				SwingModel.State.BACKSWING:
					return [bs, "Let go to swing"]
				SwingModel.State.DOWNSWING:
					return ["Tap at the green line!", ""]
		Scheme.THREE_TAPS:
			match st:
				SwingModel.State.IDLE:
					return ["Tap to start your backswing", "Tap at the top · tap as the hands cross the green line"]
				SwingModel.State.BACKSWING:
					return [bs, "Tap to swing down"]
				SwingModel.State.DOWNSWING:
					return ["Tap at the green line!", ""]
	return ["", ""]
