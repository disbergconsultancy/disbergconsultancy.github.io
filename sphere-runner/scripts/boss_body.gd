class_name BossBody
extends Node3D
## The block-built body of a boss, one look and motion per archetype:
##   gate_walker  a horned brute on legs beside the track (you run underneath it)
##   flyer        a winged beast hovering above the track (it swoops low at the end: slide)
##   roller       curled into a rolling boulder (it swerves into a side lane at the end: overtake)
##   burrower     travels underground, surfaces to attack (erupts in a lane at the end)
##   twins        two smaller brutes either side of the road (they stomp into the outer lanes)
## The boss (boss.gd) sets pass_u / pass_lane for the final pass and calls on_attack().
## Positions are relative to the boss node: x across the track, +z toward the runner.

var arch := "gate_walker"
var def := {}
var overlay: Material
var eye_mat: Material
var parts := {}          # named nodes
var t := 0.0
var drift_x := 0.0       # sideways offset (roller and burrower at the final pass)
var height := 0.0        # flyer hover / burrower depth
var pass_u := 0.0        # 0..1: how far the final-pass move has gone (set by the boss)
var pass_lane := 0
var surface_t := 0.0     # burrower: seconds above ground after an attack
var side := 1.0          # twins: which twin throws next
var attack_t := 0.0      # a short "attack" pose after each move
var swoop_z := 0.0       # flyer: how far it has dived back toward the runner


func build(d: Dictionary, ov: Material, eyes: Material) -> void:
	def = d
	arch = d.get("archetype", "gate_walker")
	overlay = ov
	eye_mat = eyes
	for c in get_children():
		c.queue_free()
	parts.clear()
	call("_build_" + arch)


# --- Pieces -------------------------------------------------------------------

func _tex() -> String:
	return "blockbits/" + def.get("block", "stone")


## A textured block (Block Bits), centred at pos, child of parent.
func _block(parent: Node3D, size: Vector3, pos: Vector3, tex := "") -> Node3D:
	var n := Kit.node(tex if tex != "" else _tex(), size)
	n.position = pos
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_overlay = overlay
	parent.add_child(n)
	return n


## A soft block in one colour.
func _soft(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.soft_box(size)
	mi.material_override = m
	mi.material_overlay = overlay
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3, name: String = "") -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	if name != "":
		parts[name] = n
	return n


func _color(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _eyes(parent: Node3D, y: float, z: float, gap: float, size: float) -> void:
	for sx in [-1.0, 1.0]:
		_soft(parent, Vector3(size * 1.5, size, 0.4), Vector3(sx * gap, y, z), eye_mat)


# --- Builders -----------------------------------------------------------------

func _build_gate_walker() -> void:
	var s := Config.BOSS_SIZE
	var lift := Config.BOSS_LIFT
	var root := _pivot(self, Vector3.ZERO, "root")
	_block(root, Vector3(s, s, s), Vector3(0, lift + s / 2.0, 0))
	_eyes(root, lift + s * 0.68, s / 2.0 + 0.15, 2.9, 1.5)
	var bone := _color(Color("efe6cf"))
	for sx in [-1.0, 1.0]:              # horns
		var h := _pivot(root, Vector3(sx * 4.6, lift + s, 0))
		h.rotation.z = -sx * 0.55
		_soft(h, Vector3(1.6, 4.0, 1.6), Vector3(0, 2.0, 0), bone)
		_soft(h, Vector3(1.0, 1.8, 1.0), Vector3(0, 4.8, 0), bone)
		var arm := _pivot(root, Vector3(sx * (s / 2.0 + 1.3), lift + s * 0.85, 0), "arm_" + str(sx))
		_block(arm, Vector3(2.4, 7.5, 2.4), Vector3(0, -3.75, 0))
		_block(arm, Vector3(3.2, 2.8, 3.2), Vector3(0, -8.2, 0))
		for k in 2:                     # legs beside the track
			var lh := (lift + 0.5) / 2.0
			var leg := _pivot(root, Vector3(sx * (Config.TRACK_HALF + 1.7), 0, 0), "leg_%s_%d" % [sx, k])
			_block(leg, Vector3(2.6, lh, 3.2), Vector3(0, lh * (k + 0.5), 0))


func _build_flyer() -> void:
	var root := _pivot(self, Vector3(0, 10, 0), "root")
	_block(root, Vector3(6.0, 4.0, 9.0), Vector3.ZERO)
	var neck := _pivot(root, Vector3(0, 0.6, 4.5), "neck")
	_block(neck, Vector3(2.2, 2.2, 2.6), Vector3(0, 0.4, 1.0))
	_block(neck, Vector3(3.4, 2.8, 3.8), Vector3(0, 1.2, 3.6))
	_eyes(neck, 1.7, 5.55, 0.9, 0.7)
	var horn := _color(Color("efe6cf"))
	for sx in [-1.0, 1.0]:
		var hn := _soft(neck, Vector3(0.5, 1.6, 0.5), Vector3(sx * 1.1, 3.1, 2.8), horn)
		hn.rotation.x = -0.6
	var tail := _pivot(root, Vector3(0, 0, -4.5), "tail")
	_block(tail, Vector3(3.0, 2.2, 4.0), Vector3(0, 0, -2.0))
	var tail2 := _pivot(tail, Vector3(0, 0, -4.0), "tail2")
	_block(tail2, Vector3(1.8, 1.4, 3.6), Vector3(0, 0, -1.8))
	_block(tail2, Vector3(1.0, 0.9, 2.6), Vector3(0, 0, -4.6))
	for sx in [-1.0, 1.0]:
		var wing := _pivot(root, Vector3(sx * 3.0, 1.2, 0.5), "wing_" + str(sx))
		_block(wing, Vector3(7.0, 0.6, 5.5), Vector3(sx * 3.5, 0, 0))
		var outer := _pivot(wing, Vector3(sx * 7.0, 0, 0), "wing2_" + str(sx))
		_block(outer, Vector3(6.0, 0.45, 4.2), Vector3(sx * 3.0, 0, -0.6))
		_soft(root, Vector3(1.0, 2.0, 1.0), Vector3(sx * 1.6, -2.8, 1.0), horn)    # legs tucked under


func _build_roller() -> void:
	var r := 4.2
	var root := _pivot(self, Vector3.ZERO, "root")
	var wheel := _pivot(root, Vector3(0, r, 0), "wheel")
	for k in 3:                              # three rotated blocks make a chunky 12-sided boulder
		var blk := _block(wheel, Vector3(3.4, 2.0 * r * 0.93, 2.0 * r * 0.93), Vector3.ZERO)
		blk.rotation.x = k * PI / 6.0
	var head := _pivot(root, Vector3(0, 2.0 * r + 0.6, 1.4), "head")   # its head peeks out on top
	_block(head, Vector3(3.2, 2.4, 2.8), Vector3.ZERO)
	_eyes(head, 0.2, 1.5, 0.75, 0.6)
	for sx in [-1.0, 1.0]:                   # little arms hugging the ball
		_block(root, Vector3(1.2, 1.2, 3.0), Vector3(sx * 2.0, 2.0 * r - 0.6, 2.2))


func _build_burrower() -> void:
	var root := _pivot(self, Vector3.ZERO, "root")
	var mound := _pivot(root, Vector3.ZERO, "mound")   # the moving mound while it is underground
	var rock := _color(Color(def.get("body", Color("4a3a3a"))).darkened(0.2))
	for k in 6:
		var a := k * TAU / 6.0
		_soft(mound, Vector3(1.6, 1.0 + 0.4 * (k % 3), 1.6), Vector3(cos(a) * 1.8, 0.3, sin(a) * 1.8), rock)
	var worm := _pivot(root, Vector3(0, -14, 0), "worm")
	var dark := "blockbits/stone_dark"
	for k in 4:                               # segments, alternating textures
		_block(worm, Vector3(2.3, 2.6, 2.3), Vector3(0, 1.3 + 2.6 * k, 0), _tex() if k % 2 else dark)
	var head := _pivot(worm, Vector3(0, 11.6, 0), "head")
	_block(head, Vector3(2.8, 3.0, 2.8), Vector3(0, 1.5, 0))
	_eyes(head, 2.1, 1.45, 0.65, 0.55)
	var tooth := _color(Color("efe6cf"))
	for sx in [-1.0, 1.0]:
		_soft(head, Vector3(0.45, 0.9, 0.45), Vector3(sx * 0.7, 0.2, 1.5), tooth)


func _build_twins() -> void:
	for sx in [-1.0, 1.0]:
		var twin := _pivot(self, Vector3(sx * 7.5, 0, 0), "twin_" + str(sx))
		_block(twin, Vector3(5.0, 5.0, 5.0), Vector3(0, 6.5, 0))
		_eyes(twin, 7.4, 2.6, 1.1, 0.8)
		var horn := _color(Color("efe6cf"))
		_soft(twin, Vector3(0.8, 1.8, 0.8), Vector3(-sx * 1.6, 9.6, 0), horn)
		for lx in [-1.0, 1.0]:
			var leg := _pivot(twin, Vector3(lx * 1.4, 0, 0), "leg_%s_%s" % [sx, lx])
			_block(leg, Vector3(1.7, 4.0, 2.2), Vector3(0, 2.0, 0))
			var arm := _pivot(twin, Vector3(lx * 3.1, 8.0, 0), "arm_%s_%s" % [sx, lx])
			_block(arm, Vector3(1.3, 3.6, 1.3), Vector3(0, -1.8, 0))


# --- Animation ------------------------------------------------------------------

func on_attack() -> void:
	attack_t = 0.6
	surface_t = 1.8
	side = -side


## Where a throw starts (x across the track, height), in the boss's frame.
func throw_origin() -> Vector2:
	match arch:
		"flyer":
			return Vector2(0.0, parts["root"].position.y)
		"roller":
			return Vector2(drift_x, 8.0)
		"burrower":
			return Vector2(drift_x, maxf(2.0, parts["worm"].position.y + 13.0))
		"twins":
			return Vector2(side * 7.5, 7.0)      # the twin that is attacking
	return Vector2(0.0, Config.BOSS_LIFT + Config.BOSS_SIZE * 0.5)


func animate(dt: float, speed: float, enraged: bool) -> void:
	t += dt * (1.5 if enraged else 1.0)
	attack_t = maxf(0.0, attack_t - dt)
	surface_t = maxf(0.0, surface_t - dt)
	var pu := smoothstep(0.0, 1.0, pass_u)
	match arch:
		"gate_walker":
			var root: Node3D = parts["root"]
			root.position.y = absf(sin(t * 1.6)) * 0.5
			root.rotation.z = 0.04 * sin(t * 1.6)
			for sx in [-1.0, 1.0]:
				var arm: Node3D = parts["arm_" + str(sx)]
				var swing := 0.35 * sin(t * 1.6 + (0.0 if sx > 0.0 else PI))
				if attack_t > 0.0 and sx > 0.0:
					swing = -2.4 * sin(PI * attack_t / 0.6)    # the throwing arm swings up and over
				arm.rotation.x = swing
				for k in 2:
					parts["leg_%s_%d" % [sx, k]].position.y = maxf(0.0, sin(t * 1.6 + (0.0 if sx > 0.0 else PI))) * 0.6
		"flyer":
			var root: Node3D = parts["root"]
			var beat := 6.0 + (4.0 if attack_t > 0.0 else 0.0)
			var flap := sin(t * beat)
			root.position.y = lerpf(10.0, 3.3, pu) + 0.8 * flap * (1.0 - pu)
			root.position.z = swoop_z
			root.rotation.x = lerpf(0.06 * sin(t * beat + 1.0), 0.15, pu)
			for sx in [-1.0, 1.0]:
				parts["wing_" + str(sx)].rotation.z = sx * 0.55 * flap
				parts["wing2_" + str(sx)].rotation.z = sx * 0.4 * sin(t * beat - 0.7)
			parts["tail"].rotation.y = 0.25 * sin(t * 1.8)
			parts["tail2"].rotation.y = 0.35 * sin(t * 1.8 - 0.8)
			parts["neck"].rotation.x = -0.35 if attack_t > 0.0 else 0.08 * sin(t * 2.0)
		"roller":
			drift_x = lerpf(0.0, Config.lane_x(pass_lane) + 0.5 * signf(pass_lane), pu)
			parts["root"].position.x = drift_x
			parts["root"].position.y = absf(sin(t * 2.4)) * 0.6 + (1.2 * sin(PI * attack_t / 0.6) if attack_t > 0.0 else 0.0)
			parts["wheel"].rotation.x -= dt * speed / 4.2
			parts["head"].rotation.z = 0.12 * sin(t * 2.4)
		"burrower":
			var up := surface_t > 0.0 or pass_u > 0.0
			drift_x = lerpf(drift_x, Config.lane_x(pass_lane) if pass_u > 0.0 else 0.0, minf(1.0, dt * 4.0))
			var worm: Node3D = parts["worm"]
			var target := -1.5 if up else -14.0
			worm.position.y = lerpf(worm.position.y, target, minf(1.0, dt * (9.0 if up else 3.0)))
			worm.position.x = drift_x
			worm.rotation.z = 0.08 * sin(t * 3.0)
			worm.rotation.x = 0.1 * sin(t * 2.3)
			parts["head"].rotation.x = -0.4 if attack_t > 0.0 else 0.1 * sin(t * 2.0)
			var mound: Node3D = parts["mound"]
			mound.position.x = drift_x
			mound.position.y = 0.25 * absf(sin(t * 7.0)) - (0.0 if worm.position.y < -8.0 else 0.6)
			mound.rotation.y += dt * 1.5
		"twins":
			for sx in [-1.0, 1.0]:
				var twin: Node3D = parts["twin_" + str(sx)]
				var bob := sin(t * 2.0 + (0.0 if sx > 0.0 else PI))
				twin.position.x = sx * lerpf(7.5, 4.3, pu)          # step in over the outer lanes
				twin.position.y = maxf(0.0, bob) * 0.5
				twin.rotation.z = -sx * 0.08 * pu + 0.04 * bob
				for lx in [-1.0, 1.0]:
					var arm: Node3D = parts["arm_%s_%s" % [sx, lx]]
					var throwing: bool = attack_t > 0.0 and side == sx
					arm.rotation.x = -2.2 * sin(PI * attack_t / 0.6) if throwing and lx == -sx else 0.3 * bob * lx
