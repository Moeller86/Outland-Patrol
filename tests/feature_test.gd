extends Node
## Test af lyd, kort og lock-on (solo). Kør headless:
##   godot --headless --path . res://tests/feature_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false


func _ready() -> void:
	Game.save_path = "user://test_features.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await _frames(3)
	Net.start_solo("Testpilot")
	await _frames(5)
	var ship: Ship = main.local_ship
	ship.steering = false
	var uni: Universe = main.universe

	# ---- Lyd
	_check(Sfx._streams.size() == Sfx.SOUNDS.size(), "alle %d lydeffekter indlæst (%d)" % [Sfx.SOUNDS.size(), Sfx._streams.size()])
	_check(Sfx._music_space.stream != null and Sfx._music_space.playing, "rummusikken spiller")
	_check((Sfx._music_space.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "musikken looper")
	_check(Sfx._players_3d.size() == Sfx.POOL_3D and Sfx._players_3d[0].get_parent() == main.world, "3D-lyde ligger i verden")
	ship.throttle = 0.8
	await _seconds(0.6)
	_check(Sfx._engine.playing, "motorbrummet kører under flyvning")
	ship.fire()
	_check(Sfx._players_2d.any(func(p: AudioStreamPlayer): return p.playing and p.stream == Sfx._streams["laser"]), "laserlyd ved skud")
	Sfx.set_music(false)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Musik")), "musik kan slås fra")
	Sfx.set_music(true)

	# ---- Lock-on
	ship.throttle = 0.0
	ship.speed = 0.0
	var start := ship.position
	var i: int = W.pirates.server_spawn_at("kepler", start + ship.forward() * 220.0 + ship.global_basis.x * 40.0, start, "test")
	await _frames(3)
	ship.steering = true
	ship.cycle_lock()
	_check(ship.lock_target == i, "T låser piraten foran skibet")
	_check(not ship.is_locked(), "først 'låser …'")
	await _seconds(0.5)
	_check(ship.is_locked(), "derefter låst")
	var j: int = W.pirates.server_spawn_at("kepler", start + ship.forward() * 300.0 - ship.global_basis.x * 60.0, start, "test")
	await _frames(3)
	ship.cycle_lock()
	_check(ship.lock_target == j, "T igen skifter til næste mål")
	ship.cycle_lock()
	_check(ship.lock_target >= 0, "låsen holdes ved skift")
	ship._set_lock(i)
	await _seconds(0.5)
	if shots:
		await _shot("10_lock_on")
	# Sigtehjælp: peg groft mod målet (ikke forudsigelsespunktet) og skyd
	var assisted := 0
	var fired := 0
	var kills_before := int(Game.wallet.get("kills", 0))
	var t := 0.0
	while W.pirates.is_active(i) and t < 8.0:
		var tp := W.pirates.position_of(i)
		ship.basis = Basis.looking_at((tp - ship.position).normalized(), Vector3.UP)
		ship.hull = 100.0
		ship.shield = ship.shield_max
		if ship.is_locked():
			fired += 1
			if ship.aim_assist_active():
				assisted += 1
		ship.fire()
		await _seconds(0.16)
		t += 0.16
	_check(fired > 0 and assisted >= fired * 0.6, "sigtehjælpen er aktiv, når man peger mod målet (%d/%d skud)" % [assisted, fired])
	_check(not W.pirates.is_active(i), "låst pirat skudt ned med sigtehjælp (%.1f s)" % t)
	_check(int(Game.wallet.get("kills", 0)) > kills_before, "dusør for nedskydningen")
	await _frames(3)
	_check(ship.lock_target == j or ship.lock_target == -1, "lås skifter/slippes, når målet er væk")
	W.pirates.server_despawn_tag("test")
	await _frames(3)
	_check(ship.lock_target == -1, "låsen slippes, når piraten forsvinder")
	ship.cycle_lock()
	_check(ship.lock_target == -1, "ingen lås uden pirater")

	# ---- Kort
	ship.position = start
	ship.steering = true
	main.toggle_map()
	await _frames(2)
	var map: StarMap = main.star_map
	_check(map.visible and not ship.steering, "M åbner kortet og slipper styringen")
	_check(map.view_sys == "kepler", "kortet viser det nuværende system")
	var vir := uni.planet("viridia")
	map._click(map._to_screen(vir.pad_top))
	_check(W.waypoint.get("label", "") == "VIRIDIA" and W.waypoint.get("system", "") == "kepler", "klik på Viridia sætter markering")
	if shots:
		await _shot("11_kort_system")
	map._switch_mode("galaxy")
	await _frames(2)
	if shots:
		await _shot("12_kort_galakse")
	map._click(map._galaxy_pos("frosta"))
	_check(map.mode == "system" and map.view_sys == "frosta", "klik på Frosta i galaksen viser Frosta")
	var fro := uni.planet("frosta")
	map._click(map._to_screen(fro.pad_top))
	_check(W.waypoint.get("system", "") == "frosta", "markering i et andet system")
	map.close()
	await _frames(2)
	_check(not map.visible and ship.steering, "kortet lukker og styringen kommer tilbage")
	_check(_marker_text().contains("(via gate)"), "HUD peger mod gaten til Frosta")
	# Markering i samme system nås
	main.toggle_map()
	await _frames(1)
	map.view_sys = "kepler"
	map._click(map._to_screen(vir.pad_top))
	map.close()
	await _frames(2)
	_check(_marker_text().contains("◆ VIRIDIA"), "HUD viser markeringen")
	ship.position = vir.pad_top + vir.pad_dir * 30.0
	await _frames(3)
	_check(W.waypoint.is_empty(), "markeringen forsvinder, når man er fremme")

	# ---- Højre musetast = sekundære våben
	ship.position = W.universe.origins["kepler"] + Vector3(0, 900, 1500)
	ship.basis = Basis.IDENTITY
	var rmb_ok := false
	for ev in InputMap.action_get_events("fire_2"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			rmb_ok = true
	_check(rmb_ok, "højre musetast skyder med de sekundære våben")

	# ---- Kanonerne følger musemarkøren inden for gimbal-keglen
	ship.basis = Basis.IDENTITY
	var cam_o := ship.position + Vector3(0, 3, 10)
	ship.aim_from_ray(cam_o, (ship.position + ship.forward() * 300.0 + Vector3(40, 0, 0) - cam_o).normalized())
	var off := rad_to_deg(ship.forward().angle_to(ship.aim_dir))
	_check(off > 4.0 and not ship.aim_clamped, "kanonerne drejer mod markøren (%.1f°)" % off)
	ship.aim_from_ray(cam_o, (ship.position + Vector3(300, 0, -100) - cam_o).normalized())
	off = rad_to_deg(ship.forward().angle_to(ship.aim_dir))
	_check(ship.aim_clamped and absf(off - float(ship.handling["gimbal"])) < 0.5, "men kun %d° ud til siden (%.1f°)" % [int(ship.handling["gimbal"]), off])

	# ---- Kamerazoom med musehjulet
	main.camera.zoom_target = 1.0
	var z0: float = main.camera.zoom_target
	for k in 3:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		main._unhandled_input(ev)
	_check(main.camera.zoom_target > z0 * 1.3, "hjulet zoomer ud (%.2f)" % main.camera.zoom_target)
	await _seconds(0.6)
	_check(main.camera.global_position.distance_to(ship.get_global_transform_interpolated().origin) > 13.0, "kameraet er længere væk")
	main.camera.zoom_target = 1.0

	# ---- Førstepersonsvisning fra cockpittet
	main.camera.set_first_person(true)
	ship.position = W.universe.origins["kepler"] + Vector3(200, 900, 1500)
	ship.basis = Basis.IDENTITY
	ship.speed = 30.0
	await _seconds(0.3)
	var eye: Vector3 = ship.get_global_transform_interpolated() * ChaseCamera.EYES["falk"]
	_check(main.camera.global_position.distance_to(eye) < 0.3, "kameraet sidder i cockpittet")
	_check(main.camera.cockpit.visible and not ship.model.visible, "cockpittet vises, og skibets yderside er skjult")
	_check(main.camera.cockpit.get_child_count() > 20, "cockpit med ramme og instrumenter (%d dele)" % main.camera.cockpit.get_child_count())
	var cp_i: int = W.pirates.server_spawn_at("kepler", ship.position + Vector3(25, 12, -160), ship.position + Vector3(0, 0, -400), "cockpit")
	W.pirates.server_spawn_at("kepler", ship.position + Vector3(-300, -40, 500), ship.position, "cockpit")
	await _frames(3)
	ship._set_lock(cp_i)
	await _seconds(0.6)
	_check(main.camera.cockpit._holo_kind.begins_with("pirat"), "målskærmen viser hologram af den låste pirat")
	if shots:
		await _shot("13_cockpit")
	W.pirates.server_despawn_tag("cockpit")
	ship.clear_lock()
	await _frames(3)
	ship.set_class("bison")
	await _seconds(0.2)
	_check(main.camera.cockpit.ship_class == "bison", "Bison har sit eget cockpit")
	if shots:
		await _shot("14_cockpit_bison")
	ship.set_class("falk")
	var wev := InputEventMouseButton.new()
	wev.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wev.pressed = true
	main._unhandled_input(wev)
	await _frames(2)
	_check(not main.camera.first_person and ship.model.visible and not main.camera.cockpit.visible, "rul ud: tilbage bag skibet")
	main.camera.zoom_target = 0.55
	wev.button_index = MOUSE_BUTTON_WHEEL_UP
	main._unhandled_input(wev)
	_check(main.camera.first_person, "rul helt ind: ind i cockpittet")
	main.camera.set_first_person(false)
	main.camera.zoom_target = 1.0
	main._save_settings()

	# ---- Styring og manøvredyser
	var base_turn := float(Game.ship_data["classes"]["falk"]["turn"])
	_check(is_equal_approx(float(ship.handling["turn"]), base_turn), "Falk drejer %.1f rad/s" % base_turn)
	Game.server_reward(multiplayer.get_unique_id(), 1000, 0)
	await _frames(2)
	var cr := int(Game.wallet["credits"])
	Game.request_upgrade("kepler_station", "thrusters")
	await _frames(3)
	_check(Game.upgrade_level("thrusters") == 1 and int(Game.wallet["credits"]) == cr - 180, "manøvredyser niveau 1 købt (180 cr)")
	_check(is_equal_approx(float(ship.handling["turn"]), base_turn * 1.15), "drejer 15 %% hurtigere (%.2f)" % float(ship.handling["turn"]))
	Game.request_upgrade("kepler_station", "thrusters")
	await _frames(3)
	_check(Game.upgrade_level("thrusters") == 2 and int(Game.wallet["credits"]) == cr - 180 - 300, "niveau 2 koster 300 cr")
	_check(ship.max_speed() > 60.0, "lidt højere topfart (%.1f)" % ship.max_speed())

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _marker_text() -> String:
	var out := ""
	for l: Label in main.hud._markers:
		if l.visible:
			out += l.text + " | "
	return out


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
