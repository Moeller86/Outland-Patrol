extends Node
## Lavtflyvning: 8 m over Viridia i 55 m/s i 12 sekunder. Kør headless:
##   godot --headless --path . res://tests/low_flight_test.tscn
## Tjekker at terrænet følger med, at man ikke rammer jorden, at re-entry
## ikke udløses ved vandret flyvning, men stadig udløses ved et dyk.

var failures := 0


func _ready() -> void:
	Game.save_path = "user://test_low.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	var main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false   # denne test starter i rummet
	add_child(main)
	W.weather.auto = false   # intet tilfældigt uvejr under testen
	await get_tree().physics_frame
	Net.start_solo("Test")
	for i in 3:
		await get_tree().physics_frame
	var ship: Ship = main.local_ship
	ship.steering = false
	var vir := W.universe.planet("viridia")
	var td: TerrainDetail = main.terrain
	var dir := (vir.pad_dir + vir.tangent * 0.08).normalized()
	var fwd := vir.tangent
	var hits := [0]
	Game.toast.connect(func(m: String): if "jorden" in m: hits[0] += 1)
	var edge := 0
	var reentry := 0
	var t := 0.0
	while t < 12.0:
		var dt := get_physics_process_delta_time()
		dir = (dir + fwd * (55.0 * dt / vir.radius)).normalized()
		fwd = (fwd - dir * fwd.dot(dir)).normalized()
		ship.position = vir.position + dir * (vir.fine_surface_radius(dir) + 8.0)
		ship.basis = Basis.looking_at(fwd, dir)
		ship.speed = 55.0
		ship.throttle = 1.0
		await get_tree().physics_frame
		t += dt
		if ship.reentry:
			reentry += 1
		if td._planet != null and (vir.position + dir * vir.radius).distance_to(td._center) > TerrainDetail.HOLE - 30.0:
			edge += 1
	_check(td._planet == vir and td._mesh.visible, "detaljeret terræn aktivt under skibet")
	_check(edge == 0, "terrænet fulgte med hele vejen (%d frames ved kanten)" % edge)
	_check(hits[0] == 0, "ingen jordkollisioner 8 m over terrænet")
	_check(reentry == 0, "ingen re-entry ved vandret lavtflyvning")
	_check(ship.hull == 100.0, "skroget er helt")

	var arr: Array = td._mesh.mesh.surface_get_arrays(0)
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var tri_n := (vv[ii[1]] - vv[ii[0]]).cross(vv[ii[2]] - vv[ii[0]])
	var up := (vv[ii[0]] - vir.position).normalized()
	_check(tri_n.dot(up) < 0.0, "terrænets trekanter vender med uret set ovenfra (Godots forside)")

	ship.position = vir.position + vir.pad_dir.rotated(vir.tangent, 0.3) * (vir.radius + vir.atmo_top * 0.75)
	ship.basis = Basis.looking_at((vir.position - ship.position).normalized(), vir.tangent)
	var seen := false
	for k in 40:
		ship.speed = 80.0
		ship.throttle = 1.0
		await get_tree().physics_frame
		seen = seen or ship.reentry
	_check(seen, "re-entry ved hurtigt dyk")
	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	print(("  OK   " if ok else "  FEJL ") + what)
	if not ok:
		failures += 1
