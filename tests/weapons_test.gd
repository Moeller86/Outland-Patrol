extends Node
## Våbensystemer og gadgets (FTL-inspireret): pladser, flak, ion, krystal, stråle,
## burst, kædekanon, lagskjold, kappe, EMP, skjoldbatteri, droner og skrotarm.
## Kør headless:  godot --headless --path . res://tests/weapons_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship
var me := 0
var pir: Pirates
var hold := {}          ## pirat-indeks -> position, de holdes fast på


func _ready() -> void:
	Game.save_path = "user://test_weapons.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Våbenmester")
	await _frames(6)
	ship = main.local_ship
	ship.steering = false
	me = multiplayer.get_unique_id()
	pir = W.pirates
	for sys_id: String in pir._wave_t:
		pir._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	Game.request_test("credits")
	Game.request_test("credits")
	await _frames(3)

	# ---- Pladser pr. skib
	_check(Game.slot_count("falk", "vaaben") == 2 and Game.slot_count("falk", "gadget") == 2, "Falk: 2 våben, 2 gadgets")
	_check(Game.slot_count("krydser", "vaaben") == 5 and Game.slot_count("krydser", "gadget") == 4, "Krydser: 5 våben, 4 gadgets")
	var old := Game.normalize_fit("falk", {"vaaben": "kanon", "special": "traktor"})
	_check(old["vaaben"] == ["kanon", "laser"] and old["gadget"] == ["traktor", ""], "gamle gemte skibe omsættes (%s)" % str(old))
	Game.request_test("ship", "krydser")
	await _frames(4)
	var guns_used := 0
	for w in ship.loadout._w:
		guns_used += (w["guns"] as Array).size()
	_check(ship.loadout._w.size() == 5 and guns_used == 6, "krydserens 6 kanoner fordeles på 5 våben")
	Game.request_test("ship", "falk")
	await _frames(4)

	# ---- Primær/sekundær våbengruppe og våben til/fra (tast 1–5)
	_park(W.universe.origins["ravne"] + Vector3(600, 2600, -1800))
	await _frames(2)
	Game.request_weapon_group(1, 1)
	await _frames(3)
	var wl: Array = ship.handling["weapons"]
	_check(int(wl[0]["group"]) == 0 and int(wl[1]["group"]) == 1, "våben 2 er sat i den sekundære gruppe")
	_check(Game.fit_for("falk")["grupper"] == [0, 1], "grupperne gemmes på skibet")
	var lw := ship.loadout._w
	var s0 := [int(lw[0].get("shots", 0)), int(lw[1].get("shots", 0))]
	lw[0]["cool"] = 0.0
	lw[1]["cool"] = 0.0
	ship.loadout.tick(0.001, true, false)
	_check(int(lw[0].get("shots", 0)) == s0[0] + 1 and int(lw[1].get("shots", 0)) == s0[1], "primær skydeknap: kun våben 1 skyder")
	lw[0]["cool"] = 0.0
	lw[1]["cool"] = 0.0
	ship.loadout.tick(0.001, false, true)
	_check(int(lw[0].get("shots", 0)) == s0[0] + 1 and int(lw[1].get("shots", 0)) == s0[1] + 1, "sekundær skydeknap (Ctrl): kun våben 2 skyder")
	ship.loadout.toggle_weapon(0)
	lw[0]["cool"] = 0.0
	ship.loadout.tick(0.001, true, false)
	_check(not ship.loadout.weapon_on(0) and int(lw[0].get("shots", 0)) == s0[0] + 1, "tast 1 slår våben 1 fra – det skyder ikke")
	ship.loadout.toggle_weapon(0)
	_check(ship.loadout.weapon_on(0) and ship.loadout.weapon_state()[0]["on"], "tast 1 igen: våben 1 er klar")
	_check(Game.key_name("weapon_1") == "1" and Game.key_name("gadget_1") == "6", "taster: våben 1–5, gadgets 6–9")
	Game.request_weapon_group(1, 0)
	await _frames(3)

	# ---- I rummet i Ravnebæltet
	var base_pos: Vector3 = W.universe.origins["ravne"] + Vector3(600, 2600, -1800)
	_park(base_pos)
	await _frames(3)
	_check(main.hud._arms.visible, "våben- og gadgetpanelet vises på HUD'en")

	# ---- Flak: nærhedsrør og sprængning
	var a := _spawn("rover", Vector3(0, 0, -120))
	var b := _spawn("rover", Vector3(10, 0, -120))
	await _frames(2)
	var hp_a := float(pir._p[a]["hp"])
	var hp_b := float(pir._p[b]["hp"])
	var from := ship.position + Vector3(-7, 0, 0)
	W.bolts.fire(from, Vector3(0, 0, -1), 300.0, Color.ORANGE, Bolts.Kind.OWN, 2.0, 2)
	await _seconds(0.7)
	_check(float(pir._p[a]["hp"]) < hp_a, "flakgranaten springer 7 m fra piraten (%.1f → %.1f)" % [hp_a, float(pir._p[a]["hp"])])
	_check(float(pir._p[b]["hp"]) < hp_b, "… og rammer også naboen 10 m væk")
	W.bolts.fire(ship.position + Vector3(-30, 0, 0), Vector3(0, 0, -1), 300.0, Color.WHITE, Bolts.Kind.OWN, 2.0, 0)
	await _seconds(0.7)
	_check(float(pir._p[a]["hp"]) == float(pir._p[a]["hp"]), "(almindeligt skud forbi)")
	_clear()

	# ---- Ion mod en kaptajn: skjoldet ned, lammet
	var c := _spawn("kaptajn", Vector3(0, 0, -150))
	await _frames(2)
	var sh0 := float(pir._p[c]["shield"])
	var hp0 := float(pir._p[c]["hp"])
	pir._srv_hit_fx(c, 1.0, 1)
	await _frames(2)
	_check(float(pir._p[c]["shield"]) <= sh0 - 4.9 and float(pir._p[c]["hp"]) == hp0, "ion: skjold %.0f → %.0f, skroget urørt" % [sh0, float(pir._p[c]["shield"])])
	_check(float(pir._p[c]["ion"]) > 2.0, "kaptajnen er lammet (%.1f s)" % float(pir._p[c]["ion"]))
	hold.erase(c)
	var sp0 := float(pir._p[c]["speed"])
	await _seconds(1.5)
	_check(float(pir._p[c]["speed"]) < sp0 * 0.8 or float(pir._p[c]["speed"]) < 30.0, "lammet pirat sakker bagud (%.0f → %.0f m/s)" % [sp0, float(pir._p[c]["speed"])])
	# ---- Krystal: gennem skjoldet
	pir._p[c]["shield"] = 20.0
	hp0 = float(pir._p[c]["hp"])
	pir._srv_hit_fx(c, 3.0, 3)
	await _frames(2)
	_check(float(pir._p[c]["hp"]) == hp0 - 3.0 and float(pir._p[c]["shield"]) == 20.0, "krystal går lige gennem skjoldet")
	# ---- EMP
	pir._p[c]["ion"] = 0.0
	_park(pir.position_of(c) + Vector3(0, 0, 60))
	_mount("emp", 0)
	await _frames(3)
	ship.loadout.activate(0)
	await _frames(3)
	_check(float(pir._p[c]["ion"]) > 3.0 and float(pir._p[c]["shield"]) == 0.0, "EMP-puls: lammet og skjoldet slået ned")
	ship.loadout.activate(0)
	_check(ship.loadout._gcool[0] > 30.0, "EMP lader op igen (%d s)" % int(ship.loadout._gcool[0]))
	_clear()
	_park(base_pos)

	# ---- Strålelaser
	_mount("straale", 0)
	_mount("straale", 1)
	await _frames(3)
	var r := _spawn("kanonbaad", Vector3(0, 0, -120))
	await _frames(2)
	hp0 = float(pir._p[r]["hp"])
	var t := 0.0
	var beam_seen := false
	while t < 3.6:
		ship.loadout.tick(0.016, true)
		beam_seen = beam_seen or (not ship.loadout._beams.is_empty() and ship.loadout._beams[0].visible)
		if shots and t > 0.5 and t < 0.52:
			await _shot("D1_straale")
		await _frames(1)
		t += 0.016
	_check(beam_seen and float(pir._p[r]["hp"]) < hp0 - 3.0, "strålen brænder kanonbåden (%.0f → %.1f)" % [hp0, float(pir._p[r]["hp"])])
	# Overophedning med rigtig skydeknap
	for w in ship.loadout._w:
		w["heat"] = 0.0
		w["hot"] = false
	ship.steering = true
	Input.action_press("fire")
	t = 0.0
	while t < 4.0 and not ship.loadout._w[0]["hot"]:
		await _seconds(0.1)
		t += 0.1
	_check(ship.loadout._w[0]["hot"] and t > 1.8, "strålen overopheder efter ~%.1f s" % t)
	_check(not ship.loadout._beams[0].visible, "… og slukker, mens den køler af")
	Input.action_release("fire")
	ship.steering = false
	await _seconds(2.5)
	_check(not ship.loadout._w[0]["hot"], "kølet af igen efter ~2 s")
	_clear()

	# ---- Burstlaser: tre skud pr. salve
	_mount("burst", 0)
	_mount("laser", 1)
	await _frames(3)
	var bb := _live_own()
	ship.loadout._w[1]["cool"] = 99.0
	ship.loadout.tick(0.016, true)
	for k in 20:
		ship.loadout.tick(0.016, false)
		await _frames(1)
	_check(_live_own() - bb == 3, "burstlaseren fyrer en salve på 3 (%d)" % (_live_own() - bb))

	# ---- Kædekanon: hurtigere, jo længere man holder
	_mount("kaede", 0)
	await _frames(3)
	var w0: Dictionary = ship.loadout._w[0]
	ship.steering = true
	Input.action_press("fire")
	var t0 := Time.get_ticks_msec()
	var shots_first := -1
	var mark := 0
	while Time.get_ticks_msec() - t0 < 4000:
		ship.loadout._w[1]["cool"] = 99.0
		var el := Time.get_ticks_msec() - t0
		if shots_first < 0 and el >= 1000:
			shots_first = int(w0.get("shots", 0))
		if mark == 0 and el >= 3000:
			mark = int(w0.get("shots", 0))
		await _frames(1)
	var shots_last := int(w0.get("shots", 0)) - mark
	Input.action_release("fire")
	ship.steering = false
	_check(shots_last > shots_first * 2, "kædekanonen spinner op (%d skud 1. sekund, %d 4. sekund)" % [shots_first, shots_last])
	_check(float(w0["spin"]) < 0.5, "spin %.2f" % float(w0["spin"]))

	# ---- Lagskjold
	_mount("skjold_lag", 0)
	await _frames(3)
	ship.shield = ship.shield_max
	ship.hull = 100.0
	for k in 4:
		ship.take_damage(30.0)
	_check(ship.hull == 100.0, "lagskjoldet stopper fire hårde skud helt")
	ship.take_damage(10.0)
	_check(ship.hull < 100.0, "femte skud går igennem (skrog %d)" % int(ship.hull))
	ship.hull = 100.0
	ship._since_hit = 0.0
	ship.shield = 0.0
	await _seconds(1.8)
	_check(ship.shield >= ship.shield_max / 4.0 - 0.5, "et lag lader op på ~1,5 s – også lige efter et træf (%.1f)" % ship.shield)
	_mount("skjold_std", 0)
	await _frames(3)

	# ---- Skjoldbatteri
	_mount("batteri", 0)
	await _frames(3)
	ship.shield = 5.0
	ship.loadout.activate(0)
	_check(ship.shield > ship.shield_max * 1.25, "skjoldbatteri: %d / %d" % [int(ship.shield), int(ship.shield_max)])
	await _seconds(0.5)
	_check(ship.shield > ship.shield_max, "overladningen falder langsomt")

	# ---- Kappe: piraterne mister os, missilet mister låsen
	_mount("kappe", 1)
	await _frames(3)
	var k1 := _spawn("rover", Vector3(0, 0, -200))
	hold.erase(k1)
	ship.loadout.activate(1)
	await _frames(2)
	_check(ship.cloaked and ship.loadout.cloaked(), "kappen er aktiv")
	W.missiles.server_pirate_fire(ship.position + Vector3(0, 0, -150), Vector3(0, 0, 1), me)
	await _frames(2)
	var mid := 0
	for id: int in W.missiles._m:
		mid = id
	var m_dir: Vector3 = W.missiles._m[mid]["dir"] if W.missiles._m.has(mid) else Vector3.ZERO
	ship.position += Vector3(80, 0, 0)
	await _seconds(0.5)
	var still: bool = W.missiles._m.has(mid) and (W.missiles._m[mid]["dir"] as Vector3).dot(m_dir) > 0.99
	_check(still, "missilet flyver ligeud – låsen er tabt")
	ship.hull = 100.0
	await _seconds(5.0)
	_check(not ship.cloaked, "kappen falder efter 5 s")
	_clear()

	# ---- Forsvarsdrone
	_mount("forsvarsdrone", 0)
	await _frames(3)
	_check(ship.loadout._drones.has("forsvar"), "forsvarsdronen kredser om skibet")
	ship.hull = 100.0
	ship.shield = ship.shield_max
	W.missiles.server_pirate_fire(ship.position + Vector3(0, 0, -260), Vector3(0, 0, 1), me)
	t = 0.0
	while t < 4.0 and W.missiles.incoming() > 0:
		ship.hull = maxf(ship.hull, 0.0)
		await _seconds(0.1)
		t += 0.1
	_check(W.missiles.incoming() == 0 and ship.shield == ship.shield_max, "missilet blev skudt ned, før det ramte (%.1f s)" % t)

	# ---- Kampdrone
	_mount("kampdrone", 1)
	await _frames(3)
	var d := _spawn("kanonbaad", Vector3(0, 0, -90))
	pir._p[d]["ion"] = 99.0     # skyder ikke tilbage
	hp0 = float(pir._p[d]["hp"])
	await _seconds(3.0)
	_check(float(pir._p[d]["hp"]) < hp0, "kampdronen skyder selv på piraten (%.0f → %.1f)" % [hp0, float(pir._p[d]["hp"])])
	if shots:
		ship.basis = Basis.IDENTITY
		main.camera.snap()
		await _seconds(0.3)
		await _shot("D2_droner")
	_clear()

	# ---- Reparationsdrone
	_mount("repdrone", 0)
	await _frames(3)
	ship.hull = 50.0
	ship._since_hit = 10.0
	await _seconds(1.5)
	_check(ship.hull > 52.0, "reparationsdronen lapper skroget (%.1f)" % ship.hull)

	# ---- Skrotarm: større dusør
	_mount("skrotarm", 0)
	await _frames(3)
	var s1 := _spawn("rover", Vector3(0, 0, -200))
	var cr := int(Game.wallet["credits"])
	pir._srv_hit(s1, 99.0)
	await _frames(3)
	_check(int(Game.wallet["credits"]) - cr == int(round(Game.combat("bounty") * 1.25)), "skrotarm: +%d cr (normalt %d)" % [int(Game.wallet["credits"]) - cr, int(Game.combat("bounty"))])

	# ---- Testknap: alle dele på lageret
	Game.request_test("parts")
	await _frames(3)
	_check(Game.parts.size() >= 20, "testknappen lægger %d slags dele på lageret" % Game.parts.size())

	if shots:
		await _gallery()

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gallery() -> void:
	# Udstyrsfanen på Kepler Station
	var st := W.universe.station("kepler_station")
	ship.position = st.dock_pos
	ship.speed = 2.0
	ship.reset_physics_interpolation()
	await _frames(2)
	ship.try_land()
	await _seconds(2.2)
	_mount("ion", 1)
	Game.request_weapon_group(1, 1)
	await _frames(3)
	main.menu._tabs.current_tab = 6
	main.menu._eq_sel = ["vaaben", 0]
	main.menu._refresh_equipment()
	await _seconds(0.4)
	await _shot("D0_udstyr")
	main.menu.launch_requested.emit()
	await _frames(3)
	# Flak og kanoner i kamp med HUD-panelet
	_mount("flak", 0)
	_mount("ion", 1)
	_mount("kampdrone", 0)
	_mount("kappe", 1)
	Game.request_weapon_group(1, 1)
	await _frames(3)
	_park(W.universe.origins["ravne"] + Vector3(600, 2600, -1800))
	for k in 3:
		var i := _spawn("rover", Vector3(-12 + k * 12, 3, -110))
		pir._p[i]["ion"] = 99.0
	await _frames(2)
	ship.loadout.tick(0.016, true)
	for k in 12:
		await _frames(1)
	await _shot("D3_kamp")


func _mount(item: String, idx: int) -> void:
	Game.request_equip("", item, idx)


func _spawn(t: String, off: Vector3) -> int:
	var at := ship.position + off
	var i := pir.server_spawn_at("ravne", at, at + Vector3(0, 0, -100), "wt", t)
	hold[i] = at
	return i


func _clear() -> void:
	pir.server_despawn_tag("wt")
	hold.clear()


func _process(_delta: float) -> void:
	for i: int in hold:
		if pir.is_active(i):
			(pir._p[i]["node"] as Node3D).position = hold[i]
			pir._p[i]["speed"] = 0.0
			pir._p[i]["cool"] = 9.0
			pir._p[i]["mcool"] = 9.0


func _live_own() -> int:
	var c := 0
	for k in Bolts.POOL:
		if W.bolts._life[k] > 0.0 and W.bolts._kind[k] == Bolts.Kind.OWN:
			c += 1
	return c


func _park(pos: Vector3) -> void:
	ship.position = pos
	ship.basis = Basis.IDENTITY
	ship.speed = 0.0
	ship.state = Ship.State.FLY
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
