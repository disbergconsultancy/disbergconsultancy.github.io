extends Node3D
## Sphere Runner — concept prototype.
## The player stays in place on top of the globe; the globe rotates toward the
## camera. Obstacles live on the globe and are recycled once they pass behind.
## Everything is built in code from primitive shapes so there is nothing to
## set up in the editor. Tweak the constants below to test the feel.

# --- World ---------------------------------------------------------------
const TRACK_R := 30.0          # radius of the running surface (smaller = steeper curve, shorter laps)
const PLANET_R := 29.7         # radius of the globe under the track
const LANE_W := 2.2            # distance between lane centres
const LANE_COUNT := 3          # lanes are -1, 0, 1

# --- Player --------------------------------------------------------------
const PLAYER_SIZE := Vector3(0.9, 1.4, 0.9)
const SLIDE_H := 0.6           # player height while sliding
const SLIDE_TIME := 0.7
const GRAVITY := 45.0
const JUMP_V := 14.0           # peak height = JUMP_V^2 / (2 * GRAVITY) ~ 2.2 m
const SLAM_V := -25.0          # swipe down in the air drops you fast
const LANE_SPEED := 16.0       # m/s sideways while switching lanes
const HITBOX_SHRINK := 0.12    # a little forgiveness on collisions

# --- Pace ----------------------------------------------------------------
const START_SPEED := 12.0      # m/s along the surface
const MAX_SPEED := 32.0
const ACCEL := 0.3             # speed gained per second
const LAP_BONUS_SPEED := 1.5   # extra speed each completed lap
const SPAWN_AHEAD := 1.1       # radians ahead where new rows appear (beyond the horizon)
const DESPAWN_BEHIND := 0.3    # radians behind where objects are removed
const MIN_ROW_GAP := 9.0       # metres between obstacle rows

# --- Input ---------------------------------------------------------------
const SWIPE_MIN := 40.0        # pixels

enum State { READY, RUNNING, DEAD }
enum Kind { EMPTY, LOW, HIGH, WALL, COIN }

var state := State.READY
var angle := 0.0               # how far the globe has turned (radians, grows forever)
var speed := START_SPEED
var lane := 0
var player_x := 0.0
var player_y := 0.0            # height above the track
var vel_y := 0.0
var slide_timer := 0.0
var next_spawn := 0.0          # globe-local angle of the next obstacle row
var coins := 0
var lap := 0
var best := 0
var items: Array = []          # Array of Dictionary
var shake := 0.0
var flash_timer := 0.0
var dead_timer := 0.0

var touch_start := Vector2.ZERO
var touch_down := false
var swipe_used := false

var planet: Node3D
var player: MeshInstance3D
var camera: Camera3D
var score_label: Label
var info_label: Label
var center_label: Label
var flash_label: Label
var mats := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_best()
	_build_world()
	_build_ui()
	_reset()


# =========================================================================
# Building the scene
# =========================================================================

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		mats[key] = m
	return mats[key]


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	return mi


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)

	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH   # lanes always fit in portrait
	camera.fov = 70.0
	camera.far = 200.0
	add_child(camera)

	planet = Node3D.new()
	add_child(planet)

	# The globe.
	var globe := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = PLANET_R
	sm.height = PLANET_R * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	globe.mesh = sm
	globe.material_override = _mat(Color(0.35, 0.7, 0.4))
	planet.add_child(globe)

	# The track: a band (cylinder) wrapped around the globe's equator.
	var track := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = TRACK_R
	cm.bottom_radius = TRACK_R
	cm.height = LANE_W * LANE_COUNT + 0.4
	cm.radial_segments = 128
	cm.rings = 1
	track.mesh = cm
	track.material_override = _mat(Color(0.3, 0.3, 0.35))
	track.rotation.z = PI / 2.0   # cylinder axis along X
	planet.add_child(track)

	# Dashed lane markings so you can feel the speed.
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.1, 0.03, 1.2)
	var dash_count := int(TAU * TRACK_R / 3.0)
	for i in dash_count:
		var phi: float = TAU * float(i) / float(dash_count)
		for side in [-0.5, 0.5]:
			var d := MeshInstance3D.new()
			d.mesh = dash_mesh
			d.material_override = _mat(Color(0.95, 0.95, 0.95))
			planet.add_child(d)
			_place(d, phi, side * LANE_W, 0.0)

	# Scenery cubes scattered over the globe (fixed seed, so every lap looks the same).
	rng.seed = 7
	var deco_colors := [Color(0.25, 0.55, 0.3), Color(0.45, 0.8, 0.45), Color(0.6, 0.5, 0.35), Color(0.85, 0.85, 0.9)]
	var placed := 0
	while placed < 240:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if v.length() < 0.1 or v.length() > 1.0:
			continue
		v = v.normalized()
		if absf(v.x) < 0.2:
			continue   # keep the track clear
		var s := rng.randf_range(0.6, 2.4)
		var size := Vector3(s, s * rng.randf_range(0.8, 2.5), s)
		var cube := _box(size, deco_colors[rng.randi() % deco_colors.size()])
		var b := Basis(Quaternion(Vector3.UP, v))
		cube.transform = Transform3D(b, v * (PLANET_R + size.y * 0.5 - 0.15))
		planet.add_child(cube)
		placed += 1
	rng.randomize()

	player = _box(PLAYER_SIZE, Color(0.2, 0.5, 1.0))
	add_child(player)


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	score_label = _label(ui, 44, HORIZONTAL_ALIGNMENT_LEFT, VERTICAL_ALIGNMENT_TOP)
	info_label = _label(ui, 32, HORIZONTAL_ALIGNMENT_RIGHT, VERTICAL_ALIGNMENT_TOP)
	center_label = _label(ui, 40, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_CENTER)
	flash_label = _label(ui, 64, HORIZONTAL_ALIGNMENT_CENTER, VERTICAL_ALIGNMENT_TOP)
	flash_label.offset_top = 220


func _label(parent: Node, size: int, h: HorizontalAlignment, v: VerticalAlignment) -> Label:
	var l := Label.new()
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 28)
	l.horizontal_alignment = h
	l.vertical_alignment = v
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	return l


## Put a node on the track at globe-local angle phi, sideways offset x,
## with its centre y_center metres above the surface.
func _place(node: Node3D, phi: float, x: float, y_center: float) -> void:
	var b := Basis(Vector3.RIGHT, -phi)
	node.transform = Transform3D(b, b * Vector3(x, TRACK_R + y_center, 0.0))


# =========================================================================
# Obstacles and coins
# =========================================================================

func _add_item(kind: int, phi: float, x: float, size: Vector3, y0: float, color: Color) -> void:
	var pivot := Node3D.new()
	var mesh := _box(size, color)
	pivot.add_child(mesh)
	planet.add_child(pivot)
	_place(pivot, phi, x, y0 + size.y * 0.5)
	items.append({
		"node": pivot, "mesh": mesh, "kind": kind, "phi": phi, "x": x,
		"y0": y0, "y1": y0 + size.y,
		"half_w": size.x * 0.5, "half_d": size.z * 0.5, "alive": true,
	})


func _spawn_row(phi: float) -> void:
	var difficulty := clampf((speed - START_SPEED) / (MAX_SPEED - START_SPEED), 0.0, 1.0)
	var row := []
	for i in LANE_COUNT:
		var r := rng.randf()
		var empty_chance := 0.45 - 0.2 * difficulty
		if r < empty_chance:
			row.append(Kind.EMPTY)
		elif r < empty_chance + 0.2:
			row.append(Kind.LOW)
		elif r < empty_chance + 0.38:
			row.append(Kind.HIGH)
		else:
			row.append(Kind.WALL)
	# Never block every lane with walls.
	if not (Kind.EMPTY in row or Kind.LOW in row or Kind.HIGH in row):
		row[rng.randi() % LANE_COUNT] = Kind.EMPTY
	# Avoid fully empty rows most of the time.
	if row.count(Kind.EMPTY) == LANE_COUNT and rng.randf() < 0.7:
		row[rng.randi() % LANE_COUNT] = Kind.LOW if rng.randf() < 0.5 else Kind.HIGH

	var w := LANE_W * 0.85
	for i in LANE_COUNT:
		var x: float = (i - 1) * LANE_W
		match row[i]:
			Kind.LOW:
				_add_item(Kind.LOW, phi, x, Vector3(w, 1.0, 0.8), 0.0, Color(1.0, 0.55, 0.15))
			Kind.HIGH:
				_add_item(Kind.HIGH, phi, x, Vector3(w, 2.2, 0.8), 1.0, Color(0.85, 0.25, 0.8))
			Kind.WALL:
				_add_item(Kind.WALL, phi, x, Vector3(w, 3.5, 1.5), 0.0, Color(0.85, 0.2, 0.2))

	# A line of coins in one passable lane, shaped to reward the right move.
	var options := []
	for i in LANE_COUNT:
		if row[i] != Kind.WALL:
			options.append(i)
	if options.is_empty() or rng.randf() < 0.35:
		return
	var ci: int = options[rng.randi() % options.size()]
	var cx: float = (ci - 1) * LANE_W
	for k in 5:
		var d: float = (k - 2) * 1.6   # metres relative to the obstacle row
		var y := 0.4
		if row[ci] == Kind.LOW:
			y = 1.2 + 1.2 * (1.0 - pow(d / 4.0, 2))   # arc over the block
		elif row[ci] == Kind.HIGH:
			y = 0.1                                   # low, under the bar
		_add_item(Kind.COIN, phi + d / TRACK_R, cx, Vector3(0.45, 0.45, 0.45), y, Color(1.0, 0.85, 0.1))


func _update_spawning() -> void:
	while next_spawn < angle + SPAWN_AHEAD:
		_spawn_row(next_spawn)
		next_spawn += maxf(MIN_ROW_GAP, speed * 0.85) / TRACK_R
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		if it["phi"] - angle < -DESPAWN_BEHIND:
			it["node"].queue_free()
			items.remove_at(i)


# =========================================================================
# Game flow
# =========================================================================

func _reset() -> void:
	for it in items:
		it["node"].queue_free()
	items.clear()
	angle = 0.0
	speed = START_SPEED
	lane = 0
	player_x = 0.0
	player_y = 0.0
	vel_y = 0.0
	slide_timer = 0.0
	coins = 0
	lap = 0
	shake = 0.0
	next_spawn = 25.0 / TRACK_R   # first row 25 m ahead
	player.material_override = _mat(Color(0.2, 0.5, 1.0))
	planet.rotation.x = 0.0
	_update_spawning()
	state = State.READY
	center_label.text = "SPHERE RUNNER\n\nSwipe left / right: switch lane\nSwipe up: jump\nSwipe down: slide\n\nTap to start"
	_update_player_visual(0.0)
	_update_camera(1.0)
	_update_hud()


func _start() -> void:
	state = State.RUNNING
	center_label.text = ""


func _die() -> void:
	state = State.DEAD
	dead_timer = 0.6
	shake = 0.5
	player.material_override = _mat(Color(1.0, 0.15, 0.15))
	Input.vibrate_handheld(60)
	var score := _score()
	var new_best := score > best
	if new_best:
		best = score
		_save_best()
	center_label.text = "CRASHED\n\nScore %d%s\nBest %d\nLaps %d\n\nTap to restart" % [score, "  NEW BEST!" if new_best else "", best, lap]


func _score() -> int:
	return int(angle * TRACK_R) + coins * 10


func _flash(text: String) -> void:
	flash_label.text = text
	flash_timer = 1.2


# =========================================================================
# Frame update
# =========================================================================

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)

	if state == State.RUNNING:
		speed = minf(MAX_SPEED, speed + ACCEL * delta)
		angle += speed / TRACK_R * delta
		planet.rotation.x = fmod(angle, TAU)

		var new_lap := int(angle / TAU)
		if new_lap > lap:
			lap = new_lap
			speed = minf(MAX_SPEED, speed + LAP_BONUS_SPEED)
			_flash("LAP %d" % (lap + 1))

		_update_player(delta)
		_update_spawning()
		_check_collisions()
		_update_hud()
	elif state == State.DEAD:
		dead_timer -= delta

	for it in items:
		if it["kind"] == Kind.COIN:
			it["mesh"].rotation.y += delta * 4.0

	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0:
			flash_label.text = ""

	_update_player_visual(delta)
	_update_camera(delta)


func _update_player(delta: float) -> void:
	player_x = move_toward(player_x, lane * LANE_W, LANE_SPEED * delta)
	if player_y > 0.0 or vel_y > 0.0:
		vel_y -= GRAVITY * delta
		player_y += vel_y * delta
		if player_y <= 0.0:
			player_y = 0.0
			vel_y = 0.0
	if slide_timer > 0.0 and player_y <= 0.0:
		slide_timer -= delta


func _player_height() -> float:
	return SLIDE_H if (slide_timer > 0.0 and player_y <= 0.0) else PLAYER_SIZE.y


func _update_player_visual(_delta: float) -> void:
	var h := _player_height()
	player.scale = Vector3(1.0, h / PLAYER_SIZE.y, 1.0)
	player.position = Vector3(player_x, TRACK_R + player_y + h * 0.5, 0.0)
	player.rotation.z = (player_x - lane * LANE_W) * 0.15   # lean into lane changes


func _update_camera(delta: float) -> void:
	var cx := lerpf(camera.position.x, player_x * 0.6, minf(1.0, delta * 8.0))
	var offset := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - delta)
		offset = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * shake * 0.6
	camera.position = Vector3(cx, TRACK_R + 4.2, 7.5) + offset
	camera.look_at(Vector3(cx, TRACK_R + 0.5, -9.0))


func _check_collisions() -> void:
	var ph := _player_height()
	var px := PLAYER_SIZE.x * 0.5 - HITBOX_SHRINK
	var pz := PLAYER_SIZE.z * 0.5 - HITBOX_SHRINK
	for it in items:
		if not it["alive"]:
			continue
		var d: float = (it["phi"] - angle) * TRACK_R   # metres ahead (+) or behind (-)
		if absf(d) > it["half_d"] + pz:
			continue
		if absf(it["x"] - player_x) > it["half_w"] + px:
			continue
		if player_y + ph - HITBOX_SHRINK <= it["y0"] or player_y + HITBOX_SHRINK >= it["y1"]:
			continue
		if it["kind"] == Kind.COIN:
			it["alive"] = false
			it["node"].visible = false
			coins += 1
		else:
			_die()
			return


func _update_hud() -> void:
	score_label.text = "%d" % _score()
	info_label.text = "Coins %d\nLap %d\n%d km/h" % [coins, lap + 1, int(speed * 3.6)]


# =========================================================================
# Input: swipes on touch (mouse is emulated as touch), arrows / WASD on keyboard
# =========================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_down = true
			swipe_used = false
			touch_start = event.position
		else:
			if touch_down and not swipe_used:
				_on_tap()
			touch_down = false
	elif event is InputEventScreenDrag:
		if touch_down and not swipe_used:
			var delta: Vector2 = event.position - touch_start
			if delta.length() >= SWIPE_MIN:
				swipe_used = true
				if absf(delta.x) > absf(delta.y):
					_action("right" if delta.x > 0 else "left")
				else:
					_action("down" if delta.y > 0 else "up")
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_action("left")
			KEY_RIGHT, KEY_D:
				_action("right")
			KEY_UP, KEY_W:
				_action("up")
			KEY_DOWN, KEY_S:
				_action("down")
			KEY_SPACE, KEY_ENTER:
				if state == State.RUNNING:
					_action("up")
				else:
					_on_tap()


func _on_tap() -> void:
	if state == State.READY:
		_start()
	elif state == State.DEAD and dead_timer <= 0.0:
		_reset()


func _action(dir: String) -> void:
	if state == State.READY:
		_start()
	if state != State.RUNNING:
		return
	match dir:
		"left":
			lane = maxi(-1, lane - 1)
		"right":
			lane = mini(1, lane + 1)
		"up":
			if player_y <= 0.0:
				slide_timer = 0.0
				vel_y = JUMP_V
		"down":
			slide_timer = SLIDE_TIME
			if player_y > 0.0:
				vel_y = SLAM_V


# =========================================================================
# Best score
# =========================================================================

const SAVE_PATH := "user://best.cfg"

func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = int(cfg.get_value("score", "best", 0))


func _save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.save(SAVE_PATH)
