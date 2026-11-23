class_name Kit
extends RefCounted
## The game's shared look: soft blocks (boxes with bevelled edges, like toy blocks) and
## low-poly models from the KayKit packs (CC0, assets/kit/). Meshes and materials are cached.

static var _soft := {}        # "size,bevel" -> ArrayMesh
static var _models := {}      # "pack/name" -> {"mesh", "aabb", "xf"}
static var _mats := {}        # "pack/name|tint|flat" -> Material


## A box with bevelled edges and corners (26 flat faces). bevel < 0: chosen from the size.
static func soft_box(size: Vector3, bevel := -1.0) -> ArrayMesh:
	var b := bevel if bevel >= 0.0 else minf(0.09, minf(size.x, minf(size.y, size.z)) * 0.22)
	var key := "%.3f,%.3f,%.3f,%.3f" % [size.x, size.y, size.z, b]
	if _soft.has(key):
		return _soft[key]
	var h := size / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Corner point on the face of `axis`, for the corner with signs s.
	var pt := func(s: Vector3, axis: int) -> Vector3:
		var v := Vector3(s.x * (h.x - b), s.y * (h.y - b), s.z * (h.z - b))
		v[axis] = s[axis] * h[axis]
		return v
	var poly := func(pts: Array) -> void:
		var c := Vector3.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
		if n.dot(c) > 0.0:          # Godot draws clockwise faces: wind so the cross points inward
			pts.reverse()
		else:
			n = -n
		for i in range(1, pts.size() - 1):
			for p in [pts[0], pts[i], pts[i + 1]]:
				st.set_normal(n)
				st.add_vertex(p)
	var ring := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for axis in 3:
		var u := (axis + 1) % 3
		var w := (axis + 2) % 3
		for s in [-1.0, 1.0]:
			var face := []
			for r in ring:
				var sv := Vector3.ZERO
				sv[axis] = s
				sv[u] = r.x
				sv[w] = r.y
				face.append(pt.call(sv, axis))
			poly.call(face)                                # main face
			for s2 in [-1.0, 1.0]:                         # edge strip between face `axis` and face `u`
				var a := Vector3.ZERO
				a[axis] = s
				a[u] = s2
				a[w] = -1.0
				var c2 := a
				c2[w] = 1.0
				poly.call([pt.call(a, axis), pt.call(c2, axis), pt.call(c2, u), pt.call(a, u)])
	for sx in [-1.0, 1.0]:                                 # corner triangles
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var sv := Vector3(sx, sy, sz)
				poly.call([pt.call(sv, 0), pt.call(sv, 1), pt.call(sv, 2)])
	var mesh := st.commit()
	_soft[key] = mesh
	return mesh


## The mesh of a KayKit model ("forest/Tree_2_A_Color1"), its bounds and node transform.
static func model(name: String) -> Dictionary:
	if not _models.has(name):
		var scene: Node = load("res://assets/kit/%s.gltf" % name).instantiate()
		var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var xf: Transform3D = mi.transform
		var p := mi.get_parent()
		while p and p != scene:
			xf = p.transform * xf
			p = p.get_parent()
		_models[name] = {"mesh": mi.mesh, "aabb": xf * mi.mesh.get_aabb(), "xf": xf}
		scene.free()
	return _models[name]


## Material for a model: its own (textured) one, tinted (multiplied), or one flat colour.
static func material(name: String, tint := Color.WHITE, flat := false) -> Material:
	var key := "%s|%s|%s" % [name, tint.to_html(), flat]
	if not _mats.has(key):
		var src: Material = model(name)["mesh"].surface_get_material(0)
		var m: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		m.albedo_color = tint
		if flat:
			m.albedo_texture = null
		m.roughness = 0.85
		_mats[key] = m
	return _mats[key]


## A model instance fitted into `size` (centred). uniform: keep its proportions (fit inside).
static func node(name: String, size: Vector3, tint := Color.WHITE, flat := false, uniform := false) -> Node3D:
	var info := model(name)
	var aabb: AABB = info["aabb"]
	var k := size / aabb.size
	if uniform:
		var m := minf(k.x, minf(k.y, k.z))
		k = Vector3(m, m, m)
	var mi := MeshInstance3D.new()
	mi.mesh = info["mesh"]
	mi.material_override = material(name, tint, flat)
	mi.transform = Transform3D(Basis.from_scale(k), -aabb.get_center() * k) * info["xf"]
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder
