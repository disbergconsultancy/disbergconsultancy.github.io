class_name HeroLab
extends Node
## Hero Lab (Settings): look at a hero's moves before they go into the game. Pick a hero and
## a move; play, pause, step a frame, slow it down; look from behind (as in a run), the side,
## the front or turning around; pixel look on or off. Moves loop. It drives the real hero
## with the same calls the game makes, on the real planet, so what you see is what runs.

const MOVES := [
	["run", "RUN"], ["jump", "JUMP"], ["flip", "AIR FLIP"], ["slide", "SLIDE"], ["lane", "LANE"],
	["stumble", "STUMBLE"], ["crash", "CRASH"], ["cheer", "CHEER"], ["float", "FLOAT"], ["idle", "IDLE"]]
const CAMS := ["behind", "side", "front", "turn"]
const SPEEDS := [1.0, 0.5, 0.25]

var g: Node                  # main.gd
var move := "run"
var cam := "behind"
var speed_i := 0
var paused := false
var pixel := true
var t := 0.0                 # time in the current loop
var turn := 0.0
var _ui: CanvasLayer
var _move_btns := {}
var _hero_label: Label
var _speed_btn: Button
var _play_btn: Button
var _cam_btn: Button
var _pix_btn: Button
var _vy := 0.0
var _py := 0.0
var _grounded := true
var _slide := 0.0
var _lane := 0


func _init(game: Node) -> void:
	g = game


func open() -> void:
	g.state = "lab"
	g.hud._menu.visible = false
	g.hud._run.visible = false
	g.hud._clear(g.hud._overlay)
	g.planet.clear_items()           # an empty road
	_build_ui()
	_restart()


func close() -> void:
	g._apply_pixel_world(true)
	_ui.queue_free()
	g.character.position = Vector3(0, g.planet.radius, 0)
	g.character.reset_anim()
	g.character.set_dead(false)
	g.lab = null
	g._to_menu()
	queue_free()


# --- Driving the hero --------------------------------------------------------------

func _restart() -> void:
	t = 0.0
	_vy = 0.0
	_py = 0.0
	_grounded = true
	_slide = 0.0
	g.character.reset_anim()
	g.character.set_dead(false)
	_select_buttons()


## One frame (dt: real seconds, already slowed down).
func tick(dt: float) -> void:
	var c: BlockCharacter = g.character
	var prev := t
	t += dt
	var run_speed := 14.0
	var state := "run"
	var s := {"grounded": true, "slide": 0.0, "vy": 0.0, "speed": run_speed, "hop": -1.0, "orbit": false,
		"floating": false, "skid": false, "lean": 0.0, "twist": 0.0}
	match move:
		"idle":
			state = "menu"
			s["speed"] = 0.0
		"jump", "flip", "float":
			var loop := 1.6 if move != "float" else 2.0
			if t >= loop:
				t -= loop
				prev = -1.0
			if prev < 0.35 and t >= 0.35:            # take off
				_vy = 14.0
				_grounded = false
				c.event("jump")
			if move == "flip" and prev < 0.6 and t >= 0.6:
				_vy = 12.0
				c.event("jump2")
			if not _grounded:
				var grav := 45.0 * (0.35 if move == "float" and _vy < 3.0 and t < 1.3 else 1.0)
				_vy -= grav * dt
				_py += _vy * dt
				if _py <= 0.0:
					_py = 0.0
					_grounded = true
					c.event("land", 1.0 if _vy < -18.0 else 0.0)
					_vy = 0.0
			s["grounded"] = _grounded
			s["vy"] = _vy
			s["floating"] = move == "float" and not _grounded and _vy < 3.0
		"slide":
			if t >= 1.6:
				t -= 1.6
				prev = -1.0
			if prev < 0.5 and t >= 0.5:
				c.event("slide")
			s["slide"] = 0.7 if t >= 0.5 and t < 1.2 else 0.0
		"lane":
			if t >= 0.9:
				t -= 0.9
				_lane = 1 - _lane
				c.event("lane", 1.0 if _lane == 1 else -1.0)
			s["lean"] = (0.5 - _lane) * 0.0
		"stumble":
			if t >= 1.8:
				t -= 1.8
				prev = -1.0
			if prev < 0.4 and t >= 0.4:
				c.event("stumble")
		"cheer":
			if t >= 2.0:
				t -= 2.0
				prev = -1.0
			if prev < 0.2 and t >= 0.2:
				c.event("cheer")
		"crash":
			if t >= 2.6:
				t -= 2.6
				prev = -1.0
				c.reset_anim()
				c.set_dead(false)
			if t >= 0.5:
				state = "hit"
				s["speed"] = 0.0
				if prev < 0.5:
					c.event("crash")
					c.set_dead(true)
	# the planet turns under the runner
	if state == "run":
		g.angle += dt * run_speed / g.planet.radius
		g.planet.rotation.x = fmod(g.angle, TAU)
	c.position = Vector3(0, g.planet.radius + _py, 0)
	c.update_pose(dt, state, s)
	_camera(dt)


func _camera(dt: float) -> void:
	var r: float = g.planet.radius
	var at := Vector3(0, r + 0.7 + _py * 0.6, 0)
	var eye: Vector3
	match cam:
		"behind":                       # a little closer than in a run
			eye = Vector3(0, r + 1.9 + _py * 0.6, 3.1)
		"side":
			eye = Vector3(3.2, r + 0.9 + _py * 0.6, 0)
		"front":
			eye = Vector3(0, r + 1.0 + _py * 0.6, -3.1)
		_:
			turn += dt * 0.6
			eye = Vector3(sin(turn) * 3.2, r + 1.1 + _py * 0.6, cos(turn) * 3.2)
	g.camera.position = eye
	g.camera.look_at(at, Vector3.UP)


# --- Screen -------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	# top: title, hero switcher, close
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var prev := UI.button("", "stone", 30, "left", 84)
	prev.custom_minimum_size.x = 84
	prev.pressed.connect(_hero.bind(-1))
	top.add_child(prev)
	var title := UI.panel("chip", 8)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_label = UI.label("", 34)
	_hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_child(_hero_label)
	top.add_child(title)
	var next := UI.button("", "stone", 30, "right", 84)
	next.custom_minimum_size.x = 84
	next.pressed.connect(_hero.bind(1))
	top.add_child(next)
	var done := UI.button("", "red", 30, "check", 84)
	done.custom_minimum_size.x = 84
	done.pressed.connect(close)
	top.add_child(done)
	root.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 24
	# bottom: moves (two rows) and the player controls
	var bottom := VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	for row in 2:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		for k in 5:
			var m: Array = MOVES[row * 5 + k]
			var b := UI.button(m[1], "stone", 20, "", 64)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func():
				move = m[0]
				_restart())
			_move_btns[m[0]] = b
			hb.add_child(b)
		bottom.add_child(hb)
	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 8)
	_play_btn = UI.button("", "green", 30, "pause", 80)
	_play_btn.custom_minimum_size.x = 96
	_play_btn.pressed.connect(func():
		paused = not paused
		_select_buttons())
	ctrl.add_child(_play_btn)
	var stepb := UI.button("+1", "stone", 24, "", 80)
	stepb.custom_minimum_size.x = 84
	stepb.pressed.connect(func():
		paused = true
		_select_buttons()
		tick(1.0 / 30.0))
	ctrl.add_child(stepb)
	_speed_btn = UI.button("SPEED 1x", "stone", 24, "", 80)
	_speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_btn.pressed.connect(func():
		speed_i = (speed_i + 1) % SPEEDS.size()
		_select_buttons())
	ctrl.add_child(_speed_btn)
	_cam_btn = UI.button("BEHIND", "stone", 24, "eye", 80)
	_cam_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cam_btn.pressed.connect(func():
		cam = CAMS[(CAMS.find(cam) + 1) % CAMS.size()]
		_select_buttons())
	ctrl.add_child(_cam_btn)
	_pix_btn = UI.button("PIXEL ON", "stone", 24, "", 80)
	_pix_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pix_btn.pressed.connect(func():
		pixel = not pixel
		g._apply_pixel_world(pixel)
		_select_buttons())
	ctrl.add_child(_pix_btn)
	bottom.add_child(ctrl)
	root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -250
	bottom.offset_bottom = -24


func _hero(step: int) -> void:
	var keys: Array = Config.CHARS.keys()
	Config.character = keys[posmod(keys.find(Config.character) + step, keys.size())]
	g._make_character()
	_restart()


func _select_buttons() -> void:
	if _ui == null:
		return
	_hero_label.text = "HERO LAB · " + Config.CHARS[Config.character]["name"].to_upper()
	for k in _move_btns:
		UI.style(_move_btns[k], "gold" if k == move else "stone")
	UI.set_text(_speed_btn, "SPEED %s" % ["1x", "½x", "¼x"][speed_i])
	UI.set_text(_cam_btn, cam.to_upper())
	UI.set_text(_pix_btn, "PIXEL ON" if pixel else "PIXEL OFF")
	var ic: TextureRect = _play_btn.get_meta("icon")
	ic.texture = UI.tex("icon_" + ("play" if paused else "pause"))


func speed() -> float:
	return 0.0 if paused else SPEEDS[speed_i]
