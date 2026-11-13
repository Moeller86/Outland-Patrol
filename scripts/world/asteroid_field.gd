class_name AsteroidField
extends Node3D
## Asteroidebælter fra universe.json. Alle maskiner genererer de samme sten ud fra
## et seed. Værten bestemmer, hvornår en sten sprænges og dukker op igen.

const RESPAWN_TIME := 25.0

var _rocks: Array[Dictionary] = []      ## {node, r, hp, alive, kind, center, spread, spin, respawn}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for sys_id: String in Game.systems:
		var sys: Dictionary = Game.systems[sys_id]
		var origin := Game.vec(sys["origin"])
		for field: Dictionary in sys.get("asteroids", []):
			_build_field(origin, field)
	Game.player_joined.connect(_on_player_joined)


func _build_field(origin: Vector3, f: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f["seed"])
	var center := origin + Game.vec(f["center"])
	var spread := Game.vec(f["spread"])
	var crystal: bool = f["kind"] == "krystal"
	var colors: Array = f["colors"]
	for i in int(f["count"]):
		var r := rng.randf_range(3.0, 10.0)
		var mesh: Mesh
		if crystal:
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = r * 0.8
			c.height = r * 2.6
			c.radial_segments = 4
			c.rings = 1
			mesh = c
		else:
			var s := SphereMesh.new()
			s.radius = r
			s.height = r * 2.0
			s.radial_segments = 5
			s.rings = 3
			mesh = s
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Game.col(colors[i % colors.size()])
		mat.roughness = 1.0
		if crystal:
			mat.emission_enabled = true
			mat.emission = Color("3a1a5a")
		mi.material_override = mat
		mi.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.4), rng.randf_range(0.8, 1.3))
		mi.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var pos := center + Vector3(rng.randf_range(-1, 1) * spread.x, rng.randf_range(-1, 1) * spread.y, rng.randf_range(-1, 1) * spread.z)
		if pos.distance_to(origin) < 60.0:
			pos += (pos - origin).normalized() * 60.0
		mi.position = pos
		add_child(mi)
		_rocks.append({"node": mi, "r": r, "hp": ceilf(r / 2.5), "alive": true, "kind": f["kind"],
			"center": center, "spread": spread, "origin": origin,
			"spin": Vector3(rng.randf_range(-.6, .6), rng.randf_range(-.6, .6), rng.randf_range(-.6, .6)), "respawn": 0.0})


func _process(delta: float) -> void:
	var server := W.is_server()
	for i in _rocks.size():
		var a: Dictionary = _rocks[i]
		if a["alive"]:
			var n: MeshInstance3D = a["node"]
			n.rotation += (a["spin"] as Vector3) * delta
		elif server:
			a["respawn"] -= delta
			if a["respawn"] <= 0.0:
				var c: Vector3 = a["center"]
				var sp: Vector3 = a["spread"]
				var pos := c + Vector3(_rng.randf_range(-1, 1) * sp.x, _rng.randf_range(-1, 1) * sp.y, _rng.randf_range(-1, 1) * sp.z)
				_cl_respawn.rpc(i, pos)


## Lokalt skud: rammer det en sten, meldes det til værten.
func hit_test(p: Vector3, dmg: float) -> bool:
	for i in _rocks.size():
		var a: Dictionary = _rocks[i]
		if a["alive"] and p.distance_to((a["node"] as Node3D).position) < float(a["r"]) + 1.2:
			_srv_hit.rpc_id(1, i, dmg)
			return true
	return false


## Lokalt skib: kollision med en sten. Returnerer true og sprænger stenen.
func collide(p: Vector3, radius: float) -> bool:
	for i in _rocks.size():
		var a: Dictionary = _rocks[i]
		if a["alive"] and p.distance_to((a["node"] as Node3D).position) < float(a["r"]) + radius:
			_srv_hit.rpc_id(1, i, 99.0)
			return true
	return false


@rpc("any_peer", "call_local", "reliable")
func _srv_hit(i: int, dmg: float) -> void:
	if not multiplayer.is_server() or i < 0 or i >= _rocks.size():
		return
	var a: Dictionary = _rocks[i]
	if not a["alive"]:
		return
	a["hp"] -= dmg
	if a["hp"] > 0.0:
		return
	var pos: Vector3 = (a["node"] as Node3D).position
	var r: float = a["r"]
	var drops := 1 + int(r / 6.0) if a["kind"] == "krystal" else 1 + int(r / 4.0)
	W.pickups.server_spawn(a["kind"], pos, drops)
	_cl_destroy.rpc(i)


@rpc("authority", "call_local", "reliable")
func _cl_destroy(i: int) -> void:
	Sfx.play_at("sten", (_rocks[i]["node"] as Node3D).position, -1.0)
	var a: Dictionary = _rocks[i]
	a["alive"] = false
	a["respawn"] = RESPAWN_TIME
	var n: MeshInstance3D = a["node"]
	n.visible = false
	W.fx.explosion(n.position)


@rpc("authority", "call_local", "reliable")
func _cl_respawn(i: int, pos: Vector3) -> void:
	var a: Dictionary = _rocks[i]
	a["alive"] = true
	a["hp"] = ceilf(float(a["r"]) / 2.5)
	var n: MeshInstance3D = a["node"]
	n.position = pos
	n.visible = true


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	var alive := PackedByteArray()
	var pos := PackedVector3Array()
	for a in _rocks:
		alive.append(1 if a["alive"] else 0)
		pos.append((a["node"] as Node3D).position)
	_cl_sync.rpc_id(id, alive, pos)


@rpc("authority", "call_remote", "reliable")
func _cl_sync(alive: PackedByteArray, pos: PackedVector3Array) -> void:
	for i in mini(alive.size(), _rocks.size()):
		var a: Dictionary = _rocks[i]
		a["alive"] = alive[i] == 1
		a["respawn"] = RESPAWN_TIME
		var n: MeshInstance3D = a["node"]
		n.position = pos[i]
		n.visible = a["alive"]
