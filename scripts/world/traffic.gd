class_name Traffic
extends Node3D
## Civil trafik: skibe fra Husene (Meridian, Vostrand, Caldera, Seiran) og fri handlende,
## der flyver mellem byer, stationer og gates i hvert system. Man kan kalde dem op (H):
## nogle vil handle, nogle har en opgave (levering eller eskorte), nogle har et tip om
## et vrag eller et fund, og andre vil bare snakke.
## Værten simulerer (kun i systemer med spillere); klienterne får positioner 10 gange i sekundet.

const SYNC_INTERVAL := 0.1
const SPEED := 38.0
const HAIL_RANGE := 500.0
const HP := 40.0

const HOUSES := {
	"meridian": {"name": "Meridian", "color": "ffd23f"},
	"vostrand": {"name": "Vostrand", "color": "4d8bff"},
	"caldera": {"name": "Caldera", "color": "ff7a3d"},
	"seiran": {"name": "Seiran", "color": "6bdc4f"},
	"fri": {"name": "Fri handler", "color": "b8b4d8"},
}
const KINDS := [
	{"kind": "fragter", "model": "fragter", "label": "fragteren"},
	{"kind": "handel", "model": "albatros", "label": "handelsskibet"},
	{"kind": "spejder", "model": "spejder", "label": "spejderen"},
	{"kind": "opmaaler", "model": "opmaaler", "label": "opmålingsskibet"},
	{"kind": "kurer", "model": "falk", "label": "kureren"},
]
const NAMES := ["Solsikke", "Kestrel", "Vandreren", "Mira", "Gamle Ole", "Stjernefrø", "Lynet", "Nordlys",
	"Havørn", "Tusmørke", "Sirius", "Jærven", "Lykkens Gave", "Frøken Ida", "Kometen", "Støvfnug", "Vega",
	"Sommerfugl", "Brokken", "Fyrtårnet", "Draugen", "Tordis", "Ravnsborg", "Glimt"]
const CHATTER := [
	"Bare på vej hjem med en last frugt. Flyv sikkert, patrulje!",
	"Skønt at se Concord herude. Piraterne har været frække på det sidste.",
	"Har du hørt om signalerne fra Architects? Folk siger, de bliver stærkere.",
	"Min bedstefar sagde altid: stol aldrig på en billig fragtpris i Ravne.",
	"Vi kom lige fra den anden side af gaten. Stille derovre – for stille.",
	"Hvis du ser Vogteren, så sig til kommandøren, at Seiran stadig skylder mig en øl.",
	"Ingen opgaver i dag, desværre. Men tak fordi du holder øje!",
]

var _n: Array[Dictionary] = []     ## {node, label, system, pos_list, target, house, kind, name, offer, hp, alive, escort, net_pos, net_rot}
var _points: Dictionary = {}       ## system -> Array[Dictionary{pos, loc}]
var _sync_t := 0.0


func _ready() -> void:
	for sys_id: String in Game.systems:
		var pts: Array[Dictionary] = []
		for p in W.universe.planets:
			if p.system_id == sys_id:
				for pad in p.pads:
					if pad.get("kind", "city") in ["city", "outpost"]:
						pts.append({"pos": (pad["top"] as Vector3) + (pad["dir"] as Vector3) * (p.atmo_top * 0.8), "loc": pad["id"]})
		for st in W.universe.stations:
			if st.system_id == sys_id and not st.data.get("plot", false):
				pts.append({"pos": st.dock_pos + st.dock_dir * 60.0 + Vector3(0, 25, 0), "loc": st.id})
		for g: Dictionary in W.universe.gates.values():
			if g["system"] == sys_id:
				pts.append({"pos": (g["pos"] as Vector3) + (g["dir"] as Vector3) * 80.0, "loc": ""})
		_points[sys_id] = pts
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for sys_id: String in Game.systems:
		var pts: Array = _points[sys_id]
		if pts.size() < 2:
			continue
		var count := 3 + int(Pirates.security(sys_id) * 3.0)
		for k in count:
			var house: String = HOUSES.keys()[rng.randi() % HOUSES.size()]
			var kind: Dictionary = KINDS[rng.randi() % KINDS.size()]
			var m := ShipModel.new()
			m.ship_class = kind["model"]
			m.paint = Game.col(HOUSES[house]["color"])
			m.visible = false
			add_child(m)
			var lbl := Label3D.new()
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.fixed_size = true
			lbl.pixel_size = 0.0011
			lbl.font_size = 22
			lbl.outline_size = 6
			lbl.no_depth_test = true
			lbl.modulate = Game.col(HOUSES[house]["color"])
			lbl.position = Vector3(0, 6, 0)
			m.add_child(lbl)
			var nm := "%s-%s %s" % [HOUSES[house]["name"], kind["label"], NAMES[rng.randi() % NAMES.size()]]
			if house == "fri":
				nm = "Fri handler %s" % NAMES[rng.randi() % NAMES.size()]
			lbl.text = nm
			var start: Vector3 = (pts[k % pts.size()]["pos"] as Vector3) + Vector3(rng.randf_range(-80, 80), rng.randf_range(-30, 30), rng.randf_range(-80, 80))
			m.position = start
			_n.append({"node": m, "label": lbl, "system": sys_id, "target": (k + 1) % pts.size(), "house": house,
				"kind": kind["kind"], "name": nm, "offer": _roll_offer(rng), "hp": HP, "alive": true, "escort": {},
				"net_pos": start, "net_rot": Quaternion.IDENTITY, "respawn": 0.0, "start": start})
	Net.started.connect(_on_net_started)
	Game.player_joined.connect(func(id: int) -> void:
		if W.is_server() and id != multiplayer.get_unique_id():
			for i in _n.size():
				_cl_alive.rpc_id(id, i, _n[i]["alive"]))


func _roll_offer(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if r < 0.25:
		return "handel"
	if r < 0.5:
		return "levering"
	if r < 0.65:
		return "eskorte"
	if r < 0.85:
		return "tip"
	return "intet"


func _on_net_started() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in _n.size():
		var t: Dictionary = _n[i]
		t["alive"] = true
		t["hp"] = HP
		t["escort"] = {}
		t["offer"] = _roll_offer(rng)
		(t["node"] as Node3D).position = t["start"]
		t["net_pos"] = t["start"]


# ---------------------------------------------------------------- forespørgsler

func positions_in(sys_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for t in _n:
		if t["alive"] and t["system"] == sys_id:
			out.append((t["node"] as Node3D).position)
	return out


## Nærmeste skib, man kan kalde op (lokalt), eller -1.
func nearest_hailable(pos: Vector3) -> int:
	var best := -1
	var bd := HAIL_RANGE
	for i in _n.size():
		var t: Dictionary = _n[i]
		if not t["alive"]:
			continue
		var d := pos.distance_to((t["node"] as Node3D).position)
		if d < bd:
			bd = d
			best = i
	return best


func name_of(i: int) -> String:
	return _n[i]["name"] if i >= 0 and i < _n.size() else ""


func house_of(i: int) -> String:
	return _n[i]["house"] if i >= 0 and i < _n.size() else ""


func position_of(i: int) -> Vector3:
	return (_n[i]["node"] as Node3D).position


func is_alive(i: int) -> bool:
	return i >= 0 and i < _n.size() and _n[i]["alive"]


# ---------------------------------------------------------------- opkald (værten svarer)

func request_hail(i: int) -> void:
	_srv_hail.rpc_id(1, i)


@rpc("any_peer", "call_local", "reliable")
func _srv_hail(i: int) -> void:
	if not multiplayer.is_server() or i < 0 or i >= _n.size() or not _n[i]["alive"]:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	var t: Dictionary = _n[i]
	var text := ""
	var opts: Array = []
	match str(t["offer"]):
		"handel":
			var g := _cheap_good(t)
			var price := _cheap_price(t, g)
			text = "Hej patrulje! Jeg har %s i overskud. Du kan få 4 stk. til %d cr stykket – det er under markedsprisen." % [Game.good_name(g).to_lower(), price]
			opts = [{"id": "buy", "label": "Køb 4 %s (%d cr)" % [Game.good_name(g).to_lower(), price * 4]}, {"id": "bye", "label": "Nej tak"}]
		"levering":
			var dest := _random_dest(t)
			text = "Godt du kom forbi! Jeg har en pakke, der skal til %s, men jeg skal den anden vej. Vil du tage den? Modtageren betaler %d cr." % [
				Game.locations[dest]["name"], _delivery_pay(t, dest)]
			opts = [{"id": "deliver:" + dest, "label": "Tag pakken med"}, {"id": "bye", "label": "Ikke nu"}]
		"eskorte":
			var dest := _random_dest(t)
			text = "Patrulje! Jeg skal til %s, og der er pirater på ruten. Vil du følge mig derhen? Jeg betaler %d cr." % [
				Game.locations[dest]["name"], _escort_pay(t, dest)]
			opts = [{"id": "escort:" + dest, "label": "Jeg følger dig"}, {"id": "bye", "label": "Beklager, jeg har travlt"}]
		"tip":
			var s := _tip_site(t)
			if s.is_empty():
				text = CHATTER.pick_random()
				opts = [{"id": "bye", "label": "Flyv sikkert"}]
			else:
				text = "Jeg så noget mærkeligt nede på %s: %s. Måske værd at kigge på?" % [W.universe.planet(s["planet"]).display_name, str(s["name"]).to_lower()]
				opts = [{"id": "tip:" + str(s["id"]), "label": "Sæt en markering"}, {"id": "bye", "label": "Tak for tippet"}]
		_:
			text = CHATTER.pick_random()
			opts = [{"id": "bye", "label": "Flyv sikkert"}]
	_cl_hail.rpc_id(who, i, t["name"], t["house"], text, opts)


@rpc("authority", "call_local", "reliable")
func _cl_hail(i: int, nm: String, house: String, text: String, opts: Array) -> void:
	hail_received.emit(i, nm, house, text, opts)


signal hail_received(i: int, name: String, house: String, text: String, options: Array)
signal hail_reply(text: String)


func request_choice(i: int, option: String) -> void:
	_srv_choice.rpc_id(1, i, option)


@rpc("any_peer", "call_local", "reliable")
func _srv_choice(i: int, option: String) -> void:
	if not multiplayer.is_server() or i < 0 or i >= _n.size() or not _n[i]["alive"]:
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	var t: Dictionary = _n[i]
	var reply := "Flyv sikkert!"
	if option == "buy" and t["offer"] == "handel":
		var g := _cheap_good(t)
		var price := _cheap_price(t, g)
		var p: Dictionary = Game.players[who]
		var room := int(p["cargo_max"]) - Game.cargo_total(p["cargo"])
		var n := mini(4, room)
		if n <= 0:
			reply = "Dit lastrum er fuldt, ven. Kom igen, når der er plads."
		elif int(p["credits"]) < price * n:
			reply = "Du har vist ikke råd i dag. Prisen er %d cr." % (price * n)
		else:
			p["credits"] = int(p["credits"]) - price * n
			p["cargo"][g] = int(p["cargo"].get(g, 0)) + n
			Game._send_wallet(who)
			t["offer"] = "intet"
			reply = "Handel! %d %s er lastet om bord. God fornøjelse." % [n, Game.good_name(g).to_lower()]
	elif option.begins_with("deliver:") and t["offer"] == "levering":
		var dest := option.trim_prefix("deliver:")
		if W.jobs.server_add(who, {"type": "levering", "to": dest, "reward": _delivery_pay(t, dest), "xp": 15,
				"from_name": t["name"], "time": 420.0}):
			t["offer"] = "intet"
			reply = "Tusind tak! Pakken er om bord. Land på %s for at aflevere den." % Game.locations[dest]["name"]
		else:
			reply = "Du har vist allerede nok at se til (højst %d opgaver)." % Jobs.MAX_JOBS
	elif option.begins_with("escort:") and t["offer"] == "eskorte":
		var dest := option.trim_prefix("escort:")
		var jid := W.jobs.server_add(who, {"type": "eskorte", "to": dest, "reward": _escort_pay(t, dest), "xp": 30,
			"from_name": t["name"], "npc": i, "time": 360.0})
		if jid:
			t["offer"] = "intet"
			t["escort"] = {"owner": who, "dest": dest, "ambushed": false, "job": W.jobs.last_id}
			reply = "Fint! Bliv tæt på mig. Vi flyver mod %s nu." % Game.locations[dest]["name"]
		else:
			reply = "Du har vist allerede nok at se til."
	elif option.begins_with("tip:"):
		var sid := option.trim_prefix("tip:")
		var s := W.sites.get_site(sid)
		if not s.is_empty():
			W.jobs.cl_tip.rpc_id(who, str(s["id"]))
			reply = "Jeg har sendt koordinaterne. Held og lykke derude!"
			t["offer"] = "intet"
	_cl_reply.rpc_id(who, reply)


@rpc("authority", "call_local", "reliable")
func _cl_reply(text: String) -> void:
	hail_reply.emit(text)


func _cheap_good(t: Dictionary) -> String:
	var goods := ["braendstof", "elektronik", "frugt", "malm"]
	return goods[(hash(t["name"]) & 0x7fffffff) % goods.size()]


func _cheap_price(t: Dictionary, g: String) -> int:
	var base := {"braendstof": 14, "elektronik": 40, "frugt": 30, "malm": 28}
	return int(round(float(base.get(g, 30)) * 0.7))


func _random_dest(t: Dictionary) -> String:
	var pts: Array = _points[t["system"]]
	var opts: Array = []
	var here := (t["node"] as Node3D).position
	for p: Dictionary in pts:
		if p["loc"] != "" and (p["pos"] as Vector3).distance_to(here) > 900.0:
			opts.append(p["loc"])
	if opts.is_empty():
		for p: Dictionary in pts:
			if p["loc"] != "":
				opts.append(p["loc"])
	return opts[(hash(t["name"]) & 0x7fffffff) % opts.size()]


func _delivery_pay(t: Dictionary, dest: String) -> int:
	var d := (t["node"] as Node3D).position.distance_to(Jobs.loc_pos(dest))
	return 60 + int(d / 40.0)


func _escort_pay(t: Dictionary, dest: String) -> int:
	return 120 + int((t["node"] as Node3D).position.distance_to(Jobs.loc_pos(dest)) / 25.0)


func _tip_site(t: Dictionary) -> Dictionary:
	var best := {}
	for s: Dictionary in W.sites.sites:
		if s["system"] == t["system"] and not s.get("looted", false) and str(s.get("mission", "")) == "":
			if best.is_empty() or (hash(t["name"] + str(s["id"])) & 0xff) > (hash(t["name"] + str(best["id"])) & 0xff):
				best = s
	return best


# ---------------------------------------------------------------- simulation (værten)

func _physics_process(delta: float) -> void:
	var server := W.is_server()
	var active_sys := {}
	for s in W.active_ships():
		active_sys[W.universe.system_at(s.position)] = true
	var me := W.local_ship
	for i in _n.size():
		var t: Dictionary = _n[i]
		var n: ShipModel = t["node"]
		var here: bool = active_sys.has(t["system"])
		n.visible = t["alive"] and here
		if me and is_instance_valid(me):
			(t["label"] as Label3D).visible = n.visible and me.position.distance_to(n.position) < 700.0
		if not t["alive"]:
			if server:
				t["respawn"] = float(t["respawn"]) - delta
				if t["respawn"] <= 0.0:
					_cl_alive.rpc(i, true)
			continue
		if server and here:
			_server_move(i, t, delta)
		elif not server:
			var k := 1.0 - exp(-delta * 10.0)
			if n.position.distance_to(t["net_pos"]) > 200.0:
				n.position = t["net_pos"]
			n.position = n.position.lerp(t["net_pos"], k)
			n.quaternion = n.quaternion.slerp(t["net_rot"], k)
		n.thrust = 0.9
	if server:
		_sync_t += delta
		if _sync_t >= SYNC_INTERVAL and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_sync_t = 0.0
			var pos := PackedVector3Array()
			var rot := PackedFloat32Array()
			for t in _n:
				var n: Node3D = t["node"]
				pos.append(n.position)
				var q := n.quaternion
				rot.append_array([q.x, q.y, q.z, q.w])
			_cl_state.rpc(pos, rot)


func _server_move(i: int, t: Dictionary, delta: float) -> void:
	var n: Node3D = t["node"]
	var pts: Array = _points[t["system"]]
	var goal: Vector3
	var esc: Dictionary = t["escort"]
	if not esc.is_empty():
		goal = Jobs.loc_pos(esc["dest"]) + (W.universe.pad_of(esc["dest"]).get("pad", {}).get("dir", Vector3.UP) as Vector3) * 40.0
	else:
		goal = pts[int(t["target"])]["pos"]
	var to := goal - n.position
	var d := to.length()
	if d < 40.0:
		if not esc.is_empty():
			W.jobs.server_escort_arrived(int(esc["job"]))
			t["escort"] = {}
		t["target"] = randi() % pts.size()
		return
	var dir := to / d
	# Undgå planeter og stationer
	var pl := W.universe.nearest_planet(n.position)
	if pl.ground_altitude(n.position) < 60.0 and esc.is_empty():
		dir = (n.position - pl.position).normalized()
	elif pl.ground_altitude(n.position) < 25.0:
		dir = (dir + (n.position - pl.position).normalized()).normalized()
	for st in W.universe.stations:
		if n.position.distance_to(st.position) < 60.0 and goal.distance_to(st.position) > 80.0:
			dir = (n.position - st.position).normalized()
	var want := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
	var ang := n.quaternion.angle_to(want)
	if ang > 0.0001:
		n.quaternion = n.quaternion.slerp(want, minf(1.0, 1.4 * delta / ang)).normalized()
	var spd := SPEED * (0.8 if not esc.is_empty() else 1.0)
	n.position += -n.global_basis.z * spd * delta
	# Baghold halvvejs på en eskorte
	if not esc.is_empty() and not esc["ambushed"] and d < float(esc.get("start_d", d + 1.0)) * 0.55:
		esc["ambushed"] = true
		var fwd := -n.global_basis.z
		for k in 2:
			var p := n.position + fwd * 300.0 + fwd.cross(Vector3.UP).normalized() * randf_range(-120, 120) + Vector3(0, randf_range(-30, 50), 0)
			W.pirates.server_spawn_at(t["system"], p, n.position, "job_esc_%d" % int(esc["job"]))
		Game.server_toast(int(esc["owner"]), "Baghold! Pirater forude – beskyt %s" % t["name"])
	if not esc.is_empty() and not esc.has("start_d"):
		esc["start_d"] = d


func server_clear_escort(job_id: int) -> void:
	for t in _n:
		if not (t["escort"] as Dictionary).is_empty() and int(t["escort"]["job"]) == job_id:
			t["escort"] = {}


## Server: mål for jobpirater (eskorteskibet).
func server_escort_target(tag: String) -> Dictionary:
	for t in _n:
		var esc: Dictionary = t["escort"]
		if t["alive"] and not esc.is_empty() and tag == "job_esc_%d" % int(esc["job"]):
			var n: Node3D = t["node"]
			return {"pos": n.position, "vel": -n.global_basis.z * SPEED * 0.8}
	return {}


## Server: rammer et piratskud et civilt skib?
func server_bolt_hit(p: Vector3, dmg: float) -> bool:
	for i in _n.size():
		var t: Dictionary = _n[i]
		if not t["alive"] or not (t["node"] as Node3D).visible:
			continue
		if p.distance_to((t["node"] as Node3D).position) < 6.0:
			t["hp"] = float(t["hp"]) - dmg
			if t["hp"] <= 0.0:
				var esc: Dictionary = t["escort"]
				if not esc.is_empty():
					W.jobs.server_fail(int(esc["job"]), "%s blev skudt ned." % t["name"])
				t["escort"] = {}
				_cl_alive.rpc(i, false)
				t["respawn"] = 90.0
				t["hp"] = HP
			return true
	return false


@rpc("authority", "call_local", "reliable")
func _cl_alive(i: int, alive: bool) -> void:
	var t: Dictionary = _n[i]
	var was: bool = t["alive"]
	t["alive"] = alive
	var n: Node3D = t["node"]
	if was and not alive:
		W.fx.explosion(n.position, true)
		Sfx.play_at("eksplosion_stor", n.position, 0.0)
	if alive and not was:
		var pts: Array = _points[t["system"]]
		n.position = pts[randi() % pts.size()]["pos"]
		t["net_pos"] = n.position


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_state(pos: PackedVector3Array, rot: PackedFloat32Array) -> void:
	for i in mini(pos.size(), _n.size()):
		_n[i]["net_pos"] = pos[i]
		_n[i]["net_rot"] = Quaternion(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])
