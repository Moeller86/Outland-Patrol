class_name ModelKit
extends RefCounted
## Byggesæt til lowpoly-modeller i pixelstil: farvede panelteksturer, oplyste vinduer,
## advarselsstriber, glødende dele, kileformer og små tekniske detaljer ("greebles").
## Teksturerne er små (16–32 px), uden udglatning og lægges på med triplanar mapping,
## så de har samme tæthed på alle dele uanset størrelse.

const TEX_PANEL := 0
const TEX_WINDOWS := 1
const TEX_STRIPES := 2
const TEX_PLATING := 3
const TEX_ROOF := 4
## Mønstre til skibenes lak (gråtoner, farves af materialet)
const TEX_CAMO := 5
const TEX_CHECKER := 6
const TEX_BANDS := 7
const TEX_BOLT := 8

static var _tex: Dictionary = {}
static var _mats: Dictionary = {}


# ---------------------------------------------------------------- teksturer

static func texture(kind: int) -> ImageTexture:
	if _tex.has(kind):
		return _tex[kind]
	var img: Image
	match kind:
		TEX_PANEL: img = _panel_image()
		TEX_WINDOWS: img = _windows_image()
		TEX_STRIPES: img = _stripes_image()
		TEX_PLATING: img = _plating_image()
		TEX_ROOF: img = _roof_image()
		TEX_CAMO: img = _camo_image()
		TEX_CHECKER: img = _checker_image()
		TEX_BANDS: img = _bands_image()
		TEX_BOLT: img = _bolt_image()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


## Lyse skrogplader med panellinjer, nitter og enkelte lemme (gråtoner, farves af materialet).
static func _panel_image() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.92, 0.92, 0.92))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Store plader med let forskellig tone
	for py in [0, 16]:
		for px in [0, 16]:
			var tone := rng.randf_range(0.84, 0.98)
			img.fill_rect(Rect2i(px + 1, py + 1, 15, 15), Color(tone, tone, tone))
	# Panellinjer
	for i in [0, 16]:
		for j in 32:
			img.set_pixel(i, j, Color(0.62, 0.62, 0.66))
			img.set_pixel(j, i, Color(0.62, 0.62, 0.66))
	# Underopdeling og nitter
	for j in range(1, 16):
		img.set_pixel(8, j, Color(0.74, 0.74, 0.78))
		img.set_pixel(j + 16, 24, Color(0.74, 0.74, 0.78))
	for p: Vector2i in [Vector2i(2, 2), Vector2i(14, 2), Vector2i(2, 14), Vector2i(14, 14), Vector2i(18, 18), Vector2i(30, 30), Vector2i(18, 30), Vector2i(30, 18)]:
		img.set_pixelv(p, Color(0.55, 0.55, 0.6))
	# Lem og ventilationsriller
	img.fill_rect(Rect2i(20, 4, 8, 6), Color(0.7, 0.7, 0.74))
	for y in [5, 7]:
		for x in range(21, 27):
			img.set_pixel(x, y, Color(0.5, 0.5, 0.56))
	img.fill_rect(Rect2i(4, 20, 6, 2), Color(1, 1, 1))
	return img


## Vinduesrækker: mørk facade med tilfældigt oplyste ruder.
static func _windows_image() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.14, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(2, 32, 6):
		for x in range(2, 32, 4):
			var lit := rng.randf() < 0.65
			var c := Color(1.0, 0.92, 0.6) if lit else Color(0.28, 0.32, 0.55)
			if lit and rng.randf() < 0.3:
				c = Color(0.6, 0.95, 1.0)
			img.fill_rect(Rect2i(x, y, 2, 3), c)
	return img


## Gul/sort advarselsstribe.
static func _stripes_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, Color(1.0, 0.82, 0.25) if ((x + y) / 4) % 2 == 0 else Color(0.1, 0.07, 0.16))
	return img


## Mørkere maskinplader til motorer, rammer og undersider.
static func _plating_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.78, 0.78, 0.82))
	for i in 16:
		img.set_pixel(i, 0, Color(0.5, 0.5, 0.56))
		img.set_pixel(0, i, Color(0.5, 0.5, 0.56))
		img.set_pixel(i, 8, Color(0.62, 0.62, 0.68))
	for x in range(3, 13, 3):
		img.set_pixel(x, 4, Color(0.55, 0.55, 0.6))
		img.set_pixel(x, 12, Color(0.55, 0.55, 0.6))
	return img


## Camouflage: tre toner i klatter.
static func _camo_image() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	img.fill(Color(0.95, 0.95, 0.95))
	for tone in [0.72, 0.5]:
		for k in 9:
			var c := Vector2i(rng.randi_range(0, 31), rng.randi_range(0, 31))
			var r := rng.randi_range(3, 6)
			for y in range(-r, r + 1):
				for x in range(-r, r + 1):
					if x * x + y * y <= r * r + rng.randi_range(-2, 2):
						img.set_pixel((c.x + x + 32) % 32, (c.y + y + 32) % 32, Color(tone, tone, tone))
	return img


## Ternet (racer).
static func _checker_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var v := 1.0 if ((x / 4) + (y / 4)) % 2 == 0 else 0.45
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Brede bånd.
static func _bands_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var v := 1.0 if (y / 4) % 2 == 0 else 0.55
			if y % 4 == 0:
				v = 0.4
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Lynstriber (zigzag).
static func _bolt_image() -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.95, 0.95))
	for x in 32:
		var y0 := 10 + (x % 8 if (x / 8) % 2 == 0 else 7 - x % 8)
		for t in 5:
			img.set_pixel(x, (y0 + t) % 32, Color(0.45, 0.45, 0.45))
			img.set_pixel(x, (y0 + t + 16) % 32, Color(0.45, 0.45, 0.45))
	return img


## Tagplader/tegl til bygninger på planeterne.
static func _roof_image() -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.9, 0.9))
	for y in range(0, 16, 4):
		for x in 16:
			img.set_pixel(x, y, Color(0.6, 0.6, 0.64))
		for x in range((y / 4) % 2 * 4, 16, 8):
			img.set_pixel(x, y + 1, Color(0.7, 0.7, 0.74))
			img.set_pixel(x, y + 2, Color(0.7, 0.7, 0.74))
	return img


# ---------------------------------------------------------------- materialer

## Malet skrog: farve * paneltekstur.
static func hull(c: Color, kind := TEX_PANEL, density := 0.35) -> StandardMaterial3D:
	var key := "h%s_%d_%.2f" % [c.to_html(), kind, density]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = texture(kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * density
	m.roughness = 0.85
	_mats[key] = m
	return m


## Ensfarvet, uden tekstur.
static func flat(c: Color) -> StandardMaterial3D:
	var key := "f" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	_mats[key] = m
	return m


## Lys, der ikke påvirkes af belysning (lamper, vinduer, motorer).
static func glow(c: Color) -> StandardMaterial3D:
	var key := "g" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## Oplyste vinduer (ulyst tekstur, så de lyser i mørke).
static func windows(density := 0.5) -> StandardMaterial3D:
	var key := "w%.2f" % density
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(TEX_WINDOWS)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * density
	_mats[key] = m
	return m


static func stripes(density := 0.5) -> StandardMaterial3D:
	var key := "s%.2f" % density
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(TEX_STRIPES)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * density
	m.roughness = 0.9
	_mats[key] = m
	return m


## Glasrude (cockpit), let gennemskinnelig udseende men uigennemsigtig.
static func glass(c: Color) -> StandardMaterial3D:
	var key := "gl" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c.darkened(0.6)
	m.metallic = 0.3
	m.roughness = 0.2
	_mats[key] = m
	return m


# ---------------------------------------------------------------- former

static func box(x: float, y: float, z: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(x, y, z)
	return m


static func cyl(top: float, bottom: float, h: float, seg := 8) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return m


static func sphere(r: float, seg := 8, rings := 6) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = seg
	m.rings = rings
	return m


## Kile (trekantet prisme). Spidsen peger op (+Y) og kan flyttes til siden med `apex` (-1..1).
static func wedge(x: float, y: float, z: float, apex := 0.0) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = Vector3(x, y, z)
	m.left_to_right = (apex + 1.0) * 0.5
	return m


static func torus(r: float, thick: float, rings := 12, seg := 4) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = r - thick * 0.5
	m.outer_radius = r + thick * 0.5
	m.rings = rings
	m.ring_segments = seg
	return m


static func add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Små tekniske kasser og rør på en flade: center og størrelse i lokale koordinater,
## `up` er fladens retning (fx Vector3.UP for et tag).
static func greebles(parent: Node3D, seed_value: int, center: Vector3, size: Vector2, up: Vector3, count: int, mat: Material, scale := 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var basis := Basis(Vector3.RIGHT, PI) if up.normalized().dot(Vector3.UP) < -0.99 else Basis(Quaternion(Vector3.UP, up.normalized()))
	for i in count:
		var p := Vector3(rng.randf_range(-0.5, 0.5) * size.x, 0, rng.randf_range(-0.5, 0.5) * size.y)
		var kind := rng.randi() % 3
		var mesh: Mesh
		var h := rng.randf_range(0.3, 1.2) * scale
		match kind:
			0: mesh = box(rng.randf_range(0.6, 1.8) * scale, h, rng.randf_range(0.6, 1.8) * scale)
			1: mesh = cyl(rng.randf_range(0.25, 0.6) * scale, rng.randf_range(0.3, 0.7) * scale, h, 6)
			_: mesh = box(rng.randf_range(1.5, 3.5) * scale, h * 0.5, 0.35 * scale)
		var mi := add(parent, mesh, mat, center + basis * (p + Vector3(0, h * 0.5, 0)))
		mi.basis = basis * Basis(Vector3.UP, rng.randf() * PI)


## Navigationslys: små ulyste kuber. Returnerer dem, så de kan blinke.
static func lights(parent: Node3D, points: Array, c: Color, size := 0.5) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for p: Vector3 in points:
		out.append(add(parent, box(size, size, size), glow(c), p))
	return out


## Saml alle faste MeshInstance3D under `root` i én maske pr. materiale (færre
## tegnekald). Noder i `keep` (og alt under dem) røres ikke – fx blinkende lys,
## motorflammer og dele, der drejer. Returnerer antallet af samlede dele.
static func merge(root: Node3D, keep: Array = []) -> int:
	if OS.get_environment("OP_NO_MERGE") != "":
		return 0
	var keep_set := {}
	for k in keep:
		if k is Node and is_instance_valid(k):
			keep_set[(k as Node).get_instance_id()] = true
	var found: Array = []
	_collect(root, root, Transform3D.IDENTITY, keep_set, found)
	if found.size() < 2:
		return 0
	var groups := {}       ## [materiale-id, skygge] -> {st, mat, shadow}
	for f: Array in found:
		var mi: MeshInstance3D = f[0]
		var key := "%d_%d" % [mi.material_override.get_instance_id(), mi.cast_shadow]
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = {"st": st, "mat": mi.material_override, "shadow": mi.cast_shadow, "n": 0}
		var g: Dictionary = groups[key]
		for si in mi.mesh.get_surface_count():
			(g["st"] as SurfaceTool).append_from(mi.mesh, si, f[1])
		g["n"] = int(g["n"]) + 1
	for g: Dictionary in groups.values():
		var out := MeshInstance3D.new()
		out.name = "Merged"
		out.mesh = (g["st"] as SurfaceTool).commit()
		out.material_override = g["mat"]
		out.cast_shadow = g["shadow"]
		root.add_child(out)
	for f: Array in found:
		var mi: MeshInstance3D = f[0]
		mi.get_parent().remove_child(mi)
		mi.free()
	return found.size()


static func _collect(root: Node3D, n: Node, xf: Transform3D, keep_set: Dictionary, out: Array) -> void:
	for c in n.get_children():
		if keep_set.has(c.get_instance_id()) or not (c is Node3D) or c.get_script() != null:
			continue
		var c3 := c as Node3D
		if not c3.visible:
			continue
		var cx := xf * c3.transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null and mi.material_override != null and mi.get_child_count() == 0 and not (mi.mesh is TextMesh):
				out.append([mi, cx])
				continue
		if c.get_class() == "Node3D":
			_collect(root, c, cx, keep_set, out)
