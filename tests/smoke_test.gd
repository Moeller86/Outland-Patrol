extends Node
## Automatisk røgtest (solo). Kør headless:
##   godot --headless --path . res://tests/smoke_test.tscn
## Flyver gennem hele loopet: dock, handel, trade lane, landing, jump gate.

var main: Node
var failures := 0


func _ready() -> void:
	Game.save_path = "user://test_smoke.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false   # denne test starter i rummet
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await _frames(5)
	Net.start_solo("Test")
	await _frames(5)
	var ship: Ship = main.local_ship
	_check(ship != null, "lokalt skib spawnet")
	if ship == null:
		_finish()
		return
	var uni: Universe = main.universe

	# Flyv lidt
	ship.throttle = 1.0
	await _seconds(1.0)
	_check(ship.speed > 10.0, "skibet accelererer (fart %.1f)" % ship.speed)

	# Dock ved stationen og køb elektronik
	var st := uni.station("kepler_station")
	ship.position = st.dock_pos + st.dock_dir * 8.0
	ship.speed = 5.0
	ship.throttle = 0.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "kepler_station", "docket ved Kepler Station")
	_check(main.menu.visible, "stationsmenu åben")
	var credits_before := int(Game.wallet["credits"])
	Game.request_trade("kepler_station", "elektronik", 2, true)
	await _frames(3)
	_check(int(Game.wallet["cargo"].get("elektronik", 0)) == 2, "købt 2 elektronik")
	_check(int(Game.wallet["credits"]) < credits_before, "kredit trukket (%d → %d)" % [credits_before, Game.wallet["credits"]])
	_check(Game.markets["kepler_station"]["elektronik"]["price"] > 40.0, "prisen steg efter køb")

	# Afgang og trade lane
	main.menu.launch_requested.emit()
	await _frames(2)
	_check(ship.state == Ship.State.FLY and not main.menu.visible, "afgang fra stationen")
	var lane: Dictionary = uni.lanes[0]
	ship.position = lane["a"]
	await _frames(3)
	_check(ship.state == Ship.State.LANE, "inde i trade lanen")
	var lane_time := (lane["a"] as Vector3).distance_to(lane["b"]) / Universe.LANE_SPEED
	await _seconds(lane_time + 0.5)
	_check(ship.state == Ship.State.FLY, "ude af trade lanen")
	var vir := uni.planet("viridia")
	_check(ship.position.distance_to(lane["b"]) < 120.0, "kom frem over Viridia")

	# Land på Viridia og sælg
	ship.position = vir.pad_top + vir.pad_dir * 12.0
	ship.speed = 5.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.0)
	_check(ship.docked_at == "viridia", "landet på Viridia")
	Game.request_trade("viridia", "elektronik", 99, false)
	await _frames(3)
	_check(int(Game.wallet["cargo"].get("elektronik", 0)) == 0, "solgt al elektronik")
	_check(int(Game.wallet["credits"]) > credits_before, "tjent penge (%d cr)" % Game.wallet["credits"])
	main.menu.launch_requested.emit()
	await _frames(2)

	# Jump gate til Frosta
	var gate: Dictionary = uni.gates["kepler_gate"]
	ship.position = gate["pos"]
	await _seconds(1.8)
	_check(uni.system_at(ship.position) == "frosta", "hoppet til Frosta")
	_check(ship.state == Ship.State.FLY, "flyver igen efter hop")
	var fro := uni.planet("frosta")
	ship.position = fro.pad_top + fro.pad_dir * 12.0
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.0)
	_check(ship.docked_at == "frosta", "landet på Frosta")
	Game.request_upgrade("frosta", "cargo")
	await _frames(3)
	_check(int(Game.wallet["cargo_max"]) == 12, "lastmodul afvist uden nok kredit")
	Game.players[1]["credits"] = 500
	Game.request_upgrade("frosta", "cargo")
	await _frames(3)
	_check(int(Game.wallet["cargo_max"]) == 20, "lastmodul købt (lastrum %d)" % Game.wallet["cargo_max"])

	# Menuscener for alle steder
	var arts := 0
	for id: String in Game.locations:
		if SceneArt.texture_for(Game.locations[id]) != null:
			arts += 1
	_check(arts == Game.locations.size(), "pixelscener tegnet for alle %d steder" % arts)

	# Detaljeret terræn tæt på Viridia (tilbage gennem gaten)
	main.menu.launch_requested.emit()
	await _frames(2)
	ship.position = (uni.gates["frosta_gate"]["pos"] as Vector3)
	await _seconds(1.8)
	ship.position = vir.pad_top + vir.pad_dir * 60.0 + vir.tangent * 150.0
	ship.speed = 0.0
	ship.throttle = 0.0
	main.camera.snap()
	await _seconds(1.5)
	var td: TerrainDetail = main.terrain
	_check(td._mesh.visible and td._mesh.mesh != null, "detaljeret terræn bygget nær overfladen")
	_check(td._flora.multimesh.visible_instance_count > 0, "træer på Viridia (%d)" % td._flora.multimesh.visible_instance_count)

	# Skyd en asteroide og saml malmen op
	var rock: Dictionary = {}
	for a: Dictionary in W.asteroids._rocks:
		if a["alive"] and a["kind"] == "malm":
			rock = a
			break
	var rock_node: Node3D = rock["node"]
	ship.position = rock_node.position + Vector3(0, 0, 40)
	ship.basis = Basis.looking_at((rock_node.position - ship.position).normalized(), Vector3.UP)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship.steering = false   # headless står musen i hjørnet og ville dreje skibet
	ship._ang = Vector3.ZERO
	var malm_before := int(Game.wallet["cargo"].get("malm", 0))
	var alive_before := _alive_rocks()
	for k in 12:
		ship.fire()
		await _seconds(0.2)
	_check(_alive_rocks() < alive_before, "asteroide sprængt af laseren")
	await _frames(2)
	_check(W.pickups._items.size() > 0, "malm tabt (%d stk.)" % W.pickups._items.size())
	ship.steering = true
	ship.position = rock_node.position
	await _seconds(1.5)
	_check(int(Game.wallet["cargo"].get("malm", 0)) > malm_before, "malm samlet op (%d)" % Game.wallet["cargo"].get("malm", 0))

	# Pirater: skyd én ned og få dusør
	W.pirates._server_spawn("kepler", ship.position)
	await _frames(3)
	var pi := -1
	for i in Pirates.POOL:
		if W.pirates._p[i]["active"]:
			pi = i
	_check(pi != -1, "pirat dukkede op")
	var credits_pre := int(Game.wallet["credits"])
	var ppos: Vector3 = (W.pirates._p[pi]["node"] as Node3D).position
	for k in 8:
		W.pirates.hit_test(ppos, ppos, ship.laser_damage())
	await _frames(3)
	_check(not W.pirates._p[pi]["active"], "piraten blev skudt ned")
	_check(int(Game.wallet["credits"]) == credits_pre + 60, "dusør udbetalt (+60 cr)")
	_check(int(Game.wallet["kills"]) == 1, "nedkæmpet tæller op")

	# Skjold og skrog
	ship.shield = ship.shield_max
	ship.hull = 100.0
	ship.take_damage(30.0)
	_check(ship.hull == 100.0 and ship.shield < ship.shield_max, "skjoldet tager skaden først")
	ship.take_damage(ship.shield + 25.0)
	_check(is_equal_approx(ship.hull, 75.0), "skroget tager resten (skrog %d)" % ship.hull)

	# Død og bjærgning
	var credits_dead := int(Game.wallet["credits"])
	ship.take_damage(500.0)
	_check(ship.dead, "skibet eksploderer ved 0 skrog")
	await _seconds(2.0)
	_check(not ship.dead and ship.state == Ship.State.LANDED, "bjærget til en by")
	_check(main.menu.visible and main.menu._note.visible, "menu viser bjærgningsbesked")
	_check(int(Game.wallet["credits"]) == maxi(0, credits_dead - 40), "bjærgningsgebyr trukket")
	_check(Game.cargo_total(Game.wallet["cargo"]) == 0, "lasten gik tabt")

	# Reparation
	Game.players[1]["credits"] = 500
	Game.request_repair(ship.docked_at, ship.hull)
	await _frames(3)
	_check(is_equal_approx(ship.hull, 100.0), "skroget repareret")
	_check(int(Game.wallet["credits"]) == 500 - 80, "reparation kostede 80 cr")

	# Fragtskibe: de flyver, og et sprængt fragtskib taber kasser
	var fr: Dictionary = W.freighters._f[0]
	var fpos: Vector3 = (fr["node"] as Node3D).position
	await _seconds(1.0)
	var moved_or_waiting: bool = (fr["node"] as Node3D).position.distance_to(fpos) > 1.0 or fr["wait"] > 0.0
	_check(moved_or_waiting, "fragtskibe flyver deres rute")
	var target := {}
	for f: Dictionary in W.freighters._f:
		if not f["docked"] and (f["node"] as Node3D).visible:
			target = f
			break
	var picks_before := W.pickups._items.size()
	for k in 6:
		W.freighters.server_bolt_hit((target["node"] as Node3D).position, 7.0)
	await _frames(3)
	_check(target["dead"], "fragtskib sprængt af piratskud")
	_check(W.pickups._items.size() >= picks_before + 3, "fragtskibet tabte sine kasser")

	# Kollision med jorden
	main.menu.launch_requested.emit()
	await _frames(2)
	main.menu.launch_requested.emit()
	await _frames(2)
	ship.position = fro.position + Vector3.UP * (fro.radius - 50.0)
	await _frames(2)
	_check(fro.ground_altitude(ship.position) > 0.0, "skibet kan ikke flyve ind i planeten")
	_finish()


func _alive_rocks() -> int:
	var n := 0
	for a: Dictionary in W.asteroids._rocks:
		if a["alive"]:
			n += 1
	return n


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _finish() -> void:
	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
