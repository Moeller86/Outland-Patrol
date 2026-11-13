extends Node
## Testknappen på startskærmen: starter solo direkte i angrebsmissionen.

var main: Node
var failures := 0


func _ready() -> void:
	Game.save_path = "user://test_testmission.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	for id in ["assault_frosta", "assault_korvus"]:
		main.title.test_mission_pressed.emit("Testpilot", id)
		await _seconds(1.0)
		var ship: Ship = main.local_ship
		_check(ship != null and ship.state == Ship.State.FLY and not main.title.visible, "%s: flyver" % id)
		_check(W.missions.active and W.assault.active(), "%s: missionen kører, fæstningen er bygget" % id)
		var p := W.assault.planet
		_check(ship.universe.nearest_planet(ship.position) == p and p.ground_altitude(ship.position) > 40.0,
			"%s: skibet er over %s (%d m)" % [id, p.display_name, int(p.ground_altitude(ship.position))])
		_check(ship.position.distance_to(W.assault.entry) < 600.0, "%s: lige før kløften (%d m)" % [id, int(ship.position.distance_to(W.assault.entry))])
		_check(W.bombs.ammo == Bombs.ISSUED, "%s: bomber om bord" % id)
		Net.leave()
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
