class_name Pirates
extends Node3D
## Pirater. Værten styrer AI, bølger, skud og skade og sender positioner ud
## ca. 10 gange i sekundet. Klienterne glider hen mod positionerne og tegner skuddene.
##
## Seks typer (TYPES): Røver (standard), Lynjæger (hurtig, kommer i par, slingrer),
## Kanonbåd (tung, kanontårn der skyder til alle sider), Missilbåd (holder afstand og
## sender missiler), Skyggejæger (usynlig på radar og HUD, til den er tæt på eller skyder)
## og Piratkaptajn (chef med skjold, eskorte og forstærkninger).
##
## AI: angrebsløb mod nærmeste spiller (eller et fragtskib hvis ingen spiller er tæt på),
## sigter foran målet, flankerer i stedet for at komme på række, viger når de bliver
## ramt, flygter med lavt skrog og kommer tilbage, og holder sig ude af atmosfæren og
## væk fra stationer. Bølgerne bliver større og tungere, jo flere der har været.

const POOL := 14
const HP := 6.0
const RAM_DAMAGE := 20.0
const SYNC_INTERVAL := 0.1
const HIT_RADIUS := 4.2
## Fart: røverne er lidt langsommere end en Falk på fuld gas (60), så man kan
## indhente dem; i et angrebsløb og når de trækker væk er de hurtigere.
const CRUISE_SPEED := 46.0
const ATTACK_SPEED := 54.0
const BREAK_SPEED := 58.0
const CLOSE_SPEED := 40.0
const TURN_RATE := 1.6        ## rad/s – hvor hurtigt de kan dreje
const MISSILE_PIRATES := 0.35 ## andel af røverne, der har to missiler med
const BOLT_DAMAGE := 7.0
const CLOAK_RANGE := 140.0    ## skyggejægeren kan ses inden for denne afstand
const BOSS_BAR_RANGE := 1800.0
const FLAK_FUSE := 9.0        ## flakgranatens nærhedsrør
const FLAK_SPLASH := 16.0     ## flakgranatens sprængradius
const ION_TIME := 3.0         ## så længe en ionkanon lammer
const ION_SHIELD := 5.0       ## ionskud slår skjolde 5 gange hårdere ned
const EMP_TIME := 4.0

## Piratetyper. speed/turn er gange standardværdierne; bolt = skade pr. skud;
## cool = tid mellem skud; missiles = antal missiler (-1: tilfældigt 0 eller 2);
## bounty = gange den normale dusør.
const TYPES := {
	"rover": {"name": "Røver", "plural": "Røvere", "hp": 6.0, "speed": 1.0, "turn": 1.0,
		"bolt": 7.0, "cool": [0.45, 0.85], "missiles": -1, "bounty": 1.0, "radius": 4.2, "color": "ff6a2a"},
	"jaeger": {"name": "Lynjæger", "plural": "Lynjægere", "hp": 3.5, "speed": 1.32, "turn": 1.6,
		"bolt": 5.0, "cool": [0.28, 0.5], "missiles": 0, "bounty": 1.2, "radius": 3.6, "color": "ffd23f",
		"jink": true, "flee": true},
	"kanonbaad": {"name": "Kanonbåd", "plural": "Kanonbåde", "hp": 20.0, "speed": 0.74, "turn": 0.55,
		"bolt": 11.0, "cool": [0.8, 1.2], "missiles": 0, "bounty": 2.5, "radius": 7.0, "color": "ff9e3d",
		"turret": true, "no_flee": true},
	"missilbaad": {"name": "Missilbåd", "plural": "Missilbåde", "hp": 9.0, "speed": 0.92, "turn": 0.9,
		"bolt": 6.0, "cool": [0.6, 1.0], "missiles": 5, "bounty": 1.8, "radius": 5.0, "color": "c77dff",
		"kite": true},
	"skygge": {"name": "Skyggejæger", "plural": "Skyggejægere", "hp": 5.0, "speed": 1.15, "turn": 1.3,
		"bolt": 9.0, "cool": [0.4, 0.7], "missiles": 0, "bounty": 2.0, "radius": 4.0, "color": "8da0ff",
		"cloak": true},
	"kaptajn": {"name": "Piratkaptajn", "plural": "Piratkaptajner", "hp": 45.0, "shield": 20.0, "speed": 0.95,
		"turn": 0.85, "bolt": 10.0, "cool": [0.5, 0.8], "missiles": 6, "bounty": 8.0, "radius": 8.0,
		"color": "ff3b3b", "boss": true, "twin": true, "no_flee": true},
}

const CAPTAINS := ["Kaptajn Vraak", "Rødskæg Morn", "Sylla Krag", "Den Grå Hertuginde",
	"Kaptajn Oskar Ild", "Mira Stålkæbe", "Gamle Tand", "Kaptajn Nul"]

signal server_pirate_killed(i: int, tag: String)   ## Kun på serveren

var _p: Array[Dictionary] = []
var _wave_t: Dictionary = {}     ## system -> nedtælling til næste bølge
var _wave_n: Dictionary = {}     ## system -> antal bølger indtil nu
var _sync_t := 0.0
var _clock := 0.0


func _ready() -> void:
	for i in POOL:
		var g := ShipModels.pirate_of("rover")
		g.visible = false
		add_child(g)
		_p.append({"node": g, "active": false, "hp": HP, "hp_max": HP, "type": "rover", "name": "",
			"shield": 0.0, "shield_max": 0.0, "shield_t": 0.0, "system": "", "speed": 0.0,
			"mode": "attack", "mode_t": 0.0, "break_dir": Vector3.FORWARD, "cool": 0.0, "tag": "",
			"net_pos": Vector3.ZERO, "net_rot": Quaternion.IDENTITY, "vel": Vector3.ZERO, "last": Vector3.ZERO,
			"models": {"rover": g}, "flank": Vector3.ZERO, "phase": 0.0, "fled": false,
			"reinforced": false, "reveal": 0.0, "missiles": 0, "mcool": 5.0, "ion": 0.0})
	for sys_id: String in Game.systems:
		_wave_t[sys_id] = wave_interval(sys_id) * 0.5
		_wave_n[sys_id] = 0
	Game.player_joined.connect(_on_player_joined)


## Concord-sikkerhed i et system (0 = lovløst, 1 = Concord-kerne). Høj sikkerhed giver
## sjældne og små bølger, og Concord-patruljer kommer til hjælp.
static func security(sys_id: String) -> float:
	return float(Game.systems[sys_id].get("security", 0.3))


static func wave_interval(sys_id: String) -> float:
	return lerpf(Game.combat("pirate_wave_interval"), 420.0, security(sys_id)) * randf_range(0.8, 1.25)


## Er et punkt tæt på en Concord-base eller -station? Der angriber pirater ikke.
static func in_concord_haven(pos: Vector3) -> bool:
	for st in W.universe.stations:
		if pos.distance_to(st.position) < 700.0:
			return true
	return false


static func type_info(type: String) -> Dictionary:
	return TYPES.get(type, TYPES["rover"])


## Er piraten skjult for den lokale spiller (skyggejæger langt væk, der ikke har skudt)?
func is_hidden(i: int) -> bool:
	var p: Dictionary = _p[i]
	if not type_info(p["type"]).get("cloak", false) or float(p["reveal"]) > 0.0:
		return false
	var me := W.local_ship
	if me == null or not is_instance_valid(me):
		return true
	return me.position.distance_to((p["node"] as Node3D).position) > CLOAK_RANGE


## Til HUD-markører: positioner af aktive pirater i et system (skjulte skyggejægere
## tælles ikke med, medmindre `include_hidden`).
func positions_in(sys_id: String, include_hidden := false) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and p["system"] == sys_id and (include_hidden or not is_hidden(i)):
			out.append((p["node"] as Node3D).position)
	return out


## Til HUD-markører: synlige pirater med type-etiket.
func markers_in(sys_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and p["system"] == sys_id and not is_hidden(i):
			var t := type_info(p["type"])
			out.append({"i": i, "pos": (p["node"] as Node3D).position, "boss": t.get("boss", false),
				"label": (str(p["name"]) if p["name"] != "" else str(t["name"])).to_upper()})
	return out


func type_of(i: int) -> String:
	return _p[i]["type"]


func display_name(i: int) -> String:
	var p: Dictionary = _p[i]
	return str(p["name"]) if p["name"] != "" else str(type_info(p["type"])["name"])


## Den nærmeste aktive chefpirat i systemet inden for BOSS_BAR_RANGE (til HUD'ens chefbjælke), ellers -1.
func boss_near(pos: Vector3, sys_id: String) -> int:
	var best := -1
	var bd := BOSS_BAR_RANGE
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and p["system"] == sys_id and type_info(p["type"]).get("boss", false):
			var d := pos.distance_to((p["node"] as Node3D).position)
			if d < bd:
				bd = d
				best = i
	return best


## Lokalt skud mod pirater: rammer skuddets strækning a–b denne frame en pirat?
## Træffere meldes til værten. `effect`: 1 ion, 2 flak (nærhedsrør: +9 m), 3 krystal.
func hit_test(a: Vector3, b: Vector3, dmg: float, effect := 0) -> bool:
	var extra := FLAK_FUSE if effect == 2 else 0.0
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and Bolts.seg_dist(a, b, (p["node"] as Node3D).position) < float(type_info(p["type"])["radius"]) + extra:
			if effect == 0:
				_srv_hit.rpc_id(1, i, dmg)
			else:
				_srv_hit_fx.rpc_id(1, i, dmg, effect)
			return true
	return false


## Lokalt skib: kollision med en pirat.
func ram_check(pos: Vector3) -> bool:
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and pos.distance_to((p["node"] as Node3D).position) < float(type_info(p["type"])["radius"]) * 0.85:
			_srv_hit.rpc_id(1, i, 3.0)
			return true
	return false


# ---------------------------------------------------------------- server

func _physics_process(delta: float) -> void:
	_clock += delta
	if W.is_server():
		_server_waves(delta)
		for i in POOL:
			if _p[i]["active"]:
				_server_ai(i, delta)
		_sync_t += delta
		if _sync_t >= SYNC_INTERVAL and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_sync_t = 0.0
			var pos := PackedVector3Array()
			var rot := PackedFloat32Array()
			for p in _p:
				var n: Node3D = p["node"]
				pos.append(n.position)
				var q := n.quaternion
				rot.append_array([q.x, q.y, q.z, q.w])
			_cl_state.rpc(pos, rot)
	else:
		var k := 1.0 - exp(-delta * 10.0)
		for p in _p:
			if p["active"]:
				var n: Node3D = p["node"]
				n.position = n.position.lerp(p["net_pos"], k)
				n.quaternion = n.quaternion.slerp(p["net_rot"], k)
	# Hastighed (til lock-on og forudsigelse), på alle maskiner
	if delta > 0.0:
		for p in _p:
			if p["active"]:
				var pos: Vector3 = (p["node"] as Node3D).position
				var v: Vector3 = (pos - (p["last"] as Vector3)) / delta
				if v.length() < 400.0:
					p["vel"] = (p["vel"] as Vector3).lerp(v, 0.25)
				p["last"] = pos
				p["reveal"] = maxf(0.0, float(p["reveal"]) - delta)


## Sammensætning af en bølge: flere og tungere pirater, jo flere bølger der har været,
## og jo mere lovløst systemet er. Hver 5. bølge i lovløst rum kommer en kaptajn.
func wave_mix(sys_id: String, wave: int) -> Array[String]:
	var sec := security(sys_id)
	var out: Array[String] = []
	if sec < 0.6 and wave >= 4 and wave % 5 == 4:
		out.assign(["kaptajn", "jaeger", "jaeger"])
		if wave >= 9:
			out.append("kanonbaad")
		return out
	var n := mini(5, 2 + int(wave / 2))
	if sec > 0.7:
		n = mini(n, 2)     # Concord-rum: kun små grupper
	var pool: Array[String] = ["rover", "rover"]
	if wave >= 1:
		pool.append("jaeger")
	if wave >= 2 and sec <= 0.7:
		pool.append("missilbaad")
	if wave >= 3 and sec < 0.6:
		pool.append("kanonbaad")
	if wave >= 2 and sec < 0.5:
		pool.append("skygge")
	out.append("rover")
	while out.size() < n:
		var t: String = pool.pick_random()
		out.append(t)
		if t == "jaeger" and out.size() < n:
			out.append("jaeger")   # Lynjægere flyver i par
	return out


## "2 Røvere, Kanonbåd" – til beskeder.
static func describe(types: Array) -> String:
	var counts := {}
	var order: Array[String] = []
	for t: String in types:
		if not counts.has(t):
			counts[t] = 0
			order.append(t)
		counts[t] += 1
	var parts: Array[String] = []
	for t in order:
		var info := type_info(t)
		parts.append(str(info["name"]) if counts[t] == 1 else "%d %s" % [counts[t], info["plural"]])
	return ", ".join(parts)


func _server_waves(delta: float) -> void:
	if W.missions and W.missions.active:
		return     # Ingen tilfældige bølger, mens en mission er i gang.
	for sys_id: String in _wave_t:
		var in_space: Array[Ship] = []
		for s in W.active_ships():
			if W.universe.system_at(s.position) != sys_id:
				continue
			var pl := W.universe.nearest_planet(s.position)
			if pl.altitude(s.position) > pl.atmo_top and not in_concord_haven(s.position):
				in_space.append(s)
		if in_space.is_empty() or not positions_in(sys_id, true).is_empty():
			continue
		_wave_t[sys_id] -= delta
		if _wave_t[sys_id] > 0.0:
			continue
		var target: Ship = in_space.pick_random()
		server_send_wave(sys_id, target.position, wave_mix(sys_id, int(_wave_n[sys_id])))
		_wave_n[sys_id] += 1
		_wave_t[sys_id] = wave_interval(sys_id)


## Server: send en bølge af de givne typer ud omkring `near` og giv spillerne besked.
func server_send_wave(sys_id: String, near: Vector3, types: Array[String]) -> void:
	var sent: Array[String] = []
	var boss := -1
	var center := _spawn_point(near)
	for t in types:
		var pos := center + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * 40.0
		var i := server_spawn_at(sys_id, pos, near, "", t)
		if i >= 0:
			sent.append(t)
			if t == "kaptajn":
				boss = i
	if sent.is_empty():
		return
	var sec := security(sys_id)
	var help := sec > 0.3 and W.patrols != null and W.patrols.server_alert(sys_id, near)
	var msg := ""
	if boss >= 0:
		msg = "⚠ %s og eskorte på radaren! Stor dusør" % display_name(boss)
	else:
		msg = "Pirater på radaren: %s" % describe(sent)
	if help:
		msg += " · En Concord-patrulje er på vej"
	for s in W.active_ships():
		if W.universe.system_at(s.position) == sys_id:
			Game.server_toast(s.peer_id, msg)


func _spawn_point(near: Vector3) -> Vector3:
	var pos := near
	for t in 10:
		pos = near + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized() * randf_range(380, 480)
		var pl := W.universe.nearest_planet(pos)
		if pl.altitude(pos) > pl.atmo_top + 80.0:
			break
	return pos


func _server_spawn(sys_id: String, near: Vector3, type := "rover") -> int:
	return server_spawn_at(sys_id, _spawn_point(near), near, "", type)


## Server: send en pirat ud på en bestemt position, rettet mod `look`. Returnerer indeks eller -1.
func server_spawn_at(sys_id: String, pos: Vector3, look: Vector3, tag: String, type := "rover") -> int:
	if not TYPES.has(type):
		type = "rover"
	for i in POOL:
		if _p[i]["active"]:
			continue
		var dir := (look - pos).normalized() if look.distance_to(pos) > 1.0 else Vector3.FORWARD
		var rot := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
		var nm := ""
		if type == "kaptajn":
			nm = CAPTAINS.pick_random()
		_cl_spawn.rpc(i, sys_id, pos, rot, type, nm)
		var info := type_info(type)
		var p: Dictionary = _p[i]
		p["tag"] = tag
		var m := int(info["missiles"])
		p["missiles"] = (2 if randf() < MISSILE_PIRATES else 0) if m < 0 else m
		p["mcool"] = randf_range(4.0, 8.0)
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		p["flank"] = (side * randf_range(-1, 1) + Vector3.UP * randf_range(-0.6, 0.6)).normalized()
		p["phase"] = randf() * TAU
		p["fled"] = false
		p["reinforced"] = false
		return i
	return -1


## Server: nærmeste aktive pirat inden for `range` meter (eller -1).
func server_nearest(from: Vector3, range_m: float) -> int:
	var best := -1
	var bd := range_m
	for i in POOL:
		if _p[i]["active"]:
			var d := from.distance_to((_p[i]["node"] as Node3D).position)
			if d < bd:
				bd = d
				best = i
	return best


## Position af nærmeste synlige pirat inden for `range_m` (alle maskiner), ellers Vector3.INF.
func nearest_visible(from: Vector3, range_m: float) -> Vector3:
	var best := Vector3.INF
	var bd := range_m
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and not is_hidden(i):
			var pos: Vector3 = (p["node"] as Node3D).position
			var d := from.distance_to(pos)
			if d < bd:
				bd = d
				best = pos
	return best


func is_active(i: int) -> bool:
	return i >= 0 and i < POOL and _p[i]["active"]


func velocity_of(i: int) -> Vector3:
	return _p[i]["vel"]


func hp_fraction(i: int) -> float:
	return clampf(float(_p[i]["hp"]) / maxf(0.1, float(_p[i]["hp_max"])), 0.0, 1.0)


func shield_fraction(i: int) -> float:
	var sm := float(_p[i]["shield_max"])
	return clampf(float(_p[i]["shield"]) / sm, 0.0, 1.0) if sm > 0.0 else 0.0


func system_of(i: int) -> String:
	return _p[i]["system"]


## Lock-on: aktive pirater i systemet inden for rækkevidde, sorteret efter vinkel fra
## sigteretningen (den tættest på sigtekornet først). `cone` er cos(maks. vinkel).
## Skjulte skyggejægere kan ikke låses.
func lock_candidates(from: Vector3, fwd: Vector3, range_m: float, cone: float, sys_id: String) -> Array[int]:
	var out: Array[int] = []
	var score: Dictionary = {}
	for i in POOL:
		var p: Dictionary = _p[i]
		if not p["active"] or p["system"] != sys_id or is_hidden(i):
			continue
		var to: Vector3 = (p["node"] as Node3D).position - from
		var d := to.length()
		if d > range_m or d < 1.0:
			continue
		var dot := fwd.dot(to / d)
		if dot < cone:
			continue
		out.append(i)
		score[i] = dot
	out.sort_custom(func(a: int, b: int) -> bool: return score[a] > score[b])
	return out


func position_of(i: int) -> Vector3:
	return (_p[i]["node"] as Node3D).position


## Server: skade uden dusør (fx fra basens forsvarstårne).
func server_damage(i: int, dmg: float) -> void:
	_server_apply(i, dmg, 0)


## Server: fælles skadeberegning. `who` = spilleren, der får dusøren (0 = ingen).
## `effect`: 1 ion (lammer, 5× mod skjold), 2 flak (rammer også dem omkring), 3 krystal (gennem skjold).
func _server_apply(i: int, dmg: float, who: int, effect := 0) -> void:
	var p: Dictionary = _p[i]
	if not p["active"]:
		return
	var info := type_info(p["type"])
	p["shield_t"] = 4.0
	if effect == 2:
		var here := position_of(i)
		for j in POOL:
			if j != i and _p[j]["active"] and position_of(j).distance_to(here) < FLAK_SPLASH:
				_server_apply(j, dmg * 0.6, who, 0)
		if not p["active"]:
			return
	if effect == 1:
		p["ion"] = ION_TIME
		_cl_ion.rpc(i, ION_TIME)
		if float(p["shield"]) > 0.0:
			var sd := minf(float(p["shield"]), dmg * ION_SHIELD)
			p["shield"] = float(p["shield"]) - sd
			dmg = maxf(0.0, dmg - sd / ION_SHIELD)
	if float(p["shield"]) > 0.0 and effect != 3:
		var absorbed := minf(float(p["shield"]), dmg)
		p["shield"] = float(p["shield"]) - absorbed
		dmg -= absorbed
	p["hp"] = float(p["hp"]) - dmg
	p["reveal"] = 3.0
	if float(p["hp"]) > 0.0:
		_cl_hit_fx.rpc(i, p["hp"], p["shield"])
		_server_on_hurt(i, info)
		return
	var tag: String = p["tag"]
	var pos := position_of(i)
	var bounty := float(info["bounty"])
	_cl_kill.rpc(i)
	if who != 0:
		W.pickups.server_spawn("malm", pos, 2 + int(bounty) / 2 + (1 if Game.server_has_gadget(who, "skrotarm") else 0))
		if info.get("boss", false):
			W.pickups.server_spawn("krystal", pos + Vector3(2, 0, 0), 3)
		Game.server_award_bounty(who, bounty, display_name(i))
	else:
		W.pickups.server_spawn("malm", pos, 1)
	server_pirate_killed.emit(i, tag)


## Server: reaktion på en træffer – vige ud, flygte med lavt skrog, kaptajnens forstærkninger.
func _server_on_hurt(i: int, info: Dictionary) -> void:
	var p: Dictionary = _p[i]
	var n: Node3D = p["node"]
	var frac := hp_fraction(i)
	if info.get("boss", false) and not p["reinforced"] and frac < 0.5:
		p["reinforced"] = true
		for k in 2:
			var off := n.global_basis * Vector3((k * 2 - 1) * 60.0, 20.0, 80.0)
			server_spawn_at(p["system"], n.position + off, n.position - n.global_basis.z * 200.0, p["tag"], "jaeger")
		for s in W.active_ships():
			if W.universe.system_at(s.position) == p["system"]:
				Game.server_toast(s.peer_id, "%s kalder forstærkninger ind!" % display_name(i))
		return
	if not info.get("no_flee", false) and not p["fled"] and frac < 0.34 and randf() < 0.7:
		p["fled"] = true
		p["mode"] = "flee"
		p["mode_t"] = randf_range(5.0, 7.0)
		p["break_dir"] = (-n.global_basis.z + Vector3(randf_range(-0.5, 0.5), randf_range(-0.3, 0.5), randf_range(-0.5, 0.5))).normalized()
		return
	if p["mode"] == "attack" and not info.get("turret", false) and randf() < 0.3:
		var fwd := -n.global_basis.z
		var side := (n.global_basis.x * (1.0 if randf() < 0.5 else -1.0) + n.global_basis.y * randf_range(-0.6, 0.6)).normalized()
		p["mode"] = "break"
		p["mode_t"] = randf_range(0.9, 1.5)
		p["break_dir"] = (fwd * 0.4 + side).normalized()


## Server: tilfældig pirat-bølge eller en bestemt type tæt på et skib (testværktøjer).
func server_test_spawn(near: Vector3, sys_id: String, what: String) -> String:
	var types: Array[String] = []
	match what:
		"bolge":
			types = wave_mix(sys_id, 3 + randi() % 6)
			if types.has("kaptajn"):
				types = wave_mix(sys_id, 6)
		"kaptajn":
			types = wave_mix(sys_id, 9)
			if not types.has("kaptajn"):
				types.assign(["kaptajn", "jaeger", "jaeger"])
		_:
			if TYPES.has(what):
				types.assign([what, what] if what == "jaeger" else [what])
	server_send_wave(sys_id, near, types)
	return describe(types)


## Server: antal aktive pirater med et bestemt mærke (fx en missions pirater).
func server_count_tag(tag: String) -> int:
	var n := 0
	for p in _p:
		if p["active"] and p["tag"] == tag:
			n += 1
	return n


## Server: fjern alle pirater med et mærke uden eksplosion (fx når en mission slutter).
func server_despawn_tag(tag: String) -> void:
	for i in POOL:
		if _p[i]["active"] and _p[i]["tag"] == tag:
			_cl_despawn.rpc(i)


@rpc("authority", "call_local", "reliable")
func _cl_despawn(i: int) -> void:
	_p[i]["active"] = false
	_p[i]["tag"] = ""
	(_p[i]["node"] as Node3D).visible = false


func _server_ai(i: int, delta: float) -> void:
	var p: Dictionary = _p[i]
	var info := type_info(p["type"])
	var n: Node3D = p["node"]
	var pos := n.position
	var fwd := -n.global_basis.z
	var up := n.global_basis.y

	# Kaptajnens skjold lader op, når den ikke er blevet ramt et stykke tid
	if float(p["shield_max"]) > 0.0:
		p["shield_t"] = float(p["shield_t"]) - delta
		if p["shield_t"] <= 0.0 and float(p["shield"]) < float(p["shield_max"]):
			p["shield"] = minf(float(p["shield_max"]), float(p["shield"]) + 2.5 * delta)
			if int(_clock * 2.0) != int((_clock - delta) * 2.0):
				_cl_shield.rpc(i, p["shield"])

	# Vælg mål: missionens eskorteskib for missionspirater, ellers nærmeste spiller
	# inden for 450 m, ellers et fragtskib, ellers nærmeste spiller.
	var t_pos := Vector3.ZERO
	var t_vel := Vector3.ZERO
	var has_target := false
	var is_freighter := false
	if str(p["tag"]).begins_with("raid_") and W.bases:
		var rt := W.bases.server_raid_target(p["tag"])
		if not rt.is_empty():
			t_pos = rt["pos"]
			t_vel = rt["vel"]
			has_target = true
			is_freighter = true
	elif str(p["tag"]).begins_with("job_esc_") and W.traffic:
		var et := W.traffic.server_escort_target(p["tag"])
		if not et.is_empty():
			t_pos = et["pos"]
			t_vel = et["vel"]
			has_target = true
			is_freighter = true
	elif p["tag"] != "" and W.missions:
		var esc := W.missions.server_escort_target(p["tag"], pos)
		if not esc.is_empty():
			t_pos = esc["pos"]
			t_vel = esc["vel"]
			has_target = true
			is_freighter = true
	var ionized := float(p["ion"]) > 0.0
	if ionized:
		p["ion"] = float(p["ion"]) - delta
	var target_ship: Ship = null
	var best := 450.0 if not has_target else 320.0   # missionspirater vender sig mod spillere, der kommer tæt på
	if info.get("kite", false) or info.get("boss", false):
		best = 700.0
	var nearest_any := INF
	var any_ship: Ship = null
	for s in W.active_ships():
		if s.cloaked or W.universe.system_at(s.position) != p["system"]:
			continue
		var d := s.position.distance_to(pos)
		if d < nearest_any:
			nearest_any = d
			any_ship = s
		if d < best:
			best = d
			t_pos = s.position
			t_vel = s.forward() * s.speed
			has_target = true
			is_freighter = false
			target_ship = s
	# Concord-patruljer tæt på bliver også angrebet
	if W.patrols:
		var pt := W.patrols.server_nearest_target(pos, p["system"], best if target_ship else 300.0)
		if not pt.is_empty():
			t_pos = pt["pos"]
			t_vel = pt["vel"]
			has_target = true
			is_freighter = true
			target_ship = null
	if not has_target and W.freighters:
		var f := W.freighters.server_nearest_target(pos, p["system"])
		if not f.is_empty():
			t_pos = f["pos"]
			t_vel = f["vel"]
			has_target = true
			is_freighter = true
	if not has_target and any_ship:
		t_pos = any_ship.position
		t_vel = any_ship.forward() * any_ship.speed
		has_target = true
		target_ship = any_ship

	var dist := pos.distance_to(t_pos) if has_target else INF
	var to_t := (t_pos - pos).normalized() if has_target else fwd
	var target_dir := fwd
	if p["mode"] == "break" or p["mode"] == "flee":
		target_dir = p["break_dir"]
		p["mode_t"] -= delta
		if p["mode_t"] <= 0.0:
			p["mode"] = "attack"
	elif has_target:
		target_dir = (t_pos + t_vel * dist / 220.0 - pos).normalized()
		if info.get("kite", false):
			# Missilbåd: hold 330–520 m afstand og cirkl rundt om målet
			var side := to_t.cross(up).normalized()
			if dist < 330.0:
				target_dir = (-to_t + side * 0.8).normalized()
			elif dist < 560.0:
				target_dir = (side + to_t * 0.15).normalized()
		elif info.get("turret", false):
			# Kanonbåd: kører langsomt hen mod målet og lægger sig på siden i 120–220 m
			if dist < 220.0:
				target_dir = (to_t.cross(up).normalized() + to_t * (0.2 if dist > 120.0 else -0.4)).normalized()
		elif dist > 160.0:
			# Flankér: kom ind fra hver sin side i stedet for i en lang række
			target_dir = (target_dir + (p["flank"] as Vector3) * 0.45 * clampf((dist - 160.0) / 300.0, 0.0, 1.0)).normalized()
		if info.get("jink", false) and dist < 400.0:
			var right := n.global_basis.x
			target_dir = (target_dir + right * sin(_clock * 3.1 + float(p["phase"])) * 0.32 \
				+ up * cos(_clock * 2.3 + float(p["phase"])) * 0.2).normalized()
		if not info.get("kite", false) and not info.get("turret", false) and dist < (45.0 if is_freighter else 35.0) + float(info["radius"]) * 2.0:
			p["mode"] = "break"
			p["mode_t"] = randf_range(1.6, 2.6)
			p["break_dir"] = (fwd + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()

	# Undgå planeter og stationer.
	var pl := W.universe.nearest_planet(pos)
	if pl.ground_altitude(pos) < 45.0:
		target_dir = (pos - pl.position).normalized()
	elif pl.ground_altitude(pos) < 90.0 and target_dir.dot((pos - pl.position).normalized()) < 0.0:
		target_dir = (target_dir - (pos - pl.position).normalized() * target_dir.dot((pos - pl.position).normalized())).normalized()
	for st in W.universe.stations:
		if pos.distance_to(st.position) < 45.0:
			target_dir = (pos - st.position).normalized()

	# Drej med en fast maksimal hastighed (så de kan "overløbes" i et sving)
	var want := Basis.looking_at(target_dir, up if absf(target_dir.dot(up)) < 0.98 else fwd).get_rotation_quaternion()
	var ang := n.quaternion.angle_to(want)
	if ang > 0.0001:
		n.quaternion = n.quaternion.slerp(want, minf(1.0, TURN_RATE * float(info["turn"]) * (0.35 if ionized else 1.0) * delta / ang)).normalized()
	var target_speed := CRUISE_SPEED
	if p["mode"] == "flee":
		target_speed = BREAK_SPEED * 1.1
	elif p["mode"] == "break":
		target_speed = BREAK_SPEED
	elif has_target and dist < 90.0:
		# Tæt på: sæt farten ned for at sigte. Farten afhænger IKKE af spillerens fart,
		# så de hverken klæber til en hurtig spiller eller bliver ufangelige.
		target_speed = CLOSE_SPEED
	elif has_target and dist < 300.0:
		target_speed = ATTACK_SPEED
	target_speed *= float(info["speed"]) * (0.45 if ionized else 1.0)
	# Skarpe sving koster fart – så er de nemmere at ramme
	target_speed *= 1.0 - 0.3 * clampf(ang / 1.2, 0.0, 1.0)
	p["speed"] = lerpf(p["speed"], target_speed, minf(1.0, delta * 1.2))
	n.position += -n.global_basis.z * float(p["speed"]) * delta

	if p["mode"] == "flee" or ionized:
		return     # Flygtende og lammede pirater skyder ikke
	# Missil mod en spiller på mellemdistance
	p["mcool"] = float(p["mcool"]) - delta
	var m_cone := -0.3 if info.get("kite", false) else (0.3 if info.get("boss", false) else 0.9)
	if target_ship and int(p["missiles"]) > 0 and p["mcool"] <= 0.0 and dist > 160.0 and dist < 650.0 \
			and fwd.dot(to_t) > m_cone and W.missiles:
		p["missiles"] = int(p["missiles"]) - 1
		p["mcool"] = randf_range(4.5, 6.5) if info.get("kite", false) else randf_range(7.0, 11.0)
		var mdir := (fwd + to_t).normalized()
		W.missiles.server_pirate_fire(pos + mdir * 4.0, mdir, target_ship.peer_id)
	p["cool"] -= delta
	if not has_target or p["mode"] != "attack" or p["cool"] > 0.0:
		return
	var cool: Array = info["cool"]
	var bolt := float(info["bolt"])
	var col := Color(str(info["color"]))
	if info.get("turret", false):
		# Kanontårnet skyder til alle sider inden for 320 m
		if dist < 320.0:
			p["cool"] = randf_range(float(cool[0]), float(cool[1]))
			var muzzle := pos + up * 2.2
			var aim := (t_pos + t_vel * dist / 190.0 - muzzle).normalized()
			aim = (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012).normalized()
			_cl_fire.rpc(i, muzzle, aim, 190.0, bolt, col)
		return
	if dist < (300.0 if info.get("boss", false) else 260.0) and fwd.dot(to_t) > 0.985:
		p["cool"] = randf_range(float(cool[0]), float(cool[1]))
		var aim := (t_pos + t_vel * dist / 200.0 - pos).normalized()
		aim = (aim + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.025).normalized()
		var sp := 170.0 + float(p["speed"])
		if info.get("twin", false):
			var right := n.global_basis.x * 4.0
			_cl_fire.rpc(i, pos + fwd * 4.0 + right, aim, sp, bolt, col)
			_cl_fire.rpc(i, pos + fwd * 4.0 - right, aim, sp, bolt, col)
		else:
			_cl_fire.rpc(i, pos + fwd * 3.0, aim, sp, bolt, col)


@rpc("any_peer", "call_local", "reliable")
func _srv_hit(i: int, dmg: float) -> void:
	if not multiplayer.is_server() or i < 0 or i >= POOL or not _p[i]["active"]:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	_server_apply(i, dmg, who)


@rpc("any_peer", "call_local", "reliable")
func _srv_hit_fx(i: int, dmg: float, effect: int) -> void:
	if not multiplayer.is_server() or i < 0 or i >= POOL or not _p[i]["active"]:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	_server_apply(i, dmg, who, effect)


## EMP-puls (gadget): lammer alle pirater inden for `radius` og slår deres skjolde ned.
@rpc("any_peer", "call_local", "reliable")
func _srv_emp(pos: Vector3, radius: float) -> void:
	if not multiplayer.is_server():
		return
	_cl_emp_fx.rpc(pos, radius)
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and position_of(i).distance_to(pos) < radius:
			p["ion"] = EMP_TIME
			p["shield"] = 0.0
			p["shield_t"] = 6.0
			p["reveal"] = EMP_TIME
			_cl_ion.rpc(i, EMP_TIME)
			_cl_shield.rpc(i, 0.0)


# ---------------------------------------------------------------- alle maskiner

@rpc("authority", "call_local", "reliable")
func _cl_ion(i: int, t: float) -> void:
	_p[i]["ion"] = t
	_p[i]["reveal"] = maxf(float(_p[i]["reveal"]), t)


@rpc("authority", "call_local", "reliable")
func _cl_emp_fx(pos: Vector3, radius: float) -> void:
	for k in 48:
		var a := k * TAU / 48.0
		W.fx.spawn(pos, Vector3(cos(a), randf_range(-0.15, 0.15), sin(a)) * radius / 0.7, Color("4d8bff") if k % 2 == 0 else Color("9fe2ff"), 1.2, 0.7)
	W.fx.burst(pos, 30, 40.0, [Color("4d8bff"), Color.WHITE], 1.0, 0.5)
	Sfx.play_at("emp", pos, 2.0)

## Skift slotets model til den rigtige type (modellerne gemmes, så skiftet er billigt).
func _set_type(i: int, type: String) -> void:
	var p: Dictionary = _p[i]
	var old: Node3D = p["node"]
	p["type"] = type
	var models: Dictionary = p["models"]
	if not models.has(type):
		var g := ShipModels.pirate_of(type)
		g.visible = false
		add_child(g)
		models[type] = g
	var node: Node3D = models[type]
	if node != old:
		old.visible = false
		p["node"] = node


@rpc("authority", "call_local", "reliable")
func _cl_spawn(i: int, sys_id: String, pos: Vector3, rot: Quaternion, type := "rover", nm := "") -> void:
	_set_type(i, type)
	var info := type_info(type)
	var p: Dictionary = _p[i]
	p["active"] = true
	p["hp_max"] = float(info["hp"])
	p["hp"] = p["hp_max"]
	p["shield_max"] = float(info.get("shield", 0.0))
	p["shield"] = p["shield_max"]
	p["shield_t"] = 0.0
	p["name"] = nm
	p["reveal"] = 0.0
	p["ion"] = 0.0
	p["system"] = sys_id
	p["mode"] = "attack"
	p["cool"] = randf_range(1.0, 2.0)
	p["speed"] = 40.0 * float(info["speed"])
	p["net_pos"] = pos
	p["net_rot"] = rot
	p["vel"] = Vector3.ZERO
	p["last"] = pos
	var n: Node3D = p["node"]
	n.position = pos
	n.quaternion = rot
	n.reset_physics_interpolation()
	n.visible = true
	if n.has_meta("shield"):
		(n.get_meta("shield") as Node3D).visible = true


@rpc("authority", "call_local", "reliable")
func _cl_kill(i: int) -> void:
	var p: Dictionary = _p[i]
	p["active"] = false
	p["tag"] = ""
	var n: Node3D = p["node"]
	n.visible = false
	p["hp"] = 0.0
	var info := type_info(p["type"])
	var big := float(info["radius"]) / 4.2
	W.fx.burst(n.position, int(34 * big), 38.0 * big, Effects.EXPLOSION + [Color(str(info["color"]))], 1.5 * big, 1.3 * sqrt(big))
	Sfx.play_at("eksplosion", n.position, 2.0 + 2.0 * (big - 1.0))
	if info.get("boss", false):
		Game.toast.emit("%s er nedkæmpet!" % display_name(i))
		for k in 4:
			var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 8.0
			W.fx.burst(n.position + off, 24, 30.0, Effects.EXPLOSION, 1.4, 1.0)


@rpc("authority", "call_local", "unreliable")
func _cl_hit_fx(i: int, hp: float, shield := 0.0) -> void:
	var p: Dictionary = _p[i]
	var had_shield := float(p["shield"]) > 0.0
	p["hp"] = hp
	p["shield"] = shield
	p["reveal"] = 3.0
	var n: Node3D = p["node"]
	var pos := n.position
	if had_shield:
		W.fx.burst(pos, 8, 18.0, [Color("8ad8ff"), Color.WHITE], 0.6, 0.5)
		Sfx.play_at("traef", pos, -6.0)
	else:
		W.fx.burst(pos, 6, 14.0, [Color.WHITE, Color("7dff4d")], 0.6, 0.4)
		Sfx.play_at("traef", pos, -2.0)
	if n.has_meta("shield"):
		(n.get_meta("shield") as Node3D).visible = shield > 0.0


@rpc("authority", "call_local", "unreliable")
func _cl_shield(i: int, shield: float) -> void:
	_p[i]["shield"] = shield
	var n: Node3D = _p[i]["node"]
	if n.has_meta("shield"):
		(n.get_meta("shield") as Node3D).visible = shield > 0.0


@rpc("authority", "call_local", "unreliable")
func _cl_fire(i: int, pos: Vector3, dir: Vector3, speed: float, dmg := BOLT_DAMAGE, col := Color("ff6a2a")) -> void:
	W.bolts.fire(pos, dir, speed, col, Bolts.Kind.PIRATE, dmg)
	Sfx.play_at("laser_pirat", pos, -4.0 + (3.0 if dmg > 9.0 else 0.0))
	if i >= 0 and i < POOL:
		_p[i]["reveal"] = 2.5     # skyggejægeren afslører sig, når den skyder


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_state(pos: PackedVector3Array, rot: PackedFloat32Array) -> void:
	for i in mini(pos.size(), POOL):
		_p[i]["net_pos"] = pos[i]
		_p[i]["net_rot"] = Quaternion(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"]:
			var n: Node3D = p["node"]
			_cl_spawn.rpc_id(id, i, p["system"], n.position, n.quaternion, p["type"], p["name"])


func _process(_delta: float) -> void:
	for i in POOL:
		var p: Dictionary = _p[i]
		if not p["active"]:
			continue
		var n: Node3D = p["node"]
		var fl: Node3D = n.get_meta("flame")
		fl.scale = Vector3(1, 0.4 + float(p["speed"]) / 60.0 + randf() * 0.2, 1)
		if float(p["ion"]) > 0.0:
			if not W.is_server():
				p["ion"] = float(p["ion"]) - _delta
			if randf() < 0.35:
				W.fx.spawn(n.position + Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2)),
					Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)), Color("9fe2ff") if randf() < 0.5 else Color("4d8bff"), 0.3, 0.25)
		if type_info(p["type"]).get("cloak", false):
			# Skjult: kun et svagt flimmer en gang imellem
			n.visible = not is_hidden(i) or randf() < 0.03
