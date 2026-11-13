class_name Universe
extends Node3D
## Bygger alle solsystemer ud fra data/universe.json og svarer på spørgsmål om
## verden: nærmeste planet, landingsmål, trade lanes og jump gates.
##
## Systemerne ligger i samme 3D-verden, men langt fra hinanden (fx 40 km),
## så de aldrig er synlige samtidig.

const LANE_SPEED := 190.0
const LANE_ENTRY_RADIUS := 14.0
const GATE_RADIUS := 16.0
const LAND_RANGE := 40.0
const DOCK_RANGE := 30.0

var planets: Array[PlanetBody] = []
var stations: Array[StationBody] = []
var lanes: Array[Dictionary] = []     ## {a, b, system}
var gates: Dictionary = {}            ## id -> {id, system, pos, dir, to, label, disc}
var origins: Dictionary = {}          ## system-id -> Vector3


func _ready() -> void:
	for sys_id: String in Game.systems:
		var sys: Dictionary = Game.systems[sys_id]
		var origin := Game.vec(sys["origin"])
		origins[sys_id] = origin
		for p: Dictionary in sys.get("planets", []):
			var body := PlanetBody.new()
			body.setup(p, origin)
			add_child(body)
			planets.append(body)
		for s: Dictionary in sys.get("stations", []):
			var st := StationBody.new()
			st.setup(s, origin)
			add_child(st)
			stations.append(st)
	for sys_id: String in Game.systems:
		var sys: Dictionary = Game.systems[sys_id]
		for l: Dictionary in sys.get("lanes", []):
			_build_lane(sys_id, l)
		for g: Dictionary in sys.get("gates", []):
			_build_gate(sys_id, g)


# ---------------------------------------------------------------- forespørgsler

func system_at(pos: Vector3) -> String:
	var best := ""
	var bd := INF
	for sys_id: String in origins:
		var d: float = pos.distance_to(origins[sys_id])
		if d < bd:
			bd = d
			best = sys_id
	return best


func nearest_planet(pos: Vector3) -> PlanetBody:
	var best: PlanetBody = null
	var ba := INF
	for p in planets:
		var a := p.altitude(pos)
		if a < ba:
			ba = a
			best = p
	return best


func planet(id: String) -> PlanetBody:
	for p in planets:
		if p.id == id:
			return p
	return null


func station(id: String) -> StationBody:
	for s in stations:
		if s.id == id:
			return s
	return null


## Concord-basen i et system, hvis der er en.
func home_base(sys_id: String) -> StationBody:
	for s in stations:
		if s.is_base and s.system_id == sys_id:
			return s
	return null


## Landingsplads for en by eller et mindre sted på en planet: {planet, pad} eller tom.
func pad_of(loc_id: String) -> Dictionary:
	for p in planets:
		var pad := p.pad_by_id(loc_id)
		if not pad.is_empty():
			return {"planet": p, "pad": pad}
	return {}


func body_position(id: String) -> Vector3:
	var po := pad_of(id)
	if not po.is_empty():
		return po["pad"]["top"]
	var s := station(id)
	return s.dock_pos if s else Vector3.ZERO


## Nærmeste sted man kan lande/docke fra pos, eller tom ordbog.
## Returnerer {id, kind, distance, name}.
func landing_spot(pos: Vector3) -> Dictionary:
	var best := {}
	var bd := INF
	for p in planets:
		for pad in p.pads:
			var d := pos.distance_to(pad["top"])
			if d < LAND_RANGE and d < bd:
				bd = d
				best = {"id": pad["id"], "kind": "planet", "distance": d, "name": pad["name"]}
	for s in stations:
		var d := pos.distance_to(s.dock_pos)
		if d < DOCK_RANGE and d < bd:
			bd = d
			best = {"id": s.id, "kind": "station", "distance": d, "name": s.display_name}
	if W.sites:
		var site := W.sites.landing_spot(pos)
		if not site.is_empty() and float(site["distance"]) < bd:
			best = site
	return best


## Hvis pos er i en trade lanes ende, returneres {a, b}. Ellers tom.
func lane_entry(pos: Vector3) -> Dictionary:
	for l in lanes:
		if pos.distance_to(l["a"]) < LANE_ENTRY_RADIUS:
			return {"a": l["a"], "b": l["b"]}
		if pos.distance_to(l["b"]) < LANE_ENTRY_RADIUS:
			return {"a": l["b"], "b": l["a"]}
	return {}


func gate_at(pos: Vector3) -> Dictionary:
	for id: String in gates:
		if pos.distance_to(gates[id]["pos"]) < GATE_RADIUS:
			return gates[id]
	return {}


## Interessepunkter i et system til HUD-markører: [{label, pos, kind}]
func points_of_interest(sys_id: String, from: Vector3) -> Array:
	var out := []
	for p in planets:
		if p.system_id == sys_id:
			out.append({"label": p.display_name.to_upper(), "pos": p.pad_top, "kind": "planet"})
			# Mindre steder vises kun, når man er tæt på planeten
			if p.altitude(from) < 1200.0:
				for pad in p.pads.slice(1):
					out.append({"label": str(pad["name"]).to_upper(), "pos": pad["top"], "kind": "plot" if pad["style"] == "plot" else "outpost"})
	for s in stations:
		if s.system_id == sys_id:
			var kind := "base" if s.is_base else ("plot" if s.data.get("plot", false) else "station")
			out.append({"label": s.display_name.to_upper(), "pos": s.dock_pos, "kind": kind})
	for id: String in gates:
		var g: Dictionary = gates[id]
		if g["system"] == sys_id:
			out.append({"label": g["label"], "pos": g["pos"], "kind": "gate"})
	var near_lane := {}
	var nd := 1600.0
	for l in lanes:
		if l["system"] != sys_id:
			continue
		for k: String in ["a", "b"]:
			var d: float = from.distance_to(l[k])
			if d < nd:
				nd = d
				near_lane = {"label": "TRADE LANE", "pos": l[k], "kind": "lane"}
	if not near_lane.is_empty():
		out.append(near_lane)
	return out


func _process(delta: float) -> void:
	for id: String in gates:
		var disc: MeshInstance3D = gates[id]["disc"]
		disc.rotate_object_local(Vector3.UP, delta * 0.6)
		var m := disc.material_override as StandardMaterial3D
		m.albedo_color.a = 0.3 + sin(Time.get_ticks_msec() / 400.0) * 0.1


# ---------------------------------------------------------------- byggeri

func _build_lane(sys_id: String, l: Dictionary) -> void:
	var st := station(l["from"])
	var pl := planet(l["to"])
	var a := st.position + (pl.pad_top - st.position).normalized() * 70.0
	var b := pl.position + pl.pad_dir * (pl.radius + pl.atmo_top + 70.0)
	lanes.append({"a": a, "b": b, "system": sys_id})
	var dir := (b - a).normalized()
	var basis := Basis(Quaternion(Vector3.UP, dir))
	var count := int(a.distance_to(b) / 95.0)
	for i in count + 1:
		var is_end := i == 0 or i == count
		var ring := TorusMesh.new()
		ring.inner_radius = 9.6 if is_end else 7.1
		ring.outer_radius = 12.4 if is_end else 8.9
		ring.rings = 10
		ring.ring_segments = 4
		var mi := PlanetBody._part(self, ring, Color("ffd23f") if is_end else Color("4dffe1"), a.lerp(b, float(i) / count))
		mi.basis = basis
		var m := mi.material_override as StandardMaterial3D
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true


func _build_gate(sys_id: String, g: Dictionary) -> void:
	var origin: Vector3 = origins[sys_id]
	var pos := origin + Game.vec(g["pos"])
	var dir := origin - pos
	if g.has("face"):
		dir = planet(g["face"]).position - pos
	dir = dir.normalized() if dir.length() > 1.0 else Vector3.FORWARD
	var root := Node3D.new()
	root.name = "Gate_" + g["id"]
	root.position = pos
	root.basis = Basis(Quaternion(Vector3.UP, dir))
	add_child(root)
	var torus := TorusMesh.new()
	torus.inner_radius = 19.4
	torus.outer_radius = 24.6
	torus.rings = 8
	torus.ring_segments = 4
	PlanetBody._part(root, torus, Color("7b4dff"), Vector3.ZERO)
	for i in 4:
		var a := i / 4.0 * TAU + PI / 8
		var off := Vector3(cos(a) * 23, 0, sin(a) * 23)
		PlanetBody._part(root, PlanetBody._box(5, 12, 5), Color("ffd23f"), off)
		var lt := PlanetBody._part(root, PlanetBody._box(1.4, 1.4, 1.4), Color("4dffe1"), off + Vector3(0, 6.5, 0))
		(lt.material_override as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := PlanetBody._part(root, PlanetBody._cyl(19.5, 19.5, 0.3, 8), Color(0.78, 0.49, 1.0, 0.3), Vector3.ZERO)
	var dm := disc.material_override as StandardMaterial3D
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.disable_fog = true
	gates[g["id"]] = {"id": g["id"], "system": sys_id, "pos": pos, "dir": dir, "to": g["to"], "label": g["label"], "disc": disc}
