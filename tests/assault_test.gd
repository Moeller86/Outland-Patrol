extends Node
## Angrebsmission: piratfæstning i en kløft, luftskyts, kontroltårne, bomber og reaktor.
## Kør headless:  godot --headless --path . res://tests/assault_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_assault.json"
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
	var a: Assault = W.assault

	# ---- Missionen starter, fæstningen bygges
	var tpl := {}
	for t: Dictionary in Game.mission_data["templates"]:
		if t["id"] == "assault_frosta":
			tpl = t
	_check(not tpl.is_empty(), "skabelonen 'Angreb: Isfæstningen' findes")
	W.missions._server_start(W.missions._make_offer(tpl))
	await _frames(4)
	_check(a.active() and a.planet.id == "frosta", "fæstningen er bygget på Frosta")
	_check(a.total("flak") >= 10 and a.total("tower") == 3 and a.total("tank") == 6 and a.reactor_idx >= 0,
		"%d luftskyts, %d tårne, %d tanke og en reaktor" % [a.total("flak"), a.total("tower"), a.total("tank")])
	_check(a.bridges.size() == 3, "tre broer over kløften")
	_check(W.bombs.ammo == Bombs.ISSUED, "Concord har udleveret %d bomber" % W.bombs.ammo)
	_check(W.missions.client.get("objective", "").contains("Frosta"), "mål: %s" % W.missions.client.get("objective", ""))
	# Kløften er dyb
	var p := a.planet
	var f: Dictionary = {}
	for ff in p.features:
		if ff["type"] == "canyon":
			f = ff
			break
	var mid: Vector3 = (f["a"] as Vector3).slerp(f["b"], 0.5)
	var rim_d := (mid + (f["n"] as Vector3) * (float(f["width"]) * 1.4 / p.radius)).normalized()
	var depth := p.surface_radius(rim_d) - p.surface_radius(mid)
	_check(depth > 80.0, "kløften er %d m dyb" % int(depth))

	# ---- Ankomst: luftskyts aktiveres, forsvarere letter
	var floor_d := (f["a"] as Vector3).slerp(f["b"], 0.12)
	var along := ((f["a"] as Vector3).slerp(f["b"], 0.13) - floor_d).normalized()
	ship.position = p.position + floor_d * (p.surface_radius(floor_d) + 30.0)
	ship.basis = Basis.looking_at(along, floor_d)
	ship.speed = 0.0
	ship.reset_physics_interpolation()
	main.camera.snap()
	await _seconds(0.5)
	_check(W.missions._m["phase"] == "attack" and float(W.missions.client.get("timer", 0)) > 200.0, "angrebet er i gang med nedtælling")
	_check(W.pirates.server_count_tag(W.missions._m["tag"]) >= 2, "piratjagere forsvarer fæstningen")
	W.pirates.server_despawn_tag(W.missions._m["tag"])
	_check(a.exposure(ship.position) < 0.2, "nede i kløften er man skjult for luftskytset (%.2f)" % a.exposure(ship.position))
	_check(a.exposure(ship.position + floor_d * 160.0) > 0.8, "over kanten er man synlig (%.2f)" % a.exposure(ship.position + floor_d * 160.0))
	_check(W.bombs.aim_valid, "sigtekrydset for bomber vises på jorden")
	if shots:
		ship.speed = 70.0
		ship.throttle = 1.0
		await _seconds(1.0)
		_hold()
		await _shot("70_kloeft_jagt")
		main.camera.set_first_person(true)
		await _seconds(0.4)
		await _shot("71_kloeft_cockpit")
		main.camera.set_first_person(false)
		ship.position = p.position + floor_d * (p.surface_radius(floor_d) + 30.0)
		ship.basis = Basis.looking_at(along, floor_d)

	# ---- Flak: synlig højt oppe, rammer oftere
	var hits_high := await _flak_hits(floor_d, 170.0)
	var hits_low := await _flak_hits(floor_d, 25.0)
	_check(hits_high > hits_low, "luftskytset rammer oftere højt oppe (%d) end nede i kløften (%d)" % [hits_high, hits_low])

	# ---- Laser mod luftskyts og panser
	var fi := _first("flak")
	var fl: Dictionary = a.targets[fi]
	var gun: Vector3 = (fl["pos"] as Vector3) + (fl["up"] as Vector3) * 4.0
	var t := 0.0
	while a.targets[fi]["alive"] and t < 6.0:
		_aim_at(gun, fl["up"], 70.0)
		ship.fire()
		await _seconds(0.15)
		t += 0.15
	_check(not a.targets[fi]["alive"], "luftskyts skudt ned med laser (%.1f s)" % t)
	await _frames(2)
	_check(int(W.missions._m["bonus"]) >= 20, "bonus for luftskyts (+%d cr)" % int(W.missions._m["bonus"]))
	var ti := _first("tower")
	var tw: Dictionary = a.targets[ti]
	var hp0 := float(tw["hp"])
	for k in 8:
		_aim_at((tw["pos"] as Vector3) + (tw["up"] as Vector3) * 30.0, tw["up"], 80.0)
		ship.fire()
		await _seconds(0.12)
	_check(is_equal_approx(float(a.targets[ti]["hp"]), hp0), "kontroltårne er pansrede mod laser")

	# ---- Tanke: kædeeksplosion
	var k0 := _first("tank")
	var tk: Dictionary = a.targets[k0]
	t = 0.0
	while a.targets[k0]["alive"] and t < 4.0:
		_aim_at((tk["pos"] as Vector3) + (tk["up"] as Vector3) * 4.0, tk["up"], 60.0)
		ship.fire()
		await _seconds(0.15)
		t += 0.15
	await _seconds(0.6)
	_check(not a.targets[k0]["alive"] and not a.targets[k0 + 1]["alive"], "tanken eksploderede og tog naboen med")

	# ---- Bomber på tårnene
	_check(a.shielded(), "reaktoren er skjoldet, mens tårnene står")
	if shots:
		var r0: Dictionary = a.targets[a.reactor_idx]
		var u0: Vector3 = r0["up"]
		var back := ((f["a"] as Vector3).slerp(f["b"], 0.85) - (f["a"] as Vector3).slerp(f["b"], 0.965)).normalized()
		ship.position = (r0["pos"] as Vector3) + u0 * 70.0 + back * 200.0
		ship.basis = Basis.looking_at(((r0["pos"] as Vector3) + u0 * 15.0 - ship.position).normalized(), u0)
		_hold()
		main.camera.snap()
		await _seconds(0.8)
		await _shot("72_reaktor_skjold")
	for i in a.targets.size():
		if a.targets[i]["kind"] != "tower":
			continue
		var tt: Dictionary = a.targets[i]
		await _bomb_from_above((tt["pos"] as Vector3) + (tt["up"] as Vector3) * (Assault.TOWER_H + 45.0), tt["up"])
		_check(not a.targets[i]["alive"], "kontroltårn %d bombet" % i)
		if shots and i == ti:
			await _shot("74_bombe")
	_check(not a.shielded(), "alle tårne væk – skjoldet er nede")
	_check(W.missions.client.get("objective", "").contains("reaktoren"), "nyt mål: %s" % W.missions.client.get("objective", ""))

	# ---- Reaktoren
	var rt: Dictionary = a.targets[a.reactor_idx]
	var bombs := 0
	while a.targets[a.reactor_idx]["alive"] and bombs < 3 and W.bombs.ammo > 0:
		await _bomb_from_above((rt["pos"] as Vector3) + (rt["up"] as Vector3) * 80.0, rt["up"])
		bombs += 1
	_check(not a.targets[a.reactor_idx]["alive"], "reaktoren er bombet (%d bomber)" % bombs)
	await _frames(3)
	_check(W.missions._m.get("phase", "") == "escape", "flugt: %s" % W.missions.client.get("objective", ""))
	if shots:
		var up: Vector3 = rt["up"]
		var back2 := ((f["a"] as Vector3).slerp(f["b"], 0.85) - (f["a"] as Vector3).slerp(f["b"], 0.965)).normalized()
		ship.position = (rt["pos"] as Vector3) + up * 200.0 + back2 * 320.0
		ship.basis = Basis.looking_at(((rt["pos"] as Vector3) - ship.position).normalized(), up)
		_hold()
		main.camera.snap()
		W.bombs.big_explosion((rt["pos"] as Vector3) + up * 20.0, 3.0)
		await _seconds(0.3)
		await _shot("73_reaktor")

	# ---- Flugt
	var cr := int(Game.wallet["credits"])
	ship.hull = 100.0
	ship.position = (rt["pos"] as Vector3) + (rt["up"] as Vector3) * 900.0
	await _seconds(0.5)
	_check(not W.missions.active, "missionen er fuldført")
	await _frames(3)
	_check(int(Game.wallet["credits"]) >= cr + int(tpl["reward"]) + 20, "belønning med bonus (+%d cr)" % (int(Game.wallet["credits"]) - cr))
	_check(not a.active(), "fæstningen er ryddet væk")

	# ---- Kollision med broer (ny fæstning)
	W.missions._server_start(W.missions._make_offer(tpl))
	await _frames(4)
	var bx: Transform3D = a.bridges[0]
	_check(a.collide(bx.origin) != Vector3.INF, "man kan ikke flyve gennem en bro")
	_check(a.collide(bx.origin - bx.basis.y.normalized() * 25.0) == Vector3.INF, "men godt under den")
	W.missions._srv_abort()
	await _frames(3)

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _first(kind: String) -> int:
	for i in W.assault.targets.size():
		if W.assault.targets[i]["kind"] == kind and W.assault.targets[i]["alive"]:
			return i
	return -1


## Placér skibet `dist` m fra målet (lidt over det) og sigt mod det.
func _aim_at(pos: Vector3, up: Vector3, dist: float) -> void:
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	ship.position = pos + side * dist + up * 12.0
	ship.basis = Basis.looking_at((pos - ship.position).normalized(), up)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship._ang = Vector3.ZERO
	ship.hull = 100.0
	ship.shield = ship.shield_max
	ship.aim_from_ray(ship.position, ship.forward())
	ship.aim_dir = ship.forward()
	ship.aim_point = pos


func _bomb_from_above(pos: Vector3, up: Vector3) -> void:
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	ship.position = pos
	ship.basis = Basis.looking_at(side, up)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship.hull = 100.0
	W.bombs.cool = 0.0
	ship.drop_bomb()
	for k in 300:
		ship.position = pos
		ship.speed = 0.0
		ship.hull = 100.0
		await get_tree().physics_frame
		if W.bombs._b.is_empty():
			break
	await _seconds(0.3)


func _flak_hits(floor_d: Vector3, alt: float) -> int:
	var p := W.assault.planet
	var hits := 0
	var t := 0.0
	ship.position = p.position + floor_d * (p.surface_radius(floor_d) + alt)
	while t < 8.0:
		ship.position = p.position + floor_d * (p.surface_radius(floor_d) + alt)
		ship.speed = 0.0
		var before := ship.shield + ship.hull
		await _seconds(0.1)
		t += 0.1
		if ship.shield + ship.hull < before - 0.01:
			hits += 1
		ship.hull = 100.0
		ship.shield = ship.shield_max
	return hits


func _hold() -> void:
	ship.speed = 0.0
	ship.throttle = 0.0
	ship._ang = Vector3.ZERO
	ship.reset_physics_interpolation()


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
