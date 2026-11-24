class_name ModelCharacter
extends BlockCharacter
## A rigged hero model (Mixamo-style bone names, e.g. a Tripo export) driven by the same
## poses as the block figure: springs, squash and stretch, takeoff, flip, lane hop, stumble,
## crash and cheer all come from BlockCharacter. Each pose angle is a rotation about the
## character's own axes at a joint (forward -Z, left -X, up +Y); it is turned into a bone
## rotation relative to the model's rest pose. Arms and legs are first straightened to hang
## down (the block figure's rest pose), so every pose means the same on both.

const BONES := {
	"spine": ["Spine", "Spine1", "Spine2"], "head": ["Neck", "Head"],
	"arm_l": ["LeftArm"], "fore_l": ["LeftForeArm"], "arm_r": ["RightArm"], "fore_r": ["RightForeArm"],
	"thigh_l": ["LeftUpLeg"], "shin_l": ["LeftLeg"], "thigh_r": ["RightUpLeg"], "shin_r": ["RightLeg"]}
const SPLIT := {"Spine": 0.34, "Spine1": 0.33, "Spine2": 0.33, "Neck": 0.4, "Head": 0.6}
const MODEL_K := 1100.0          # spring stiffness (block figure: 520)
const MODEL_ZETA := 0.9          # damping (block figure: 0.5, which overshoots)
const STRAIGHTEN := ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]

var model: Node3D
var skel: Skeleton3D
var _m := Basis()                 # skeleton space -> character space (rotation only)
var _rest := {}                   # bone index -> rest global basis (skeleton space)
var _fix := {}                    # bone name -> straightening rotation (character space)
var _idx := {}                    # bone name -> index
var _overlay := StandardMaterial3D.new()
var anim: AnimationPlayer          # the model's animation clips (if it has any)
var clips := {}                    # move -> clip name (from the character's "clips")
var use_clips := true              # Hero Lab: CLIPS / CODE
var force_clip := ""               # Hero Lab: show this move's clip on a loop
var _clip := ""                    # the move whose clip is playing
var _restart := ""                 # a move whose clip starts again (a new jump, slide...)


func build(d: Dictionary) -> void:
	def = d
	for c in pivot.get_children():
		c.queue_free()
	j.clear()
	eyes.clear()
	model = (load(d["model"]) as PackedScene).instantiate()
	pivot.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in skel.get_bone_count():
		_idx[_short(skel.get_bone_name(i))] = i
		_rest[i] = skel.get_bone_global_rest(i).basis.orthonormalized()
	# skeleton -> model root transform (the scene's own nodes in between)
	var t := Transform3D()
	var n: Node = skel
	while n != model:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	var gpos := func(b: String) -> Vector3: return t * skel.get_bone_global_rest(_idx[b]).origin
	# Turn the model to face -Z like the game: forward is where the toes point (foot -> toe),
	# checked against its left side (left leg minus right leg) ending up at -X.
	var fwd: Vector3 = (gpos.call("LeftToeBase") - gpos.call("LeftFoot")) + (gpos.call("RightToeBase") - gpos.call("RightFoot"))
	var l: Vector3 = gpos.call("LeftUpLeg") - gpos.call("RightUpLeg")
	var turn := Basis()
	var best := -INF
	for step in 72:                      # the turn (5 degree steps) that best fits both
		var b := Basis(Vector3.UP, step * TAU / 72.0)
		var fit: float = -(b * Vector3(fwd.x, 0, fwd.z)).normalized().z - (b * Vector3(l.x, 0, l.z)).normalized().x
		if fit > best:
			best = fit
			turn = b
	# height: the top of the head bone (plus the hood) scaled to model_h
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		m3.material_overlay = _overlay
		for si in m3.mesh.get_surface_count():   # readable on the road: a little self-light and a rim
			var src := m3.mesh.surface_get_material(si)
			if src is StandardMaterial3D:
				var m: StandardMaterial3D = src.duplicate()
				m.emission_enabled = true
				m.emission_texture = m.albedo_texture
				m.emission = Color.WHITE
				m.emission_energy_multiplier = d.get("model_glow", 0.18)
				m.rim_enabled = true
				m.rim = 0.25
				m.rim_tint = 0.6
				m.roughness = 0.9
				m.metallic = 0.0
				m3.set_surface_override_material(si, m)
	var top: Vector3 = gpos.call("HeadTop_End") if _idx.has("HeadTop_End") else gpos.call("Head")
	var k: float = d.get("model_h", 1.5) / maxf(0.05, top.y * 1.04)
	var hips: Vector3 = turn * (gpos.call("Hips") * k)
	model.transform = Transform3D(turn.scaled(Vector3(k, k, k)), -hips)
	hip_y = hips.y
	_m = (turn * t.basis).orthonormalized()
	# straighten arms and legs to hang down, parent first (each fix carries to its children)
	var acc := {}
	for name in STRAIGHTEN:
		var i: int = _idx[name]
		var child := _first_child(i)
		if child < 0:
			continue
		var dir: Vector3 = _m * (skel.get_bone_global_rest(child).origin - skel.get_bone_global_rest(i).origin)
		var parent_fix: Basis = acc.get(_short(skel.get_bone_name(skel.get_bone_parent(i))), Basis())
		dir = (parent_fix * dir).normalized()
		var f := Basis(Quaternion(dir, Vector3.DOWN)) if dir.length() > 0.0 else Basis()
		_fix[name] = f
		acc[name] = parent_fix * f
	# animation clips: moves mapped to clip names in config (e.g. "run": "Running")
	clips = {}
	_clip = ""
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	anim = aps[0] if aps.size() > 0 else null
	if anim:
		# clips advance with the game's own time (pause, slow motion, Focus), not on their own
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for move in d.get("clips", {}):
			var name: String = d["clips"][move]
			if anim.has_animation(name):
				clips[move] = name
				anim.get_animation(name).loop_mode = Animation.LOOP_LINEAR if move == "run" else Animation.LOOP_NONE
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(0, 0, 0, 0)
	set_dead(false)


## "mixamorig:LeftArm" / "mixamorig_LeftArm" (Godot renames ':' on import) -> "LeftArm"
static func _short(bone: String) -> String:
	return bone.replace("mixamorig:", "").replace("mixamorig_", "")


func event(name: String, arg := 0.0) -> void:
	super.event(name, arg)
	if name in ["jump", "jump2", "slide", "stumble", "crash", "cheer"]:
		_restart = "jump" if name == "jump2" else name


## Which clip fits the moment ("" = none: the code-driven pose).
func _choose(state: String, s: Dictionary) -> String:
	if force_clip != "":
		return force_clip
	if state == "hit" or state == "over":
		return "crash"
	if state != "run" or s.get("hop", -1.0) >= 0.0 or s.get("orbit", false):
		return ""
	if stumble_t > 0.0:
		return "stumble"
	if s["grounded"]:
		return "slide" if s["slide"] > 0.0 else "run"
	return "jump"


## With clips: the clip moves the skeleton; the toon layer (squash and stretch, the lane hop
## and lean, the air flip, the crash flop) still moves the whole hero on top.
func update_pose(dt: float, state: String, s: Dictionary) -> void:
	var move := _choose(state, s) if (use_clips and anim) else ""
	if move == "" or not clips.has(move):
		if anim and anim.is_playing():
			anim.stop()
		_clip = ""
		super.update_pose(dt, state, s)
		return
	var flip := _tick(dt, state, s)
	var target := {}
	if state == "run":
		_lane_layer(target, s["grounded"] and s["slide"] <= 0.0, 0.0)
	_springs(target, ["y", "rx", "ry", "rz"], dt, false)
	_apply_pivot(s, flip)
	var speed := 1.0
	match move:
		"run": speed = clampf(0.9 + s["speed"] * 0.035, 1.0, 1.9)
		"jump": speed = 1.7
		"slide": speed = 1.6
		"stumble": speed = 1.2
	if move != _clip or _restart == move:
		anim.play(clips[move], 0.12 if _clip != "" else 0.0)
		if move == "run" and _clip != "":
			anim.seek(randf() * 0.05, true)
		_clip = move
	_restart = ""
	anim.speed_scale = 1.0
	anim.advance(dt * speed)


func _first_child(i: int) -> int:
	for c in skel.get_bone_children(i):
		var nm := skel.get_bone_name(c)
		if not ("Index" in nm or "Middle" in nm or "Ring" in nm or "Pinky" in nm or "Thumb" in nm):
			return c
	return -1


func _apply_joints() -> void:
	if skel == null:
		return
	var rot := {
		"spine": Vector3(pose["spine"], pose["spine_y"], 0), "head": Vector3(pose["head"], pose["head_y"], 0),
		"arm_l": Vector3(pose["arm_lx"], 0, pose["arm_lz"]), "arm_r": Vector3(pose["arm_rx"], 0, pose["arm_rz"]),
		"fore_l": Vector3(pose["fore_l"], 0, 0), "fore_r": Vector3(pose["fore_r"], 0, 0),
		"thigh_l": Vector3(pose["thigh_lx"], 0, pose["thigh_lz"]), "thigh_r": Vector3(pose["thigh_rx"], 0, pose["thigh_rz"]),
		"shin_l": Vector3(pose["shin_l"], 0, 0), "shin_r": Vector3(pose["shin_r"], 0, 0)}
	var mi := _m.inverse()
	for key in BONES:
		for name in BONES[key]:
			if not _idx.has(name):
				continue
			var i: int = _idx[name]
			var r: Basis = Basis.from_euler(rot[key] * SPLIT.get(name, 1.0)) * _fix.get(name, Basis())
			var p := skel.get_bone_parent(i)
			var parent_rest: Basis = _rest[p] if p >= 0 else Basis()
			var local: Basis = parent_rest.inverse() * (mi * r * _m) * _rest[i]
			skel.set_bone_pose_rotation(i, local.get_rotation_quaternion())


## Stiffer than the block figure: a real body with real legs looks rubbery when the joints
## overshoot. Firm springs, close to critically damped (floppy only when crashed).
func _springs(target: Dictionary, keys: Array, dt: float, floppy: bool) -> void:
	var h := dt / 3.0
	for _i in 3:
		for k in keys:
			var kk: float = (MODEL_K * 0.5 if floppy else MODEL_K) * SOFT.get(k, 1.0)
			var d := 2.0 * (0.45 if floppy else MODEL_ZETA) * sqrt(kk)
			vel[k] += ((target.get(k, 0.0) - pose[k]) * kk - vel[k] * d) * h
			pose[k] += vel[k] * h


func set_dead(dead: bool) -> void:
	_overlay.albedo_color = Color(1, 0.1, 0.1, 0.45) if dead else Color(0, 0, 0, 0)


func set_glow(on: bool) -> void:
	if not on:
		if _overlay.albedo_color.r < 0.9:
			_overlay.albedo_color = Color(0, 0, 0, 0)
		return
	_overlay.albedo_color = Color(0.2, 0.45, 1.0, 0.25 + 0.15 * sin(Time.get_ticks_msec() / 60.0))
