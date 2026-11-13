extends Node
## Test af storbyer og mindre landingssteder, Concord-rum og patruljer, missiler og
## missilforsvar (solo). Kør headless:
##   godot --headless --path . res://tests/world2_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_world2.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Testpilot")
	await _frames(5)
	ship = main.local_ship
	ship.steering = false
	var uni: Universe = main.universe
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0   # ingen tilfældige bølger under testen

	# ---- Byer og mindre steder
	var total_pads := 0
	for p in uni.planets:
		total_pads += p.pads.size()
	_check(total_pads == 30, "30 landingssteder på 10 planeter inkl. byggegrunde (%d)" % total_pads)
	var vir := uni.planet("viridia")
	var towers := 0
	for n in vir.get_children():
		if n.name == "Pad_viridia":
			towers = n.get_child_count() - 1
	_check(towers >= 15, "Viridias storby har en skyline (%d skyskrabere)" % towers)
	var flat_ok := true
	for p in uni.planets:
		for pad in p.pads:
			var h := p.height_at(pad["dir"])
			if absf(h - float(pad["h"])) > 0.01:
				flat_ok = false
	_check(flat_ok, "alle landingspladser ligger på fladt terræn")
	if shots:
		_view(vir, vir.pads[0], 260.0, 120.0)
		await _seconds(1.5)
		await _shot("40_storby_viridia")
		var sahra := uni.planet("sahra")
		_view(sahra, sahra.pad_by_id("sahra_mine"), 110.0, 60.0)
		await _seconds(1.5)
		await _shot("41_mine_sahra")
		_view(vir, vir.pad_by_id("viridia_farm"), 110.0, 60.0)
		await _seconds(1.5)
		await _shot("42_landbrug_viridia")
		var ign := uni.planet("ignis")
		_view(ign, ign.pads[0], 170.0, 80.0)
		await _seconds(1.5)
		await _shot("43_storby_ignis")
		var fro := uni.planet("frosta")
		_view(fro, fro.pads[0], 230.0, 110.0)
		await _seconds(1.5)
		await _shot("44_storby_frosta")
	# Land ved minen på Sahra
	var mine: Dictionary = uni.pad_of("sahra_mine")["pad"]
	ship.position = (mine["top"] as Vector3) + (mine["dir"] as Vector3) * 10.0
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.0)
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "sahra_mine", "landet ved Dybgruben")
	_check(main.menu.visible and main.menu._title.text.contains("DYBGRUBEN"), "menuen viser minen: %s" % main.menu._title.text)
	_check(Game.markets.has("sahra_mine") and Game.markets["sahra_mine"].has("malm"), "minen har et marked med malm")
	if shots:
		await _shot("45_menu_mine")
	main.menu.launch_requested.emit()
	await _frames(3)
	_check(ship.state == Ship.State.FLY and uni.planet("sahra").ground_altitude(ship.position) > 3.0, "letter fra minen")

	# ---- Concord-rum
	_check(Pirates.wave_interval("kepler") > 250.0, "sjældne pirater i Kepler (ca. %d s)" % int(Pirates.wave_interval("kepler")))
	_check(Pirates.wave_interval("frosta") < Pirates.wave_interval("kepler"), "oftere i Frosta (grænserum)")
	_check(Pirates.in_concord_haven(uni.station("concord_base").position + Vector3(0, 0, 300)), "ingen pirater tæt på basen")
	var patrols := W.patrols.positions_in("kepler").size()
	_check(patrols == 2, "to Concord-patruljer flyver i Kepler (%d)" % patrols)
	# Pirat ved en patrulje: patruljen tager den
	var pp: Vector3 = W.patrols.positions_in("kepler")[0]
	ship.position = pp + Vector3(0, 400, 0)
	var pi: int = W.pirates.server_spawn_at("kepler", pp + Vector3(0, 0, -250), pp, "patrol_test")
	W.patrols.server_alert("kepler", pp)
	_check(W.patrols.positions_in("kepler").size() >= 3, "der letter ekstra patruljer fra basen")
	var t := 0.0
	while W.pirates.is_active(pi) and t < 40.0:
		await _seconds(0.5)
		t += 0.5
	_check(not W.pirates.is_active(pi), "patruljen skød piraten ned (%.0f s)" % t)

	# Fjern pirater fra piratlejre, som skærmbillederne kan have vækket
	for i in Pirates.POOL:
		if W.pirates.is_active(i):
			W.pirates._cl_despawn.rpc(i)
	for site in W.sites.sites:
		site["armed"] = true
	await _frames(2)

	# ---- Spillerens missiler
	ship.position = uni.origins["kepler"] + Vector3(400, 900, 1500)
	ship.basis = Basis.IDENTITY
	ship.speed = 0.0
	ship.throttle = 0.0
	_check(int(Game.wallet["missiles"]) == 4, "starter med 4 missiler")
	var j: int = W.pirates.server_spawn_at("kepler", ship.position + ship.forward() * 300.0, ship.position, "m_test")
	await _frames(3)
	# Uden lås flyver missilet ligeud og sprænger ved første træf
	ship.aim_dir = ship.forward()
	W.pirates.server_despawn_tag("m_test")
	await _frames(2)
	var p0 := ship.position
	var f0 := ship.forward()
	ship.aim_dir = f0
	_check(W.missiles.fire_player(ship) == "", "missil affyret uden lås")
	await _seconds(0.5)
	var mp := Vector3.ZERO
	for id: int in W.missiles._m:
		mp = W.missiles._m[id]["pos"]
	var off := (mp - p0) - f0 * (mp - p0).dot(f0)
	_check((mp - p0).dot(f0) > 40.0 and off.length() < 3.0, "det flyver ligeud (%d m frem, %.1f m til siden)" % [int((mp - p0).dot(f0)), off.length()])
	await _seconds(7.0)
	j = W.pirates.server_spawn_at("kepler", ship.position + ship.forward() * 300.0, ship.position, "m_test")
	await _frames(3)
	W.missiles.fire_cool = 0.0
	ship.steering = true
	ship.cycle_lock()
	ship.steering = false
	await _seconds(0.5)
	_check(ship.is_locked(), "målet er låst")
	_check(W.missiles.fire_player(ship) == "", "missil affyret")
	await _frames(3)
	_check(int(Game.wallet["missiles"]) == 2, "2 missiler tilbage")
	if shots:
		await _seconds(0.6)
		await _shot("46_missil")
	t = 0.0
	while W.pirates.is_active(j) and t < 6.0:
		ship.hull = 100.0
		await _seconds(0.2)
		t += 0.2
	_check(not W.pirates.is_active(j), "missilet sprængte piraten (%.1f s)" % t)
	W.pirates.server_despawn_tag("m_test")

	# ---- Piratmissiler, flares og missilforsvar
	ship.shield = ship.shield_max
	ship.hull = 100.0
	var from := ship.position + ship.forward() * 400.0
	W.missiles.server_pirate_fire(from, -ship.forward(), ship.peer_id)
	await _frames(2)
	_check(W.missiles.incoming() == 1, "et piratmissil er låst på skibet")
	_check(main.hud._warn.text.contains("MISSIL"), "advarsel: %s" % main.hud._warn.text)
	await _seconds(0.6)
	seed(3)
	W.missiles.flare_cool = 0.0
	W.missiles.fire_flares(ship)
	var decoyed := false
	for id: int in W.missiles._m:
		decoyed = decoyed or W.missiles._m[id].has("decoy")
	await _seconds(3.0)
	_check(W.missiles.incoming() == 0, "missilet er væk")
	if decoyed:
		_check(ship.shield == ship.shield_max and ship.hull == 100.0, "flares narrede missilet – ingen skade")
	else:
		_check(ship.shield < ship.shield_max or ship.hull < 100.0, "flares virkede ikke denne gang – skibet blev ramt")
	ship.shield = ship.shield_max
	W.missiles.server_pirate_fire(ship.position + ship.forward() * 400.0, -ship.forward(), ship.peer_id)
	await _seconds(4.0)
	_check(ship.shield < ship.shield_max, "uden flares rammer missilet (skjold %d)" % int(ship.shield))
	# Køb missilforsvar og missiler på Kepler Station
	Game.server_reward(multiplayer.get_unique_id(), 1000, 0)
	await _frames(2)
	var cr := int(Game.wallet["credits"])
	Game.request_upgrade("kepler_station", "missile_defense")
	Game.request_upgrade("kepler_station", "missiles")
	await _frames(4)
	_check(Game.upgrade_level("missile_defense") == 1, "missilforsvar købt")
	_check(int(Game.wallet["missiles"]) == 8 and int(Game.wallet["credits"]) == cr - 260 - 6 * 15, "magasinet fyldt op (8) for 90 cr")
	var shot_down := 0
	for k in 6:
		ship.shield = ship.shield_max
		ship.hull = 100.0
		W.missiles.server_pirate_fire(ship.position + ship.forward() * 300.0, -ship.forward(), ship.peer_id)
		var before := ship.shield
		await _seconds(3.0)
		if ship.shield == before:
			shot_down += 1
	_check(shot_down >= 1, "missilforsvaret skød missiler ned (%d af 6)" % shot_down)

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


## Svæv over et landingssted og kig ind mod det.
func _view(p: PlanetBody, pad: Dictionary, back: float, up_m: float) -> void:
	var d: Vector3 = pad["dir"]
	var t: Vector3 = pad["tangent"]
	var c: Vector3 = pad["top"]
	ship.position = c + t * back + d * up_m
	ship.basis = Basis.looking_at((c + d * 20.0 - ship.position).normalized(), d)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship._ang = Vector3.ZERO
	main.camera.snap()


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
