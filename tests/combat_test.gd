extends Node
## Bedre kampe: piratetyper, chefpirat, smartere AI og bølger der bliver sværere.
## Kør headless:  godot --headless --path . res://tests/combat_test.tscn

var main: Node
var failures := 0
var shots := false
var ship: Ship
var me := 0
var pir: Pirates


func _ready() -> void:
	Game.save_path = "user://test_combat.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	shots = DisplayServer.get_name() != "headless"
	if shots:
		DirAccess.make_dir_recursive_absolute("user://screenshots")
	main = load("res://scenes/main.tscn").instantiate()
	main.start_docked = false
	add_child(main)
	W.weather.auto = false
	await _frames(3)
	Net.start_solo("Kriger")
	await _frames(6)
	ship = main.local_ship
	ship.steering = false
	me = multiplayer.get_unique_id()
	pir = W.pirates
	for sys_id: String in pir._wave_t:
		pir._wave_t[sys_id] = 99999.0
	W.bases._raid_t = 99999.0

	# ---- Bølger bliver sværere
	var w0 := pir.wave_mix("ravne", 0)
	var w6 := pir.wave_mix("ravne", 6)
	var w4 := pir.wave_mix("ravne", 4)
	var k8 := pir.wave_mix("kepler", 8)
	_check(w0.size() == 2 and w0[0] == "rover", "første bølge: %s" % Pirates.describe(w0))
	_check(w6.size() == 5, "7. bølge i Ravnebæltet: %s" % Pirates.describe(w6))
	_check(w4.has("kaptajn") and w4.size() >= 3, "5. bølge i lovløst rum har en kaptajn: %s" % Pirates.describe(w4))
	_check(k8.size() <= 2 and not k8.has("kanonbaad") and not k8.has("kaptajn"), "Concord-rum: små grupper (%s)" % Pirates.describe(k8))
	var heavy := 0
	for k in 40:
		for t in pir.wave_mix("ekko", 7):
			if t in ["kanonbaad", "missilbaad", "skygge"]:
				heavy += 1
	_check(heavy > 20, "senere bølger har tunge typer (%d i 40 bølger)" % heavy)

	# ---- I rummet i Ravnebæltet
	var base_pos: Vector3 = W.universe.origins["ravne"] + Vector3(600, 2600, -1800)
	_park(base_pos)
	await _frames(3)

	# ---- Alle typer: egen model, eget skrog, etiket
	var seen := {}
	for t: String in Pirates.TYPES:
		var i := pir.server_spawn_at("ravne", ship.position + Vector3(0, 0, -300), ship.position, "test", t)
		await _frames(2)
		_check(pir.is_active(i) and pir.type_of(i) == t and is_equal_approx(float(pir._p[i]["hp_max"]), float(Pirates.TYPES[t]["hp"])), "%s: %d skrog" % [Pirates.TYPES[t]["name"], int(pir._p[i]["hp_max"])])
		seen[(pir._p[i]["node"] as Node3D).get_instance_id()] = true
		pir.server_despawn_tag("test")
		await _frames(2)
	_check(seen.size() == Pirates.TYPES.size(), "seks forskellige modeller (%d)" % seen.size())

	# ---- Skyggejægeren
	var si := pir.server_spawn_at("ravne", ship.position + Vector3(0, 0, -450), ship.position + Vector3(0, 0, -900), "skygge", "skygge")
	await _frames(3)
	var hidden := pir.is_hidden(si) and pir.positions_in("ravne").is_empty() and pir.lock_candidates(ship.position, ship.forward(), 2000.0, -1.0, "ravne").is_empty()
	_check(hidden, "skyggejægeren er usynlig på radar og kan ikke låses på 450 m")
	_check(pir.positions_in("ravne", true).size() == 1, "… men værten ved, den er der")
	(pir._p[si]["node"] as Node3D).position = ship.position + Vector3(0, 0, -100)
	await _frames(2)
	_check(not pir.is_hidden(si) and pir.markers_in("ravne")[0]["label"] == "SKYGGEJÆGER", "tæt på (100 m) kan den ses: %s" % (pir.markers_in("ravne")[0]["label"] if not pir.markers_in("ravne").is_empty() else "-"))
	(pir._p[si]["node"] as Node3D).position = ship.position + Vector3(0, 0, -450)
	pir._cl_fire(si, ship.position + Vector3(0, 0, -450), Vector3.FORWARD, 10.0, 9.0, Color.WHITE)
	_check(not pir.is_hidden(si), "den afslører sig, når den skyder")
	pir.server_despawn_tag("skygge")
	await _frames(2)

	# ---- Kanonbåd: kanontårnet skyder bagud, og skuddene er tunge
	var gi := pir.server_spawn_at("ravne", ship.position + Vector3(0, 0, -150), ship.position + Vector3(0, 0, -900), "kb", "kanonbaad")
	ship.shield = 0.0
	ship.hull = 100.0
	var t := 0.0
	var hit := false
	while t < 8.0 and not hit:
		ship.shield = 0.0
		ship.speed = 0.0
		await _seconds(0.1)
		t += 0.1
		hit = ship.hull < 100.0
	var dmg_taken := 100.0 - ship.hull
	_check(hit, "kanonbådens tårn ramte os bag sig (%.1f s)" % t)
	_check(dmg_taken > Bolts.HIT_DAMAGE_PIRATE * float(ship.handling.get("armor", 1.0)) * 0.99, "tungt skud: %.1f skade" % dmg_taken)
	pir.server_despawn_tag("kb")
	ship.hull = 100.0
	await _frames(2)

	# ---- Missilbåd holder afstand
	var mi := pir.server_spawn_at("ravne", ship.position + Vector3(0, 0, -250), ship.position, "mb", "missilbaad")
	var min_d := INF
	t = 0.0
	while t < 10.0:
		ship.speed = 0.0
		ship.hull = 100.0
		await _seconds(0.2)
		t += 0.2
		if t > 4.0:
			min_d = minf(min_d, ship.position.distance_to(pir.position_of(mi)))
	_check(min_d > 200.0, "missilbåden holder afstand (mindst %d m)" % int(min_d))
	_check(int(pir._p[mi]["missiles"]) < 5, "og sender missiler (%d tilbage)" % int(pir._p[mi]["missiles"]))
	pir.server_despawn_tag("mb")
	W.missiles.flare_cool = 0.0
	for id in W.missiles._m.keys() if "_m" in W.missiles else []:
		pass
	await _frames(2)

	# ---- Flugt og vige ud
	var ri := pir.server_spawn_at("ravne", ship.position + Vector3(0, 0, -300), ship.position, "rv", "rover")
	await _frames(2)
	var fled := false
	for k in 20:
		pir._p[ri]["fled"] = false
		pir._p[ri]["mode"] = "attack"
		pir._p[ri]["hp"] = 1.5
		pir._server_on_hurt(ri, Pirates.TYPES["rover"])
		if pir._p[ri]["mode"] == "flee":
			fled = true
			break
	_check(fled, "en hårdt ramt røver flygter")
	pir._p[ri]["fled"] = true
	pir._p[ri]["mode"] = "attack"
	pir._p[ri]["hp"] = 6.0
	var broke := 0
	for k in 40:
		pir._p[ri]["mode"] = "attack"
		pir._server_on_hurt(ri, Pirates.TYPES["rover"])
		if pir._p[ri]["mode"] == "break":
			broke += 1
	_check(broke > 4 and broke < 25, "pirater viger ud, når de bliver ramt (%d af 40)" % broke)
	pir.server_despawn_tag("rv")
	await _frames(2)

	# ---- Piratkaptajn: skjold, forstærkninger, stor dusør
	_park(base_pos)
	pir.server_send_wave("ravne", ship.position, pir.wave_mix("ravne", 4))
	await _frames(3)
	var bi := pir.boss_near(ship.position, "ravne")
	_check(bi >= 0 and pir.display_name(bi) in Pirates.CAPTAINS, "kaptajnen er her: %s" % (pir.display_name(bi) if bi >= 0 else "-"))
	_check(main.hud._boss.visible, "chefbjælken vises på HUD'en")
	var hp0 := float(pir._p[bi]["hp"])
	pir._srv_hit(bi, 5.0)
	await _frames(2)
	_check(float(pir._p[bi]["hp"]) == hp0 and pir.shield_fraction(bi) < 1.0, "skjoldet tager de første træffere (%.0f%% skjold)" % (pir.shield_fraction(bi) * 100.0))
	var before := _count_type("jaeger")
	pir._srv_hit(bi, 15.0 + hp0 * 0.55)
	await _frames(3)
	_check(_count_type("jaeger") == before + 2, "under halvdelen kalder den to lynjægere ind (%d → %d)" % [before, _count_type("jaeger")])
	if shots:
		_aim_at(pir.position_of(bi), 70.0)
		ship.lock_target = bi
		await _seconds(0.6)
		await _shot("C1_kaptajn")
	var cr := int(Game.wallet["credits"])
	var kills := int(Game.wallet.get("kills", 0))
	pir._srv_hit(bi, 999.0)
	await _frames(4)
	var gained := int(Game.wallet["credits"]) - cr
	_check(not pir.is_active(bi) and gained >= int(Game.combat("bounty")) * 7, "kaptajnen er nedkæmpet: +%d cr dusør" % gained)
	var crystals := 0
	for id: int in W.pickups._items:
		if W.pickups._items[id]["kind"] == "krystal":
			crystals += 1
	_check(crystals >= 3, "den taber krystaller (%d)" % crystals)
	await _frames(3)
	_check(not main.hud._boss.visible, "chefbjælken er væk igen")
	for k in Pirates.POOL:
		if pir.is_active(k):
			pir._cl_despawn(k)

	# ---- Testværktøj: send en bølge
	Game.request_test("pirates", "bolge")
	await _frames(4)
	_check(pir.positions_in("ravne", true).size() >= 2, "testknappen sender en bølge (%d pirater)" % pir.positions_in("ravne", true).size())
	for k in Pirates.POOL:
		if pir.is_active(k):
			pir._cl_despawn(k)

	if shots:
		await _gallery()

	print("RESULTAT: %s (%d fejl)" % ["BESTÅET" if failures == 0 else "FEJLET", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _gallery() -> void:
	_park(W.universe.origins["ravne"] + Vector3(600, 2600, -1800))
	var types := ["jaeger", "rover", "skygge", "missilbaad", "kanonbaad", "kaptajn"]
	main.hud.visible = false
	ship.visible = false
	var x := -30.0
	for t: String in types:
		var at := ship.position + Vector3(x, -2.0 + (3.0 if t == "kaptajn" else 0.0), -42 - (6.0 if t == "kaptajn" else 0.0))
		var i := pir.server_spawn_at("ravne", at, at + Vector3(-0.8, -0.25, 1.0) * 10.0, "gal", t)
		pir._p[i]["reveal"] = 999.0
		x += 10.0 if t not in ["kanonbaad", "missilbaad"] else 13.0
	# Frys dem på stedet
	set_physics_process(false)
	var t0 := 0.0
	while t0 < 0.8:
		for k in Pirates.POOL:
			if pir.is_active(k):
				pir._p[k]["speed"] = 0.0
				pir._p[k]["cool"] = 9.0
				pir._p[k]["mcool"] = 9.0
		await _frames(1)
		t0 += get_process_delta_time()
	main.camera.snap()
	await _shot("C0_piratgalleri")


func _count_type(t: String) -> int:
	var c := 0
	for k in Pirates.POOL:
		if pir.is_active(k) and pir.type_of(k) == t:
			c += 1
	return c


func _park(pos: Vector3) -> void:
	ship.position = pos
	ship.basis = Basis.IDENTITY
	ship.speed = 0.0
	ship.state = Ship.State.FLY
	ship.reset_physics_interpolation()
	main.camera.snap()


func _aim_at(p: Vector3, dist: float) -> void:
	var dir := (p - ship.position).normalized()
	ship.position = p - dir * dist + Vector3(0, 6, 0)
	ship.basis = Basis.looking_at((p - ship.position).normalized(), Vector3.UP)
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
