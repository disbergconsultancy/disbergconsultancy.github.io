class_name BlockCharacter
extends Node3D
## A block figure on a standard humanoid joint layout (hips, spine, head, arms,
## forearms, thighs, shins). It only *shows* the game state: gameplay never waits for
## an animation. Toon style: every joint follows its target pose on a spring (snappy,
## with a little overshoot), the head and forearms lag behind (follow-through), the body
## squashes and stretches, and short one-off moves (takeoff, flip, lane hop, stumble,
## crash, cheer) are layered on top. Swap it later for a rigged model with the same poses.

const KEYS := ["y", "rx", "ry", "rz", "spine", "spine_y", "head", "head_y", "arm_lx", "arm_lz", "arm_rx", "arm_rz",
	"fore_l", "fore_r", "thigh_lx", "thigh_lz", "thigh_rx", "thigh_rz", "shin_l", "shin_r"]
## Spring stiffness per joint (x the base). Lower = lags behind = follow-through.
const SOFT := {"head": 0.4, "head_y": 0.4, "fore_l": 0.5, "fore_r": 0.5, "arm_lz": 0.7, "arm_rz": 0.7, "spine_y": 0.7}
const BASE_K := 520.0       # spring stiffness
const ZETA := 0.5           # damping: < 1 overshoots a little, then settles
var hip_y := 0.66

var pivot := Node3D.new()      # at the hips: tilts, leans and flips rotate here
var j := {}                    # joints by name
var pose := {}                 # current pose
var vel := {}                  # spring velocity per joint
var run_phase := 0.0
var land_t := 0.0
var def := {}
var body_mat := StandardMaterial3D.new()
var limb_mat := StandardMaterial3D.new()
var accent_mat := StandardMaterial3D.new()
var head_mat := StandardMaterial3D.new()
var visor_mat := StandardMaterial3D.new()

# Squash and stretch: sq > 0 squashes (wide and low), sq < 0 stretches. A bouncy spring.
var sq := 0.0
var sq_v := 0.0
# One-off moves (seconds left, or progress for the flip / crash).
var takeoff_t := 0.0
var flip_t := -1.0
var lane_t := 0.0
var lane_dir := 0.0
var stumble_t := 0.0
var cheer_t := 0.0
var crash_t := -1.0
var dust_slide: CPUParticles3D
var dust_land: CPUParticles3D


func _ready() -> void:
	for k in KEYS:
		pose[k] = 0.0
	head_mat.albedo_color = Color("f0f0f5")
	visor_mat.emission_enabled = true
	visor_mat.emission_energy_multiplier = 0.4
	body_mat.emission_enabled = true
	body_mat.emission_energy_multiplier = 0.0
	for k in KEYS:
		vel[k] = 0.0
	add_child(pivot)
	dust_slide = _dust(false)
	dust_land = _dust(true)
	build(Config.char_def())


## Toon dust: little blocks that puff up and drift behind the runner.
func _dust(burst: bool) -> CPUParticles3D:
	var d := CPUParticles3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 0.14
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = m
	d.mesh = bm
	d.local_coords = false
	d.emitting = false
	d.amount = 16 if burst else 20
	d.lifetime = 0.45
	d.one_shot = burst
	d.explosiveness = 0.95 if burst else 0.0
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = Vector3(0.3, 0.02, 0.15)
	d.direction = Vector3(0, 0.5, 1) if not burst else Vector3(0, 0.35, 0.4)
	d.spread = 35.0 if not burst else 80.0
	d.initial_velocity_min = 2.0
	d.initial_velocity_max = 4.5
	d.gravity = Vector3(0, -5, 0)
	d.scale_amount_min = 0.6
	d.scale_amount_max = 1.3
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0.1))
	d.scale_amount_curve = c
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.97, 0.9, 0.9))
	g.set_color(1, Color(1, 0.97, 0.9, 0.0))
	d.color_ramp = g
	d.position = Vector3(0, 0.05, 0.1)
	add_child(d)
	return d


## Clears one-off moves and springs (new run, character change).
func reset_anim() -> void:
	sq = 0.0
	sq_v = 0.0
	takeoff_t = 0.0
	flip_t = -1.0
	lane_t = 0.0
	stumble_t = 0.0
	cheer_t = 0.0
	crash_t = -1.0
	for k in KEYS:
		vel[k] = 0.0
	scale = Vector3.ONE


## Squash (amount > 0) or stretch (amount < 0); the body springs back with a wobble.
func kick(amount: float) -> void:
	sq = clampf(amount * 0.3, -0.25, 0.38)
	sq_v = 0.0


## One-off moves, called by the game: jump, jump2 (air jump: front flip), land (arg 1 = hard),
## lane (arg = -1 left / 1 right), slide, stumble, crash, cheer.
func event(name: String, arg := 0.0) -> void:
	match name:
		"jump":
			takeoff_t = 0.14
			kick(-0.8)
		"jump2":
			flip_t = 0.0
			kick(-0.6)
		"land":
			land_t = 0.16
			kick(1.0 if arg > 0.0 else 0.45)
			dust_land.amount = 16 if arg > 0.0 else 8
			dust_land.restart()
		"lane":
			lane_t = 0.24
			lane_dir = arg
			kick(0.35)
		"slide":
			kick(0.7)
		"stumble":
			stumble_t = 0.55
			kick(1.0)
		"crash":
			crash_t = 0.0
			kick(1.3)
		"cheer":
			cheer_t = 1.1


## Same skeleton for every character type; only proportions and colours differ,
## so every pose works for all of them.
func build(d: Dictionary) -> void:
	def = d
	for c in pivot.get_children():
		c.queue_free()
	j.clear()
	set_dead(false)
	accent_mat.albedo_color = d["accent"]
	visor_mat.albedo_color = d["visor"]
	visor_mat.emission = d["visor"]
	var sh: Dictionary = d["shape"]
	var leg: float = sh["leg_len"]
	var tw: float = sh["torso_w"]
	var hs: float = sh["head"]
	hip_y = 0.07 + 0.59 * leg
	pivot.position.y = hip_y
	j["hips"] = _joint(pivot, Vector3.ZERO)
	_part(j["hips"], Vector3(0.42 * tw, 0.16, 0.26), limb_mat, Vector3.ZERO)
	j["spine"] = _joint(j["hips"], Vector3(0, 0.06, 0))
	_part(j["spine"], Vector3(0.5 * tw, 0.44, 0.28 * sqrt(tw)), body_mat, Vector3(0, 0.24, 0))
	_part(j["spine"], Vector3(0.34 * tw, 0.3, 0.12), head_mat, Vector3(0, 0.26, 0.19 * sqrt(tw)))     # backpack (faces the camera)
	if d.get("heavy", false):
		for sx in [-1.0, 1.0]:
			_part(j["spine"], Vector3(0.26, 0.14, 0.34), accent_mat, Vector3(sx * 0.36 * sh["shoulder"], 0.47, 0))   # shoulder pads
	j["head"] = _joint(j["spine"], Vector3(0, 0.48, 0))
	_part(j["head"], Vector3(0.32, 0.3, 0.3) * hs, head_mat, Vector3(0, 0.16 * hs, 0))
	_part(j["head"], Vector3(0.26 * hs, 0.08, 0.04), visor_mat, Vector3(0, 0.18 * hs, -0.16 * hs))   # visor on the front
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var at: float = sh["arm_t"]
		var lt: float = sh["leg_t"]
		var hand: float = sh["hand"]
		var arm := _joint(j["spine"], Vector3(s * 0.32 * sh["shoulder"], 0.42, 0))
		j["arm_" + side] = arm
		_part(arm, Vector3(0.13 * at, 0.3, 0.13 * at), body_mat, Vector3(0, -0.14, 0))
		var fore := _joint(arm, Vector3(0, -0.29, 0))
		j["fore_" + side] = fore
		_part(fore, Vector3(0.12 * at, 0.24, 0.12 * at), limb_mat, Vector3(0, -0.12, 0))
		_part(fore, Vector3(0.13, 0.11, 0.13) * hand, accent_mat if d.get("heavy", false) else head_mat, Vector3(0, -0.27 - 0.03 * hand, 0))
		var thigh := _joint(j["hips"], Vector3(s * 0.12 * tw, -0.04, 0))
		j["thigh_" + side] = thigh
		_part(thigh, Vector3(0.17 * lt, 0.32 * leg, 0.17 * lt), limb_mat, Vector3(0, -0.15 * leg, 0))
		var shin := _joint(thigh, Vector3(0, -0.3 * leg, 0))
		j["shin_" + side] = shin
		_part(shin, Vector3(0.15 * lt, 0.28 * leg, 0.15 * lt), limb_mat, Vector3(0, -0.14 * leg, 0))
		_part(shin, Vector3(0.17 * lt, 0.08, 0.28), accent_mat if d["ability"] == "super" else head_mat, Vector3(0, -0.29 * leg, -0.05))   # shoe


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, size: Vector3, m: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func set_dead(dead: bool) -> void:
	if def.is_empty():
		return
	body_mat.albedo_color = Color("ff2626") if dead else def["body"]
	limb_mat.albedo_color = Color("c41e1e") if dead else def["limb"]


## Pulse a glow while an ability is active.
func set_glow(on: bool) -> void:
	if not on:
		body_mat.emission_energy_multiplier = 0.0
		return
	var c := Color("ff6a00") if def["ability"] == "smash" else Color("55ff55") if def["ability"] == "super" else Color("3377ff")
	body_mat.emission = c
	body_mat.emission_energy_multiplier = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 60.0)


# --- Poses. For arms and legs +X swings forward; a shin bends back with -X, a forearm forward with +X.
# Left arm/leg swing outward with -Z, right with +Z.

static func p_idle(t: float) -> Dictionary:
	var b := sin(t * 1.8)                                    # breathing
	var hop := fmod(t, 4.5)                                  # now and then a little "ready" bounce
	var bounce := 0.07 * sin(PI * hop / 0.45) if hop < 0.45 else 0.0
	return {"y": 0.015 * b + bounce, "spine": -0.03 + 0.04 * b, "head": 0.05 + 0.04 * sin(t * 0.9),
		"head_y": 0.45 * clampf(sin(t * 0.5) * 2.0, -1.0, 1.0), "rz": 0.04 * sin(t * 0.6),
		"thigh_lz": -0.06, "thigh_rz": 0.06, "shin_l": -0.08, "shin_r": -0.08,
		"arm_lz": -0.2 - 0.05 * b - 1.5 * bounce, "arm_rz": 0.2 + 0.05 * b + 1.5 * bounce, "fore_l": 0.3, "fore_r": 0.3}


static func p_run(p: float, lean: float) -> Dictionary:
	var s := sin(p)
	return {"y": 0.09 * absf(cos(p)) - 0.05, "spine": -0.25 - lean, "head": 0.2 + lean * 0.6 + 0.05 * cos(2.0 * p),
		"ry": 0.16 * s, "spine_y": -0.3 * s, "rz": 0.05 * s,          # hips twist, shoulders counter-twist, hip sway
		"thigh_lx": 1.0 * s, "thigh_rx": -1.0 * s,
		"shin_l": -0.25 - 1.5 * maxf(0.0, -sin(p + 0.5)), "shin_r": -0.25 - 1.5 * maxf(0.0, sin(p + 0.5)),
		"arm_lx": -1.0 * s, "arm_rx": 1.0 * s, "fore_l": 1.45 + 0.25 * s, "fore_r": 1.45 - 0.25 * s, "arm_lz": -0.12, "arm_rz": 0.12}


## Push-off: legs extend, arms thrown up.
static func p_takeoff() -> Dictionary:
	return {"y": 0.05, "spine": 0.1, "head": -0.1, "thigh_lx": -0.35, "thigh_rx": 0.6, "shin_l": -0.1, "shin_r": -1.0,
		"arm_lx": 2.7, "arm_rx": 2.2, "arm_lz": -0.3, "arm_rz": 0.3, "fore_l": 0.2, "fore_r": 0.2}


## Stumble (upper body, over the running legs): pitched forward, arms windmilling.
static func p_stumble(t: float) -> Dictionary:
	return {"rx": -0.3, "spine": -0.65, "head": 0.55, "head_y": 0.3 * sin(t * 18.0),
		"arm_lx": 1.6 + 1.3 * sin(t * 22.0), "arm_rx": 1.6 - 1.3 * sin(t * 22.0), "arm_lz": -0.9, "arm_rz": 0.9, "fore_l": 0.3, "fore_r": 0.3}


## Crash impact: thrown back, arms and legs flung forward (before the flop).
static func p_impact() -> Dictionary:
	return {"y": 0.1, "rx": 0.55, "spine": 0.4, "head": 0.7, "arm_lx": 2.0, "arm_rx": 2.5, "arm_lz": -1.2, "arm_rz": 1.2,
		"thigh_lx": 1.0, "thigh_rx": 0.6, "shin_l": -0.3, "shin_r": -0.6, "fore_l": 0.1, "fore_r": 0.1}


## Cheer (upper body): both fists pumping in the air.
static func p_cheer(t: float) -> Dictionary:
	var pump := 0.35 * sin(t * 16.0)
	return {"arm_lx": 2.9 + pump, "arm_rx": 2.9 - pump, "arm_lz": -0.35, "arm_rz": 0.35, "fore_l": 0.5 - pump, "fore_r": 0.5 + pump, "head": -0.25}


static func p_air(v: float) -> Dictionary:
	var u := clampf((v + 6.0) / 18.0, 0.0, 1.0)   # 1 = rising fast, 0 = falling
	var mix := func(a: float, b: float) -> float: return b + (a - b) * u
	return {"spine": mix.call(-0.15, 0.0), "head": 0.1, "thigh_lx": mix.call(1.3, 0.5), "shin_l": mix.call(-1.6, -0.5),
		"thigh_rx": mix.call(0.4, 0.15), "shin_r": mix.call(-0.7, -0.3), "arm_lx": mix.call(2.4, 0.9), "arm_rx": mix.call(1.6, 0.9),
		"arm_lz": mix.call(-0.3, -0.7), "arm_rz": mix.call(0.3, 0.7), "fore_l": mix.call(0.3, 0.5), "fore_r": 0.5}


static func p_float(t: float) -> Dictionary:
	return {"spine": -0.1, "arm_lx": 0.2, "arm_rx": 0.2, "arm_lz": -1.45 + 0.15 * sin(t * 14.0), "arm_rz": 1.45 - 0.15 * sin(t * 14.0),
		"fore_l": 0.2, "fore_r": 0.2, "thigh_lx": 0.35, "thigh_rx": -0.15, "shin_l": -0.5, "shin_r": -0.3, "thigh_lz": -0.1, "thigh_rz": 0.1}


static func p_slam() -> Dictionary:
	return {"rx": -0.45, "arm_lx": 3.0, "arm_rx": 3.0, "arm_lz": -0.1, "arm_rz": 0.1, "thigh_lx": -0.15, "thigh_rx": -0.15, "shin_l": -0.1, "shin_r": -0.1, "head": 0.3}


static func p_slide() -> Dictionary:
	return {"y": -0.36, "rx": 1.25, "spine": -0.15, "head": -0.85, "thigh_lx": 0.3, "shin_l": -0.1, "thigh_rx": 0.05, "shin_r": -1.1,
		"arm_lx": -0.6, "arm_rx": -0.6, "arm_lz": -0.5, "arm_rz": 0.5, "fore_l": 0.3, "fore_r": 0.3}


static func p_land() -> Dictionary:
	return {"y": -0.2, "spine": -0.45, "head": 0.35, "thigh_lx": 0.7, "thigh_rx": 0.7, "shin_l": -1.2, "shin_r": -1.2,
		"arm_lx": 0.5, "arm_rx": 0.5, "arm_lz": -0.4, "arm_rz": 0.4, "fore_l": 0.6, "fore_r": 0.6}


static func p_tuck() -> Dictionary:
	return {"spine": -0.5, "head": -0.3, "thigh_lx": 1.9, "thigh_rx": 1.9, "shin_l": -2.2, "shin_r": -2.2,
		"arm_lx": 1.2, "arm_rx": 1.2, "fore_l": 1.6, "fore_r": 1.6}


static func p_orbit(t: float) -> Dictionary:
	return {"rx": -1.35, "head": 1.1, "arm_rx": 3.0, "arm_rz": 0.05, "arm_lx": 0.2, "arm_lz": -0.25, "fore_l": 0.4,
		"thigh_lx": -0.05 + 0.08 * sin(t * 6.0), "thigh_rx": 0.3, "shin_r": -0.7, "shin_l": -0.1}


static func p_hit() -> Dictionary:
	return {"y": -0.45, "rx": 1.45, "head": 0.4, "arm_lx": 2.6, "arm_rx": 2.2, "arm_lz": -0.9, "arm_rz": 0.9,
		"thigh_lx": 0.9, "thigh_rx": 0.4, "shin_l": -0.5, "shin_r": -0.2}


## state: menu | run | hit | over. s: the player's movement state (see main.gd).
func update_pose(dt: float, state: String, s: Dictionary) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var grounded: bool = s["grounded"]
	var flip := _tick(dt, state, s)
	var target: Dictionary
	if state == "menu":
		target = p_idle(t)
	elif state == "hit" or state == "over":
		target = p_impact() if crash_t >= 0.0 and crash_t < 0.12 else p_hit()
	elif s.get("hop", -1.0) >= 0.0:
		target = p_tuck()
	elif s.get("orbit", false):
		target = p_orbit(t)
	elif grounded:
		if s["slide"] > 0.0:
			target = p_slide()
		else:
			target = p_run(run_phase, clampf((s["speed"] - 12.0) / 40.0, 0.0, 0.2))
			if land_t > 0.0:   # landing crouch layered over the run
				_blend(target, p_land(), land_t / 0.16)
	elif takeoff_t > 0.0:
		target = p_takeoff()
	elif s["vy"] < -20.0:
		target = p_slam()
	elif s["floating"]:
		target = p_float(t)
	else:
		target = p_air(s["vy"])
	if state == "run":
		if stumble_t > 0.0:
			_blend(target, p_stumble(t), minf(1.0, stumble_t / 0.15))
		if cheer_t > 0.0:
			_blend(target, p_cheer(t), minf(1.0, cheer_t / 0.2))
		_lane_layer(target, grounded and s["slide"] <= 0.0, 1.0)
	_springs(target, KEYS, dt, state == "hit" or state == "over")
	_apply_pivot(s, flip)
	j["spine"].rotation = Vector3(pose["spine"], pose["spine_y"], 0)
	j["head"].rotation = Vector3(pose["head"], pose["head_y"], 0)
	j["arm_l"].rotation = Vector3(pose["arm_lx"], 0, pose["arm_lz"])
	j["arm_r"].rotation = Vector3(pose["arm_rx"], 0, pose["arm_rz"])
	j["fore_l"].rotation.x = pose["fore_l"]
	j["fore_r"].rotation.x = pose["fore_r"]
	j["thigh_l"].rotation = Vector3(pose["thigh_lx"], 0, pose["thigh_lz"])
	j["thigh_r"].rotation = Vector3(pose["thigh_rx"], 0, pose["thigh_rz"])
	j["shin_l"].rotation.x = pose["shin_l"]
	j["shin_r"].rotation.x = pose["shin_r"]


# --- Shared toon layer (also used by HeroCharacter) ---------------------------------

## Timers, squash and stretch, dust and the air-jump flip. Returns the extra flip angle.
func _tick(dt: float, state: String, s: Dictionary) -> float:
	var grounded: bool = s["grounded"]
	if state == "run" and grounded and s["slide"] <= 0.0:
		run_phase += dt * (4.0 + s["speed"] * 0.42)
	land_t = maxf(0.0, land_t - dt)
	takeoff_t = maxf(0.0, takeoff_t - dt)
	lane_t = maxf(0.0, lane_t - dt)
	stumble_t = maxf(0.0, stumble_t - dt)
	cheer_t = maxf(0.0, cheer_t - dt)
	if crash_t >= 0.0:
		crash_t += dt
	for _i in 2:          # squash spring: bouncy
		var h := dt / 2.0
		sq_v += (-sq * 300.0 - sq_v * 2.0 * 0.28 * sqrt(300.0)) * h
		sq += sq_v * h
	# Squash and stretch (volume kept), plus a small squash at each footfall.
	var step_sq := 0.06 * pow(absf(sin(run_phase)), 8.0) if state == "run" and grounded and s["slide"] <= 0.0 else 0.0
	var q := clampf(sq + step_sq, -0.3, 0.45)
	scale = Vector3(1.0 / sqrt(1.0 - q), 1.0 - q, 1.0 / sqrt(1.0 - q))
	dust_slide.emitting = state == "run" and grounded and s["slide"] > 0.0
	var flip: float = -s.get("hop", -1.0) * TAU if s.get("hop", -1.0) >= 0.0 else 0.0   # forward somersault on a planet hop
	if flip_t >= 0.0:      # air jump: a quick front flip
		flip_t += dt / 0.45
		if flip_t >= 1.0 or grounded:
			flip_t = -1.0
		else:
			flip -= TAU * (1.0 - pow(1.0 - flip_t, 2.0))
	return flip


## Lane switch: a little hop, lean in, shoulders turn, outer arm flies out (scaled by w).
func _lane_layer(target: Dictionary, hop: bool, w: float) -> void:
	if lane_t <= 0.0:
		return
	var bump := sin(PI * (1.0 - lane_t / 0.24))
	if hop:
		target["y"] = target.get("y", 0.0) + 0.16 * bump
	target["rz"] = target.get("rz", 0.0) - lane_dir * 0.25 * bump
	target["spine_y"] = target.get("spine_y", 0.0) - lane_dir * 0.35 * bump * w
	if lane_dir > 0.0:
		target["arm_lz"] = target.get("arm_lz", 0.0) - 0.9 * bump * w
	else:
		target["arm_rz"] = target.get("arm_rz", 0.0) + 0.9 * bump * w


## Springs: snappy, with a little overshoot; floppier when crashed.
func _springs(target: Dictionary, keys: Array, dt: float, floppy: bool) -> void:
	var h := dt / 2.0
	for _i in 2:
		for k in keys:
			var kk: float = (BASE_K * 0.45 if floppy else BASE_K) * SOFT.get(k, 1.0)
			var d := 2.0 * (0.3 if floppy else ZETA) * sqrt(kk)
			vel[k] += ((target.get(k, 0.0) - pose[k]) * kk - vel[k] * d) * h
			pose[k] += vel[k] * h


func _apply_pivot(s: Dictionary, flip: float) -> void:
	pivot.position.y = hip_y + pose["y"]
	var lean: float = s["lean"] * 0.12
	var twist: float = s["twist"] * 0.35
	pivot.rotation = Vector3(pose["rx"] + flip, pose["ry"] + twist, pose["rz"] + lean)


## Mixes the keys of b into a with weight w (keys missing in b count as 0).
static func _blend(a: Dictionary, b: Dictionary, w: float) -> void:
	for k in b:
		a[k] = a.get(k, 0.0) * (1.0 - w) + b[k] * w
