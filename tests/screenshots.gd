extends Node
## Tager skærmbilleder af nøglesituationer (kræver en skærm, ikke --headless):
##   godot --path . --rendering-driver opengl3 res://tests/screenshots.tscn
## Billederne gemmes i user://screenshots/.

var main: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false   # denne test starter i rummet
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await _seconds(1.0)
	await _shot("01_titel")
	Net.start_solo("Joakim")
	await _seconds(0.3)
	var ship: Ship = main.local_ship
	var uni: Universe = main.universe
	ship.steering = false
	ship.throttle = 0.4
	await _seconds(1.5)
	await _shot("02_rummet")

	var st := uni.station("kepler_station")
	ship.position = st.dock_pos + st.dock_dir * 70.0
	ship.basis = Basis.looking_at(-st.dock_dir, Vector3.UP)
	ship.speed = 8.0
	ship.throttle = 0.1
	main.camera.snap()
	await _seconds(1.2)
	await _shot("03_station")

	var vir := uni.planet("viridia")
	ship.position = vir.position + vir.pad_dir * (vir.radius + 900.0)
	ship.basis = Basis.looking_at(-vir.pad_dir + vir.tangent * 0.3, vir.tangent)
	main.camera.snap()
	await _seconds(1.2)
	await _shot("04_viridia_fra_rummet")

	ship.position = vir.pad_top + vir.pad_dir * 70.0 - vir.tangent * 140.0
	ship.basis = Basis.looking_at((vir.tangent - vir.pad_dir * 0.35).normalized(), vir.pad_dir)
	main.camera.snap()
	await _seconds(1.2)
	await _shot("05_viridia_lavt")

	ship.position = vir.pad_top + vir.pad_dir * 8.0
	ship.speed = 3.0
	ship.try_land()
	await _seconds(2.2)
	await _shot("06_planetmenu")
	main.menu.launch_requested.emit()

	var gate: Dictionary = uni.gates["kepler_gate"]
	ship.position = (gate["pos"] as Vector3) - (gate["dir"] as Vector3) * 90.0
	ship.basis = Basis.looking_at(gate["dir"], Vector3.UP)
	ship.speed = 0.0
	ship.throttle = 0.0
	main.camera.snap()
	await _seconds(1.2)
	await _shot("07_jump_gate")

	var lum := uni.planet("lumina")
	var fro := uni.planet("frosta")
	ship.position = fro.position + fro.pad_dir * (fro.radius + 260.0)
	ship.basis = Basis.looking_at((lum.position - ship.position).normalized(), Vector3.UP)
	main.camera.snap()
	await _seconds(1.5)
	await _shot("08_frosta_system")
	# Kamp i asteroidebæltet
	main.menu.close()
	ship.state = Ship.State.FLY
	var gate2: Dictionary = uni.gates["frosta_gate"]
	ship.position = gate2["pos"]
	ship.steering = false
	await _seconds(1.9)
	ship.position = Vector3(0, 10, -60)
	ship.basis = Basis.looking_at(Vector3(0, -0.05, -1).normalized(), Vector3.UP)
	ship.speed = 0.0
	ship.throttle = 0.0
	ship.shield = ship.shield_max
	ship.hull = 100.0
	main.camera.snap()
	for k in 3:
		W.pirates._server_spawn("kepler", ship.position + Vector3(0, 0, -200))
	for k in 3:
		var p: Dictionary = W.pirates._p[k]
		(p["node"] as Node3D).position = ship.position + Vector3(-30 + k * 30, 8 - k * 6, -90 - k * 25)
	await _seconds(0.3)
	for k in 6:
		ship.fire()
		await _seconds(0.12)
	W.fx.explosion(ship.position + Vector3(14, 4, -70), true)
	await _seconds(0.1)
	await _shot("09_kamp")

	# Fragtskib på vej ind til stationen
	var st2 := uni.station("kepler_station")
	var fr: Dictionary = W.freighters._f[0]
	var fn: Node3D = fr["node"]
	fn.visible = true
	fr["wait"] = 0.0
	ship.position = st2.dock_pos + st2.dock_dir * 110.0 + Vector3(25, 12, 0)
	ship.basis = Basis.looking_at((st2.position - ship.position).normalized(), Vector3.UP)
	fn.position = st2.dock_pos + st2.dock_dir * 50.0 + Vector3(8, -2, 0)
	fn.basis = Basis.looking_at(-st2.dock_dir, Vector3.UP)
	main.camera.snap()
	await _seconds(0.4)
	await _shot("10_fragtskib")

	# Stationsmenu med pixelscene
	ship.position = st2.dock_pos + st2.dock_dir * 8.0
	ship.speed = 3.0
	ship.try_land()
	await _seconds(2.2)
	await _shot("11_stationsmenu")
	get_tree().quit()


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://screenshots/%s.png" % file)
	print("gemt ", file)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
