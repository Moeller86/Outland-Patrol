class_name Sites
extends Node3D
## Fund på planeternes overflade, som man finder med scanneren (C) og lander ved:
##  vrag       – styrtet fragtskib: bjærg lasten (varer i lastrummet)
##  ruin       – Architect-ruin: undersøg den (erfaring, kredit og et stykke historie)
##  forsyning  – nedkastet Concord-kapsel: reparerer skib og skjold
##  piratlejr  – sender pirater op, når man kommer tæt på; ryd dem, og plyndr lejren
##
## Placeringerne regnes ud af planetens seed, så de er ens på alle maskiner.
## Værten styrer, hvad der er plyndret, lejrenes pirater og belønningerne.
## Hvad man har fundet (scannet) er lokalt for hver spiller.
## Missioner kan lægge ekstra fund ud (fx vraget i en eftersøgning).

signal known_changed
signal action_result(site_id: String, text: String)
signal server_site_found(site_id: String)                   ## Kun på serveren
signal server_site_action(site_id: String, who: int)       ## Kun på serveren (missionsfund)

const K = preload("res://scripts/world/model_kit.gd")
const SCAN_RANGE := 1600.0
const SCAN_COOLDOWN := 6.0
const LAND_RANGE := 30.0
const SEE_RANGE := 220.0          ## Så tæt på opdager man et fund uden scanner
const CAMP_TRIGGER := 380.0

const KINDS := {
	"vrag": {"label": "VRAG", "color": "ff9e3d", "respawn": 240.0,
		"title": "Styrtet fragtskib", "action": "BJÆRG LASTEN",
		"desc": "Et fragtskib er gået ned her. Skroget er knust, men noget af lasten ser ud til at være intakt."},
	"ruin": {"label": "RUIN", "color": "9fe2ff", "respawn": 600.0,
		"title": "Architect-ruin", "action": "UNDERSØG RUINEN",
		"desc": "En buegang af mørk sten med lysende tegn. Ingen ved, hvem Architects var, eller hvorfor de forsvandt."},
	"forsyning": {"label": "FORSYNING", "color": "6bdc4f", "respawn": 180.0,
		"title": "Concord-forsyningskapsel", "action": "ÅBN KAPSLEN",
		"desc": "En nedkastet kapsel fra Concord Patrol med reservedele, skjoldceller og lidt kontanter."},
	"piratlejr": {"label": "PIRATLEJR", "color": "ff5a5a", "respawn": 300.0,
		"title": "Piratlejr", "action": "PLYNDR LEJREN",
		"desc": "Containere, telte og et sendeanlæg. Piraterne bruger lejren som skjulested mellem plyndringstogterne."},
}
const LORE := [
	"Tegnene danner et stjernekort. Et af systemerne findes ikke på nogen Concord-kort.",
	"I stenen er der en tavle med en tekst, der gentager ét ord: STILHEDEN.",
	"Ruinen summer svagt. Dine instrumenter måler en puls hvert 11. sekund.",
	"Du finder et rum med tomme sokler. Noget har stået her – og er blevet flyttet.",
	"Lyset i tegnene følger dig, når du bevæger dig. Det er ikke ubehageligt.",
]

var sites: Array[Dictionary] = []
var known: Dictionary = {}          ## site-id -> true (lokalt: hvad denne spiller har fundet)
var scan_cool := 0.0

var _by_id: Dictionary = {}
var _see_t := 0.0
var _smoke_t := 0.0
var _pulse: MeshInstance3D
var _pulse_t := -1.0
var _pulse_range := SCAN_RANGE


func _ready() -> void:
	for p in W.universe.planets:
		_generate(p)
	_pulse = MeshInstance3D.new()
	_pulse.mesh = K.sphere(1.0, 32, 16)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/scan_pulse.gdshader")
	_pulse.material_override = sm
	_pulse.visible = false
	_pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pulse.extra_cull_margin = 16384.0
	add_child(_pulse)
	Game.player_joined.connect(_on_player_joined)
	Net.started.connect(_on_net_started)


func _on_net_started() -> void:
	known.clear()
	for s in sites.duplicate():
		if s["mission"] != "":
			_remove(s["id"])
	for s in sites:
		s["looted"] = false
		s["armed"] = false
		s["cleared"] = false
		s["timer"] = 0.0
	known_changed.emit()


# ---------------------------------------------------------------- placering

func _generate(p: PlanetBody) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.data["seed"]) * 7919 + 13
	var n := int(p.data.get("sites", 5))
	var kinds: Array = p.data.get("site_kinds", ["vrag", "ruin", "forsyning", "piratlejr", "vrag", "forsyning"])
	var names: Array = Game.mission_data["freighter_names"]
	for k in n:
		var d := _pick_dir(p, rng)
		if d == Vector3.ZERO:
			continue
		var kind: String = kinds[k % kinds.size()]
		var title := str(KINDS[kind]["title"])
		if kind == "vrag":
			title = "Vraget af %s" % names[rng.randi() % names.size()]
		_add({"id": "%s_%d" % [p.id, k], "kind": kind, "planet": p.id, "dir": d, "name": title, "mission": ""})


## En tilfældig retning på planeten: på land, ikke ved byen, ikke oven i andre fund.
func _pick_dir(p: PlanetBody, rng: RandomNumberGenerator) -> Vector3:
	for t in 80:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var to_pad := d.dot(p.pad_dir)
		if to_pad < 0.25 or p.in_flat_zone(d, 60.0) or p.in_feature_clear(d):
			continue
		if p.height_at(d) < 8.0:
			continue
		var ok := true
		for s in sites:
			if s["planet"] == p.id and (s["dir"] as Vector3).dot(d) > 0.985:
				ok = false
				break
		if ok:
			return d
	return Vector3.ZERO


func _add(info: Dictionary) -> Dictionary:
	var p := W.universe.planet(info["planet"])
	var d: Vector3 = info["dir"]
	var t := d.cross(Vector3.UP)
	if t.length() < 0.01:
		t = d.cross(Vector3.RIGHT)
	t = t.normalized()
	var s := info.duplicate()
	s["system"] = p.system_id
	s["pos"] = p.position + d * p.fine_surface_radius(d)
	var ld := (d * p.radius + t * 18.0).normalized()
	s["land"] = p.position + ld * p.fine_surface_radius(ld)
	s["land_up"] = ld
	s["tangent"] = t
	s["looted"] = false
	s["armed"] = false
	s["cleared"] = false
	s["timer"] = 0.0
	s["node"] = _build_node(s)
	sites.append(s)
	_by_id[s["id"]] = s
	return s


func _remove(site_id: String) -> void:
	if not _by_id.has(site_id):
		return
	var s: Dictionary = _by_id[site_id]
	(s["node"] as Node3D).queue_free()
	sites.erase(s)
	_by_id.erase(site_id)
	known.erase(site_id)
	known_changed.emit()


func get_site(site_id: String) -> Dictionary:
	return _by_id.get(site_id, {})


# ---------------------------------------------------------------- forespørgsler

## Nærmeste fund, man kan lande ved, eller tom ordbog. {id, kind, distance, name}
func landing_spot(pos: Vector3) -> Dictionary:
	var best := {}
	var bd := LAND_RANGE
	for s in sites:
		var d := pos.distance_to(s["land"])
		if d < bd:
			bd = d
			best = {"id": "site:" + str(s["id"]), "kind": "site", "distance": d, "name": s["name"]}
	return best


## Er fundet tilgængeligt (ikke plyndret)?
func available(s: Dictionary) -> bool:
	return not s["looted"]


## Fund, spilleren kender, i et system.
func known_in(sys_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in sites:
		if s["system"] == sys_id and known.has(s["id"]):
			out.append(s)
	return out


## Hvad kan man gøre ved et fund lige nu? {label, enabled, note}
func action_for(site_id: String) -> Dictionary:
	var s := get_site(site_id)
	if s.is_empty():
		return {"label": "", "enabled": false, "note": ""}
	var label := str(KINDS[s["kind"]]["action"])
	if s["mission"] != "":
		label = "BJÆRG DEN SORTE BOKS"
	if s["looted"]:
		return {"label": label, "enabled": false, "note": "Her er ikke mere at hente lige nu."}
	if s["kind"] == "piratlejr" and not s["cleared"]:
		return {"label": label, "enabled": false, "note": "Lejren forsvares stadig. Skyd piraterne ned først."}
	return {"label": label, "enabled": true, "note": ""}


# ---------------------------------------------------------------- scanner (lokalt)

## Sender en scannerpuls ud fra pos. Returnerer antal nye fund (eller -1 hvis scanneren lader op).
func scan(pos: Vector3) -> int:
	if scan_cool > 0.0:
		return -1
	var h: Dictionary = W.local_ship.handling if W.local_ship and is_instance_valid(W.local_ship) else {}
	scan_cool = SCAN_COOLDOWN * float(h.get("scan_mult", 1.0))
	_pulse.position = pos
	_pulse_t = 0.0
	_pulse.visible = true
	Sfx.play("scan", -3.0, 0.0)
	var sys := W.universe.system_at(pos)
	_pulse_range = SCAN_RANGE * float(h.get("scan_range", 1.0)) * (W.weather.scan_mul(pos) if W.weather else 1.0)
	var found := 0
	for s in sites:
		if s["system"] != sys or pos.distance_to(s["pos"]) > _pulse_range:
			continue
		if s["mission"] != "":
			_srv_found.rpc_id(1, s["id"])
		if not known.has(s["id"]):
			known[s["id"]] = true
			found += 1
	if found > 0:
		known_changed.emit()
		get_tree().create_timer(0.5).timeout.connect(func(): Sfx.play("fund", -3.0, 0.0))
	return found


func _discover(s: Dictionary) -> void:
	if known.has(s["id"]):
		return
	known[s["id"]] = true
	Sfx.play("fund", -4.0, 0.0)
	Game.toast.emit("Fundet: %s" % s["name"])
	if s["mission"] != "":
		_srv_found.rpc_id(1, s["id"])
	known_changed.emit()


func request_action(site_id: String) -> void:
	_srv_action.rpc_id(1, site_id)


# ---------------------------------------------------------------- løkke

func _process(delta: float) -> void:
	scan_cool = maxf(0.0, scan_cool - delta)
	var me := W.local_ship
	# Scannerpulsen breder sig ud og falmer
	if _pulse_t >= 0.0:
		_pulse_t += delta
		var k := _pulse_t / 1.6
		var r := _pulse_range * (1.0 - pow(1.0 - minf(k, 1.0), 2.0))
		_pulse.scale = Vector3.ONE * maxf(r, 1.0)
		(_pulse.material_override as ShaderMaterial).set_shader_parameter("fade", clampf(1.0 - k, 0.0, 1.0))
		if k >= 1.0:
			_pulse_t = -1.0
			_pulse.visible = false
	var t := Time.get_ticks_msec() / 1000.0
	var blink := int(t * 2.0) % 2 == 0
	for s in sites:
		var n: Node3D = s["node"]
		var beam: Node3D = n.get_meta("beam")
		beam.visible = known.has(s["id"]) and not s["looted"]
		for l: Node3D in n.get_meta("blink"):
			l.visible = blink
		if n.has_meta("spin"):
			var spin: Node3D = n.get_meta("spin")
			spin.rotate_y(delta * 0.8)
			spin.position.y = 13.0 + sin(t * 1.5) * 0.8
	if me == null or not is_instance_valid(me) or me.dead:
		return
	# Opdag fund, man flyver tæt forbi, og lad vragene ryge
	_see_t -= delta
	_smoke_t -= delta
	var near_check := _see_t <= 0.0
	if near_check:
		_see_t = 0.5
	for s in sites:
		var d := me.position.distance_to(s["pos"])
		if near_check and d < SEE_RANGE:
			_discover(s)
		if s["kind"] == "vrag" and not s["looted"] and d < 900.0 and _smoke_t <= 0.0:
			var up: Vector3 = s["dir"]
			W.fx.spawn((s["pos"] as Vector3) + up * 3.0 + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)),
				up * randf_range(4.0, 7.0), Color("5a5470") if randf() < 0.7 else Color("ff9e3d"), randf_range(1.2, 2.2), 2.2)
	if _smoke_t <= 0.0:
		_smoke_t = 0.12


func _physics_process(delta: float) -> void:
	if not W.is_server():
		return
	for s in sites:
		if s["looted"]:
			if s["mission"] != "":
				continue
			s["timer"] = float(s["timer"]) - delta
			if s["timer"] <= 0.0:
				s["looted"] = false
				s["armed"] = false
				s["cleared"] = false
				_cl_state.rpc(s["id"], false, false, false)
			continue
		if s["kind"] != "piratlejr":
			continue
		var tag := "camp_" + str(s["id"])
		if not s["armed"]:
			for sh in W.active_ships():
				if sh.position.distance_to(s["pos"]) < CAMP_TRIGGER:
					_server_arm_camp(s, tag)
					break
		elif not s["cleared"] and W.pirates.server_count_tag(tag) == 0:
			s["cleared"] = true
			_cl_state.rpc(s["id"], false, true, true)
			for id: int in Game.players:
				Game.server_toast(id, "Piratlejren er ryddet – land og plyndr den")


func _server_arm_camp(s: Dictionary, tag: String) -> void:
	s["armed"] = true
	var up: Vector3 = s["dir"]
	var n := 2 + maxi(1, Game.players.size())
	for k in n:
		var a := TAU * k / n
		var side := (s["tangent"] as Vector3).rotated(up, a)
		var p := (s["pos"] as Vector3) + up * randf_range(90.0, 140.0) + side * 70.0
		W.pirates.server_spawn_at(s["system"], p, p + up * 50.0, tag)
	_cl_state.rpc(s["id"], false, true, false)
	for id: int in Game.players:
		Game.server_toast(id, "Piratlejren har opdaget dig! %d pirater letter" % n)


# ---------------------------------------------------------------- server: handlinger

@rpc("any_peer", "call_local", "reliable")
func _srv_found(site_id: String) -> void:
	if multiplayer.is_server() and _by_id.has(site_id):
		server_site_found.emit(site_id)


@rpc("any_peer", "call_local", "reliable")
func _srv_action(site_id: String) -> void:
	if not multiplayer.is_server() or not _by_id.has(site_id):
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	var s: Dictionary = _by_id[site_id]
	var ship: Ship = W.ships.get(who)
	if ship == null or ship.position.distance_to(s["land"]) > 60.0:
		return
	var act := action_for(site_id)
	if not act["enabled"]:
		_cl_result.rpc_id(who, site_id, str(act["note"]), "")
		return
	var text := ""
	var effect := ""
	if s["mission"] != "":
		text = "Du har den sorte boks. Bring den hjem!"
		server_site_action.emit(site_id, who)
	else:
		match s["kind"]:
			"vrag":
				var goods: Array = Game.goods.keys()
				var got := {}
				for k in randi_range(2, 4):
					var g: String = goods.pick_random()
					if Game.server_add_cargo(who, g):
						got[g] = int(got.get(g, 0)) + 1
				if got.is_empty():
					text = "Lastrummet er fuldt – du kunne ikke tage noget med."
					_cl_result.rpc_id(who, site_id, text, "")
					return
				var parts := []
				for g: String in got:
					parts.append("%d %s" % [got[g], Game.good_name(g).to_lower()])
				text = "Du bjærgede %s fra vraget." % ", ".join(parts)
			"ruin":
				Game.server_reward(who, 60, 40)
				text = "%s\n\n+60 cr for data · +40 xp" % LORE.pick_random()
			"forsyning":
				Game.server_reward(who, 25, 0)
				text = "Skrog og skjold er repareret. Der lå også 25 cr i kapslen."
				effect = "repair"
			"piratlejr":
				Game.server_reward(who, 150, 25)
				var extra := 0
				for k in 2:
					if Game.server_add_cargo(who, "elektronik"):
						extra += 1
				text = "Du fandt piraternes kasse: +150 cr, +25 xp" + (" og %d elektronik." % extra if extra > 0 else ".")
	s["looted"] = true
	s["timer"] = float(KINDS[s["kind"]]["respawn"])
	_cl_state.rpc(site_id, true, s["armed"], s["cleared"])
	_cl_result.rpc_id(who, site_id, text, effect)


@rpc("authority", "call_local", "reliable")
func _cl_state(site_id: String, looted: bool, armed: bool, cleared: bool) -> void:
	if not _by_id.has(site_id):
		return
	var s: Dictionary = _by_id[site_id]
	s["looted"] = looted
	s["armed"] = armed
	s["cleared"] = cleared
	known_changed.emit()


@rpc("authority", "call_local", "reliable")
func _cl_result(site_id: String, text: String, effect: String) -> void:
	if effect == "repair" and W.local_ship and is_instance_valid(W.local_ship):
		W.local_ship.hull = 100.0
		W.local_ship.shield = W.local_ship.shield_max
	if text != "":
		Sfx.play("fund" if effect == "repair" else "bekraeft", -3.0, 0.0)
	action_result.emit(site_id, text)


# ---------------------------------------------------------------- missionsfund

## Server: læg et missionsvrag ud på en planet. Returnerer fundets id.
func server_add_mission_site(tag: String, planet_id: String, title: String) -> String:
	var p := W.universe.planet(planet_id)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var d := _pick_dir(p, rng)
	if d == Vector3.ZERO:
		d = (p.pad_dir + p.tangent * 0.6).normalized()
	var site_id := "%s_%s" % [tag, planet_id]
	_cl_add.rpc(site_id, planet_id, d, title, tag)
	return site_id


func server_remove_mission_site(site_id: String) -> void:
	_cl_remove.rpc(site_id)


@rpc("authority", "call_local", "reliable")
func _cl_add(site_id: String, planet_id: String, d: Vector3, title: String, tag: String) -> void:
	if _by_id.has(site_id):
		return
	_add({"id": site_id, "kind": "vrag", "planet": planet_id, "dir": d, "name": title, "mission": tag})


@rpc("authority", "call_local", "reliable")
func _cl_remove(site_id: String) -> void:
	_remove(site_id)


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	for s in sites:
		if s["mission"] != "":
			_cl_add.rpc_id(id, s["id"], s["planet"], s["dir"], s["name"], s["mission"])
		if s["looted"] or s["armed"]:
			_cl_state.rpc_id(id, s["id"], s["looted"], s["armed"], s["cleared"])


# ---------------------------------------------------------------- modeller

func _build_node(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Site_" + str(s["id"])
	var up: Vector3 = s["dir"]
	root.transform = Transform3D(Basis.looking_at(s["tangent"], up), (s["pos"] as Vector3) - up * 0.6)
	add_child(root)
	var blink: Array[Node3D] = []
	match s["kind"]:
		"vrag": _build_wreck(root, blink, s["mission"] != "")
		"ruin": _build_ruin(root, blink)
		"forsyning": _build_pod(root, blink)
		"piratlejr": _build_camp(root, blink)
	K.merge(root, blink)
	# Små fund ses kun på kortere afstand (sparer tegnekald fra den anden side af planeten)
	for c in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visibility_range_end = 2600.0
	# Lyssøjle over kendte fund
	var beam := MeshInstance3D.new()
	beam.mesh = K.cyl(1.2, 1.2, 160.0, 6)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c := Game.col(KINDS[s["kind"]]["color"])
	if s["mission"] != "":
		c = UiTheme.GREEN
	bm.albedo_color = Color(c, 0.45)
	bm.disable_fog = true
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0, 84, 0)
	beam.visible = false
	root.add_child(beam)
	root.set_meta("beam", beam)
	root.set_meta("blink", blink)
	return root


func _build_wreck(g: Node3D, blink: Array[Node3D], mission: bool) -> void:
	# Et fragtskib, der ligger skævt og halvt begravet, med knækket bagende
	var hull := ShipModels.freighter()
	hull.rotation = Vector3(0.18, 0.4, 0.35)
	hull.position = Vector3(0, 0.8, 0)
	hull.scale = Vector3.ONE * 1.3
	var flame: Node3D = hull.get_meta("flame")
	flame.visible = false
	g.add_child(hull)
	var dark := K.flat(Color("2a2238"))
	var metal := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.5)
	K.add(g, K.box(10, 2.5, 7), K.flat(Color("3a2d24")), Vector3(1, -0.6, 2))          # jordvold
	K.add(g, K.box(3.2, 2.4, 4.0), metal, Vector3(7, 0.6, 12), Vector3(0.5, 0.8, 0.9))  # løsrevet motorblok
	K.add(g, K.box(2.0, 1.6, 1.6), dark, Vector3(6.4, 0.4, 13.8), Vector3(0.2, 0.3, 0.4))
	var cols := [Color("ff7a59"), Color("6bdc4f"), Color("ffd23f"), Color("4dd0ff")]
	for k in 4:
		var a := k * 1.7
		K.add(g, K.box(1.9, 2.2, 2.5), K.hull(cols[k], K.TEX_PLATING, 0.7),
			Vector3(cos(a) * 9.0 - 3.0, 0.5, sin(a) * 7.0 + 4.0), Vector3(0.2 * k, a, 0.4 - 0.2 * k))
	K.add(g, K.box(6, 0.3, 4), dark, Vector3(-5, -0.2, -6), Vector3(0, 0.7, 0))         # brændemærke
	# Nødsender med blinkende lys
	K.add(g, K.cyl(0.08, 0.12, 3.0, 4), K.flat(Color("d9d2ff")), Vector3(-3, 1.5, -2))
	blink.append(K.add(g, K.box(0.5, 0.5, 0.5), K.glow(UiTheme.GREEN if mission else Color("ff3b3b")), Vector3(-3, 3.2, -2)))


func _build_ruin(g: Node3D, blink: Array[Node3D]) -> void:
	var stone := K.hull(Color("4a3f6b"), K.TEX_PLATING, 0.25)
	var stone2 := K.hull(Color("3a3155"), K.TEX_PANEL, 0.2)
	var glyph := K.glow(Color("9fe2ff"))
	K.add(g, K.box(22, 3, 16), stone2, Vector3(0, -0.5, 0))                       # sokkel
	K.add(g, K.box(18, 0.5, 12), stone, Vector3(0, 1.2, 0))
	for s in [-1.0, 1.0]:
		K.add(g, K.box(2.6, 12, 2.6), stone, Vector3(s * 6.5, 7, 0))               # søjler
		K.add(g, K.box(0.4, 9, 0.3), glyph, Vector3(s * 6.5, 7, 1.35))
		K.add(g, K.box(3.4, 1.2, 3.4), stone2, Vector3(s * 6.5, 1.8, 0))
		K.add(g, K.box(2.4, 6, 2.4), stone, Vector3(s * 7.5, 3, -6), Vector3(0, 0, s * 0.25))   # væltet søjle
	K.add(g, K.box(16.5, 2.4, 3.2), stone, Vector3(0, 14, 0))                     # overligger
	K.add(g, K.box(12, 0.4, 0.3), glyph, Vector3(0, 14, 1.65))
	for k in 5:
		K.add(g, K.box(0.9, 0.9, 0.3), glyph, Vector3(-4.0 + k * 2.0, 15.6, 1.4))
	# Svævende krystal
	var spin := Node3D.new()
	spin.position = Vector3(0, 13, 0)
	g.add_child(spin)
	var crystal := K.add(spin, K.sphere(1.8, 4, 2), K.glow(Color("c77dff")), Vector3(0, -5, 0))
	crystal.scale = Vector3(1, 1.8, 1)
	g.set_meta("spin", spin)
	blink.append(K.add(g, K.box(0.6, 0.6, 0.6), glyph, Vector3(0, 2, 0)))


func _build_pod(g: Node3D, blink: Array[Node3D]) -> void:
	var white := K.hull(Color("e6ecff"))
	K.add(g, K.box(8, 0.4, 8), K.flat(Color("3a2d24")), Vector3(0, -0.1, 0), Vector3(0, 0.4, 0))   # nedslagskrater
	var body := Node3D.new()
	body.rotation = Vector3(0.25, 0, 0.15)
	g.add_child(body)
	K.add(body, K.cyl(1.8, 2.2, 5.0, 10), white, Vector3(0, 2.5, 0))
	K.add(body, K.sphere(1.8, 10, 5), white, Vector3(0, 5.0, 0), Vector3.ZERO, Vector3(1, 0.6, 1))
	K.add(body, K.cyl(2.25, 2.25, 0.6, 10), K.stripes(0.6), Vector3(0, 1.0, 0))
	K.add(body, K.cyl(1.85, 1.85, 0.8, 10), K.hull(Color("2e6bd6")), Vector3(0, 3.4, 0))
	K.add(body, K.cyl(0.6, 1.0, 0.6, 8), K.flat(Color("23203a")), Vector3(0, 0.0, 0))
	K.add(body, K.cyl(0.05, 0.08, 2.4, 4), K.flat(Color("d9d2ff")), Vector3(0.8, 6.6, 0))
	blink.append(K.add(body, K.box(0.45, 0.45, 0.45), K.glow(UiTheme.GREEN), Vector3(0.8, 7.9, 0)))
	# Faldskærm på jorden
	K.add(g, K.box(7, 0.15, 4), K.flat(Color("ff9e3d")), Vector3(-6, 0.1, 3), Vector3(0, 0.5, 0.05))
	K.add(g, K.box(7, 0.16, 1.2), K.flat(Color("e6ecff")), Vector3(-6, 0.12, 3), Vector3(0, 0.5, 0.05))


func _build_camp(g: Node3D, blink: Array[Node3D]) -> void:
	var dark := K.hull(Color("3a2350"))
	var red := K.hull(Color("ff3b3b"), K.TEX_PLATING, 0.6)
	var rust := K.hull(Color("8a4a3a"), K.TEX_PLATING, 0.5)
	for c: Vector3 in [Vector3(-6, -0.5, -2), Vector3(5, -0.5, 3), Vector3(0, -0.5, -7)]:
		K.add(g, K.cyl(7.0, 7.5, 1.2, 8), K.flat(Color("3a2d24")), c)
	# Containere og telte
	for k in 4:
		K.add(g, K.box(3.2, 3.0, 6.5), rust if k % 2 else dark, Vector3(-9 + k * 1.2, 1.4, -6 + k * 4.2), Vector3(0, 0.3 * k, 0))
	for p: Vector3 in [Vector3(6, 0, -6), Vector3(9, 0, 3)]:
		K.add(g, K.wedge(6, 3.6, 5), red, p + Vector3(0, 1.8, 0))
	# Parkeret pirat
	var pir := ShipModels.pirate()
	(pir.get_meta("flame") as Node3D).visible = false
	pir.position = Vector3(1, 1.2, 6)
	pir.rotation = Vector3(0, 2.3, 0)
	pir.scale = Vector3.ONE * 1.1
	g.add_child(pir)
	# Sendemast med flag og lys
	K.add(g, K.cyl(0.2, 0.35, 14, 6), K.flat(Color("5a5470")), Vector3(-2, 7, -3))
	K.add(g, K.box(3.0, 1.8, 0.1), red, Vector3(-0.4, 12.6, -3))
	K.add(g, K.cyl(1.6, 0.4, 0.4, 8), K.flat(Color("d9d2ff")), Vector3(-2, 10, -3), Vector3(0.9, 0, 0))
	blink.append(K.add(g, K.box(0.6, 0.6, 0.6), K.glow(Color("ff3b3b")), Vector3(-2, 14.4, -3)))
	# Bål/projektør
	K.add(g, K.box(1.2, 0.6, 1.2), K.glow(Color("ff9e3d")), Vector3(3, 0.4, -1))
