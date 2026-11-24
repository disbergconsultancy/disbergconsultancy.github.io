class_name Planet
extends Node3D
## The globe the runner runs around. It rotates around the X axis while the player
## stays on top. Everything on it is placed by (phi = globe-local angle, x = sideways
## offset, y = height above the track). `build(theme)` rebuilds it for another planet.

var radius := 45.0
var items: Array[Item] = []
var theme: Dictionary = {}
var _mats := {}
var _world: Node3D              # globe, road and scenery (rebuilt per planet)

# Scenery props: parts of [mesh, colour, position, scale, rotation (degrees), glow].
const PROPS := {
	"tree": [["cyl6", "8a5a3a", Vector3(0, 0.6, 0), Vector3(0.16, 1.2, 0.16)], ["ico", "5fae4e", Vector3(0, 1.75, 0), Vector3(0.9, 1.0, 0.9)]],
	"tree2": [["cyl6", "8a5a3a", Vector3(0, 0.5, 0), Vector3(0.14, 1.0, 0.14)], ["ico", "8bc34a", Vector3(0, 1.45, 0), Vector3(0.75, 0.8, 0.75)]],
	"pine": [["cyl6", "7a4e30", Vector3(0, 0.3, 0), Vector3(0.12, 0.6, 0.12)], ["cone6", "2f7a4a", Vector3(0, 1.15, 0), Vector3(0.8, 1.3, 0.8)], ["cone6", "3a8c55", Vector3(0, 1.85, 0), Vector3(0.58, 1.0, 0.58)]],
	"rock": [["octa", "9a9a9a", Vector3(0, 0.2, 0), Vector3(0.7, 0.5, 0.6)]],
	"house": [["box", "f3ead8", Vector3(0, 0.55, 0), Vector3(1.4, 1.1, 1.2)], ["cone4", "c0533a", Vector3(0, 1.5, 0), Vector3(1.2, 0.8, 1.05), Vector3(0, 45, 0)], ["box", "6b4a33", Vector3(0, 0.3, 0.61), Vector3(0.3, 0.6, 0.04)]],
	"bush": [["ico", "4e9a45", Vector3(0, 0.25, 0), Vector3(0.55, 0.45, 0.55)]],
	"cactus": [["cyl6", "5f9b4a", Vector3(0, 0.8, 0), Vector3(0.22, 1.6, 0.22)], ["cyl6", "5f9b4a", Vector3(0.32, 1.1, 0), Vector3(0.12, 0.55, 0.12)], ["cyl6", "5f9b4a", Vector3(-0.3, 0.85, 0), Vector3(0.12, 0.45, 0.12)], ["box", "5f9b4a", Vector3(0.2, 0.85, 0), Vector3(0.3, 0.12, 0.12)]],
	"pyramid": [["cone4", "d9b56a", Vector3(0, 1.2, 0), Vector3(2.2, 2.4, 2.2), Vector3(0, 45, 0)]],
	"palm": [["cyl6", "9a6b40", Vector3(0, 1.2, 0), Vector3(0.12, 2.4, 0.12), Vector3(0, 0, 7)], ["ico", "4f9e3f", Vector3(0.15, 2.45, 0), Vector3(1.1, 0.25, 1.1)]],
	"mesa": [["cyl6", "b5703a", Vector3(0, 0.6, 0), Vector3(1.3, 1.2, 1.3)], ["cyl6", "c98450", Vector3(0, 1.25, 0), Vector3(1.15, 0.1, 1.15)]],
	"dune": [["hemi", "e8c98a", Vector3(0, -0.1, 0), Vector3(1.8, 0.7, 1.4)]],
	"spike": [["cone5", "bfe6ff", Vector3(0, 1.0, 0), Vector3(0.4, 2.0, 0.4), Vector3.ZERO, 0.15], ["cone5", "d9f1ff", Vector3(0.35, 0.6, 0.1), Vector3(0.25, 1.2, 0.25), Vector3.ZERO, 0.15]],
	"snowpine": [["cone6", "2f5a4a", Vector3(0, 0.9, 0), Vector3(0.8, 1.4, 0.8)], ["cone6", "ffffff", Vector3(0, 1.7, 0), Vector3(0.5, 0.7, 0.5)]],
	"igloo": [["hemi", "f4fbff", Vector3(0, 0, 0), Vector3(0.9, 0.85, 0.9)], ["box", "9cc3df", Vector3(0, 0.22, 0.82), Vector3(0.36, 0.44, 0.3)]],
	"ice_rock": [["octa", "9cc3df", Vector3(0, 0.4, 0), Vector3(0.6, 0.8, 0.6)]],
	"snowman": [["ico", "ffffff", Vector3(0, 0.35, 0), Vector3(0.4, 0.4, 0.4)], ["ico", "ffffff", Vector3(0, 0.9, 0), Vector3(0.28, 0.28, 0.28)], ["cone4", "ff8a2a", Vector3(0, 0.92, -0.3), Vector3(0.06, 0.25, 0.06), Vector3(-90, 0, 0)]],
	"volcano": [["frustum", "3a2a2a", Vector3(0, 1.0, 0), Vector3(1.6, 2.0, 1.6)], ["cyl6", "ff5a1f", Vector3(0, 2.0, 0), Vector3(0.45, 0.06, 0.45), Vector3.ZERO, 1.5]],
	"shard": [["octa", "5a2a6a", Vector3(0, 0.8, 0), Vector3(0.35, 1.2, 0.35), Vector3.ZERO, 0.3], ["octa", "7a3a8a", Vector3(0.3, 0.45, 0), Vector3(0.2, 0.7, 0.2), Vector3.ZERO, 0.3]],
	"deadtree": [["box", "2a1e1e", Vector3(0, 0.7, 0), Vector3(0.12, 1.4, 0.12)], ["box", "2a1e1e", Vector3(0.18, 1.1, 0), Vector3(0.08, 0.6, 0.08), Vector3(0, 0, -40)]],
	"lava": [["cyl6", "ff6a1f", Vector3(0, 0.02, 0), Vector3(0.9, 0.05, 0.9), Vector3.ZERO, 1.5]],
	"ash_rock": [["octa", "4a3a3a", Vector3(0, 0.25, 0), Vector3(0.7, 0.55, 0.6)]],
}
## Scenery models from the KayKit Forest pack: [model, height in m, tint (multiplied), flat colour?].
const MODEL_PROPS := {
	"f_tree1": ["forest/Tree_1_A_Color1", 2.4, Color.WHITE, false],
	"f_tree1b": ["forest/Tree_1_B_Color1", 2.8, Color.WHITE, false],
	"f_tree2": ["forest/Tree_2_A_Color1", 2.6, Color.WHITE, false],
	"f_tree2e": ["forest/Tree_2_E_Color1", 3.2, Color.WHITE, false],
	"f_tree3": ["forest/Tree_3_A_Color1", 2.2, Color.WHITE, false],
	"f_pine": ["forest/Tree_4_A_Color1", 2.8, Color.WHITE, false],
	"f_bush": ["forest/Bush_1_D_Color1", 0.8, Color.WHITE, false],
	"f_bush3": ["forest/Bush_3_A_Color1", 0.5, Color.WHITE, false],
	"f_rock": ["forest/Rock_1_E_Color1", 0.9, Color.WHITE, false],
	"f_rock2": ["forest/Rock_3_A_Color1", 0.7, Color.WHITE, false],
	"f_grass": ["forest/Grass_1_C_Color1", 0.45, Color.WHITE, false],
	"f_acacia": ["forest/Tree_3_C_Color1", 2.4, Color("c8d27a"), false],
	"f_sandrock": ["forest/Rock_2_E_Color1", 1.6, Color("e0a868"), false],
	"f_sandrock2": ["forest/Rock_1_J_Color1", 1.3, Color("d9a060"), false],
	"f_drygrass": ["forest/Grass_1_C_Color1", 0.45, Color("d8c070"), false],
	"f_frostpine": ["forest/Tree_4_A_Color1", 2.8, Color("bfe4ff"), false],
	"f_icerock": ["forest/Rock_3_K_Color1", 1.0, Color("bfe0ff"), true],
	"f_snowrock": ["forest/Rock_1_E_Color1", 0.9, Color("eef6ff"), true],
	"f_bare": ["forest/Tree_Bare_1_A_Color1", 1.8, Color("2a1e1e"), true],
	"f_bare2": ["forest/Tree_Bare_2_A_Color1", 2.4, Color("33241f"), true],
	"f_ashrock": ["forest/Rock_1_A_Color1", 0.8, Color("4a3a3a"), true],
	"f_ashrock2": ["forest/Rock_3_E_Color1", 0.9, Color("3a2e2e"), true],
}
## Power-up models (Platformer pack).
const POWER_MODELS := {"magnet": "platformer/power_blue", "shield": "platformer/heart_green",
	"orbit": "platformer/star_yellow", "x2": "platformer/diamond_red"}
const TERRAIN_AMP := 4.3
const WATER_H := -1.1


func build(th: Dictionary) -> void:
	theme = th
	radius = th["radius"]
	if _world:
		_world.queue_free()
	_world = Node3D.new()
	add_child(_world)
	_world.add_child(_build_globe())
	# Road: a band (cylinder) around the equator, with raised curbs and lane dashes.
	var road_glow := 0.8 if th["glow_road"] else 0.0
	_world.add_child(_ring(radius, Config.TRACK_HALF * 2.0, mat(th["track"])))
	for side in [-1.0, 1.0]:
		var curb := _ring(radius + 0.12, 0.3, mat(th["curb"], road_glow))
		curb.position.x = side * (Config.TRACK_HALF + 0.1)
		_world.add_child(curb)
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.1, 0.03, 1.2)
	var n := 96
	for i in n:
		for side in [-0.5, 0.5]:
			var d := MeshInstance3D.new()
			d.mesh = dash_mesh
			d.material_override = mat(th["dash"], road_glow * 0.75)
			_world.add_child(d)
			place(d, TAU * i / n, side * Config.LANE_W, 0.02)
	_build_roadside()
	_build_props()


## Cones along the curbs and a few flags in the planet's colour (Platformer pack).
func _build_roadside() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + int(radius)
	var flag: String = theme.get("flag", "red")
	var sets := {"platformer/cone_red": [], "platformer/cone_yellow": [], "platformer/flag_A_" + flag: []}
	var n := int(TAU * radius / 9.0)
	for i in n:
		var phi := TAU * (i + rng.randf() * 0.6) / n
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var kind := "platformer/flag_A_" + flag if i % 7 == 3 else ("platformer/cone_red" if rng.randf() < 0.5 else "platformer/cone_yellow")
		var hgt := 1.9 if kind.contains("flag") else 0.55
		var x := side * (Config.TRACK_HALF + (0.75 if kind.contains("flag") else 0.55))
		var b := Basis(Vector3.RIGHT, -phi)
		sets[kind].append([Transform3D(b, b * Vector3(x, radius + 0.1, 0.0)), hgt, rng.randf() * TAU])
	for kind in sets:
		_multimesh(kind, sets[kind], Color.WHITE, false)


## One MultiMesh for many copies of a model. items: [base transform, height, spin].
func _multimesh(name: String, items: Array, tint: Color, flat: bool) -> void:
	if items.is_empty():
		return
	var info := Kit.model(name)
	var aabb: AABB = info["aabb"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = info["mesh"]
	mm.instance_count = items.size()
	for i in items.size():
		var k: float = items[i][1] / aabb.size.y
		var local := Transform3D(Basis(Vector3.UP, items[i][2]).scaled(Vector3.ONE * k),
			Basis(Vector3.UP, items[i][2]) * Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z) * k)
		mm.set_instance_transform(i, items[i][0] * local * info["xf"])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Kit.material(name, tint, flat)
	_world.add_child(mmi)


## Terrain height in metres at a direction on the globe: hills and lakes, always
## sunk a little below the road near the track.
func terrain_h(v: Vector3) -> float:
	var h := 0.6 * sin(3.1 * v.x + 1.3) * sin(2.3 * v.y + 0.7) * sin(2.9 * v.z + 2.2) \
		+ 0.4 * sin(7.1 * v.x + 0.4) * sin(6.3 * v.y + 1.9) * sin(5.7 * v.z + 0.2)
	h *= TERRAIN_AMP
	var t := smoothstep(0.0, 4.0, absf(v.x) * radius - (Config.TRACK_HALF + 0.5))
	return h * t - 0.35 * (1.0 - t)


## A bumpy low-poly globe with flat-shaded colour patches (grass, hills, water).
func _build_globe() -> MeshInstance3D:
	var th := theme
	var pr := radius - 0.3
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 64
	sm.rings = 32
	var arrays := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in range(0, idx.size(), 3):
		var ps: Array[Vector3] = []
		var hsum := 0.0
		var near := false
		for k in 3:
			var v: Vector3 = verts[idx[f + k]].normalized()
			var h := maxf(terrain_h(v), WATER_H)
			hsum += h
			near = near or absf(v.x) * pr < Config.TRACK_HALF + 1.2
			ps.append(v * (pr + h))
		var ha := hsum / 3.0
		var col: Color
		if ha <= WATER_H + 0.05:
			col = th["water"]
		elif ha < WATER_H + 0.45:
			col = th["shore"]
		elif ha < 0.5 or near:
			col = th["ground"][0]
		elif ha < 1.6:
			col = th["ground"][1]
		else:
			col = th["ground"][2]
		col = col.darkened(((f * 7919) % 13) / 200.0)   # patchwork variation per facet
		for k in 3:
			st.set_color(col)
			st.add_vertex(ps[k])
	st.generate_normals()      # vertices are not shared, so normals stay flat per facet
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	if th["glow_road"]:          # Ember: lava glows
		m.emission_enabled = true
		m.emission = Color("401000")
	mi.material_override = m
	return mi


func _ring(r: float, width: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = width
	cm.radial_segments = 160
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	mi.rotation.z = PI / 2.0   # cylinder axis along X
	return mi


func _prop_mesh(kind: String) -> PrimitiveMesh:
	match kind:
		"box":
			return BoxMesh.new()
		"cyl6", "cone4", "cone5", "cone6", "frustum":
			var c := CylinderMesh.new()
			c.height = 1.0
			c.bottom_radius = 1.0
			c.top_radius = 0.0 if kind.begins_with("cone") else 0.3 if kind == "frustum" else 1.0
			c.radial_segments = int(kind.right(1)) if kind.begins_with("cone") or kind == "cyl6" else 7
			c.rings = 1
			return c
		"hemi":
			var h := SphereMesh.new()
			h.radius = 1.0
			h.height = 1.0
			h.is_hemisphere = true
			h.radial_segments = 8
			h.rings = 3
			return h
		"octa":
			var o := SphereMesh.new()
			o.radius = 1.0
			o.height = 2.0
			o.radial_segments = 4
			o.rings = 2
			return o
		_:
			var s := SphereMesh.new()   # "ico": low-poly ball
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 6
			s.rings = 3
			return s


## Scenery from the planet's kit, one MultiMesh per prop part (cheap to draw).
## Fixed seed per planet, so every lap looks the same.
func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + int(radius)
	var kit: Dictionary = theme["props"]
	var total := 0.0
	for w in kit.values():
		total += w
	var per_part := {}   # "prop/index" -> Array[Transform3D]
	var model_sets := {} # model prop -> [[transform, height, spin]]
	var placed := 0
	var guard := 0
	while placed < 340 and guard < 6000:
		guard += 1
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if v.length() < 0.1 or v.length() > 1.0:
			continue
		v = v.normalized()
		var s := rng.randf_range(0.7, 1.6)
		if absf(v.x) * radius < Config.TRACK_HALF + 0.9 + s * 0.9:
			continue                     # keep the road clear
		if terrain_h(v) <= WATER_H + 0.1:
			continue                     # not in the water
		var roll := rng.randf() * total
		var name: String = kit.keys()[0]
		for k in kit:
			roll -= kit[k]
			if roll < 0.0:
				name = k
				break
		var b := Basis(Quaternion(Vector3.UP, v)) * Basis(Vector3.UP, rng.randf() * TAU)
		var base := Transform3D(b.scaled_local(Vector3.ONE * s), v * (radius - 0.3 + terrain_h(v) - 0.05))
		if MODEL_PROPS.has(name):
			if not model_sets.has(name):
				model_sets[name] = []
			model_sets[name].append([Transform3D(b, base.origin), MODEL_PROPS[name][1] * s, 0.0])
			placed += 1
			continue
		var parts: Array = PROPS[name]
		for i in parts.size():
			var part: Array = parts[i]
			var rot: Vector3 = part[4] if part.size() > 4 else Vector3.ZERO
			var local := Transform3D(Basis.from_euler(rot * PI / 180.0).scaled_local(part[3]), part[2])
			var key := "%s/%d" % [name, i]
			if not per_part.has(key):
				per_part[key] = []
			per_part[key].append(base * local)
		placed += 1
	for key in per_part:
		var pname: String = key.split("/")[0]
		var part: Array = PROPS[pname][int(key.split("/")[1])]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _prop_mesh(part[0])
		mm.instance_count = per_part[key].size()
		for i in per_part[key].size():
			mm.set_instance_transform(i, per_part[key][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(Color(part[1]), part[5] if part.size() > 5 else 0.0)
		_world.add_child(mmi)
	for name in model_sets:
		var mp: Array = MODEL_PROPS[name]
		_multimesh(mp[0], model_sets[name], mp[2], mp[3])


func mat(color: Color, glow := 0.0) -> StandardMaterial3D:
	var key := color.to_html() + str(glow)
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = color
			m.emission_energy_multiplier = glow
		_mats[key] = m
	return _mats[key]


## Put a node on the track at globe-local angle phi, sideways offset x, centre y above the surface.
func place(node: Node3D, phi: float, x: float, y_center: float) -> void:
	var b := Basis(Vector3.RIGHT, -phi)
	node.transform = Transform3D(b, b * Vector3(x, radius + y_center, 0.0))


func _box(size: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.soft_box(size)
	mi.material_override = mat(color, glow)
	return mi


static var _coin_meshes: Array = []


## A low-poly coin: a dark gold rim, a raised bright face on both sides and a slot in the
## middle (like the coin icon). It stands upright and spins around its vertical axis.
func _coin() -> Node3D:
	if _coin_meshes.is_empty():
		var rim := CylinderMesh.new()
		rim.top_radius = 0.26
		rim.bottom_radius = 0.26
		rim.height = 0.07
		rim.radial_segments = 12
		rim.rings = 1
		var face := CylinderMesh.new()
		face.top_radius = 0.2
		face.bottom_radius = 0.2
		face.height = 0.1
		face.radial_segments = 12
		face.rings = 1
		var slot := BoxMesh.new()
		slot.size = Vector3(0.06, 0.12, 0.2)
		_coin_meshes = [rim, face, slot]
	var holder := Node3D.new()
	var tilt := Node3D.new()                   # discs are made lying flat: stand them up
	tilt.rotation.x = PI / 2.0
	holder.add_child(tilt)
	var parts := [[_coin_meshes[0], mat(Color("c8901a"), 0.25)], [_coin_meshes[1], mat(Color("ffd34a"), 0.45)], [_coin_meshes[2], mat(Color("b07d10"), 0.2)]]
	for pm in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pm[0]
		mi.material_override = pm[1]
		tilt.add_child(mi)
	return holder


## Create an item and its visuals. opts: w, h, depth, y0 (all optional).
func add_item(kind: String, phi: float, x: float, opts := {}) -> Item:
	var k: Dictionary = Config.KIND[kind]
	var it := Item.new()
	var w: float = opts.get("w", 0.45 if kind == "COIN" else 0.7 if kind == "POWER" else Config.LANE_W * 0.85)
	var h: float = opts.get("h", k["h"])
	var depth: float = opts.get("depth", k["d"])
	it.kind = kind
	it.phi = phi
	it.x = x
	it.cx = x
	it.y0 = opts.get("y0", k["y0"])
	it.y1 = it.y0 + h
	it.hw = w / 2.0
	it.hd = depth / 2.0
	var color: Color = k["color"]
	match kind:
		"PLATFORM":
			# Split into segments so a long block follows the curve of the globe.
			var n := maxi(1, ceili(depth / 2.5))
			var seg := depth / n
			for i in n:
				it.parts.append({"node": Kit.node("platformer/platform_2x2x1_blue", Vector3(w, h, seg + 0.02), Color(0.62, 0.7, 0.88) if i % 2 else Color(0.56, 0.64, 0.82)), "dm": -depth / 2.0 + seg * (i + 0.5), "y": it.y0 + h / 2.0})
		"RAMP":
			var g := Kit.node("platformer/platform_slope_2x4x4_blue", Vector3(w, h, depth), Color(0.62, 0.7, 0.88))   # rises away from the player
			it.parts.append({"node": g, "dm": 0.0, "y": h / 2.0})
		"LOW":       # padded crate: jump over it
			it.parts.append({"node": Kit.node("platformer/barrier_1x1x1_yellow", Vector3(w, h, depth), Color(1.0, 0.68, 0.42)), "dm": 0.0, "y": it.y0 + h / 2.0})
		"WALL":      # two stacked red blocks: switch lane
			for i in 2:
				it.parts.append({"node": Kit.node("blockbits/decorative_block_red", Vector3(w, h / 2.0, depth)), "dm": 0.0, "y": it.y0 + h * (0.25 + 0.5 * i)})
		"PIT":
			it.parts.append({"node": _box(Vector3(w, h, depth), color, 1.2), "dm": 0.0, "y": 0.03})
		"COIN":
			it.parts.append({"node": _coin(), "dm": 0.0, "y": it.y0 + h / 2.0, "spin": true})
		"MARK":
			# Red warning marker on the track where a boss throw will land.
			var mm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(w, h, depth)
			mm.mesh = bm
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.2, 1, 0.4, 0.6) if opts.get("safe", false) else opts.get("tint", Color(1, 0.16, 0.16, 0.55))
			red.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mm.material_override = red
			it.parts.append({"node": mm, "dm": 0.0, "y": it.y0 + h / 2.0})
		"ROLLER":
			it.parts.append({"node": _box(Vector3(w, h, depth), color), "dm": 0.0, "y": it.y0 + h / 2.0})
			for yy in [0.35, h - 0.35]:
				it.parts.append({"node": _box(Vector3(w + 0.05, 0.16, depth + 0.05), Color("8a1a1a")), "dm": 0.0, "y": yy})
		"LAVA":
			# Segments so the 20 m stripe follows the curve; red warning look until it is armed.
			var n := maxi(1, ceili(depth / 2.5))
			var seg := depth / n
			for i in n:
				it.parts.append({"node": _box(Vector3(w, 0.06, seg + 0.02), color, 1.4), "dm": -depth / 2.0 + seg * (i + 0.5), "y": 0.03})
		"VINE":
			# Purple (slide) bar on posts, wrapped in green leaves.
			it.parts.append({"node": _box(Vector3(w, h, depth), color), "dm": 0.0, "y": it.y0 + h / 2.0})
			for yy in [it.y0 + 0.2, it.y0 + h - 0.25]:
				it.parts.append({"node": _box(Vector3(w + 0.08, 0.14, depth + 0.08), Color("3f9d3f")), "dm": 0.0, "y": yy})
			for sx in [-1.0, 1.0]:
				it.parts.append({"node": _box(Vector3(0.2, it.y0, 0.2), Color("2f7a2f")), "dm": 0.0, "y": it.y0 / 2.0, "dx": sx * (w / 2.0 - 0.12)})
		"ICE":
			var n2 := maxi(1, ceili(depth / 2.5))
			var seg2 := depth / n2
			for i in n2:
				it.parts.append({"node": _box(Vector3(w, 0.05, seg2 + 0.02), color, 0.6), "dm": -depth / 2.0 + seg2 * (i + 0.5), "y": 0.03})
		"SHOCK":
			it.parts.append({"node": _box(Vector3(w, h, depth), theme["boss"]["wave"], 1.0), "dm": 0.0, "y": it.y0 + h / 2.0})
		"POWER":
			it.power = opts.get("power", "magnet")
			it.parts.append({"node": Kit.node(POWER_MODELS[it.power], Vector3(w, h, depth) * 1.25, Color.WHITE, false, true), "dm": 0.0, "y": it.y0 + h / 2.0, "spin": true})
		_:
			it.parts.append({"node": _box(Vector3(w, h, depth), color), "dm": 0.0, "y": it.y0 + h / 2.0})
			_add_details(it, kind, w, h, depth)
	if opts.get("invisible", false):     # a hitbox only (the boss body is the visual)
		for p in it.parts:
			p["node"].free()
		it.parts.clear()
	for p in it.parts:
		add_child(p["node"])
	place_item(it)
	items.append(it)
	return it


## Shape details: same colour code everywhere, but each type has a recognisable form.
func _add_details(it: Item, kind: String, w: float, h: float, depth: float) -> void:
	var y0 := it.y0
	var band := func(yy: float, color: Color, bh: float) -> void:
		it.parts.append({"node": _box(Vector3(w + 0.05, bh, depth + 0.05), color), "dm": 0.0, "y": yy})
	match kind:
		"HIGH":      # a bar on two posts: clearly "go under"
			for sx in [-1.0, 1.0]:
				it.parts.append({"node": _box(Vector3(0.14, y0, 0.14), Color("8a3a8a")), "dm": 0.0, "y": y0 / 2.0, "dx": sx * (w / 2.0 - 0.07)})
			band.call(y0 + 0.08, Color.WHITE, 0.08)
		"MOVER", "SWEEPLOW":
			band.call(y0 + h * 0.5, Color.WHITE, 0.14 if kind == "MOVER" else 0.08)
		"SWEEPHIGH":   # a thrown bar that lands on two posts: slide under
			for sx in [-1.0, 1.0]:
				it.parts.append({"node": _box(Vector3(0.18, y0, 0.18), Color("8a3a8a")), "dm": 0.0, "y": y0 / 2.0, "dx": sx * (w / 2.0 - 0.1)})
			band.call(y0 + 0.08, Color.WHITE, 0.08)
		"FIST", "BLOCK":   # boulder / wall bands
			band.call(y0 + h - 0.15, Color("8a1a1a"), 0.18)
			band.call(y0 + 0.5, Color("8a1a1a"), 0.12)


## Lava stripe: a translucent red warning first, glowing lava once it is deadly.
func set_lava_armed(it: Item, armed: bool) -> void:
	var warn := StandardMaterial3D.new()
	warn.albedo_color = Color(1, 0.16, 0.16, 0.5)
	warn.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for p in it.parts:
		p["node"].material_override = mat(Config.KIND["LAVA"]["color"], 1.4) if armed else warn


## Ice stripe: pale frost first, solid glowing ice once it is active.
func set_ice_armed(it: Item, armed: bool) -> void:
	var frost := StandardMaterial3D.new()
	frost.albedo_color = Color(0.75, 0.95, 1.0, 0.45)
	frost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for p in it.parts:
		p["node"].material_override = mat(Config.KIND["ICE"]["color"], 0.6) if armed else frost


func place_item(it: Item) -> void:
	for p in it.parts:
		place(p["node"], it.phi + p["dm"] / radius, it.x + p.get("dx", 0.0), p["y"])


func hide_item(it: Item) -> void:
	it.alive = false
	for p in it.parts:
		p["node"].visible = false


func remove_item(it: Item) -> void:
	for p in it.parts:
		p["node"].queue_free()


func clear_items() -> void:
	for it in items:
		remove_item(it)
	items.clear()
