extends Node
## Co-op-test med to processer. Start værten først, derefter klienten:
##   godot --headless --path . res://tests/net_test.tscn -- host
##   godot --headless --path . res://tests/net_test.tscn -- client
## Klienten handler på stationen, og begge sider tjekker at markedet,
## tegnebogen og skibspositionerne er synkroniseret.

const PORT := 7788
var main: Node
var failures := 0


func _ready() -> void:
	var role0 := "host" if "host" in OS.get_cmdline_user_args() else "client"
	Game.save_path = "user://test_%s_%s.json" % ["net", role0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	var role := "host" if "host" in OS.get_cmdline_user_args() else "client"
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false   # denne test starter i rummet
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await _frames(5)
	if role == "host":
		await _host()
	else:
		await _client()
	_finish(role)


func _host() -> void:
	_check(Net.host("Vært", PORT), "server startet")
	var t := 0.0
	while main.ships.size() < 2 and t < 15.0:
		await _seconds(0.2)
		t += 0.2
	_check(main.ships.size() == 2, "klienten joinede (%d skibe)" % main.ships.size())
	# Vent på at klienten handler, og at dens skib bevæger sig.
	var start_pos := Vector3.ZERO
	for id: int in main.ships:
		if id != 1:
			start_pos = main.ships[id].position
	await _seconds(4.0)
	var moved := false
	for id: int in main.ships:
		if id != 1:
			moved = main.ships[id].position.distance_to(start_pos) > 5.0
	_check(moved, "klientens skib bevæger sig hos værten")
	_check(Game.markets["kepler_station"]["elektronik"]["price"] > 40.0, "klientens køb ændrede værtens marked")
	var client_id := -1
	for id: int in Game.players:
		if id != 1:
			client_id = id
	_check(client_id != -1 and int(Game.players[client_id]["cargo"].get("elektronik", 0)) == 2, "værten har klientens last registreret")
	# Send en pirat efter klienten. Klienten skyder den ned.
	W.pirates._server_spawn("kepler", main.ships[client_id].position)
	var t2 := 0.0
	while int(Game.players[client_id]["kills"]) == 0 and t2 < 8.0:
		await _seconds(0.2)
		t2 += 0.2
	_check(int(Game.players[client_id]["kills"]) == 1, "klienten fik dusøren hos værten")
	await _seconds(1.5)
	_check(not W.asteroids._rocks[0]["alive"], "klientens skud sprængte asteroiden hos værten")
	# Klienten tager en mission fra tavlen og afbryder den igen.
	var got := []
	W.missions.mission_ended.connect(func(r: Dictionary): got.append(r))
	var t3 := 0.0
	while not W.missions.active and t3 < 8.0:
		await _seconds(0.2)
		t3 += 0.2
	_check(W.missions.active, "klientens mission kører hos værten")
	t3 = 0.0
	while W.missions.active and t3 < 8.0:
		await _seconds(0.2)
		t3 += 0.2
	_check(not W.missions.active and got.size() == 1, "værten fik debriefing, da missionen blev afbrudt")
	await _seconds(1.0)


func _client() -> void:
	await _seconds(1.0)
	_check(Net.join("Klient", "127.0.0.1", PORT), "forbinder")
	var t := 0.0
	while main.local_ship == null and t < 10.0:
		await _seconds(0.2)
		t += 0.2
	_check(main.local_ship != null, "eget skib spawnet")
	await _seconds(0.5)
	_check(main.ships.size() == 2, "ser værtens skib (%d skibe)" % main.ships.size())
	main.local_ship.throttle = 1.0
	Game.request_trade("kepler_station", "elektronik", 2, true)
	await _seconds(1.0)
	_check(int(Game.wallet["cargo"].get("elektronik", 0)) == 2, "købte 2 elektronik via værten")
	_check(int(Game.wallet["credits"]) < Game.START_CREDITS, "kredit opdateret fra værten")
	_check(Game.markets["kepler_station"]["elektronik"]["price"] > 40.0, "ser den nye pris")
	main.local_ship.steering = false
	main.local_ship.throttle = 0.0
	# Vent på piraten, som værten sender, og skyd den ned.
	var pi := -1
	var t2 := 0.0
	while pi == -1 and t2 < 10.0:
		await _seconds(0.2)
		t2 += 0.2
		for i in Pirates.POOL:
			if W.pirates._p[i]["active"]:
				pi = i
	_check(pi != -1, "ser piraten fra værten")
	if pi != -1:
		await _seconds(0.5)
		var credits := int(Game.wallet["credits"])
		var ppos: Vector3 = (W.pirates._p[pi]["node"] as Node3D).position
		for k in 8:
			W.pirates.hit_test(ppos, ppos, 1.0)
		await _seconds(1.0)
		_check(not W.pirates._p[pi]["active"], "piraten forsvandt hos klienten")
		_check(int(Game.wallet["credits"]) == credits + 60, "dusør modtaget (+60 cr)")
	# Asteroide: meld en træffer og se den forsvinde og tabe malm.
	W.asteroids._srv_hit.rpc_id(1, 0, 99.0)
	await _seconds(1.0)
	_check(not W.asteroids._rocks[0]["alive"], "asteroiden sprang hos klienten")
	_check(W.pickups._items.size() > 0, "malm dukkede op hos klienten")
	# Missionstavle i co-op
	var got := []
	W.missions.mission_ended.connect(func(r: Dictionary): got.append(r))
	_check(W.missions.board.size() == 3, "klienten ser missionstavlen (%d)" % W.missions.board.size())
	var easy := {}
	for o: Dictionary in W.missions.board:
		if int(o["min_rank"]) == 0:
			easy = o
	W.missions.request_accept(int(easy["oid"]))
	await _seconds(1.0)
	_check(W.missions.active and str(W.missions.client.get("objective", "")) != "", "missionen startet hos klienten: %s" % W.missions.client.get("objective", ""))
	W.missions.request_abort()
	await _seconds(1.0)
	_check(not W.missions.active and got.size() == 1 and not got[0]["success"], "klienten fik debriefing efter afbrydelse")
	await _seconds(2.5)


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _finish(role: String) -> void:
	print("RESULTAT %s: %s (%d fejl)" % [role.to_upper(), "BESTÅET" if failures == 0 else "FEJLET", failures])
	Net.leave()
	get_tree().quit(1 if failures else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
