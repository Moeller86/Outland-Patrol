extends Node
## Rumskibsmanageren (U) og Mk I–III: overblik, træk og slip i hangaren, rangkrav.
## Kør headless:  godot --headless --path . res://tests/manager_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship
var me := 0
var mgr: ShipManager


func _ready() -> void:
	Game.save_path = "user://test_manager.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Mekanikeren")
	await _frames(6)
	ship = main.local_ship
	ship.steering = false
	me = multiplayer.get_unique_id()
	mgr = main.ship_manager
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0

	# ---- Mk-niveauer
	var p1 := Game.part("puls")
	var p2 := Game.part("puls@2")
	var p3 := Game.part("puls@3")
	_check(p1["name"] == "Pulslaser Mk I" and p2["name"] == "Pulslaser Mk II" and p3["name"] == "Pulslaser Mk III", "navne: %s / %s / %s" % [p1["name"], p2["name"], p3["name"]])
	_check(float(p3["dmg_mult"]) > float(p2["dmg_mult"]) and float(p2["dmg_mult"]) > float(p1["dmg_mult"]), "højere Mk rammer hårdere (%.2f → %.2f → %.2f)" % [float(p1["dmg_mult"]), float(p2["dmg_mult"]), float(p3["dmg_mult"])])
	_check(int(p3["price"]) > int(p2["price"]) and int(p2["price"]) > int(p1["price"]), "og koster mere (%d / %d / %d cr)" % [int(p1["price"]), int(p2["price"]), int(p3["price"])])
	_check(int(Game.part("laser")["price"]) == 0 and int(Game.part("laser@2")["price"]) > 0, "Standardlaser Mk I er gratis, Mk II koster %d cr" % int(Game.part("laser@2")["price"]))
	_check(int(Game.part("skjold_lag@3")["layers"]) == 5, "Lagskjold Mk III har 5 lag")
	_check(Game.part("nope").is_empty() and Game.part_base("emp@3") == "emp" and Game.part_mk("emp@3") == 3, "id'er: grunddel@mk")

	# ---- Overblik under flyvning
	_park(W.universe.origins["kepler"] + Vector3(300, 900, 1500))
	await _frames(2)
	_press("ship_manager")
	await _frames(4)
	_check(mgr.visible and not ship.steering, "U åbner rumskibsmanageren under flyvning")
	_check(not mgr.editable(), "… men kun som overblik (ikke i en hangar)")
	_check(mgr._boxes.size() == 6, "Falk: 6 kasser (2 våben, skjold, motor, 2 gadgets) – %d" % mgr._boxes.size())
	await _frames(3)
	var inside := 0
	for b in mgr._boxes:
		var sp := mgr.screen_of(b.anchor3d)
		if Rect2(Vector2.ZERO, mgr._stage.size).has_point(sp):
			inside += 1
		else:
			print("    ", b.slot, b.idx, " ", sp, " stage ", mgr._stage.size, " sv ", mgr._sv.size, " a ", b.anchor3d)
	_check(inside == mgr._boxes.size() or mgr._stage.size.y < 200.0, "alle streger peger ind på skibet (%d/%d)" % [inside, mgr._boxes.size()])
	if shots:
		await _seconds(0.4)
		await _shot("F0_manager_flyvning")
	_press("ship_manager")
	await _frames(3)
	_check(not mgr.visible and ship.steering, "U lukker igen, og styringen er tilbage")

	# ---- Hangaren på Kepler Station
	Game.test_mode = false
	Game.server_reward(me, 20000, 0)
	var st := W.universe.station("kepler_station")
	ship.position = st.dock_pos
	ship.speed = 2.0
	ship.reset_physics_interpolation()
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and main.menu.visible, "landet på Kepler Station")
	_press("ship_manager")
	await _frames(4)
	_check(mgr.visible and mgr.editable() and mgr.can_shop(), "i hangaren kan man flytte, installere og købe")
	# Rangkrav: Mk III kræver Kaptajn
	var cr := int(Game.wallet["credits"])
	Game.request_equip(mgr.loc_id, "ion@3", 0)
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"][0] == "laser" and int(Game.wallet["credits"]) == cr, "Ionkanon Mk III kræver rang (Kadet afvises)")
	Game.request_equip(mgr.loc_id, "ion", 0)
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"][0] == "ion", "Ionkanon Mk I købt og monteret i våben 1")
	Game.players[me]["xp"] = 800
	Game._send_wallet(me)
	await _frames(2)
	Game.request_equip(mgr.loc_id, "ion@3", 0)
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"][0] == "ion@3" and int(Game.parts.get("ion", 0)) == 1, "som Kaptajn: Mk III monteret – Mk I lagt på lageret")
	# Træk og slip: lager → plads
	var w2 := _box("vaaben", 1)
	_check(mgr.can_drop_on_slot(w2, {"kind": "stash", "id": "ion"}) and not mgr.can_drop_on_slot(_box("skjold", 0), {"kind": "stash", "id": "ion"}), "et våben kan kun slippes på en våbenplads")
	mgr.drop_on_slot(w2, {"kind": "stash", "id": "ion"})
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"] == ["ion@3", "ion"] and Game.parts.is_empty(), "trukket fra lageret til våben 2")
	# Plads → plads (bytter, også våbengruppen)
	Game.request_weapon_group(0, 1)
	await _frames(3)
	mgr.drop_on_slot(_box("vaaben", 1), {"kind": "slot", "slot": "vaaben", "idx": 0, "id": "ion@3"})
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"] == ["ion", "ion@3"] and Game.fit_for("falk")["grupper"] == [0, 1], "våben 1 og 2 byttet – gruppen fulgte med")
	# Plads → lager
	mgr.drop_on_stash({"kind": "slot", "slot": "vaaben", "idx": 0, "id": "ion"})
	await _frames(3)
	_check(Game.fit_for("falk")["vaaben"][0] == "" and int(Game.parts.get("ion", 0)) == 1, "trukket til lageret: våben 1 er tom")
	# Gadget med Mk: styrke
	Game.request_equip(mgr.loc_id, "repdrone@2", 0)
	await _frames(3)
	_check(is_equal_approx(Game.gadget_power("repdrone"), 1.3), "Reparationsdrone Mk II: styrke %.0f %%" % (Game.gadget_power("repdrone") * 100.0))
	ship.loadout.rebuild()
	_check(Game.has_gadget("repdrone") and ship.loadout._drones.has("rep"), "dronen er klar på skibet")
	Game.request_equip(mgr.loc_id, "laser@2", 0)
	Game.request_equip(mgr.loc_id, "skjold_hurtig@2", 0)
	Game.request_equip(mgr.loc_id, "motor_sprint@3", 0)
	Game.request_equip(mgr.loc_id, "kappe@2", 1)
	await _frames(4)
	_check(_box("skjold", 0).item_id == "skjold_hurtig@2" and _box("motor", 0).item_id == "motor_sprint@3", "kasserne viser de nye dele")
	if shots:
		mgr.select("vaaben", 1)
		await _seconds(0.5)
		await _shot("F1_manager_hangar")
	mgr.select("motor", 0)
	await _frames(2)
	_check(mgr._left.get_child_count() > 8, "venstre panel viser skibet og den valgte del")
	Game.server_save()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	var saved: Dictionary = (data["pilots"]["Mekanikeren"] as Dictionary).get("fit", {}).get("falk", {})
	_check(saved.get("motor", "") == "motor_sprint@3" and (data["pilots"]["Mekanikeren"] as Dictionary).get("parts", {}).has("ion"), "udstyr med Mk og lageret gemmes")
	mgr.close()
	await _frames(2)

	# ---- Stationsfanen Udstyr åbner manageren
	main.menu._tabs.current_tab = 6
	main.menu._refresh_equipment()
	await _frames(2)
	get_tree().call_group("ship_manager", "open_here", "kepler_station")
	await _frames(3)
	_check(mgr.visible and mgr.loc_id == "kepler_station", "knappen under Udstyr åbner manageren")
	mgr.close()
	Game.test_mode = true

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _box(slot: String, idx: int) -> ShipManager.SlotBox:
	for b in mgr._boxes:
		if b.slot == slot and b.idx == idx:
			return b
	return null


func _press(action: String) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = Game.key_of(action)
	ev.pressed = true
	main._unhandled_input(ev)


func _park(pos: Vector3) -> void:
	ship.position = pos
	ship.basis = Basis.IDENTITY
	ship.speed = 0.0
	ship.state = Ship.State.FLY
	ship.steering = true
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
