extends Node
## Free roam: civil trafik, opkald (H), opslagstavler og sideopgaver.
## Kør headless:  godot --headless --path . res://tests/roam_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship
var me := 0


func _ready() -> void:
	Game.save_path = "user://test_roam.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Vagabond")
	await _frames(6)
	ship = main.local_ship
	ship.steering = false
	me = multiplayer.get_unique_id()
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	var tr: Traffic = W.traffic

	# ---- Trafik
	var n0 := tr.positions_in("kepler").size()
	_check(n0 >= 4, "civil trafik i Kepler (%d skibe)" % n0)
	var i := _npc_in("kepler")
	var p0 := tr.position_of(i)
	await _seconds(1.0)
	_check(tr.position_of(i).distance_to(p0) > 20.0, "skibene flyver (%d m på 1 s)" % int(tr.position_of(i).distance_to(p0)))
	_check((tr._n[i]["node"] as ShipModel).visible, "synlige i spillerens system")

	# ---- Opkald: handel
	tr._n[i]["offer"] = "handel"
	_near(i)
	await _frames(2)
	_check(main.hud._hail_hint.visible and main.hud._hail_hint.text.contains("kald"), "hjælpetekst: %s" % main.hud._hail_hint.text)
	Game.server_reward(me, 1000, 0)
	await _frames(2)
	var cr := int(Game.wallet["credits"])
	_press_hail()
	await _frames(4)
	_check(main.comm_panel.visible and main.comm_panel._opts.get_child_count() == 2, "kanalen er åben med to svar")
	_check(not ship.steering, "styringen er sluppet under samtalen")
	if shots:
		await _shot("A0_opkald")
	_choose(0)
	await _frames(4)
	_check(Game.cargo_total(Game.wallet["cargo"]) == 4 and int(Game.wallet["credits"]) < cr, "købte 4 varer billigt (%d cr)" % (cr - int(Game.wallet["credits"])))
	main.comm_panel.close()
	await _frames(2)
	_check(ship.steering, "styringen er tilbage")

	# ---- Opkald: levering
	tr._n[i]["offer"] = "levering"
	_near(i)
	_press_hail()
	await _frames(4)
	_choose(0)
	await _frames(4)
	_check(W.jobs.mine.size() == 1 and W.jobs.mine[0]["type"] == "levering", "pakke modtaget: %s" % (W.jobs.mine[0]["title"] if not W.jobs.mine.is_empty() else "-"))
	main.comm_panel.close()
	var dest: String = W.jobs.mine[0]["to"]
	cr = int(Game.wallet["credits"])
	W.jobs.request_landed(dest)
	await _frames(4)
	_check(W.jobs.mine.is_empty() and int(Game.wallet["credits"]) > cr, "leveret på %s (+%d cr)" % [Jobs.loc_name(dest), int(Game.wallet["credits"]) - cr])

	# ---- Opkald: tip
	var j := _npc_in("kepler", i)
	tr._n[j]["offer"] = "tip"
	_near(j)
	_press_hail()
	await _frames(4)
	var has_tip: bool = main.comm_panel._opts.get_child_count() == 2
	_choose(0)
	await _frames(4)
	_check(has_tip and not W.waypoint.is_empty() and W.waypoint.get("system", "") == "kepler", "tippet satte en markering: %s" % W.waypoint.get("label", ""))
	main.comm_panel.close()

	# ---- Opkald: eskorte
	tr._n[j]["offer"] = "eskorte"
	_near(j)
	_press_hail()
	await _frames(4)
	_choose(0)
	await _frames(4)
	main.comm_panel.close()
	_check(W.jobs.mine.size() == 1 and W.jobs.mine[0]["type"] == "eskorte" and not (tr._n[j]["escort"] as Dictionary).is_empty(), "eskorte begyndt")
	var edest: String = W.jobs.mine[0]["to"]
	if shots:
		await _seconds(0.3)
		await _shot("A1_eskorte")
	# Hop frem: skibet når næsten frem, og vi er tæt på
	var goal := Jobs.loc_pos(edest)
	(tr._n[j]["node"] as Node3D).position = goal + Vector3(0, 120, 0)
	ship.position = goal + Vector3(30, 140, 0)
	cr = int(Game.wallet["credits"])
	var t := 0.0
	while not W.jobs.mine.is_empty() and t < 15.0:
		ship.position = tr.position_of(j) + Vector3(30, 20, 0)
		ship.hull = 100.0
		await _seconds(0.25)
		t += 0.25
	_check(W.jobs.mine.is_empty() and int(Game.wallet["credits"]) > cr, "eskorten nåede frem (+%d cr)" % (int(Game.wallet["credits"]) - cr))
	W.pirates.server_despawn_tag("job_esc_%d" % W.jobs.last_id)

	# ---- Opslagstavle
	ship.position = W.universe.station("kepler_station").dock_pos + Vector3(0, 0, 0)
	ship.speed = 2.0
	ship.reset_physics_interpolation()
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and main.menu.visible, "landet på Kepler Station")
	await _frames(4)
	var offers: Array = W.jobs.board_cache.get("kepler_station", [])
	_check(offers.size() == Jobs.BOARD_SIZE, "opslagstavlen har %d opslag" % offers.size())
	main.menu._tabs.current_tab = 5
	await _frames(3)
	if shots:
		await _seconds(0.3)
		await _shot("A2_opslagstavle")
	W.jobs.request_accept("kepler_station", offers[0]["oid"])
	await _frames(4)
	_check(W.jobs.mine.size() == 1 and (W.jobs.board_cache["kepler_station"] as Array).size() == Jobs.BOARD_SIZE - 1, "tog opgaven fra tavlen")
	W.jobs.request_abandon(int(W.jobs.mine[0]["id"]))
	await _frames(4)
	_check(W.jobs.mine.is_empty(), "opgaven kan opgives")
	main.menu.launch_requested.emit()
	await _frames(3)

	# ---- Jagt
	var sp := ship.position + Vector3(0, 0, -600)
	W.jobs.server_add(me, {"type": "jagt", "pos": sp, "n": 2, "reward": 200, "xp": 30, "time": 300.0, "title": "Piratjagt", "system": "kepler"})
	await _frames(3)
	var tag := "job_%d" % W.jobs.last_id
	_check(W.pirates.server_count_tag(tag) == 2, "to jobpirater er sat ud")
	cr = int(Game.wallet["credits"])
	for k in Pirates.POOL:
		if W.pirates.is_active(k) and W.pirates._p[k]["tag"] == tag:
			W.pirates.server_damage(k, 99.0)
	await _seconds(1.0)
	_check(W.jobs.mine.is_empty() and int(Game.wallet["credits"]) >= cr + 200, "piratjagten er fuldført")

	# ---- Bjærgning
	var wp := ship.position + ship.forward() * 60.0
	W.jobs.server_add(me, {"type": "bjaergning", "pos": wp, "n": 3, "reward": 180, "xp": 20, "time": 300.0, "title": "Bjærgning af et vrag", "system": "kepler"})
	await _frames(4)
	_check(W.jobs._wrecks.size() == 1, "vraget ligger i rummet")
	if shots:
		ship.basis = Basis.looking_at((wp - ship.position).normalized(), Vector3.UP)
		ship.reset_physics_interpolation()
		main.camera.snap()
		await _seconds(0.5)
		await _shot("A3_vrag")
	# Tøm lastrummet først (der skal være plads)
	Game.players[me]["cargo"] = {}
	Game._send_wallet(me)
	t = 0.0
	while not W.jobs.mine.is_empty() and t < 12.0:
		for id: int in W.pickups._items:
			if W.pickups._items[id]["kind"] == "vragdel":
				ship.position = (W.pickups._items[id]["node"] as Node3D).position
				break
		ship.speed = 0.0
		await _seconds(0.2)
		t += 0.2
	_check(W.jobs.mine.is_empty() and W.jobs._wrecks.is_empty(), "vragdelene er samlet op – bjærgningen er fuldført (%.1f s)" % t)

	# ---- Fragt
	var fdest := "viridia"
	W.jobs.server_add(me, {"type": "fragt", "to": fdest, "good": "frugt", "n": 3, "reward": 150, "xp": 20, "time": 300.0, "title": "Fragt: 3 frugt til Viridia"})
	await _frames(3)
	W.jobs.request_landed(fdest)
	await _frames(3)
	_check(W.jobs.mine.size() == 1, "uden varerne kan fragten ikke afleveres")
	for k in 3:
		Game.server_add_cargo(me, "frugt")
	W.jobs.request_landed(fdest)
	await _frames(3)
	_check(W.jobs.mine.is_empty() and int(Game.wallet["cargo"].get("frugt", 0)) == 0, "fragten er afleveret")

	# ---- Højst 3 opgaver, og tiden kan løbe ud
	for k in 4:
		W.jobs.server_add(me, {"type": "levering", "to": "viridia", "reward": 50, "time": 300.0})
	await _frames(3)
	_check(W.jobs.mine.size() == Jobs.MAX_JOBS, "højst %d opgaver ad gangen" % Jobs.MAX_JOBS)
	for jj: Dictionary in W.jobs._jobs.values():
		jj["time_left"] = 0.1
	await _seconds(1.2)
	_check(W.jobs.mine.is_empty(), "opgaver udløber, når tiden er gået")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _npc_in(sys_id: String, not_i := -1) -> int:
	for k in W.traffic._n.size():
		if W.traffic._n[k]["system"] == sys_id and W.traffic._n[k]["alive"] and k != not_i:
			return k
	return -1


func _near(i: int) -> void:
	var p := W.traffic.position_of(i)
	ship.position = p + Vector3(0, 15, 60)
	ship.basis = Basis.looking_at((p - ship.position).normalized(), Vector3.UP)
	ship.speed = 0.0
	ship.state = Ship.State.FLY
	ship.reset_physics_interpolation()
	main.camera.snap()


func _press_hail() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = Game.key_of("hail")
	ev.pressed = true
	main._unhandled_input(ev)


func _choose(k: int) -> void:
	var opts: VBoxContainer = main.comm_panel._opts
	if k < opts.get_child_count():
		(opts.get_child(k) as Button).pressed.emit()


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
