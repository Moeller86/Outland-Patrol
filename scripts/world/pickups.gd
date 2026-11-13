class_name Pickups
extends Node3D
## Ting der kan samles op: malm, krystaller og fragtkasser. Værten opretter dem
## og afgør, hvem der får dem. Hver maskine trækker dem visuelt mod sit eget skib.

const LIFE := 45.0
const MAGNET_RANGE := 24.0
const TRACTOR_RANGE := 150.0    ## traktorstrålen (specialudstyr, hold Z)
const TAKE_RANGE := 3.2
const JETTISON_GRACE := 6.0     ## sekunder, før man kan samle sin egen udsmidte last op igen

var _items: Dictionary = {}     ## id -> {node, kind, vel, life, asked}
var _next_id := 1
var _meshes: Dictionary = {}


func _ready() -> void:
	Game.player_joined.connect(_on_player_joined)


## Server: læg `count` stk. af en vare ud omkring `pos`.
func server_spawn(kind: String, pos: Vector3, count: int) -> void:
	if not W.is_server():
		return
	for k in count:
		var p := pos + Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
		var v := Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		_cl_spawn.rpc(_next_id, kind, p, v, 0, 0.0)
		_next_id += 1


## Server: last smidt ud af en spillers lastrum. Kasserne driver bagud, og ejeren
## trækker dem ikke til sig igen de første sekunder.
func server_jettison(kind: String, pos: Vector3, vel: Vector3, count: int, owner: int) -> void:
	if not W.is_server():
		return
	for k in count:
		var p := pos + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		var v := vel + Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
		_cl_spawn.rpc(_next_id, kind, p, v, owner, JETTISON_GRACE)
		_next_id += 1


@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, kind: String, pos: Vector3, vel: Vector3, owner := 0, grace := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_for(kind)
	mi.position = pos
	add_child(mi)
	_items[id] = {"node": mi, "kind": kind, "vel": vel, "life": LIFE, "asked": 0.0, "owner": owner, "grace": grace}


@rpc("authority", "call_local", "reliable")
func _cl_remove(id: int) -> void:
	if _items.has(id):
		var n := _items[id]["node"] as Node3D
		var me := W.local_ship
		if me and is_instance_valid(me) and n.position.distance_to(me.position) < 40.0:
			Sfx.play("opsamling", -4.0, 0.0)
		n.queue_free()
		_items.erase(id)


var _beam_mesh: MeshInstance3D
var _beams: PackedVector3Array = []


## Traktorstrålens linjer fra skibet til kasserne, den trækker i.
func _draw_beams(me: Ship) -> void:
	if _beam_mesh == null:
		_beam_mesh = MeshInstance3D.new()
		_beam_mesh.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 1.0, 0.9, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.disable_fog = true
		_beam_mesh.material_override = m
		_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam_mesh)
	var im := _beam_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if _beams.is_empty() or me == null:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var from := me.global_transform * Vector3(0, -0.6, -1.5)
	var wob := sin(Time.get_ticks_msec() / 60.0) * 0.4
	for p in _beams:
		for k in 3:
			var off := Vector3(wob * (k - 1), wob * 0.5 * (k - 1), 0)
			im.surface_add_vertex(from + off)
			im.surface_add_vertex(p + off * 0.3)
	im.surface_end()


func _process(delta: float) -> void:
	var me := W.local_ship
	_draw_beams(me if me and is_instance_valid(me) else null)   # strålerne fra sidste billede
	_beams.clear()
	var can_take := me != null and is_instance_valid(me) and not me.dead and me.state == Ship.State.FLY
	var has_room := Game.cargo_total(Game.wallet["cargo"]) < int(Game.wallet["cargo_max"])
	var server := W.is_server()
	for id: int in _items.keys():
		var it: Dictionary = _items[id]
		var n: MeshInstance3D = it["node"]
		it["life"] -= delta
		if it["life"] <= 0.0 and server:
			_cl_remove.rpc(id)
			continue
		var v: Vector3 = it["vel"]
		it["grace"] = float(it.get("grace", 0.0)) - delta
		var mine_dropped: bool = float(it["grace"]) > 0.0 and me != null and int(it.get("owner", 0)) == me.peer_id
		var dist := n.position.distance_to(me.position) if me else INF
		var tractor := me != null and me.tractor_on and dist < TRACTOR_RANGE
		if can_take and has_room and not mine_dropped and (dist < MAGNET_RANGE or tractor):
			var want := (me.position - n.position).normalized() * ((70.0 if tractor else 40.0) + me.speed)
			v = v.lerp(want, minf(1.0, delta * (6.0 if tractor else 4.0)))
			if tractor and dist > MAGNET_RANGE:
				_beams.append(n.position)
		else:
			v *= 1.0 - delta * 0.5
		it["vel"] = v
		n.position += v * delta
		n.rotation += Vector3(2, 3, 0) * delta
		it["asked"] -= delta
		if can_take and not mine_dropped and it["asked"] <= 0.0 and n.position.distance_to(me.position) < TAKE_RANGE:
			it["asked"] = 1.0
			if has_room:
				_srv_take.rpc_id(1, id)
			else:
				Game.toast.emit("Lastrummet er fuldt – sælg, eller smid last ud (%s)" % Game.key_name("cargo"))


@rpc("any_peer", "call_local", "reliable")

func _srv_take(id: int) -> void:
	if not multiplayer.is_server() or not _items.has(id):
		return
	var who := multiplayer.get_remote_sender_id()
	if who == 0:
		who = multiplayer.get_unique_id()
	var kind: String = _items[id]["kind"]
	if Game.server_add_cargo(who, kind):
		_cl_remove.rpc(id)
		var w: Dictionary = Game.players[who]
		Game.server_toast(who, "+1 %s (%d/%d)" % [Game.good_name(kind).to_lower(), Game.cargo_total(w["cargo"]), int(w["cargo_max"])])
	else:
		Game.server_toast(who, "Lastrummet er fuldt – land og sælg")


func _on_player_joined(id: int) -> void:
	if id == multiplayer.get_unique_id():
		return
	for item_id: int in _items:
		var it: Dictionary = _items[item_id]
		_cl_spawn.rpc_id(id, item_id, it["kind"], (it["node"] as Node3D).position, it["vel"], int(it.get("owner", 0)), maxf(0.0, float(it.get("grace", 0.0))))


func _mesh_for(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	if kind == "malm" or kind == "krystal":
		var s := SphereMesh.new()     # 4 sider og 2 ringe = en diamant
		s.radius = 0.9
		s.height = 1.8
		s.radial_segments = 4
		s.rings = 2
		mesh = s
	else:
		var b := BoxMesh.new()
		b.size = Vector3(1.4, 1.4, 1.4)
		mesh = b
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Game.col(Game.goods[kind]["color"])
	(mesh as PrimitiveMesh).material = mat
	_meshes[kind] = mesh
	return mesh
