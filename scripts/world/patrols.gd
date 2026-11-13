class_name Patrols
extends Node3D
## Concord-patruljer: blå/hvide jagere, der flyver faste ruter i Concord-rum
## (mellem basen, stationen og planeterne). Når pirater dukker op i et system med
## Concord-sikkerhed, kommer patruljen til hjælp, og der sendes ekstra skibe ud
## fra basen. Værten styrer dem; klienterne får positioner ca. 10 gange i sekundet.

const POOL := 6
const HP := 40.0
const SPEED := 56.0
const ENGAGE_SPEED := 62.0
const TURN_RATE := 1.9
const SIGHT := 1500.0
const FIRE_INTERVAL := 0.35
const HIT_CHANCE := 0.45
const RESPAWN := 60.0
const SYNC_INTERVAL := 0.1
const PAINT := Color("2e6bd6")

var _p: Array[Dictionary] = []
var _routes: Dictionary = {}       ## system -> Array[Vector3]
var _homes: Dictionary = {}        ## system -> Vector3 (hvor ekstra patruljer letter fra)
var _sync_t := 0.0


func _ready() -> void:
	for i in POOL:
		var m := ShipModel.new()
		m.paint = PAINT
		m.visible = false
		add_child(m)
		_p.append({"node": m, "active": false, "system": "", "hp": HP, "mode": "patrol", "route": false,
			"idx": 0, "target": -1, "speed": 0.0, "cool": 0.0, "respawn": 0.0, "home": Vector3.ZERO,
			"net_pos": Vector3.ZERO, "net_rot": Quaternion.IDENTITY})
	for sys_id: String in Game.systems:
		var pts: Array[Vector3] = []
		var origin: Vector3 = W.universe.origins[sys_id]
		for st in W.universe.stations:
			if st.system_id == sys_id:
				pts.append(st.position + st.dock_dir * 160.0 + Vector3(0, 60, 0))
				if st.is_base:
					_homes[sys_id] = st.dock_pos
		for pl in W.universe.planets:
			if pl.system_id == sys_id:
				var d := (origin - pl.position).normalized()
				if d.length() < 0.5:
					d = pl.pad_dir
				pts.append(pl.position + d * (pl.radius + pl.atmo_top + 220.0))
				if not _homes.has(sys_id) and pl.data.get("patrol", false):
					_homes[sys_id] = pl.pad_top + pl.pad_dir * 20.0
		_routes[sys_id] = pts
	Net.started.connect(_on_net_started)
	Game.player_joined.connect(_on_player_joined)


func _on_net_started() -> void:
	for i in POOL:
		_p[i]["active"] = false
		(_p[i]["node"] as Node3D).visible = false
	if not W.is_server():
		return
	# Faste ruter i systemer med høj Concord-sikkerhed: to skibe på hver rute.
	for sys_id: String in Game.systems:
		if Pirates.security(sys_id) >= 0.7 and (_routes[sys_id] as Array).size() >= 2:
			for k in 2:
				var pts: Array = _routes[sys_id]
				var idx := (k * pts.size() / 2) % pts.size()
				_server_spawn(sys_id, pts[idx], true, idx)


# ---------------------------------------------------------------- server

func _server_spawn(sys_id: String, pos: Vector3, route: bool, idx := 0) -> int:
	for i in POOL:
		if _p[i]["active"] or float(_p[i]["respawn"]) > 0.0:
			continue
		var p: Dictionary = _p[i]
		p["system"] = sys_id
		p["hp"] = HP
		p["mode"] = "patrol" if route else "engage"
		p["route"] = route
		p["idx"] = idx
		p["target"] = -1
		p["speed"] = 30.0
		p["home"] = pos
		_cl_spawn.rpc(i, pos, Quaternion.IDENTITY)
		return i
	return -1


## Server: pirater er dukket op ved `pos`. Patruljen sendes derhen, og der letter
## ekstra skibe fra basen. Returnerer true, hvis der kommer hjælp.
func server_alert(sys_id: String, pos: Vector3) -> bool:
	var helpers := 0
	for p in _p:
		if p["active"] and p["system"] == sys_id:
			p["mode"] = "engage"
			p["alert"] = pos
			p["alert_t"] = 90.0
			helpers += 1
	if _homes.has(sys_id):
		for k in 2:
			var i := _server_spawn(sys_id, _homes[sys_id], false)
			if i >= 0:
				_p[i]["alert"] = pos
				_p[i]["alert_t"] = 90.0
				helpers += 1
	return helpers > 0


## Server: nærmeste patrulje som mål for en pirat (inden for max_d), ellers tom.
func server_nearest_target(from: Vector3, sys_id: String, max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for p in _p:
		if not p["active"] or p["system"] != sys_id:
			continue
		var n: Node3D = p["node"]
		var d := from.distance_to(n.position)
		if d < bd:
			bd = d
			best = {"pos": n.position, "vel": -n.global_basis.z * float(p["speed"])}
	return best


## Server: rammer et piratskud en patrulje?
func server_bolt_hit(pos: Vector3, dmg: float) -> bool:
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"] and pos.distance_to((p["node"] as Node3D).position) < 3.5:
			p["hp"] = float(p["hp"]) - dmg
			if p["hp"] <= 0.0:
				_cl_kill.rpc(i)
				p["respawn"] = RESPAWN
			return true
	return false


func positions_in(sys_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in _p:
		if p["active"] and p["system"] == sys_id:
			out.append((p["node"] as Node3D).position)
	return out


func _physics_process(delta: float) -> void:
	if W.is_server():
		for i in POOL:
			var p: Dictionary = _p[i]
			if float(p["respawn"]) > 0.0:
				p["respawn"] = float(p["respawn"]) - delta
				if p["respawn"] <= 0.0 and p["route"]:
					var pts: Array = _routes[p["system"]]
					_server_spawn(p["system"], pts[randi() % pts.size()], true, 0)
			if p["active"]:
				_server_ai(i, delta)
		_sync_t += delta
		if _sync_t >= SYNC_INTERVAL and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_sync_t = 0.0
			var pos := PackedVector3Array()
			var rot := PackedFloat32Array()
			for p in _p:
				var n: Node3D = p["node"]
				pos.append(n.position)
				var q := n.quaternion
				rot.append_array([q.x, q.y, q.z, q.w])
			_cl_state.rpc(pos, rot)
	else:
		var k := 1.0 - exp(-delta * 10.0)
		for p in _p:
			if p["active"]:
				var n: Node3D = p["node"]
				n.position = n.position.lerp(p["net_pos"], k)
				n.quaternion = n.quaternion.slerp(p["net_rot"], k)
	for p in _p:
		if p["active"]:
			(p["node"] as ShipModel).thrust = float(p["speed"]) / SPEED


func _server_ai(i: int, delta: float) -> void:
	var p: Dictionary = _p[i]
	var n: Node3D = p["node"]
	var pos := n.position
	var fwd := -n.global_basis.z
	# Find nærmeste pirat i systemet
	var target := -1
	var bd := SIGHT
	for k in Pirates.POOL:
		if W.pirates.is_active(k) and W.pirates.system_of(k) == p["system"]:
			var d := pos.distance_to(W.pirates.position_of(k))
			if d < bd:
				bd = d
				target = k
	var goal: Vector3
	var spd := SPEED
	if target >= 0:
		p["mode"] = "engage"
		var tp := W.pirates.position_of(target)
		var tv := W.pirates.velocity_of(target)
		goal = tp + tv * (bd / 300.0)
		spd = ENGAGE_SPEED if bd > 90.0 else 42.0
		p["cool"] = float(p["cool"]) - delta
		if bd < 320.0 and fwd.dot((goal - pos).normalized()) > 0.97 and p["cool"] <= 0.0:
			p["cool"] = FIRE_INTERVAL
			_cl_fire.rpc(pos + fwd * 3.0, (goal - pos).normalized())
			if randf() < HIT_CHANCE:
				W.pirates.server_damage(target, 1.0)
		if bd < 30.0:
			goal = pos + (pos - tp).normalized() * 80.0 + fwd * 40.0   # bryd af
	elif float(p.get("alert_t", 0.0)) > 0.0:
		# På vej til et alarmsted, hvor piraterne blev set
		p["alert_t"] = float(p["alert_t"]) - delta
		goal = p["alert"]
		spd = ENGAGE_SPEED
		if pos.distance_to(goal) < 150.0:
			p["alert_t"] = 0.0
	elif p["route"]:
		p["mode"] = "patrol"
		var pts: Array = _routes[p["system"]]
		goal = pts[p["idx"]]
		if pos.distance_to(goal) < 60.0:
			p["idx"] = (int(p["idx"]) + 1) % pts.size()
	else:
		# Ekstra patrulje: flyv hjem og land
		goal = p["home"]
		spd = SPEED
		if pos.distance_to(goal) < 40.0:
			_cl_despawn.rpc(i)
			return
	# Undgå planeter og stationer
	var dir := (goal - pos).normalized()
	if dir.length() < 0.5:
		dir = fwd
	var pl := W.universe.nearest_planet(pos)
	if pl.ground_altitude(pos) < 70.0:
		dir = (pos - pl.position).normalized()
	for st in W.universe.stations:
		if pos.distance_to(st.position) < 45.0 and goal.distance_to(st.position) > 60.0:
			dir = (pos - st.position).normalized()
	var want := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).get_rotation_quaternion()
	var ang := n.quaternion.angle_to(want)
	if ang > 0.0001:
		n.quaternion = n.quaternion.slerp(want, minf(1.0, TURN_RATE * delta / ang)).normalized()
	p["speed"] = lerpf(float(p["speed"]), spd, minf(1.0, delta * 1.2))
	n.position += -n.global_basis.z * float(p["speed"]) * delta


# ---------------------------------------------------------------- alle maskiner

@rpc("authority", "call_local", "reliable")
func _cl_spawn(i: int, pos: Vector3, rot: Quaternion) -> void:
	var p: Dictionary = _p[i]
	p["active"] = true
	p["net_pos"] = pos
	p["net_rot"] = rot
	var n: Node3D = p["node"]
	n.position = pos
	n.quaternion = rot
	n.reset_physics_interpolation()
	n.visible = true


@rpc("authority", "call_local", "reliable")
func _cl_despawn(i: int) -> void:
	_p[i]["active"] = false
	(_p[i]["node"] as Node3D).visible = false


@rpc("authority", "call_local", "reliable")
func _cl_kill(i: int) -> void:
	var n: Node3D = _p[i]["node"]
	_p[i]["active"] = false
	n.visible = false
	W.fx.explosion(n.position, true)
	Sfx.play_at("eksplosion_stor", n.position, 0.0)


@rpc("authority", "call_local", "unreliable")
func _cl_fire(pos: Vector3, dir: Vector3) -> void:
	W.bolts.fire(pos + dir.cross(Vector3.UP).normalized() * 1.5, dir, 300.0, Color("4d8bff"), Bolts.Kind.REMOTE)
	W.bolts.fire(pos - dir.cross(Vector3.UP).normalized() * 1.5, dir, 300.0, Color("4d8bff"), Bolts.Kind.REMOTE)
	Sfx.play_at("laser", pos, -8.0)


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_state(pos: PackedVector3Array, rot: PackedFloat32Array) -> void:
	for i in mini(pos.size(), POOL):
		_p[i]["net_pos"] = pos[i]
		_p[i]["net_rot"] = Quaternion(rot[i * 4], rot[i * 4 + 1], rot[i * 4 + 2], rot[i * 4 + 3])


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	for i in POOL:
		var p: Dictionary = _p[i]
		if p["active"]:
			var n: Node3D = p["node"]
			_cl_spawn.rpc_id(id, i, n.position, n.quaternion)
