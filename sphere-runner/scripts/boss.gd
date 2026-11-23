class_name BossChase
extends Node3D
## The boss at the end of every world. It appears on the horizon at the start of the
## final lap; when the laps are done the chase starts: it backs away while throwing
## things onto red markers, you slowly close the gap (fast in the last ~20%), and
## running underneath it defeats it. A hit still ends the run.
## Throws keep the colour code: red = switch lane, orange = jump, purple = slide.

var game: Node                 # main.gd (angle, speed, planet, hud, sfx, scoring)
var phase := "none"            # none | intro | fight | down
var dist := 0.0                # chase length (metres)
var done := 0.0                # metres covered in the chase
var kills := 0
var _attack_t := 0.0
var _stomp_t := 0.0
var _end_t := 0.0
var _wind_t := -1.0
var _flash_t := 0.0
var _body: Node3D
var _mats: Array[StandardMaterial3D] = []
var _rng := RandomNumberGenerator.new()


func setup(g: Node) -> void:
	game = g
	_rng.randomize()


func progress() -> float:
	return clampf(done / dist, 0.0, 1.0) if dist > 0.0 else 0.0


## Distance ahead of the runner: near the horizon for most of the chase, then you
## close the gap fast and run underneath it.
func ahead() -> float:
	var far := minf(0.85 * game.planet.radius, 42.0)
	if phase == "intro":
		return far
	return (far + Config.BOSS_SIZE) * (1.0 - pow(progress(), 5)) - Config.BOSS_SIZE


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_mats.clear()
	var b: Dictionary = Config.THEME["boss"]
	_body = Node3D.new()      # pivot at the ground: leans and hops happen here
	add_child(_body)
	var body_mat := _mat(b["body"], b["glow"] * 0.3)
	var s := Config.BOSS_SIZE
	_box(Vector3(s, s, s), body_mat, Vector3(0, Config.BOSS_LIFT + s / 2.0, 0))
	for sx in [-1.0, 1.0]:      # legs beside the track
		_box(Vector3(2.4, Config.BOSS_LIFT + 0.5, 3.2), body_mat, Vector3(sx * (Config.TRACK_HALF + 1.7), (Config.BOSS_LIFT + 0.5) / 2.0, 0))
	var eye := _mat(b["eye"], 1.0)
	for sx in [-1.0, 1.0]:      # eyes on the face toward the runner (+Z)
		_box(Vector3(2.4, 1.5, 0.4), eye, Vector3(sx * 2.9, Config.BOSS_LIFT + s * 0.68, s / 2.0 + 0.1))


func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = glow
	m.set_meta("glow", glow)
	m.set_meta("color", c)
	_mats.append(m)
	return m


func _box(size: Vector3, m: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	_body.add_child(mi)


func remove() -> void:
	phase = "none"
	for c in get_children():
		c.queue_free()
	if get_parent():
		get_parent().remove_child(self)


func start_intro() -> void:
	if phase == "none":
		_build()
		game.planet.add_child(self)
	phase = "intro"
	game.hud.flash("FINAL LAP\n%s AHEAD" % Config.THEME["boss"]["name"])


func start_fight() -> void:
	if phase == "none":
		_build()
		game.planet.add_child(self)
	phase = "fight"
	dist = Config.THEME["boss_loops"] * Config.BOSS_LOOP_M
	done = 0.0
	_attack_t = 0.4
	_stomp_t = 0.0
	game.hud.flash("CATCH THE\n%s" % Config.THEME["boss"]["name"])


func _defeat() -> void:
	phase = "down"
	_end_t = 1.6
	kills += 1
	var bonus: int = 500 * game._mult()
	game.pts += bonus
	game.hud.flash("%s\nDEFEATED!" % Config.THEME["boss"]["name"])
	game.hud.pop("+%d" % bonus)
	game.sfx.play("ready")
	_flash_t = 0.5
	for it in game.planet.items:
		if it.boss:
			game.planet.hide_item(it)


## Called every game step while running.
func update(dt: float) -> void:
	if phase == "none":
		return
	var planet: Planet = game.planet
	if phase == "fight":
		done += game.speed * dt
		if done >= dist:
			_defeat()
		else:
			_schedule(dt)
	planet.place(self, game.angle + ahead() / planet.radius, 0.0, -0.4)
	# Flash white when defeated.
	_flash_t = maxf(0.0, _flash_t - dt)
	for m in _mats:
		m.emission = Color.WHITE if _flash_t > 0.0 else m.get_meta("color")
		m.emission_energy_multiplier = 0.8 if _flash_t > 0.0 else m.get_meta("glow")
	# Throw: lean back, then pitch forward toward the runner.
	if _wind_t >= 0.0:
		_wind_t += dt
		var u := _wind_t / 0.9
		_body.rotation.x = -0.2 * (u / 0.4) if u < 0.4 else (-0.2 + 0.5 * ((u - 0.4) / 0.15) if u < 0.55 else 0.3 * maxf(0.0, 1.0 - (u - 0.55) / 0.6))
		if u > 1.2:
			_wind_t = -1.0
			_body.rotation.x = 0.0
	if phase == "down":
		_end_t -= dt
		_body.position.y -= dt * 6.0
		_body.rotation.z += dt * 0.6
		if _end_t <= 0.0:
			game.on_boss_defeated()
	elif _stomp_t > 0.0:
		_body.position.y = -1.2 * (1.0 - (_stomp_t - 0.35) / 0.45) if _stomp_t > 0.35 else 3.5 * sin(PI * (0.35 - _stomp_t) / 0.35)
	else:
		_body.position.y = maxf(0.0, sin(Time.get_ticks_msec() / 1000.0 * 1.6)) * 0.4
	_update_throws(dt)


func _schedule(dt: float) -> void:
	var a := ahead()
	var planet: Planet = game.planet
	if _stomp_t > 0.0:     # stomp: crouch, hop, land -> a wave rolls toward the runner
		_stomp_t -= dt
		if _stomp_t <= 0.0 and a > 14.0:
			var w := planet.add_item("SHOCK", game.angle + (a - Config.BOSS_SIZE / 2.0) / planet.radius, 0.0, {"w": Config.TRACK_HALF * 2.0 - 0.4})
			w.vel = 9.0
			w.boss = true
			game.shake = maxf(game.shake, 0.3)
			game.sfx.play("smash")
	_attack_t -= dt
	if _attack_t > 0.0:
		return
	var bt: Dictionary = Config.THEME["boss"]
	# Land between the runner and the boss, as far ahead as possible (more warning).
	var target := minf(30.0 + game.st.get("throw_lead", 0.0), a - Config.BOSS_SIZE / 2.0 - 2.0)   # Read the Throw: further ahead
	var lvl := int(progress() * Config.THEME["boss_loops"])
	var last: bool = lvl >= Config.THEME["boss_loops"] - 1
	_attack_t = maxf(14.0, game.speed * (1.15 - 0.07 * lvl - (0.1 if last else 0.0)) * bt["gap_mul"]) / maxf(game.speed, 1.0)
	if target < 13.0:
		return              # about to pass it: no more throws
	# Each boss has its own mix of throws (the first boss never throws 2-lane walls).
	var throws: Dictionary = bt["throws"]
	var total := 0.0
	for v in throws.values():
		total += v
	var roll := _rng.randf() * total
	var kind := "smash"
	for k in throws:
		roll -= throws[k]
		if roll < 0.0:
			kind = k
			break
	if kind == "stomp" and (_stomp_t > 0.0 or a < 22.0):
		kind = "smash"
	if kind == "stomp":
		_stomp_t = 0.8
		return
	_throw(kind, game.angle + target / planet.radius)
	# Later in the chase: combos (a second throw right behind the first), if this boss does them.
	if lvl >= 1 and target > 20.0 and _rng.randf() < bt["combo"] * (1.6 if last else 1.0):
		_throw("smash" if throws["block"] == 0 or _rng.randf() < 0.5 else "block", game.angle + (target - 9.0) / planet.radius)


func _throw(kind: String, phi: float) -> void:
	var planet: Planet = game.planet
	var marks: Array = []
	var mark := func(lanes: Array) -> void:
		for l in lanes:
			marks.append(planet.add_item("MARK", phi, Config.lane_x(l), {"w": Config.LANE_W * 0.9}))
	var it: Item
	var free_lane := 0
	match kind:
		"smash":   # red boulder on one lane: switch lanes
			var l: int = [-1, 0, 1][_rng.randi() % 3]
			mark.call([l])
			it = planet.add_item("FIST", phi, Config.lane_x(l), {"w": 2.0})
			free_lane = ([-1, 0, 1].filter(func(x): return x != l)).pick_random()
		"block":   # red wall over two lanes: take the open one
			var open: int = [-1, 0, 1][_rng.randi() % 3]
			var lanes := [-1, 0, 1].filter(func(x): return x != open)
			mark.call(lanes)
			it = planet.add_item("BLOCK", phi, (Config.lane_x(lanes[0]) + Config.lane_x(lanes[1])) / 2.0, {"w": Config.LANE_W * 1.9})
			free_lane = open
		_:         # across the track: jump the log, slide under the bar
			mark.call([-1, 0, 1])
			it = planet.add_item("SWEEPLOW" if kind == "sweep_low" else "SWEEPHIGH", phi, 0.0, {"w": Config.TRACK_HALF * 2.0 - 0.4})
			free_lane = [-1, 0, 1][_rng.randi() % 3]
	it.boss = true
	it.fly_t = 0.0
	it.marks = marks
	for m in marks:
		m.boss = true
	if _rng.randf() < 0.6:     # coins in the safe lane keep the combo going
		var m := -3.0
		while m <= 3.0:
			planet.add_item("COIN", phi + m / planet.radius, Config.lane_x(free_lane), {"y0": 0.4})
			m += 1.6
	_wind_t = 0.0


## Throws fly in an arc from the boss onto their markers, then stay as obstacles.
## Stomp waves roll toward the runner.
func _update_throws(dt: float) -> void:
	var planet: Planet = game.planet
	for it in planet.items:
		if it.vel > 0.0:
			it.phi -= it.vel * dt / planet.radius
			planet.place_item(it)
		if it.fly_t < 0.0:
			continue
		it.fly_t = minf(it.fly_dur, it.fly_t + dt)
		var u := it.fly_t / it.fly_dur
		# Wrecking Ball (Smasher): during Smash, throws aimed at your lane shatter in mid-air.
		if game.st.get("wreck", false) and u > 0.35 and u < 1.0 and game.ability_t > 0.0 and Config.char_def()["ability"] == "smash" \
				and it.alive and absf(it.x - game.px) < it.hw + 0.6:
			it.fly_t = -1.0
			for m in it.marks:
				planet.hide_item(m)
			game._smash(it)
			game.hud.pop("WRECKED!")
			continue
		if u < 1.0 and phase != "none":
			var phi_b: float = game.angle + ahead() / planet.radius
			var y_b := Config.BOSS_LIFT + Config.BOSS_SIZE * 0.5
			for p in it.parts:
				var tphi: float = it.phi + p["dm"] / planet.radius
				var tx: float = it.x + p.get("dx", 0.0)
				planet.place(p["node"], lerpf(phi_b, tphi, u), lerpf(0.0, tx, u), lerpf(y_b, p["y"], u) + 8.0 * sin(PI * u))
				p["node"].rotate_object_local(Vector3.RIGHT, u * 5.0)
		else:
			it.fly_t = -1.0
			planet.place_item(it)
			for m in it.marks:
				planet.hide_item(m)
			game.shake = maxf(game.shake, 0.2)
			game.sfx.play("smash")
			if it.alive:
				game._burst(it, Color("9a8a7a"))


func is_flying(it: Item) -> bool:
	return it.fly_t >= 0.0
