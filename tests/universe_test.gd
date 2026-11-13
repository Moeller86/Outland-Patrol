extends Node
## Test af det udvidede univers (5 systemer, jump gates mellem dem) og skibstyperne.
##   godot --headless --path . res://tests/universe_test.tscn
## Med skærm (uden --headless) gemmes også skærmbilleder i user://screenshots/.

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_universe.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	if shots:
		Net.chosen_ship = "bison"
		main.title._select_ship("bison")
		await _seconds(1.0)
		await _shot("60_titel_skibsvalg")
	Net.chosen_ship = "hveps"
	Net.start_solo("Testpilot")
	await _frames(5)
	ship = main.local_ship
	ship.steering = false
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	var uni: Universe = main.universe

	# ---- Startskib
	_check(ship.ship_class == "hveps" and ship.model.ship_class == "hveps", "ny pilot starter i det valgte skib (Hveps)")
	_check(int(Game.wallet["cargo_max"]) == 8, "Hveps har et mindre lastrum (8)")
	_check(is_equal_approx(float(ship.handling["max_speed"]), 72.0), "Hveps er hurtigere (72)")
	_check(ship.shield_max == 40.0, "Hveps har 40 skjold")

	# ---- Universet
	_check(Game.systems.size() == 5, "5 systemer (%d)" % Game.systems.size())
	_check(uni.planets.size() == 10, "10 planeter (%d)" % uni.planets.size())
	var reach := {"kepler": true}
	var queue := ["kepler"]
	while not queue.is_empty():
		var sys: String = queue.pop_front()
		for gid: String in uni.gates:
			var g: Dictionary = uni.gates[gid]
			if g["system"] == sys:
				var dest: String = uni.gates[g["to"]]["system"]
				_check(uni.gates[g["to"]]["to"] == gid, "gate %s ↔ %s går begge veje" % [gid, g["to"]])
				if not reach.has(dest):
					reach[dest] = true
					queue.append(dest)
	_check(reach.size() == 5, "alle systemer kan nås via jump gates (%d)" % reach.size())
	_check(W.gate_towards("kepler", "ravne").get("id", "") == "kepler_gate_s", "ruten til Ravnebæltet går via Solhavn")
	_check(W.gate_towards("kepler", "ekko").get("id", "") == "kepler_gate", "ruten til Ekkoet går via Frosta")
	# Hop Kepler → Solhavn → Ravnebæltet
	for gid: String in ["kepler_gate_s", "solhavn_gate_r"]:
		var g: Dictionary = uni.gates[gid]
		ship.state = Ship.State.FLY
		ship.position = (g["pos"] as Vector3) - (g["dir"] as Vector3) * 30.0
		ship.basis = Basis.looking_at(g["dir"], Vector3.UP)
		ship.speed = 20.0
		ship.throttle = 0.3
		ship._gate_cool = 0.0
		var t := 0.0
		while ship.state != Ship.State.JUMP and t < 4.0:
			ship.position += (g["dir"] as Vector3) * 2.0
			await _frames(1)
			t += 0.016
		await _seconds(1.8)
		var dest: String = uni.gates[g["to"]]["system"]
		_check(uni.system_at(ship.position) == dest, "hop gennem %s lander i %s" % [gid, Game.systems[dest]["name"]])
		if shots:
			main.camera.snap()
			await _seconds(1.0)
			await _shot("61_system_" + dest)
	# Land på alle nye planeter
	for pid: String in ["aurum", "thalassa", "korvus", "obelisk", "nadir"]:
		var p := uni.planet(pid)
		var pad: Dictionary = p.pads[0]
		ship.state = Ship.State.FLY
		ship.position = (pad["top"] as Vector3) + (pad["dir"] as Vector3) * 10.0
		ship.speed = 3.0
		await _frames(2)
		ship.try_land()
		await _seconds(2.0)
		_check(ship.docked_at == pid and main.menu.visible and Game.markets.has(pid), "landet på %s – menu og marked" % p.display_name)
		if shots and pid in ["aurum", "obelisk"]:
			await _shot("62_menu_" + pid)
		main.menu.launch_requested.emit()
		await _frames(2)
	if shots:
		for pid: String in ["thalassa", "korvus", "obelisk", "nadir"]:
			var p := uni.planet(pid)
			ship.position = p.position + (p.pad_dir + p.tangent * 0.8).normalized() * (p.radius * 2.6)
			ship.basis = Basis.looking_at((p.position - ship.position).normalized(), Vector3.UP)
			main.camera.snap()
			await _seconds(1.0)
			await _shot("63_planet_" + pid)

	# ---- Værft i Solhavn
	var st := uni.station("solhavn_station")
	ship.state = Ship.State.FLY
	ship.position = st.dock_pos + st.dock_dir * 8.0
	ship.speed = 3.0
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(Game.has_shipyard("solhavn_station") and not main.menu._tabs.is_tab_hidden(3), "Solhavn Handelsring har et værft")
	Game.server_reward(multiplayer.get_unique_id(), 3000, 0)
	await _frames(2)
	Game.request_ship("solhavn_station", "albatros")
	await _frames(4)
	_check(ship.ship_class == "albatros" and ship.model.ship_class == "albatros", "Albatros købt og taget i brug")
	_check(int(Game.wallet["cargo_max"]) == 24, "Albatros har lastrum 24 (%d)" % int(Game.wallet["cargo_max"]))
	_check("hveps" in Game.owned_ships() and "albatros" in Game.owned_ships(), "begge skibe ejes")
	var cr := int(Game.wallet["credits"])
	Game.request_ship("solhavn_station", "hveps")
	await _frames(4)
	_check(ship.ship_class == "hveps" and int(Game.wallet["credits"]) == cr, "skift tilbage til Hveps er gratis")
	if shots:
		main.menu._tabs.current_tab = 3
		await _seconds(0.3)
		await _shot("64_vaerft")
	# Panser: Bison tager mindre skade (et tredje skib kræver en base)
	Game.world["bases"] = {W.bases.plot_ids()[0]: {"owned": true, "modules": {}, "storage": 0, "hp": 600.0}}
	Game.request_ship("solhavn_station", "bison")
	await _frames(4)
	main.menu.launch_requested.emit()
	await _frames(3)
	ship.shield = 0.0
	ship.hull = 100.0
	ship.take_damage(10.0)
	_check(is_equal_approx(ship.hull, 94.0), "Bisons panser tager 40 %% af skaden (skrog %.1f)" % ship.hull)
	Game.server_save()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check(saved["pilots"]["Testpilot"]["ship"] == "bison" and (saved["pilots"]["Testpilot"]["ships"] as Array).size() == 3, "skib og flåde er gemt")

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


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://screenshots/%s.png" % shot_name)
