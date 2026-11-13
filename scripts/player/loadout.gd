class_name Loadout
extends Node3D
## Våben og gadgets på det lokale skib (inspireret af FTL).
##
## Hvert monteret våben har sin egen genopladning og skyder fra sin egen kanon
## (skibets kanoner fordeles mellem våbnene). Særlige våben:
##   salvo   – burstlaser: flere hurtige skud pr. opladning
##   spinup  – kædekanon: skyder hurtigere, jo længere man holder inde
##   beam    – strålelaser: sammenhængende stråle med varme
##   effect  – 1 ion (lammer, slår skjolde ned), 2 flak (nærhedsrør, sprængning),
##             3 krystal (går gennem skjolde)
## Gadgets: droner (kamp, forsvar, reparation), passive augments og aktive gadgets
## på tasterne 6–9 (kappe, EMP-puls, skjoldbatteri). Våbnene står i en primær og en
## sekundær gruppe (venstre klik / Ctrl) og kan slås til og fra med tasterne 1–5.

const K = preload("res://scripts/world/model_kit.gd")
const BEAM_TICK := 0.1
const DRONE_RANGE := 260.0
const DRONE_COOL := 0.6
const DEF_RANGE := 180.0
const DEF_COOL := 3.5
const REP_DELAY := 5.0
const REP_RATE := 2.0

var ship: Ship
var _w: Array[Dictionary] = []       ## pr. våben: {def, guns, cool, salvo, salvo_t, spin, heat, hot, beam_t, firing}
var _beams: Array[MeshInstance3D] = []
var _beam_mat: StandardMaterial3D
var _drones: Dictionary = {}         ## "kamp"/"forsvar"/"rep" -> Node3D
var _drone_cool := {"kamp": 0.0, "forsvar": 0.0}
var _gcool: Array[float] = []        ## pr. gadgetplads: genopladning tilbage
var _cloak_t := 0.0
var _batt_flash := 0.0
var _sig := ""
var _off: Dictionary = {}            ## våbenplads -> true, når den er slået fra (tast 1–5)


func _init(s: Ship) -> void:
	ship = s
	name = "Loadout"


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.vertex_color_use_as_albedo = false
	_beam_mat.albedo_color = Color("ff5af0")
	_beam_mat.disable_fog = true
	rebuild()


## Byg våbenlisten og dronerne op igen (efter skibs- eller udstyrsskift).
func rebuild() -> void:
	var weapons: Array = ship.handling.get("weapons", [])
	var gadget_slots: Array = ship.handling.get("gadget_slots", [])
	var sig := JSON.stringify([weapons.map(func(w): return [w["id"], w.get("group", 0)]), gadget_slots, ship.ship_class])
	if sig == _sig:
		return
	_sig = sig
	_w.clear()
	var guns := ship.guns()
	var n := weapons.size()
	for k in n:
		var g: Array = []
		for gi in guns.size():
			if gi % n == k:
				g.append(guns[gi])
		if g.is_empty() and not guns.is_empty():
			g.append(guns[k % guns.size()])
		_w.append({"def": weapons[k], "guns": g, "cool": 0.0, "salvo": 0, "salvo_t": 0.0,
			"spin": 1.0, "idle": 0.0, "heat": 0.0, "hot": false, "beam_t": 0.0, "firing": false})
	for b in _beams:
		b.queue_free()
	_beams.clear()
	_gcool.resize(gadget_slots.size())
	for k in _gcool.size():
		_gcool[k] = 0.0
	# Droner
	var want := {}
	for gid: String in ship.handling.get("gadgets", []):
		var it := Game.part(gid)
		if it.has("drone"):
			want[it["drone"]] = true
	for kind: String in _drones.keys():
		if not want.has(kind):
			(_drones[kind] as Node3D).queue_free()
			_drones.erase(kind)
	for kind: String in want:
		if not _drones.has(kind):
			var d := _drone_model(kind)
			add_child(d)
			_drones[kind] = d
	if _cloak_t > 0.0:
		_set_cloak(false)


static func _drone_model(kind: String) -> Node3D:
	var g := Node3D.new()
	var col := {"kamp": Color("ff4f8b"), "forsvar": Color("4dd0ff"), "rep": Color("6bdc4f")}[kind] as Color
	K.add(g, K.box(0.7, 0.35, 0.7), K.hull(Color("4e4a6e"), K.TEX_PLATING, 0.5), Vector3.ZERO)
	K.add(g, K.box(0.3, 0.18, 0.3), K.glow(col), Vector3(0, 0.25, 0))
	for s in [-1.0, 1.0]:
		K.add(g, K.box(0.5, 0.06, 0.25), K.hull(col), Vector3(s * 0.55, 0, 0))
	if kind == "kamp":
		K.add(g, K.cyl(0.05, 0.05, 0.6, 5), K.flat(Color("2a2838")), Vector3(0, -0.05, -0.5), Vector3(-PI / 2, 0, 0))
	return g


# ---------------------------------------------------------------- våben

## Kaldes hver fysik-frame fra skibet. `primary`/`secondary` = skydeknapperne for
## de to våbengrupper holdes inde. Våben, der er slået fra (tast 1–5), skyder ikke.
func tick(delta: float, primary: bool, secondary := false) -> void:
	rebuild()
	var reload := float(ship.handling.get("reload_mult", 1.0))
	var base_cd := float(ship.handling.get("fire_cooldown", Ship.FIRE_COOLDOWN))
	for k in _w.size():
		var w: Dictionary = _w[k]
		var d: Dictionary = w["def"]
		w["cool"] = float(w["cool"]) - delta
		var pressed: bool = (secondary if int(d.get("group", 0)) == 1 else primary) and not _off.has(int(d.get("slot", k)))
		if d.get("beam", false):
			_tick_beam(k, w, d, delta, pressed)
			continue
		# Salve i gang (burstlaser)
		if int(w["salvo"]) > 0:
			w["salvo_t"] = float(w["salvo_t"]) - delta
			if w["salvo_t"] <= 0.0:
				w["salvo"] = int(w["salvo"]) - 1
				w["salvo_t"] = float(d.get("salvo_gap", 0.07))
				_fire_weapon(w, d)
			continue
		# Kædekanon: hurtigere, mens man holder inde; slipper man, falder farten igen
		if d.has("spinup"):
			if pressed:
				w["idle"] = 0.0
			else:
				w["idle"] = float(w["idle"]) + delta
				if w["idle"] > 0.8:
					w["spin"] = 1.0
		if pressed and w["cool"] <= 0.0:
			var cd := base_cd * float(d.get("cd_mult", 1.0)) * reload
			if d.has("spinup"):
				cd *= float(w["spin"])
				w["spin"] = maxf(float(d.get("spin_min", 0.25)), float(w["spin"]) * float(d["spinup"]))
			w["cool"] = cd
			_fire_weapon(w, d)
			if int(d.get("salvo", 1)) > 1:
				w["salvo"] = int(d["salvo"]) - 1
				w["salvo_t"] = float(d.get("salvo_gap", 0.07))


func _aim_dir_from(p: Vector3, assist: bool, lead: Vector3) -> Vector3:
	return (lead - p).normalized() if assist else (ship.aim_point - p).normalized()


func _fire_weapon(w: Dictionary, d: Dictionary) -> void:
	w["shots"] = int(w.get("shots", 0)) + 1
	var heavy := Game.upgrade_level("laser") > 0
	var color := Game.col(d.get("color", "ff4fd8"))
	if heavy and d.get("color", "ff4fd8") == "ff4fd8":
		color = Color("4dffe1")
	var bspeed := Ship.BOLT_SPEED * float(d.get("speed_mult", 1.0)) + ship.speed
	var bolts := int(d.get("bolts", 1))
	var spread := deg_to_rad(float(d.get("spread", 0.0)))
	var assist := ship.aim_assist_active()
	var lead := ship.lead_point() if assist else Vector3.ZERO
	var up := ship.global_basis.y
	var dmg := ship.laser_damage() * float(d.get("dmg_mult", 1.0))
	var effect := int(d.get("effect", 0))
	var dir := ship.aim_dir
	for ga in w["guns"]:
		var g := Vector3(ga[0], ga[1], ga[2]) if ga is Array else (ga as Vector3)
		var p := ship.global_transform * g
		var dd := _aim_dir_from(p, assist, lead)
		dir = dd
		for b in bolts:
			var bd := dd
			if bolts > 1:
				bd = dd.rotated(up, spread * (b - (bolts - 1) / 2.0)).normalized()
			elif spread > 0.0:
				bd = (dd + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
			W.bolts.fire(p, bd, bspeed, color, Bolts.Kind.OWN, dmg, effect)
	Sfx.play(str(d.get("sound", "laser_tung" if heavy else "laser")), -6.0)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		ship._net_fire.rpc(ship.position, dir, bspeed, color)


func _tick_beam(k: int, w: Dictionary, d: Dictionary, delta: float, pressed: bool) -> void:
	var heat_time := float(d.get("heat_time", 3.0))
	var cool_time := float(d.get("cool_time", 2.2))
	var on: bool = pressed and not w["hot"]
	if on:
		w["heat"] = float(w["heat"]) + delta / heat_time
		if w["heat"] >= 1.0:
			w["heat"] = 1.0
			w["hot"] = true
			Sfx.play("skjold", -10.0)
	else:
		w["heat"] = maxf(0.0, float(w["heat"]) - delta / cool_time)
		if w["hot"] and w["heat"] <= 0.0:
			w["hot"] = false
	w["firing"] = on
	# Strålernes udseende: én pr. kanon
	var guns: Array = w["guns"]
	while _beams.size() < _beam_count():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, 1.0)
		mi.mesh = bm
		var m := _beam_mat.duplicate() as StandardMaterial3D
		m.albedo_color = Game.col(d.get("color", "ff5af0"))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_beams.append(mi)
	var first := _beam_index(k)
	var rng := float(d.get("beam_range", 240.0))
	var assist := ship.aim_assist_active()
	var lead := ship.lead_point() if assist else Vector3.ZERO
	w["beam_t"] = float(w["beam_t"]) - delta
	var tick: bool = on and w["beam_t"] <= 0.0
	if tick:
		w["beam_t"] = BEAM_TICK
		Sfx.play("straale", -10.0, 0.02)
	for gi in guns.size():
		var bi := first + gi
		if bi >= _beams.size():
			break
		var mi := _beams[bi]
		mi.visible = on
		if not on:
			continue
		var ga = guns[gi]
		var g := Vector3(ga[0], ga[1], ga[2]) if ga is Array else (ga as Vector3)
		var p := ship.global_transform * g
		var dir := _aim_dir_from(p, assist, lead)
		var length := _beam_length(p, dir, rng)
		var mid := p + dir * length * 0.5
		var flick := 0.8 + randf() * 0.5
		mi.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).scaled(Vector3(flick, flick, length)), mid)
		if tick:
			var dmg := float(d.get("dps", 7.0)) * BEAM_TICK * ship.laser_damage() / float(guns.size())
			if W.bolts._own_hit(p, p + dir * length * 1.02, dmg):
				W.fx.burst(p + dir * length, 4, 10.0, [Color.WHITE, Game.col(d.get("color", "ff5af0"))], 0.5, 0.3)
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				ship._net_fire.rpc(p, dir, 900.0, Game.col(d.get("color", "ff5af0")))


func _beam_count() -> int:
	var c := 0
	for w in _w:
		if (w["def"] as Dictionary).get("beam", false):
			c += (w["guns"] as Array).size()
	return c


func _beam_index(k: int) -> int:
	var c := 0
	for j in k:
		if (_w[j]["def"] as Dictionary).get("beam", false):
			c += (_w[j]["guns"] as Array).size()
	return c


## Hvor langt strålen når: til den første pirat på vejen, ellers fuld længde.
func _beam_length(p: Vector3, dir: Vector3, rng: float) -> float:
	var best := rng
	if W.pirates:
		for pp in W.pirates.positions_in(ship.universe.system_at(ship.position)):
			var to := pp - p
			var along := to.dot(dir)
			if along > 0.0 and along < best and (to - dir * along).length() < 4.0:
				best = along
	return best


func stop_beams() -> void:
	for b in _beams:
		b.visible = false
	for w in _w:
		w["firing"] = false


# ---------------------------------------------------------------- gadgets

func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var flying := ship.state == Ship.State.FLY and not ship.dead
	if not flying:
		stop_beams()
	for k in _gcool.size():
		_gcool[k] = maxf(0.0, _gcool[k] - delta)
	if _cloak_t > 0.0:
		_cloak_t -= delta
		if _cloak_t <= 0.0:
			_set_cloak(false)
			Game.toast.emit("Kappen er nede")
	_batt_flash = maxf(0.0, _batt_flash - delta)
	# Dronerne kredser om skibet
	var t := Time.get_ticks_msec() / 1000.0
	var i := 0
	for kind: String in _drones:
		var dn: Node3D = _drones[kind]
		var a := t * 1.6 + i * TAU / maxf(1.0, _drones.size())
		dn.position = Vector3(cos(a) * 4.2, 1.6 + sin(t * 2.3 + i) * 0.4, sin(a) * 4.2 + 1.0)
		dn.rotation.y = -a
		dn.visible = flying and not ship.hide_model and _cloak_t <= 0.0
		i += 1
	if not flying:
		return
	_drone_tick(delta)
	if ship.steering:
		for k in 4:
			if Input.is_action_just_pressed("gadget_%d" % (k + 1)):
				activate(k)
		for k in 5:
			if Input.is_action_just_pressed("weapon_%d" % (k + 1)):
				toggle_weapon(k)


func _drone_tick(delta: float) -> void:
	_drone_cool["kamp"] = float(_drone_cool["kamp"]) - delta
	_drone_cool["forsvar"] = float(_drone_cool["forsvar"]) - delta
	if _drones.has("kamp") and _drone_cool["kamp"] <= 0.0 and W.pirates and _cloak_t <= 0.0:
		var dn: Node3D = _drones["kamp"]
		var from := dn.global_position
		var target := -1
		if ship.lock_target >= 0 and W.pirates.is_active(ship.lock_target) and from.distance_to(W.pirates.position_of(ship.lock_target)) < DRONE_RANGE:
			target = ship.lock_target
		else:
			var cand := W.pirates.lock_candidates(from, ship.forward(), DRONE_RANGE, -1.0, ship.universe.system_at(ship.position))
			var bd := DRONE_RANGE
			for c in cand:
				var dd := from.distance_to(W.pirates.position_of(c))
				if dd < bd:
					bd = dd
					target = c
		if target >= 0:
			_drone_cool["kamp"] = DRONE_COOL / sqrt(Game.gadget_power("kampdrone"))
			var tp := W.pirates.position_of(target)
			var tv := W.pirates.velocity_of(target)
			var aim := tp + tv * from.distance_to(tp) / 320.0
			var dir := (aim - from).normalized()
			dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02).normalized()
			W.bolts.fire(from, dir, 320.0, Color("ff8fb5"), Bolts.Kind.OWN, 0.6 * ship.laser_damage())
			Sfx.play("drone", -10.0)
	if _drones.has("forsvar") and _drone_cool["forsvar"] <= 0.0 and W.missiles:
		if W.missiles.drone_intercept((_drones["forsvar"] as Node3D).global_position, DEF_RANGE):
			_drone_cool["forsvar"] = DEF_COOL / Game.gadget_power("forsvarsdrone")
	if _drones.has("rep") and ship._since_hit > REP_DELAY and ship.hull < 100.0:
		ship.hull = minf(100.0, ship.hull + REP_RATE * Game.gadget_power("repdrone") * delta)
		if randf() < 0.15:
			var dn: Node3D = _drones["rep"]
			W.fx.spawn(dn.global_position, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.0, Color("6bdc4f"), 0.25, 0.4)


## Slå våbnet i plads k til eller fra (taster 1–5).
func toggle_weapon(k: int) -> void:
	var name_ := ""
	for w in _w:
		if int((w["def"] as Dictionary).get("slot", -1)) == k:
			name_ = str(w["def"]["name"])
	if name_ == "":
		return
	if _off.has(k):
		_off.erase(k)
	else:
		_off[k] = true
		if (k < _w.size()):
			stop_beams()
	Sfx.play("klik", -6.0)
	Game.toast.emit("Våben %d · %s %s" % [k + 1, name_, "slået fra" if _off.has(k) else "klar"])


func weapon_on(k: int) -> bool:
	return not _off.has(k)


## Aktivér gadgetten i plads k (taster 6–9).
func activate(k: int) -> void:
	var slots: Array = ship.handling.get("gadget_slots", [])
	if k >= slots.size() or str(slots[k]) == "":
		return
	var it := Game.part(str(slots[k]))
	var gid := Game.part_base(str(slots[k]))
	if not it.get("active", false):
		if gid == "traktor":
			Game.toast.emit("Traktorstrålen: hold %s" % Game.key_name("tractor"))
		return
	if _gcool[k] > 0.0:
		Game.toast.emit("%s lader op (%d s)" % [it["name"], ceili(_gcool[k])])
		return
	_gcool[k] = float(it.get("cooldown", 30.0))
	match gid:
		"kappe":
			_cloak_t = float(it.get("duration", 5.0))
			_set_cloak(true)
			Sfx.play("kappe", -4.0)
			Game.toast.emit("Kappe aktiv – usynlig i %d s" % int(_cloak_t))
		"emp":
			var r := float(it.get("radius", 150.0))
			if W.pirates:
				W.pirates._srv_emp.rpc_id(1, ship.position, r)
			Game.toast.emit("EMP-puls!")
		"batteri":
			ship.shield = ship.shield_max * (1.0 + 0.3 * float(it.get("power", 1.0)))
			_batt_flash = 0.6
			Sfx.play("batteri", -4.0)
			W.fx.burst(ship.position, 30, 16.0, [Color("4dd0ff"), Color.WHITE], 0.6, 0.5)
			Game.toast.emit("Skjoldbatteri: skjold %d" % int(ship.shield))


func _set_cloak(on: bool) -> void:
	ship.set_cloak(on)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		ship._net_cloak.rpc(on)


func cloaked() -> bool:
	return _cloak_t > 0.0


# ---------------------------------------------------------------- til HUD'en

## [{name, charge 0..1, ready, color, heat, hot}] for hvert våben.
func weapon_state() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var reload := float(ship.handling.get("reload_mult", 1.0))
	var base_cd := float(ship.handling.get("fire_cooldown", Ship.FIRE_COOLDOWN))
	for w in _w:
		var d: Dictionary = w["def"]
		var sl := int(d.get("slot", 0))
		var e := {"name": str(d.get("name", "?")), "color": Game.col(d.get("color", "ff4fd8")),
			"slot": sl, "group": int(d.get("group", 0)), "on": not _off.has(sl)}
		if d.get("beam", false):
			e["charge"] = 1.0 - float(w["heat"])
			e["ready"] = not w["hot"]
			e["hot"] = w["hot"]
			e["beam"] = true
		else:
			var cd := base_cd * float(d.get("cd_mult", 1.0)) * reload
			e["charge"] = clampf(1.0 - float(w["cool"]) / maxf(cd, 0.01), 0.0, 1.0)
			e["ready"] = float(w["cool"]) <= 0.0
			if d.has("spinup"):
				e["spin"] = clampf((1.0 - float(w["spin"])) / 0.75, 0.0, 1.0)
		out.append(e)
	return out


## [{key, name, active, ready 0..1, on}] for hver gadgetplads.
func gadget_state() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slots: Array = ship.handling.get("gadget_slots", [])
	for k in slots.size():
		var it := Game.part(str(slots[k]))
		var gid := Game.part_base(str(slots[k]))
		var e := {"key": k + 1, "id": gid, "name": str(it.get("name", "– tom –")), "active": it.get("active", false), "ready": 1.0, "on": false}
		if e["active"]:
			e["ready"] = 1.0 - _gcool[k] / maxf(1.0, float(it.get("cooldown", 30.0))) if k < _gcool.size() else 1.0
			e["on"] = (gid == "kappe" and _cloak_t > 0.0) or (gid == "batteri" and _batt_flash > 0.0)
		elif gid == "traktor":
			e["on"] = ship.tractor_on
		elif gid == "repdrone":
			e["on"] = ship._since_hit > REP_DELAY and ship.hull < 100.0
		out.append(e)
	return out
