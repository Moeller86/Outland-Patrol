extends Node
## Missionstest (solo). Kør headless:
##   godot --headless --path . res://tests/mission_test.tscn
## Nødkald (succes og fiasko), Patruljesweep, debriefing, rang og gem/indlæs.

var main: Node
var failures := 0
var results: Array = []


func _ready() -> void:
	Game.save_path = "user://test_mission.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await _frames(3)
	Net.start_solo("Testpilot")
	await _frames(5)
	var ship: Ship = main.local_ship
	ship.steering = false
	var ms: Missions = W.missions
	ms.mission_ended.connect(func(r: Dictionary): results.append(r))
	_check(ms.board.size() == 3, "missionstavlen har 3 tilbud")

	# Start docket i Bastion Kepler med missionstavlen åben
	var st := W.universe.station("concord_base")
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "concord_base", "starter docket i Bastion Kepler")
	_check(main.menu.visible and main.menu._tabs.current_tab == 0, "basens menu åbner på missionstavlen")
	_check(not main.menu._tabs.is_tab_hidden(1), "Bastion-fanen vises på basen")
	_check(not ("laser" in Game.location_upgrades("concord_base")), "våbenlageret er låst fra start")
	_check(main.menu._board.get_child_count() >= 4, "tavlen viser missionerne")
	main.menu.launch_requested.emit()
	await _frames(2)

	# ---- Nødkald: succes
	var distress := _offer("distress")
	await _accept(distress)
	_check(ms.active and str(ms.client.get("objective", "")).begins_with("Nå frem"), "nødkald startet: %s" % ms.client.get("objective", ""))
	_check(_tagged() >= 3, "piraterne angriber fragtskibet (%d)" % _tagged())
	var esc: Dictionary = ms._m["escort"]
	ship.position = (esc["pos"] as Vector3) + Vector3(0, 30, 90)
	await _frames(3)
	_check(ms._m["phase"] == "fight", "fremme ved fragtskibet: kamp")
	Engine.time_scale = 4.0
	var t := 0.0
	while ms.active and t < 90.0:
		_keep_alive(ship)
		_shoot_tagged()
		if ms.active and ms._m.get("escort", {}).has("pos"):
			ship.position = (ms._m["escort"]["pos"] as Vector3) + Vector3(0, 25, 60)
		await _seconds(0.5)
		t += 0.5
	Engine.time_scale = 1.0
	_check(results.size() == 1 and results[0]["success"], "nødkald fuldført: %s" % (results[0]["reason"] if results.size() > 0 else "intet resultat"))
	_check(int(Game.wallet["credits"]) >= 100 + 180, "løn udbetalt (%d cr)" % Game.wallet["credits"])
	_check(int(Game.wallet["xp"]) == 60, "erfaring +60")
	_check(main.debrief.visible and main.debrief._head.text == "MISSION FULDFØRT", "debriefing vises")
	main.debrief._close()
	_check(ms.board.size() == 3, "ny tavle efter missionen")

	# ---- Nødkald: fiasko (for sent)
	await _accept(_offer("distress"))
	ms._m["timer"] = 0.5
	await _seconds(1.0)
	_check(results.size() == 2 and not results[1]["success"], "fiasko når man ikke når frem")
	_check(int(Game.wallet["xp"]) == 75, "trøste-erfaring ved fiasko (+15)")
	_check(_tagged() == 0, "missionens pirater fjernet efter fiasko")
	main.debrief._close()

	# ---- Patruljesweep
	await _accept(_offer("sweep_kepler"))
	_check(ms.client.get("type", "") == "sweep" and ms._beacon.visible, "patrulje startet med navigationsbøje")
	for k in 3:
		_keep_alive(ship)
		ship.position = (ms._m["target"] as Vector3) + Vector3(0, 10, 30)
		await _frames(3)
		_check(ms._m["phase"] == "clear", "baghold ved bøje %d" % (k + 1))
		for r in 20:
			_shoot_tagged()
			await _frames(2)
			if _tagged() == 0:
				break
		await _frames(3)
	_check(ms._m.get("phase", "") == "return", "alle bøjer klaret, meld tilbage")
	ship.position = st.dock_pos + st.dock_dir * 40.0
	await _frames(3)
	_check(results.size() == 3 and results[2]["success"], "patruljesweep fuldført")
	_check(int(Game.wallet["xp"]) == 125 and Game.rank_name(125) == "Pilot", "forfremmet til Pilot (125 xp)")
	_check(main.debrief._rankup.visible, "debriefing viser forfremmelse")
	_check(Game.base_level() == 2, "basen har 2 fuldførte missioner")
	_check(str(results[2].get("unlocked", "")) == "Våbenlager" and main.debrief._base.text.contains("Våbenlager"), "debriefing: basen udvidet med våbenlager")
	_check("laser" in Game.location_upgrades("concord_base"), "Laser Mk II kan nu købes på basen")
	var armory: Node3D = W.universe.station("concord_base")._modules["armory"]
	_check(armory.visible, "våbenlageret er synligt på basen i 3D")
	main.debrief._close()

	# ---- Gem og indlæs
	var credits := int(Game.wallet["credits"])
	Game.server_save()
	_check(FileAccess.file_exists(Game.save_path), "spillet gemt")
	Net.leave()
	await _frames(3)
	Net.start_solo("Testpilot")
	await _frames(5)
	_check(int(Game.wallet["credits"]) == credits and int(Game.wallet["xp"]) == 125, "pilot indlæst igen (%d cr, %d xp)" % [Game.wallet["credits"], Game.wallet["xp"]])
	_check(Game.base_level() == 2, "basens fremskridt indlæst igen")
	Net.start_solo("Ny pilot")
	await _frames(5)
	_check(int(Game.wallet["credits"]) == Game.START_CREDITS and int(Game.wallet["xp"]) == 0, "ny pilot starter forfra")

	# Forsvarstårne (åbnes ved 8 missioner) skyder pirater nær basen
	Game.world["missions_completed"] = 8
	Game._cl_world.rpc(Game.world)
	await _frames(2)
	var base := W.universe.station("concord_base")
	_check(base._modules["turrets"].visible, "forsvarstårnene er bygget")
	var pi := W.pirates.server_spawn_at("kepler", base.position + Vector3(0, 40, 150), base.position, "")
	Engine.time_scale = 4.0
	await _seconds(12.0)
	Engine.time_scale = 1.0
	_check(not W.pirates._p[pi]["active"], "tårnene skød piraten ned")

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit(1 if failures else 0)


func _offer(tid: String) -> Dictionary:
	for t: Dictionary in Game.mission_data["templates"]:
		if t["id"] == tid:
			return W.missions._make_offer(t)
	return {}


func _accept(o: Dictionary) -> void:
	W.missions.board = [o]
	W.missions.request_accept(int(o["oid"]))
	await _frames(3)


func _tagged() -> int:
	if not W.missions.active:
		return W.pirates.server_count_tag("m%d" % (W.missions._next_oid - 1))
	return W.pirates.server_count_tag(W.missions._m["tag"])


func _shoot_tagged() -> void:
	if not W.missions.active:
		return
	for i in Pirates.POOL:
		var p: Dictionary = W.pirates._p[i]
		if p["active"] and p["tag"] == W.missions._m["tag"]:
			for k in 6:
				W.pirates.hit_test((p["node"] as Node3D).position, (p["node"] as Node3D).position, 1.0)


func _keep_alive(ship: Ship) -> void:
	ship.hull = 100.0
	ship.shield = ship.shield_max


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
