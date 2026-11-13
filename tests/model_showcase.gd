extends Node
## Renderer nærbilleder af modellerne (kræver skærm):
##   godot --path . res://tests/model_showcase.tscn
## Billederne gemmes i user://models/.

var main: Node


func _ready() -> void:
	Game.save_path = "user://test_models.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	DirAccess.make_dir_recursive_absolute("user://models")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await get_tree().create_timer(0.5).timeout
	Net.start_solo("Model")
	await get_tree().create_timer(0.3).timeout
	var ship: Ship = main.local_ship
	ship.steering = false
	ship.throttle = 0.0
	ship.speed = 0.0
	var spot := Vector3(-300, 200, 300)   # tomt rum med planeter i baggrunden
	ship.position = spot
	ship.basis = Basis.looking_at(Vector3(0.3, -0.2, -1).normalized(), Vector3.UP)

	var cam: ChaseCamera = main.camera
	cam.target = null
	cam.set_process(false)

	# Spillerens skib fra tre vinkler
	for v: Array in [["skib_bagfra", Vector3(4, 3, 11)], ["skib_side", Vector3(9, 2.5, -1)], ["skib_forfra", Vector3(-4, 2, -10)]]:
		await _view(spot + ship.basis * v[1], spot, v[0])

	# Pirat og fragtskib
	var pirate := ShipModels.pirate()
	main.world.add_child(pirate)
	pirate.position = spot + Vector3(40, 0, 0)
	pirate.rotation = Vector3(0, 0.6, 0)
	await _view(pirate.position + Vector3(6, 3.5, 7), pirate.position, "pirat")
	var fr := ShipModels.freighter()
	main.world.add_child(fr)
	fr.position = spot + Vector3(-60, 0, 0)
	fr.rotation = Vector3(0, -0.7, 0)
	await _view(fr.position + Vector3(-16, 8, 14), fr.position + Vector3(0, 0, 3), "fragtskib")

	# Baser og by
	var base := W.universe.station("concord_base")
	Game.world["missions_completed"] = 12
	Game._cl_world.rpc(Game.world)
	await _view(base.position + base.dock_dir * 85.0 + Vector3(45, 40, 0), base.position, "bastion_udbygget")
	Game.world["missions_completed"] = 0
	Game._cl_world.rpc(Game.world)
	await _view(base.position + base.dock_dir * 70.0 + Vector3(-25, 15, 10), base.position + base.dock_dir * 10.0, "bastion_hangar")
	var st := W.universe.station("kepler_station")
	await _view(st.position + st.dock_dir * 90.0 + Vector3(40, 30, 20), st.position, "kepler_station")
	for pid in ["viridia", "sahra", "frosta"]:
		var pl := W.universe.planet(pid)
		var up := pl.pad_dir
		ship.position = pl.pad_top + up * 300.0
		await get_tree().create_timer(0.6).timeout
		await _view(pl.pad_top + up * 45.0 + pl.tangent * 70.0, pl.pad_top + up * 8.0, "by_" + pid)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	get_tree().quit()


func _view(from: Vector3, at: Vector3, file: String) -> void:
	var cam: Camera3D = main.camera
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://models/%s.png" % file)
	print("gemt ", file)
