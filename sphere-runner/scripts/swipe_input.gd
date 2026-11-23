class_name SwipeInput
extends Node
## Turns touches (and mouse, which is emulated as touch) into swipe actions, taps and
## double-taps. Thumbs curve, so vertical swipes get the wider zone: a swipe only counts
## as sideways when it is within about 39 degrees of horizontal.

signal action(dir: String)     # "left", "right", "up", "down"
signal tapped
signal double_tapped

const SWIPE_MIN := 40.0          # pixels in the 720-wide base resolution
const SIDEWAYS_RATIO := 0.8
const TAP_MAX_MS := 300
const DOUBLE_TAP_MS := 450

var holding := false             # finger still down (used for float after a jump)
var _start := Vector2.ZERO
var _start_ms := 0
var _used := false
var _last_tap_ms := -10000


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			holding = true
			_used = false
			_start = event.position
			_start_ms = Time.get_ticks_msec()
		else:
			holding = false
			if not _used and Time.get_ticks_msec() - _start_ms < TAP_MAX_MS:
				var now := Time.get_ticks_msec()
				if now - _last_tap_ms < DOUBLE_TAP_MS:
					_last_tap_ms = -10000
					double_tapped.emit()
				else:
					_last_tap_ms = now
					tapped.emit()
	elif event is InputEventScreenDrag:
		if _used:
			return
		var d: Vector2 = event.position - _start
		if d.length() < SWIPE_MIN:
			return
		_used = true
		if absf(d.y) < absf(d.x) * SIDEWAYS_RATIO:
			action.emit("right" if d.x > 0 else "left")
		else:
			action.emit("down" if d.y > 0 else "up")
	elif event is InputEventKey and not event.echo:
		var map := {KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right",
			KEY_UP: "up", KEY_W: "up", KEY_SPACE: "up", KEY_DOWN: "down", KEY_S: "down"}
		if map.has(event.keycode):
			if map[event.keycode] == "up":
				holding = event.pressed
			if event.pressed:
				action.emit(map[event.keycode])
		elif event.pressed and event.keycode == KEY_ENTER:
			tapped.emit()
