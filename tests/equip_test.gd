extends Node
## Udstyr (våben, skjold, motor, specialudstyr), traktorstråle og samlede masker.
## Kør headless:  godot --headless --path . res://tests/equip_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship
var me := 0


func _ready() -> void:
	Game.save_path = "user://test_equip.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Mekaniker")
	await _frames(6)
	ship = main.local_ship
	ship.steering = false
	me = multiplayer.get_unique_id()
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0

	# ---- Samlede masker (færre tegnekald)
	_check(_meshes(ship.model) <= 24, "skibet er samlet i få masker (%d)" % _meshes(ship.model))
	var base := W.universe.station("concord_base")
	_check(_meshes(base) < 140, "Concord-basen er samlet (%d masker)" % _meshes(base))
	var vir := W.universe.planet("viridia")
	var city: Node3D = vir.get_node("Pad_viridia")
	_check(_meshes(city) > 0 and _meshes(city) < 120, "Viridias storby er samlet (%d masker)" % _meshes(city))

	# ---- Land på Kepler Station: udstyrsfanen
	var st := W.universe.station("kepler_station")
	ship.position = st.dock_pos
	ship.speed = 2.0
	ship.reset_physics_interpolation()
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and main.menu.visible, "landet på Kepler Station")
	_check(not main.menu._tabs.is_tab_hidden(6), "fanen Udstyr findes på stationen")
	Game.server_reward(me, 8000, 0)
	await _frames(3)
	main.menu._tabs.current_tab = 6
	await _frames(3)
	if shots:
		await _seconds(0.3)
		await _shot("B0_udstyr")

	# ---- Våben: to pladser på en Falk, hver med sin kanon
	_check(Game.fit_for("falk")["vaaben"] == ["laser", "laser"], "Falk har to våbenpladser med standardlasere")
	Game.request_equip("kepler_station", "puls")
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"][0] == "puls", "pulslaser monteret i plads 1")
	var cr := int(Game.wallet["credits"])
	Game.request_equip("kepler_station", "spred", 0)
	await _frames(3)
	_check(int(Game.wallet["credits"]) == cr - 800 and int(Game.parts.get("puls", 0)) == 1, "spredekanon købt for 800 cr – pulslaseren ligger på lageret")
	cr = int(Game.wallet["credits"])
	Game.request_equip("kepler_station", "puls", 1)
	await _frames(3)
	_check(int(Game.wallet["credits"]) == cr and Game.fit_for("falk")["vaaben"] == ["spred", "puls"] and Game.parts.is_empty(), "pulslaseren flyttet fra lageret til plads 2 (gratis)")
	var before := _live_bolts()
	ship.state = Ship.State.FLY
	ship.fire()
	_check(_live_bolts() - before == 4, "spredekanonen skyder 3 skud, pulslaseren 1 (%d)" % (_live_bolts() - before))
	Game.request_equip("kepler_station", "kanon", 1)
	await _frames(3)
	var ws: Array = ship.handling["weapons"]
	_check(ws.size() == 2 and ws[1]["id"] == "kanon" and float(ws[1]["dmg_mult"]) > 2.0, "massekanonen rammer hårdt (%.1f×)" % float(ws[1]["dmg_mult"]))
	Game.request_sell_part("kepler_station", "puls")
	await _frames(3)
	_check(not Game.parts.has("puls") and int(Game.wallet["credits"]) == cr - 900 + 325, "pulslaseren solgt fra lageret for halv pris")
	Game.request_unequip("kepler_station", "vaaben", 0)
	await _frames(3)
	Game.request_unequip("kepler_station", "vaaben", 1)
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"] == ["", "kanon"], "skibet beholder mindst ét våben (%s)" % str(Game.fit_for("falk")["vaaben"]))
	Game.request_equip("kepler_station", "laser", 0)
	await _frames(3)
	ship.state = Ship.State.LANDED

	# ---- Skjold, motor, panser
	var sh0 := ship.shield_max
	Game.request_equip("kepler_station", "skjold_tung")
	await _frames(3)
	_check(ship.shield_max > sh0 * 1.4 and float(ship.handling["regen_mult"]) < 1.0, "tungt skjold: %d (før %d)" % [int(ship.shield_max), int(sh0)])
	var sp0 := ship.max_speed()
	Game.request_equip("kepler_station", "motor_sprint")
	await _frames(3)
	_check(ship.max_speed() > sp0 * 1.1, "sprintmotor: %.0f m/s (før %.0f)" % [ship.max_speed(), sp0])
	Game.request_equip("kepler_station", "panser")
	await _frames(3)
	_check(float(ship.handling["armor"]) < 0.85 and Game.fit_for("falk")["gadget"][0] == "panser", "ekstra panser i gadgetplads 1 (%.2f)" % float(ship.handling["armor"]))

	# ---- Udstyret følger skibet
	Game.request_test("ship", "hveps")
	await _frames(3)
	_check(Game.fit_for("hveps")["vaaben"] == ["laser", "laser"] and not ship.handling.has("special") and (ship.handling["gadgets"] as Array).is_empty(), "Hveps har sit eget (standard) udstyr")
	Game.request_test("ship", "falk")
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"] == ["laser", "kanon"] and "panser" in ship.handling["gadgets"], "Falk har stadig sit udstyr")
	Game.server_save()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check((data["pilots"]["Mekaniker"] as Dictionary).get("fit", {}).get("falk", {}).get("vaaben", []) == ["laser", "kanon"], "udstyret gemmes")

	# ---- Traktorstråle
	Game.request_equip("kepler_station", "traktor")
	await _frames(3)
	_check("traktor" in ship.handling["gadgets"] and "panser" in ship.handling["gadgets"], "traktorstråle i gadgetplads 2 – panseret sidder der stadig")
	main.menu.launch_requested.emit()
	await _frames(3)
	ship.position = W.universe.origins["kepler"] + Vector3(300, 900, 1500)
	ship.basis = Basis.IDENTITY
	ship.speed = 0.0
	ship.steering = true
	ship.reset_physics_interpolation()
	main.camera.snap()
	Game.players[me]["cargo"] = {}
	Game._send_wallet(me)
	await _frames(2)
	W.pickups.server_spawn("malm", ship.position + ship.forward() * 110.0, 1)
	await _seconds(2.0)
	_check(Game.cargo_total(Game.wallet["cargo"]) == 0, "uden strålen bliver kassen 110 m væk liggende")
	Input.action_press("tractor")
	var t := 0.0
	var beam_seen := false
	while Game.cargo_total(Game.wallet["cargo"]) == 0 and t < 6.0:
		ship.speed = 0.0
		await _seconds(0.1)
		t += 0.1
		beam_seen = beam_seen or not W.pickups._beams.is_empty()
		if shots and t > 0.45 and t < 0.56:
			await _shot("B1_traktor")
	Input.action_release("tractor")
	_check(Game.cargo_total(Game.wallet["cargo"]) == 1 and beam_seen, "traktorstrålen trak kassen ind (%.1f s)" % t)

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _meshes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			c += 1
		c += _meshes(ch)
	return c


func _live_bolts() -> int:
	var c := 0
	for l in W.bolts._life:
		if l > 0.0:
			c += 1
	return c


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
