class_name CityBuilder
extends RefCounted
## Bygger landingsstederne på en planet:
##  city    – hovedbyen: landingsplads, hal, kontroltårn, boligblokke og en skyline af
##            skyskrabere i planetens stil (glas og haver, sandsten, industri, is, svampe).
##  mine    – boretårne, transportbånd, malmbunker, siloer og raffinaderi.
##  farm    – drivhuskupler, marker i striber, vandtårn og lade.
##  research– radarskål, kupler, antenner og laboratorium.
##  military– Concord-forpost: bunkers, forsvarstårne og radar.
##  town    – en lille by med huse og et marked.
## Alt bygges med ModelKit og står på planetens krumme overflade (hver bygning
## placeres og vendes efter overfladen, så de står lodret selv langt fra pladsen).

const K = preload("res://scripts/world/model_kit.gd")


## Bygger et landingssted. Returnerer roden (barn af planeten).
static func build(p: PlanetBody, pad: Dictionary, lights: Array[MeshInstance3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "Pad_" + str(pad["id"])
	p.add_child(root)
	var town := Node3D.new()
	town.transform = _frame(p, pad, 0.0, 0.0, -0.4)
	root.add_child(town)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(pad["id"]))
	if pad["kind"] == "city":
		_landing_pad(town, 18.0, lights, Color("4dffe1"))
		_city_core(p, town, rng, lights)
		_skyline(p, pad, root, rng, lights)
		_beacon(town, Color(1.0, 0.31, 0.85, 0.5), 320.0)
	else:
		_landing_pad(town, 12.0, lights, Color("ffd23f"))
		match str(pad["style"]):
			"mine": _mine(p, pad, root, town, rng, lights)
			"farm": _farm(p, pad, root, town, rng, lights)
			"research": _research(p, pad, root, town, rng, lights)
			"military": _military(p, pad, root, town, rng, lights)
			"plot": _plot(p, pad, root, lights)
			_: _small_town(p, pad, root, town, rng, lights)
		_beacon(town, Color(1.0, 0.82, 0.25, 0.45), 220.0)
	return root


## Overfladens koordinatsystem (planet-lokalt) x meter til siden og z meter frem fra pladsen.
static func _frame(p: PlanetBody, pad: Dictionary, x: float, z: float, lift := 0.0) -> Transform3D:
	var up0: Vector3 = pad["dir"]
	var t: Vector3 = pad["tangent"]
	var side := up0.cross(t).normalized()
	var d := (up0 * p.radius + t * -z + side * x).normalized()
	var r := p.radius + maxf(p.height_at(d), 0.0) + lift
	var fwd := t - d * t.dot(d)
	return Transform3D(Basis.looking_at(fwd.normalized(), d), d * r)


static func _place(p: PlanetBody, pad: Dictionary, root: Node3D, x: float, z: float, sink := 0.0, rot := 0.0) -> Node3D:
	var n := Node3D.new()
	var xf := _frame(p, pad, x, z, -sink)
	n.transform = xf * Transform3D(Basis(Vector3.UP, rot), Vector3.ZERO)
	root.add_child(n)
	return n


static func _landing_pad(town: Node3D, r: float, lights: Array[MeshInstance3D], light_col: Color) -> void:
	var concrete := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.25)
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	K.add(town, K.cyl(r, r + 2, 6, 16), concrete, Vector3(0, -1.0, 0))
	K.add(town, K.cyl(r - 3, r - 3, 6.3, 16), K.stripes(0.35), Vector3(0, -1.0, 0))
	K.add(town, K.cyl(r - 5, r - 5, 6.6, 16), metal, Vector3(0, -1.0, 0))
	var hw := r * 0.2
	for x in [-hw, hw]:
		K.add(town, K.box(1.4, 0.2, r * 0.5), K.flat(Color("ffd23f")), Vector3(x, 2.35, 0))
	K.add(town, K.box(hw * 2.0, 0.2, 1.4), K.flat(Color("ffd23f")), Vector3(0, 2.35, 0))
	var n := 12 if r > 15 else 8
	for i in n:
		var a := i / float(n) * TAU
		lights.append(K.add(town, K.box(0.8, 0.5, 0.8), K.glow(light_col), Vector3(cos(a) * (r - 0.5), 2.2, sin(a) * (r - 0.5))))


static func _beacon(town: Node3D, c: Color, h: float) -> void:
	var beacon := MeshInstance3D.new()
	beacon.name = "Beacon"
	beacon.mesh = K.cyl(1.4, 1.4, h, 6)
	beacon.position = Vector3(0, h / 2.0 + 2.0, 0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = c
	bm.disable_fog = true
	beacon.material_override = bm
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	town.add_child(beacon)


# ---------------------------------------------------------------- hovedbyen

static func _cols(p: PlanetBody) -> Array:
	var bld: Array = p.data["buildings"]
	var c0: Color = Game.col(bld[0])
	var c1: Color = Game.col(bld[1])
	var c2: Color = Game.col(bld[2]) if bld.size() > 2 else c0
	return [c0, c1, c2]


## Den gamle bykerne omkring pladsen: hal, kontroltårn, boligblokke, kuppel, tanke, gadelys.
static func _city_core(p: PlanetBody, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var cols := _cols(p)
	var c0: Color = cols[0]
	var c1: Color = cols[1]
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	var concrete := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.25)
	var white := K.hull(Color("e6ecff"))
	var win := K.windows(0.5)
	# Hangar/handelshal
	var hall := Node3D.new()
	hall.position = Vector3(-31, 0, 6)
	town.add_child(hall)
	K.add(hall, K.box(18, 12, 14), K.hull(c0), Vector3(0, 1, 0))
	K.add(hall, K.box(18.2, 1.8, 14.2), win, Vector3(0, 4.5, 0))
	K.add(hall, K.cyl(7, 7, 18, 10), K.hull(c0.darkened(0.25), K.TEX_ROOF, 0.4), Vector3(0, 7, 0), Vector3(0, 0, PI / 2))
	K.add(hall, K.box(9, 6, 0.6), K.stripes(0.5), Vector3(0, -1, 7.1))
	K.add(hall, K.box(7.6, 5, 0.8), K.flat(Color("1a1028")), Vector3(0, -1.2, 7.2))
	lights.append(K.add(hall, K.box(0.6, 0.6, 0.6), K.glow(Color("ff3b3b")), Vector3(-4.8, 2.4, 7.3)))
	lights.append(K.add(hall, K.box(0.6, 0.6, 0.6), K.glow(Color("4dff6a")), Vector3(4.8, 2.4, 7.3)))
	# Kontroltårn
	var tower := Node3D.new()
	tower.position = Vector3(26, 0, -10)
	town.add_child(tower)
	K.add(tower, K.cyl(3.2, 4.2, 6, 8), concrete, Vector3(0, 1, 0))
	K.add(tower, K.cyl(2.0, 2.6, 22, 8), K.hull(c1), Vector3(0, 14, 0))
	K.add(tower, K.cyl(2.1, 2.1, 14, 8), K.windows(0.7), Vector3(0, 14, 0), Vector3.ZERO, Vector3(1, 1, 0.35))
	K.add(tower, K.cyl(5, 3.6, 3, 10), white, Vector3(0, 26.5, 0))
	K.add(tower, K.cyl(5.1, 5.1, 1.6, 10), K.glow(Color("4dffe1")), Vector3(0, 28.6, 0))
	K.add(tower, K.cyl(1.6, 5.2, 2.2, 10), K.hull(c1.darkened(0.2), K.TEX_ROOF, 0.4), Vector3(0, 30.5, 0))
	K.add(tower, K.cyl(0.15, 0.25, 7, 4), K.flat(Color("d9d2ff")), Vector3(0, 35, 0))
	lights.append(K.add(tower, K.box(0.9, 0.9, 0.9), K.glow(Color("ff3b3b")), Vector3(0, 38.6, 0)))
	# Boligblokke tæt på pladsen
	var spots := [Vector3(18, 0, 24), Vector3(28, 0, 14), Vector3(-22, 0, -26), Vector3(-34, 0, -12), Vector3(6, 0, -32), Vector3(-8, 0, 30)]
	for i in spots.size():
		_block(town, spots[i], rng, cols[i % 3], i % 2 == 0)
	# Tanke og gadelys
	for k in 3:
		var tp := Vector3(34 + k * 0.5, 0, -28 + k * 7)
		K.add(town, K.cyl(3, 3, 8, 10), K.hull(Color("ff9e3d"), K.TEX_PLATING, 0.5), tp + Vector3(0, 3, 0))
		K.add(town, K.sphere(3, 10, 4), K.hull(Color("ff9e3d"), K.TEX_PLATING, 0.5), tp + Vector3(0, 7, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	for a in [0.35, 1.9, 3.4, 4.9]:
		for k in 2:
			var r := 22.0 + k * 9.0
			var lp := Vector3(cos(a) * r, 0, sin(a) * r)
			K.add(town, K.cyl(0.15, 0.2, 5, 4), metal, lp + Vector3(0, 2.0, 0))
			K.add(town, K.box(0.7, 0.4, 0.7), K.glow(Color("ffe08a")), lp + Vector3(0, 4.6, 0))


static func _block(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, col: Color, pitched: bool) -> void:
	var w := rng.randf_range(7, 11)
	var d := rng.randf_range(6, 9)
	var h := rng.randf_range(6, 14)
	var b := Node3D.new()
	b.position = pos
	b.rotation.y = rng.randf_range(-0.4, 0.4)
	parent.add_child(b)
	K.add(b, K.box(w, h + 6, d), K.hull(col), Vector3(0, h * 0.5 - 3, 0))
	for f in int(h / 3.2):
		K.add(b, K.box(w + 0.15, 1.2, d + 0.15), K.windows(0.5), Vector3(0, 1.4 + f * 3.2, 0))
	if pitched:
		K.add(b, K.wedge(w + 0.8, 3, d + 0.8), K.hull(col.darkened(0.35), K.TEX_ROOF, 0.45), Vector3(0, h + 1.5, 0))
	else:
		K.add(b, K.box(w + 0.6, 0.8, d + 0.6), K.hull(Color("e6ecff")), Vector3(0, h + 0.4, 0))


## Skyskrabere i ringe omkring bykernen. Højest tæt på centrum.
static func _skyline(p: PlanetBody, pad: Dictionary, root: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var cols := _cols(p)
	var style: String = p.data.get("decor", "tree")
	var outer := float(pad["flat_m"]) - 12.0
	var step := 26.0
	var placed := 0
	var max_towers := int(clampf(outer / 6.0, 8.0, 26.0))
	var spots: Array[Vector2] = []
	var gx := -outer
	while gx <= outer:
		var gz := -outer
		while gz <= outer:
			var v := Vector2(gx, gz) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			var r := v.length()
			if r > 50.0 and r < outer:
				spots.append(v)
			gz += step
		gx += step
	# Behold de inderste først (med lidt tilfældighed), så skylinen samler sig om centrum
	var keys := {}
	for v in spots:
		keys[v] = v.length() + rng.randf() * 40.0
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return keys[a] < keys[b])
	for v in spots:
		if placed >= max_towers:
			break
		var r := v.length()
		var k := clampf((r - 50.0) / maxf(outer - 50.0, 1.0), 0.0, 1.0)
		var h := lerpf(72.0, 26.0, k) * rng.randf_range(0.75, 1.1)
		var w := rng.randf_range(9.0, 14.0)
		var d := rng.randf_range(9.0, 14.0)
		var n := _place(p, pad, root, v.x, v.y, 0.0, rng.randf_range(-0.2, 0.2) + atan2(v.x, v.y))
		_tower(n, w, d, h, style, cols[placed % 3], rng, lights)
		placed += 1


## En skyskraber: fundament, skakt med vinduesfacade og søjler, tilbagetrækninger og en top.
static func _tower(n: Node3D, w: float, d: float, h: float, style: String, col: Color, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var wall := K.hull(col)
	var dark := K.hull(col.darkened(0.45), K.TEX_PLATING, 0.3)
	var win := K.windows(0.32)
	var trim := K.hull(Color("e6ecff"), K.TEX_PANEL, 0.4)
	match style:
		"cactus":
			wall = K.hull(Color("e8c48a").lerp(col, 0.25))
			trim = K.hull(Color("c96b4a"), K.TEX_PLATING, 0.4)
		"lava":
			wall = K.hull(Color("3a2a3a").lerp(col, 0.2), K.TEX_PLATING, 0.35)
			trim = K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
		"crystal":
			wall = K.hull(Color("e6f4ff").lerp(col, 0.2))
			trim = K.hull(Color("9fe2ff"), K.TEX_PANEL, 0.4)
	# Fundament (rækker ned i terrænet, så skråninger ikke viser hul under)
	K.add(n, K.box(w + 5.0, 26.0, d + 5.0), dark, Vector3(0, -9.0, 0))
	K.add(n, K.box(w + 4.0, 1.0, d + 4.0), K.stripes(0.4), Vector3(0, 4.4, 0))
	var tiers := 1 if h < 40.0 else (2 if h < 60.0 else 3)
	var y := 4.0
	var cw := w
	var cd := d
	for t in tiers:
		var th := (h - 4.0) / tiers * (1.15 if t == 0 else 0.92)
		var mid := y + th / 2.0
		K.add(n, K.box(cw, th, cd), wall, Vector3(0, mid, 0))
		# Vinduesfacade: to sider ad gangen, så hjørnerne står som søjler
		K.add(n, K.box(cw + 0.3, th - 2.0, cd - 2.4), win, Vector3(0, mid, 0))
		K.add(n, K.box(cw - 2.4, th - 2.0, cd + 0.3), win, Vector3(0, mid, 0))
		# Etagebånd
		var bands := int(th / 12.0)
		for b in bands:
			K.add(n, K.box(cw + 0.5, 0.7, cd + 0.5), trim, Vector3(0, y + 6.0 + b * 12.0, 0))
		y += th
		if t < tiers - 1:
			K.add(n, K.box(cw + 0.8, 1.0, cd + 0.8), trim, Vector3(0, y, 0))
			if style == "tree":
				K.add(n, K.box(cw - 1.0, 1.4, cd - 1.0), K.flat(Color("2fa04f")), Vector3(0, y + 0.8, 0))   # tagterrasse med have
			cw *= 0.72
			cd *= 0.72
	# Top
	K.add(n, K.box(cw + 0.6, 1.0, cd + 0.6), trim, Vector3(0, y + 0.5, 0))
	match style:
		"cactus":
			K.add(n, K.sphere(minf(cw, cd) * 0.45, 10, 5), K.hull(Color("4dd0ff"), K.TEX_PANEL, 0.4), Vector3(0, y + 1.0, 0), Vector3.ZERO, Vector3(1, 0.7, 1))
		"lava":
			for s in [-1.0, 1.0]:
				K.add(n, K.cyl(0.9, 1.2, 9.0, 8), K.hull(Color("5a5470"), K.TEX_PLATING, 0.4), Vector3(s * cw * 0.25, y + 5.0, 0))
				K.add(n, K.cyl(0.95, 0.95, 0.6, 8), K.glow(Color("ff7a3d")), Vector3(s * cw * 0.25, y + 9.3, 0))
		"crystal":
			var spire := K.add(n, K.cyl(0.0, minf(cw, cd) * 0.35, 12.0, 4), K.glow(Color("9fe2ff")), Vector3(0, y + 7.0, 0))
			spire.rotation.y = PI / 4
		"mushroom":
			K.add(n, K.sphere(maxf(cw, cd) * 0.75, 10, 5), K.glow(col.lightened(0.2)), Vector3(0, y + 2.0, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
		_:
			if rng.randf() < 0.5:
				K.add(n, K.cyl(0.18, 0.3, 10.0, 4), K.flat(Color("d9d2ff")), Vector3(0, y + 6.0, 0))
				lights.append(K.add(n, K.box(0.9, 0.9, 0.9), K.glow(Color("ff3b3b")), Vector3(0, y + 11.3, 0)))
			else:
				K.add(n, K.box(cw * 0.6, 0.3, cd * 0.6), K.stripes(0.5), Vector3(0, y + 1.1, 0))   # landingsplads på taget
				lights.append(K.add(n, K.box(0.6, 0.6, 0.6), K.glow(Color("4dffe1")), Vector3(cw * 0.3, y + 1.4, cd * 0.3)))
	if style != "tree" and style != "crystal" and rng.randf() < 0.6:
		K.greebles(n, rng.randi(), Vector3(0, y + 1.0, 0), Vector2(cw * 0.7, cd * 0.7), Vector3.UP, 3, K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4), 1.0)


# ---------------------------------------------------------------- mindre steder

## En byggegrund: afmærkningspæle med lys i hjørnerne. Basen bygges af PlayerBases.
static func _plot(p: PlanetBody, pad: Dictionary, root: Node3D, lights: Array[MeshInstance3D]) -> void:
	for c: Vector2 in [Vector2(-48, -48), Vector2(48, -48), Vector2(48, 48), Vector2(-48, 48)]:
		var n := _place(p, pad, root, c.x, c.y)
		K.add(n, K.cyl(0.3, 0.4, 6.0, 6), K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5), Vector3(0, 2.0, 0))
		lights.append(K.add(n, K.box(0.7, 0.7, 0.7), K.glow(Color("6bdc4f")), Vector3(0, 5.4, 0)))

static func _mine(p: PlanetBody, pad: Dictionary, root: Node3D, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var steel := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.4)
	var yellow := K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5)
	var rust := K.hull(Color("8a4a3a"), K.TEX_PLATING, 0.5)
	var ore := Color("ffe14d") if p.data.get("decor", "") != "crystal" else Color("c77dff")
	# Boretårne (gittermaster) med bor ned i jorden
	for k in 2:
		var n := _place(p, pad, root, -26.0 + k * 52.0, -24.0, 0.0, rng.randf() * TAU)
		for c: Vector2 in [Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)]:
			K.add(n, K.box(0.6, 26.0, 0.6), yellow, Vector3(c.x * 0.6, 13.0, c.y * 0.6), Vector3(c.y * 0.035, 0, -c.x * 0.035))
		for y in range(3, 26, 5):
			K.add(n, K.box(5.0 - y * 0.1, 0.35, 0.35), yellow, Vector3(0, y, 1.8 - y * 0.04))
			K.add(n, K.box(0.35, 0.35, 5.0 - y * 0.1), yellow, Vector3(1.8 - y * 0.04, y, 0))
		K.add(n, K.cyl(1.0, 1.0, 34.0, 8), steel, Vector3(0, 9.0, 0))
		K.add(n, K.box(4.0, 2.0, 4.0), rust, Vector3(0, 26.5, 0))
		lights.append(K.add(n, K.box(0.7, 0.7, 0.7), K.glow(Color("ff3b3b")), Vector3(0, 28.0, 0)))
		K.add(n, K.cyl(5.0, 6.0, 3.0, 10), K.hull(Color("3a2d24"), K.TEX_PLATING, 0.3), Vector3(0, 0.5, 0))
	# Malmbunker og transportbånd
	for k in 3:
		var n := _place(p, pad, root, -30.0 + k * 9.0, 22.0 + k * 3.0, 0.5)
		K.add(n, K.cyl(0.0, 7.0 - k, 6.0 - k, 7), K.hull(ore, K.TEX_PLATING, 0.6), Vector3(0, 2.5, 0))
	var belt := _place(p, pad, root, 0.0, 24.0)
	K.add(belt, K.box(40.0, 1.0, 2.2), K.hull(Color("23203a"), K.TEX_PLATING, 0.6), Vector3(0, 5.0, 0))
	for x in range(-18, 19, 6):
		K.add(belt, K.box(0.5, 6.0, 0.5), steel, Vector3(x, 2.0, 0))
	# Siloer og raffinaderi
	for k in 3:
		var n := _place(p, pad, root, 28.0 + k * 7.0, 8.0 - k * 3.0, 0.0)
		K.add(n, K.cyl(3.0, 3.0, 16.0, 10), K.hull(Color("e6ecff"), K.TEX_PLATING, 0.4), Vector3(0, 6.0, 0))
		K.add(n, K.sphere(3.0, 10, 4), K.hull(Color("e6ecff"), K.TEX_PLATING, 0.4), Vector3(0, 14.0, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
		K.add(n, K.box(6.2, 0.8, 6.2), K.stripes(0.6), Vector3(0, 3.0, 0))
	var plant := _place(p, pad, root, 30.0, -20.0, 0.0, 0.3)
	K.add(plant, K.box(16.0, 18.0, 12.0), rust, Vector3(0, 4.0, 0))
	K.add(plant, K.box(16.2, 1.6, 12.2), K.windows(0.5), Vector3(0, 8.0, 0))
	K.add(plant, K.cyl(1.2, 1.6, 16.0, 8), K.hull(Color("5a5470"), K.TEX_PLATING, 0.4), Vector3(5.0, 18.0, 0))
	K.add(plant, K.cyl(1.25, 1.25, 0.6, 8), K.glow(Color("ff7a3d")), Vector3(5.0, 26.2, 0))
	_shacks(p, pad, root, rng, Color("8a8fb0"), 3)


static func _farm(p: PlanetBody, pad: Dictionary, root: Node3D, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var glass := K.glass(Color("6bdc4f"))
	var steel := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.4)
	var crop := Color("6bdc4f") if p.data.get("decor", "") != "mushroom" else Color("ff4f8b")
	# Drivhuskupler i rækker
	for k in 6:
		var n := _place(p, pad, root, -36.0 + (k % 3) * 14.0, -22.0 - (k / 3) * 16.0, 0.0)
		var dome := K.add(n, K.sphere(6.0, 12, 6), glass, Vector3(0, 0.5, 0))
		dome.scale = Vector3(1, 0.7, 1.6)
		K.add(n, K.box(12.4, 1.0, 19.6), steel, Vector3(0, 0.2, 0))
	# Marker i striber
	for k in 6:
		var n := _place(p, pad, root, 18.0 + k * 4.5, -20.0, 0.2)
		K.add(n, K.box(3.6, 0.8, 34.0), K.flat(crop.darkened(0.15 * (k % 2))), Vector3(0, 0.3, 0))
	# Vandtårn og lade
	var wt := _place(p, pad, root, -20.0, 24.0)
	for c: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]:
		K.add(wt, K.box(0.5, 16.0, 0.5), steel, Vector3(c.x, 8.0, c.y))
	K.add(wt, K.cyl(4.0, 4.0, 6.0, 10), K.hull(Color("4dd0ff"), K.TEX_PLATING, 0.5), Vector3(0, 18.0, 0))
	lights.append(K.add(wt, K.box(0.6, 0.6, 0.6), K.glow(Color("ff3b3b")), Vector3(0, 21.5, 0)))
	var barn := _place(p, pad, root, 26.0, 22.0, 0.0, 0.4)
	K.add(barn, K.box(14.0, 12.0, 10.0), K.hull(Color("c96b4a")), Vector3(0, 2.0, 0))
	K.add(barn, K.wedge(14.6, 5.0, 10.6), K.hull(Color("5a3a4a"), K.TEX_ROOF, 0.45), Vector3(0, 10.5, 0))
	_shacks(p, pad, root, rng, Color("e8c48a"), 3)


static func _research(p: PlanetBody, pad: Dictionary, root: Node3D, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var white := K.hull(Color("e6ecff"))
	var steel := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.4)
	# Stor radarskål
	var dish := _place(p, pad, root, -30.0, -18.0, 0.0, 0.6)
	K.add(dish, K.cyl(2.0, 3.0, 14.0, 8), steel, Vector3(0, 7.0, 0))
	K.add(dish, K.cyl(11.0, 2.0, 2.0, 16), white, Vector3(0, 16.0, 2.0), Vector3(0.7, 0, 0))
	K.add(dish, K.cyl(0.3, 0.3, 8.0, 4), K.flat(Color("d9d2ff")), Vector3(0, 19.0, -1.0), Vector3(0.7, 0, 0))
	lights.append(K.add(dish, K.box(0.7, 0.7, 0.7), K.glow(Color("4dffe1")), Vector3(0, 22.0, -3.5)))
	# Kupler forbundet med gange
	for k in 3:
		var n := _place(p, pad, root, 16.0 + k * 13.0, 10.0 - k * 9.0, 0.0)
		var dm := K.add(n, K.sphere(6.0 - k, 12, 6), K.glass(Color("9fe2ff")), Vector3(0, 0.5, 0))
		dm.scale = Vector3(1, 0.8, 1)
		K.add(n, K.torus(6.0 - k, 1.0, 14, 4), white, Vector3(0, 0.6, 0))
	# Laboratorium med vinduesbånd og antenner
	var lab := _place(p, pad, root, -10.0, 28.0, 0.0, -0.2)
	K.add(lab, K.box(22.0, 14.0, 10.0), white, Vector3(0, 3.0, 0))
	K.add(lab, K.box(22.2, 2.0, 10.2), K.windows(0.5), Vector3(0, 5.0, 0))
	for x in [-7.0, 0.0, 7.0]:
		K.add(lab, K.cyl(0.15, 0.25, 9.0, 4), K.flat(Color("d9d2ff")), Vector3(x, 14.0, 0))
		lights.append(K.add(lab, K.box(0.5, 0.5, 0.5), K.glow(Color("c77dff")), Vector3(x, 18.6, 0)))


static func _military(p: PlanetBody, pad: Dictionary, root: Node3D, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var blue := K.hull(Color("2e6bd6"))
	var white := K.hull(Color("e6ecff"))
	var steel := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	# Bunkers
	for k in 3:
		var n := _place(p, pad, root, -28.0 + k * 14.0, -26.0, 0.0, rng.randf_range(-0.2, 0.2))
		K.add(n, K.box(11.0, 10.0, 8.0), steel, Vector3(0, 1.5, 0))
		K.add(n, K.wedge(11.4, 3.0, 8.4), blue, Vector3(0, 8.0, 0))
		K.add(n, K.box(8.0, 1.2, 8.2), K.windows(0.6), Vector3(0, 4.0, 0))
	# Forsvarstårne
	for v: Vector2 in [Vector2(26, -14), Vector2(26, 18), Vector2(-26, 20)]:
		var n := _place(p, pad, root, v.x, v.y)
		K.add(n, K.cyl(2.5, 3.2, 8.0, 10), steel, Vector3(0, 2.0, 0))
		K.add(n, K.box(3.4, 2.0, 3.4), blue, Vector3(0, 7.0, 0))
		for s in [-0.6, 0.6]:
			K.add(n, K.cyl(0.2, 0.28, 4.0, 6), K.flat(Color("3a3f5a")), Vector3(s, 7.2, -3.0), Vector3(-PI / 2, 0, 0))
	# Radarmast og Concord-flag
	var mast := _place(p, pad, root, 4.0, 28.0)
	K.add(mast, K.cyl(0.4, 0.7, 24.0, 6), white, Vector3(0, 10.0, 0))
	K.add(mast, K.cyl(4.0, 1.0, 0.8, 10), white, Vector3(0, 22.0, 0), Vector3(0.8, 0, 0))
	lights.append(K.add(mast, K.box(0.9, 0.9, 0.9), K.glow(Color("4d8bff")), Vector3(0, 24.6, 0)))
	K.add(mast, K.box(5.0, 3.0, 0.15), K.hull(Color("2e6bd6")), Vector3(2.6, 16.0, 0))
	K.add(mast, K.torus(1.0, 0.3, 10, 4), K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5), Vector3(2.6, 16.0, 0.1), Vector3(PI / 2, 0, 0))


static func _small_town(p: PlanetBody, pad: Dictionary, root: Node3D, town: Node3D, rng: RandomNumberGenerator, lights: Array[MeshInstance3D]) -> void:
	var cols := _cols(p)
	for k in 8:
		var a := k / 8.0 * TAU + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(24.0, 44.0)
		var n := _place(p, pad, root, cos(a) * r, sin(a) * r, 0.0, rng.randf() * TAU)
		_block(n, Vector3.ZERO, rng, cols[k % 3], k % 2 == 0)
	# Lille vandtårn/oase-kuppel
	var n2 := _place(p, pad, root, 0.0, 34.0)
	var dm := K.add(n2, K.sphere(7.0, 12, 6), K.glass(Color("4fc3d6")), Vector3(0, 0.5, 0))
	dm.scale = Vector3(1, 0.6, 1)


## Små skure/containere spredt rundt om et sted.
static func _shacks(p: PlanetBody, pad: Dictionary, root: Node3D, rng: RandomNumberGenerator, col: Color, n: int) -> void:
	for k in n:
		var a := rng.randf() * TAU
		var r := rng.randf_range(30.0, 46.0)
		var s := _place(p, pad, root, cos(a) * r, sin(a) * r, 0.0, rng.randf() * TAU)
		K.add(s, K.box(6.0, 6.0, 4.0), K.hull(col, K.TEX_PLATING, 0.5), Vector3(0, 1.5, 0))
		K.add(s, K.box(6.2, 0.6, 4.2), K.stripes(0.6), Vector3(0, 4.2, 0))
