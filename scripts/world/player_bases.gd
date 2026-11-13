class_name PlayerBases
extends Node3D
## Gruppens egne baser. Man køber en byggegrund (på en planet eller i rummet) og
## bygger moduler på den: udvinding, lager, forsvarstårne, skjold og hangar.
## Basen er fælles for hele gruppen. Udvindingen fylder lageret, mens I spiller
## (ikke når spillet er lukket), og af og til angriber pirater basen.
##
## Tilstanden ligger i Game.world["bases"] (gemmes af værten og sendes til alle).
## Alle køb og handlinger går gennem værten.

signal base_message(plot_id: String, text: String)

const K = preload("res://scripts/world/model_kit.gd")
const TURRET_RANGE := 420.0
const TURRET_INTERVAL := 1.0
const TURRET_DAMAGE := 1.5
const REGEN := 3.0                ## basens selvreparation pr. sekund med skjold
const BASE_HIT_RADIUS := 34.0

var _visual: Dictionary = {}      ## plot-id -> {root, anchor, turrets: Array[Node3D], bubble}
var _prod_t := 0.0
var _turret_t := 0.0
var _raid_t := -1.0
var _blink: Array = []


func _ready() -> void:
	Game.world_changed.connect(_rebuild_all)
	Net.started.connect(func():
		_raid_t = float(Game.bases_data["raid_first"])
		_rebuild_all())
	_rebuild_all.call_deferred()


# ---------------------------------------------------------------- forespørgsler

func plot_ids() -> Array:
	var out := []
	for p: Dictionary in Game.bases_data["plots"]:
		out.append(p["id"])
	return out


func is_plot(loc_id: String) -> bool:
	return not Game.plot_data(loc_id).is_empty()


func owned(plot_id: String) -> bool:
	return Game.base_state(plot_id).get("owned", false)


func level(plot_id: String, module_id: String) -> int:
	return int(Game.base_state(plot_id).get("modules", {}).get(module_id, 0))


func hp_max(plot_id: String) -> float:
	return float(Game.bases_data["base_hp"]) + (200.0 if level(plot_id, "skjold") > 0 else 0.0)


func storage_cap(plot_id: String) -> int:
	return int(Game.bases_data["storage_base"]) + 20 * level(plot_id, "lager")


func production_per_min(plot_id: String) -> int:
	return 2 * level(plot_id, "udvinding")


## Pris for næste niveau af et modul: {credits, goods}
func module_cost(plot_id: String, module_id: String) -> Dictionary:
	var m := Game.base_module_data(module_id)
	var lvl := level(plot_id, module_id)
	return {"credits": int(m["price"]) + int(m.get("price_step", 0)) * lvl, "goods": m.get("goods", {})}


## Basens position i verden (centrum).
func base_position(plot_id: String) -> Vector3:
	var plot := Game.plot_data(plot_id)
	if plot["kind"] == "ground":
		var po := W.universe.pad_of(plot_id)
		return (po["pad"]["top"] as Vector3) + (po["pad"]["dir"] as Vector3) * 6.0
	return W.universe.station(plot_id).position


func system_of(plot_id: String) -> String:
	var plot := Game.plot_data(plot_id)
	if plot["kind"] == "ground":
		return W.universe.planet(plot["planet"]).system_id
	return plot["system"]


func raid_active(plot_id: String) -> bool:
	return W.pirates != null and _raid_count(plot_id) > 0


func _raid_count(plot_id: String) -> int:
	var n := 0
	for i in Pirates.POOL:
		if W.pirates.is_active(i) and W.pirates._p[i]["tag"] == "raid_" + plot_id:
			n += 1
	return n


# ---------------------------------------------------------------- anmodninger (alle maskiner -> værten)

func request(action: String, plot_id: String, arg := "") -> void:
	_srv_request.rpc_id(1, action, plot_id, arg)


@rpc("any_peer", "call_local", "reliable")
func _srv_request(action: String, plot_id: String, arg: String) -> void:
	if not multiplayer.is_server():
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	if not Game.players.has(who) or not is_plot(plot_id):
		return
	var p: Dictionary = Game.players[who]
	var plot := Game.plot_data(plot_id)
	var bases: Dictionary = Game.world.get("bases", {})
	Game.world["bases"] = bases
	var st: Dictionary = bases.get(plot_id, {})
	var msg := ""
	match action:
		"buy":
			if st.get("owned", false):
				return
			var price := int(plot["price"])
			if int(p["credits"]) < price:
				msg = "Ikke nok kredit – byggegrunden koster %d cr" % price
			else:
				p["credits"] = int(p["credits"]) - price
				bases[plot_id] = {"owned": true, "modules": {}, "storage": 0, "hp": float(Game.bases_data["base_hp"])}
				msg = "%s er købt – byg moduler på den!" % plot["name"]
				for id: int in Game.players:
					if id != who:
						Game.server_toast(id, "%s købte %s til gruppen" % [p["name"], plot["name"]])
		"build":
			if not st.get("owned", false):
				return
			var m := Game.base_module_data(arg)
			if m.is_empty():
				return
			var lvl := level(plot_id, arg)
			if lvl >= int(m["max"]):
				msg = "%s er allerede fuldt udbygget" % m["name"]
			else:
				var cost := module_cost(plot_id, arg)
				var goods: Dictionary = cost["goods"]
				var missing := []
				for g: String in goods:
					if int(p["cargo"].get(g, 0)) < int(goods[g]):
						missing.append("%d %s" % [int(goods[g]), Game.good_name(g).to_lower()])
				if int(p["credits"]) < int(cost["credits"]):
					msg = "Ikke nok kredit (%d cr)" % int(cost["credits"])
				elif not missing.is_empty():
					msg = "Mangler i lastrummet: " + ", ".join(missing)
				else:
					p["credits"] = int(p["credits"]) - int(cost["credits"])
					for g: String in goods:
						p["cargo"][g] = int(p["cargo"][g]) - int(goods[g])
						if int(p["cargo"][g]) <= 0:
							p["cargo"].erase(g)
					var mods: Dictionary = st.get("modules", {})
					mods[arg] = lvl + 1
					st["modules"] = mods
					st["hp"] = minf(float(st.get("hp", 0.0)) + (200.0 if arg == "skjold" else 0.0), hp_max(plot_id))
					msg = "%s bygget (niveau %d)" % [m["name"], lvl + 1]
		"take":
			if not st.get("owned", false):
				return
			var res: String = plot["resource"]
			var n := 0
			while int(st.get("storage", 0)) > 0 and (arg == "all" or n < int(arg)) and Game.server_add_cargo(who, res):
				st["storage"] = int(st["storage"]) - 1
				n += 1
			msg = "+%d %s fra lageret" % [n, Game.good_name(res).to_lower()] if n > 0 else "Lastrummet er fuldt eller lageret tomt"
		"repair_base":
			var missing_hp := hp_max(plot_id) - float(st.get("hp", 0.0))
			var cost := int(ceil(missing_hp * 1.0))
			if cost <= 0:
				return
			var pay := mini(cost, int(p["credits"]))
			p["credits"] = int(p["credits"]) - pay
			st["hp"] = float(st.get("hp", 0.0)) + float(pay)
			msg = "Basen er repareret (%d cr)" % pay
		"repair_ship":
			if level(plot_id, "hangar") <= 0:
				return
			Game._cl_repaired.rpc_id(who, 100.0)
			msg = "Skibet er repareret – gratis i egen hangar"
		"missiles":
			if level(plot_id, "hangar") <= 0:
				return
			var have := int(p.get("missiles", 0))
			var n := mini(Game.missile_max_of(who) - have, int(p["credits"]) / 15)
			if n > 0:
				p["credits"] = int(p["credits"]) - n * 15
				p["missiles"] = have + n
				msg = "+%d missiler" % n
			else:
				msg = "Magasinet er fuldt" if have >= Game.missile_max_of(who) else "Ikke nok kredit"
	Game._send_wallet(who)
	Game.server_world_changed()
	if msg != "":
		_cl_message.rpc_id(who, plot_id, msg)


@rpc("authority", "call_local", "reliable")
func _cl_message(plot_id: String, text: String) -> void:
	Game.toast.emit(text)
	base_message.emit(plot_id, text)


# ---------------------------------------------------------------- server: produktion, tårne og angreb

func _physics_process(delta: float) -> void:
	_animate()
	if not W.is_server():
		return
	var bases: Dictionary = Game.world.get("bases", {})
	if bases.is_empty():
		return
	# Udvinding fylder lageret
	_prod_t += delta
	if _prod_t >= float(Game.bases_data["production_interval"]):
		_prod_t = 0.0
		var changed := false
		for plot_id: String in bases:
			var st: Dictionary = bases[plot_id]
			if not st.get("owned", false) or float(st.get("hp", 0.0)) <= 0.0:
				continue
			var add := production_per_min(plot_id) / 2
			if add > 0:
				var before := int(st.get("storage", 0))
				st["storage"] = mini(storage_cap(plot_id), before + add)
				changed = changed or int(st["storage"]) != before
		if changed:
			Game.server_world_changed()
	# Forsvarstårne og selvreparation
	_turret_t -= delta
	var fire := _turret_t <= 0.0
	if fire:
		_turret_t = TURRET_INTERVAL
	for plot_id: String in bases:
		var st: Dictionary = bases[plot_id]
		if not st.get("owned", false):
			continue
		var raided := raid_active(plot_id)
		if level(plot_id, "skjold") > 0 and not raided and float(st.get("hp", 0.0)) < hp_max(plot_id) and float(st.get("hp", 0.0)) > 0.0:
			st["hp"] = minf(hp_max(plot_id), float(st["hp"]) + REGEN * delta)
		if fire and level(plot_id, "taarn") > 0 and float(st.get("hp", 0.0)) > 0.0:
			var c := base_position(plot_id)
			for k in level(plot_id, "taarn"):
				var target := W.pirates.server_nearest(c, TURRET_RANGE)
				if target < 0:
					break
				W.pirates.server_damage(target, TURRET_DAMAGE)
				_cl_turret_shot.rpc(plot_id, k, W.pirates.position_of(target))
	# Piratangreb
	if W.missions and W.missions.active:
		return
	_raid_t -= delta
	if _raid_t <= 0.0:
		var r: Array = Game.bases_data["raid_interval"]
		_raid_t = randf_range(float(r[0]), float(r[1]))
		_server_start_raid()


func _server_start_raid() -> void:
	# Kun baser i et system, hvor nogen flyver lige nu, så man kan nå at forsvare dem.
	var candidates := []
	for plot_id: String in Game.world.get("bases", {}):
		if not owned(plot_id) or raid_active(plot_id) or float(Game.base_state(plot_id).get("hp", 0.0)) <= 0.0:
			continue
		for s in W.active_ships():
			if W.universe.system_at(s.position) == system_of(plot_id):
				candidates.append(plot_id)
				break
	if candidates.is_empty():
		return
	server_raid(candidates.pick_random())


## Server (og tests): send pirater mod en base.
func server_raid(plot_id: String) -> void:
	var c := base_position(plot_id)
	var sys := system_of(plot_id)
	var up := Vector3.UP
	var plot := Game.plot_data(plot_id)
	if plot["kind"] == "ground":
		var p := W.universe.planet(plot["planet"])
		up = (c - p.position).normalized()
	var n := 3 + maxi(0, Game.players.size() - 1)
	for k in n:
		var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized().rotated(up, TAU * k / n)
		var pos := c + up * 260.0 + side * 280.0
		W.pirates.server_spawn_at(sys, pos, c, "raid_" + plot_id)
	if W.patrols and Pirates.security(sys) > 0.3:
		W.patrols.server_alert(sys, c)
	for id: int in Game.players:
		Game.server_toast(id, "⚠ %d pirater angriber jeres base: %s!" % [n, plot["name"]])


## Server: mål for piraterne i et angreb (basens centrum).
func server_raid_target(tag: String) -> Dictionary:
	var plot_id := tag.trim_prefix("raid_")
	if not owned(plot_id) or float(Game.base_state(plot_id).get("hp", 0.0)) <= 0.0:
		return {}
	return {"pos": base_position(plot_id), "vel": Vector3.ZERO}


## Server: rammer et piratskud en base?
func server_bolt_hit(pos: Vector3, dmg: float) -> bool:
	var bases: Dictionary = Game.world.get("bases", {})
	for plot_id: String in bases:
		var st: Dictionary = bases[plot_id]
		if not st.get("owned", false) or float(st.get("hp", 0.0)) <= 0.0:
			continue
		if pos.distance_to(base_position(plot_id)) < BASE_HIT_RADIUS:
			st["hp"] = maxf(0.0, float(st["hp"]) - dmg)
			if st["hp"] <= 0.0:
				st["storage"] = 0
				W.pirates.server_despawn_tag("raid_" + plot_id)
				for id: int in Game.players:
					Game.server_toast(id, "%s er sat ud af drift! Lageret er plyndret – reparer basen." % Game.plot_data(plot_id)["name"])
				Game.server_world_changed()
			elif int(st["hp"]) % 25 == 0:
				Game.server_world_changed()
			return true
	return false


@rpc("authority", "call_local", "unreliable")
func _cl_turret_shot(plot_id: String, k: int, to: Vector3) -> void:
	var v: Dictionary = _visual.get(plot_id, {})
	var turrets: Array = v.get("turrets", [])
	var from := base_position(plot_id) if turrets.is_empty() else (turrets[k % turrets.size()] as Node3D).global_position
	W.bolts.fire(from, (to - from).normalized(), 340.0, Color("6bdc4f"), Bolts.Kind.REMOTE)
	Sfx.play_at("taarn", from, -4.0)


# ---------------------------------------------------------------- grafik

func _rebuild_all() -> void:
	if W.universe == null:
		return
	for plot_id in plot_ids():
		_rebuild(plot_id)


func _anchor(plot_id: String) -> Node3D:
	var plot := Game.plot_data(plot_id)
	if plot["kind"] == "ground":
		var p := W.universe.planet(plot["planet"])
		return p.get_node_or_null("Pad_" + plot_id)
	var st := W.universe.station(plot_id)
	return st.get_node_or_null("Body") if st else null


func _rebuild(plot_id: String) -> void:
	var st := Game.base_state(plot_id)
	var mods: Dictionary = st.get("modules", {})
	var key := "%s|%s|%d" % [str(st.get("owned", false)), JSON.stringify(mods), int(float(st.get("hp", 0.0)) > 0.0)]
	var v: Dictionary = _visual.get(plot_id, {})
	if v.get("key", "") == key:
		return
	if v.has("root") and is_instance_valid(v["root"]):
		(v["root"] as Node3D).queue_free()
	var anchor := _anchor(plot_id)
	if anchor == null:
		return
	var root := Node3D.new()
	root.name = "PlayerBase"
	anchor.add_child(root)
	v = {"key": key, "root": root, "turrets": [], "bubble": null}
	_visual[plot_id] = v
	if not st.get("owned", false):
		return
	var plot := Game.plot_data(plot_id)
	if plot["kind"] == "ground":
		_build_ground(plot_id, plot, root, mods, v)
	else:
		_build_space(plot_id, plot, root, mods, v)


## Moduler rundt om landingspladsen på en planet: på faste pladser i en ring.
func _build_ground(plot_id: String, plot: Dictionary, root: Node3D, mods: Dictionary, v: Dictionary) -> void:
	var p := W.universe.planet(plot["planet"])
	var pad := p.pad_by_id(plot_id)
	var slots := [Vector2(-30, -14), Vector2(30, -14), Vector2(-30, 20), Vector2(30, 20), Vector2(0, -36), Vector2(0, 38),
		Vector2(-44, 4), Vector2(44, 4), Vector2(-20, 44), Vector2(20, 44), Vector2(-20, -44), Vector2(20, -44)]
	var si := 0
	var steel := K.hull(Color("8a8fb0"), K.TEX_PLATING, 0.4)
	var green := K.hull(Color("6bdc4f"), K.TEX_PLATING, 0.5)
	# Kommandomodul (altid med, når grunden er købt)
	var hq := CityBuilder._place(p, pad, root, 0.0, 0.0, 0.0)
	K.add(hq, K.box(10.0, 3.0, 2.0), green, Vector3(16.0, 1.0, 0))
	K.add(hq, K.cyl(0.2, 0.3, 12.0, 4), K.flat(Color("d9d2ff")), Vector3(16.0, 7.0, 0))
	K.add(hq, K.box(3.0, 2.0, 0.15), K.hull(Color("6bdc4f")), Vector3(17.6, 11.5, 0))
	_blink.append(K.add(hq, K.box(0.7, 0.7, 0.7), K.glow(Color("6bdc4f")), Vector3(16.0, 13.3, 0)))
	for k in int(mods.get("udvinding", 0)):
		var n := CityBuilder._place(p, pad, root, slots[si].x, slots[si].y, 0.0, k * 0.7)
		si += 1
		for c: Vector2 in [Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)]:
			K.add(n, K.box(0.5, 20.0, 0.5), K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5), Vector3(c.x, 10.0, c.y))
		for y in range(3, 20, 5):
			K.add(n, K.box(4.4, 0.3, 0.3), K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5), Vector3(0, y, 2.0))
		K.add(n, K.cyl(0.8, 0.8, 26.0, 8), steel, Vector3(0, 6.0, 0))
		K.add(n, K.cyl(4.0, 5.0, 2.5, 10), K.hull(Color("3a2d24"), K.TEX_PLATING, 0.3), Vector3(0, 0.5, 0))
		var res_col := Game.col(Game.goods[plot["resource"]]["color"])
		K.add(n, K.cyl(0.0, 3.5, 3.0, 7), K.hull(res_col, K.TEX_PLATING, 0.6), Vector3(5.5, 1.0, 0))
		_blink.append(K.add(n, K.box(0.6, 0.6, 0.6), K.glow(Color("ff3b3b")), Vector3(0, 20.6, 0)))
	for k in int(mods.get("lager", 0)):
		var n := CityBuilder._place(p, pad, root, slots[si].x, slots[si].y)
		si += 1
		for j in 3:
			K.add(n, K.cyl(3.0, 3.0, 12.0, 10), K.hull(Color("e6ecff"), K.TEX_PLATING, 0.4), Vector3(-7.0 + j * 7.0, 5.0, 0))
			K.add(n, K.sphere(3.0, 10, 4), K.hull(Color("e6ecff"), K.TEX_PLATING, 0.4), Vector3(-7.0 + j * 7.0, 11.0, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
		K.add(n, K.box(21.0, 0.8, 6.4), K.stripes(0.6), Vector3(0, 2.0, 0))
	if int(mods.get("hangar", 0)) > 0:
		var n := CityBuilder._place(p, pad, root, slots[si].x, slots[si].y, 0.0, PI / 2)
		si += 1
		K.add(n, K.box(18.0, 12.0, 14.0), K.hull(Color("2e6bd6")), Vector3(0, 3.0, 0))
		K.add(n, K.cyl(7.0, 7.0, 18.0, 10), K.hull(Color("1f3f8a"), K.TEX_ROOF, 0.4), Vector3(0, 9.0, 0), Vector3(0, 0, PI / 2))
		K.add(n, K.box(10.0, 7.0, 0.6), K.stripes(0.5), Vector3(0, 1.5, 7.1))
		K.add(n, K.box(8.6, 6.0, 0.8), K.flat(Color("1a1028")), Vector3(0, 1.4, 7.2))
	if int(mods.get("skjold", 0)) > 0:
		var n := CityBuilder._place(p, pad, root, slots[si].x, slots[si].y)
		si += 1
		K.add(n, K.cyl(3.0, 4.0, 6.0, 10), K.hull(Color("e6ecff")), Vector3(0, 2.0, 0))
		K.add(n, K.torus(3.4, 0.8, 12, 4), K.glow(Color("4dffe1")), Vector3(0, 5.4, 0))
		K.add(n, K.sphere(2.0, 10, 6), K.glow(Color("9ff2ff")), Vector3(0, 7.0, 0))
		v["bubble"] = _bubble(root, CityBuilder._frame(p, pad, 0.0, 0.0).origin, 62.0)
	for k in int(mods.get("taarn", 0)):
		var n := CityBuilder._place(p, pad, root, slots[si].x, slots[si].y)
		si += 1
		K.add(n, K.cyl(2.4, 3.0, 8.0, 10), steel, Vector3(0, 2.0, 0))
		var head := Node3D.new()
		head.position = Vector3(0, 7.2, 0)
		n.add_child(head)
		K.add(head, K.box(3.4, 2.0, 3.4), green, Vector3.ZERO)
		for s in [-0.6, 0.6]:
			K.add(head, K.cyl(0.2, 0.28, 4.0, 6), K.flat(Color("3a3f5a")), Vector3(s, 0.2, -3.0), Vector3(-PI / 2, 0, 0))
		(v["turrets"] as Array).append(head)


## Moduler på en rumplatform: et nav med arme ud til modulerne.
func _build_space(plot_id: String, plot: Dictionary, root: Node3D, mods: Dictionary, v: Dictionary) -> void:
	var white := K.hull(Color("e6ecff"))
	var green := K.hull(Color("6bdc4f"), K.TEX_PLATING, 0.5)
	var steel := K.hull(Color("5a5f8a"), K.TEX_PLATING, 0.4)
	K.add(root, K.cyl(7.0, 7.0, 14.0, 12), white, Vector3(0, 0, -6), Vector3(PI / 2, 0, 0))
	K.add(root, K.cyl(7.2, 7.2, 2.0, 12), K.windows(0.6), Vector3(0, 0, -6), Vector3(PI / 2, 0, 0))
	K.add(root, K.torus(9.0, 2.0, 16, 6), green, Vector3(0, 0, 4), Vector3(PI / 2, 0, 0))
	_blink.append(K.add(root, K.box(1.0, 1.0, 1.0), K.glow(Color("6bdc4f")), Vector3(0, 9.5, -6)))
	var slots := [Vector3(26, 0, -6), Vector3(-26, 0, -6), Vector3(0, 26, -6), Vector3(0, -26, -6),
		Vector3(19, 19, -14), Vector3(-19, 19, -14), Vector3(19, -19, -14), Vector3(-19, -19, -14), Vector3(0, 0, -30), Vector3(0, 18, 6), Vector3(0, -18, 6), Vector3(18, 0, 6)]
	var si := 0
	var arm := func(to: Vector3) -> void:
		var mid := to / 2.0
		var mi := K.add(root, K.box(1.4, 1.4, to.length()), steel, mid)
		mi.basis = Basis.looking_at(to.normalized(), Vector3.UP if absf(to.normalized().y) < 0.95 else Vector3.RIGHT)
	for k in int(mods.get("udvinding", 0)):
		var s: Vector3 = slots[si]
		si += 1
		arm.call(s)
		var n := K.add(root, K.box(6.0, 6.0, 6.0), K.hull(Color("ffd23f"), K.TEX_PLATING, 0.5), s)
		K.add(n, K.cyl(0.6, 1.2, 9.0, 8), steel, Vector3(0, 0, -6.0), Vector3(PI / 2, 0, 0))
		_blink.append(K.add(n, K.box(0.8, 0.8, 0.8), K.glow(Color("ff7a3d")), Vector3(0, 0, -10.8)))
	for k in int(mods.get("lager", 0)):
		var s: Vector3 = slots[si]
		si += 1
		arm.call(s)
		var cols := [Color("ff9e3d"), Color("4dd0ff"), Color("c77dff"), Color("6bdc4f")]
		for j in 4:
			K.add(root, K.box(4.0, 4.0, 6.0), K.hull(cols[j], K.TEX_PLATING, 0.6), s + Vector3((j % 2) * 4.4 - 2.2, (j / 2) * 4.4 - 2.2, 0))
	if int(mods.get("hangar", 0)) > 0:
		var s: Vector3 = slots[si]
		si += 1
		arm.call(s)
		K.add(root, K.box(12.0, 8.0, 14.0), K.hull(Color("2e6bd6")), s)
		K.add(root, K.box(8.0, 5.0, 0.6), K.flat(Color("1a1028")), s + Vector3(0, 0, 7.1))
	if int(mods.get("skjold", 0)) > 0:
		var s: Vector3 = slots[si]
		si += 1
		arm.call(s)
		K.add(root, K.sphere(3.0, 10, 6), K.glow(Color("9ff2ff")), s)
		K.add(root, K.torus(4.0, 0.8, 12, 4), K.hull(Color("e6ecff")), s)
		v["bubble"] = _bubble(root, Vector3.ZERO, 46.0)
	for k in int(mods.get("taarn", 0)):
		var s: Vector3 = slots[si]
		si += 1
		arm.call(s)
		K.add(root, K.cyl(2.4, 2.4, 2.0, 10), steel, s)
		var head := Node3D.new()
		head.position = s + s.normalized() * 2.0
		root.add_child(head)
		K.add(head, K.box(3.2, 2.0, 3.2), green, Vector3.ZERO)
		for side in [-0.6, 0.6]:
			K.add(head, K.cyl(0.2, 0.28, 4.0, 6), K.flat(Color("3a3f5a")), Vector3(side, 0.2, -3.0), Vector3(-PI / 2, 0, 0))
		(v["turrets"] as Array).append(head)


func _bubble(parent: Node3D, pos: Vector3, r: float) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	b.mesh = K.sphere(r, 24, 12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.4, 1.0, 0.6, 0.06)
	b.material_override = m
	b.position = pos
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(b)
	return b


func _animate() -> void:
	var t := Time.get_ticks_msec()
	var on := (t / 500) % 2 == 0
	_blink = _blink.filter(func(l): return is_instance_valid(l))
	for l in _blink:
		(l as MeshInstance3D).visible = on
	# Tårnene drejer mod nærmeste pirat
	if W.pirates == null:
		return
	for plot_id: String in _visual:
		var v: Dictionary = _visual[plot_id]
		for h: Node3D in v.get("turrets", []):
			if not is_instance_valid(h):
				continue
			var target := W.pirates.nearest_visible(h.global_position, TURRET_RANGE)
			if target != Vector3.INF:
				var dir := (target - h.global_position).normalized()
				h.global_basis = Basis.looking_at(dir, h.get_parent_node_3d().global_basis.y)
		var bubble = v.get("bubble")
		if bubble and is_instance_valid(bubble):
			(bubble as MeshInstance3D).visible = float(Game.base_state(plot_id).get("hp", 0.0)) > 0.0
