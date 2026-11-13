extends Node
## ESC-menuen: pause, indstillinger, taster, genstart af mission, ny pilot, startskærm.

var main: Node
var failures := 0
var shots := false


func _ready() -> void:
	Game.save_path = "user://test_pause.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	var pm: PauseMenu = main.pause_menu
	# Uden spil: ESC på startskærmen gør intet
	_esc()
	_check(not pm.visible, "ESC på startskærmen åbner ikke menuen")

	main.title.test_mission_pressed.emit("Pausepilot", "assault_frosta")
	await _seconds(1.0)
	var ship: Ship = main.local_ship
	_esc()
	await _frames(2)
	_check(pm.visible and get_tree().paused, "ESC åbner menuen og sætter spillet på pause")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "musen er synlig i menuen")
	var pos0 := ship.position
	await _frames(10)
	_check(ship.position == pos0, "skibet står stille under pausen")
	if shots:
		await _shot("80_esc_menu")

	# ---- Indstillinger
	pm._show("settings")
	await _frames(2)
	if shots:
		await _shot("81_indstillinger")
	pm._invert.button_pressed = true
	_check(Game.invert_y, "inverter musens op/ned")
	pm._sens.value = 1.5
	_check(is_equal_approx(Game.mouse_sensitivity, 1.5), "musens følsomhed 150 %")
	pm._pixel.select(2)
	pm._pixel.item_selected.emit(2)
	_check(main.pixel_mode == 2, "pixelstørrelse ændret")
	pm._music_vol.value = 0.4
	_check(absf(main.get_volume("Musik") - 0.4) < 0.02, "musikkens lydstyrke 40 %")
	pm._cockpit.button_pressed = true
	_check(main.camera.first_person, "cockpit slået til fra menuen")
	pm._cockpit.button_pressed = false
	var cfg := ConfigFile.new()
	cfg.load(main.SETTINGS_PATH)
	_check(bool(cfg.get_value("controls", "invert_y", false)) and absf(float(cfg.get_value("audio", "music_volume", 0)) - 0.4) < 0.02, "indstillingerne er gemt")
	pm._invert.button_pressed = false
	pm._sens.value = 1.0
	pm._pixel.select(1)
	pm._pixel.item_selected.emit(1)
	pm._music_vol.value = 0.8

	# ---- Taster
	pm._show("keys")
	await _frames(2)
	if shots:
		await _shot("82_taster")
	(pm._key_buttons["bomb"] as Button).pressed.emit()
	_check((pm._key_buttons["bomb"] as Button).text.contains("TRYK"), "venter på ny tast")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = true
	pm._input(ev)
	_check(Game.key_of("bomb") == KEY_G, "bombe flyttet til G")
	(pm._key_buttons["bomb"] as Button).pressed.emit()
	ev.physical_keycode = KEY_T
	pm._input(ev)
	_check(Game.key_of("bomb") == KEY_T and Game.key_of("lock") != KEY_T, "T flyttet fra 'Lås mål' til bombe: %s" % pm._note.text)
	cfg.load(main.SETTINGS_PATH)
	_check((cfg.get_value("controls", "keys", {}) as Dictionary).get("bomb", []).has(KEY_T), "tasterne er gemt")
	Game.reset_keys()
	_check(Game.key_of("bomb") == KEY_B and Game.key_of("lock") == KEY_T, "standardtaster gendannet")
	main.save_settings()

	# ---- Testværktøjer
	pm._show("main")
	_check(pm._test_btn.visible, "knappen Testværktøjer vises i testtilstand")
	pm._show("test")
	await _frames(2)
	if shots:
		await _shot("83_test")
	W.bombs.ammo = 0
	Game.players[multiplayer.get_unique_id()]["missiles"] = 0
	pm._fill_all()
	await _frames(3)
	_check(W.bombs.ammo == Bombs.ISSUED and int(Game.wallet["missiles"]) == Game.missile_max(), "fyld op: %d bomber og %d missiler" % [W.bombs.ammo, int(Game.wallet["missiles"])])
	Game.request_test("upgrades")
	await _frames(3)
	_check(Game.upgrade_level("laser") >= 1 and Game.upgrade_level("cargo") == 2 and int(Game.wallet["cargo_max"]) >= 28, "alle opgraderinger på max (last %d)" % int(Game.wallet["cargo_max"]))
	Game.request_test("ship", "krydser")
	await _frames(3)
	_check(Game.local_class() == "krydser" and main.local_ship.ship_class == "krydser", "skiftede direkte til Krydser")
	Game.request_test("all_ships")
	await _frames(3)
	_check(Game.owned_ships().size() == 12, "alle 12 skibe i hangaren")
	Game.request_test("ship", "falk")
	await _frames(3)

	# ---- ESC lukker
	pm._show("main")
	_esc_menu(pm)
	await _frames(2)
	_check(not pm.visible and not get_tree().paused, "ESC lukker menuen og spillet fortsætter")

	# ---- Genstart missionen
	var a: Assault = W.assault
	var fi := -1
	for i in a.targets.size():
		if a.targets[i]["kind"] == "flak":
			fi = i
			break
	a._srv_hit(fi, 99.0)
	await _frames(2)
	W.bombs.ammo = 2
	_check(not a.targets[fi]["alive"], "et luftskyts er skudt ned")
	pm.open()
	await _frames(1)
	_check(not pm._restart_btn.disabled, "'Genstart missionen' kan vælges")
	pm._restart_btn.pressed.emit()
	await _seconds(0.5)
	_check(not pm.visible and W.missions.active and a.active() and a.count("flak", false) == 0, "missionen er startet forfra – alt luftskyts står igen")
	_check(W.bombs.ammo == Bombs.ISSUED and not main.debrief.visible, "6 bomber igen, ingen debriefing")
	_check(ship.position.distance_to(a.entry) < 600.0, "skibet er tilbage ved kløften")

	# ---- Ny pilot
	Game.server_reward(multiplayer.get_unique_id(), 500, 50)
	await _frames(2)
	Game.server_save()
	_check(int(Game.wallet["credits"]) > 500, "piloten har %d cr" % int(Game.wallet["credits"]))
	main.restart_as_new_pilot()
	await _seconds(0.6)
	_check(main.local_ship != null and int(Game.wallet["credits"]) < 500 and int(Game.wallet.get("xp", 0)) == 0, "ny pilot: %d cr, 0 xp" % int(Game.wallet["credits"]))

	# ---- Til startskærmen
	main.to_title()
	await _frames(3)
	_check(main.title.visible and main.local_ship == null, "tilbage på startskærmen")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _esc() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	main._unhandled_input(ev)


func _esc_menu(pm: PauseMenu) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	pm._input(ev)


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
