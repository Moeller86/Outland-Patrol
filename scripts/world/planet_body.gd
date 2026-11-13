class_name PlanetBody
extends Node3D
## En planet genereret fra data: lowpoly-overflade fra et seed, biomfarver,
## atmosfære, skyer, landingsplads med by og en lyssøjle.

const ATMO_TOP := 380.0       ## Atmosfærens højde på de store planeter (største værdi)
const BIG_RADIUS := 1500.0    ## Planeter med denne radius er "store" (k = 1)
const SUBDIVISIONS := 5

var data: Dictionary
var id: String
var system_id: String
var display_name: String
var radius: float
var amp: float
## Størrelsesfaktor: 1 for de store planeter, ca. 0,3 for de små. Atmosfæren,
## bjergenes højde og tætheden af småbakker skaleres med den.
var k := 1.0
var atmo_top := ATMO_TOP
var _freq := 3.8
var pad_dir: Vector3
var pad_h: float
var pad_top: Vector3        ## Landingsfladen (verdenskoordinater)
var tangent: Vector3        ## En fast vandret retning ved landingspladsen
var sky_color: Color
var surface_material: ShaderMaterial

var _off := Vector3.ZERO      ## Forskydning i støjen (planetens "seed"), som i browseren
var _biome: Array = []
var _town_lights: Array[MeshInstance3D] = []
## Landingssteder: [0] er hovedbyen, resten er mindre steder (mine, landbrug ...).
## {id, name, kind, style, dir, h, top, tangent, flat_in, flat_out}
var pads: Array[Dictionary] = []
var _city_roots: Array[Node3D] = []
## Landskabsdetaljer: vulkaner, kløfter, plateauer med vandfald og grotter.
## {type, dir, ...} – se _make_feature.
var features: Array[Dictionary] = []


func setup(d: Dictionary, system_origin: Vector3) -> void:
	data = d
	id = d["id"]
	system_id = d["system"]
	display_name = d["name"]
	name = "Planet_" + id
	radius = float(d["radius"])
	amp = float(d.get("amp", 1.0))
	k = clampf(radius / BIG_RADIUS, 0.25, 1.2)
	atmo_top = ATMO_TOP * clampf(k, 0.36, 1.0)
	_freq = lerpf(2.2, 3.8, clampf((k - 0.3) / 0.7, 0.0, 1.0))
	pad_h = float(d.get("pad_h", 18))
	position = d["world_pos"]
	sky_color = Game.col(d["sky"])
	if d.has("pad_dir"):
		pad_dir = Game.vec(d["pad_dir"]).normalized()
	else:
		# Landingspladsen vender mod systemets centrum, lidt opad.
		pad_dir = ((system_origin - position).normalized() + Vector3(0.15, 0.5, 0)).normalized()
	for b: Array in d["biome"]:
		_biome.append([float(b[0]), Game.col(b[1])])

	_off = Game.vec(d.get("noise_offset", [float(d["seed"]) * 0.1, 1.7, 7.3]))

	pad_top = position + pad_dir * (radius + pad_h + 1.6)
	tangent = pad_dir.cross(Vector3.UP)
	if tangent.length() < 0.01:
		tangent = pad_dir.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	# Hovedbyen får et stort fladt område til skyskraberne; de mindre steder et mindre.
	var city_r := minf(170.0, radius * 0.3)
	pads.append(_make_pad(id, display_name, "city", "city", pad_dir, pad_h, city_r))
	for o: Dictionary in d.get("outposts", []):
		var ang := float(o["dist"]) / radius
		var axis := tangent.rotated(pad_dir, deg_to_rad(float(o["bearing"])))
		var od := pad_dir.rotated(axis, ang).normalized()
		pads.append(_make_pad(o["id"], o["name"], "outpost", o["kind"], od, float(o.get("pad_h", 14)), 62.0))
	for f: Dictionary in d.get("features", []):
		features.append(_make_feature(f))


## Retning på overfladen `dist` meter fra hovedbyen i kompasretningen `bearing` (grader).
func dir_from_pad(dist: float, bearing: float) -> Vector3:
	var axis := tangent.rotated(pad_dir, deg_to_rad(bearing))
	return pad_dir.rotated(axis, dist / radius).normalized()


## Vandret retning (tangent) i punktet d, drejet `heading` grader.
func _heading_at(d: Vector3, heading: float) -> Vector3:
	var t := d.cross(Vector3.UP)
	if t.length() < 0.01:
		t = d.cross(Vector3.RIGHT)
	return t.normalized().rotated(d, deg_to_rad(heading))


func _make_feature(f: Dictionary) -> Dictionary:
	var out := f.duplicate()
	var c := dir_from_pad(float(f["dist"]), float(f["bearing"]))
	out["dir"] = c
	var base := maxf(_raw_height(c), 6.0)
	match str(f["type"]):
		"volcano":
			out["base_r"] = float(f.get("size", 480.0))
			out["height"] = float(f.get("height", 300.0))
			out["crater_r"] = out["base_r"] * 0.16
			out["reach"] = out["base_r"] + 10.0
		"mesa":
			out["r"] = float(f.get("size", 220.0))
			out["top"] = base + float(f.get("height", 110.0))
			out["reach"] = out["r"] + 40.0
		"canyon":
			var half := float(f.get("length", 1600.0)) / 2.0
			var hd := _heading_at(c, float(f.get("heading", 0.0)))
			var axis := c.cross(hd).normalized()
			out["a"] = c.rotated(axis, half / radius).normalized()
			out["b"] = c.rotated(axis, -half / radius).normalized()
			out["n"] = (out["a"] as Vector3).cross(out["b"]).normalized()
			out["width"] = float(f.get("width", 80.0))
			out["depth"] = float(f.get("depth", 110.0))
			out["reach"] = half + out["width"] * 2.5
		"cave":
			out["base_h"] = base
			out["r"] = 95.0
			out["reach"] = 150.0
			out["heading_dir"] = _heading_at(c, float(f.get("heading", 0.0)))
	out["cos_reach"] = cos(float(out["reach"]) / radius)
	return out


func _make_pad(pid: String, pname: String, kind: String, style: String, d: Vector3, h: float, flat_m: float) -> Dictionary:
	var t := d.cross(Vector3.UP)
	if t.length() < 0.01:
		t = d.cross(Vector3.RIGHT)
	t = t.normalized()
	return {"id": pid, "name": pname, "kind": kind, "style": style, "dir": d, "h": h,
		"top": position + d * (radius + h + 1.6), "tangent": t, "flat_m": flat_m,
		"flat_in": cos(flat_m / radius), "flat_out": cos((flat_m + 55.0) / radius)}


func pad_by_id(pid: String) -> Dictionary:
	for p in pads:
		if p["id"] == pid:
			return p
	return {}


## Ligger retningen d inden for et fladt byområde (plus en margin i meter)?
func in_flat_zone(d: Vector3, margin := 0.0) -> bool:
	for p in pads:
		if d.dot(p["dir"]) > cos((float(p["flat_m"]) + margin) / radius):
			return true
	return false


func _ready() -> void:
	_build_surface()
	_build_atmosphere()
	_build_clouds()
	_build_town()


## Terrænhøjde (meter over havniveau) i retningen d fra planetens centrum.
## Samme formel som browser-demoen.
func height_at(d: Vector3) -> float:
	var h := _raw_height(d)
	for f in features:
		var c := d.dot(f["dir"])
		if c < f["cos_reach"]:
			continue
		var s := acos(minf(c, 1.0)) * radius
		match str(f["type"]):
			"volcano":
				var br: float = f["base_r"]
				if s < br:
					h += float(f["height"]) * pow(1.0 - s / br, 1.6)
					var cr: float = f["crater_r"]
					if s < cr:
						h -= float(f["height"]) * 0.45 * (1.0 - (s / cr) * (s / cr))
			"mesa":
				h = lerpf(h, f["top"], smoothstep(float(f["r"]) + 30.0, float(f["r"]), s))
			"canyon":
				var cd := _canyon_dist(d, f)
				var w: float = f["width"]
				if cd < w * 2.4:
					var floor_h := 4.0 if f.get("dry", false) else -float(f["depth"]) * 0.12
					# Kløftens kanter hæves, så den altid er mindst `depth` dyb
					var rim := floor_h + float(f["depth"])
					h = maxf(h, lerpf(h, rim, 1.0 - smoothstep(w * 1.1, w * 2.4, cd)))
					if cd < w:
						var k := 1.0 - smoothstep(w * 0.35, w, cd)
						h = lerpf(h, minf(h, floor_h), k)
			"cave":
				h = lerpf(h, f["base_h"], smoothstep(float(f["r"]) + 40.0, float(f["r"]), s))
	for p in pads:
		var t := d.dot(p["dir"])
		if t > p["flat_out"]:
			h = lerpf(h, p["h"], smoothstep(p["flat_out"], p["flat_in"], t))
	return h


## Støjterrænet uden byer og landskabsdetaljer.
func _raw_height(d: Vector3) -> float:
	var h := (TerrainNoise.fbm(d.x * _freq + _off.x, d.y * _freq + _off.y, d.z * _freq + _off.z) - 0.47) * 420.0 * amp * maxf(k, 0.34)
	var sf := 24.0 * k
	h += (TerrainNoise.vnoise(d.x * sf + _off.y, d.y * sf, d.z * sf) - 0.5) * 22.0
	return h


## Afstand i meter fra retningen d til en kløfts midterlinje.
func _canyon_dist(d: Vector3, f: Dictionary) -> float:
	var n: Vector3 = f["n"]
	var a: Vector3 = f["a"]
	var b: Vector3 = f["b"]
	var proj := (d - n * d.dot(n)).normalized()
	# Ligger projektionen mellem a og b på storcirklen?
	if a.cross(proj).dot(n) >= 0.0 and proj.cross(b).dot(n) >= 0.0:
		return absf(asin(clampf(d.dot(n), -1.0, 1.0))) * radius
	return minf(acos(clampf(d.dot(a), -1.0, 1.0)), acos(clampf(d.dot(b), -1.0, 1.0))) * radius


## Skal flora og fund holdes væk herfra (grotter og vulkankratere)?
func in_feature_clear(d: Vector3) -> bool:
	for f in features:
		var c := d.dot(f["dir"])
		if c < f["cos_reach"]:
			continue
		var s := acos(minf(c, 1.0)) * radius
		match str(f["type"]):
			"cave":
				if s < 140.0:
					return true
			"volcano":
				if s < float(f["crater_r"]) * 1.4:
					return true
	return false


## Er punktet nede i et vulkankrater (lavasøen)?
func in_crater(pos: Vector3) -> bool:
	var d := (pos - position).normalized()
	for f in features:
		if f["type"] != "volcano":
			continue
		var s := acos(minf(d.dot(f["dir"]), 1.0)) * radius
		if s < float(f["crater_r"]) * 0.8 and ground_altitude(pos) < 40.0:
			return true
	return false


## Højde med de fine bump fra det detaljerede terræn (det man ser tæt på jorden).
func fine_height(d: Vector3) -> float:
	var h := height_at(d)
	if h <= 0.0:
		return h
	var flat := 1.0
	for p in pads:
		flat = minf(flat, 1.0 - smoothstep(p["flat_out"], p["flat_in"], d.dot(p["dir"])))
	var f1 := 210.0 * k
	var f2 := 630.0 * k
	return maxf(0.5, h + flat * ((TerrainNoise.vnoise(d.x * f1 + 9.0, d.y * f1, d.z * f1) - 0.5) * 8.0
		+ (TerrainNoise.vnoise(d.x * f2, d.y * f2 + 3.0, d.z * f2) - 0.5) * 3.0))


## Afstand fra centrum til overfladen (havet tæller som overflade).
func surface_radius(d: Vector3) -> float:
	return radius + maxf(height_at(d), 0.0)


## Som surface_radius, men med de fine bump. Bruges til kollision og højdemåler.
func fine_surface_radius(d: Vector3) -> float:
	return radius + maxf(fine_height(d), 0.0)


func altitude(world_pos: Vector3) -> float:
	return world_pos.distance_to(position) - radius


func ground_altitude(world_pos: Vector3) -> float:
	var rel := world_pos - position
	return rel.length() - fine_surface_radius(rel.normalized())


## Skjul den grove overflade inden for `r` meter af `center` (0 = intet hul).
func set_hole(center: Vector3, r: float) -> void:
	surface_material.set_shader_parameter("hole_center", center)
	surface_material.set_shader_parameter("hole_radius", r)


func color_for(h: float) -> Color:
	return _color_for(h)


func _color_for(h: float) -> Color:
	for b: Array in _biome:
		if h <= b[0]:
			return b[1]
	return Color.WHITE


# ---------------------------------------------------------------- overflade

func _build_surface() -> void:
	var ico := _icosphere(SUBDIVISIONS)
	var dirs: PackedVector3Array = ico[0]
	var faces: PackedInt32Array = ico[1]
	var hs := PackedFloat32Array()
	var pts := PackedVector3Array()
	hs.resize(dirs.size())
	pts.resize(dirs.size())
	for i in dirs.size():
		var h := height_at(dirs[i])
		hs[i] = h
		pts[i] = dirs[i] * (radius + maxf(h, 0.0))

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var tri := faces.size() / 3
	verts.resize(tri * 3)
	normals.resize(tri * 3)
	colors.resize(tri * 3)
	for f in tri:
		var ia := faces[f * 3]
		var ib := faces[f * 3 + 1]
		var ic := faces[f * 3 + 2]
		var a := pts[ia]
		var b := pts[ib]
		var c := pts[ic]
		var n := (b - a).cross(c - a)
		if n.dot(a + b + c) < 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		n = n.normalized()
		var h := (hs[ia] + hs[ib] + hs[ic]) / 3.0
		var colr := _color_for(h)
		# Godot tegner forsider med uret set udefra: a, c, b.
		verts[f * 3] = a
		verts[f * 3 + 1] = c
		verts[f * 3 + 2] = b
		for k in 3:
			normals[f * 3 + k] = n
			colors[f * 3 + k] = colr

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	surface_material = ShaderMaterial.new()
	surface_material.shader = load("res://shaders/planet.gdshader")
	var mi := MeshInstance3D.new()
	mi.name = "Surface"
	mi.mesh = mesh
	mi.material_override = surface_material
	add_child(mi)


## Returnerer [retninger, trekant-indekser] for en underopdelt icosaeder.
static func _icosphere(levels: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	for i in v.size():
		v[i] = v[i].normalized()
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4,
		11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
		2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for _l in levels:
		var cache := {}
		var nf := PackedInt32Array()
		for i in range(0, f.size(), 3):
			var a := f[i]
			var b := f[i + 1]
			var c := f[i + 2]
			var ab := _mid(v, cache, a, b)
			var bc := _mid(v, cache, b, c)
			var ca := _mid(v, cache, c, a)
			nf.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		f = nf
	return [v, f]


static func _mid(v: PackedVector3Array, cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 1000000 + maxi(a, b)
	if cache.has(key):
		return cache[key]
	v.append(((v[a] + v[b]) * 0.5).normalized())
	cache[key] = v.size() - 1
	return v.size() - 1


# ---------------------------------------------------------------- atmosfære og skyer

func _build_atmosphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius + atmo_top
	sphere.height = (radius + atmo_top) * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	var c := Game.col(data["atmo"])
	c.a = 0.18
	mat.albedo_color = c
	var mi := MeshInstance3D.new()
	mi.name = "Atmosphere"
	mi.mesh = sphere
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data["seed"]) * 13
	var box := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Game.col(data["cloud"])
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.27, 0.4)
	mat.roughness = 1.0
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	var groups := 60
	mm.instance_count = groups * 3
	var idx := 0
	for i in groups:
		var dir: Vector3
		if i < 20:
			dir = (pad_dir + Vector3(rng.randf_range(-.35, .35), rng.randf_range(-.35, .35), rng.randf_range(-.35, .35))).normalized()
		else:
			dir = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var tries := 0
		while in_flat_zone(dir, 40.0) and tries < 6:
			dir = (dir + tangent * 0.25).normalized()
			tries += 1
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
		var basis := Basis.looking_at(side, dir)
		var center := dir * (radius + rng.randf_range(atmo_top * 0.68, atmo_top * 0.83))
		for k in 3:
			var off := basis * Vector3(rng.randf_range(-12, 12), rng.randf_range(-1, 2), rng.randf_range(-8, 8))
			var scl := Vector3(rng.randf_range(9, 16), rng.randf_range(3, 5), rng.randf_range(7, 12))
			mm.set_instance_transform(idx, Transform3D(basis * Basis.from_scale(scl), center + off))
			idx += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Clouds"
	mmi.multimesh = mm
	add_child(mmi)


# ---------------------------------------------------------------- landingsplads og by

func _build_town() -> void:
	var lights: Array[MeshInstance3D] = []
	for pad in pads:
		_city_roots.append(CityBuilder.build(self, pad, lights))
	for f in features:
		var n := FeatureBuilder.build(self, f, lights)
		if n:
			_city_roots.append(n)
	_town_lights = lights
	# Byer, udposter og landskabsdetaljer: faste dele samles (lysene beholdes)
	for c in get_children():
		if c is Node3D and c.get_script() == null and (str(c.name).begins_with("Pad_") or str(c.name).contains("Volcano") or str(c.name).contains("Mesa") or str(c.name).contains("Cave")):
			ModelKit.merge(c, lights)


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func _box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


static func _part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _process(_delta: float) -> void:
	# Byerne skjules, når kameraet er langt væk (sparer tegning)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var far := cam.global_position.distance_to(position) - radius > 2600.0
		for r in _city_roots:
			r.visible = not far
			if far or not is_instance_valid(r):
				continue
			if r.has_meta("smoke_at") and randf() < 0.5:
				var sp: Vector3 = r.get_meta("smoke_at")
				var up := (sp - position).normalized()
				W.fx.spawn(sp + Vector3(randf_range(-25, 25), randf_range(-10, 10), randf_range(-25, 25)), up * randf_range(14, 24),
					Color("3a2a3a") if randf() < 0.7 else Color("ff7a3d"), randf_range(4.0, 8.0), 4.0)
			if r.has_meta("mist_at") and randf() < 0.4 and cam.global_position.distance_to(r.get_meta("mist_at")) < 900.0:
				var mp: Vector3 = r.get_meta("mist_at")
				W.fx.spawn(mp + Vector3(randf_range(-12, 12), 0, randf_range(-12, 12)), (mp - position).normalized() * 5.0,
					Color(0.9, 0.97, 1.0), randf_range(2.0, 4.0), 1.6)
	if _town_lights.is_empty():
		return
	var on := (Time.get_ticks_msec() / 600) % 2 == 0
	for i in _town_lights.size():
		_town_lights[i].visible = on == (i % 2 == 0)
