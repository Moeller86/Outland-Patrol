class_name Freighters
extends Node3D
## NPC-fragtskibe, der flyver deres rute for sig selv: dok ved stationen →
## trade lane → landing ved planeten og tilbage. Hver levering trykker prisen på
## varen, de bringer. Pirater angriber dem; et sprængt fragtskib taber sine kasser.
## Værten simulerer, og klienterne får positioner ca. 10 gange i sekundet.

const HP := 30.0
const RESPAWN := 40.0
const SYNC_INTERVAL := 0.1

var _f: Array[Dictionary] = []
var _routes: Array[Dictionary] = []    ## {system, points, home, away, cargo_out, cargo_home}
var _sync_t := 0.0
var _warn_t := -99.0


func _ready() -> void:
	for sys_id: String in Game.systems:
		var sys: Dictionary = Game.systems[sys_id]
		if not sys.has("freighters"):
			continue
		var cfg: Dictionary = sys["freighters"]
		var st := W.universe.station(cfg["from"])
		var pl := W.universe.planet(cfg["to"])
		var lane := {}
		for l in W.universe.lanes:
			if l["system"] == sys_id:
				lane = l
		var side := pl.tangent * 16.0
		var points := [st.dock_pos, st.dock_pos + st.dock_dir * 30.0, lane["a"], lane["b"],
			pl.pad_top + pl.pad_dir * 60.0 + side, pl.pad_top + pl.pad_dir * 3.0 + side]
		var route := {"system": sys_id, "points": points, "home": cfg["from"], "away": cfg["to"],
			"cargo_out": cfg["cargo_out"], "cargo_home": cfg["cargo_home"]}
		_routes.append(route)
		var starts := [1, 3, 4, 2]
		for i in int(cfg["count"]):
			var g := _build_model()
			add_child(g)
			var idx: int = starts[i % starts.size()]
			g.position = points[idx]
			_f.append({"node": g, "route": route, "idx": idx, "dir": -1 if i % 2 else 1, "wait": 0.0,
				"hp": HP, "dead": false, "docked": false, "net_pos": g.position, "net_rot": Quaternion.IDENTITY})
	Game.player_joined.connect(_on_player_joined)


## Server: nærmeste fragtskib i rummet, som pirater kan angribe.
func server_nearest_target(pos: Vector3, sys_id: String) -> Dictionary:
	var best := {}
	var bd := 700.0
	for f in _f:
		var n: Node3D = f["node"]
		if f["dead"] or f["docked"] or not n.visible or f["route"]["system"] != sys_id:
			continue
		var pl := W.universe.nearest_planet(n.position)
		if pl.ground_altitude(n.position) < 90.0:
			continue
		var d := n.position.distance_to(pos)
		if d < bd:
			bd = d
			best = {"pos": n.position, "vel": -n.global_basis.z * 30.0}
	return best


## Til kortet: positioner af synlige fragtskibe i et system.
func positions_in(sys_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for f in _f:
		var n: Node3D = f["node"]
		if not f["dead"] and n.visible and f["route"]["system"] == sys_id:
			out.append(n.position)
	return out


## Server: rammer et piratskud et fragtskib?
func server_bolt_hit(p: Vector3, dmg: float) -> bool:
	for i in _f.size():
		var f: Dictionary = _f[i]
		var n: Node3D = f["node"]
		if f["dead"] or f["docked"] or not n.visible or p.distance_to(n.position) > 6.0:
			continue
		f["hp"] -= dmg
		var now := Time.get_ticks_msec() / 1000.0
		if now - _warn_t > 15.0:
			_warn_t = now
			for s in W.active_ships():
				if s.position.distance_to(n.position) < 1500.0:
					Game.server_toast(s.peer_id, "Nødsignal: fragtskib under angreb!")
		if f["hp"] <= 0.0:
			var route: Dictionary = f["route"]
			var kind: String = route["cargo_out"] if f["dir"] > 0 else route["cargo_home"]
			W.pickups.server_spawn(kind, n.position, 3)
			_cl_destroy.rpc(i)
		return true
	return false


func _physics_process(delta: float) -> void:
	if W.is_server():
		for f in _f:
			_server_move(f, delta)
		_sync_t += delta
		if _sync_t >= SYNC_INTERVAL and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_sync_t = 0.0
			var pos := PackedVector3Array()
			var rot := PackedFloat32Array()
			var vis := PackedByteArray()
			for f in _f:
				var n: Node3D = f["node"]
				pos.append(n.position)
				var q := n.quaternion
				rot.append_array([q.x, q.y, q.z, q.w])
				vis.append(1 if n.visible else 0)
			_cl_state.rpc(pos, rot, vis)
	else:
		var k := 1.0 - exp(-delta * 10.0)
		for f in _f:
			var n: Node3D = f["node"]
			if n.position.distance_to(f["net_pos"]) > 200.0:
				n.position = f["net_pos"]
			n.position = n.position.lerp(f["net_pos"], k)
			n.quaternion = n.quaternion.slerp(f["net_rot"], k)
	for f in _f:
		var fl: Node3D = (f["node"] as Node3D).get_meta("flame")
		fl.scale = Vector3(1, 0.8 + randf() * 0.2, 1)


func _server_move(f: Dictionary, delta: float) -> void:
	var n: Node3D = f["node"]
	var route: Dictionary = f["route"]
	var pts: Array = route["points"]
	if f["dead"]:
		f["wait"] -= delta
		if f["wait"] <= 0.0:
			f["dead"] = false
			f["hp"] = HP
			f["idx"] = 1
			f["dir"] = 1
			f["docked"] = true
			f["wait"] = 4.0
			n.position = pts[0]
		return
	if f["wait"] > 0.0:
		f["wait"] -= delta
		if f["wait"] <= 0.0:
			n.visible = true
			f["docked"] = false
		return
	var idx: int = f["idx"]
	var from: int = idx - int(f["dir"])
	var target: Vector3 = pts[idx]
	var on_lane := mini(idx, from) == 2 and maxi(idx, from) == 3
	var spd := Universe.LANE_SPEED if on_lane else (14.0 if idx == 0 or idx == pts.size() - 1 else 32.0)
	var to := target - n.position
	var d := to.length()
	if d > 0.5:
		var want := Basis.looking_at(to / d, Vector3.UP if absf(to.y / d) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
		n.quaternion = n.quaternion.slerp(want, minf(1.0, delta * (8.0 if on_lane else 1.5)))
	var step := spd * delta
	if d <= step:
		n.position = target
		var nxt := idx + int(f["dir"])
		if nxt < 0 or nxt >= pts.size():
			var at_home := idx == 0
			# Levering trykker prisen på det, der bliver leveret.
			if at_home:
				Game.server_nudge_price(route["home"], route["cargo_home"], 0.92)
			else:
				Game.server_nudge_price(route["away"], route["cargo_out"], 0.92)
			f["dir"] = -int(f["dir"])
			f["idx"] = idx + int(f["dir"])
			f["wait"] = randf_range(8.0, 14.0)
			if at_home:
				n.visible = false
				f["docked"] = true
		else:
			f["idx"] = nxt
	else:
		n.position += to / d * step


@rpc("authority", "call_local", "reliable")
func _cl_destroy(i: int) -> void:
	var f: Dictionary = _f[i]
	var n: Node3D = f["node"]
	W.fx.explosion(n.position, true)
	Sfx.play_at("eksplosion_stor", n.position, 2.0)
	n.visible = false
	f["dead"] = true
	f["wait"] = RESPAWN


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_state(pos: PackedVector3Array, rot: PackedFloat32Array, vis: PackedByteArray) -> void:
	for i in mini(pos.size(), _f.size()):
		var f: Dictionary = _f[i]
		f["net_pos"] = pos[i]
		f["net_rot"] = Quaternion(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])
		(f["node"] as Node3D).visible = vis[i] == 1


func _on_player_joined(_id: int) -> void:
	pass   # Positionerne kommer med den næste statusopdatering.


func _build_model() -> Node3D:
	return ShipModels.freighter()
