class_name ShipModels
extends RefCounted
## Modeller til NPC-skibe: pirater og fragtskibe. Begge returnerer en Node3D med
## metadata "flame" (en pivot, der skaleres for motorflammen). Næsen peger mod -Z.

const K = preload("res://scripts/world/model_kit.gd")


## Piratjager: mørkt, kantet skrog med røde paneler, fremadrettede vinger,
## grønt cockpit, dobbelte kanoner og én stor motor.
static func pirate() -> Node3D:
	var g := Node3D.new()
	var hull := K.hull(Color("3a2350"))
	var red := K.hull(Color("ff3b3b"), K.TEX_PLATING, 0.6)
	var dark := K.flat(Color("1a1028"))
	var metal := K.hull(Color("5a5470"), K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(g, K.box(1.3, 0.9, 3.6), hull, Vector3(0, 0, 0.3))
	K.add(g, K.wedge(1.3, 2.8, 0.9), hull, Vector3(0, 0, -2.9), fwd)
	K.add(g, K.box(1.4, 0.12, 2.6), red, Vector3(0, 0.5, -0.6))
	var cockpit := K.add(g, K.sphere(0.5, 6, 4), K.glow(Color("4dff9e")), Vector3(0, 0.55, -1.0))
	cockpit.scale = Vector3(0.8, 0.6, 1.8)
	K.add(g, K.wedge(0.16, 1.4, 1.6), red, Vector3(0, 1.1, 1.3), Vector3(0, 0, 0), Vector3.ONE)   # rygfinne
	for s in [-1.0, 1.0]:
		# Fremadrettede vinger med takker
		var wing := Node3D.new()
		wing.position = Vector3(s * 0.65, 0, 0.9)
		wing.rotation = Vector3(0, s * 0.42, s * 0.08)
		g.add_child(wing)
		K.add(wing, K.box(3.0, 0.2, 1.3), red, Vector3(s * 1.5, 0, 0))
		K.add(wing, K.box(3.0, 0.16, 0.4), hull, Vector3(s * 1.5, 0.04, 0.8))
		K.add(wing, K.wedge(0.24, 1.2, 0.5), dark, Vector3(s * 3.05, 0, -0.5), fwd)       # pig ved spidsen
		K.add(wing, K.wedge(0.2, 0.8, 0.4), dark, Vector3(s * 2.2, 0, 1.15), back)
		# Kanoner under næsen
		K.add(g, K.cyl(0.1, 0.14, 1.6, 6), metal, Vector3(s * 0.45, -0.5, -2.0), fwd)
		K.add(g, K.cyl(0.12, 0.12, 0.1, 6), K.glow(Color("ff6a2a")), Vector3(s * 0.45, -0.5, -2.82), fwd)
		K.add(g, K.box(0.18, 0.18, 0.18), K.glow(Color("ff3b3b")), Vector3(s * 0.7, 0.2, 0.8))
	# Motor
	K.add(g, K.cyl(0.62, 0.72, 1.6, 8), metal, Vector3(0, 0, 2.6), back)
	K.add(g, K.cyl(0.5, 0.5, 0.06, 8), K.glow(Color("7dff4d")), Vector3(0, 0, 3.42), back)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 3.45)
	pivot.rotation = back
	g.add_child(pivot)
	K.add(pivot, K.cyl(0.0, 0.5, 2.0, 8), K.glow(Color("7dff4d")), Vector3(0, 1, 0))
	K.add(pivot, K.cyl(0.0, 0.25, 1.3, 8), K.glow(Color("eaffd0")), Vector3(0, 0.65, 0))
	g.set_meta("flame", pivot)
	K.merge(g, [pivot])
	return g


## Fragtskib: førerkabine med vinduer, gitterrygrad med containere,
## motorblok med tre dyser, advarselsstriber og lys. Ca. 18 m langt.
static func freighter() -> Node3D:
	var g := Node3D.new()
	var white := K.hull(Color("d9d2ff"))
	var blue := K.hull(Color("2e6bd6"))
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.5)
	var dark := K.flat(Color("23203a"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	# Førerkabine
	K.add(g, K.box(4.2, 3.0, 4.0), white, Vector3(0, 0.3, -3.2))
	K.add(g, K.wedge(4.2, 1.6, 3.0), white, Vector3(0, 0.3, -6.0), fwd)
	K.add(g, K.box(3.2, 0.7, 0.1), K.glow(Color("4dffe1")), Vector3(0, 1.0, -5.25))
	K.add(g, K.box(4.3, 0.5, 3.0), blue, Vector3(0, 1.95, -3.4))
	K.add(g, K.box(4.26, 0.6, 3.4), K.windows(0.9), Vector3(0, 0.6, -3.0))
	K.add(g, K.cyl(0.05, 0.08, 2.0, 4), K.flat(Color("d9d2ff")), Vector3(1.2, 3.2, -3.0))
	K.add(g, K.box(0.3, 0.3, 0.3), K.glow(Color("ff3b3b")), Vector3(1.2, 4.2, -3.0))
	# Rygrad (gitter)
	K.add(g, K.box(1.2, 1.2, 12.0), metal, Vector3(0, 0, 4.2))
	for k in 5:
		K.add(g, K.box(3.6, 0.25, 0.25), metal, Vector3(0, -0.6, -0.8 + k * 2.6))
	# Containere i to lag
	var cols := [Color("ff7a59"), Color("6bdc4f"), Color("ffd23f"), Color("4dd0ff"), Color("c77dff"), Color("ff9e3d")]
	var i := 0
	for z in [0.8, 3.6, 6.4]:
		for sx in [-1.0, 1.0]:
			K.add(g, K.box(1.9, 2.2, 2.5), K.hull(cols[i % cols.size()], K.TEX_PLATING, 0.7), Vector3(sx * 1.05, 0.5, z))
			K.add(g, K.box(1.96, 0.3, 0.3), K.stripes(0.8), Vector3(sx * 1.05, 1.45, z - 1.15))
			i += 1
	# Motorblok
	K.add(g, K.box(4.6, 3.4, 3.0), white, Vector3(0, 0.2, 11.4))
	K.add(g, K.box(4.7, 0.6, 3.1), K.stripes(0.6), Vector3(0, -1.2, 11.4))
	K.greebles(g, 21, Vector3(0, 1.9, 11.4), Vector2(3.8, 2.4), Vector3.UP, 5, metal, 0.6)
	for x in [-1.3, 0.0, 1.3]:
		K.add(g, K.cyl(0.55, 0.7, 0.9, 8), dark, Vector3(x, 0.2, 13.2), back)
		K.add(g, K.cyl(0.48, 0.48, 0.06, 8), K.glow(Color("4dd0ff")), Vector3(x, 0.2, 13.66), back)
	K.lights(g, [Vector3(2.4, 0.3, -3.0), Vector3(-2.4, 0.3, -3.0), Vector3(2.4, 1.8, 11.4), Vector3(-2.4, 1.8, 11.4)], Color("ffd23f"), 0.3)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.2, 13.7)
	pivot.rotation = back
	g.add_child(pivot)
	for x in [-1.3, 0.0, 1.3]:
		K.add(pivot, K.cyl(0.0, 0.5, 2.0, 8), K.glow(Color("4dd0ff")), Vector3(x, 1, 0))
	g.set_meta("flame", pivot)
	K.merge(g, [pivot])
	return g


## Piratmodel efter type (se Pirates.TYPES).
static func pirate_of(type: String) -> Node3D:
	match type:
		"jaeger":
			return pirate_interceptor()
		"kanonbaad":
			return pirate_gunboat()
		"missilbaad":
			return pirate_missileboat()
		"skygge":
			return pirate_shadow()
		"kaptajn":
			return pirate_captain()
	return pirate()


## Fælles motorflamme til piraterne: en pivot med flammekegler (skaleres i _process).
static func _pirate_flames(g: Node3D, z: float, xs: Array, r: float, c: Color, y := 0.0) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(0, y, z)
	pivot.rotation = Vector3(PI / 2, 0, 0)
	g.add_child(pivot)
	for x: float in xs:
		K.add(pivot, K.cyl(0.0, r, r * 4.0, 8), K.glow(c), Vector3(x, r * 2.0, 0))
		K.add(pivot, K.cyl(0.0, r * 0.5, r * 2.6, 8), K.glow(Color("fff6d0")), Vector3(x, r * 1.3, 0))
	g.set_meta("flame", pivot)
	K.merge(g, [pivot])


## Lynjæger: lille, spids og hurtig – en nål med to korte, bagudskrå finner. Gul/sort.
static func pirate_interceptor() -> Node3D:
	var g := Node3D.new()
	var black := K.hull(Color("1c1826"), K.TEX_PLATING, 0.5)
	var yellow := K.hull(Color("ffc21f"), K.TEX_BANDS, 0.7)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(g, K.box(0.8, 0.6, 3.0), black, Vector3(0, 0, 0.4))
	K.add(g, K.wedge(0.8, 2.6, 0.6), black, Vector3(0, 0, -2.4), fwd)
	K.add(g, K.box(0.84, 0.1, 2.6), yellow, Vector3(0, 0.33, -0.2))
	var cp := K.add(g, K.sphere(0.36, 6, 4), K.glow(Color("ffef6b")), Vector3(0, 0.36, -0.7))
	cp.scale = Vector3(0.8, 0.5, 2.0)
	for s in [-1.0, 1.0]:
		var fin := Node3D.new()
		fin.position = Vector3(s * 0.4, 0, 1.2)
		fin.rotation = Vector3(0, -s * 0.7, s * 0.35)
		g.add_child(fin)
		K.add(fin, K.box(2.2, 0.12, 0.9), yellow, Vector3(s * 1.1, 0, 0))
		K.add(fin, K.box(0.14, 0.5, 0.9), black, Vector3(s * 2.2, 0.15, 0))
		K.add(g, K.cyl(0.06, 0.08, 1.4, 5), K.flat(Color("50485e")), Vector3(s * 0.32, -0.32, -1.6), fwd)
		K.add(g, K.box(0.14, 0.14, 0.14), K.glow(Color("ff3b3b")), Vector3(s * 2.4, 0.3, 1.2))
	K.add(g, K.cyl(0.42, 0.5, 1.0, 8), black, Vector3(0, 0, 2.3), back)
	K.add(g, K.cyl(0.36, 0.36, 0.05, 8), K.glow(Color("ffd23f")), Vector3(0, 0, 2.82), back)
	_pirate_flames(g, 2.85, [0.0], 0.36, Color("ffd23f"))
	return g


## Kanonbåd: bred, tungt pansret pram med et kanontårn på ryggen. Rustrød/grå.
static func pirate_gunboat() -> Node3D:
	var g := Node3D.new()
	var rust := K.hull(Color("7a3424"), K.TEX_PLATING, 0.8)
	var grey := K.hull(Color("4e4a5c"), K.TEX_PLATING, 0.6)
	var dark := K.flat(Color("1a1420"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(g, K.box(4.6, 2.0, 8.0), rust, Vector3(0, 0, 0.4))
	K.add(g, K.wedge(4.6, 2.4, 2.0), rust, Vector3(0, 0, -4.8), fwd)
	K.add(g, K.box(5.4, 0.6, 6.0), grey, Vector3(0, -0.8, 0.8))      # sidepanser
	K.add(g, K.box(4.7, 0.5, 0.5), K.stripes(0.8), Vector3(0, 0.6, -3.4))
	K.add(g, K.box(2.2, 0.6, 1.2), K.glow(Color("ff9e3d")), Vector3(0, 0.75, -3.0))   # bro
	K.greebles(g, 77, Vector3(0, 1.0, 2.2), Vector2(3.8, 3.0), Vector3.UP, 6, grey, 0.7)
	# Kanontårn
	K.add(g, K.cyl(1.2, 1.4, 0.8, 8), grey, Vector3(0, 1.4, 0.0))
	K.add(g, K.box(1.6, 0.8, 1.8), rust, Vector3(0, 2.1, 0.0))
	for x in [-0.4, 0.4]:
		K.add(g, K.cyl(0.14, 0.18, 2.6, 6), dark, Vector3(x, 2.1, -1.9), fwd)
		K.add(g, K.cyl(0.16, 0.16, 0.08, 6), K.glow(Color("ff6a2a")), Vector3(x, 2.1, -3.2), fwd)
	for s in [-1.0, 1.0]:
		K.add(g, K.cyl(0.18, 0.22, 1.8, 6), dark, Vector3(s * 2.0, -0.2, -4.0), fwd)
		K.add(g, K.box(0.3, 0.3, 0.3), K.glow(Color("ff3b3b")), Vector3(s * 2.75, 0.2, 3.8))
		K.add(g, K.cyl(0.7, 0.85, 1.6, 8), grey, Vector3(s * 1.4, 0, 4.9), back)
		K.add(g, K.cyl(0.6, 0.6, 0.06, 8), K.glow(Color("ff9e3d")), Vector3(s * 1.4, 0, 5.72), back)
	_pirate_flames(g, 5.75, [-1.4, 1.4], 0.6, Color("ff9e3d"))
	return g


## Missilbåd: slank krop med to store missilkapsler på siderne. Lilla/grøn.
static func pirate_missileboat() -> Node3D:
	var g := Node3D.new()
	var hull := K.hull(Color("2f2a52"), K.TEX_PLATING, 0.6)
	var green := K.hull(Color("6bdc4f"), K.TEX_PLATING, 0.6)
	var dark := K.flat(Color("15121f"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(g, K.box(1.4, 1.1, 5.0), hull, Vector3(0, 0, 0.4))
	K.add(g, K.wedge(1.4, 2.0, 1.1), hull, Vector3(0, 0, -3.0), fwd)
	var cp := K.add(g, K.sphere(0.5, 6, 4), K.glow(Color("c77dff")), Vector3(0, 0.6, -1.4))
	cp.scale = Vector3(0.8, 0.6, 1.6)
	for s in [-1.0, 1.0]:
		K.add(g, K.box(1.6, 0.18, 1.6), hull, Vector3(s * 1.4, 0, 0.6))
		K.add(g, K.box(1.2, 1.2, 4.0), green, Vector3(s * 2.5, 0, 0.4))        # kapsel
		for row in 2:
			for col in 2:
				K.add(g, K.cyl(0.18, 0.18, 0.1, 6), K.glow(Color("ff3b3b")), Vector3(s * 2.5 + (col - 0.5) * 0.5, (row - 0.5) * 0.5, -1.62), fwd)
		K.add(g, K.box(1.24, 0.2, 0.3), K.stripes(0.8), Vector3(s * 2.5, 0.62, 1.8))
	K.add(g, K.cyl(0.55, 0.65, 1.4, 8), dark, Vector3(0, 0, 3.4), back)
	K.add(g, K.cyl(0.45, 0.45, 0.05, 8), K.glow(Color("c77dff")), Vector3(0, 0, 4.12), back)
	_pirate_flames(g, 4.15, [0.0], 0.45, Color("c77dff"))
	return g


## Skyggejæger: flad, kantet "flyvende vinge" i matsort med blå glødekanter.
static func pirate_shadow() -> Node3D:
	var g := Node3D.new()
	var black := K.hull(Color("14141e"), K.TEX_PLATING, 0.3)
	var edge := K.glow(Color("4d6bff"))
	var fwd := Vector3(-PI / 2, 0, 0)
	K.add(g, K.wedge(5.6, 5.2, 0.5), black, Vector3(0, 0, -0.4), fwd)
	K.add(g, K.box(1.2, 0.7, 2.4), black, Vector3(0, 0.15, 0.8))
	K.add(g, K.box(5.6, 0.06, 0.12), edge, Vector3(0, 0.0, 2.2))
	for s in [-1.0, 1.0]:
		var e := K.add(g, K.box(0.08, 0.08, 3.8), edge, Vector3(s * 1.4, 0.18, -0.4))
		e.rotation = Vector3(0, s * 0.49, 0)
		K.add(g, K.wedge(0.12, 0.8, 0.9), black, Vector3(s * 2.3, 0.45, 1.6))
	var cp := K.add(g, K.sphere(0.3, 6, 4), K.glow(Color("8da0ff")), Vector3(0, 0.45, -0.3))
	cp.scale = Vector3(1.2, 0.4, 1.6)
	_pirate_flames(g, 2.1, [-0.35, 0.35], 0.22, Color("4d6bff"), 0.1)
	return g


## Piratkaptajn: stor, ornamenteret korvet med kranie-galionsfigur, skjoldring og
## fire motorer. Sort/guld/rød. Ca. 16 m lang.
static func pirate_captain() -> Node3D:
	var g := Node3D.new()
	var black := K.hull(Color("201526"), K.TEX_PLATING, 0.7)
	var red := K.hull(Color("c2202f"), K.TEX_PLATING, 0.7)
	var gold := K.hull(Color("e0b13a"))
	var dark := K.flat(Color("100a14"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(g, K.box(3.4, 2.4, 10.0), black, Vector3(0, 0, 0.5))
	K.add(g, K.wedge(3.4, 4.0, 2.4), black, Vector3(0, 0, -6.5), fwd)
	K.add(g, K.box(3.5, 0.3, 8.0), red, Vector3(0, 1.3, 0.0))
	K.add(g, K.box(0.3, 0.3, 10.2), gold, Vector3(0, 1.5, 0.4))
	# Kranie i stævnen
	K.add(g, K.sphere(0.8, 8, 6), K.hull(Color("e8e2d0")), Vector3(0, 0.3, -6.2))
	for s in [-1.0, 1.0]:
		K.add(g, K.box(0.3, 0.3, 0.1), K.glow(Color("ff3b3b")), Vector3(s * 0.3, 0.45, -6.95))
	# Bro med vinduer
	K.add(g, K.box(2.4, 1.2, 2.6), black, Vector3(0, 1.9, -1.2))
	K.add(g, K.box(2.44, 0.4, 2.0), K.glow(Color("ff9e3d")), Vector3(0, 2.1, -1.6))
	K.add(g, K.cyl(0.05, 0.08, 2.6, 4), gold, Vector3(0.7, 3.6, 0.2))
	K.add(g, K.box(1.0, 0.6, 0.05), red, Vector3(1.2, 4.4, 0.2))        # vimpel
	for s in [-1.0, 1.0]:
		# Store vinger med guldkant og kanoner
		var wing := Node3D.new()
		wing.position = Vector3(s * 1.7, -0.2, 1.0)
		wing.rotation = Vector3(0, s * 0.28, -s * 0.12)
		g.add_child(wing)
		K.add(wing, K.box(5.0, 0.3, 3.2), red, Vector3(s * 2.5, 0, 0))
		K.add(wing, K.box(5.0, 0.32, 0.3), gold, Vector3(s * 2.5, 0, -1.6))
		K.add(wing, K.cyl(0.2, 0.26, 3.2, 6), dark, Vector3(s * 4.6, 0, -2.4), fwd)
		K.add(wing, K.cyl(0.22, 0.22, 0.1, 6), K.glow(Color("ff6a2a")), Vector3(s * 4.6, 0, -4.0), fwd)
		K.add(wing, K.box(0.3, 0.3, 0.3), K.glow(Color("ff3b3b")), Vector3(s * 5.0, 0.3, 1.4))
		K.add(g, K.box(0.9, 0.9, 2.4), black, Vector3(s * 1.1, -1.2, -2.0))      # missilrum
		for k in 3:
			K.add(g, K.cyl(0.14, 0.14, 0.08, 6), K.glow(Color("ff3b3b")), Vector3(s * 1.1, -1.2 + (k - 1) * 0.28, -3.24), fwd)
		for y in [-0.6, 0.6]:
			K.add(g, K.cyl(0.6, 0.75, 1.6, 8), dark, Vector3(s * 0.9, y, 6.2), back)
			K.add(g, K.cyl(0.5, 0.5, 0.06, 8), K.glow(Color("ff3b3b")), Vector3(s * 0.9, y, 7.02), back)
	K.greebles(g, 99, Vector3(0, 1.45, 3.4), Vector2(2.6, 3.4), Vector3.UP, 6, gold, 0.5)
	# Skjoldring (synlig glød rundt om skibet; skjules når skjoldet er nede)
	var ring := K.add(g, K.torus(8.5, 0.12, 24, 4), K.glow(Color(0.5, 0.75, 1.0, 1.0)), Vector3(0, 0, 0.5), Vector3(PI / 2, 0, 0))
	ring.name = "Skjold"
	g.set_meta("shield", ring)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 7.05)
	pivot.rotation = back
	g.add_child(pivot)
	for s in [-1.0, 1.0]:
		for y in [-0.6, 0.6]:
			K.add(pivot, K.cyl(0.0, 0.5, 2.4, 8), K.glow(Color("ff3b3b")), Vector3(s * 0.9, 1.2, -y))
			K.add(pivot, K.cyl(0.0, 0.25, 1.4, 8), K.glow(Color("ffe0d0")), Vector3(s * 0.9, 0.7, -y))
	g.set_meta("flame", pivot)
	K.merge(g, [pivot, ring])
	return g
