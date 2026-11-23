class_name HeroCharacter
extends BlockCharacter
## A rigged hero model (KayKit, CC0) driven by animation clips, with the same toon layer
## as the block figure on top: squash and stretch, springy leans, lane hops, flips, dust.
## Same interface as BlockCharacter, so the game does not care which one it shows.
## All heroes share one 23-bone rig, so every clip works on every hero.

const ANIM_FILES := ["MovementBasic", "General", "Simulation", "MovementAdvanced"]
const LOOPS := ["Running_A", "Running_B", "Idle_A", "Idle_B", "Jump_Idle", "Sit_Floor_Idle", "Cheering", "Crouching"]
## Base clips (whole body) and upper-body overlays (arms, chest, head over the running legs).
const BASE := ["Idle_A", "Running_A", "Jump_Start", "Jump_Idle", "Jump_Land", "Dodge_Left", "Dodge_Right",
	"Sit_Floor_Idle", "Death_A"]
const UPPER := ["Cheering", "Hit_A"]
const UPPER_BONES := ["chest", "head", "upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "upperarm.r", "lowerarm.r",
	"wrist.r", "hand.r"]
const PIVOT_KEYS := ["y", "rx", "rz"]
const HEIGHT := 1.6         # metres, for a scale of 1 in the character definition

static var _library: AnimationLibrary   # loaded once, shared by all heroes

var model: Node3D
var tree: AnimationTree
var meshes: Array[MeshInstance3D] = []
var overlay := StandardMaterial3D.new()
var _base := ""
var _upper := ""
var _upper_w := 0.0


func _ready() -> void:
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	super._ready()


static func library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for f in ANIM_FILES:
		var scene: Node = load("res://assets/kaykit/animations/Rig_Medium_%s.glb" % f).instantiate()
		var ap: AnimationPlayer = scene.find_child("AnimationPlayer", true, false)
		for n in ap.get_animation_list():
			if n != "T-Pose" and not _library.has_animation(n):
				var a: Animation = ap.get_animation(n).duplicate()
				if n in LOOPS:
					a.loop_mode = Animation.LOOP_LINEAR
				_library.add_animation(n, a)
		scene.free()
	return _library


func build(d: Dictionary) -> void:
	def = d
	for c in pivot.get_children():
		c.queue_free()
	j.clear()
	meshes.clear()
	model = load("res://assets/kaykit/characters/%s.glb" % d["model"]).instantiate()
	var k: float = HEIGHT / 2.2 * d.get("model_scale", 1.0)
	model.scale = Vector3.ONE * k
	model.rotation.y = PI                       # the models face +Z, the runner faces -Z
	var skel: Skeleton3D = model.find_child("Skeleton3D", true, false)
	hip_y = skel.get_bone_global_rest(skel.find_bone("hips")).origin.y * k
	pivot.position.y = hip_y
	model.position.y = -hip_y                   # the pivot sits at the hips: leans and flips turn there
	pivot.add_child(model)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(m)
		m.material_overlay = overlay
	overlay.albedo_color = Color(0, 0, 0, 0)
	tree = AnimationTree.new()
	tree.add_animation_library("", library())
	tree.tree_root = _make_tree()
	model.add_child(tree)                        # tracks are relative to the model root
	tree.root_node = NodePath("..")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # advanced with the game
	tree.active = true
	_base = ""
	_upper = ""
	_upper_w = 0.0
	_play("Idle_A")


## Base clips cross-fade into each other; an upper-body overlay blends on top; the base
## can be sped up (running cadence follows the run speed).
func _make_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var base := AnimationNodeTransition.new()
	base.xfade_time = 0.12
	var upper := AnimationNodeTransition.new()
	upper.xfade_time = 0.1
	bt.add_node("base", base)
	bt.add_node("upper", upper)
	for list in [[BASE, base, "b_", "base"], [UPPER, upper, "u_", "upper"]]:
		var i := 0
		for n in list[0]:
			list[1].add_input(n)
			list[1].set_input_reset(i, true)
			var an := AnimationNodeAnimation.new()
			an.animation = n
			bt.add_node(list[2] + n, an)
			bt.connect_node(list[3], i, list[2] + n)
			i += 1
	var speed := AnimationNodeTimeScale.new()
	bt.add_node("speed", speed)
	bt.connect_node("speed", 0, "base")
	var mix := AnimationNodeBlend2.new()
	mix.filter_enabled = true
	for b in UPPER_BONES:
		mix.set_filter_path(NodePath("Rig_Medium/Skeleton3D:" + b), true)
	bt.add_node("mix", mix)
	bt.connect_node("mix", 0, "speed")
	bt.connect_node("mix", 1, "upper")
	bt.connect_node("output", 0, "mix")
	return bt


func _play(clip: String) -> void:
	if clip != _base:
		_base = clip
		tree.set("parameters/base/transition_request", clip)


func set_dead(dead: bool) -> void:
	overlay.albedo_color = Color(1, 0.1, 0.1, 0.35) if dead else Color(0, 0, 0, 0)


func set_glow(on: bool) -> void:
	if not on:
		if overlay.albedo_color.r < 0.9 or overlay.albedo_color.g > 0.2:   # keep the red of a crash
			overlay.albedo_color = Color(0, 0, 0, 0)
		return
	var c := Color("ff6a00") if def["ability"] == "smash" else Color("55ff55") if def["ability"] == "super" else Color("3377ff")
	c.a = 0.25 + 0.15 * sin(Time.get_ticks_msec() / 60.0)
	overlay.albedo_color = c


func update_pose(dt: float, state: String, s: Dictionary) -> void:
	var grounded: bool = s["grounded"]
	var flip := _tick(dt, state, s)
	var target := {}
	var clip := "Running_A"
	var rate := 1.0
	var hop: float = s.get("hop", -1.0)
	if state == "menu":
		clip = "Idle_A"
	elif state == "hit" or state == "over":
		clip = "Death_A"
	elif hop >= 0.0 or s.get("orbit", false):
		clip = "Jump_Idle"
		if s.get("orbit", false):
			target["rx"] = -1.2               # superman pose while orbiting
	elif grounded:
		if s["slide"] > 0.0:
			clip = "Sit_Floor_Idle"           # a baseball slide: sitting, legs forward
			target["rx"] = 0.25
			target["y"] = 0.05
		elif lane_t > 0.12:
			clip = "Dodge_Left" if lane_dir < 0.0 else "Dodge_Right"
		elif land_t > 0.0:
			clip = "Jump_Land"
			rate = 2.0
		else:
			clip = "Running_A"
			rate = (4.0 + s["speed"] * 0.42) / TAU * 0.8     # cadence follows the run speed
			target["rx"] = -0.1 - clampf((s["speed"] - 12.0) / 60.0, 0.0, 0.15)
	elif takeoff_t > 0.0:
		clip = "Jump_Start"
		rate = 2.5
	elif s["vy"] < -20.0:
		clip = "Jump_Idle"
		target["rx"] = -0.4                   # slam: dive down
	else:
		clip = "Jump_Idle"
	if state == "run":
		if stumble_t > 0.0:
			target["rx"] = -0.35
		_lane_layer(target, grounded and s["slide"] <= 0.0, 0.0)
	_play(clip)
	tree.set("parameters/speed/scale", rate)
	# Upper-body overlay: cheer after a boss, flinch on a stumble.
	var up := "Cheering" if cheer_t > 0.0 else "Hit_A" if stumble_t > 0.0 else ""
	if up != "" and up != _upper:
		_upper = up
		tree.set("parameters/upper/transition_request", up)
	_upper_w = move_toward(_upper_w, 1.0 if up != "" and state == "run" else 0.0, dt * 6.0)
	tree.set("parameters/mix/blend_amount", _upper_w)
	tree.advance(dt)
	_springs(target, PIVOT_KEYS, dt, state == "hit" or state == "over")
	_apply_pivot(s, flip)
