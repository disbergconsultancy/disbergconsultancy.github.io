extends Node3D
## Sphere Runner: game state, the run loop (movement, collisions, scoring), camera and HUD.
## The player stays on top of the globe; the globe rotates toward the camera.
##
## Headless self-test: godot --headless --path . -- --autotest

var planet: Planet
var spawner: Spawner
var character: BlockCharacter
var hitbox: MeshInstance3D
var camera: Camera3D
var hud: Hud
var swipe: SwipeInput

var state := "menu"            # menu | run | hit | over | paused
var angle := 0.0               # how far the globe has turned (radians)
var speed := 0.0
var dist := 0.0
var lap := 0
var lane := 0
var px := 0.0
var py := 0.0
var vy := 0.0
var grounded := true
var slide_t := 0.0
var jump_buffer_t := 0.0
var float_t := 0.0
var dash_t := 0.0
var hit_t := 0.0
var pts := 0.0
var coins := 0
var close_calls := 0
var combo := 0
var combo_t := 0.0
var combo_level := 1
var shake := 0.0
var squash := 0.0
var cam_x := 0.0
var cam_y := 0.0
var best := 0
var god := false               # test mode: no crashes
var sfx: Sfx
# Power-ups: remaining seconds (shield is a count)
var pw := {"magnet": 0.0, "shield": 0.0, "orbit": 0.0, "x2": 0.0, "invuln": 0.0}
var sky_coin_in := 0.0
var sky_wave := 0.0
# Character ability
var meter := 0.0
var ability_t := 0.0
var ability_total := 0.0
var super_active := false
var debris: Array = []
# Worlds, planet hop and boss
var boss: BossChase
var theme_idx := 0
var world_start := 0.0         # angle at which this planet's laps began
var world_lap := 0
var hop_t := 0.0
var hop_base := 0.0
var hop_swapped := false
var test_run := -1             # boss test: planet index (no scores saved), -1 = normal run
var st := {}                   # this run's stats: character base + learned skills (Progress.stats)
var air_jumps := 0
var hang_used := 0.0
var slip_t := 0.0
var smashes := 0
var stumbles_left := 0
var _sky_mat: ProceduralSkyMaterial
var _env: Environment         # [{ "node": MeshInstance3D, "v": Vector3, "life": float }]

var _test := {}                # autotest bookkeeping


func _ready() -> void:
	_build_environment()
	planet = Planet.new()
	add_child(planet)
	Config.THEME = Config.THEMES[0]
	planet.build(Config.THEME)
	boss = BossChase.new()
	boss.setup(self)
	spawner = Spawner.new(planet)
	character = BlockCharacter.new()
	add_child(character)
	hitbox = MeshInstance3D.new()
	hitbox.mesh = BoxMesh.new()
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0, 1, 0.65, 0.35)
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hitbox.material_override = wire
	hitbox.visible = false
	add_child(hitbox)
	swipe = SwipeInput.new()
	add_child(swipe)
	swipe.action.connect(_on_action)
	swipe.tapped.connect(_on_tap)
	swipe.double_tapped.connect(use_ability)
	sfx = Sfx.new()
	add_child(sfx)
	hud = Hud.new()
	add_child(hud)
	hud.play_pressed.connect(start_run)
	hud.again_pressed.connect(func(): start_boss_test(test_run) if test_run >= 0 else start_run())
	hud.boss_test.connect(start_boss_test)
	hud.menu_pressed.connect(_to_menu)
	hud.pause_pressed.connect(_toggle_pause)
	hud.character_changed.connect(func():
		character.build(Config.char_def())
		Progress.save()
		best = Progress.best_score()
		hud.show_menu(best))
	best = Progress.best_score()
	hud.progress_changed.connect(func():
		st = Progress.stats()
		best = Progress.best_score())
	reset()
	hud.show_menu(best)
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		_test = {"phase": "god", "kinds": {}, "frames": 0}
	elif "--shot" in args:
		# Screenshot: --shot <file.png> <seconds into an invincible run> [menu]
		var i := args.find("--shot")
		_test = {"phase": "shot", "path": args[i + 1], "t": float(args[i + 2]), "menu": "menu" in args, "done": false}
		for a in args:   # optional: char=<runner|smasher|jumper>  power=<magnet|shield|orbit|x2>  ability
			if a.begins_with("char="):
				Config.character = a.substr(5)
				character.build(Config.char_def())
			elif a.begins_with("power="):
				_test["power"] = a.substr(6)
			elif a == "ability":
				_test["ability"] = true
			elif a.begins_with("boss="):     # start a boss test on planet N instead of a normal run
				_test["boss"] = int(a.substr(5))
			elif a == "skills" or a == "shop" or a == "over":
				_test["screen"] = a


func _exit_tree() -> void:
	if is_instance_valid(boss) and not boss.is_inside_tree():
		boss.free()      # the boss node lives outside the tree between fights


func _build_environment() -> void:
	var th: Dictionary = Config.THEME
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = th["sky_top"]
	sm.sky_horizon_color = th["sky_bottom"]
	sm.ground_horizon_color = th["sky_bottom"]
	sm.ground_bottom_color = th["sky_bottom"]
	sky.sky_material = sm
	_sky_mat = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	# Light haze for depth; kept off the sky so colours stay saturated.
	env.fog_enabled = true
	env.fog_light_color = th["sky_bottom"]
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	_env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_WIDTH   # all lanes fit in portrait
	camera.fov = 62.0
	camera.far = 300.0
	add_child(camera)


## Switch to planet i: rebuild the globe, sky and haze.
func _set_planet(i: int) -> void:
	theme_idx = i
	Config.THEME = Config.THEMES[i]
	var th: Dictionary = Config.THEME
	planet.build(th)
	_sky_mat.sky_top_color = th["sky_top"]
	_sky_mat.sky_horizon_color = th["sky_bottom"]
	_sky_mat.ground_horizon_color = th["sky_bottom"]
	_sky_mat.ground_bottom_color = th["sky_bottom"]
	_env.fog_light_color = th["sky_bottom"]


## Begin this planet's laps (boss after `laps_to_boss` laps).
func _start_world() -> void:
	world_start = angle
	world_lap = 0
	spawner.reset(angle)
	spawner.stop_angle = angle + Config.THEME["laps_to_boss"] * TAU - 10.0 / planet.radius
	if Config.THEME["laps_to_boss"] <= 1:
		boss.start_intro()


# =====================================================================
# Run flow
# =====================================================================

func reset() -> void:
	boss.remove()
	boss.kills = 0
	planet.clear_items()
	hop_t = 0.0
	hud.fade.color.a = 0.0
	if theme_idx != 0:
		_set_planet(0)
	angle = 0.0
	planet.rotation.x = 0.0
	speed = Config.diff()["start"]
	dist = 0.0
	lap = 0
	lane = 0
	px = 0.0
	py = 0.0
	vy = 0.0
	grounded = true
	slide_t = 0.0
	jump_buffer_t = 0.0
	float_t = 0.0
	dash_t = 0.0
	pts = 0.0
	coins = 0
	close_calls = 0
	combo = 0
	combo_t = 0.0
	combo_level = 1
	shake = 0.0
	character.set_dead(false)
	character.set_glow(false)
	for k in pw:
		pw[k] = 0.0
	st = Progress.stats()
	air_jumps = 0
	hang_used = 0.0
	slip_t = 0.0
	smashes = 0
	stumbles_left = Progress.stumbles_per_run()
	meter = 0.0
	ability_t = 0.0
	ability_total = 0.0
	super_active = false
	for d in debris:
		d["node"].queue_free()
	debris.clear()
	spawner.speed = speed
	_start_world()
	spawner.update(angle)
	_update_hud()


func start_run() -> void:
	test_run = -1
	Progress.save()            # remembers character, difficulty and sound
	spawner.allow_powers = true
	sfx.enabled = Config.sound
	reset()
	state = "run"
	hud.show_run()
	hud.flash("GO!")


func _to_menu() -> void:
	state = "menu"
	spawner.allow_powers = false
	reset()
	hud.show_menu(best)


func _toggle_pause() -> void:
	if state == "run":
		state = "paused"
		hud.flash("PAUSED")
	elif state == "paused":
		state = "run"
		hud.flash("")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "run":
		_toggle_pause()


func score() -> int:
	return int(pts)


func crash(it: Item = null) -> void:
	if god or pw["invuln"] > 0.0:
		return
	if pw["shield"] > 0.0:
		pw["shield"] = 0.0
		pw["invuln"] = 1.0
		if it:
			planet.hide_item(it)
		shake = 0.35
		hud.flash("SHIELD!")
		sfx.play("shield")
		return
	# Stumble guard (core shop): a small hit knocks the obstacle over instead of ending the run.
	if stumbles_left > 0 and it and it.kind in ["LOW", "HIGH", "FIST", "SWEEPLOW", "SWEEPHIGH", "SHOCK"]:
		stumbles_left -= 1
		var lv: int = Progress.core["stumble"]
		planet.hide_item(it)
		_burst(it, Config.KIND[it.kind]["color"])
		combo = 0
		combo_t = 0.0
		combo_level = 1
		meter = meter * 0.5 if lv >= 2 else 0.0
		speed *= 0.88 if lv >= 2 else 0.8
		pw["invuln"] = 0.8
		squash = 1.0
		character.land_t = 0.16
		shake = 0.45
		hud.flash("STUMBLE!" + ("\n1 left" if stumbles_left > 0 else ""))
		sfx.play("smash")
		Input.vibrate_handheld(40)
		return
	state = "hit"
	sfx.play("crash")
	hit_t = Config.HIT_PAUSE
	shake = 0.5
	character.set_dead(true)
	Input.vibrate_handheld(80)


## Boss test: start on planet i's final lap, ~160 m before the chase, at mid-run speed.
func start_boss_test(i: int) -> void:
	start_run()
	test_run = i
	planet.clear_items()
	_set_planet(i)
	var d: Dictionary = Config.diff()
	speed = d["start"] + (d["max"] - d["start"]) * 0.4
	_start_world()
	world_lap = Config.THEME["laps_to_boss"] - 1
	world_start = angle - world_lap * TAU - (TAU - 160.0 / planet.radius)
	spawner.stop_angle = world_start + Config.THEME["laps_to_boss"] * TAU - 10.0 / planet.radius
	spawner.speed = speed
	spawner.spawned = 3
	spawner.update(angle)
	boss.start_intro()
	hud.flash("BOSS TEST")


func on_boss_defeated() -> void:
	boss.remove()
	start_hop()


func start_hop() -> void:
	hop_t = Config.HOP_TIME
	hop_swapped = false
	hop_base = py
	pw["orbit"] = 0.0
	slide_t = 0.0
	vy = 0.0
	pw["invuln"] = Config.HOP_TIME + 1.2
	hud.flash("PLANET HOP!")
	sfx.play("ability")


## Flip high into the air; at the top the screen flashes white and the next planet appears.
func _update_hop(dt: float) -> void:
	hop_t = maxf(0.0, hop_t - dt)
	var u := 1.0 - hop_t / Config.HOP_TIME
	py = sin(PI * u) * Config.HOP_H + (1.0 - u) * hop_base
	grounded = false
	hud.fade.color.a = maxf(0.0, 1.0 - absf(u - 0.5) * 5.0)
	if not hop_swapped and u >= 0.5:
		hop_swapped = true
		boss.remove()
		planet.clear_items()
		_set_planet((theme_idx + 1) % Config.THEMES.size())
		_start_world()
		hud.flash(Config.THEME["name"])
	if hop_t <= 0.0:
		hud.fade.color.a = 0.0
		py = maxf(py, 0.0)
		vy = -5.0


func _game_over() -> void:
	state = "over"
	if test_run >= 0:
		hud.show_over("Score %d · Coins %d\n%s" % [score(), coins,
			"%s DEFEATED" % Config.THEMES[test_run]["boss"]["name"] if boss.kills > 0
			else ("%d m left to pass it" % int(boss.dist - boss.done) if boss.phase == "fight" else "Chase not reached")], "Boss test (not saved)")
		return
	var s := score()
	var is_best := Progress.record_run(int(dist), s)
	best = Progress.best_score()
	var aw := Progress.award(Config.character, int(dist / 4.0) + coins * 2 + close_calls * 5 + smashes * 3 + boss.kills * 250)
	Progress.wallet += coins
	Progress.save()
	var p: Dictionary = Progress.prog[Config.character]
	var level_line := ""
	if aw["levels"] > 0:
		level_line = "\nLEVEL UP! " + ("+%d skill point%s" % [aw["points"], "" if aw["points"] == 1 else "s"] if aw["points"] > 0 else "(next point at the next level)")
	var xp_line := "Max level" if p["lvl"] >= Progress.MAX_LEVEL else "%d / %d XP" % [p["xp"], Progress.xp_for_next(p["lvl"])]
	hud.show_over("Score %d%s\nBest %d\nLaps %d · Coins %d\nDistance %d m · Close calls %d\nBosses defeated %d\n\n+%d XP · %s Lv %d (%s)%s\n+%d coins · wallet %d" % [
		s, "  NEW BEST!" if is_best else "", best, lap, coins, int(dist), close_calls, boss.kills,
		aw["xp"], Config.CHARS[Config.character]["name"], p["lvl"], xp_line, level_line, coins, Progress.wallet])


func _on_tap() -> void:
	if state == "paused":
		_toggle_pause()


func _on_action(dir: String) -> void:
	if state != "run":
		return
	match dir:
		"left", "right":
			var nl := clampi(lane + (-1 if dir == "left" else 1), -1, 1)
			if nl != lane:
				lane = nl
				if not grounded and pw["orbit"] <= 0.0:
					dash_t = 0.18   # air dash: faster lane switch in the air
					sfx.play("dash")
				else:
					sfx.play("swish")
		"up":
			if pw["orbit"] > 0.0:
				return
			if grounded:
				_jump()
			elif st["double_jump"] and air_jumps == 0 and not super_active:
				air_jumps = 1
				_jump()
			else:
				jump_buffer_t = Config.JUMP_BUFFER
		"down":
			if pw["orbit"] > 0.0:
				return
			slide_t = Config.SLIDE_TIME
			if not grounded:
				vy = Config.SLAM_V * st["slam_mul"]
			sfx.play("slide")


func _jump() -> void:
	slide_t = 0.0
	vy = st["jump_v"]
	sfx.play("jump")
	jump_buffer_t = 0.0
	grounded = false
	squash = -1.0
	float_t = 0.0


func _add_combo(n: int) -> void:
	var was := meter
	var gain: float = Config.METER_PER_CLOSE if n >= 3 else Config.METER_PER_COIN * n
	meter = minf(1.0, meter + gain * st["meter_mul"])
	if was < 1.0 and meter >= 1.0:
		hud.pop(Config.char_def()["label"] + " READY")
		sfx.play("ready")
	combo += n
	combo_t = st["combo_time"]
	var lv := _combo_mult()
	if lv > combo_level:
		combo_level = lv
		hud.pop("COMBO x%d" % lv)
		sfx.play("combo")


func _mult() -> int:
	return 2 if pw["x2"] > 0.0 else 1


# =====================================================================
# Power-ups and abilities
# =====================================================================

func activate(kind: String) -> void:
	sfx.play("power")
	hud.flash(Config.POWERS[kind]["label"])
	if kind == "shield":
		pw["shield"] = 1.0
	else:
		pw[kind] = Config.POWERS[kind]["time"] * Progress.dur_mul()
	if kind == "orbit":
		sky_coin_in = 0.0
		slide_t = 0.0
		pw["invuln"] = Config.POWERS["orbit"]["time"] * Progress.dur_mul() + 1.4


## Double-tap when the meter is full.
func use_ability() -> void:
	if state != "run" or meter < 1.0 or pw["orbit"] > 0.0 or ability_t > 0.0:
		return
	var d := Config.char_def()
	meter = 0.0
	sfx.play("ability")
	hud.flash(d["label"] + "!")
	if d["ability"] == "super":
		slide_t = 0.0
		vy = Config.SUPER_JUMP_V
		grounded = false
		float_t = 0.0
		squash = -1.0
		jump_buffer_t = 0.0
		super_active = true
		hang_used = 0.0
		ability_t = 1.6       # only for the glow
		ability_total = 1.6
	else:
		ability_t = st["ability_time"]
		ability_total = st["ability_time"]


func _smash(it: Item) -> void:
	planet.hide_item(it)
	_burst(it, Config.KIND[it.kind]["color"])
	shake = maxf(shake, 0.25)
	sfx.play("smash")
	smashes += 1
	var b: int = (Config.SMASH_POINTS + st["smash_pts"]) * _mult() * _combo_mult()
	pts += b
	_add_combo(2 + st["smash_combo"])
	if st["jackpot"]:
		coins += 3
		pts += 30 * st["coin_mul"] * _mult() * _combo_mult()
	# Each smash extends an active Smash a little, but never past ability_max.
	var smashing: bool = ability_t > 0.0 and Config.char_def()["ability"] == "smash"
	var add: float = clampf(st["ability_max"] - ability_total, 0.0, st["smash_extend"]) if smashing else 0.0
	ability_t += add
	ability_total += add
	hud.pop("SMASH +%d%s" % [b, ("  +%.1fs" % add) if add > 0.0 else ""])


## Debris: small cubes thrown up and back.
## Smash everything smashable within [from_m, to_m] metres ahead (Aftershock, Meteor).
func _blast(from_m: float, to_m: float, label: String) -> void:
	var n := 0
	for it in planet.items:
		var d := _ahead_m(it)
		if it.alive and it.kind in Config.SMASHABLE and d > from_m and d < to_m:
			_smash(it)
			n += 1
	shake = maxf(shake, 0.45)
	if n > 0:
		hud.flash(label)


func _burst(it: Item, color: Color) -> void:
	var origin: Vector3 = it.parts[0]["node"].global_position
	var m := planet.mat(color)
	for i in 10:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := randf_range(0.15, 0.4)
		bm.size = Vector3(sz, sz, sz)
		mi.mesh = bm
		mi.material_override = m
		add_child(mi)
		mi.global_position = origin + Vector3(randf_range(-0.6, 0.6), randf_range(0, 0.8), randf_range(-0.3, 0.3))
		debris.append({"node": mi, "v": Vector3(randf_range(-4, 4), randf_range(4, 11), randf_range(-2, 2)), "life": 0.9})


func _update_debris(dt: float) -> void:
	for i in range(debris.size() - 1, -1, -1):
		var d: Dictionary = debris[i]
		d["life"] -= dt
		d["v"].y -= 30.0 * dt
		var n: MeshInstance3D = d["node"]
		n.position += d["v"] * dt
		n.position.z += speed * dt if state == "run" else 0.0    # left behind as the world moves
		n.rotation += Vector3(8, 6, 0) * dt
		if d["life"] <= 0.0:
			n.queue_free()
			debris.remove_at(i)


func _combo_mult() -> int:
	return 1 + mini(st.get("combo_cap", 5) - 1, combo / st.get("combo_step", 10))


# =====================================================================
# Update
# =====================================================================

func _process(delta: float) -> void:
	if not _test.is_empty():
		_autotest_tick()
		return
	var dt := minf(delta, 0.05)
	var gdt := dt
	if state == "run" and ability_t > 0.0:
		ability_t = maxf(0.0, ability_t - dt)
		if Config.char_def()["ability"] == "focus":
			gdt = dt * st["focus_slow"]     # Focus slows the whole game down
		if ability_t == 0.0 and Config.char_def()["ability"] == "smash" and st["aftershock"]:
			_blast(-1.0, 10.0, "AFTERSHOCK!")   # when Smash ends, clear the next 10 m
	step(gdt)
	_update_debris(gdt)
	_render(dt)


func step(dt: float) -> void:
	if state == "hit":
		hit_t -= dt
		if hit_t <= 0.0:
			_game_over()
		return
	if state != "run":
		if state == "menu":
			angle += dt * 0.12        # idle spin behind the menu
			planet.rotation.x = fmod(angle, TAU)
			spawner.update(angle)
		return
	var d: Dictionary = Config.diff()
	speed = minf(d["max"], speed + d["accel"] * dt)
	angle += speed / planet.radius * dt
	dist += speed * dt
	pts += speed * dt * _mult()
	planet.rotation.x = fmod(angle, TAU)
	var wl := int((angle - world_start) / TAU)
	if wl > world_lap and hop_t <= 0.0:
		world_lap = wl
		lap += 1
		if world_lap == Config.THEME["laps_to_boss"]:
			boss.start_fight()                     # laps done: the chase starts
			sfx.play("ability")
		elif boss.phase == "none":
			speed = minf(d["max"], speed + Config.LAP_BONUS)
			if world_lap == Config.THEME["laps_to_boss"] - 1:
				boss.start_intro()                 # final lap: the boss shows up on the horizon
			else:
				hud.flash("LAP %d" % (world_lap + 1))
			sfx.play("lap")
	if hop_t > 0.0:
		_update_hop(dt)
	boss.update(dt)
	if combo_t > 0.0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			combo_level = 1
	if dash_t > 0.0:
		dash_t -= dt
	slip_t = maxf(0.0, slip_t - dt)
	for k in ["magnet", "orbit", "x2", "invuln"]:
		pw[k] = maxf(0.0, pw[k] - dt)
	# Orbit: a trail of sky coins to collect while flying high.
	if pw["orbit"] > 0.0:
		sky_coin_in -= speed * dt
		if sky_coin_in <= 0.0 and pw["orbit"] > 1.2:
			sky_coin_in = 2.2
			sky_wave += 0.35
			planet.add_item("COIN", angle + 26.0 / planet.radius, sin(sky_wave) * Config.LANE_W, {"y0": Config.ORBIT_H + 0.4})
	# Moving blocks
	var t := Time.get_ticks_msec() / 1000.0
	for it in planet.items:
		if it.move_amp > 0.0:
			it.x = it.cx + sin(t * it.move_speed + it.move_phase) * it.move_amp
			planet.place_item(it)
	_move_player(dt)
	spawner.speed = speed
	spawner.update(angle)
	_collide()
	_update_hud()


func _player_height() -> float:
	return Config.SLIDE_H if slide_t > 0.0 and grounded else Config.PLAYER_SIZE.y


## Highest surface under the player that they can stand on (ramps and long blocks).
func _surface_under_player() -> float:
	var g := 0.0
	for it in planet.items:
		if it.kind != "PLATFORM" and it.kind != "RAMP":
			continue
		var d := _ahead_m(it)
		if absf(d) > it.hd + 0.2 or absf(it.x - px) > it.hw + 0.2:
			continue
		var s := it.y1
		if it.kind == "RAMP":
			s = it.y1 * clampf((it.hd - d) / (2.0 * it.hd), 0.0, 1.0)
		if py >= s - Config.STEP_UP:
			g = maxf(g, s)
	return g


func _move_player(dt: float) -> void:
	if hop_t > 0.0:
		px = move_toward(px, lane * Config.LANE_W, Config.LANE_SPEED * dt)
		return
	px = move_toward(px, lane * Config.LANE_W, Config.LANE_SPEED * st["lane_mul"] * (1.2 if slip_t > 0.0 else 1.0) * (2.0 * st["air_dash_mul"] if dash_t > 0.0 else 1.0) * dt)
	if pw["orbit"] > 0.0:
		py += (Config.ORBIT_H - py) * minf(1.0, dt * 3.0)   # float high above the globe
		vy = 0.0
		grounded = false
		return
	var ground_y := _surface_under_player()
	if grounded and py < ground_y:
		py = ground_y             # walking up a ramp
	if py > ground_y + 0.001 or vy > 0.0:
		grounded = false
		var g := Config.GRAVITY
		# Holding the finger down after a jump floats a little near the top.
		if swipe.holding and vy < 3.0 and float_t < st["float_time"] and slide_t <= 0.0:
			g *= Config.FLOAT_GRAVITY
			float_t += dt
		if super_active and absf(vy) < 5.0 and hang_used < st["hang_time"]:
			g *= 0.12            # Hang Time: hover at the top of a super jump
			hang_used += dt
		vy -= g * dt
		py += vy * dt
		if py <= ground_y:
			var hard := vy < -12.0
			py = ground_y
			vy = 0.0
			grounded = true
			if hard:
				squash = 1.0
			air_jumps = 0
			if super_active:
				super_active = false
				if st["meteor"]:
					_blast(-1.0, 9.0, "METEOR!")   # landing from a super jump smashes what is just ahead
			character.land_t = 0.16
			if jump_buffer_t > 0.0:
				_jump()
	else:
		grounded = true
		py = ground_y
	if jump_buffer_t > 0.0:
		jump_buffer_t -= dt
	if slide_t > 0.0 and grounded:
		slide_t -= dt


## Metres ahead (+) or behind (-) of the player.
func _ahead_m(it: Item) -> float:
	return wrapf(it.phi - angle, -PI, PI) * planet.radius


func _collide() -> void:
	var ph := _player_height()
	var hw := Config.PLAYER_SIZE.x / 2.0 - Config.HIT_SHRINK
	var hd := Config.PLAYER_SIZE.z / 2.0 - Config.HIT_SHRINK
	for it in planet.items:
		if not it.alive:
			continue
		var d := _ahead_m(it)
		# Magnet pulls nearby coins in.
		var focus_field: bool = st["focus_magnet"] and ability_t > 0.0 and Config.char_def()["ability"] == "focus"
		if it.kind == "COIN" and (pw["magnet"] > 0.0 or focus_field) and d < 9.0 and d > -1.0 and absf(it.x - px) < 5.0:
			var k := minf(1.0, get_process_delta_time() * 10.0)
			it.x += (px - it.x) * k
			it.y0 += (py + 0.5 - it.y0) * k
			it.y1 = it.y0 + 0.45
			it.phi += (angle - it.phi) * k
			it.parts[0]["y"] = it.y0 + 0.225
			planet.place_item(it)
			d = _ahead_m(it)
		if it.kind == "MARK" or it.fly_t >= 0.0:
			continue
		var overlap_z := absf(d) <= it.hd + hd
		var overlap_x := absf(it.x - px) <= it.hw + hw
		# Close calls: clearing an obstacle by a small margin.
		if it.kind in Config.HAZARDS and not it.passed and it.kind != "PLATFORM" and it.kind != "PIT":
			if overlap_z:
				if not grounded and py >= it.y1 - 0.15 and absf(it.x - px) < it.hw + Config.PLAYER_SIZE.x / 2.0:
					it.set_meta("vaulted", true)
				var lat := absf(it.x - px) - (it.hw + Config.PLAYER_SIZE.x / 2.0)
				var above := py - it.y1
				var below := it.y0 - (py + ph)
				it.min_clear = minf(it.min_clear, maxf(lat, maxf(above, below)))
			elif d < -(it.hd + hd):
				it.passed = true
				# Vault (Jumper): jumping a boss throw or a crate fills the meter.
				if it.has_meta("vaulted"):
					var gain: float = st["vault_boss"] if it.boss else st["vault_crate"] if it.kind == "LOW" else 0.0
					if gain > 0.0:
						var was := meter
						meter = minf(1.0, meter + gain)
						if was < 1.0 and meter >= 1.0:
							hud.pop(Config.char_def()["label"] + " READY")
							sfx.play("ready")
				if it.min_clear < Config.NEAR_MISS and it.min_clear > -0.3 and pw["orbit"] <= 0.0:
					close_calls += 1
					var b: int = (25 + st["close_bonus"]) * _mult() * _combo_mult()
					pts += b
					_add_combo(3)
					hud.pop("CLOSE! +%d" % b)
					sfx.play("close")
					if st["updraft"] and not grounded:
						meter = minf(1.0, meter + 0.1)
					if st["slipstream"]:
						slip_t = 1.5
		if not overlap_z or not overlap_x:
			continue
		match it.kind:
			"RAMP":
				continue
			"PIT":
				# Glowing floor: deadly with your feet on it (thinner than the hitbox margin).
				if py <= 0.05 and pw["orbit"] <= 0.0:
					crash(it)
					if state != "run":
						return
				continue
			"PLATFORM":
				if py < it.y1 - Config.STEP_UP and pw["orbit"] <= 0.0:
					crash(it)
					if state != "run":
						return
				continue
		if py + ph - Config.HIT_SHRINK <= it.y0 or py + Config.HIT_SHRINK >= it.y1:
			continue
		if it.kind == "COIN":
			planet.hide_item(it)
			coins += 1
			pts += 10 * st["coin_mul"] * (1.0 if grounded else st["air_coin_mul"]) * _mult() * _combo_mult()
			_add_combo(1)
			sfx.play("coin")
		elif it.kind == "POWER":
			planet.hide_item(it)
			activate(it.power)
		elif pw["orbit"] <= 0.0:
			if ability_t > 0.0 and Config.char_def()["ability"] == "smash" and it.kind in Config.SMASHABLE:
				_smash(it)
				continue
			if st["ram"] and it.kind == "LOW" and slide_t > 0.0 and grounded:
				_smash(it)      # Battering Ram: sliding breaks crates
				continue
			crash(it)
			if state != "run":
				return


# =====================================================================
# Visuals
# =====================================================================

func _render(dt: float) -> void:
	var h := _player_height()
	squash *= pow(0.001, dt)
	var sq := 1.0 - 0.25 * squash if squash > 0.0 else 1.0 + 0.2 * -squash
	character.position = Vector3(px, planet.radius + py, 0.0)
	character.set_glow(state == "run" and ability_t > 0.0)
	# Blink while invulnerable after a shield hit or orbit.
	character.visible = not (pw["invuln"] > 0.0 and pw["invuln"] < 1.4 and int(Time.get_ticks_msec() / 80) % 2 == 0)
	character.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))
	character.update_pose(dt, state, {
		"grounded": grounded, "slide": slide_t, "vy": vy, "speed": speed,
		"hop": 1.0 - hop_t / Config.HOP_TIME if hop_t > 0.0 else -1.0, "orbit": pw["orbit"] > 0.0,
		"floating": swipe.holding and float_t > 0.0 and float_t < st["float_time"] and vy < 3.0,
		"lean": px - lane * Config.LANE_W, "twist": (lane * Config.LANE_W - px) if dash_t > 0.0 else 0.0})
	hitbox.scale = Vector3(Config.PLAYER_SIZE.x, h, Config.PLAYER_SIZE.z)
	hitbox.position = Vector3(px, planet.radius + py + h / 2.0, 0.0)
	for it in planet.items:
		for p in it.parts:
			if p.get("spin", false):
				p["node"].rotate_object_local(Vector3.UP, dt * 4.0)
	# Camera follows sideways and rises a little with jumps.
	cam_x += (px * 0.6 - cam_x) * minf(1.0, dt * 8.0)
	cam_y += ((py * 1.1 if pw["orbit"] > 0.0 or hop_t > 0.0 else py * 0.6) - cam_y) * minf(1.0, dt * 3.0)
	var off := Vector3.ZERO
	if shake > 0.0:
		shake = maxf(0.0, shake - dt)
		off = Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), 0.0) * shake
	var r := planet.radius
	camera.position = Vector3(cam_x, r + 4.0 + cam_y, 6.0 + cam_y * 0.9) + off
	camera.look_at(Vector3(cam_x, r - 1.5 + cam_y * 0.55, -12.0 - cam_y), Vector3.UP)


func _update_hud() -> void:
	hud.score_label.text = str(score())
	var where: String = "Boss chase" if boss.phase == "fight" or boss.phase == "down" else "Lap %d/%d" % [mini(world_lap + 1, Config.THEME["laps_to_boss"]), Config.THEME["laps_to_boss"]]
	hud.info_label.text = "Coins %d\n%s\n%d km/h\n%s" % [coins, where, int(speed * 3.6), Config.THEME["name"].capitalize()]
	match boss.phase:
		"intro":
			hud.set_boss(true, Config.THEME["boss"]["name"], 0.0, "waiting at the end of this lap")
		"fight":
			hud.set_boss(true, Config.THEME["boss"]["name"], boss.progress(), "%d m to pass it" % int(boss.dist - boss.done))
		"down":
			hud.set_boss(true, Config.THEME["boss"]["name"], 1.0, "DEFEATED")
		_:
			hud.set_boss(false)
	hud.combo_label.text = "COMBO x%d  (%d)" % [_combo_mult(), combo] if combo >= 3 else ""
	var list: Array[String] = []
	for k in ["magnet", "orbit", "x2"]:
		if pw[k] > 0.0:
			list.append("%s %d" % [Config.POWERS[k]["label"], ceili(pw[k])])
	if pw["shield"] > 0.0:
		list.append("SHIELD")
	if stumbles_left > 0:
		list.append("STUMBLE GUARD %d" % stumbles_left)
	hud.powers_label.text = "\n".join(list)
	if _mult() > 1:
		hud.score_label.text += "  x2"
	var cd := Config.char_def()
	var showing_ability: bool = ability_t > 0.0 and cd["ability_time"] > 0.0
	var frac: float = ability_t / st["ability_max"] if showing_ability else meter
	var text: String = cd["label"] if showing_ability else ("DOUBLE-TAP: " + cd["label"] if meter >= 1.0 else cd["label"])
	hud.set_meter(frac, cd["visor"], text, meter >= 1.0 and ability_t <= 0.0)


# =====================================================================
# Save
# =====================================================================




func _spawn_ahead(kind: String, m: float) -> Item:
	return planet.add_item(kind, angle + m / planet.radius, Config.lane_x(lane))


## Runs `seconds` of game time; Focus slows the game like the real frame loop does.
func _sim(seconds: float, dt: float) -> float:
	var peak := py
	for i in int(seconds / dt):
		var gdt := dt
		if ability_t > 0.0:
			ability_t = maxf(0.0, ability_t - dt)
			if Config.char_def()["ability"] == "focus":
				gdt = dt * st["focus_slow"]
		step(gdt)
		_update_debris(gdt)
		peak = maxf(peak, py)
	return peak


func _set_build(c: String, alloc: Dictionary) -> void:
	Config.character = c
	character.build(Config.char_def())
	Progress.prog[c] = {"lvl": 20, "xp": 0, "alloc": alloc}


func _autotest_phase4(dt: float) -> void:
	var saved := Progress.prog.duplicate(true)
	print("AUTOTEST levels: xp for level 2 = %d, level 20 total = %d, points at 8/9/10/20 = %d/%d/%d/%d" % [
		Progress.xp_for_next(1), range(1, 20).reduce(func(a, l): return a + Progress.xp_for_next(l), 0),
		Progress.points_at_level(8), Progress.points_at_level(9), Progress.points_at_level(10), Progress.points_at_level(20)])
	# Tier gate: a capstone needs 6 points in its branch.
	_set_build("runner", {})
	print("AUTOTEST capstone with 0 points in branch learnable: %s; after 3+2+1: %s" % [Progress.can_learn("runner", 1, 3),
		(func():
			Progress.prog["runner"]["alloc"] = {"quickfeet": 3, "aircontrol": 2, "spring": 1}
			return Progress.can_learn("runner", 1, 3)).call()])
	var s0 := Progress.stats("runner")
	print("AUTOTEST runner build stats: lane x%.2f, jump v %.1f, xp x%.2f" % [s0["lane_mul"], s0["jump_v"], s0["xp_mul"]])
	# Double jump (Jumper capstone)
	_set_build("jumper", {"springlegs": 3, "glider": 2, "quickland": 1, "djump": 1})
	god = true
	start_run()
	_sim(0.3, dt)
	_on_action("up")
	_sim(0.25, dt)
	_on_action("up")
	var peak := _sim(1.2, dt)
	print("AUTOTEST jumper double jump: air jumps %d, peak %.1f m" % [air_jumps if not grounded else 1, peak])
	# Meteor and Vault
	_set_build("jumper", {"windup": 3, "vault": 2, "hang": 1, "meteor": 1})
	start_run()
	_sim(0.3, dt)
	meter = 1.0
	use_ability()
	_sim(0.6, dt)
	_spawn_ahead("WALL", 9.0)
	var s_before := smashes
	_sim(2.5, dt)
	print("AUTOTEST jumper meteor: smashes on landing %d" % (smashes - s_before))
	meter = 0.0
	_sim(1.0, dt)
	var crate := _spawn_ahead("LOW", 12.0)
	while _ahead_m(crate) > 3.0:      # jump about 3 m before the crate
		_sim(dt, dt)
	_on_action("up")
	_sim(1.2, dt)
	print("AUTOTEST jumper vault over a crate: meter %.2f (expected ~0.06)" % meter)
	# Aftershock
	_set_build("smasher", {"fuel": 3, "wreck": 2, "overdrive": 1, "aftershock": 1})
	start_run()
	_sim(0.3, dt)
	meter = 1.0
	use_ability()
	while ability_t > 0.25:
		_sim(0.05, dt)
	_spawn_ahead("WALL", 6.0)
	s_before = smashes
	for i in 60:                 # frame loop path, where Aftershock fires
		var gdt := dt
		if ability_t > 0.0:
			ability_t = maxf(0.0, ability_t - dt)
			if ability_t == 0.0 and st["aftershock"]:
				_blast(-1.0, 10.0, "AFTERSHOCK!")
		step(gdt)
	print("AUTOTEST smasher aftershock: smashes when Smash ended %d" % (smashes - s_before))
	# Wrecking Ball in a boss chase
	start_boss_test(0)
	while boss.phase != "fight":
		step(dt)
	meter = 1.0
	use_ability()
	s_before = smashes
	var t := 0.0
	while t < 8.0 and smashes - s_before < 2:
		for it in planet.items:
			if it.fly_t >= 0.0 and it.kind == "FIST":
				lane = int(round(it.x / Config.LANE_W))
		step(dt)
		t += dt
	print("AUTOTEST smasher wrecking ball: throws shattered or smashed %d" % (smashes - s_before))
	# Stumble guard (core shop)
	var saved_core: Dictionary = Progress.core.duplicate()
	Progress.core["stumble"] = 3
	_set_build("runner", {})
	god = false
	start_run()
	var out := []
	for k in ["HIGH", "FIST", "LOW"]:
		if state != "run":
			out.append(k + ":over")
			continue
		_spawn_ahead(k, 6.0)
		_sim(1.0, dt)
		out.append("%s:%s/%d" % [k, state, stumbles_left])
	print("AUTOTEST stumble guard L3: ", "  ".join(out))
	# Game over: XP and coins saved
	_set_build("runner", {})
	Progress.core = saved_core
	var w0 := Progress.wallet
	god = true
	start_run()
	_sim(20.0, dt)
	god = false
	var c := coins
	_spawn_ahead("WALL", 5.0)
	_sim(1.5, dt)
	print("AUTOTEST game over: state %s, coins %d -> wallet +%d, runner level %d xp %d" % [state, c, Progress.wallet - w0, Progress.prog["runner"]["lvl"], Progress.prog["runner"]["xp"]])
	Progress.wallet = w0
	Progress.prog = saved
	Progress.save()
	Config.character = "runner"
	character.build(Config.char_def())


func _autotest_phase3(dt: float) -> void:
	# Long blocks must have their length (roof route).
	god = true
	start_run()
	var plat := planet.add_item("PLATFORM", angle + 30.0 / planet.radius, 0.0, {"depth": 18.0})
	print("AUTOTEST long block: depth %.1f m, %d segments" % [plat.hd * 2.0, plat.parts.size()])
	# A boss test per planet: the chase, throws, defeat and the hop to the next planet.
	for i in Config.THEMES.size():
		god = true
		start_boss_test(i)
		var kinds := {}
		var t := 0.0
		var fight_at := -1.0
		while t < 120.0:
			step(dt)
			_update_debris(dt)
			t += dt
			for it in planet.items:
				if it.boss:
					kinds[it.kind] = true
			if fight_at < 0.0 and boss.phase == "fight":
				fight_at = t
			if (theme_idx != i and hop_t <= 0.0) or state != "run":
				break
		print("AUTOTEST boss %s: chase began at %.1f s, finished at %.1f s, kills %d, now on %s | throws: %s" % [
			Config.THEMES[i]["boss"]["name"], fight_at, t, boss.kills, Config.THEME["name"], ", ".join(kinds.keys())])
	# A boss throw hits when it lands: god off, stand in a lane where a boulder lands.
	god = true                   # invincible during the run-up, then real collisions in the chase
	start_boss_test(0)
	var guard := 0
	while boss.phase != "fight" and guard < 60 * 60:
		step(dt)
		guard += 1
	god = false
	var t2 := 0.0
	while t2 < 30.0 and state == "run":
		for it in planet.items:     # steer into the next landed boulder
			if it.kind == "FIST" and it.fly_t < 0.0 and _ahead_m(it) > 0.0:
				lane = int(round(it.x / Config.LANE_W))
				break
		step(dt)
		t2 += dt
	print("AUTOTEST running into boss boulders: state %s after %.1f s of chase" % [state, t2])


func _autotest_phase2(dt: float) -> void:
	# Power-ups
	god = true
	start_run()
	_sim(0.5, dt)
	activate("magnet")
	var c0 := coins
	_sim(6.0, dt)
	print("AUTOTEST magnet: %.1f s left after 6 s, coins collected %d" % [pw["magnet"], coins - c0])
	activate("orbit")
	var peak := _sim(3.0, dt)
	print("AUTOTEST orbit: height %.1f m (target %.1f)" % [peak, Config.ORBIT_H])
	_sim(6.0, dt)
	print("AUTOTEST orbit ended: grounded %s, height %.2f" % [grounded, py])
	god = false
	pw["invuln"] = 0.0
	activate("shield")
	_spawn_ahead("WALL", 4.0)
	_sim(1.0, dt)
	print("AUTOTEST shield: state after hitting a wall = %s, shield left %d" % [state, int(pw["shield"])])
	# Abilities per character
	for c in Config.CHARS:
		Config.character = c
		character.build(Config.char_def())
		god = true
		start_run()
		_sim(0.5, dt)
		meter = 1.0
		use_ability()
		var report := ""
		if c == "runner":
			var d0 := dist
			_sim(1.0, dt)
			report = "focus active %.2f s left, distance in 1 s of real time %.1f m (normal %.1f m)" % [ability_t, dist - d0, speed]
		elif c == "smasher":
			god = false
			_spawn_ahead("WALL", 6.0)
			_spawn_ahead("LOW", 14.0)
			_sim(1.5, dt)
			report = "after running into a wall and a crate during Smash: state %s, Smash %.2f s left (extended to %.1f)" % [state, ability_t, ability_total]
		else:
			var p := _sim(2.0, dt)
			report = "super jump peak %.1f m (normal jump ~%.1f m)" % [p, pow(st["jump_v"], 2) / (2.0 * Config.GRAVITY)]
		print("AUTOTEST %s: %s" % [c, report])
	Config.character = "runner"
	character.build(Config.char_def())


# =====================================================================
# Headless self-test: simulates runs at a fixed time step and prints a report.
# =====================================================================

func _autotest_tick() -> void:
	var dt := 1.0 / 60.0
	if _test["phase"] == "shot":
		if _test["done"]:
			return
		_test["done"] = true
		if not _test["menu"]:
			god = true
			if _test.has("boss"):
				start_boss_test(_test["boss"])
			else:
				start_run()
			var n := int(_test["t"] * 60.0)
			for i in n:
				if i == n - 90:
					if _test.has("power"):
						activate(_test["power"])
					if _test.has("ability"):
						meter = 1.0
						use_ability()
				var gdt := dt
				if ability_t > 0.0:
					ability_t = maxf(0.0, ability_t - dt)
				step(gdt)
				_update_debris(gdt)
				_render(dt)
		else:
			for i in 30:
				step(dt)
				_render(dt)
			match _test.get("screen", ""):
				"skills":
					Progress.prog[Config.character]["lvl"] = 12
					Progress.prog[Config.character]["alloc"] = {"quickfeet": 3, "aircontrol": 2, "rhythm": 1}
					hud.open_skills("menu")
				"shop":
					Progress.wallet = 650
					Progress.core = {"luck": 1, "dur": 0, "stumble": 1}
					hud.open_shop("menu")
				"over":
					start_run()
					god = false
					for i in 600:
						step(dt)
						if state != "run":
							break
					for i in 30:
						step(dt)
					_render(dt)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_test["path"])
		print("AUTOTEST screenshot saved: ", _test["path"])
		get_tree().quit()
		return
	if _test["phase"] == "god":
		god = true
		start_run()
		var jumps := 0
		for i in 60 * 120:          # two minutes of play
			step(dt)
			_render(dt)
			for it in planet.items:
				_test["kinds"][it.kind] = true
			if i % 600 == 0:
				var ahead := 0
				for it in planet.items:
					if _ahead_m(it) > 0.0:
						ahead += 1
				print("AUTOTEST t=%ds items=%d ahead=%d next_spawn_ahead=%.1fm" % [i / 60, planet.items.size(), ahead, (spawner.next_spawn - angle) * planet.radius])
			if i % 90 == 0:
				_on_action(["left", "right", "up", "down"][i / 90 % 4])
				jumps += 1
		print("AUTOTEST god run: distance %d m, laps %d, speed %.1f m/s, coins %d, close calls %d, items on track %d" % [
			int(dist), lap, speed, coins, close_calls, planet.items.size()])
		print("AUTOTEST kinds seen: ", ", ".join(_test["kinds"].keys()))
		# Swipe input check
		var got := []
		swipe.action.connect(func(dir): got.append(dir))
		for deg in [0, 30, 45, 60, 90, 135, 180, 270]:
			var a := deg_to_rad(deg)
			var t0 := InputEventScreenTouch.new()
			t0.pressed = true
			t0.position = Vector2(360, 900)
			swipe._input(t0)
			var dr := InputEventScreenDrag.new()
			dr.position = t0.position + Vector2(cos(a), -sin(a)) * 80.0
			swipe._input(dr)
			var t1 := InputEventScreenTouch.new()
			t1.pressed = false
			t1.position = dr.position
			swipe._input(t1)
		print("AUTOTEST swipes 0/30/45/60/90/135/180/270 deg -> ", got.slice(got.size() - 8))
		_test["phase"] = "phase2"
	elif _test["phase"] == "phase2":
		_autotest_phase2(dt)
		_test["phase"] = "phase3"
	elif _test["phase"] == "phase3":
		_autotest_phase3(dt)
		_test["phase"] = "phase4"
	elif _test["phase"] == "phase4":
		_autotest_phase4(dt)
		_test["phase"] = "real"
	elif _test["phase"] == "real":
		god = false
		start_run()
		var t := 0
		while state == "run" and t < 60 * 120:
			step(dt)
			t += 1
		print("AUTOTEST real run (no input): state %s after %.1f s, distance %d m" % [state, t / 60.0, int(dist)])
		get_tree().quit()
