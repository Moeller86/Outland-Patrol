class_name Jobs
extends Node3D
## Sideopgaver til free roam (ved siden af Concords missioner): fra opslagstavlen i
## byer, udposter og på stationer, eller fra skibe man kalder op.
##   levering  – bring en pakke til et andet sted (land der)
##   fragt     – bring N stk. af en vare til et sted (fra eget lastrum)
##   jagt      – pirater er set et sted i systemet: skyd dem ned
##   bjaergning – et vrag i rummet: saml vragdelene op (lastrum)
##   eskorte   – følg et civilt skib til dets mål (fra et opkald)
## Hver pilot kan have MAX_JOBS opgaver ad gangen. Værten ejer dem; de gemmes ikke.

signal jobs_changed

const K = preload("res://scripts/world/model_kit.gd")

const MAX_JOBS := 3
const BOARD_SIZE := 3
const BOARD_REFRESH := 300.0

var mine: Array = []              ## klient: egne opgaver (offentlige felter)
var board_cache: Dictionary = {}  ## klient: loc -> Array (sidst modtagne opslagstavle)
var last_id := 0
var _jobs: Dictionary = {}        ## server: id -> job
var _boards: Dictionary = {}      ## server: loc -> {t, offers}
var _wrecks: Dictionary = {}      ## id -> Node3D (vrag i rummet)
var _next := 1
var _tick := 0.0


func _ready() -> void:
	Net.started.connect(func() -> void:
		for id: int in _jobs.keys():
			_drop(id)
		_jobs.clear()
		_boards.clear()
		mine.clear()
		jobs_changed.emit())


static func loc_pos(loc_id: String) -> Vector3:
	var po := W.universe.pad_of(loc_id)
	if not po.is_empty():
		return po["pad"]["top"]
	var st := W.universe.station(loc_id)
	if st:
		return st.dock_pos
	return Vector3.ZERO


static func loc_name(loc_id: String) -> String:
	return str(Game.locations.get(loc_id, {}).get("name", loc_id))


# ---------------------------------------------------------------- opslagstavlen

func request_board(loc_id: String) -> void:
	_srv_board.rpc_id(1, loc_id)


@rpc("any_peer", "call_local", "reliable")
func _srv_board(loc_id: String) -> void:
	if not multiplayer.is_server() or not Game.locations.has(loc_id):
		return
	var who := _sender()
	_cl_board.rpc_id(who, loc_id, _board(loc_id))


@rpc("authority", "call_local", "reliable")
func _cl_board(loc_id: String, offers: Array) -> void:
	board_cache[loc_id] = offers
	jobs_changed.emit()


func _board(loc_id: String) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var b: Dictionary = _boards.get(loc_id, {})
	if b.is_empty() or now - float(b["t"]) > BOARD_REFRESH:
		var offers: Array = []
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for k in BOARD_SIZE:
			var o := _make_offer(loc_id, rng)
			if not o.is_empty():
				o["oid"] = "%s_%d" % [loc_id, _next]
				_next += 1
				offers.append(o)
		b = {"t": now, "offers": offers}
		_boards[loc_id] = b
	return b["offers"]


func _make_offer(loc_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var sys: String = Game.locations[loc_id]["system"]
	var here := loc_pos(loc_id)
	var dests: Array = []
	for id: String in Game.locations:
		var l: Dictionary = Game.locations[id]
		if id != loc_id and l.get("system", "") == sys and l.get("kind", "") in ["planet", "outpost", "station"] and not W.bases.is_plot(id):
			dests.append(id)
	var kinds := ["levering", "fragt", "jagt", "bjaergning"]
	var kind: String = kinds[rng.randi() % kinds.size()]
	match kind:
		"levering":
			if dests.is_empty():
				return {}
			var to: String = dests[rng.randi() % dests.size()]
			var d := here.distance_to(loc_pos(to))
			return {"type": "levering", "to": to, "reward": 70 + int(d / 35.0), "xp": 15, "time": 480.0,
				"title": "Levering til %s" % loc_name(to), "desc": "En forseglet pakke skal til %s. Land der for at aflevere den." % loc_name(to)}
		"fragt":
			if dests.is_empty():
				return {}
			var to: String = dests[rng.randi() % dests.size()]
			var goods := ["malm", "frugt", "elektronik", "braendstof"]
			var g: String = goods[rng.randi() % goods.size()]
			var n := rng.randi_range(3, 6)
			var base := {"malm": 30, "frugt": 34, "elektronik": 40, "braendstof": 15}
			return {"type": "fragt", "to": to, "good": g, "n": n, "reward": int(n * float(base[g]) * 1.7) + 40, "xp": 20, "time": 600.0,
				"title": "Fragt: %d %s til %s" % [n, Game.good_name(g).to_lower(), loc_name(to)],
				"desc": "Køb %d %s, og bring dem til %s. Betalingen dækker varerne og lidt til." % [n, Game.good_name(g).to_lower(), loc_name(to)]}
		"jagt":
			var p := _spot(sys, here, rng)
			return {"type": "jagt", "pos": p, "n": rng.randi_range(2, 3), "reward": 160 + rng.randi_range(0, 80), "xp": 35, "time": 420.0,
				"title": "Piratjagt i %s" % Game.systems[sys]["name"],
				"desc": "En lille piratgruppe er set i nærheden. Find dem på markeringen, og skyd dem ned."}
		"bjaergning":
			var p := _spot(sys, here, rng)
			var n := rng.randi_range(4, 6)
			return {"type": "bjaergning", "pos": p, "n": n, "reward": 40 * n + 60, "xp": 25, "time": 480.0,
				"title": "Bjærgning af et vrag", "desc": "Et fragtskib er forulykket. Flyv derud, og saml %d vragdele op med lastrummet." % n}
	return {}


## Et frit sted i rummet 1–2,5 km fra `here`, væk fra planeter.
func _spot(sys: String, here: Vector3, rng: RandomNumberGenerator) -> Vector3:
	for k in 20:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		var p := here + dir * rng.randf_range(1000.0, 2500.0)
		var pl := W.universe.nearest_planet(p)
		if pl.altitude(p) > pl.atmo_top * 1.5 and W.universe.system_at(p) == sys:
			return p
	return here + Vector3(0, 600, 0)


func request_accept(loc_id: String, oid: String) -> void:
	_srv_accept.rpc_id(1, loc_id, oid)


@rpc("any_peer", "call_local", "reliable")
func _srv_accept(loc_id: String, oid: String) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender()
	var b: Dictionary = _boards.get(loc_id, {})
	var offers: Array = b.get("offers", [])
	for o: Dictionary in offers:
		if o["oid"] == oid:
			var job := o.duplicate(true)
			job["from_name"] = loc_name(loc_id)
			job["system"] = Game.locations[loc_id]["system"]
			if server_add(who, job):
				offers.erase(o)
				_cl_board.rpc_id(who, loc_id, offers)
			else:
				Game.server_toast(who, "Du har allerede %d opgaver – gør en færdig først" % MAX_JOBS)
			return


# ---------------------------------------------------------------- server: opgaver

func server_add(who: int, job: Dictionary) -> bool:
	var n := 0
	for j: Dictionary in _jobs.values():
		if j["owner"] == who:
			n += 1
	if n >= MAX_JOBS:
		return false
	var id := _next
	_next += 1
	last_id = id
	job["id"] = id
	job["owner"] = who
	job["time_left"] = float(job.get("time", 480.0))
	if not job.has("title"):
		match str(job["type"]):
			"levering": job["title"] = "Levering til %s" % loc_name(job["to"])
			"eskorte": job["title"] = "Eskortér %s til %s" % [job.get("from_name", "skibet"), loc_name(job["to"])]
	if not job.has("system"):
		job["system"] = Game.locations.get(job.get("to", ""), {}).get("system", "")
	match str(job["type"]):
		"jagt":
			job["tag"] = "job_%d" % id
			var look: Vector3 = job["pos"]
			for k in int(job["n"]):
				var p: Vector3 = (job["pos"] as Vector3) + Vector3(randf_range(-80, 80), randf_range(-30, 30), randf_range(-80, 80))
				W.pirates.server_spawn_at(job["system"], p, look, job["tag"])
		"bjaergning":
			job["good"] = "vragdel"
			job["have0"] = int(Game.players[who]["cargo"].get("vragdel", 0))
			_cl_wreck.rpc(id, job["pos"])
			W.pickups.server_spawn("vragdel", job["pos"], int(job["n"]) + 1)
	_jobs[id] = job
	Game.server_toast(who, "Ny opgave: %s" % job["title"])
	_send(who)
	return true


func server_fail(id: int, reason: String) -> void:
	if not _jobs.has(id):
		return
	var j: Dictionary = _jobs[id]
	Game.server_toast(int(j["owner"]), "Opgave mislykkedes: %s" % reason)
	_drop(id)
	_send(int(j["owner"]))


func _complete(id: int, note := "") -> void:
	var j: Dictionary = _jobs[id]
	var who := int(j["owner"])
	Game.server_reward(who, int(j["reward"]), int(j.get("xp", 0)))
	Game.server_toast(who, "Opgave fuldført: %s · +%d cr%s" % [j["title"], int(j["reward"]), note])
	_drop(id)
	_send(who)
	_cl_done.rpc_id(who)


@rpc("authority", "call_local", "reliable")
func _cl_done() -> void:
	Sfx.play("mission_ok", -6.0, 0.0)


func _drop(id: int) -> void:
	if not _jobs.has(id):
		return
	var j: Dictionary = _jobs[id]
	if j.has("tag"):
		W.pirates.server_despawn_tag(j["tag"])
	if j["type"] == "eskorte":
		W.pirates.server_despawn_tag("job_esc_%d" % id)
		W.traffic.server_clear_escort(id)
	if j["type"] == "bjaergning":
		_cl_wreck_remove.rpc(id)
	_jobs.erase(id)


func server_escort_arrived(id: int) -> void:
	if not _jobs.has(id):
		return
	var j: Dictionary = _jobs[id]
	var s: Ship = W.ships.get(int(j["owner"]))
	var npc_pos := W.traffic.position_of(int(j["npc"]))
	if s and is_instance_valid(s) and s.position.distance_to(npc_pos) < 1200.0:
		_complete(id, " – tak for følgeskabet!")
	else:
		server_fail(id, "du var ikke i nærheden, da skibet nåede frem.")


## Klient landede et sted: aflever leveringer og fragt.
func request_landed(loc_id: String) -> void:
	_srv_landed.rpc_id(1, loc_id)


@rpc("any_peer", "call_local", "reliable")
func _srv_landed(loc_id: String) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender()
	for id: int in _jobs.keys():
		var j: Dictionary = _jobs[id]
		if j["owner"] != who or j.get("to", "") != loc_id:
			continue
		if j["type"] == "levering":
			_complete(id)
		elif j["type"] == "fragt":
			var p: Dictionary = Game.players[who]
			var have := int(p["cargo"].get(j["good"], 0))
			if have >= int(j["n"]):
				p["cargo"][j["good"]] = have - int(j["n"])
				if int(p["cargo"][j["good"]]) <= 0:
					p["cargo"].erase(j["good"])
				Game._send_wallet(who)
				_complete(id)
			else:
				Game.server_toast(who, "Fragt til %s: du mangler %d %s" % [loc_name(loc_id), int(j["n"]) - have, Game.good_name(j["good"]).to_lower()])


func request_abandon(id: int) -> void:
	_srv_abandon.rpc_id(1, id)


@rpc("any_peer", "call_local", "reliable")
func _srv_abandon(id: int) -> void:
	if not multiplayer.is_server() or not _jobs.has(id) or _jobs[id]["owner"] != _sender():
		return
	var who := _sender()
	Game.server_toast(who, "Opgave opgivet: %s" % _jobs[id]["title"])
	_drop(id)
	_send(who)


func _physics_process(delta: float) -> void:
	for j: Dictionary in mine:
		j["time_left"] = maxf(0.0, float(j["time_left"]) - delta)
	if not W.is_server():
		return
	_tick += delta
	if _tick < 0.5:
		return
	var dt := _tick
	_tick = 0.0
	for id: int in _jobs.keys():
		if not _jobs.has(id):
			continue
		var j: Dictionary = _jobs[id]
		j["time_left"] = float(j["time_left"]) - dt
		match str(j["type"]):
			"jagt":
				if W.pirates.server_count_tag(j["tag"]) == 0:
					_complete(id)
					continue
			"bjaergning":
				var p: Dictionary = Game.players.get(int(j["owner"]), {})
				if not p.is_empty() and int(p["cargo"].get("vragdel", 0)) - int(j["have0"]) >= int(j["n"]):
					p["cargo"]["vragdel"] = int(p["cargo"]["vragdel"]) - int(j["n"])
					if int(p["cargo"]["vragdel"]) <= 0:
						p["cargo"].erase("vragdel")
					Game._send_wallet(int(j["owner"]))
					_complete(id)
					continue
		if float(j["time_left"]) <= 0.0:
			server_fail(id, "tiden løb ud.")


func _send(who: int) -> void:
	var out: Array = []
	for j: Dictionary in _jobs.values():
		if j["owner"] == who:
			var pub := {"id": j["id"], "type": j["type"], "title": j["title"], "reward": j["reward"],
				"time_left": j["time_left"], "system": j.get("system", "")}
			if j.has("to"):
				pub["to"] = j["to"]
			if j.has("pos"):
				pub["pos"] = j["pos"]
			if j.has("npc"):
				pub["npc"] = j["npc"]
			if j.has("good"):
				pub["good"] = j["good"]
				pub["n"] = j["n"]
			out.append(pub)
	_cl_jobs.rpc_id(who, out)


@rpc("authority", "call_local", "reliable")
func _cl_jobs(list: Array) -> void:
	mine = list
	jobs_changed.emit()


## Hvor skal man hen for en opgave? (til HUD-markører)
func target_of(j: Dictionary) -> Vector3:
	match str(j["type"]):
		"levering", "fragt":
			return loc_pos(j["to"])
		"eskorte":
			if j.has("npc") and W.traffic.is_alive(int(j["npc"])):
				return W.traffic.position_of(int(j["npc"]))
			return loc_pos(j["to"])
		_:
			return j.get("pos", Vector3.ZERO)


# ---------------------------------------------------------------- vrag i rummet og tips

@rpc("authority", "call_local", "reliable")
func _cl_wreck(id: int, pos: Vector3) -> void:
	var g := Node3D.new()
	g.position = pos
	g.rotation = Vector3(0.4, randf() * TAU, 0.7)
	add_child(g)
	var hull := K.hull(Color("6a6f8a"), K.TEX_PLATING, 0.4)
	var dark := K.flat(Color("23203a"))
	K.add(g, K.box(4.0, 3.0, 9.0), hull, Vector3.ZERO)
	K.add(g, K.box(4.2, 0.5, 3.0), K.stripes(0.5), Vector3(0, 1.6, -2.0))
	var half := K.add(g, K.box(4.0, 3.0, 5.0), hull, Vector3(1.5, -2.0, 7.5))
	half.rotation = Vector3(0.6, 0.4, 0.3)
	K.add(g, K.cyl(0.8, 1.0, 2.0, 8), dark, Vector3(0, 0, 5.2), Vector3(PI / 2, 0, 0))
	for k in 5:
		var b := K.add(g, K.box(randf_range(0.6, 1.6), randf_range(0.3, 1.0), randf_range(0.8, 2.0)), hull,
			Vector3(randf_range(-8, 8), randf_range(-5, 5), randf_range(-8, 8)))
		b.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	var blink := K.add(g, K.box(0.5, 0.5, 0.5), K.glow(Color("ff3b3b")), Vector3(0, 1.8, 3.0))
	blink.set_meta("blink", true)
	_wrecks[id] = g


@rpc("authority", "call_local", "reliable")
func _cl_wreck_remove(id: int) -> void:
	if _wrecks.has(id):
		(_wrecks[id] as Node3D).queue_free()
		_wrecks.erase(id)


## Et tip fra et opkald: fundet sættes på kortet og markeres.
@rpc("authority", "call_local", "reliable")
func cl_tip(site_id: String) -> void:
	var s := W.sites.get_site(site_id)
	if s.is_empty():
		return
	W.sites._discover(s)
	W.waypoint = {"pos": s["pos"], "label": str(s["name"]).to_upper(), "system": s["system"]}
	Game.toast.emit("Markering sat: %s" % s["name"])


func _process(_delta: float) -> void:
	var on := (Time.get_ticks_msec() / 400) % 2 == 0
	for g: Node3D in _wrecks.values():
		for c in g.get_children():
			if c.has_meta("blink"):
				(c as Node3D).visible = on


func _sender() -> int:
	var who := multiplayer.get_remote_sender_id()
	return multiplayer.get_unique_id() if who == 0 else who
