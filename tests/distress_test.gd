extends Node
## Nødkald: fragtskibet skal kunne nås og eskorteres, før det bliver skudt ned.

var main: Node
var failures := 0


func _ready() -> void:
	Game.save_path = "user://test_distress.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Eskorte")
	await _frames(5)
	var ship: Ship = main.local_ship
	ship.steering = false
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	for id in ["distress", "distress_hard"]:
		var tpl := {}
		for t: Dictionary in Game.mission_data["templates"]:
			if t["id"] == id:
				tpl = t
		var st := W.universe.station(tpl["from"])
		ship.position = st.dock_pos + st.dock_dir * 40.0
		ship.speed = 0.0
		ship.reset_physics_interpolation()
		W.missions._server_start(W.missions._make_offer(tpl))
		await _frames(3)
		var esc: Dictionary = W.missions._m["escort"]
		var far := ship.position.distance_to(esc["pos"])
		var travel := far / 70.0
		_check(float(W.missions._m["timer"]) > travel + 20.0, "%s: tid nok til at nå frem (%d s til %d m)" % [id, int(W.missions._m["timer"]), int(far)])
		# Flyv derud med efterbrænderfart (ca. 70 m/s)
		var t := 0.0
		while t < travel and W.missions.active:
			ship.position = ship.position.move_toward(esc["pos"], 70.0 / 10.0)
			ship.hull = 100.0
			ship.shield = ship.shield_max
			await _seconds(0.1)
			t += 0.1
		var hp_arrive := float(esc["hp"]) / float(esc["max"])
		_check(W.missions.active and esc["alive"] and hp_arrive > 0.5, "%s: fragtskibet lever ved ankomst (%d %%)" % [id, int(hp_arrive * 100.0)])
		# Realistisk kamp: piraterne angriber i 30 s, før man får skudt dem ned
		t = 0.0
		while t < 30.0 and W.missions.active:
			ship.position = (esc["pos"] as Vector3) + Vector3(0, 30, 0)
			ship.hull = 100.0
			ship.shield = ship.shield_max
			await _seconds(0.5)
			t += 0.5
		_check(W.missions.active and esc["alive"], "%s: fragtskibet holder 30 s kamp (%d %%)" % [id, int(100.0 * float(esc["hp"]) / float(esc["max"]))])
		# Kæmp: skyd piraterne ned (lidt ad gangen)
		t = 0.0
		while W.missions.active and W.missions._m["phase"] != "escort" and t < 40.0:
			ship.position = (esc["pos"] as Vector3) + Vector3(0, 30, 0)
			ship.hull = 100.0
			ship.shield = ship.shield_max
			for i in Pirates.POOL:
				if W.pirates.is_active(i) and W.pirates._p[i]["tag"] == W.missions._m["tag"]:
					W.pirates.server_damage(i, 1.0)
					break
			await _seconds(0.5)
			t += 0.5
		_check(W.missions.active and W.missions._m["phase"] == "escort", "%s: piraterne er væk efter %.0f s – eskorte begynder (%d %%)" % [id, t, int(100.0 * float(esc["hp"]) / float(esc["max"]))])
		# Eskortér: følg med, skyd bagholdet ned
		t = 0.0
		while W.missions.active and t < 240.0:
			ship.position = (esc["pos"] as Vector3) + Vector3(0, 25, 30)
			ship.hull = 100.0
			ship.shield = ship.shield_max
			if fmod(t, 1.5) < 0.25:
				for i in Pirates.POOL:
					if W.pirates.is_active(i) and W.pirates._p[i]["tag"] == W.missions._m["tag"]:
						W.pirates.server_damage(i, 1.0)
						break
			await _seconds(0.25)
			t += 0.25
		_check(not W.missions.active and main.debrief._head.text.contains("FULDFØRT"), "%s: fragtskibet landede (%s, %.0f s)" % [id, main.debrief._head.text, t])
		main.debrief.visible = false
		await _seconds(0.5)
	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
