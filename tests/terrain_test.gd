extends Node
## Større planeter: vulkaner, mesaer med vandfald, kløfter, grotter og cruise-drev.
## Kør headless:  godot --headless --path . res://tests/terrain_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_terrain.json"
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

	# ---- Størrelse og landskabsdetaljer
	var vir := uni.planet("viridia")
	_check(vir.radius >= 1500.0, "Viridia er stor (radius %d m)" % int(vir.radius))
	var sah := uni.planet("sahra")
	_check(sah.radius < 500.0 and sah.atmo_top < 160.0, "Sahra er stadig en lille planet (radius %d m, atmosfære %d m)" % [int(sah.radius), int(sah.atmo_top)])
	var counts := {"volcano": 0, "mesa": 0, "canyon": 0, "cave": 0}
	for p in uni.planets:
		for f in p.features:
			counts[f["type"]] += 1
	_check(counts["volcano"] >= 3 and counts["mesa"] >= 6 and counts["canyon"] >= 6 and counts["cave"] >= 10,
		"landskabsdetaljer: %s" % str(counts))
	# Ingen detaljer oven i byer/landingspladser
	var clash := 0
	for p in uni.planets:
		for pad in p.pads:
			if p.in_feature_clear(pad["dir"]):
				clash += 1
	_check(clash == 0, "ingen landingspladser inde i vulkaner, kløfter eller grotter (%d)" % clash)

	# Vulkan: kraterkanten rager op, og krateret er varmt
	var ign := uni.planet("ignis")
	var vol: Dictionary = _feature(ign, "volcano")
	var vd: Vector3 = vol["dir"]
	var rim_d := vd.rotated(_perp(vd), float(vol["crater_r"]) * 1.4 / ign.radius).normalized()
	var foot_d := vd.rotated(_perp(vd), float(vol["base_r"]) * 1.1 / ign.radius).normalized()
	_check(ign.height_at(rim_d) > ign.height_at(foot_d) + 150.0,
		"vulkanens kant rager op (%d m over foden)" % int(ign.height_at(rim_d) - ign.height_at(foot_d)))
	_check(ign.in_crater(ign.position + vd * (ign.radius + ign.height_at(vd) + 10.0)), "krateret er lava-varmt")

	# Mesa med vandfald
	var mesa: Dictionary = _feature(vir, "mesa")
	var md: Vector3 = mesa["dir"]
	_check(absf(vir.height_at(md) - float(mesa["top"])) < 3.0, "mesaen har et fladt plateau")
	var falls := 0
	for n in vir.get_children():
		if n.has_meta("mist_at"):
			falls += 1
	_check(falls == 2, "Viridia har to vandfald (%d)" % falls)

	# Kløft
	var can: Dictionary = _feature(vir, "canyon")
	var cd: Vector3 = can["dir"]
	_check(vir.height_at(cd) < 0.0, "kløftens bund ligger under havniveau med en flod")

	# ---- Flyv gennem en grotte
	var cave: Dictionary = _feature(vir, "cave")
	var fr := Cave.frame(vir, cave)
	var start: Vector3 = vir.position + fr * Vector3(0, 0, Cave.LENGTH / 2.0 + 60.0)
	var fwd: Vector3 = (fr.basis * Vector3(0, 0, -1)).normalized()
	ship.position = start
	ship.basis = Basis.looking_at(fwd, fr.basis.y.normalized())
	ship._ang = Vector3.ZERO
	ship.throttle = 0.5
	ship.speed = 40.0
	ship.reset_physics_interpolation()
	main.camera.snap()
	var hull0 := ship.hull
	var was_inside := false
	var t := 0.0
	while t < 7.0:
		ship.basis = Basis.looking_at(fwd, fr.basis.y.normalized())
		ship.speed = 40.0
		ship.throttle = 0.5
		await get_tree().physics_frame
		t += 1.0 / 60.0
		was_inside = was_inside or Cave.inside(vir, ship.position)
		if shots and is_equal_approx(snappedf(t, 1.0 / 60.0), snappedf(2.4, 1.0 / 60.0)):
			await _shot("60_grotte_inde")
	_check(was_inside, "fløj ind gennem grottens tunnel")
	_check(ship.hull == hull0 and ship.state == Ship.State.FLY, "ingen kollision i tunnelen (skrog %d)" % int(ship.hull))
	_check((ship.position - start).length() > Cave.LENGTH, "kom ud i den anden ende")
	# Klippen udenom er massiv
	var rock_pos: Vector3 = vir.position + fr * Vector3(Cave.TUBE_R + 12.0, 0, 0)
	var res := Cave.push(vir, rock_pos)
	_check(res["hit"], "klippen omkring tunnelen er massiv")

	# ---- Cruise-drev
	ship.position = vir.position + vir.pad_dir * (vir.radius + 900.0)
	ship.basis = Basis.looking_at(vir.tangent, vir.pad_dir)
	ship.speed = 30.0
	ship.reset_physics_interpolation()
	ship.toggle_cruise()
	_check(ship.cruise == 1, "X lader cruise-drevet op")
	await _seconds(1.7)
	_check(ship.cruise == 2, "cruise aktivt efter opladning")
	ship.steering = false
	await _seconds(3.0)
	_check(ship.speed > 200.0, "cruise flyver hurtigt (%d m/s)" % int(ship.speed))
	if shots:
		await _shot("61_cruise")
	ship.take_damage(1.0)
	_check(ship.cruise == 0, "skade afbryder cruise")
	ship.toggle_cruise()
	await _seconds(1.7)
	ship.basis = Basis.looking_at((vir.position - ship.position).normalized(), vir.tangent)
	t = 0.0
	while ship.cruise == 2 and t < 10.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
	_check(ship.cruise == 0 and ship.hull > 0.0 and not ship.dead, "cruise slår fra før jorden (%.1f s, %d m over jorden)" % [t, int(vir.ground_altitude(ship.position))])
	ship.speed = 0.0
	ship.throttle = 0.0

	if shots:
		_view_feature(ign, vol, 520.0, 260.0)
		await _seconds(2.0)
		await _shot("62_vulkan")
		_view_waterfall(vir, mesa)
		await _seconds(2.0)
		await _shot("63_vandfald")
		_view_feature(vir, cave, 230.0, 60.0, cave["heading_dir"])
		await _seconds(2.0)
		await _shot("64_grotte")
		_view_feature(vir, can, 500.0, 150.0, null, 0.0)
		await _seconds(2.0)
		await _shot("65_kloeft")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _feature(p: PlanetBody, type: String) -> Dictionary:
	for f in p.features:
		if f["type"] == type:
			return f
	return {}


func _perp(d: Vector3) -> Vector3:
	var a := d.cross(Vector3.UP)
	if a.length() < 0.1:
		a = d.cross(Vector3.RIGHT)
	return a.normalized()


## Svæv `back` m fra detaljen og `up_m` m over den og kig mod den.
func _view_feature(p: PlanetBody, f: Dictionary, back: float, up_m: float, side = null, look_h := 40.0) -> void:
	var d: Vector3 = f["dir"]
	var s: Vector3 = side if side != null else _perp(d)
	s = (s - d * s.dot(d)).normalized()
	var c: Vector3 = p.position + d * (p.radius + maxf(p.height_at(d), 0.0))
	var cam_d := (c + s * back - p.position).normalized()
	var ground := p.radius + maxf(p.height_at(cam_d), 0.0)
	ship.position = p.position + cam_d * (ground + up_m)
	ship.basis = Basis.looking_at((c + d * look_h - ship.position).normalized(), cam_d)
	_freeze()


func _view_waterfall(p: PlanetBody, f: Dictionary) -> void:
	var d: Vector3 = f["dir"]
	var hd := p._heading_at(d, float(f.get("fall", 90.0)))
	var axis := d.cross(hd).normalized()
	var foot := d.rotated(axis, -(float(f["r"]) + 34.0) / p.radius).normalized()
	var cam_d := d.rotated(axis, -(float(f["r"]) + 260.0) / p.radius).normalized()
	var ground := p.radius + maxf(p.height_at(cam_d), 0.0)
	ship.position = p.position + cam_d * (ground + 60.0)
	var look := p.position + foot * (p.radius + maxf(p.height_at(foot), 0.0) + 50.0)
	ship.basis = Basis.looking_at((look - ship.position).normalized(), cam_d)
	_freeze()


func _freeze() -> void:
	ship.speed = 0.0
	ship.throttle = 0.0
	ship._ang = Vector3.ZERO
	ship.reset_physics_interpolation()
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
