extends Node
## Test af vejr og farer: sandstorm på Sahra, tordenvejr på Viridia, lava på Ignis.
##   godot --headless --path . res://tests/weather_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship
var wx: Weather


func _ready() -> void:
	Game.save_path = "user://test_weather.json"
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
	wx = W.weather
	var uni: Universe = main.universe
	_check(wx.active.size() == 6, "seks planeter har vejr (%d)" % wx.active.size())

	# ---- Sandstorm på Sahra
	var sahra := uni.planet("sahra")
	_hover(sahra, sahra.tangent * 0.4, 60.0)
	await _frames(3)
	var lock_calm := ship.lock_range()
	wx.server_set("sahra", true, true)
	await _frames(3)
	_check(float(wx.effect_at(ship.position)["k"]) > 0.9, "sandstormen er i gang")
	_check(ship.lock_range() < lock_calm * 0.5, "lock-on har kort rækkevidde (%d m)" % int(ship.lock_range()))
	_check(wx.scan_mul(ship.position) < 0.5, "scanneren har kort rækkevidde")
	var p0 := ship.position
	await _seconds(1.0)
	_check(ship.position.distance_to(p0) > 2.0, "vinden skubber skibet (%.1f m)" % ship.position.distance_to(p0))
	_check(main.env.fog_density > 0.006, "tæt sandtåge (%.4f)" % main.env.fog_density)
	_check(main.hud._warn.text.contains("SANDSTORM"), "advarsel i HUD: %s" % main.hud._warn.text)
	if shots:
		await _seconds(1.5)
		await _shot("30_sandstorm")
	wx.server_set("sahra", false, true)
	await _frames(3)
	_check(float(wx.effect_at(ship.position)["k"]) == 0.0, "sandstormen er ovre")

	# ---- Tordenvejr på Viridia
	var vir := uni.planet("viridia")
	_hover(vir, vir.tangent * 0.3, 50.0)
	wx.server_set("viridia", true, true)
	await _frames(3)
	ship.shield = ship.shield_max
	ship.hull = 100.0
	var up := (ship.position - vir.position).normalized()
	var ground := vir.position + up * vir.fine_surface_radius(up)
	wx._cl_strike("viridia", ground)
	await _seconds(0.5)
	_check(wx._strikes.size() > 0 and ship.shield == ship.shield_max, "jorden knitrer før nedslaget – ingen skade endnu")
	await _seconds(0.75)
	if shots:
		await _shot("31_lynnedslag")
	_check(ship.shield < ship.shield_max, "lynet ramte skibet (skjold %d)" % int(ship.shield))
	# Værten sender selv lyn ned omkring skibet
	ship.shield = ship.shield_max
	var n := 0
	for k in 40:
		ship.hull = 100.0
		await _seconds(0.1)
		n = maxi(n, wx._strikes.size())
	_check(n > 0, "værten sender lyn ned omkring skibet")
	if shots:
		await _seconds(1.0)
		await _shot("32_tordenvejr")
	wx.server_set("viridia", false, true)
	await _seconds(1.5)

	# ---- Lava på Ignis
	var ign := uni.planet("ignis")
	var lava_dir := Vector3.ZERO
	var rock_dir := Vector3.ZERO
	for k in 4000:
		var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		if d.dot(ign.pad_dir) < 0.3:
			continue
		if lava_dir == Vector3.ZERO and ign.height_at(d) < -6.0:
			lava_dir = d
		if rock_dir == Vector3.ZERO and ign.height_at(d) > 20.0:
			rock_dir = d
	_check(lava_dir != Vector3.ZERO, "Ignis har et lavahav")
	ship.position = ign.position + lava_dir * (ign.fine_surface_radius(lava_dir) + 15.0)
	ship.shield = ship.shield_max
	ship.hull = 100.0
	await _seconds(1.0)
	_check(wx.heat and ship.shield < ship.shield_max, "lavt over lavahavet koger skibet (skjold %d)" % int(ship.shield))
	_check(main.hud._warn.text.contains("LAVA"), "advarsel: %s" % main.hud._warn.text)
	if shots:
		ship.basis = Basis.looking_at(ign.tangent, lava_dir)
		main.camera.snap()
		await _seconds(0.4)
		await _shot("33_lavahav")
	ship.position = ign.position + lava_dir * (ign.fine_surface_radius(lava_dir) + 80.0)
	await _frames(3)
	_check(not wx.heat, "højere oppe er der ikke varmt")
	# Vulkanudbrud
	ship.position = ign.position + rock_dir * (ign.fine_surface_radius(rock_dir) + 60.0)
	var it := (ign.tangent - rock_dir * ign.tangent.dot(rock_dir)).normalized()
	ship.basis = Basis.looking_at((it - rock_dir * 0.35).normalized(), rock_dir)
	wx.server_set("ignis", true, true)
	var bombs := 0
	for k in 40:
		ship.hull = 100.0
		ship.shield = ship.shield_max
		await _seconds(0.1)
		bombs = maxi(bombs, wx._bombs.size())
	_check(bombs > 0, "vulkanen skyder lavabomber op (%d)" % bombs)
	if shots:
		main.camera.snap()
		await _seconds(0.3)
		await _shot("34_vulkanudbrud")
	ship.shield = ship.shield_max
	wx._cl_bomb("ignis", ship.position + ship.forward() * 2.0, Vector3.ZERO)
	await _frames(3)
	_check(ship.shield < ship.shield_max, "en lavabombe rammer skibet")
	wx.server_set("ignis", false, true)

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


## Svæv over planeten: retningen pad_dir + offset, `alt` meter over jorden, stillestående.
func _hover(p: PlanetBody, offset: Vector3, alt: float) -> void:
	var d := (p.pad_dir + offset).normalized()
	ship.position = p.position + d * (p.fine_surface_radius(d) + alt)
	var t := (p.tangent - d * p.tangent.dot(d)).normalized()
	ship.basis = Basis.looking_at((t - d * 0.35).normalized(), d)
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
