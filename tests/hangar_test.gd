extends Node
## Hangaren på Concord-basen, tilpasning af skibet, nye skibstyper, skibspladser
## (egen base giver flere) og dreadnoughten CNS Vogteren.
## Kør headless:  godot --headless --path . res://tests/hangar_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship


func _ready() -> void:
	Game.save_path = "user://test_hangar.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)            # start i hangaren (start_docked)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Hangarpilot")
	await _frames(6)
	ship = main.local_ship
	for sys_id: String in W.pirates._wave_t:
		W.pirates._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0
	var base: StationBody = W.universe.station("concord_base")

	# ---- Start på egen plads i hangaren
	var l := base._body_xf().affine_inverse() * ship.position
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "concord_base", "starter landet i Concord-basen")
	_check(l.z > StationBody.HANGAR_BACK and l.z < StationBody.HANGAR_FRONT and absf(l.x) < StationBody.HANGAR_HALF_W, "skibet står inde i hangaren")
	_check(ship.position.distance_to(base.pad_world(0)) < 3.0, "på plads 1")
	if shots:
		main.menu.visible = false
		main.camera.snap()
		await _seconds(0.6)
		await _shot("96_hangar_inde")
		main.menu.visible = true

	# ---- Tilpas skibet
	main.menu._tabs.current_tab = 4
	main.menu._paint.refresh()
	await _frames(2)
	main.menu._paint._choose("paint", "4d8bff")
	main.menu._paint._choose("accent", "ff4f8b")
	main.menu._paint._choose("engine", "ff4fd8")
	main.menu._paint._choose("pattern", "camo")
	main.menu._paint._choose("ship_name", "Nattens Gnist")
	await _frames(4)
	_check(ship.look.get("paint", "") == "4d8bff" and ship.look.get("pattern", "") == "camo", "skibet er lakeret blåt med camouflage")
	_check(ship.model.engine.to_html(false) == "ff4fd8" and ship.paint.to_html(false) == "4d8bff", "motorens glød og lakken er skiftet")
	_check(ship.look.get("ship_name", "") == "Nattens Gnist", "skibet hedder Nattens Gnist")
	Game.server_save()
	var data = JSON.parse_string(FileAccess.get_file_as_string(Game.save_path))
	_check((data["pilots"]["Hangarpilot"] as Dictionary).get("look", {}).get("ship_name", "") == "Nattens Gnist", "tilpasningen gemmes")
	if shots:
		await _seconds(0.5)
		await _shot("97_tilpas_skib")

	# ---- Flyv ud af hangaren og ind igen
	main.menu.launch_requested.emit()
	await _frames(3)
	_check(ship.state == Ship.State.FLY, "letter fra pladsen")
	ship.steering = false
	ship.throttle = 0.6
	var t := 0.0
	var hull0 := ship.hull
	while t < 3.0:
		await _seconds(0.1)
		t += 0.1
	l = base._body_xf().affine_inverse() * ship.position
	_check(l.z > StationBody.HANGAR_FRONT and ship.hull == hull0, "fløj ud gennem åbningen uden at ramme noget (%d m ude)" % int(l.z - StationBody.HANGAR_FRONT))
	if shots:
		ship.throttle = 0.0
		ship.speed = 0.0
		ship.position = base._body_xf() * Vector3(0, 4, StationBody.HANGAR_FRONT + 70.0)
		ship.basis = Basis.looking_at(-base.dock_dir, Vector3.UP)
		ship.reset_physics_interpolation()
		main.camera.snap()
		await _seconds(0.6)
		await _shot("98_hangar_ude")
	# Vægge og basen er massive, hangaren er åben
	_check(base.collide_point(base._body_xf() * Vector3(0, 0, StationBody.HANGAR_Z)) == Vector3.INF, "hangarens indre er åbent")
	_check(base.collide_point(base._body_xf() * Vector3(StationBody.HANGAR_HALF_W + 0.5, 0, StationBody.HANGAR_Z)) != Vector3.INF, "hangarens væg er massiv")
	_check(base.collide_point(base._body_xf() * Vector3(0, 0, -10)) != Vector3.INF, "basen selv er massiv")
	# Ind og land
	ship.position = base._body_xf() * Vector3(0, -2, StationBody.HANGAR_Z + 6.0)
	ship.speed = 3.0
	ship.reset_physics_interpolation()
	await _frames(2)
	_check(ship.try_land() == "", "kan lande inde i hangaren")
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and ship.position.distance_to(base.pad_world(0) + base._body_xf().basis.y * 1.6) < 0.5, "landede på sin egen plads")

	# ---- Skibspladser: 2 uden base
	var me := multiplayer.get_unique_id()
	Game.server_reward(me, 20000, 0)
	await _frames(2)
	Game.world["missions_completed"] = 10       # værftet på basen er åbent
	Game.request_ship("kepler_station", "hveps")
	await _frames(3)
	_check(not ("hveps" in Game.owned_ships()), "Kepler Station har intet værft")
	Game.request_ship("concord_base", "hveps")
	await _frames(3)
	_check(Game.owned_ships().size() == 2 and Game.local_class() == "hveps", "køber Hveps (2/2 pladser)")
	var cr := int(Game.wallet["credits"])
	Game.request_ship("concord_base", "glente")
	await _frames(3)
	_check(not ("glente" in Game.owned_ships()) and int(Game.wallet["credits"]) == cr, "ingen plads til et tredje skib uden base")
	# Køb en base med hangar → flere pladser
	var plot: String = W.bases.plot_ids()[0]
	if not Game.world.has("bases"):
		Game.world["bases"] = {}
	Game.world["bases"][plot] = {"owned": true, "modules": {"hangar": 1}, "storage": 0, "hp": 600.0}
	_check(Game.ship_slots() == 6, "base med hangar giver 6 pladser (%d)" % Game.ship_slots())
	for cls in ["glente", "ravn", "fregat", "krydser"]:
		Game.request_ship("concord_base", cls)
		await _frames(3)
	_check(Game.owned_ships().size() == 6, "ejer nu 6 skibe: %s" % ", ".join(Game.owned_ships()))
	# Skift skib i egen base (ikke købe)
	Game.request_ship(plot, "falk")
	await _frames(3)
	_check(Game.local_class() == "falk", "skifter til Falk i egen base med hangar")
	Game.world["bases"][plot]["modules"] = {}
	Game.request_ship(plot, "ravn")
	await _frames(3)
	_check(Game.local_class() == "falk", "uden hangar kan man ikke skifte på basen")

	# ---- Alle skibstyper kan flyve
	var bad := []
	for cls: String in Game.ship_data["order"]:
		ship.set_class(cls)
		await _frames(1)
		if ship.model == null or ship.model.get_child_count() < 5 or ship.guns().is_empty():
			bad.append(cls)
	_check(bad.is_empty() and Game.ship_data["order"].size() == 12, "12 skibstyper bygger og har kanoner %s" % str(bad))
	ship.set_class("falk")
	_check(not ("krydser" in Game.ship_data["start"]) and "spejder" in Game.ship_data["start"], "Krydser kan ikke vælges som startskib, Spejder kan")

	# ---- Dreadnoughten
	var dr: StationBody = W.universe.station("dreadnought")
	_check(dr != null and dr.mobile and dr.system_id == "frosta", "CNS Vogteren flyver i Frosta")
	_check(Game.locations["dreadnought"].get("shipyard", false), "dreadnoughten har værft og hangar")
	main.menu.launch_requested.emit()
	await _frames(3)
	ship.position = dr.dock_pos + dr.dock_dir * 5.0
	ship.speed = 2.0
	ship.reset_physics_interpolation()
	await _frames(2)
	_check(ship.try_land() == "", "kan docke ved dreadnoughten")
	await _seconds(2.2)
	_check(ship.state == Ship.State.LANDED and ship.docked_at == "dreadnought", "docket ved CNS Vogteren")
	if shots:
		main.menu.visible = false
		ship.state = Ship.State.FLY
		ship.position = dr.position + dr.dock_dir * 220.0 + Vector3(0, 60, 0)
		ship.basis = Basis.looking_at((dr.position - ship.position).normalized(), Vector3.UP)
		ship.speed = 0.0
		ship.reset_physics_interpolation()
		main.camera.snap()
		await _seconds(0.8)
		await _shot("99_dreadnought")
		ship.state = Ship.State.LANDED
		ship.dock_at("dreadnought", ship.slot)
	var old := dr.position
	dr._park_t = dr.park_time
	await _seconds(0.3)
	_check(dr.position.distance_to(old) > 500.0 and dr.stop_idx == 1, "dreadnoughten hoppede videre (%d m)" % int(dr.position.distance_to(old)))
	_check(ship.state == Ship.State.LANDED and ship.position.distance_to(dr.dock_pos) < 20.0, "det dockede skib fulgte med")
	_check(Game.locations["dreadnought"]["world_pos"] == dr.position, "kortet kender den nye position")

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
