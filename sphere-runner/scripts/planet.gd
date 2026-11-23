class_name Planet
extends Node3D
## The globe the runner runs around. It rotates around the X axis while the player
## stays on top. Everything on it is placed by (phi = globe-local angle, x = sideways
## offset, y = height above the track).

var radius := Config.GLOBE_R
var items: Array[Item] = []
var _mats := {}


func build() -> void:
	var th: Dictionary = Config.THEME
	# Globe: low-poly sphere slightly inside the track.
	var globe := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius - 0.4
	sm.height = (radius - 0.4) * 2.0
	sm.radial_segments = 40
	sm.rings = 20
	globe.mesh = sm
	globe.material_override = mat(th["ground"][1])
	add_child(globe)

	# Track: a band (cylinder) around the equator, with raised curbs.
	add_child(_ring(radius, Config.TRACK_HALF * 2.0, mat(th["track"])))
	for side in [-1.0, 1.0]:
		var curb := _ring(radius + 0.12, 0.3, mat(th["curb"]))
		curb.position.x = side * (Config.TRACK_HALF + 0.1)
		add_child(curb)

	# Lane dashes for a sense of speed.
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.1, 0.03, 1.2)
	var n := 96
	for i in n:
		for side in [-0.5, 0.5]:
			var d := MeshInstance3D.new()
			d.mesh = dash_mesh
			d.material_override = mat(th["dash"])
			add_child(d)
			place(d, TAU * i / n, side * Config.LANE_W, 0.02)

	_build_props()


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


## Trees, pines and rocks scattered over the globe (fixed seed, so every lap looks the same).
func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.16
	trunk.height = 1.2
	trunk.radial_segments = 6
	var crown := SphereMesh.new()
	crown.radius = 0.9
	crown.height = 1.8
	crown.radial_segments = 6
	crown.rings = 3
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 0.8
	pine.height = 2.0
	pine.radial_segments = 6
	var rock := SphereMesh.new()
	rock.radius = 0.6
	rock.height = 0.8
	rock.radial_segments = 5
	rock.rings = 2
	var parts := [
		{"mesh": trunk, "color": Color("8a5a3a"), "y": 0.6},
		{"mesh": crown, "color": Color("5fae4e"), "y": 1.7},
		{"mesh": pine, "color": Color("2f7a4a"), "y": 1.0},
		{"mesh": rock, "color": Color("9a9a9a"), "y": 0.3},
	]
	# Which parts make up each prop type.
	var types := [[0, 1], [2], [3]]
	var transforms := [[], [], [], []]
	var placed := 0
	while placed < 300:
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if v.length() < 0.1 or v.length() > 1.0:
			continue
		v = v.normalized()
		if absf(v.x) * radius < Config.TRACK_HALF + 2.0:
			continue
		var s := rng.randf_range(0.7, 1.5)
		var basis := Basis(Quaternion(Vector3.UP, v)).rotated(v, rng.randf() * TAU).scaled(Vector3.ONE * s)
		var t: Array = types[rng.randi() % types.size()]
		for pi in t:
			var origin: Vector3 = v * (radius - 0.45) + basis * Vector3(0, parts[pi]["y"], 0)
			transforms[pi].append(Transform3D(basis, origin))
		placed += 1
	for pi in parts.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = parts[pi]["mesh"]
		mm.instance_count = transforms[pi].size()
		for i in transforms[pi].size():
			mm.set_instance_transform(i, transforms[pi][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat(parts[pi]["color"])
		add_child(mmi)


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
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat(color, glow)
	return mi


## Create an item and its visuals. opts: w, h, depth, y0 (all optional).
func add_item(kind: String, phi: float, x: float, opts := {}) -> Item:
	var k: Dictionary = Config.KIND[kind]
	var it := Item.new()
	var w: float = opts.get("w", 0.45 if kind == "COIN" else Config.LANE_W * 0.85)
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
				var c := Color("5a6b8c") if i % 2 else Color("52617f")
				it.parts.append({"node": _box(Vector3(w, h, seg + 0.02), c), "dm": -depth / 2.0 + seg * (i + 0.5), "y": it.y0 + h / 2.0})
		"RAMP":
			var g := Node3D.new()
			var plank := _box(Vector3(w, 0.15, Vector2(depth, h).length()), color)
			plank.rotation.x = atan2(h, depth)   # rises away from the player
			g.add_child(plank)
			it.parts.append({"node": g, "dm": 0.0, "y": h / 2.0})
		"PIT":
			it.parts.append({"node": _box(Vector3(w, h, depth), color, 1.2), "dm": 0.0, "y": 0.03})
		"COIN":
			it.parts.append({"node": _box(Vector3(w, h, depth), color, 0.4), "dm": 0.0, "y": it.y0 + h / 2.0, "spin": true})
		_:
			it.parts.append({"node": _box(Vector3(w, h, depth), color), "dm": 0.0, "y": it.y0 + h / 2.0})
			_add_details(it, kind, w, h, depth)
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
		"LOW":       # crate: bands and a cross plank
			band.call(y0 + 0.07, Color("b8561a"), 0.14)
			band.call(y0 + h - 0.07, Color("b8561a"), 0.14)
			it.parts.append({"node": _box(Vector3(w * 0.18, h - 0.2, depth + 0.06), Color("b8561a")), "dm": 0.0, "y": y0 + h / 2.0})
		"HIGH":      # a bar on two posts: clearly "go under"
			for sx in [-1.0, 1.0]:
				it.parts.append({"node": _box(Vector3(0.14, y0, 0.14), Color("8a3a8a")), "dm": 0.0, "y": y0 / 2.0, "dx": sx * (w / 2.0 - 0.07)})
			band.call(y0 + 0.08, Color.WHITE, 0.08)
		"WALL":      # stacked layers
			var yy := 0.7
			while yy < h:
				band.call(yy, Color("a82020"), 0.09)
				yy += 0.7
		"MOVER":
			band.call(y0 + h * 0.5, Color.WHITE, 0.14)


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
