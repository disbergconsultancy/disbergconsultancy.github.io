class_name Tutorial
extends RefCounted
## The trial world: a short first run that teaches the moves. Before each new element the
## world freezes and a tip shows the gesture; doing it continues the run. Then a small
## training boss (with a pause at its first red marker) and a real planet hop into the
## first world. Mistakes do not end the trial: a hit just flashes "OOPS".

var g: Node                  # main.gd
var waiting := false
var need := ""               # lr | up | down | ability
var _steps: Array = []
var _i := -1
var _watch: Item             # the item that triggers the next freeze
var _trigger := 9.0
var _next_at := 0.0          # run distance at which the next step spawns its items
var _pending_tip := []       # tip to show when the freeze happens
var _marker_done := false


func _init(game: Node) -> void:
	g = game
	var ability: String = Config.char_def()["label"]
	_steps = [
		{"spawn": _wall, "trigger": 11.0, "need": "lr", "icon": "lr", "title": "SWIPE LEFT OR RIGHT", "text": "Change lanes to get past red walls"},
		{"spawn": _row.bind("LOW"), "trigger": 7.5, "need": "up", "icon": "up", "title": "SWIPE UP", "text": "Jump over orange crates"},
		{"spawn": _row.bind("HIGH"), "trigger": 7.5, "need": "down", "icon": "down", "title": "SWIPE DOWN", "text": "Slide under purple bars"},
		{"spawn": _row.bind("PIT"), "trigger": 6.5, "need": "up", "icon": "up", "title": "JUMP THE GLOW", "text": "Glowing floor burns: jump over it.\\nHold up to float further"},
		{"spawn": _goodies, "flash": "COINS AND POWER-UPS\nGRAB THEM!"},
		{"spawn": _full_meter, "trigger": 999.0, "need": "ability", "icon": "tap", "title": "DOUBLE-TAP",
			"text": "Your meter is full: use %s" % ability.to_lower().capitalize()},
	]


func begin() -> void:
	_next_at = g.dist + 22.0
	g.hud.flash("TRIAL WORLD")


## Called every step while the run is going (not while frozen).
func update() -> void:
	if waiting:
		return
	if _watch == null and g.dist >= _next_at and _i + 1 < _steps.size():
		_start(_i + 1)
	if _watch and _watch.alive and g._ahead_m(_watch) < _trigger:
		_freeze()
	# The training boss: pause once when its first red marker is close.
	if not _marker_done and g.boss.phase == "fight":
		for it in g.planet.items:
			if it.kind == "MARK" and it.alive and it.boss:
				var d: float = g._ahead_m(it)
				if d > 6.0 and d < 16.0:
					_marker_done = true
					_pending_tip = ["lr", "RED MARKER", "Something lands there:\\nchange lane!"]
					need = "lr"
					_freeze()
					break


func _start(i: int) -> void:
	_i = i
	var s: Dictionary = _steps[i]
	_watch = s["spawn"].call()
	if s.has("flash"):
		g.hud.flash(s["flash"])
		_next_at = g.dist + 45.0
		return
	_trigger = s["trigger"]
	need = s["need"]
	_pending_tip = [s["icon"], s["title"], s["text"]]
	if _watch == null:          # nothing to wait for: freeze at once (the ability step)
		_freeze()


func _freeze() -> void:
	waiting = true
	g.hud.show_tip(_pending_tip[0], _pending_tip[1], _pending_tip[2].replace("\\n", "\n"))
	g.sfx.play("ready")


## Is this the move the tip asks for?
func accepts(action: String) -> bool:
	if not waiting:
		return true
	return action == need or (need == "lr" and action in ["left", "right"])


func resume() -> void:
	waiting = false
	_watch = null
	g.hud.hide_tip()
	g.hud.pop("NICE!")
	_next_at = g.dist + 38.0


## Arrived in the first world: the trial is done.
func finish() -> void:
	Progress.tutorial_done = true
	Progress.save()
	g.hud.flash("WORLD 1\nMEADOW")


# --- What each step puts on the track --------------------------------------------

func _ahead(m: float) -> float:
	return g.angle + m / g.planet.radius


func _wall() -> Item:
	var it: Item = g.planet.add_item("WALL", _ahead(30.0), Config.lane_x(g.lane))
	for l in [-1, 0, 1]:
		if l != g.lane:
			for k in 3:
				g.planet.add_item("COIN", _ahead(26.0 + k * 1.6), Config.lane_x(l), {"y0": 0.4})
	return it


func _row(kind: String) -> Item:
	var first: Item
	for l in [-1, 0, 1]:
		var it: Item = g.planet.add_item(kind, _ahead(28.0), Config.lane_x(l))
		if l == 0:
			first = it
	return first


func _goodies() -> Item:
	for k in 8:
		g.planet.add_item("COIN", _ahead(14.0 + k * 1.8), Config.lane_x(g.lane), {"y0": 0.4})
	g.planet.add_item("POWER", _ahead(34.0), Config.lane_x(g.lane), {"power": "shield"})
	return null


func _full_meter() -> Item:
	g.meter = 1.0
	return null
