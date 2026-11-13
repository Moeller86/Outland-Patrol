extends Node
## Missiler uden lås, kratere og plask, lastrum (smid last ud) og gem.
## Kør headless:  godot --headless --path . res://tests/impact_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_impact.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Krater")
	await _frames(5)
	ship = main.local_ship
	ship.steering = false
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	var vir := W.universe.planet("viridia")

	# ---- Bombens sigtekryds er væk
	W.bombs.ammo = 3
	var land_d := _find(vir, true)
	_hover(vir, land_d, 60.0)
	await _seconds(0.3)
	_check(not W.bombs._aim.visible, "intet sigtekryds for bomber")

	# ---- Missil mod jorden: eksplosion og krater
	var craters0 := W.bombs._craters.size()
	ship.basis = Basis.looking_at(((vir.position + land_d * vir.surface_radius(land_d)) - ship.position).normalized(), _side(land_d))
	ship.aim_dir = ship.forward()
	_check(W.missiles.fire_player(ship) == "", "missil affyret mod jorden uden lås")
	await _seconds(1.5)
	_check(W.bombs._craters.size() == craters0 + 1, "missilet lavede et krater")
	var small_r := 0.0
	if not W.bombs._craters.is_empty():
		small_r = _crater_r(W.bombs._craters.back())
	if shots:
		_look_at_mark(vir, land_d)
		await _seconds(0.4)
		await _shot("90_krater_missil")

	# ---- Bombe: større krater
	var bomb_d := land_d.rotated(_side(land_d), 0.02)
	_hover(vir, bomb_d, 70.0)
	W.bombs.cool = 0.0
	ship.drop_bomb()
	await _wait_bombs()
	_check(W.bombs._craters.size() == craters0 + 2, "bomben lavede et krater")
	var big_r := _crater_r(W.bombs._craters.back())
	_check(big_r > small_r * 1.8, "bombens krater er større (%.0f m mod %.0f m)" % [big_r, small_r])
	if shots:
		_look_at_mark(vir, bomb_d)
		await _seconds(1.2)
		await _shot("91_krater_bombe")

	# ---- I vandet: plask, intet krater
	var sea_d := _find(vir, false)
	_hover(vir, sea_d, 70.0)
	var n_craters := W.bombs._craters.size()
	W.bombs.cool = 0.0
	ship.drop_bomb()
	await _wait_bombs(0.0)
	_check(W.bombs._splashes.size() > 0 and W.bombs._craters.size() == n_craters, "plask i vandet – intet krater")
	if shots:
		_look_at_mark(vir, sea_d)
		await _seconds(0.25)
		await _shot("92_plask")
	await _seconds(2.0)

	ship.model.scale = Vector3.ONE
	# ---- Lastrum: fyld op, smid ud, saml op igen
	var me := multiplayer.get_unique_id()
	var cap := int(Game.players[me]["cargo_max"])
	for k in cap:
		Game.server_add_cargo(me, "malm" if k % 2 == 0 else "krystal")
	await _frames(3)
	_check(Game.cargo_total(Game.wallet["cargo"]) == cap, "lastrummet er fuldt (%d/%d)" % [cap, cap])
	ship.position = W.universe.origins["kepler"] + Vector3(300, 900, 1500)
	ship.basis = Basis.IDENTITY
	ship.speed = 20.0
	ship.reset_physics_interpolation()
	main.camera.snap()
	await _frames(2)
	var ev := InputEventKey.new()
	ev.physical_keycode = Game.key_of("cargo")
	ev.pressed = true
	main._unhandled_input(ev)
	await _frames(2)
	_check(main.cargo_panel.visible and not ship.steering, "I åbner lastrummet")
	if shots:
		await _shot("93_lastrum")
	var items0 := W.pickups._items.size()
	var malm := int(Game.wallet["cargo"].get("malm", 0))
	_press(main.cargo_panel, "malm", "SMID 1")
	await _frames(4)
	_check(int(Game.wallet["cargo"].get("malm", 0)) == malm - 1 and W.pickups._items.size() == items0 + 1, "smed 1 malm ud")
	_press(main.cargo_panel, "krystal", "SMID ALLE")
	await _frames(4)
	_check(int(Game.wallet["cargo"].get("krystal", 0)) == 0, "smed alle krystaller ud")
	var dropped := W.pickups._items.size()
	await _seconds(1.0)
	_check(W.pickups._items.size() == dropped, "den udsmidte last suges ikke straks ind igen")
	main._unhandled_input(ev)
	await _frames(2)
	_check(not main.cargo_panel.visible and ship.steering, "I lukker lastrummet igen")
	# Efter et par sekunder kan den samles op igen
	await _seconds(Pickups.JETTISON_GRACE)
	var before := Game.cargo_total(Game.wallet["cargo"])
	var t := 0.0
	while t < 4.0 and Game.cargo_total(Game.wallet["cargo"]) == before:
		for id: int in W.pickups._items:
			ship.position = (W.pickups._items[id]["node"] as Node3D).position
			break
		ship.speed = 0.0
		await _seconds(0.1)
		t += 0.1
	_check(Game.cargo_total(Game.wallet["cargo"]) > before, "udsmidt last kan samles op igen")

	# ---- Gem
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	_check(main.save_game() and FileAccess.file_exists(Game.save_path), "F6/menuen gemmer spillet")
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(data is Dictionary and (data["pilots"] as Dictionary).has("Krater"), "piloten er i gemmefilen")
	main.pause_menu.open()
	await _frames(1)
	main.pause_menu._save_btn.pressed.emit()
	_check(main.pause_menu._note.text.contains("gemt"), "menuen: %s" % main.pause_menu._note.text)
	main.pause_menu.close()

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


## Find en retning på Viridia med land (true) eller hav (false), væk fra byer.
func _find(p: PlanetBody, land: bool) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 4000:
		var d := p.pad_dir.rotated(p.tangent, rng.randf_range(0.15, 1.2)).rotated(p.pad_dir, rng.randf_range(0, TAU)).normalized()
		var h := p.height_at(d)
		if p.in_flat_zone(d, 40.0) or p.in_feature_clear(d):
			continue
		if land and h > 15.0 and h < 120.0:
			return d
		if not land and h < -25.0:
			return d
	return p.pad_dir


func _side(d: Vector3) -> Vector3:
	return d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()


func _hover(p: PlanetBody, d: Vector3, alt: float) -> void:
	ship.position = p.position + d * (p.surface_radius(d) + alt)
	ship.basis = Basis.looking_at(_side(d).cross(d).normalized(), d)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship._ang = Vector3.ZERO
	ship.hull = 100.0
	ship.reset_physics_interpolation()
	main.camera.snap()


func _look_at_mark(p: PlanetBody, d: Vector3) -> void:
	var s := _side(d)
	var c := p.position + d * p.surface_radius(d)
	var cam_d := (c + s * 55.0 - p.position).normalized()
	ship.position = p.position + cam_d * (p.surface_radius(cam_d) + 40.0)
	ship.model.scale = Vector3.ONE * 0.001   # skjul skibet på billedet
	ship.basis = Basis.looking_at((c - ship.position).normalized(), cam_d)
	ship.speed = 0.0
	ship._ang = Vector3.ZERO
	ship.reset_physics_interpolation()
	main.camera.snap()


func _crater_r(c: Node3D) -> float:
	var r := 0.0
	for ch in c.get_children():
		if ch is MeshInstance3D:
			r = maxf(r, (ch as Node3D).position.length())
	return r


func _wait_bombs(extra := 0.4) -> void:
	for k in 400:
		ship.speed = 0.0
		await get_tree().physics_frame
		if W.bombs._b.is_empty():
			break
	await _seconds(extra + 0.05)


func _press(panel: CargoPanel, good: String, label: String) -> void:
	var name := Game.good_name(good)
	for row in panel._list.get_children():
		if row is HBoxContainer and (row.get_child(0) as Label).text.begins_with(name):
			for b in row.get_children():
				if b is Button and (b as Button).text == label:
					(b as Button).pressed.emit()
					return


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
