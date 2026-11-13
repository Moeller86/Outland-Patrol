extends Node
## Test af scanner, fund på planeterne og eftersøgningsmissionen (solo). Kør headless:
##   godot --headless --path . res://tests/site_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_sites.json"
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
	ship = main.local_ship
	ship.steering = false
	var sites: Sites = W.sites
	var uni: Universe = main.universe

	# ---- Placering
	_check(sites.sites.size() >= 20, "fund på planeterne (%d)" % sites.sites.size())
	var on_ground := true
	for s in sites.sites:
		var p := uni.planet(s["planet"])
		if absf(p.ground_altitude(s["pos"])) > 1.0 or absf(p.ground_altitude(s["land"])) > 1.0:
			on_ground = false
	_check(on_ground, "alle fund ligger på jorden")
	var kinds := {}
	for s in sites.sites:
		kinds[s["kind"]] = true
	_check(kinds.size() == 4, "alle fire slags fund findes")

	# ---- Nærbilleder af fundene (kun med skærm)
	if shots:
		var cam := Camera3D.new()
		cam.fov = 60.0
		main.world.add_child(cam)
		cam.make_current()
		for kind: String in ["vrag", "ruin", "forsyning", "piratlejr"]:
			var s := _site("viridia", kind)
			if s.is_empty():
				s = _site("", kind)
			var up: Vector3 = s["dir"]
			var t: Vector3 = s["tangent"]
			var side := up.cross(t).normalized()
			var c: Vector3 = (s["pos"] as Vector3) + up * 4.0
			ship.position = c + up * 400.0
			cam.position = c + up * 16.0 + side * 26.0 - t * 18.0
			cam.look_at(c, up)
			await _seconds(1.0)
			await _shot("19_fund_" + kind)
		cam.queue_free()
		main.camera.make_current()
		for s in sites.sites:
			sites.known.erase(s["id"])
		W.pirates.server_despawn_tag("camp_" + str(_site("viridia", "piratlejr").get("id", "")))
		for s in sites.sites:
			W.pirates.server_despawn_tag("camp_" + str(s["id"]))
			s["armed"] = false

	# ---- Scanner
	var vir := uni.planet("viridia")
	var pod := _site("viridia", "forsyning")
	ship.position = (pod["pos"] as Vector3) + (pod["dir"] as Vector3) * 500.0
	await _frames(2)
	_check(sites.known.is_empty(), "intet fundet før scanning")
	ship.steering = true
	ship.scan()
	ship.steering = false
	_check(sites.known.has(pod["id"]), "scanneren finder kapslen 500 m nede")
	_check(sites.scan(ship.position) == -1, "scanneren skal lade op")
	await _frames(3)
	_check(_marker_text().contains("FORSYNING"), "HUD viser fundet")
	if shots:
		ship.basis = Basis.looking_at(-(pod["dir"] as Vector3), (pod["tangent"] as Vector3))
		main.camera.snap()
		await _seconds(0.5)
		await _shot("20_scanning")

	# ---- Forsyningskapsel: repararer
	ship.hull = 40.0
	var cr := int(Game.wallet["credits"])
	await _land(pod)
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "site:" + str(pod["id"]), "landet ved kapslen")
	_check(main.site_menu.visible and not main.site_menu._action.disabled, "fundmenuen er åben med en handling")
	if shots:
		await _shot("21_fundmenu_kapsel")
	main.site_menu._on_action()
	await _seconds(0.3)
	_check(ship.hull == 100.0, "skroget er repareret")
	_check(int(Game.wallet["credits"]) == cr + 25, "+25 cr fra kapslen")
	_check(pod["looted"] and main.site_menu._action.disabled, "kapslen er tom bagefter")
	main.site_menu.launch_requested.emit()
	await _frames(3)
	_check(ship.state == Ship.State.FLY and not main.site_menu.visible, "letter fra fundet")
	_check(vir.ground_altitude(ship.position) > 3.0, "skibet er over jorden efter afgang")

	# ---- Vrag: last
	var wreck := _site("", "vrag")
	var cargo := Game.cargo_total(Game.wallet["cargo"])
	await _land(wreck)
	main.site_menu._on_action()
	await _seconds(0.3)
	_check(Game.cargo_total(Game.wallet["cargo"]) > cargo, "last bjærget fra vraget (%d)" % Game.cargo_total(Game.wallet["cargo"]))
	if shots:
		await _shot("22_fundmenu_vrag")
	main.site_menu.launch_requested.emit()
	await _frames(2)

	# ---- Ruin: erfaring
	var ruin := _site("", "ruin")
	var xp := int(Game.wallet["xp"])
	await _land(ruin)
	main.site_menu._on_action()
	await _seconds(0.3)
	_check(int(Game.wallet["xp"]) == xp + 40, "+40 xp fra ruinen")
	_check(main.site_menu._result.text.length() > 20, "ruinen fortæller et stykke historie")
	if shots:
		await _shot("23_fundmenu_ruin")
	main.site_menu.launch_requested.emit()
	await _frames(2)

	# ---- Piratlejr
	var camp := _site("", "piratlejr")
	var tag := "camp_" + str(camp["id"])
	ship.position = (camp["pos"] as Vector3) + (camp["dir"] as Vector3) * 200.0
	await _seconds(0.3)
	_check(W.pirates.server_count_tag(tag) >= 3, "lejren sender pirater op (%d)" % W.pirates.server_count_tag(tag))
	_check(not sites.action_for(camp["id"])["enabled"], "lejren kan ikke plyndres, mens den forsvares")
	if shots:
		ship.basis = Basis.looking_at(-(camp["dir"] as Vector3) * 0.8 + (camp["tangent"] as Vector3) * 0.6, camp["dir"])
		main.camera.snap()
		await _seconds(0.6)
		await _shot("24_piratlejr")
	await _kill_tag(tag)
	await _seconds(0.3)
	_check(camp["cleared"], "lejren er ryddet")
	cr = int(Game.wallet["credits"])
	await _land(camp)
	main.site_menu._on_action()
	await _seconds(0.3)
	_check(int(Game.wallet["credits"]) >= cr + 150, "lejren plyndret (+150 cr)")
	main.site_menu.launch_requested.emit()
	await _frames(2)

	# ---- Eftersøgning
	var ms: Missions = W.missions
	var tpl := {}
	for t: Dictionary in Game.mission_data["templates"]:
		if t["id"] == "search_sahra":
			tpl = t
	ms._server_start(ms._make_offer(tpl))
	await _frames(3)
	_check(ms.active and ms._m["phase"] == "search", "eftersøgning startet")
	var msite := sites.get_site(ms._m["site"])
	_check(not msite.is_empty() and msite["planet"] == "sahra", "vraget ligger på Sahra")
	_check(str(ms.client.get("objective", "")).contains("scan"), "opgaven siger: scan")
	var area: Vector3 = ms._m["area"]
	ship.position = area
	await _frames(2)
	ship.steering = true
	sites.scan_cool = 0.0
	ship.scan()
	ship.steering = false
	await _frames(3)
	_check(ms._m["phase"] == "land", "scanneren fandt vraget: land")
	_check(W.pirates.server_count_tag(ms._m["tag"]) >= 2, "pirater dukker op ved vraget")
	await _kill_tag(ms._m["tag"])
	await _land(msite)
	_check(main.site_menu._action.text == "BJÆRG DEN SORTE BOKS", "missionshandlingen: sort boks")
	if shots:
		await _shot("25_sort_boks")
	main.site_menu._on_action()
	await _seconds(0.3)
	_check(ms._m["phase"] == "return", "sort boks bjærget: flyv hjem")
	main.site_menu.launch_requested.emit()
	await _frames(2)
	await _kill_tag(ms._m["tag"])
	var results: Array = []
	ms.mission_ended.connect(func(r: Dictionary): results.append(r))
	var base := uni.station("concord_base")
	ship.position = base.dock_pos + base.dock_dir * 20.0
	await _seconds(0.5)
	_check(results.size() == 1 and results[0]["success"], "eftersøgning fuldført")
	await _frames(3)
	_check(sites.get_site(msite.get("id", "")).is_empty(), "missionsvraget er fjernet")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _site(planet: String, kind: String) -> Dictionary:
	for s in W.sites.sites:
		if s["kind"] == kind and (planet == "" or s["planet"] == planet) and not s["looted"] and s["mission"] == "":
			return s
	return {}


func _land(s: Dictionary) -> void:
	var up: Vector3 = s["land_up"]
	ship.state = Ship.State.FLY
	ship.position = (s["land"] as Vector3) + up * 12.0
	ship.basis = Basis.looking_at(s["tangent"], up)
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.0)


func _kill_tag(tag: String) -> void:
	for k in 60:
		if W.pirates.server_count_tag(tag) == 0:
			return
		var i := 0
		while i < Pirates.POOL:
			if W.pirates._p[i]["active"] and W.pirates._p[i]["tag"] == tag:
				W.pirates.server_damage(i, 10.0)
			i += 1
		ship.hull = 100.0
		await _frames(2)


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
