class_name TerrainDetail
extends Node3D
## Finmasket terræn med træer og sten tæt på overfladen. Under 300 m højde
## lægges et kvadrat (560 × 560 m) med ca. 7 gange finere masker ind under
## kameraet, og planetens grove overflade skæres væk lige der.
## Masken bygges i en baggrundstråd og skiftes ud, når den er færdig.

const N := 112
const SIZE := 940.0
const HOLE := 420.0
const ACTIVE_ALT := 460.0
const REBUILD_DIST := 110.0
const MAX_FLORA := 1400

var camera: Camera3D

var _mesh := MeshInstance3D.new()
var _flora := MultiMeshInstance3D.new()
var _rocks := MultiMeshInstance3D.new()
var _planet: PlanetBody
var _center := Vector3.INF
var _task := -1
var _result: Dictionary = {}
var _pending_planet: PlanetBody
var _pending_center: Vector3
var _mutex := Mutex.new()
## Hvor lang tid den seneste ombygning tog i baggrundstråden (til F9-visningen)
static var last_build_ms := 0.0


func _ready() -> void:
	# Indekseret maske (6 gange færre punkter at sende til grafikkortet) med flade
	# trekanter: normalen regnes i shaderen, og farven tages fra ét hjørne.
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain_flat.gdshader")
	_mesh.material_override = mat
	_mesh.visible = false
	add_child(_mesh)
	for spec: Array in [[_flora, _cone()], [_rocks, _rock()]]:
		var mmi: MultiMeshInstance3D = spec[0]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = spec[1]
		mm.instance_count = MAX_FLORA
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.visible = false
		mmi.extra_cull_margin = 1000.0
		add_child(mmi)


func _process(_delta: float) -> void:
	if camera == null or W.universe == null:
		return
	var cam := camera.global_position
	var pl := W.universe.nearest_planet(cam)
	var alt := pl.altitude(cam)
	if alt > ACTIVE_ALT:
		if _planet:
			_planet.set_hole(Vector3.ZERO, 0.0)
			_planet = null
			_center = Vector3.INF
		_mesh.visible = false
		_flora.visible = false
		_rocks.visible = false
		_finish_task()
		return
	var dir := (cam - pl.position).normalized()
	var surf := pl.position + dir * pl.radius
	if _task == -1 and (pl != _planet or surf.distance_to(_center) > REBUILD_DIST):
		_pending_planet = pl
		_pending_center = surf
		_task = WorkerThreadPool.add_task(_build.bind(pl, dir, pl.position))
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		_finish_task()


func _exit_tree() -> void:
	# Vent på en igangværende byggetråd, så den ikke rører en planet, der er ved at blive fjernet.
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _finish_task() -> void:
	if _task == -1:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_mutex.lock()
	var r := _result
	_result = {}
	_mutex.unlock()
	if r.is_empty() or _pending_planet == null:
		return
	if _planet and _planet != _pending_planet:
		_planet.set_hole(Vector3.ZERO, 0.0)
	_planet = _pending_planet
	_center = _pending_center
	_apply(r)
	_planet.set_hole(_center, HOLE)


## Kører i en baggrundstråd: beregner punkter, farver og flora. Rører ikke scenetræet.
func _build(pl: PlanetBody, cdir: Vector3, center: Vector3) -> void:
	var t0 := Time.get_ticks_usec()
	var n1 := N + 1
	var step := SIZE / N
	var e1 := cdir.cross(Vector3.UP if absf(cdir.y) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := cdir.cross(e1).normalized()
	var c := center + cdir * pl.radius
	var pts := PackedVector3Array()
	var hs := PackedFloat32Array()
	var dirs := PackedVector3Array()
	pts.resize(n1 * n1)
	hs.resize(n1 * n1)
	dirs.resize(n1 * n1)
	for j in n1:
		for i in n1:
			var d := (c + e1 * ((i - N / 2.0) * step) + e2 * ((j - N / 2.0) * step) - center).normalized()
			var h := pl.fine_height(d)
			var k := j * n1 + i
			hs[k] = h
			dirs[k] = d
			pts[k] = center + d * (pl.radius + maxf(h, 0.0))
	# Farver pr. punkt og indeks til trekanterne (samme omløbsretning overalt)
	var colors := PackedColorArray()
	colors.resize(n1 * n1)
	for k in n1 * n1:
		var col := pl.color_for(hs[k])
		if hs[k] > 0.0:
			var jitter := 0.88 + _hash(pts[k]) * 0.2
			col = Color(col.r * jitter, col.g * jitter, col.b * jitter)
		colors[k] = col
	var idx := PackedInt32Array()
	idx.resize(N * N * 6)
	var ccw := e1.cross(e2).dot(cdir) > 0.0
	var wi := 0
	for j in N:
		for i in N:
			var ia := j * n1 + i
			var ib := ia + 1
			var ic := ia + n1
			var id := ia + n1 + 1
			# Godot tegner forsider med uret set udefra.
			if ccw:
				idx[wi] = ia; idx[wi + 1] = ic; idx[wi + 2] = ib
				idx[wi + 3] = ib; idx[wi + 4] = ic; idx[wi + 5] = id
			else:
				idx[wi] = ia; idx[wi + 1] = ib; idx[wi + 2] = ic
				idx[wi + 3] = ib; idx[wi + 4] = id; idx[wi + 5] = ic
			wi += 6

	# Flora og sten
	var fl: Dictionary = pl.data.get("flora", {})
	var tree_xf: Array[Transform3D] = []
	var tree_col: Array[Color] = []
	var rock_xf: Array[Transform3D] = []
	var rock_col: Array[Color] = []
	if not fl.is_empty():
		var band: Array = fl["band"]
		var size: Array = fl["size"]
		var trees: Array = fl["tree"]
		var rocks: Array = fl["rock"]
		for j in range(1, N):
			for i in range(1, N):
				var k := j * n1 + i
				var h := hs[k]
				if h <= 0.6 or pl.in_flat_zone(dirs[k], 8.0) or pl.in_feature_clear(dirs[k]):
					continue
				var p := pts[k]
				var rr := _hash(p.snapped(Vector3(step, step, step)))
				if h > float(band[0]) and h <= float(band[1]) and rr < float(fl["density"]) and tree_xf.size() < MAX_FLORA:
					var sc := float(size[0]) + _hash(p * 1.7) * (float(size[1]) - float(size[0]))
					var w := sc * float(fl["width"])
					var b := Basis(Quaternion(Vector3.UP, dirs[k])) * Basis.from_scale(Vector3(w, sc, w))
					tree_xf.append(Transform3D(b, p - dirs[k] * 0.6))
					tree_col.append(Game.col(trees[int(rr * 997.0) % trees.size()]))
				elif rr > 1.0 - float(fl["rocks"]) and rock_xf.size() < MAX_FLORA:
					var sc := 0.8 + _hash(p * 2.3) * 2.4
					var b := Basis.from_euler(Vector3(rr * 10.0, rr * 20.0, rr * 30.0)) * Basis.from_scale(Vector3(sc, sc * 0.7, sc))
					rock_xf.append(Transform3D(b, p))
					rock_col.append(Game.col(rocks[int(rr * 991.0) % rocks.size()]))
	# Alt det tunge laves her i tråden, så hovedtråden kun skal skifte maske ud
	# (ellers hakker billedet, hver gang terrænet flytter sig under skibet).
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_mutex.lock()
	_result = {"mesh": mesh, "tree_buf": _buffer(tree_xf, tree_col), "tree_n": tree_xf.size(),
		"rock_buf": _buffer(rock_xf, rock_col), "rock_n": rock_xf.size()}
	_mutex.unlock()


## MultiMesh-data i ét stykke (transform 3×4 + farve pr. instans).
static func _buffer(xf: Array[Transform3D], cols: Array[Color]) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(MAX_FLORA * 16)
	for i in xf.size():
		var t := xf[i]
		var b := t.basis
		var o := i * 16
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = t.origin.z
		var c := cols[i]
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = c.a
	return buf


func _apply(r: Dictionary) -> void:
	_mesh.mesh = r["mesh"]
	_mesh.visible = true
	_fill(_flora, r["tree_buf"], r["tree_n"])
	_fill(_rocks, r["rock_buf"], r["rock_n"])


func _fill(mmi: MultiMeshInstance3D, buf: PackedFloat32Array, n: int) -> void:
	var mm := mmi.multimesh
	mm.buffer = buf
	mm.visible_instance_count = n
	mmi.visible = true


static func _hash(p: Vector3) -> float:
	var s := sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7) * 43758.5453
	return s - floorf(s)


static func _cone() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 1
	var arr := m.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		v.y += 0.5        # foden i origo
		verts[i] = v
	arr[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(0, _flora_mat())
	return out


static func _rock() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 5
	m.rings = 3
	m.material = _flora_mat()
	return m


static func _flora_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	return mat
