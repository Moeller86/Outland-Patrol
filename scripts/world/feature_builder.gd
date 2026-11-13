class_name FeatureBuilder
extends RefCounted
## Grafik til landskabsdetaljer (selve formen ligger i PlanetBody.height_at):
##  volcano – glødende lavasø i krateret og et rødt lys
##  mesa    – sø på toppen og et vandfald ned over kanten med en pool forneden
##  canyon  – (kun terræn; floden i bunden er planetens hav)
##  cave    – en klippeformation med en tunnel, man kan flyve igennem, oplyst af
##            krystaller, med et krystalkammer i midten

const K = preload("res://scripts/world/model_kit.gd")


static func build(p: PlanetBody, f: Dictionary, lights: Array[MeshInstance3D]) -> Node3D:
	match str(f["type"]):
		"volcano": return _volcano(p, f)
		"mesa": return _mesa(p, f)
		"cave": return _cave(p, f, lights)
	return null


static func _surface(p: PlanetBody, d: Vector3, lift := 0.0) -> Vector3:
	return d * (p.radius + maxf(p.height_at(d), 0.0) + lift)


static func _frame_at(p: PlanetBody, d: Vector3, fwd: Vector3, lift := 0.0) -> Transform3D:
	var f := (fwd - d * fwd.dot(d)).normalized()
	return Transform3D(Basis.looking_at(f, d), _surface(p, d, lift))


static func _volcano(p: PlanetBody, f: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Volcano"
	p.add_child(root)
	var d: Vector3 = f["dir"]
	var floor_r := p.radius + p.height_at(d)
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(p.tangent - d * p.tangent.dot(d), d), d * (floor_r + 6.0))
	root.add_child(n)
	var cr: float = f["crater_r"]
	var lava := K.add(n, K.cyl(cr * 0.75, cr * 0.75, 2.0, 20), K.glow(Color("ff5a1f")), Vector3.ZERO)
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	K.add(n, K.cyl(cr * 0.45, cr * 0.45, 2.2, 14), K.glow(Color("ffd23f")), Vector3(0, 0.2, 0))
	var light := OmniLight3D.new()
	light.light_color = Color("ff7a3d")
	light.light_energy = 4.0
	light.omni_range = cr * 4.0
	light.position = Vector3(0, 40, 0)
	n.add_child(light)
	root.set_meta("smoke_at", p.position + d * (floor_r + 20.0))
	return root


static func _mesa(p: PlanetBody, f: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Mesa"
	p.add_child(root)
	var d: Vector3 = f["dir"]
	var top: float = f["top"]
	var r: float = f["r"]
	if not f.get("waterfall", true):
		return root
	var water := _water_mat()
	# Sø på toppen
	var lake := Node3D.new()
	lake.transform = Transform3D(Basis.looking_at(p.tangent - d * p.tangent.dot(d), d), d * (p.radius + top + 0.8))
	root.add_child(lake)
	K.add(lake, K.cyl(r * 0.45, r * 0.45, 1.0, 20), water, Vector3.ZERO)
	# Vandfaldet ned over kanten i kompasretningen "fall"
	var hd := p._heading_at(d, float(f.get("fall", 90.0)))
	var axis := d.cross(hd).normalized()
	var edge_d := d.rotated(axis, -(r + 4.0) / p.radius).normalized()
	var foot_d := d.rotated(axis, -(r + 34.0) / p.radius).normalized()
	var top_pos := edge_d * (p.radius + top + 0.5)
	var foot_pos := foot_d * (p.radius + maxf(p.height_at(foot_d), 0.0))
	var fall := Node3D.new()
	var mid := (top_pos + foot_pos) / 2.0
	var down := (foot_pos - top_pos)
	var len := down.length()
	var upv := -down.normalized()
	var outv := (hd - upv * hd.dot(upv)).normalized()
	fall.transform = Transform3D(Basis.looking_at(-outv, upv), mid)
	root.add_child(fall)
	var sheet := MeshInstance3D.new()
	sheet.mesh = K.box(26.0, len, 3.0)
	sheet.material_override = _fall_mat()
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fall.add_child(sheet)
	# Kanal fra søen ud til kanten
	var chan := Node3D.new()
	chan.transform = Transform3D(Basis.looking_at(hd - edge_d * hd.dot(edge_d), edge_d), d.rotated(axis, -(r * 0.7) / p.radius).normalized() * (p.radius + top + 0.6))
	root.add_child(chan)
	K.add(chan, K.box(24.0, 1.0, r * 0.7), water, Vector3.ZERO)
	# Pool forneden
	var pool := Node3D.new()
	pool.transform = Transform3D(Basis.looking_at(hd - foot_d * hd.dot(foot_d), foot_d), foot_pos + foot_d * 0.6)
	root.add_child(pool)
	K.add(pool, K.cyl(30.0, 30.0, 1.0, 16), water, Vector3.ZERO)
	root.set_meta("mist_at", p.position + foot_pos + foot_d * 4.0)
	return root


static func _water_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("flow", 0.0)
	return m


static func _fall_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/water.gdshader")
	m.set_shader_parameter("flow", 1.0)
	return m


## Klippeformation med en tunnel langs `heading`. Tunnelens akse ligger 18 m over jorden.
static func _cave(p: PlanetBody, f: Dictionary, lights: Array[MeshInstance3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "Cave"
	p.add_child(root)
	var d: Vector3 = f["dir"]
	var hd: Vector3 = f["heading_dir"]
	var base: float = f["base_h"]
	var cave := Node3D.new()
	cave.transform = Cave.frame(p, f)
	root.add_child(cave)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(f["dist"]) + str(f["bearing"]))
	var rock_cols: Array = p.data.get("flora", {}).get("rock", ["8a6bbf"])
	var rock := K.hull(Game.col(rock_cols[0]).darkened(0.25), K.TEX_PLATING, 0.15)
	var rock2 := K.hull(Game.col(rock_cols[rock_cols.size() - 1]).darkened(0.4), K.TEX_PLATING, 0.12)
	var glow_col := Color("4dffe1") if p.data.get("decor", "") != "lava" else Color("ff7a3d")
	var half := Cave.LENGTH / 2.0
	# Tunnelvægge: ringe af klippeblokke langs aksen (lokal -Z)
	var z := -half
	while z <= half:
		var seg := 10
		for i in seg:
			var a := TAU * i / seg + rng.randf_range(-0.1, 0.1)
			var rr := Cave.TUBE_R + 5.0
			var blk := K.add(cave, K.box(rng.randf_range(9, 13), rng.randf_range(8, 12), 13.0),
				rock if (i + int(z)) % 3 else rock2, Vector3(cos(a) * rr, sin(a) * rr, z))
			blk.rotation = Vector3(0, 0, a)
		z += 12.0
	# Ydre klippemasse (bjerget omkring tunnelen)
	for k in 46:
		var a := rng.randf_range(0.0, PI)
		var rr := rng.randf_range(Cave.TUBE_R + 10.0, Cave.OUTER_R)
		var zz := rng.randf_range(-half + 6.0, half - 6.0)
		var s := rng.randf_range(14.0, 26.0)
		var b := K.add(cave, K.box(s, s * rng.randf_range(0.6, 1.0), s), rock if k % 2 else rock2, Vector3(cos(a) * rr, sin(a) * rr, zz))
		b.rotation = Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6)
	# Gulv
	K.add(cave, K.box(Cave.TUBE_R * 2.4, 4.0, Cave.LENGTH), rock2, Vector3(0, -Cave.TUBE_R - 3.0, 0))
	# Lysende krystaller langs væggene og et kammer i midten
	for k in 14:
		var a := rng.randf_range(0.0, TAU)
		var zz := rng.randf_range(-half + 8.0, half - 8.0)
		var c := K.add(cave, K.cyl(0.0, 1.4, rng.randf_range(4.0, 7.0), 4), K.glow(glow_col if k % 3 else Color("c77dff")),
			Vector3(cos(a) * (Cave.TUBE_R - 1.0), sin(a) * (Cave.TUBE_R - 1.0), zz))
		c.rotation = Vector3(0, 0, a - PI / 2)
	for zz in [-half * 0.5, 0.0, half * 0.5]:
		var l := OmniLight3D.new()
		l.light_color = glow_col
		l.light_energy = 2.5
		l.omni_range = 45.0
		l.position = Vector3(0, 6, zz)
		cave.add_child(l)
	# Indgangsmarkører (blinker)
	for zz in [-half - 2.0, half + 2.0]:
		for x in [-Cave.TUBE_R, Cave.TUBE_R]:
			lights.append(K.add(cave, K.box(1.2, 1.2, 1.2), K.glow(Color("ffd23f")), Vector3(x, -Cave.TUBE_R + 2.0, zz)))
	return root
