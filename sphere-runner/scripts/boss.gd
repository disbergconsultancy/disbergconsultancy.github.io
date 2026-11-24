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
var _model: Node3D            # 3D boss model (or null: the block boss)
var _overlay := StandardMaterial3D.new()   # flash and enrage tint on the model
var _anim_t := 0.0
var _mats: Array[StandardMaterial3D] = []
var _rng := RandomNumberGenerator.new()
var _last_phase := 0
var _used := {}               # signature moves already announced this chase
var _pending: Array = []      # delayed steps of multi-part moves: [{ "t": seconds, "fn": Callable }]
var _gate: Array[Item] = []   # Gate slam legs on the track
var _gate_state := 0          # 0 open, 1 closed (gap shown), 2 gap shift announced, 3 shifted
var _gate_gap := 0
var _gate_mark: Item
var _last_item: Item          # the last thrown item (decoy)
var _jump_t := 0.0           # a "jump" attack (stomp, quake, low sweep) is still on its way
var _bb: BossBody             # block body (one look per archetype); null with a 3D model
var _pass_state := 0          # final pass: 0 not yet, 1 announced, 2 the boss blocks part of the track
var _pass_lane := 0
var _pass_items: Array[Item] = []
var _pass_marks: Array[Item] = []


func setup(g: Node) -> void:
	game = g
	_rng.randomize()


func progress() -> float:
	return clampf(done / dist, 0.0, 1.0) if dist > 0.0 else 0.0


## Distance ahead of the runner: near the horizon for most of the chase, then you
## close the gap fast and run underneath it.
func ahead() -> float:
	var far := _far()
	if phase == "intro":
		return far
	return (far + Config.BOSS_SIZE) * (1.0 - pow(progress(), 5)) - Config.BOSS_SIZE


func _far() -> float:
	return minf(0.85 * game.planet.radius, 42.0)


## Chase progress at which the final pass is announced (the boss is 24 m ahead, and past 60%).
func _pass_progress() -> float:
	var span := _far() + Config.BOSS_SIZE
	var p24 := pow(1.0 - (24.0 + Config.BOSS_SIZE) / span, 0.2) if span > 24.0 + Config.BOSS_SIZE else 0.0
	return maxf(0.6, p24)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_mats.clear()
	var b: Dictionary = Config.THEME["boss"]
	_body = Node3D.new()      # pivot at the ground: leans and hops happen here
	add_child(_body)
	_model = null
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(0, 0, 0, 0)
	_bb = null
	if Config.hero_models and b.has("model"):
		_build_model(b)
		return
	# Block body built from KayKit Block Bits textures, shaped by the archetype.
	_bb = BossBody.new()
	_body.add_child(_bb)
	_bb.build(b, _overlay, _mat(b["eye"], 1.0))


func arch() -> String:
	return Config.THEME["boss"].get("archetype", "gate_walker")


## A boss model (static mesh, animated in code): 1 m tall in the file, scaled to model_h,
## facing +Z (the runner). Tint for untextured models, glowing cracks for hot ones.
func _build_model(b: Dictionary) -> void:
	_model = load("res://assets/bosses/%s.glb" % b["model"]).instantiate()
	_model.scale = Vector3.ONE * b.get("model_h", 20.0)
	_model.position.y = b.get("hover", 0.0)
	_body.add_child(_model)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var src: BaseMaterial3D = mi.mesh.surface_get_material(0)
		var m: StandardMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
		if b.has("tint"):
			m.albedo_color = b["tint"]
			m.vertex_color_use_as_albedo = false
		m.roughness = 0.8
		if b["glow"] > 0.3 and m.albedo_texture:      # lava cracks glow
			m.emission_enabled = true
			m.emission_texture = m.albedo_texture
			m.emission = Color.WHITE
			m.emission_energy_multiplier = b["glow"] * 0.4
		mi.material_override = m
		mi.material_overlay = _overlay


## Model animation on top of the body moves (throw lean, stomp hop, defeat fall):
## breathing, a heavy waddle (or flapping for a flyer), squash on stomps, a red pulse
## when enraged, a white flash when defeated, and a leap over the runner at the final pass.
func _animate_model(dt: float) -> void:
	_anim_t += dt * (1.5 if boss_phase() == 3 and phase == "fight" else 1.0)
	var b: Dictionary = Config.THEME["boss"]
	var t := _anim_t
	var hover: float = b.get("hover", 0.0)
	var h: float = b.get("model_h", 20.0)
	var sx := 1.0
	var sy := 1.0 + 0.02 * sin(t * 2.2)                    # breathing
	if _stomp_t > 0.35:
		sy *= 0.88                                        # crouch before the stomp
		sx = 1.06
	elif _stomp_t > 0.0:
		sy *= 1.08                                        # stretch in the hop
		sx = 0.96
	_model.scale = Vector3(sx, sy, sx) * h
	if hover > 0.0:                                       # flyer: bob with the wing beat, pitch a little
		_model.position.y = hover + 0.9 * sin(t * 5.0)
		_model.rotation = Vector3(0.08 * sin(t * 5.0 + 1.0), 0.0, 0.06 * sin(t * 1.3))
	else:                                                 # walker: heavy waddle backwards
		_model.rotation = Vector3(0.0, 0.08 * sin(t * 1.6), 0.05 * sin(t * 3.2))
		var lift := 0.0
		if phase == "fight":                              # leap over the runner at the final pass
			var u := clampf((24.0 - ahead()) / 24.0, 0.0, 1.0)
			lift = h * 0.55 * sin(u * PI / 2.0)
		_model.position.y = absf(sin(t * 3.2)) * 0.5 + lift


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


func _block(name: String, size: Vector3, pos: Vector3) -> void:
	var n := Kit.node(name, size)
	n.position = pos
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = _overlay      # flash white when hit, pulse red when enraged
	_body.add_child(n)


func _box(size: Vector3, m: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.soft_box(size)
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
	game.hud.flash("FINAL LAP\nBOSS AHEAD")


func start_fight() -> void:
	if phase == "none":
		_build()
		game.planet.add_child(self)
	phase = "fight"
	dist = Config.THEME["boss_loops"] * Config.BOSS_LOOP_M
	done = 0.0
	_attack_t = 0.4
	_last_phase = 0
	_used = {}
	_pending.clear()
	_gate.clear()
	_gate_state = 0
	_pass_state = 0
	_jump_t = 0.0
	_pass_items.clear()
	_pass_marks.clear()
	_stomp_t = 0.0
	game.hud.flash("CATCH THE\nBOSS")


func _defeat() -> void:
	phase = "down"
	_end_t = 1.6
	kills += 1
	var bonus: int = 500 * game._mult()
	game.pts += bonus
	game.hud.flash("BOSS\nDEFEATED!")
	game.hud.pop("+%d" % bonus)
	game.sfx.play("defeat")
	_flash_t = 0.5
	game.character.event("cheer")
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
			for i in range(_pending.size() - 1, -1, -1):
				_pending[i]["t"] -= dt
				if _pending[i]["t"] <= 0.0:
					var step: Dictionary = _pending[i]
					_pending.remove_at(i)
					step["fn"].call()
			_update_pass()
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
		_body.position.y = 0.0
	if _bb:
		_bb.animate(dt, game.speed, phase == "fight" and boss_phase() == 3)
	if _model:
		_animate_model(dt)
	# White flash when defeated, red pulse when enraged.
	var c := Color(0, 0, 0, 0)
	if _flash_t > 0.0:
		c = Color(1, 1, 1, 0.7)
	elif phase == "fight" and boss_phase() == 3:
		c = Color(1, 0.15, 0.1, 0.12 + 0.1 * sin(Time.get_ticks_msec() / 1000.0 * 8.0))
	_overlay.albedo_color = c
	_update_throws(dt)


## Current phase: 1 = base throws, 2 = signature moves unlocked, 3 = enraged.
func boss_phase() -> int:
	var p := progress()
	return 3 if p >= Config.BOSS_PHASES[2] else 2 if p >= Config.BOSS_PHASES[1] else 1


## Picks the next move from this boss's base throws (+ signature moves from phase 2),
## and waits until it has earned enough threat budget for it.
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
			game.sfx.play("stomp")
	_attack_t -= dt
	_jump_t = maxf(0.0, _jump_t - dt)
	if _attack_t > 0.0:
		return
	var bt: Dictionary = Config.THEME["boss"]
	var ph := boss_phase()
	if ph != _last_phase:
		_last_phase = ph
		if ph == 3:
			game.hud.pop("ENRAGED!")
	# Land between the runner and the boss, as far ahead as possible (more warning).
	var target := minf(30.0 + game.st.get("throw_lead", 0.0), a - Config.BOSS_SIZE / 2.0 - 2.0)   # Read the Throw: further ahead
	if target < 13.0:
		_attack_t = 0.3
		return              # about to pass it: no more throws
	# One answer at a time: no new attacks in the ~3 s before a final pass that blocks the track.
	if arch() != "gate_walker" or bt["signature"].has("gate_slam"):
		if _pass_state > 0 or _gate_state > 0 or _pass_progress() - progress() < 3.0 * game.speed / dist:
			_attack_t = 0.3
			return
	var pool: Dictionary = bt["throws"].duplicate()
	if ph >= 2:
		pool.merge(bt["signature"])
		pool.erase("gate_slam")      # happens on its own at the final pass
	var kind := _pick(pool)
	if kind == "stomp" and (_stomp_t > 0.0 or a < 22.0):
		kind = "smash"
	if (kind == "rolling_boulder" and a < 30.0) or (kind == "ice_lane" and a < 38.0):
		kind = "smash"        # these need room between you and the boss
	if kind == "quake_rhythm" and (a < 22.0 or _stomp_t > 0.0 or _pending.size() > 0):
		kind = "smash"
	# One jump at a time: two jump attacks close together could land you on the second one.
	if kind in ["stomp", "sweep_low", "quake_rhythm"]:
		if _jump_t > 0.0:
			kind = "smash"
		else:
			_jump_t = 3.4 if kind == "quake_rhythm" else 2.4 if kind == "stomp" else 1.6
	# Threat budget: the move's cost sets how long until the next one (minimum ~14 m apart).
	var rate: float = bt["rate"] * (1.25 if ph == 3 else 1.1 if ph == 2 else 1.0)
	_attack_t = maxf(Config.BOSS_MOVES[kind]["cost"] / rate, 14.0 / maxf(game.speed, 1.0))
	# Fair-play: make the move, then check there is still a way through; if not, take it
	# back and try a single boulder instead (or nothing this time).
	for attempt in [kind, "smash"]:
		var before: int = game.planet.items.size()
		if not _do_move(attempt, a, target):
			_throw_with_combo(attempt, target, ph, bt)
		if path_ok():
			if _bb:
				_bb.on_attack()
			game.sfx.play("throw")
			var label: String = Config.BOSS_MOVES[attempt]["label"]
			if label != "" and not _used.has(attempt):
				_used[attempt] = true
				game.hud.flash(label + "!")    # announce a signature move the first time
			return
		_take_back(before)
	_attack_t = 0.3


## Forces one move right now (screenshots and tests).
func force_move(kind: String) -> void:
	var a := ahead()
	var target := minf(30.0, a - Config.BOSS_SIZE / 2.0 - 2.0)
	if kind == "gate_slam":
		return
	if not _do_move(kind, a, target):
		_throw(kind, game.angle + target / game.planet.radius)


## Runs a move that is not a plain throw. Returns false for plain throws.
func _do_move(kind: String, a: float, target: float) -> bool:
	match kind:
		"stomp":
			_stomp_t = 0.8
			return true
		"rolling_boulder":
			_rolling_boulder(a)
			return true
		"lava_trail":
			_lava_trail(target)
			return true
		"vine_sweep":
			_vine_sweep(target)
			return true
		"meteor_shower":
			_meteor_shower()
			_attack_t = maxf(_attack_t, 1.05 + 14.0 / maxf(game.speed, 1.0))   # the next move waits for the last meteor
			return true
		"ice_lane":
			_ice_lane()
			return true
		"quake_rhythm":
			for k in 3:           # three stomp waves in a beat: jump in rhythm
				_pending.append({"t": k * 0.75, "fn": func(): _stomp_t = 0.7})
			_attack_t = maxf(_attack_t, 3.2)   # one answer at a time: nothing else until the waves are past
			return true
		"decoy":
			_decoy(target)
			return true
	return false


func _throw_with_combo(kind: String, target: float, ph: int, bt: Dictionary) -> void:
	var planet: Planet = game.planet
	var safe := _throw(kind, game.angle + target / planet.radius)
	# Later phases: combos (a second throw right behind the first), if this boss does them.
	# Fair-play: the combo keeps the first throw's safe lane free, so one answer covers both.
	if ph >= 2 and target > 20.0 and _rng.randf() < bt["combo"] * (1.6 if ph == 3 else 1.0):
		var combo_kind := "smash" if bt["throws"]["block"] == 0 or _rng.randf() < 0.5 else "block"
		_throw(combo_kind, game.angle + (target - 9.0) / planet.radius, safe)


func _pick(pool: Dictionary) -> String:
	var total := 0.0
	for v in pool.values():
		total += v
	var roll := _rng.randf() * total
	for k in pool:
		roll -= pool[k]
		if roll < 0.0:
			return k
	return "smash"


# --- Signature moves ---------------------------------------------------

## Rolling boulder (Sand Wyvern): rolls toward you down one lane and switches to an
## adjacent lane once. Before the switch it wobbles and a red marker shows the new lane.
func _rolling_boulder(a: float) -> void:
	var planet: Planet = game.planet
	var lane: int = [-1, 0, 1][_rng.randi() % 3]
	var to: int = lane + (1 if lane == -1 else -1 if lane == 1 else [-1, 1][_rng.randi() % 2])
	var it := planet.add_item("ROLLER", game.angle + (a - Config.BOSS_SIZE / 2.0 - 1.0) / planet.radius, Config.lane_x(lane), {"w": 2.0})
	it.boss = true
	it.vel = 6.0                       # rolls toward the runner on top of the world's motion
	it.set_meta("to_x", Config.lane_x(to))
	it.set_meta("switch_at", 18.0)     # metres ahead of the runner where it changes lane
	it.set_meta("warn_at", 28.0)       # the warning starts here (~1 s before the switch)
	_wind_t = 0.0


## Lava trail (Magma Giant): a red stripe marks one lane for 20 m, then it turns to lava.
## Answer: stay out of that lane (or jump across where it ends).
func _lava_trail(target: float) -> void:
	var planet: Planet = game.planet
	var lane: int = [-1, 0, 1][_rng.randi() % 3]
	var start := maxf(14.0, target - 14.0)
	var it := planet.add_item("LAVA", game.angle + (start + 10.0) / planet.radius, Config.lane_x(lane))
	it.boss = true
	it.set_meta("arm_t", 0.9)          # warning time before it becomes deadly
	planet.set_lava_armed(it, false)
	_wind_t = 0.0


## Vine sweep (Minotaur): vines grow up over two lanes at slide height.
## Answer: slide under them, or take the third lane.
func _vine_sweep(target: float) -> void:
	var planet: Planet = game.planet
	var phi: float = game.angle + target / planet.radius
	var open: int = [-1, 0, 1][_rng.randi() % 3]
	var lanes := [-1, 0, 1].filter(func(x): return x != open)
	var parts: Array = []
	if open == 0:
		for l in lanes:
			parts.append([Config.lane_x(l), Config.LANE_W * 0.85])
	else:
		parts.append([(Config.lane_x(lanes[0]) + Config.lane_x(lanes[1])) / 2.0, Config.LANE_W * 1.9])
	for p in parts:
		var marks: Array = []
		for l in lanes:
			if absf(Config.lane_x(l) - p[0]) < p[1] / 2.0:
				var m := planet.add_item("MARK", phi, Config.lane_x(l), {"w": Config.LANE_W * 0.9})
				m.boss = true
				marks.append(m)
		var it := planet.add_item("VINE", phi, p[0], {"w": p[1]})
		it.boss = true
		it.marks = marks
		it.set_meta("arm_t", 0.8)        # grows for 0.8 s, then it is solid
		it.set_meta("grow", 0.8)
	_wind_t = 0.0


## Meteor shower (Sand Wyvern): four small meteors, thrown one after another every 0.35 s,
## never twice in a row in the same lane. Each has a normal throw's warning. Answer: weave.
func _meteor_shower() -> void:
	var lane: int = [-1, 0, 1][_rng.randi() % 3]
	for k in 4:
		_pending.append({"t": k * 0.35, "fn": _meteor.bind(lane)})
		lane = ([-1, 0, 1].filter(func(x): return x != lane)).pick_random()


func _meteor(lane: int) -> void:
	var planet: Planet = game.planet
	var target := minf(30.0, ahead() - Config.BOSS_SIZE / 2.0 - 2.0)
	if target < 13.0:
		return
	var phi: float = game.angle + target / planet.radius
	var before := planet.items.size()
	var m := planet.add_item("MARK", phi, Config.lane_x(lane), {"w": Config.LANE_W * 0.9})
	m.boss = true
	var it := planet.add_item("FIST", phi, Config.lane_x(lane), {"w": 1.6, "h": 1.8, "depth": 1.6})
	it.boss = true
	it.fly_t = 0.0
	it.fly_dur = 0.7
	it.marks = [m]
	it.set_meta("meteor", true)
	_wind_t = 0.0
	if not path_ok():
		_take_back(before)                   # this one would leave no way through: skip it


## Ice lane (Ice Titan): one lane freezes for 16 m with a boulder at its end; on ice a
## lane switch is a slow slide. Answer: leave that lane before the ice, or switch early.
func _ice_lane() -> void:
	var planet: Planet = game.planet
	var lane: int = [-1, 0, 1][_rng.randi() % 3]
	var start := 20.0
	var ice := planet.add_item("ICE", game.angle + (start + 8.0) / planet.radius, Config.lane_x(lane))
	ice.boss = true
	ice.set_meta("arm_t", 0.6)
	planet.set_ice_armed(ice, false)
	var end_phi: float = game.angle + (start + 17.5) / planet.radius
	var m := planet.add_item("MARK", end_phi, Config.lane_x(lane), {"w": Config.LANE_W * 0.9})
	m.boss = true
	var it := planet.add_item("FIST", end_phi, Config.lane_x(lane), {"w": 2.0})
	it.boss = true
	it.fly_t = 0.0
	it.marks = [m]
	_wind_t = 0.0


## Decoy (Ice Titan, Magma Giant): a boulder's marker jumps to a neighbouring lane
## halfway through the throw. Answer: watch the throw, not only the marker.
func _decoy(target: float) -> void:
	_throw("smash", game.angle + target / game.planet.radius, -2, false)
	var it := _last_item
	var lane := int(round(it.x / Config.LANE_W))
	var to: int = lane + (1 if lane == -1 else -1 if lane == 1 else [-1, 1][_rng.randi() % 2])
	# Never jump into the open lane of a wall nearby: that would leave no way through.
	it.set_meta("decoy_to", Config.lane_x(to))


## The final pass, by archetype (announced ~1.5 s ahead, then part of the track is blocked
## by the boss itself, following it): gate-walker: run underneath; flyer: it swoops low,
## slide under it; roller: it swerves into a side lane, overtake; burrower: it erupts in a
## lane; twins: they stomp into the outer lanes, pass between them. Gate slam (a signature
## move) replaces the pass of any archetype but the flyer.
func _update_pass() -> void:
	var b: Dictionary = Config.THEME["boss"]
	if b["signature"].has("gate_slam") and arch() != "flyer":
		_update_gate()
		return
	if arch() == "gate_walker":
		return
	var planet: Planet = game.planet
	var a := ahead()
	var phi: float = game.angle + a / planet.radius
	if _pass_state == 0 and progress() > 0.6 and a < 24.0 and a > 15.0:
		_pass_state = 1
		match arch():
			"flyer":    # the swoop spot stays put: you reach it at full speed, the flyer dives back to meet it
				_pass_items.append(planet.add_item("SWOOP", phi, 0.0, {"w": Config.TRACK_HALF * 2.0, "invisible": true}))
				for l in [-1, 0, 1]:
					_pass_marks.append(planet.add_item("MARK", phi - 3.0 / planet.radius, Config.lane_x(l), {"w": Config.LANE_W * 0.9, "tint": Color(0.85, 0.25, 0.8, 0.6)}))
				game.hud.flash("SWOOP!\nSLIDE UNDER IT")
				_pass_state = 2
			"roller", "burrower":
				_pass_lane = [-1, 1][_rng.randi() % 2] if arch() == "roller" else [-1, 0, 1][_rng.randi() % 3]
				_pass_marks.append(planet.add_item("MARK", phi, Config.lane_x(_pass_lane), {"w": Config.LANE_W * 0.9}))
				game.hud.flash("IT SWERVES!" if arch() == "roller" else "IT ERUPTS!")
			"twins":
				for l in [-1, 1]:
					_pass_marks.append(planet.add_item("MARK", phi, Config.lane_x(l), {"w": Config.LANE_W * 0.9}))
				_pass_marks.append(planet.add_item("MARK", phi, 0.0, {"w": Config.LANE_W * 0.9, "safe": true}))
				game.hud.flash("PASS BETWEEN!")
		for m in _pass_marks:
			m.boss = true
		if _bb:
			_bb.pass_lane = _pass_lane
		game.sfx.play("swish")
	elif _pass_state == 1 and a < 15.0:
		_pass_state = 2
		match arch():
			"roller", "burrower":
				_pass_items.append(planet.add_item("LEG", phi, Config.lane_x(_pass_lane), {"w": Config.LANE_W * 0.9, "invisible": true}))
			"twins":
				for l in [-1, 1]:
					_pass_items.append(planet.add_item("LEG", phi, Config.lane_x(l), {"w": Config.LANE_W * 0.9, "invisible": true}))
		for it in _pass_items:
			it.boss = true
		game.shake = maxf(game.shake, 0.4)
		game.sfx.play("smash")
	if _pass_state > 0 and arch() == "flyer":
		for it in _pass_items + _pass_marks:
			it.boss = true
			if it.alive and game._ahead_m(it) < -3.0:
				planet.hide_item(it)
		if _bb and not _pass_items.is_empty():
			var ia: float = game._ahead_m(_pass_items[0])
			_bb.swoop_z = ahead() - ia             # dive back toward the runner, to the swoop spot
			_bb.pass_u = clampf((24.0 - ia) / 14.0, 0.0, 1.0)
		return
	if _pass_state > 0:
		for it in _pass_items:
			if it.alive:
				it.phi = phi
				planet.place_item(it)
		for m in _pass_marks:
			if m.alive:
				m.phi = phi - 3.0 / planet.radius
				planet.place_item(m)
				if a < 2.0:
					planet.hide_item(m)
		if _bb:
			_bb.pass_u = clampf((24.0 - a) / 9.0, 0.0, 1.0)


## Gate slam (Magma Giant): when you reach the boss, its legs slam onto the track leaving
## one gap (marked green); the gap shifts once, announced by a new green marker.
func _update_gate() -> void:
	var planet: Planet = game.planet
	var a := ahead()
	var phi: float = game.angle + a / planet.radius
	if _gate_state == 0 and progress() > 0.6 and a < 22.0 and a > 15.0:
		_gate_state = 1
		_gate_gap = [-1, 0, 1][_rng.randi() % 3]
		_place_gate_legs()
		_gate_mark = planet.add_item("MARK", phi, Config.lane_x(_gate_gap), {"w": Config.LANE_W * 0.9, "safe": true})
		_gate_mark.boss = true
		game.hud.flash("GATE SLAM!")
		game.shake = maxf(game.shake, 0.4)
		game.sfx.play("smash")
	elif _gate_state == 1 and a < 15.0:
		_gate_state = 2                  # announce the shift ~1 s before it happens
		_gate_gap = _gate_gap + (1 if _gate_gap == -1 else -1 if _gate_gap == 1 else [-1, 1][_rng.randi() % 2])
		_gate_mark.x = Config.lane_x(_gate_gap)
		game.hud.pop("THE GAP MOVES!")
	elif _gate_state == 2 and a < 9.0:
		_gate_state = 3
		for it in _gate:
			planet.hide_item(it)
		_place_gate_legs()
		game.sfx.play("smash")
	if _gate_state > 0:
		for it in _gate:
			if it.alive:
				it.phi = phi
				planet.place_item(it)
		if _gate_mark and _gate_mark.alive:
			_gate_mark.phi = phi - 3.0 / planet.radius
			planet.place_item(_gate_mark)
			if a < 2.0:
				planet.hide_item(_gate_mark)


func _place_gate_legs() -> void:
	var planet: Planet = game.planet
	_gate.clear()
	for l in [-1, 0, 1]:
		if l != _gate_gap:
			var leg := planet.add_item("LEG", game.angle + ahead() / planet.radius, Config.lane_x(l))
			leg.boss = true
			_gate.append(leg)


func _update_signature(it: Item, dt: float) -> void:
	var planet: Planet = game.planet
	if it.kind == "ROLLER":
		var d: float = game._ahead_m(it)
		var to_x: float = it.get_meta("to_x")
		if d < it.get_meta("warn_at") and not it.has_meta("warned"):
			it.set_meta("warned", true)
			var m := planet.add_item("MARK", it.phi, to_x, {"w": Config.LANE_W * 0.9})
			m.boss = true
			m.vel = it.vel
			it.marks = [m]
		if d < it.get_meta("switch_at"):
			it.x = move_toward(it.x, to_x, 10.0 * dt)
			for m in it.marks:
				planet.hide_item(m)
		elif it.has_meta("warned"):
			it.x = it.cx + sin(Time.get_ticks_msec() / 40.0) * 0.15   # wobble before switching
		planet.place_item(it)
		for p in it.parts:   # roll
			p["node"].rotate_object_local(Vector3.RIGHT, -dt * (game.speed + it.vel) / 1.1)
	elif (it.kind == "VINE" or it.kind == "ICE") and it.has_meta("arm_t"):
		var t: float = it.get_meta("arm_t") - dt
		if it.kind == "VINE":            # grow out of the ground
			var g := 1.0 - maxf(t, 0.0) / float(it.get_meta("grow"))
			planet.place_item(it)
			for p in it.parts:
				p["node"].scale = Vector3(1, maxf(g, 0.05), 1)
		if t <= 0.0:
			it.remove_meta("arm_t")
			if it.kind == "ICE":
				planet.set_ice_armed(it, true)
			else:
				for m in it.marks:
					planet.hide_item(m)
		else:
			it.set_meta("arm_t", t)
	elif it.kind == "LAVA" and it.has_meta("arm_t"):
		var t: float = it.get_meta("arm_t") - dt
		if t <= 0.0:
			it.remove_meta("arm_t")
			planet.set_lava_armed(it, true)
			game.sfx.play("smash")
		else:
			it.set_meta("arm_t", t)


func is_armed(it: Item) -> bool:
	return not it.has_meta("arm_t")


## Throws one attack landing at phi. keep_free: a lane that must stay open (combos), -2 = any.
## Returns a lane that is safe from this throw.
func _throw(kind: String, phi: float, keep_free := -2, coins := true) -> int:
	var planet: Planet = game.planet
	var marks: Array = []
	var mark := func(lanes: Array) -> void:
		for l in lanes:
			marks.append(planet.add_item("MARK", phi, Config.lane_x(l), {"w": Config.LANE_W * 0.9}))
	var it: Item
	var free_lane := 0
	match kind:
		"smash":   # red boulder on one lane: switch lanes
			var l: int = ([-1, 0, 1].filter(func(x): return x != keep_free)).pick_random()
			mark.call([l])
			it = planet.add_item("FIST", phi, Config.lane_x(l), {"w": 2.0})
			free_lane = ([-1, 0, 1].filter(func(x): return x != l)).pick_random()
		"block":   # red wall over two lanes: take the open one
			var open: int = keep_free if keep_free != -2 else [-1, 0, 1][_rng.randi() % 3]
			var lanes := [-1, 0, 1].filter(func(x): return x != open)
			mark.call(lanes)
			free_lane = open
			if open == 0:
				# Middle lane open: two separate walls on the outer lanes (one wide wall would cover all three).
				var side := planet.add_item("BLOCK", phi, Config.lane_x(-1))
				side.boss = true
				side.fly_t = 0.0
				it = planet.add_item("BLOCK", phi, Config.lane_x(1))
			else:
				it = planet.add_item("BLOCK", phi, (Config.lane_x(lanes[0]) + Config.lane_x(lanes[1])) / 2.0, {"w": Config.LANE_W * 1.9})
		_:         # across the track: jump the log, slide under the bar
			mark.call([-1, 0, 1])
			it = planet.add_item("SWEEPLOW" if kind == "sweep_low" else "SWEEPHIGH", phi, 0.0, {"w": Config.TRACK_HALF * 2.0 - 0.4})
			free_lane = keep_free if keep_free != -2 else [-1, 0, 1][_rng.randi() % 3]
	it.boss = true
	it.fly_t = 0.0
	it.marks = marks
	_last_item = it
	for m in marks:
		m.boss = true
	if coins and _rng.randf() < 0.6:     # coins in the safe lane keep the combo going
		var m := -3.0
		while m <= 3.0:
			planet.add_item("COIN", phi + m / planet.radius, Config.lane_x(free_lane), {"y0": 0.4})
			m += 1.6
	_wind_t = 0.0
	return free_lane


## Removes items made since the item list had `count` entries (a move that was taken back).
func _take_back(count: int) -> void:
	var planet: Planet = game.planet
	while planet.items.size() > count:
		var it: Item = planet.items.pop_back()
		planet.remove_item(it)


## The general fairness check: is there still a way through everything on the track?
## Lanes are blocked (over a stretch of track) by lane-filling things; a lane switch
## takes a stretch of track too (longer on ice). Starting from the runner's lane, some
## lane must be reachable at the far end. Jump and slide hazards are answered in place
## and are kept apart by the "one jump at a time" rule.
func path_ok() -> bool:
	const STEP := 0.5
	const N := 140                                  # 70 m ahead
	var planet: Planet = game.planet
	var speed: float = maxf(game.speed, 1.0)
	var blocked := []                               # per slice: [lane -1, 0, 1] blocked?
	var icy := []
	for s in N:
		blocked.append([false, false, false])
		icy.append([false, false, false])
	var mark := func(d0: float, d1: float, x: float, hw: float, arr: Array) -> void:
		for s in range(maxi(0, int(d0 / STEP)), mini(N, int(ceil(d1 / STEP)) + 1)):
			for l in 3:
				if absf(x - Config.lane_x(l - 1)) < hw + Config.PLAYER_SIZE.x * 0.5:
					arr[s][l] = true
	for it in planet.items:
		if not it.alive:
			continue
		var d: float = game._ahead_m(it)
		if d + it.hd < -1.0 or d - it.hd > N * STEP:
			continue
		if it.kind == "ICE":
			mark.call(d - it.hd, d + it.hd, it.x, it.hw, icy)
			continue
		if not (it.kind in ["FIST", "BLOCK", "ROLLER", "LEG", "LAVA", "WALL", "MOVER"]):
			continue
		var xs := [it.x]                            # also where it is going
		if it.has_meta("decoy_to"):
			xs.append(it.get_meta("decoy_to"))
		if it.has_meta("to_x"):
			xs.append(it.get_meta("to_x"))
		if it.kind == "MOVER":
			xs = [-Config.LANE_W, 0.0, Config.LANE_W]
		var near := d - it.hd - 1.0
		if it.vel > 0.0:                            # rolling toward the runner: met sooner
			near = d * speed / (speed + it.vel) - it.hd - 1.0
		for x in xs:
			mark.call(near, d + it.hd + 1.0, x, it.hw, blocked)
	# Reachable lanes per slice, from the runner's lane now.
	var reach := []
	for s in N:
		reach.append([false, false, false])
	var start: int = clampi(game.lane, -1, 1) + 1
	if blocked[0][start]:
		return true                                 # already inside something: not this move's doing
	reach[0][start] = true
	var sw := int(ceil(speed * (Config.LANE_W / Config.LANE_SPEED + 0.15) / STEP))   # a switch, plus reaction
	var sw_ice := int(ceil(speed * 0.55 / STEP))
	for s in N - 1:
		for l in 3:
			if not reach[s][l]:
				continue
			if not blocked[s + 1][l]:
				reach[s + 1][l] = true
			for nl in [l - 1, l + 1]:
				if nl < 0 or nl > 2:
					continue
				var span: int = sw_ice if icy[s][l] else sw
				var ok := true
				for k in range(s, mini(N, s + span + 1)):
					if blocked[k][l] or blocked[k][nl]:
						ok = false
						break
				if ok and s + span < N:
					reach[s + span][nl] = true
	return reach[N - 1][0] or reach[N - 1][1] or reach[N - 1][2]


## Throws fly in an arc from the boss onto their markers, then stay as obstacles.
## Stomp waves roll toward the runner.
func _update_throws(dt: float) -> void:
	var planet: Planet = game.planet
	for it in planet.items:
		if it.vel > 0.0:
			it.phi -= it.vel * dt / planet.radius
			planet.place_item(it)
		if it.kind in ["ROLLER", "LAVA", "VINE", "ICE"]:
			if it.alive:
				_update_signature(it, dt)
			continue
		if it.fly_t < 0.0:
			continue
		it.fly_t = minf(it.fly_dur, it.fly_t + dt)
		if it.has_meta("decoy_to") and it.fly_t / it.fly_dur >= 0.55:
			it.x = it.get_meta("decoy_to")    # the marker jumps lanes mid-flight
			it.remove_meta("decoy_to")
			for m in it.marks:
				m.x = it.x
				planet.place_item(m)
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
			if not it.has_meta("origin"):     # where the throw leaves the boss (depends on its body)
				it.set_meta("origin", _bb.throw_origin() if _bb else Vector2(0.0, Config.BOSS_LIFT + Config.BOSS_SIZE * 0.5))
			var o: Vector2 = it.get_meta("origin")
			for p in it.parts:
				if p.get("shadow", false):     # the shadow appears when it lands
					continue
				var tphi: float = it.phi + p["dm"] / planet.radius
				var tx: float = it.x + p.get("dx", 0.0)
				planet.place(p["node"], lerpf(phi_b, tphi, u), lerpf(o.x, tx, u), lerpf(o.y, p["y"], u) + 8.0 * sin(PI * u))
				p["node"].rotate_object_local(Vector3.RIGHT, u * 5.0)
		else:
			it.fly_t = -1.0
			planet.place_item(it)
			for p in it.parts:
				if p.get("shadow", false):
					p["node"].visible = it.alive
			for m in it.marks:
				planet.hide_item(m)
			game.shake = maxf(game.shake, 0.2)
			game.sfx.play("smash")
			if it.alive:
				game._burst(it, Color("9a8a7a"))


func is_flying(it: Item) -> bool:
	return it.fly_t >= 0.0
