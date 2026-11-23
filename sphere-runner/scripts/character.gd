class_name BlockCharacter
extends Node3D
## A block figure on a standard humanoid joint layout (hips, spine, head, arms,
## forearms, thighs, shins). It only *shows* the game state: gameplay never waits for
## an animation. Poses are blended (~0.1 s crossfade); lean, twist and flip are layered on top.
## Swap it later for a rigged model with the same named poses.

const KEYS := ["y", "rx", "ry", "rz", "spine", "head", "arm_lx", "arm_lz", "arm_rx", "arm_rz",
	"fore_l", "fore_r", "thigh_lx", "thigh_lz", "thigh_rx", "thigh_rz", "shin_l", "shin_r"]
const HIP_Y := 0.66
const BODY_COLOR := Color("3380ff")
const LIMB_COLOR := Color("2559c4")

var pivot := Node3D.new()      # at the hips: tilts, leans and flips rotate here
var j := {}                    # joints by name
var pose := {}                 # current blended pose
var run_phase := 0.0
var land_t := 0.0
var body_mat := StandardMaterial3D.new()
var limb_mat := StandardMaterial3D.new()


func _ready() -> void:
	for k in KEYS:
		pose[k] = 0.0
	body_mat.albedo_color = BODY_COLOR
	limb_mat.albedo_color = LIMB_COLOR
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color("f0f0f5")
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color("29d4ff")
	visor_mat.emission_enabled = true
	visor_mat.emission = Color("29d4ff")
	visor_mat.emission_energy_multiplier = 0.4
	pivot.position.y = HIP_Y
	add_child(pivot)
	j["hips"] = _joint(pivot, Vector3.ZERO)
	_part(j["hips"], Vector3(0.42, 0.16, 0.26), limb_mat, Vector3.ZERO)
	j["spine"] = _joint(j["hips"], Vector3(0, 0.06, 0))
	_part(j["spine"], Vector3(0.5, 0.44, 0.28), body_mat, Vector3(0, 0.24, 0))
	_part(j["spine"], Vector3(0.34, 0.3, 0.12), head_mat, Vector3(0, 0.26, 0.19))     # backpack (faces the camera)
	j["head"] = _joint(j["spine"], Vector3(0, 0.48, 0))
	_part(j["head"], Vector3(0.32, 0.3, 0.3), head_mat, Vector3(0, 0.16, 0))
	_part(j["head"], Vector3(0.26, 0.08, 0.04), visor_mat, Vector3(0, 0.18, -0.16))  # visor on the front
	for s in [-1, 1]:
		var side := "l" if s < 0 else "r"
		var arm := _joint(j["spine"], Vector3(s * 0.32, 0.42, 0))
		j["arm_" + side] = arm
		_part(arm, Vector3(0.13, 0.3, 0.13), body_mat, Vector3(0, -0.14, 0))
		var fore := _joint(arm, Vector3(0, -0.29, 0))
		j["fore_" + side] = fore
		_part(fore, Vector3(0.12, 0.24, 0.12), limb_mat, Vector3(0, -0.12, 0))
		_part(fore, Vector3(0.13, 0.11, 0.13), head_mat, Vector3(0, -0.29, 0))
		var thigh := _joint(j["hips"], Vector3(s * 0.12, -0.04, 0))
		j["thigh_" + side] = thigh
		_part(thigh, Vector3(0.17, 0.32, 0.17), limb_mat, Vector3(0, -0.15, 0))
		var shin := _joint(thigh, Vector3(0, -0.3, 0))
		j["shin_" + side] = shin
		_part(shin, Vector3(0.15, 0.28, 0.15), limb_mat, Vector3(0, -0.14, 0))
		_part(shin, Vector3(0.17, 0.08, 0.28), head_mat, Vector3(0, -0.29, -0.05))     # shoe


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
	body_mat.albedo_color = Color("ff2626") if dead else BODY_COLOR
	limb_mat.albedo_color = Color("c41e1e") if dead else LIMB_COLOR


# --- Poses. For arms and legs +X swings forward; a shin bends back with -X, a forearm forward with +X.
# Left arm/leg swing outward with -Z, right with +Z.

static func p_idle(t: float) -> Dictionary:
	return {"y": 0.01 * sin(t * 2.0), "head": 0.05 * sin(t * 0.7), "arm_lz": -0.12, "arm_rz": 0.12, "fore_l": 0.15, "fore_r": 0.15}


static func p_run(p: float) -> Dictionary:
	var s := sin(p)
	return {"y": 0.05 * absf(cos(p)) - 0.03, "spine": -0.25, "head": 0.18,
		"thigh_lx": 0.9 * s, "thigh_rx": -0.9 * s,
		"shin_l": -0.2 - 1.3 * maxf(0.0, -sin(p + 0.5)), "shin_r": -0.2 - 1.3 * maxf(0.0, sin(p + 0.5)),
		"arm_lx": -0.85 * s, "arm_rx": 0.85 * s, "fore_l": 1.4, "fore_r": 1.4, "arm_lz": -0.1, "arm_rz": 0.1}


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


static func p_hit() -> Dictionary:
	return {"y": -0.45, "rx": 1.45, "head": 0.4, "arm_lx": 2.6, "arm_rx": 2.2, "arm_lz": -0.9, "arm_rz": 0.9,
		"thigh_lx": 0.9, "thigh_rx": 0.4, "shin_l": -0.5, "shin_r": -0.2}


## state: menu | run | hit | over. s: the player's movement state (see main.gd).
func update_pose(dt: float, state: String, s: Dictionary) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if state == "run" and s["grounded"] and s["slide"] <= 0.0:
		run_phase += dt * (4.0 + s["speed"] * 0.42)
	land_t = maxf(0.0, land_t - dt)
	var target: Dictionary
	if state == "menu":
		target = p_idle(t)
	elif state == "hit" or state == "over":
		target = p_hit()
	elif s["grounded"]:
		if s["slide"] > 0.0:
			target = p_slide()
		else:
			target = p_run(run_phase)
			if land_t > 0.0:   # landing crouch layered over the run
				var w := land_t / 0.16
				var l := p_land()
				for k in KEYS:
					target[k] = target.get(k, 0.0) * (1.0 - w) + l.get(k, 0.0) * w
	elif s["vy"] < -20.0:
		target = p_slam()
	elif s["floating"]:
		target = p_float(t)
	else:
		target = p_air(s["vy"])
	var a := 1.0 - exp(-dt * (10.0 if state == "hit" else 18.0))
	for k in KEYS:
		pose[k] += (target.get(k, 0.0) - pose[k]) * a
	pivot.position.y = HIP_Y + pose["y"]
	var lean: float = s["lean"] * 0.12
	var twist: float = s["twist"] * 0.35
	pivot.rotation = Vector3(pose["rx"], pose["ry"] + twist, pose["rz"] + lean)
	j["spine"].rotation.x = pose["spine"]
	j["head"].rotation.x = pose["head"]
	j["arm_l"].rotation = Vector3(pose["arm_lx"], 0, pose["arm_lz"])
	j["arm_r"].rotation = Vector3(pose["arm_rx"], 0, pose["arm_rz"])
	j["fore_l"].rotation.x = pose["fore_l"]
	j["fore_r"].rotation.x = pose["fore_r"]
	j["thigh_l"].rotation = Vector3(pose["thigh_lx"], 0, pose["thigh_lz"])
	j["thigh_r"].rotation = Vector3(pose["thigh_rx"], 0, pose["thigh_rz"])
	j["shin_l"].rotation.x = pose["shin_l"]
	j["shin_r"].rotation.x = pose["shin_r"]
