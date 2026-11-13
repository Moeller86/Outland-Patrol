class_name Missions
extends Node3D
## Concord Patrol-missioner. Værten styrer tavlen, den aktive mission, faserne,
## missionens pirater og eskorteskib, og udbetaler belønningen til hele gruppen.
## Klienterne får tilstanden løbende og tegner mål, markør, eskorte og debriefing.
##
## Missionstyper:
##  distress – Nødkald: nå frem i tide, ryd angriberne, eskortér fragtskibet til landing.
##  sweep    – Patruljesweep: flyv til navigationsbøjer, ryd bagholdet ved hver, meld tilbage.
##  search   – Eftersøgning: find et nedstyrtet fragtskib på en planet med scanneren,
##             land og bjærg den sorte boks, og bring den hjem gennem piraternes baghold.
##  assault  – Angreb: en piratfæstning i en kløft. Skyd luftskyts ned, bomb
##             kontroltårnene, så reaktorens skjold falder, bomb reaktoren og kom væk.

signal board_changed
signal state_changed
signal mission_started(name: String)
signal mission_ended(result: Dictionary)

const ESCORT_SPEED := 45.0
const ESCORT_HP := 200.0
## Fragtskibets skjold holder det meste af skaden, indtil hjælpen når frem
const ESCORT_ARMOR_WAITING := 0.2
const ESCORT_ARMOR_ESCORT := 0.55
const SYNC_INTERVAL := 0.25

var board: Array = []          ## Tilbud på tavlen (synkroniseret)
var active := false            ## Er en mission i gang (synkroniseret)
var client: Dictionary = {}    ## Den aktive missions tilstand, som HUD'en viser

var _m: Dictionary = {}        ## Kun på serveren: fuld missionstilstand
var _next_oid := 1
var _sync_t := 0.0
var _escort_node: Node3D
var _escort_label: Label3D
var _beacon: Node3D
var _beacon_light: MeshInstance3D


func _ready() -> void:
	_escort_node = W.freighters._build_model()
	_escort_node.visible = false
	add_child(_escort_node)
	_escort_label = Label3D.new()
	_escort_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_escort_label.fixed_size = true
	_escort_label.pixel_size = 0.0012
	_escort_label.font_size = 24
	_escort_label.outline_size = 6
	_escort_label.modulate = Color("6bdc4f")
	_escort_label.no_depth_test = true
	_escort_label.position = Vector3(0, 6, 0)
	_escort_node.add_child(_escort_label)
	_beacon = _build_beacon()
	_beacon.visible = false
	add_child(_beacon)
	Game.player_joined.connect(_on_player_joined)
	W.pirates.server_pirate_killed.connect(_on_pirate_killed)
	W.sites.server_site_found.connect(_on_site_found)
	W.sites.server_site_action.connect(_on_site_action)
	Net.started.connect(_on_net_started)


func _on_net_started() -> void:
	board = []
	active = false
	client = {}
	_m = {}
	_escort_node.visible = false
	_beacon.visible = false
	if W.is_server():
		_server_new_board()


# ---------------------------------------------------------------- forespørgsler fra UI

func request_accept(oid: int) -> void:
	_srv_accept.rpc_id(1, oid)


func request_abort() -> void:
	_srv_abort.rpc_id(1)


## Må den lokale spiller tage dette tilbud?
func can_accept(offer: Dictionary) -> bool:
	return not active and Game.rank_index(int(Game.wallet.get("xp", 0))) >= int(offer["min_rank"])


# ---------------------------------------------------------------- tavlen

func _server_new_board() -> void:
	var templates: Array = Game.mission_data["templates"].duplicate()
	templates.shuffle()
	# Sørg for, at mindst én let mission altid er med.
	templates.sort_custom(func(a, b): return int(a["min_rank"]) < int(b["min_rank"]))
	var picks: Array = [templates[0]]
	var rest := templates.slice(1)
	rest.shuffle()
	picks.append_array(rest.slice(0, 2))
	board = []
	for t: Dictionary in picks:
		board.append(_make_offer(t))
	_cl_board.rpc(board)


func _make_offer(t: Dictionary) -> Dictionary:
	var names: Array = Game.mission_data["freighter_names"]
	var ship_name: String = names.pick_random()
	var o := t.duplicate(true)
	o["oid"] = _next_oid
	_next_oid += 1
	o["ship"] = ship_name
	var sys_name: String = Game.systems[t["system"]]["name"]
	var to_name := ""
	if t.has("to"):
		to_name = Game.locations[t["to"]]["name"]
	var ret_name := ""
	if t.has("return"):
		ret_name = Game.locations[t["return"]]["name"]
	o["brief"] = str(t["brief"]).format({"ship": ship_name, "to": to_name, "system": sys_name, "return": ret_name})
	return o


@rpc("authority", "call_local", "reliable")
func _cl_board(b: Array) -> void:
	board = b
	board_changed.emit()


# ---------------------------------------------------------------- start og slut (server)

@rpc("any_peer", "call_local", "reliable")
func _srv_accept(oid: int) -> void:
	if not multiplayer.is_server() or active:
		return
	var who := _sender()
	var offer := {}
	for o: Dictionary in board:
		if int(o["oid"]) == oid:
			offer = o
	if offer.is_empty() or not Game.players.has(who):
		return
	if Game.rank_index(int(Game.players[who]["xp"])) < int(offer["min_rank"]):
		Game.server_toast(who, "Din rang er for lav til denne mission")
		return
	_server_start(offer)


@rpc("any_peer", "call_local", "reliable")
func _srv_abort() -> void:
	if multiplayer.is_server() and active:
		_server_end(false, "Missionen blev afbrudt.")


func _server_start(offer: Dictionary) -> void:
	var tag := "m%d" % int(offer["oid"])
	var crew := maxi(1, Game.players.size())
	_m = {"offer": offer, "tag": tag, "type": offer["type"], "system": offer["system"], "phase": "",
		"timer": -1.0, "target": Vector3.ZERO, "has_target": false, "kills": 0, "crew": crew,
		"objective": "", "progress": "", "escort": {}, "started": Time.get_ticks_msec()}
	active = true
	match offer["type"]:
		"distress": _distress_start()
		"sweep": _sweep_start()
		"search": _search_start()
		"assault": _assault_start()
	_cl_started.rpc(offer["name"], offer["brief"])
	_server_sync(true)


func _server_end(success: bool, reason: String) -> void:
	if not active:
		return
	var offer: Dictionary = _m["offer"]
	var bonus := int(_m.get("bonus", 0))
	var credits := int(offer["reward"]) + bonus if success else 0
	var xp := int(offer["xp"]) if success else int(int(offer["xp"]) / 4)
	var minutes := (Time.get_ticks_msec() - int(_m["started"])) / 60000.0
	var unlocked := Game.server_mission_completed() if success else ""
	for id: int in Game.players:
		var before := int(Game.players[id]["xp"])
		Game.server_reward(id, credits, xp)
		var result := {"success": success, "name": offer["name"], "reason": reason, "credits": credits, "xp": xp,
			"kills": int(_m["kills"]), "minutes": minutes, "xp_before": before, "xp_after": before + xp,
			"unlocked": unlocked, "base_level": Game.base_level()}
		_cl_ended.rpc_id(id, result)
	W.pirates.server_despawn_tag(_m["tag"])
	if _m.has("site"):
		W.sites.server_remove_mission_site(_m["site"])
	if _m.get("type", "") == "assault":
		W.assault.server_clear()
	active = false
	_m = {}
	_cl_state.rpc({"active": false})
	_server_new_board()
	Game.server_save()


@rpc("authority", "call_local", "reliable")
func _cl_started(mission_name: String, _brief: String) -> void:
	active = true
	mission_started.emit(mission_name)


@rpc("authority", "call_local", "reliable")
func _cl_ended(result: Dictionary) -> void:
	mission_ended.emit(result)


# ---------------------------------------------------------------- Nødkald

func _distress_start() -> void:
	var o: Dictionary = _m["offer"]
	var st := W.universe.station(o["from"])
	var pl := W.universe.planet(o["to"])
	var approach := pl.pad_top + pl.pad_dir * 220.0
	var dest := pl.pad_top + pl.pad_dir * 3.0 - pl.tangent * 16.0
	# Nødkaldet kommer et stykke ude på ruten, så man kan nå derud i tide
	var mid := st.dock_pos.lerp(approach, 0.3)
	var side := (approach - st.dock_pos).cross(Vector3.UP).normalized()
	var start := mid + side * 140.0 + Vector3(0, 40, 0)
	_m["escort"] = {"pos": start, "rot": Basis.looking_at((approach - start).normalized(), Vector3.UP).get_rotation_quaternion(),
		"hp": ESCORT_HP, "max": ESCORT_HP, "path": [approach, dest], "idx": 0, "moving": false, "alive": true,
		"name": o["ship"], "start": start, "ambushed": false}
	var n := int(o["pirates"]) + int(_m["crew"]) - 1
	for k in n:
		var a := TAU * k / n
		var p := start + Vector3(cos(a) * 95.0, randf_range(-20, 20), sin(a) * 95.0)
		W.pirates.server_spawn_at(o["system"], p, start, _m["tag"])
	_m["phase"] = "reach"
	# Tid nok til at flyve derud (ca. 70 m/s med efterbrænder) plus lidt luft
	var far := 0.0
	for s in W.active_ships():
		far = maxf(far, s.position.distance_to(start))
	_m["timer"] = maxf(float(o["time"]), far / 70.0 + 45.0)
	_m["objective"] = "Nå frem til %s før det er for sent" % o["ship"]


func _distress_tick(delta: float) -> void:
	var o: Dictionary = _m["offer"]
	var esc: Dictionary = _m["escort"]
	var epos: Vector3 = esc["pos"]
	_m["target"] = epos
	_m["has_target"] = true
	match _m["phase"]:
		"reach":
			_m["timer"] -= delta
			_m["progress"] = "Pirater angriber: %d · %s %d %%" % [W.pirates.server_count_tag(_m["tag"]), esc["name"], int(100.0 * float(esc["hp"]) / float(esc["max"]))]
			for s in W.active_ships():
				if s.position.distance_to(epos) < 160.0:
					_m["phase"] = "fight"
					_m["timer"] = -1.0
					_m["objective"] = "Skyd piraterne ned, før de ødelægger %s" % o["ship"]
					_server_sync(true)
					break
			if _m["phase"] == "reach" and _m["timer"] <= 0.0:
				_escort_destroyed("I nåede ikke frem i tide. %s gik tabt." % o["ship"])
		"fight":
			var left := W.pirates.server_count_tag(_m["tag"])
			_m["progress"] = "Pirater tilbage: %d · %s %d %%" % [left, esc["name"], int(100.0 * float(esc["hp"]) / float(esc["max"]))]
			if left == 0:
				_m["phase"] = "escort"
				esc["moving"] = true
				_m["objective"] = "Eskortér %s til %s" % [o["ship"], Game.locations[o["to"]]["name"]]
				_server_sync(true)
		"escort":
			var path: Array = esc["path"]
			var target: Vector3 = path[esc["idx"]]
			var to := target - epos
			var d := to.length()
			var spd := ESCORT_SPEED if esc["idx"] == 0 else 14.0
			if d <= spd * delta:
				esc["pos"] = target
				esc["idx"] = int(esc["idx"]) + 1
				if esc["idx"] >= path.size():
					_server_end(true, "%s landede sikkert på %s." % [o["ship"], Game.locations[o["to"]]["name"]])
					return
			else:
				esc["pos"] = epos + to / d * spd * delta
				var want := Basis.looking_at(to / d, Vector3.UP if absf(to.y / d) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
				esc["rot"] = (esc["rot"] as Quaternion).slerp(want, minf(1.0, delta * 1.5))
			var total := (esc["start"] as Vector3).distance_to(path[0])
			var done := 1.0 - ((esc["pos"] as Vector3).distance_to(path[0]) / maxf(total, 1.0))
			_m["progress"] = ("Vej til landing: %d %%" % int(clampf(done, 0.0, 1.0) * 100.0) if esc["idx"] == 0 else "Lander …") + \
				" · skrog %d %%" % int(100.0 * float(esc["hp"]) / float(esc["max"]))
			if not esc["ambushed"] and done > 0.45:
				esc["ambushed"] = true
				var n := int(o["ambush"]) + int(_m["crew"]) - 1
				var ahead: Vector3 = (path[0] as Vector3)
				var dir := (ahead - (esc["pos"] as Vector3)).normalized()
				for k in n:
					var p := (esc["pos"] as Vector3) + dir * 260.0 + dir.cross(Vector3.UP).normalized() * randf_range(-120, 120) + Vector3(0, randf_range(-40, 60), 0)
					W.pirates.server_spawn_at(o["system"], p, esc["pos"], _m["tag"])
				for id: int in Game.players:
					Game.server_toast(id, "Baghold! %d pirater forude" % n)


func _escort_destroyed(reason: String) -> void:
	var esc: Dictionary = _m["escort"]
	esc["alive"] = false
	_cl_escort_boom.rpc(esc["pos"])
	_server_end(false, reason)


@rpc("authority", "call_local", "reliable")
func _cl_escort_boom(pos: Vector3) -> void:
	W.fx.explosion(pos, true)
	_escort_node.visible = false


## Server: rammer et piratskud missionens eskorteskib?
func server_bolt_hit(p: Vector3, dmg: float) -> bool:
	if not active or _m.get("type", "") != "distress":
		return false
	var esc: Dictionary = _m["escort"]
	if not esc.get("alive", false) or p.distance_to(esc["pos"]) > 6.5:
		return false
	var armor := ESCORT_ARMOR_WAITING if _m["phase"] == "reach" else ESCORT_ARMOR_ESCORT
	esc["hp"] -= dmg * armor
	if esc["hp"] <= 0.0:
		_escort_destroyed("%s blev skudt ned af piraterne." % esc["name"])
	return true


## Server: mål for missionspirater (eskorteskibet), hvis det findes.
func server_escort_target(tag: String, _from: Vector3) -> Dictionary:
	if not active or _m.get("tag", "") != tag or _m.get("type", "") != "distress":
		return {}
	var esc: Dictionary = _m["escort"]
	if not esc.get("alive", false):
		return {}
	var vel := Vector3.ZERO
	if esc["moving"]:
		vel = -(Basis(esc["rot"] as Quaternion)).z * ESCORT_SPEED
	return {"pos": esc["pos"], "vel": vel}


# ---------------------------------------------------------------- Patruljesweep

func _sweep_start() -> void:
	var o: Dictionary = _m["offer"]
	var origin: Vector3 = W.universe.origins[o["system"]]
	var pts: Array = []
	var tries := 0
	while pts.size() < int(o["points"]) and tries < 200:
		tries += 1
		var a := randf() * TAU
		var r := randf_range(450.0, 1100.0)
		var p := origin + Vector3(cos(a) * r, randf_range(-150, 150), sin(a) * r - 400.0)
		var ok := true
		for pl in W.universe.planets:
			if pl.altitude(p) < pl.atmo_top + 120.0:
				ok = false
		for st in W.universe.stations:
			if p.distance_to(st.position) < 250.0:
				ok = false
		for q: Vector3 in pts:
			if p.distance_to(q) < 350.0:
				ok = false
		if ok:
			pts.append(p)
	_m["points"] = pts
	_m["point"] = 0
	_m["return_pos"] = W.universe.body_position(o["return"])
	_sweep_nav()


func _sweep_nav() -> void:
	var n: int = _m["points"].size()
	_m["phase"] = "nav"
	_m["objective"] = "Flyv til navigationsbøje %d af %d" % [int(_m["point"]) + 1, n]
	_m["progress"] = ""
	_m["target"] = _m["points"][_m["point"]]
	_m["has_target"] = true


func _sweep_tick(_delta: float) -> void:
	var o: Dictionary = _m["offer"]
	match _m["phase"]:
		"nav":
			var wp: Vector3 = _m["target"]
			for s in W.active_ships():
				if s.position.distance_to(wp) < 80.0:
					var n := int(o["pirates"]) + int(_m["crew"]) - 1
					for k in n:
						var dir := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.4), randf_range(-1, 1)).normalized()
						W.pirates.server_spawn_at(o["system"], wp + dir * randf_range(240, 320), wp, _m["tag"])
					_m["phase"] = "clear"
					_m["objective"] = "Baghold ved bøje %d! Ryd piraterne" % (int(_m["point"]) + 1)
					_server_sync(true)
					break
		"clear":
			var left := W.pirates.server_count_tag(_m["tag"])
			_m["progress"] = "Pirater tilbage: %d" % left
			if left == 0:
				_m["point"] = int(_m["point"]) + 1
				if _m["point"] >= _m["points"].size():
					_m["phase"] = "return"
					_m["objective"] = "Meld tilbage ved %s" % Game.locations[o["return"]]["name"]
					_m["progress"] = "Alle bøjer tjekket"
					_m["target"] = _m["return_pos"]
				else:
					_sweep_nav()
				_server_sync(true)
		"return":
			for id: int in W.ships:
				var s: Ship = W.ships[id]
				if not is_instance_valid(s) or s.dead:
					continue
				if s.docked_at == o["return"] or s.position.distance_to(_m["return_pos"]) < 90.0:
					_server_end(true, "Patruljeruten i %s er sikret." % Game.systems[o["system"]]["name"])
					return


# ---------------------------------------------------------------- Eftersøgning

func _search_start() -> void:
	var o: Dictionary = _m["offer"]
	var pl := W.universe.planet(o["to"])
	var site_id := W.sites.server_add_mission_site(_m["tag"], o["to"], "Vraget af %s" % o["ship"])
	var s := W.sites.get_site(site_id)
	_m["site"] = site_id
	# Søgeområdet ligger et stykke fra vraget, så man skal scanne for at finde det præcist.
	var d: Vector3 = s["dir"]
	var t: Vector3 = s["tangent"]
	var off := (d + t * randf_range(-0.3, 0.3) + d.cross(t) * randf_range(-0.3, 0.3)).normalized()
	_m["area"] = pl.position + off * (pl.radius + 260.0)
	_m["return_pos"] = W.universe.body_position(o["return"])
	_m["phase"] = "search"
	_m["target"] = _m["area"]
	_m["has_target"] = true
	_m["objective"] = "Flyv til %s, og scan efter nødsignalet fra %s (C)" % [pl.display_name, o["ship"]]
	_m["progress"] = "Søgeområdet er markeret"


func _search_tick(_delta: float) -> void:
	var o: Dictionary = _m["offer"]
	var s := W.sites.get_site(_m["site"])
	if s.is_empty():
		return
	match _m["phase"]:
		"search":
			for sh in W.active_ships():
				if sh.position.distance_to(s["pos"]) < Sites.SEE_RANGE:
					_on_site_found(_m["site"])
					break
		"land":
			var left := W.pirates.server_count_tag(_m["tag"])
			_m["progress"] = "Pirater i området: %d" % left if left > 0 else "Området er sikret"
		"return":
			var left := W.pirates.server_count_tag(_m["tag"])
			_m["progress"] = "Sort boks om bord" + (" · pirater: %d" % left if left > 0 else "")
			for id: int in W.ships:
				var sh: Ship = W.ships[id]
				if not is_instance_valid(sh) or sh.dead:
					continue
				if sh.docked_at == o["return"] or sh.position.distance_to(_m["return_pos"]) < 90.0:
					_server_end(true, "Den sorte boks fra %s er afleveret. Nu kan Concord finde ud af, hvad der skete." % o["ship"])
					return


func _on_site_found(site_id: String) -> void:
	if not active or _m.get("type", "") != "search" or site_id != _m.get("site", "") or _m["phase"] != "search":
		return
	var o: Dictionary = _m["offer"]
	var s := W.sites.get_site(site_id)
	_m["phase"] = "land"
	_m["target"] = s["land"]
	_m["objective"] = "Land ved vraget af %s, og bjærg den sorte boks" % o["ship"]
	var n := int(o["pirates"]) + int(_m["crew"]) - 1
	var up: Vector3 = s["dir"]
	for k in n:
		var side := (s["tangent"] as Vector3).rotated(up, TAU * k / n)
		var p := (s["pos"] as Vector3) + up * randf_range(160.0, 220.0) + side * 180.0
		W.pirates.server_spawn_at(o["system"], p, s["pos"], _m["tag"])
	for id: int in Game.players:
		Game.server_toast(id, "Signal fundet! %d pirater har også opfanget det" % n)
	_server_sync(true)


func _on_site_action(site_id: String, _who: int) -> void:
	if not active or _m.get("type", "") != "search" or site_id != _m.get("site", ""):
		return
	if _m["phase"] == "return":
		return
	var o: Dictionary = _m["offer"]
	var s := W.sites.get_site(site_id)
	_m["phase"] = "return"
	_m["target"] = _m["return_pos"]
	_m["objective"] = "Bring den sorte boks hjem til %s" % Game.locations[o["return"]]["name"]
	# Baghold i kredsløb, når man letter
	var n := int(o["ambush"]) + int(_m["crew"]) - 1
	var up: Vector3 = s["dir"]
	for k in n:
		var side := (s["tangent"] as Vector3).rotated(up, TAU * k / n + 0.5)
		var p := (s["pos"] as Vector3) + up * randf_range(380.0, 460.0) + side * 220.0
		W.pirates.server_spawn_at(o["system"], p, s["pos"], _m["tag"])
	for id: int in Game.players:
		Game.server_toast(id, "Sort boks bjærget! Pirater venter i kredsløb")
	_server_sync(true)


# ---------------------------------------------------------------- Angreb på piratfæstning

func _assault_start() -> void:
	var o: Dictionary = _m["offer"]
	W.assault.server_setup(o["to"])
	W.bombs.cl_issue.rpc(Bombs.ISSUED)
	_m["phase"] = "approach"
	_m["target"] = W.assault.entry
	_m["has_target"] = true
	_m["bonus"] = 0
	_m["objective"] = "Flyv til %s – fæstningen ligger i kløften" % W.universe.planet(o["to"]).display_name
	_m["progress"] = "Bomber om bord: %d (B)" % Bombs.ISSUED


func _assault_tick(delta: float) -> void:
	var o: Dictionary = _m["offer"]
	var a := W.assault
	if not a.active():
		return
	match _m["phase"]:
		"approach":
			for s in W.active_ships():
				if s.position.distance_to(a.center) < 1300.0:
					_m["phase"] = "attack"
					_m["timer"] = float(o.get("time", 300))
					var n := int(o.get("defenders", 2)) + int(_m["crew"]) - 1
					for k in n:
						var side := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.4), randf_range(-1, 1)).normalized()
						W.pirates.server_spawn_at(o["system"], a.center + side * 260.0 + (a.center - a.planet.position).normalized() * 160.0, s.position, _m["tag"])
					for id: int in Game.players:
						Game.server_toast(id, "Luftskyts aktiveret! Flyv lavt nede i kløften")
					_server_sync(true)
					break
		"attack":
			_m["timer"] = float(_m["timer"]) - delta
			var towers := a.count("tower")
			var flak_dead := a.count("flak", false)
			var tanks_dead := a.count("tank", false)
			_m["bonus"] = flak_dead * 20 + tanks_dead * 10
			_m["progress"] = "Tårne %d/%d · Luftskyts %d/%d · Bonus +%d cr" % [a.total("tower") - towers, a.total("tower"),
				flak_dead, a.total("flak"), int(_m["bonus"])]
			if towers > 0:
				_m["objective"] = "Bomb kontroltårnene (B) – de holder reaktorens skjold oppe"
				_m["target"] = _nearest_target("tower")
			else:
				_m["objective"] = "Skjoldet er nede! Bomb reaktoren for enden af kløften"
				_m["target"] = a.targets[a.reactor_idx]["pos"]
			if not a.targets[a.reactor_idx]["alive"]:
				_m["phase"] = "escape"
				_m["timer"] = 30.0
				_m["objective"] = "Reaktoren går kritisk – kom væk! Over 600 m eller 1,6 km væk"
				_m["target"] = a.planet.position + (a.center - a.planet.position).normalized() * (a.planet.radius + 900.0)
				for k in 3:
					var side := Vector3(randf_range(-1, 1), randf_range(0.1, 0.5), randf_range(-1, 1)).normalized()
					W.pirates.server_spawn_at(o["system"], a.center + side * 420.0, a.center, _m["tag"])
				for id: int in Game.players:
					Game.server_toast(id, "Reaktoren er ramt! Kom væk – NU!")
				_server_sync(true)
			elif _m["timer"] <= 0.0:
				_server_end(false, "Piraterne fik forstærkninger, før fæstningen faldt.")
		"escape":
			_m["timer"] = float(_m["timer"]) - delta
			var rpos: Vector3 = a.targets[a.reactor_idx]["pos"]
			# Små eksplosioner i kløften, mens reaktoren nedsmelter
			if randf() < delta * 2.5:
				var t: Dictionary = a.targets.pick_random()
				W.bombs.cl_boom.rpc(0, (t["pos"] as Vector3) + (t["up"] as Vector3) * randf_range(2, 20), 0.7)
			var all_out := true
			var any := false
			for s in W.active_ships():
				any = true
				if a.planet.ground_altitude(s.position) < 600.0 and s.position.distance_to(rpos) < 1600.0:
					all_out = false
			if any and all_out:
				_reactor_blast(rpos, a)
				_server_end(true, _assault_result(o, a, "Fæstningen i %s er udslettet. Alle kom væk i tide." % a.planet.display_name))
			elif _m["timer"] <= 0.0:
				_reactor_blast(rpos, a)
				_server_end(true, _assault_result(o, a, "Fæstningen i %s er udslettet – men det var tæt på!" % a.planet.display_name))


func _reactor_blast(rpos: Vector3, a: Assault) -> void:
	var up := (rpos - a.planet.position).normalized()
	W.bombs.cl_boom.rpc(0, rpos + up * 20.0, 3.5)
	a.cl_shock.rpc(rpos, 700.0, 120.0)


func _assault_result(o: Dictionary, a: Assault, text: String) -> String:
	return "%s Bonus: %d luftskyts og %d tanke = +%d cr." % [text, a.count("flak", false), a.count("tank", false), int(_m["bonus"])]


func _nearest_target(kind: String) -> Vector3:
	var a := W.assault
	var from := a.entry
	var ships := W.active_ships()
	if not ships.is_empty():
		from = ships[0].position
	var best := a.center
	var bd := INF
	for t in a.targets:
		if t["kind"] == kind and t["alive"]:
			var d := from.distance_to(t["pos"])
			if d < bd:
				bd = d
				best = (t["pos"] as Vector3) + (t["up"] as Vector3) * Assault.TOWER_H
	return best


# ---------------------------------------------------------------- løkke og synk

func _physics_process(delta: float) -> void:
	if W.is_server() and active:
		match _m.get("type", ""):
			"distress": _distress_tick(delta)
			"sweep": _sweep_tick(delta)
			"search": _search_tick(delta)
			"assault": _assault_tick(delta)
		_sync_t += delta
		if active and _sync_t >= SYNC_INTERVAL:
			_sync_t = 0.0
			_server_sync(false)
	_update_visuals(delta)


func _server_sync(reliable: bool) -> void:
	if not active:
		return
	var st := {"active": true, "name": _m["offer"]["name"], "type": _m["type"], "system": _m["system"],
		"objective": _m["objective"], "progress": _m["progress"], "timer": _m["timer"],
		"has_target": _m["has_target"], "target": _m["target"]}
	var esc: Dictionary = _m.get("escort", {})
	if not esc.is_empty():
		st["escort"] = {"pos": esc["pos"], "rot": esc["rot"], "hp": esc["hp"], "max": esc["max"],
			"alive": esc["alive"], "name": esc["name"]}
	if reliable:
		_cl_state.rpc(st)
	else:
		_cl_state_fast.rpc(st)


@rpc("authority", "call_local", "reliable")
func _cl_state(st: Dictionary) -> void:
	client = st
	active = st.get("active", false)
	state_changed.emit()


@rpc("authority", "call_local", "unreliable_ordered")
func _cl_state_fast(st: Dictionary) -> void:
	_cl_state(st)


func _update_visuals(delta: float) -> void:
	var esc: Dictionary = client.get("escort", {})
	var show_escort: bool = active and not esc.is_empty() and esc.get("alive", false)
	_escort_node.visible = show_escort
	if show_escort:
		var target: Vector3 = esc["pos"]
		if _escort_node.position.distance_to(target) > 50.0:
			_escort_node.position = target
		_escort_node.position = _escort_node.position.lerp(target, minf(1.0, delta * 8.0))
		_escort_node.quaternion = _escort_node.quaternion.slerp(esc["rot"], minf(1.0, delta * 6.0))
		_escort_label.text = "%s  %d%%" % [esc["name"], int(100.0 * float(esc["hp"]) / float(esc["max"]))]
	var show_beacon: bool = active and client.get("type", "") == "sweep" and client.get("has_target", false)
	_beacon.visible = show_beacon
	if show_beacon:
		_beacon.position = client["target"]
		_beacon_light.visible = (Time.get_ticks_msec() / 400) % 2 == 0


# ---------------------------------------------------------------- hjælpere

func _on_pirate_killed(_i: int, tag: String) -> void:
	if active and tag == _m.get("tag", "-"):
		_m["kills"] = int(_m["kills"]) + 1


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	_cl_board.rpc_id(id, board)
	if active:
		_server_sync(true)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _build_beacon() -> Node3D:
	var g := Node3D.new()
	var mast := MeshInstance3D.new()
	mast.mesh = ShipModel._cyl(0.6, 1.2, 14.0, 6)
	mast.material_override = ShipModel._mat(Color("5a5f8a"))
	g.add_child(mast)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 3.0
	t.outer_radius = 4.0
	t.rings = 10
	t.ring_segments = 4
	ring.mesh = t
	ring.material_override = ShipModel._unshaded(Color("6bdc4f"))
	ring.position = Vector3(0, 2, 0)
	g.add_child(ring)
	_beacon_light = MeshInstance3D.new()
	_beacon_light.mesh = ShipModel._box(1.6, 1.6, 1.6)
	_beacon_light.material_override = ShipModel._unshaded(Color("6bdc4f"))
	_beacon_light.position = Vector3(0, 8, 0)
	g.add_child(_beacon_light)
	return g
