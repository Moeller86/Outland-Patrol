extends Node
## Test af gruppens egne baser: køb, moduler, produktion, lager, hangar, piratangreb,
## gem/indlæs og en base i rummet. Kør headless:
##   godot --headless --path . res://tests/base_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_bases.json"
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
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	var uni: Universe = main.universe
	var B: PlayerBases = W.bases
	var me := multiplayer.get_unique_id()

	# ---- Byggegrunde
	var ground := 0
	for p in uni.planets:
		for pad in p.pads:
			if pad["style"] == "plot":
				ground += 1
	var space := 0
	for s in uni.stations:
		if s.data.get("plot", false):
			space += 1
	_check(ground == 6 and space == 3, "6 byggegrunde på planeter og 3 i rummet (%d/%d)" % [ground, space])

	# ---- Land på grunden på Sahra og køb den
	var sahra := uni.planet("sahra")
	var pad := sahra.pad_by_id("plot_sahra")
	await _land_pad(pad)
	_check(ship.docked_at == "plot_sahra" and main.base_menu.visible, "landet på byggegrunden – basemenuen er åben")
	_check(not B.owned("plot_sahra"), "grunden er til salg")
	B.request("buy", "plot_sahra")
	await _frames(3)
	_check(not B.owned("plot_sahra"), "for lidt kredit til at købe")
	Game.server_reward(me, 6000, 0)
	await _frames(2)
	B.request("buy", "plot_sahra")
	await _frames(3)
	_check(B.owned("plot_sahra") and int(Game.wallet["credits"]) == 6100 - 900, "grunden er købt (900 cr)")
	_check(main.base_menu._title.text.begins_with("GRUPPENS BASE"), "menuen viser gruppens base")

	# ---- Moduler
	B.request("build", "plot_sahra", "udvinding")
	await _frames(3)
	_check(B.level("plot_sahra", "udvinding") == 0, "udvinding kræver malm i lastrummet")
	for k in 5:
		Game.server_add_cargo(me, "malm")
	for k in 5:
		Game.server_add_cargo(me, "elektronik")
	await _frames(2)
	B.request("build", "plot_sahra", "udvinding")
	await _frames(3)
	_check(B.level("plot_sahra", "udvinding") == 1 and int(Game.wallet["cargo"].get("malm", 0)) == 2, "udvinding bygget (3 malm brugt)")
	B.request("build", "plot_sahra", "taarn")
	B.request("build", "plot_sahra", "hangar")
	await _frames(4)
	_check(B.level("plot_sahra", "taarn") == 1 and B.level("plot_sahra", "hangar") == 1, "forsvarstårn og hangar bygget")
	var vis: Node3D = B._visual["plot_sahra"]["root"]
	_check(vis.get_child_count() >= 4, "basen er bygget i 3D (%d dele)" % vis.get_child_count())

	# ---- Produktion og lager
	B._prod_t = 999.0
	await _frames(3)
	_check(int(Game.base_state("plot_sahra")["storage"]) == 1, "udvindingen fylder lageret")
	Game.base_state("plot_sahra")["storage"] = 6
	var malm := int(Game.wallet["cargo"].get("malm", 0))
	B.request("take", "plot_sahra", "all")
	await _frames(3)
	_check(int(Game.wallet["cargo"].get("malm", 0)) > malm and int(Game.base_state("plot_sahra")["storage"]) < 6, "malm hentet fra lageret til lastrummet")

	# ---- Hangar
	ship.hull = 40.0
	B.request("repair_ship", "plot_sahra")
	await _frames(3)
	_check(ship.hull == 100.0, "gratis reparation i egen hangar")
	if shots:
		await _shot("50_basemenu")

	# ---- Piratangreb
	main.base_menu.launch_requested.emit()
	await _frames(3)
	var up := pad["dir"] as Vector3
	ship.position = (pad["top"] as Vector3) + up * 120.0 + (pad["tangent"] as Vector3) * 200.0
	B.server_raid("plot_sahra")
	await _frames(3)
	var raiders := B._raid_count("plot_sahra")
	_check(raiders >= 3 and B.raid_active("plot_sahra"), "pirater angriber basen (%d)" % raiders)
	Engine.time_scale = 3.0
	var hp0 := float(Game.base_state("plot_sahra")["hp"])
	var t := 0.0
	while t < 45.0 and B._raid_count("plot_sahra") == raiders and float(Game.base_state("plot_sahra")["hp"]) >= hp0:
		ship.hull = 100.0
		ship.shield = ship.shield_max
		await _seconds(0.5)
		t += 0.5
	Engine.time_scale = 1.0
	_check(B._raid_count("plot_sahra") < raiders or float(Game.base_state("plot_sahra")["hp"]) < hp0,
		"kamp ved basen: tårnet skyder / basen tager skade (pirater %d, modstand %d)" % [B._raid_count("plot_sahra"), int(Game.base_state("plot_sahra")["hp"])])
	if shots:
		ship.basis = Basis.looking_at(((pad["top"] as Vector3) - ship.position).normalized(), up)
		main.camera.snap()
		await _seconds(0.8)
		await _shot("51_base_sahra")
	W.pirates.server_despawn_tag("raid_plot_sahra")

	# ---- Gem og indlæs
	Game.server_save()
	var saved: Dictionary = Game.world.duplicate(true)
	Game.world = {}
	Game.server_load()
	_check(Game.base_state("plot_sahra").get("owned", false) and int(Game.base_state("plot_sahra")["modules"]["udvinding"]) == 1,
		"basen er gemt og indlæst")
	Game.world = saved

	# ---- Base i rummet
	var orbit := uni.station("plot_kepler_orbit")
	ship.state = Ship.State.FLY
	ship.position = orbit.dock_pos + orbit.dock_dir * 8.0
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(ship.docked_at == "plot_kepler_orbit" and main.base_menu.visible, "docket ved orbitalpladsen")
	B.request("buy", "plot_kepler_orbit")
	await _frames(3)
	B.request("build", "plot_kepler_orbit", "udvinding")
	B.request("build", "plot_kepler_orbit", "lager")
	await _frames(4)
	_check(B.owned("plot_kepler_orbit") and B.level("plot_kepler_orbit", "udvinding") == 1 and B.level("plot_kepler_orbit", "lager") == 1,
		"rumbase købt med udvinding og lager")
	_check(B.storage_cap("plot_kepler_orbit") == 30, "lageret rummer 30")
	if shots:
		main.base_menu.launch_requested.emit()
		await _frames(2)
		ship.position = orbit.position + orbit.dock_dir * 90.0 + Vector3(30, 40, 0)
		ship.basis = Basis.looking_at((orbit.position - ship.position).normalized(), Vector3.UP)
		ship.speed = 0.0
		ship.throttle = 0.0
		main.camera.snap()
		await _seconds(1.0)
		await _shot("52_rumbase")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _land_pad(pad: Dictionary) -> void:
	ship.state = Ship.State.FLY
	ship.position = (pad["top"] as Vector3) + (pad["dir"] as Vector3) * 10.0
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.0)


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
