class_name ShipModel
extends Node3D
## Spillerens skib: et Concord-patruljeskib bygget med ModelKit.
## Næsen peger mod -Z (Godots "fremad"). `paint` er spillerens farve.
## Ca. 9 m langt og 7,4 m bredt.

var paint := Color("ff4f8b")
var thrust := 0.3          ## 0..~2, styrer flammernes længde
var ship_class := "falk"   ## se data/ships.json
## Tilpasning (hangaren): stribe-/accentfarve, motorens glød, flammefarve og lakmønster
var accent := Color("ffd23f")
var engine := Color("4dffe1")
var flame := Color("ff9e3d")
var pattern := "panel"

const PATTERNS := {"panel": 0, "camo": 5, "ternet": 6, "baand": 7, "lyn": 8}
const PATTERN_NAMES := {"panel": "Plader", "camo": "Camouflage", "ternet": "Ternet", "baand": "Bånd", "lyn": "Lyn"}

var _flames: Array[Node3D] = []
var _nav: Array[MeshInstance3D] = []

const K = preload("res://scripts/world/model_kit.gd")


func _ready() -> void:
	match ship_class:
		"hveps": _build_hveps()
		"bison": _build_bison()
		"albatros": _build_albatros()
		"glente": _build_glente()
		"hugorm": _build_hugorm()
		"ravn": _build_ravn()
		"spejder": _build_spejder()
		"fragter": _build_fragter()
		"opmaaler": _build_opmaaler()
		"fregat": _build_fregat()
		"krydser": _build_krydser()
		_: _build_falk()
	# Saml de faste dele i én maske pr. materiale; flammer og lys beholdes for sig
	var keep: Array = []
	keep.append_array(_flames)
	keep.append_array(_nav)
	K.merge(self, keep)


## Tilpasning fra en ordbog (gemt pr. pilot): {paint, accent, engine, flame, pattern}
func apply_look(look: Dictionary) -> void:
	if look.has("paint"):
		paint = Game.col(look["paint"])
	accent = Game.col(look.get("accent", accent.to_html(false)))
	engine = Game.col(look.get("engine", engine.to_html(false)))
	flame = Game.col(look.get("flame", flame.to_html(false)))
	pattern = str(look.get("pattern", pattern))


## Skibets lak: farven med det valgte mønster.
func _body(c: Color) -> StandardMaterial3D:
	return K.hull(c, PATTERNS.get(pattern, 0), 0.35 if pattern == "panel" else 0.22)


## Motorflamme-pivot: skaleres i _process efter fart.
func _flame(pos: Vector3, r: float, col := Color(0, 0, 0, 0)) -> void:
	if col.a == 0.0:
		col = flame
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation = Vector3(PI / 2, 0, 0)
	add_child(pivot)
	K.add(pivot, K.cyl(0.0, r, 2.0, 8), K.glow(col), Vector3(0, 1, 0))
	K.add(pivot, K.cyl(0.0, r * 0.55, 1.4, 8), K.glow(Color("fff3b0")), Vector3(0, 0.7, 0))
	_flames.append(pivot)


## Hveps-interceptor: lang, smal næse, små pilevinger langt tilbage, én stor motor.
func _build_hveps() -> void:
	var body := _body(paint.lerp(Color.WHITE, 0.1))
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var yellow := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(1.0, 0.8, 4.4), body, Vector3(0, 0, 0.8))
	K.add(self, K.wedge(1.0, 3.6, 0.8), body, Vector3(0, 0, -3.2), fwd)
	K.add(self, K.box(1.1, 0.12, 5.6), yellow, Vector3(0, 0.42, -0.2))
	var canopy := K.add(self, K.sphere(0.45, 8, 6), K.glass(Color("2ec4d6")), Vector3(0, 0.45, -1.0))
	canopy.scale = Vector3(0.9, 0.7, 2.4)
	for s in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(s * 0.5, 0, 2.0)
		wing.rotation = Vector3(0, -s * 0.6, 0)
		add_child(wing)
		K.add(wing, K.box(2.6, 0.12, 1.2), body, Vector3(s * 1.3, 0, 0))
		K.add(wing, K.box(0.3, 0.9, 1.4), dark, Vector3(s * 2.6, 0.3, 0.1))
		_nav.append(K.add(wing, K.box(0.2, 0.2, 0.2), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 2.6, 0.8, 0.5)))
		K.add(self, K.cyl(0.08, 0.1, 1.6, 6), darker, Vector3(s * 0.9, -0.2, -2.2), fwd)
		K.add(self, K.box(0.12, 0.7, 0.9), body, Vector3(s * 0.35, 0.55, 2.6), Vector3(0, 0, -s * 0.3))
	K.add(self, K.cyl(0.62, 0.7, 1.8, 8), dark, Vector3(0, 0, 3.6), back)
	K.add(self, K.torus(0.6, 0.15, 10, 4), K.hull(paint, K.TEX_PLATING, 0.6), Vector3(0, 0, 2.8), back)
	K.add(self, K.cyl(0.5, 0.5, 0.06, 8), K.glow(engine), Vector3(0, 0, 4.52), back)
	_flame(Vector3(0, 0, 4.55), 0.48)


## Bison-kanonbåd: bred, pansret og kantet, fire kanoner og to tunge motorer.
func _build_bison() -> void:
	var armor := _body(Color("6a6f8a").lerp(paint, 0.25))
	var body := _body(paint.lerp(Color("3a3f5a"), 0.35))
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(3.0, 1.6, 5.6), armor, Vector3(0, 0, 0.4))
	K.add(self, K.wedge(3.0, 2.0, 1.6), armor, Vector3(0, 0, -3.2), fwd)
	K.add(self, K.box(2.2, 0.6, 3.4), body, Vector3(0, 1.0, 0.2))
	K.add(self, K.box(1.4, 0.4, 0.9), K.glass(Color("2ec4d6")), Vector3(0, 1.1, -1.5))
	K.add(self, K.box(3.2, 0.3, 4.0), K.stripes(0.6), Vector3(0, -0.9, 0.6))
	for s in [-1.0, 1.0]:
		# Sidepansring og korte, tykke vinger med kanontårne
		K.add(self, K.box(0.5, 1.4, 4.6), dark, Vector3(s * 1.7, 0, 0.6))
		K.add(self, K.box(1.8, 0.4, 2.6), armor, Vector3(s * 2.4, 0.1, 0.0))
		K.add(self, K.box(0.7, 0.6, 1.2), dark, Vector3(s * 3.0, 0.3, -0.4))
		K.add(self, K.cyl(0.14, 0.18, 2.0, 6), darker, Vector3(s * 3.0, 0.2, -1.6), fwd)
		K.add(self, K.cyl(0.14, 0.18, 1.6, 6), darker, Vector3(s * 1.6, -0.9, -2.4), fwd)
		_nav.append(K.add(self, K.box(0.24, 0.24, 0.24), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.3, 0.6, 0.6)))
		# Motorer
		K.add(self, K.box(1.2, 1.2, 2.4), dark, Vector3(s * 1.0, 0, 3.8))
		K.add(self, K.cyl(0.55, 0.65, 0.6, 8), darker, Vector3(s * 1.0, 0, 5.2), back)
		K.add(self, K.cyl(0.48, 0.48, 0.06, 8), K.glow(engine), Vector3(s * 1.0, 0, 5.5), back)
		_flame(Vector3(s * 1.0, 0, 5.55), 0.5)
	K.greebles(self, 9, Vector3(0, 1.3, 0.6), Vector2(1.8, 2.4), Vector3.UP, 5, dark, 0.35)
	K.add(self, K.cyl(0.04, 0.06, 1.4, 4), K.flat(Color("d9d2ff")), Vector3(0.6, 1.9, 1.2))


## Albatros-fragter: cockpit foran, lastmoduler på en ryg, fire små motorer.
func _build_albatros() -> void:
	var white := K.hull(Color("e8e6ff"))
	var body := _body(paint.lerp(Color.WHITE, 0.2))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(2.2, 1.6, 2.6), white, Vector3(0, 0.3, -3.4))
	K.add(self, K.wedge(2.2, 1.4, 1.6), white, Vector3(0, 0.3, -5.4), fwd)
	K.add(self, K.box(1.8, 0.5, 0.1), K.glow(engine), Vector3(0, 0.75, -4.75))
	K.add(self, K.box(2.3, 0.3, 2.0), body, Vector3(0, 1.2, -3.4))
	K.add(self, K.box(0.9, 0.9, 7.0), dark, Vector3(0, 0, 0.8))
	var cols := [paint, Color("4dd0ff"), Color("ffd23f")]
	for k in 3:
		for s in [-1.0, 1.0]:
			K.add(self, K.box(1.3, 1.5, 1.8), K.hull(cols[k], K.TEX_PLATING, 0.7), Vector3(s * 0.95, 0.15, -1.2 + k * 2.0))
	for s in [-1.0, 1.0]:
		K.add(self, K.box(2.6, 0.2, 1.2), body, Vector3(s * 2.4, 0, 1.8))
		K.add(self, K.cyl(0.1, 0.12, 1.4, 6), darker, Vector3(s * 1.8, 0.6, -4.2), fwd)
		_nav.append(K.add(self, K.box(0.22, 0.22, 0.22), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.7, 0, 1.8)))
		for e in [1.2, 3.0]:
			var x: float = s * e
			K.add(self, K.cyl(0.38, 0.45, 1.6, 8), dark, Vector3(x, 0, 2.8), back)
			K.add(self, K.cyl(0.32, 0.32, 0.06, 8), K.glow(engine), Vector3(x, 0, 3.62), back)
			_flame(Vector3(x, 0, 3.65), 0.32)


func _build_falk() -> void:
	var white := K.hull(Color("e8e6ff"))
	var body := _body(paint.lerp(Color.WHITE, 0.15))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var accent := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)     # cylindre/kiler: top/spids mod -Z
	var back := Vector3(PI / 2, 0, 0)     # top mod +Z

	# Skrog, næse og bug
	K.add(self, K.box(1.6, 1.1, 5.2), white, Vector3(0, 0, 0.2))
	K.add(self, K.wedge(1.6, 2.6, 1.1), white, Vector3(0, 0, -3.7), fwd)
	K.add(self, K.wedge(0.5, 0.9, 0.42), body, Vector3(0, 0.05, -5.35), fwd)
	K.add(self, K.box(1.7, 0.16, 3.4), body, Vector3(0, 0.6, -0.4))         # farvestribe på ryggen
	K.add(self, K.box(1.2, 0.28, 4.2), dark, Vector3(0, -0.66, 0.4))       # bugplade
	K.add(self, K.box(0.5, 0.2, 2.4), K.stripes(0.6), Vector3(0, -0.84, 0.6))
	# Cockpit med ramme
	var canopy := K.add(self, K.sphere(0.6, 8, 6), K.glass(Color("2ec4d6")), Vector3(0, 0.62, -1.5))
	canopy.scale = Vector3(0.95, 0.75, 2.1)
	K.add(self, K.box(0.08, 0.5, 2.4), darker, Vector3(0, 0.95, -1.5))
	K.add(self, K.box(1.1, 0.42, 0.1), darker, Vector3(0, 0.78, -0.8))
	# Ryg med antenne og detaljer
	K.add(self, K.box(0.55, 0.42, 2.8), body, Vector3(0, 0.75, 1.3))
	K.greebles(self, 3, Vector3(0, 0.96, 1.4), Vector2(0.5, 2.4), Vector3.UP, 4, dark, 0.35)
	K.add(self, K.cyl(0.03, 0.05, 1.0, 4), K.flat(Color("d9d2ff")), Vector3(0.3, 1.4, 0.4))
	# Luftindtag på siderne
	for s in [-1.0, 1.0]:
		K.add(self, K.box(0.5, 0.7, 1.6), dark, Vector3(s * 0.98, -0.05, -0.6))
		K.add(self, K.box(0.42, 0.55, 0.08), darker, Vector3(s * 0.98, -0.05, -1.42))
		# Canard ved næsen
		K.add(self, K.box(0.9, 0.08, 0.5), body, Vector3(s * 1.1, 0.1, -2.4), Vector3(0, s * 0.3, 0))

	# Vinger (pilformede) med stribe, flaps, vingespids og kanon
	for s in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(s * 0.8, 0.0, 0.7)
		wing.rotation = Vector3(0, -s * 0.33, -s * 0.06)
		add_child(wing)
		K.add(wing, K.box(2.8, 0.18, 1.8), body, Vector3(s * 1.4, 0, 0))
		K.add(wing, K.box(2.8, 0.14, 0.5), white, Vector3(s * 1.4, 0.02, -1.1))       # forkant
		K.add(wing, K.box(2.2, 0.06, 0.26), K.flat(Color.WHITE), Vector3(s * 1.3, 0.12, -0.25))
		K.add(wing, K.box(2.3, 0.12, 0.45), dark, Vector3(s * 1.25, -0.02, 1.08))      # flaps
		K.add(wing, K.box(0.42, 0.46, 2.3), accent, Vector3(s * 2.9, 0, 0.0))         # vingespids
		K.add(wing, K.cyl(0.09, 0.11, 1.5, 6), darker, Vector3(s * 2.9, -0.05, -1.75), fwd)
		K.add(wing, K.cyl(0.13, 0.13, 0.12, 6), K.glow(Color("ff9ed2")), Vector3(s * 2.9, -0.05, -2.52), fwd)
		_nav.append(K.add(wing, K.box(0.22, 0.22, 0.22), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.14, 0, 0.7)))
		# Haleror (skrå)
		var fin := Node3D.new()
		fin.position = Vector3(s * 0.55, 0.5, 2.3)
		fin.rotation = Vector3(-0.25, 0, -s * 0.35)
		add_child(fin)
		K.add(fin, K.box(0.14, 1.4, 1.2), body, Vector3(0, 0.7, 0))
		K.add(fin, K.box(0.16, 0.25, 1.25), white, Vector3(0, 1.35, 0))
		K.add(fin, K.box(0.18, 0.18, 0.18), K.glow(Color.WHITE), Vector3(0, 1.48, 0.55))

		# Motor: nacelle, indtagsring, dyse, glød og flamme
		var ex: float = s * 0.95
		K.add(self, K.cyl(0.5, 0.58, 2.2, 8), dark, Vector3(ex, -0.1, 2.0), back)
		K.add(self, K.torus(0.52, 0.16, 10, 4), K.hull(paint, K.TEX_PLATING, 0.6), Vector3(ex, -0.1, 1.0), back)
		K.add(self, K.cyl(0.38, 0.52, 0.5, 8), darker, Vector3(ex, -0.1, 3.3), back)
		K.add(self, K.cyl(0.34, 0.34, 0.06, 8), K.glow(engine), Vector3(ex, -0.1, 3.56), back)
		K.add(self, K.torus(0.42, 0.1, 10, 4), K.glow(engine), Vector3(ex, -0.1, 3.5), back)
		var pivot := Node3D.new()
		pivot.position = Vector3(ex, -0.1, 3.58)
		pivot.rotation = back
		add_child(pivot)
		K.add(pivot, K.cyl(0.0, 0.38, 2.0, 8), K.glow(flame), Vector3(0, 1, 0))
		K.add(pivot, K.cyl(0.0, 0.2, 1.4, 8), K.glow(Color("fff3b0")), Vector3(0, 0.7, 0))
		_flames.append(pivot)


# ---------------------------------------------------------------- nye skibe

## Glente-angrebsjager: bred deltavinge med kanonpods på spidserne og to motorer.
func _build_glente() -> void:
	var body := _body(paint.lerp(Color.WHITE, 0.12))
	var white := K.hull(Color("e8e6ff"))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(1.5, 1.0, 5.0), white, Vector3(0, 0.1, 0.0))
	K.add(self, K.wedge(1.5, 2.8, 1.0), white, Vector3(0, 0.1, -3.9), fwd)
	K.add(self, K.box(1.6, 0.14, 4.0), acc, Vector3(0, 0.66, -0.2))
	var canopy := K.add(self, K.sphere(0.55, 8, 6), K.glass(Color("2ec4d6")), Vector3(0, 0.7, -1.7))
	canopy.scale = Vector3(0.9, 0.7, 2.0)
	for s in [-1.0, 1.0]:
		# Deltavinge: en kile, der breder sig bagud
		var wing := Node3D.new()
		wing.position = Vector3(s * 0.75, 0, 0.6)
		add_child(wing)
		K.add(wing, K.wedge(3.6, 4.6, 0.16, 0.0 if s > 0 else 1.0), body, Vector3(s * 1.8, 0, 0.4), Vector3(-PI / 2, 0, 0))
		K.add(wing, K.box(3.2, 0.1, 0.3), white, Vector3(s * 1.5, 0.1, 1.6))
		# Kanonpod på vingespidsen
		K.add(wing, K.box(0.5, 0.5, 2.4), acc, Vector3(s * 2.7, -0.1, -0.6))
		K.add(wing, K.cyl(0.09, 0.12, 1.6, 6), darker, Vector3(s * 2.7, -0.1, -2.4), fwd)
		_nav.append(K.add(wing, K.box(0.22, 0.22, 0.22), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.0, 0, 0.6)))
		# Kanoner under næsen og motorer
		K.add(self, K.cyl(0.08, 0.1, 1.4, 6), darker, Vector3(s * 0.55, -0.45, -3.0), fwd)
		K.add(self, K.cyl(0.48, 0.55, 2.0, 8), dark, Vector3(s * 0.7, 0.0, 2.6), back)
		K.add(self, K.cyl(0.36, 0.36, 0.06, 8), K.glow(engine), Vector3(s * 0.7, 0.0, 3.62), back)
		_flame(Vector3(s * 0.7, 0.0, 3.65), 0.38)
		var fin := K.add(self, K.box(0.12, 1.3, 1.2), body, Vector3(s * 0.4, 1.0, 2.2))
		fin.rotation = Vector3(-0.3, 0, -s * 0.25)
	K.greebles(self, 21, Vector3(0, 0.75, 1.2), Vector2(0.9, 2.0), Vector3.UP, 4, dark, 0.3)


## Hugorm-interceptor: smal krop, fremadbøjede vinger og én stor motor.
func _build_hugorm() -> void:
	var body := _body(paint.lerp(Color("23203a"), 0.15))
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(0.8, 0.7, 5.6), body, Vector3(0, 0, 0.6))
	K.add(self, K.wedge(0.8, 3.0, 0.7), body, Vector3(0, 0, -3.6), fwd)
	K.add(self, K.box(0.84, 0.1, 5.0), acc, Vector3(0, 0.38, 0.2))
	var canopy := K.add(self, K.sphere(0.38, 8, 6), K.glass(Color("ff7a3d")), Vector3(0, 0.42, -1.6))
	canopy.scale = Vector3(0.9, 0.7, 2.6)
	for s in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(s * 0.4, -0.05, 2.0)
		wing.rotation = Vector3(0, s * 0.45, 0)     # fremadbøjet
		add_child(wing)
		K.add(wing, K.box(3.0, 0.1, 1.0), body, Vector3(s * 1.5, 0, 0))
		K.add(wing, K.box(0.3, 0.3, 1.4), acc, Vector3(s * 3.0, 0, 0.0))
		_nav.append(K.add(wing, K.box(0.18, 0.18, 0.18), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.1, 0.2, 0.0)))
		K.add(self, K.cyl(0.07, 0.09, 1.4, 6), darker, Vector3(s * 0.9, -0.2, -2.4), fwd)
		K.add(self, K.box(0.1, 0.8, 1.0), body, Vector3(s * 0.3, 0.6, 3.0), Vector3(0, 0, -s * 0.5))
	K.add(self, K.cyl(0.7, 0.8, 2.2, 10), dark, Vector3(0, 0, 4.2), back)
	K.add(self, K.torus(0.7, 0.14, 12, 4), K.glow(engine), Vector3(0, 0, 5.2), back)
	K.add(self, K.cyl(0.6, 0.6, 0.06, 10), K.glow(engine), Vector3(0, 0, 5.32), back)
	_flame(Vector3(0, 0, 5.35), 0.6)


## Ravn-dusørjæger: kantet, bred krop, to store sidemotorer og tunge kanoner.
func _build_ravn() -> void:
	var body := _body(paint.lerp(Color("6a6f8a"), 0.45))
	var plate := K.hull(Color("8a8fa8"), K.TEX_PLATING, 0.45)
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(2.6, 1.8, 6.4), plate, Vector3(0, 0, 0.4))
	K.add(self, K.wedge(2.6, 1.8, 1.8), body, Vector3(0, -0.1, -3.8), fwd)
	K.add(self, K.box(2.0, 0.6, 4.0), body, Vector3(0, 1.1, 0.4))
	K.add(self, K.box(1.4, 0.5, 0.12), K.glow(Color("ff9e3d")), Vector3(0, 0.55, -2.9))   # vinduesbånd
	K.add(self, K.box(2.7, 0.25, 0.6), acc, Vector3(0, 0.55, 2.2))
	for s in [-1.0, 1.0]:
		# Sidemotorer på korte bjælker
		K.add(self, K.box(1.2, 0.5, 1.4), dark, Vector3(s * 1.9, 0.0, 1.4))
		K.add(self, K.box(1.4, 1.4, 4.4), body, Vector3(s * 2.9, 0.0, 1.2))
		K.add(self, K.cyl(0.6, 0.7, 0.6, 8), darker, Vector3(s * 2.9, 0.0, 3.7), back)
		K.add(self, K.cyl(0.52, 0.52, 0.06, 8), K.glow(engine), Vector3(s * 2.9, 0.0, 4.02), back)
		_flame(Vector3(s * 2.9, 0.0, 4.05), 0.52)
		K.add(self, K.box(1.5, 0.3, 1.0), acc, Vector3(s * 2.9, 0.75, -0.4))
		_nav.append(K.add(self, K.box(0.24, 0.24, 0.24), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.65, 0.5, 1.2)))
		# Tunge kanoner
		K.add(self, K.cyl(0.13, 0.16, 2.2, 6), darker, Vector3(s * 2.6, -0.4, -2.2), fwd)
		K.add(self, K.cyl(0.1, 0.12, 1.6, 6), darker, Vector3(s * 0.8, -1.0, -3.3), fwd)
		# Landingsben
		K.add(self, K.box(0.2, 0.6, 0.2), darker, Vector3(s * 1.0, -1.15, 1.6))
	K.greebles(self, 31, Vector3(0, 1.45, 0.4), Vector2(1.6, 3.2), Vector3.UP, 6, dark, 0.35)


## Frontier-spejder: lille kugleformet cockpit, en antennebom og to små motorer.
func _build_spejder() -> void:
	var body := _body(paint.lerp(Color.WHITE, 0.25))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(1.1, 0.9, 3.6), body, Vector3(0, 0, 0.4))
	K.add(self, K.wedge(1.1, 1.8, 0.9), body, Vector3(0, 0, -2.3), fwd)
	var canopy := K.add(self, K.sphere(0.5, 8, 6), K.glass(Color("2ec4d6")), Vector3(0, 0.45, -0.9))
	canopy.scale = Vector3(1.0, 0.8, 1.5)
	K.add(self, K.cyl(0.03, 0.03, 3.0, 4), K.flat(Color("d9d2ff")), Vector3(0, 0.6, -2.4), fwd)
	K.add(self, K.sphere(0.12, 6, 4), K.glow(Color("4dff6a")), Vector3(0, 0.6, -3.9))
	K.add(self, K.cyl(0.5, 0.05, 0.15, 10), acc, Vector3(0, 1.05, 0.8))     # scannerskål
	K.add(self, K.cyl(0.03, 0.03, 0.5, 4), darker, Vector3(0, 0.75, 0.8))
	for s in [-1.0, 1.0]:
		K.add(self, K.box(1.4, 0.1, 0.9), body, Vector3(s * 1.1, -0.1, 1.0), Vector3(0, -s * 0.2, 0))
		_nav.append(K.add(self, K.box(0.18, 0.18, 0.18), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 1.8, 0, 1.0)))
		K.add(self, K.cyl(0.28, 0.32, 1.2, 8), dark, Vector3(s * 0.55, -0.1, 2.6), back)
		K.add(self, K.cyl(0.22, 0.22, 0.06, 8), K.glow(engine), Vector3(s * 0.55, -0.1, 3.22), back)
		_flame(Vector3(s * 0.55, -0.1, 3.25), 0.24)


## Frontier-fragtskib: lang rygbjælke med store containere, førerhus foran.
func _build_fragter() -> void:
	var white := K.hull(Color("d8d4f0"))
	var body := _body(paint.lerp(Color.WHITE, 0.25))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(2.6, 2.0, 2.6), white, Vector3(0, 0.6, -5.0))
	K.add(self, K.wedge(2.6, 1.2, 2.0), white, Vector3(0, 0.6, -6.9), fwd)
	K.add(self, K.box(2.2, 0.4, 0.12), K.glow(Color("4dffe1")), Vector3(0, 1.1, -6.35))
	K.add(self, K.box(2.7, 0.3, 2.0), body, Vector3(0, 1.7, -5.0))
	K.add(self, K.box(1.0, 1.0, 10.0), dark, Vector3(0, 0, 0.6))
	var cols := [paint, accent, Color("4dd0ff"), Color("e8b13a")]
	for k in 4:
		K.add(self, K.box(3.4, 2.4, 2.0), K.hull(cols[k], K.TEX_PLATING, 0.5), Vector3(0, 0.4, -2.6 + k * 2.3))
		K.add(self, K.box(3.5, 0.15, 0.3), K.stripes(0.5), Vector3(0, 1.65, -3.45 + k * 2.3))
	for s in [-1.0, 1.0]:
		_nav.append(K.add(self, K.box(0.24, 0.24, 0.24), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 1.8, 0.6, -5.0)))
		K.add(self, K.cyl(0.1, 0.12, 1.2, 6), darker, Vector3(s * 1.6, 0.8, -5.8), fwd)
		K.add(self, K.cyl(0.6, 0.7, 2.0, 8), dark, Vector3(s * 1.0, 0, 7.0), back)
		K.add(self, K.cyl(0.52, 0.52, 0.06, 8), K.glow(engine), Vector3(s * 1.0, 0, 8.02), back)
		_flame(Vector3(s * 1.0, 0, 8.05), 0.5)


## Opmålingsskib: slank krop med en stor sensorring og to sensorbomme.
func _build_opmaaler() -> void:
	var white := K.hull(Color("e8e6ff"))
	var body := _body(paint.lerp(Color.WHITE, 0.2))
	var dark := K.hull(Color("4a4f72"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(1.6, 1.2, 6.0), white, Vector3(0, 0, 0.4))
	K.add(self, K.wedge(1.6, 2.2, 1.2), white, Vector3(0, 0, -3.5), fwd)
	K.add(self, K.box(1.7, 0.16, 5.0), body, Vector3(0, 0.66, 0.0))
	var canopy := K.add(self, K.sphere(0.55, 8, 6), K.glass(Color("2ec4d6")), Vector3(0, 0.6, -1.9))
	canopy.scale = Vector3(1.0, 0.7, 1.8)
	# Sensorring rundt om skroget
	K.add(self, K.torus(2.2, 0.22, 20, 4), acc, Vector3(0, 0, 0.6), back)
	for k in 6:
		var a := TAU * k / 6.0
		_nav.append(K.add(self, K.box(0.2, 0.2, 0.2), K.glow(engine), Vector3(cos(a) * 2.2, sin(a) * 2.2, 0.6)))
	for s in [-1.0, 1.0]:
		K.add(self, K.box(0.18, 0.18, 2.2), dark, Vector3(s * 1.1, 0, 0.6), Vector3(0, 0, 0))
		K.add(self, K.cyl(0.03, 0.03, 2.4, 4), K.flat(Color("d9d2ff")), Vector3(s * 0.5, 0.2, -4.0), fwd)
		K.add(self, K.sphere(0.14, 6, 4), K.glow(Color("ff4fd8")), Vector3(s * 0.5, 0.2, -5.2))
		K.add(self, K.cyl(0.08, 0.1, 1.2, 6), darker, Vector3(s * 1.2, -0.4, -2.6), fwd)
		K.add(self, K.cyl(0.42, 0.5, 1.6, 8), dark, Vector3(s * 0.6, 0, 4.0), back)
		K.add(self, K.cyl(0.34, 0.34, 0.06, 8), K.glow(engine), Vector3(s * 0.6, 0, 4.82), back)
		_flame(Vector3(s * 0.6, 0, 4.85), 0.36)
	K.add(self, K.cyl(0.9, 0.1, 0.2, 12), acc, Vector3(0, 1.0, 1.8))
	K.add(self, K.cyl(0.04, 0.04, 0.5, 4), darker, Vector3(0, 0.8, 1.8))


## Fregat: kantet krigsskib med to kanontårne på ryggen og sidepansring.
func _build_fregat() -> void:
	var armor := _body(Color("6a6f8a").lerp(paint, 0.3))
	var plate := K.hull(Color("8a8fa8"), K.TEX_PLATING, 0.4)
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.6)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.6)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(3.6, 2.0, 9.0), plate, Vector3(0, 0, 0.5))
	K.add(self, K.wedge(3.6, 3.0, 2.0), armor, Vector3(0, 0, -5.5), fwd)
	K.add(self, K.box(2.4, 1.6, 2.2), armor, Vector3(0, 1.6, 2.2))            # bro
	K.add(self, K.box(2.0, 0.4, 0.12), K.glow(Color("4dffe1")), Vector3(0, 1.9, 1.08))
	K.add(self, K.box(3.7, 0.3, 6.0), K.stripes(0.45), Vector3(0, -1.05, 0.5))
	for z in [-3.0, -0.6]:
		K.add(self, K.cyl(0.8, 0.9, 0.5, 8), dark, Vector3(0, 1.2, z))
		for s in [-1.0, 1.0]:
			K.add(self, K.cyl(0.1, 0.12, 1.8, 6), darker, Vector3(s * 0.3, 1.4, z - 1.0), fwd)
	for s in [-1.0, 1.0]:
		K.add(self, K.box(0.6, 1.6, 7.0), armor, Vector3(s * 2.1, -0.1, 0.6))
		K.add(self, K.box(1.2, 0.5, 1.6), acc, Vector3(s * 2.9, -0.6, -1.0))
		K.add(self, K.cyl(0.12, 0.14, 1.6, 6), darker, Vector3(s * 3.2, -0.6, -2.4), fwd)
		_nav.append(K.add(self, K.box(0.28, 0.28, 0.28), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 2.45, 0.8, 3.8)))
		K.add(self, K.box(1.4, 1.4, 1.8), dark, Vector3(s * 1.1, 0, 5.6))
		K.add(self, K.cyl(0.6, 0.7, 0.4, 8), darker, Vector3(s * 1.1, 0, 6.7), back)
		K.add(self, K.cyl(0.55, 0.55, 0.06, 8), K.glow(engine), Vector3(s * 1.1, 0, 6.92), back)
		_flame(Vector3(s * 1.1, 0, 6.95), 0.55)
	K.greebles(self, 41, Vector3(0, 1.05, -1.8), Vector2(3.0, 4.0), Vector3.UP, 8, dark, 0.45)


## Krydser: stort, langt krigsskib med seks kanontårne og en høj bro.
func _build_krydser() -> void:
	var armor := _body(Color("6a6f8a").lerp(paint, 0.3))
	var plate := K.hull(Color("9a9fb8"), K.TEX_PLATING, 0.35)
	var dark := K.hull(Color("3a3f5a"), K.TEX_PLATING, 0.5)
	var darker := K.flat(Color("23203a"))
	var acc := K.hull(accent, K.TEX_PLATING, 0.5)
	var fwd := Vector3(-PI / 2, 0, 0)
	var back := Vector3(PI / 2, 0, 0)
	K.add(self, K.box(5.0, 2.8, 14.0), plate, Vector3(0, 0, 0.5))
	K.add(self, K.wedge(5.0, 4.0, 2.8), armor, Vector3(0, 0, -8.5), fwd)
	K.add(self, K.box(3.0, 2.6, 3.0), armor, Vector3(0, 2.4, 3.6))
	K.add(self, K.box(2.6, 1.2, 1.6), armor, Vector3(0, 4.0, 3.2))
	K.add(self, K.box(2.4, 0.4, 0.12), K.glow(Color("4dffe1")), Vector3(0, 4.2, 2.38))
	K.add(self, K.cyl(0.05, 0.08, 2.4, 4), K.flat(Color("d9d2ff")), Vector3(0.8, 5.6, 3.4))
	K.add(self, K.box(5.1, 0.35, 10.0), K.stripes(0.4), Vector3(0, -1.45, 0.5))
	K.add(self, K.box(5.1, 0.3, 1.0), acc, Vector3(0, 1.45, -5.0))
	for z in [-5.5, -2.5]:
		K.add(self, K.cyl(1.0, 1.1, 0.6, 8), dark, Vector3(0, 1.7, z))
		for s in [-1.0, 1.0]:
			K.add(self, K.cyl(0.12, 0.15, 2.4, 6), darker, Vector3(s * 0.4, 1.9, z - 1.3), fwd)
	for s in [-1.0, 1.0]:
		K.add(self, K.box(0.8, 2.4, 11.0), armor, Vector3(s * 2.9, -0.1, 0.8))
		for z in [-2.0, 2.0]:
			K.add(self, K.cyl(0.6, 0.7, 0.5, 8), dark, Vector3(s * 3.5, 0.0, z), Vector3(0, 0, s * PI / 2))
			K.add(self, K.cyl(0.1, 0.13, 1.8, 6), darker, Vector3(s * 4.0, 0.0, z - 1.0), fwd)
		K.add(self, K.cyl(0.1, 0.13, 1.8, 6), darker, Vector3(s * 2.0, -1.6, -7.4), fwd)
		_nav.append(K.add(self, K.box(0.32, 0.32, 0.32), K.glow(Color("4dff6a") if s > 0 else Color("ff3b3b")), Vector3(s * 3.35, 1.2, 5.6)))
		for e in [0.9, 2.3]:
			K.add(self, K.box(1.3, 1.3, 2.2), dark, Vector3(s * e, 0, 8.4))
			K.add(self, K.cyl(0.55, 0.62, 0.4, 8), darker, Vector3(s * e, 0, 9.7), back)
			K.add(self, K.cyl(0.5, 0.5, 0.06, 8), K.glow(engine), Vector3(s * e, 0, 9.92), back)
			_flame(Vector3(s * e, 0, 9.95), 0.5)
	K.greebles(self, 51, Vector3(0, 1.45, -0.5), Vector2(4.2, 6.0), Vector3.UP, 10, dark, 0.5)
	for k in 8:
		K.add(self, K.box(0.3, 0.2, 0.2), K.glow(Color("ffd23f")), Vector3(-2.2 + k * 0.63, 0.4, -6.9))


func _process(_delta: float) -> void:
	var flame_len := 0.25 + thrust * 1.4 + randf() * 0.15
	for f in _flames:
		f.scale = Vector3(1, flame_len, 1)
	var blink := (Time.get_ticks_msec() / 450) % 2 == 0
	for n in _nav:
		n.visible = blink


# Hjælpere, som andre scripts stadig bruger
static func _mat(c: Color) -> StandardMaterial3D:
	return ModelKit.flat(c)


static func _unshaded(c: Color) -> StandardMaterial3D:
	return ModelKit.glow(c)


static func _cyl(top: float, bottom: float, h: float, seg: int) -> CylinderMesh:
	return ModelKit.cyl(top, bottom, h, seg)


static func _box(x: float, y: float, z: float) -> BoxMesh:
	return ModelKit.box(x, y, z)


static func _sphere(r: float) -> SphereMesh:
	return ModelKit.sphere(r)
