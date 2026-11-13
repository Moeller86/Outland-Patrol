class_name Bombs
extends Node3D
## Bomber (B): falder med skibets fart og planetens tyngdekraft og sprænger med en stor
## eksplosion, når de rammer jorden eller et mål. Concord udleverer dem til
## angrebsmissioner. Skytten simulerer sin egen bombe og melder nedslaget til værten,
## som giver skade i et område; alle ser eksplosionen. Et sigtekryds på jorden viser,
## hvor bomben vil lande.

const GRAVITY := 38.0
const DRAG := 0.12
const RADIUS := 42.0           ## sprængradius
const DAMAGE := 14.0           ## skade i centrum (falder til 30 % ved kanten)
const COOLDOWN := 0.45
const MAX_FALL := 9.0
const ISSUED := 6              ## bomber udleveret pr. angrebsmission

var ammo := 0
var cool := 0.0
var _b: Dictionary = {}        ## id -> {pos, vel, life, mine, node}
var _next := 1
var _aim: Node3D
var _aim_ring: MeshInstance3D
var aim_valid := false
var aim_point := Vector3.ZERO
var _waves: Array[Dictionary] = []
var _craters: Array[Node3D] = []
var _splashes: Array[Dictionary] = []
const MAX_CRATERS := 40


func _ready() -> void:
	_aim = Node3D.new()
	_aim.visible = false
	add_child(_aim)
	_aim_ring = MeshInstance3D.new()
	_aim_ring.mesh = ModelKit.torus(RADIUS * 0.5, 0.9, 24, 4)
	_aim_ring.material_override = ModelKit.glow(Color("ff9f1c"))
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim.add_child(_aim_ring)
	var dot := MeshInstance3D.new()
	dot.mesh = ModelKit.box(3.0, 0.6, 3.0)
	dot.material_override = ModelKit.glow(Color("ff3b3b"))
	_aim.add_child(dot)
	for k in 4:
		var tick := MeshInstance3D.new()
		tick.mesh = ModelKit.box(1.0, 0.6, 7.0)
		tick.material_override = ModelKit.glow(Color("ffd23f"))
		tick.position = Vector3(cos(k * PI / 2.0), 0, sin(k * PI / 2.0)) * (RADIUS * 0.5 + 5.0)
		tick.rotation.y = -k * PI / 2.0 + PI / 2.0
		_aim.add_child(tick)
	Net.started.connect(func() -> void:
		ammo = 0
		for id: int in _b.keys():
			(_b[id]["node"] as Node3D).queue_free()
		_b.clear())


# ---------------------------------------------------------------- affyring

## Slip en bombe. Returnerer en fejltekst eller "".
func drop(ship: Ship) -> String:
	if cool > 0.0:
		return "busy"
	if ammo <= 0:
		return "Ingen bomber – de udleveres til angrebsmissioner"
	var pl := ship.universe.nearest_planet(ship.position)
	if pl.altitude(ship.position) > pl.atmo_top * 1.2:
		return "Bomber kan kun bruges over en planet"
	cool = COOLDOWN
	ammo -= 1
	var id := multiplayer.get_unique_id() * 10000 + _next
	_next += 1
	var pos := ship.global_transform * Vector3(0, -1.4, 0.4)
	var vel := ship.forward() * ship.speed + (pos - pl.position).normalized() * -6.0
	_spawn(id, pos, vel, true)
	Sfx.play("missil" if Sfx.SOUNDS.has("missil") else "afgang", -4.0, 0.15)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_cl_copy.rpc(id, pos, vel)
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _cl_copy(id: int, pos: Vector3, vel: Vector3) -> void:
	_spawn(id, pos, vel, false)


@rpc("authority", "call_local", "reliable")
func cl_issue(n: int) -> void:
	ammo = maxi(ammo, n)
	Game.toast.emit("Concord har lastet %d bomber om bord (B)" % n)


func _spawn(id: int, pos: Vector3, vel: Vector3, mine: bool) -> void:
	var n := Node3D.new()
	var body := ModelKit.add(n, ModelKit.cyl(0.45, 0.45, 2.2, 8), ModelKit.hull(Color("3a3656"), ModelKit.TEX_PLATING, 0.6),
		Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ModelKit.add(n, ModelKit.cyl(0.0, 0.45, 0.8, 8), ModelKit.hull(Color("ffd23f"), ModelKit.TEX_STRIPES, 0.6), Vector3(0, 0, -1.5), Vector3(-PI / 2, 0, 0))
	for k in 4:
		var fin := ModelKit.add(n, ModelKit.box(0.08, 0.9, 0.7), ModelKit.flat(Color("23203a")), Vector3(0, 0, 1.0))
		fin.rotation.z = k * PI / 2.0
	var lamp := ModelKit.add(n, ModelKit.box(0.25, 0.25, 0.25), ModelKit.glow(Color("ff3b3b")), Vector3(0, 0.5, 0))
	lamp.name = "Lamp"
	n.position = pos
	add_child(n)
	_b[id] = {"pos": pos, "vel": vel, "life": MAX_FALL, "mine": mine, "node": n}


# ---------------------------------------------------------------- simulering

func _physics_process(delta: float) -> void:
	cool = maxf(0.0, cool - delta)
	var done: Array[int] = []
	var impacts: Array = []
	for id: int in _b:
		var b: Dictionary = _b[id]
		var pos: Vector3 = b["pos"]
		var vel: Vector3 = b["vel"]
		var pl := W.universe.nearest_planet(pos)
		var down := (pl.position - pos).normalized()
		vel += down * GRAVITY * delta
		vel *= 1.0 - DRAG * delta
		var nxt := pos + vel * delta
		b["life"] = float(b["life"]) - delta
		var hit := false
		var at := nxt
		if pl.ground_altitude(nxt) < 0.5:
			hit = true
			var dn := (nxt - pl.position).normalized()
			at = pl.position + dn * (pl.fine_surface_radius(dn) + 1.0)
		elif W.assault and W.assault.bomb_contact(pos, nxt):
			hit = true
		b["pos"] = nxt
		b["vel"] = vel
		var n: Node3D = b["node"]
		n.position = nxt
		if vel.length() > 0.5:
			n.basis = Basis.looking_at(vel.normalized(), -down if absf(vel.normalized().dot(down)) < 0.98 else Vector3.RIGHT)
		(n.get_node("Lamp") as Node3D).visible = fmod(float(b["life"]) * 6.0, 1.0) < 0.5
		if hit or float(b["life"]) <= 0.0:
			done.append(id)
			if b["mine"]:
				impacts.append([id, at])
	for id in done:
		if _b.has(id):
			(_b[id]["node"] as Node3D).queue_free()
			_b.erase(id)
	for im: Array in impacts:
		_srv_impact.rpc_id(1, im[0], im[1])
	_update_aim()
	_update_waves(delta)
	_update_marks(delta)


@rpc("any_peer", "call_local", "reliable")
func _srv_impact(id: int, pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if W.assault:
		W.assault.server_blast(pos, RADIUS, DAMAGE)
	# Pirater i nærheden tager også skade
	for i in Pirates.POOL:
		if W.pirates.is_active(i) and W.pirates.position_of(i).distance_to(pos) < RADIUS:
			W.pirates.server_damage(i, 10.0)
	cl_boom.rpc(id, pos, 1.0)


## Stor eksplosion hos alle. `size` 1 = bombe, 2–3 = reaktor.
@rpc("authority", "call_local", "reliable")
func cl_boom(id: int, pos: Vector3, size: float) -> void:
	if _b.has(id):
		(_b[id]["node"] as Node3D).queue_free()
		_b.erase(id)
	big_explosion(pos, size)


## Kun visuelt: ildkugle, trykbølge, lysglimt, gnister og røg + kamerarystelse.
## Tæt på jorden laves et krater; i vandet et plask.
func big_explosion(pos: Vector3, size := 1.0) -> void:
	var pl := W.universe.nearest_planet(pos)
	var up := (pos - pl.position).normalized()
	if pl.ground_altitude(pos) < 8.0 * maxf(size, 0.5):
		if pl.height_at(up) <= 0.3:
			_splash(pl, up, size)
			return
		_crater(pl, up, size)
	for k in int(3 * size):
		W.fx.explosion(pos + up * randf_range(0, 8) * size + Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)) * size, true)
	W.fx.burst(pos, int(30 * size), 70.0 * size, [Color("ffd23f"), Color.WHITE, Color("ff7a3d")], 2.2 * size, 1.4)
	# Jord og sten kastes op
	for k in int(24 * size):
		var dir := (up * randf_range(0.6, 1.6) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.7).normalized()
		W.fx.spawn(pos, dir * randf_range(25, 70) * size, [Color("5a3d2a"), Color("8a6a4a"), Color("3a3048")][k % 3], randf_range(1.0, 2.4) * size, randf_range(1.2, 2.2))
	# Ildkugle, trykbølge og lys
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var ball := MeshInstance3D.new()
	ball.mesh = ModelKit.sphere(1.0, 10, 8)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color("ffd23f")
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ball.material_override = bm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ball)
	var ring := MeshInstance3D.new()
	ring.mesh = ModelKit.torus(1.0, 0.12, 32, 4)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.95, 0.8, 0.9)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fwd := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	ring.basis = Basis.looking_at(fwd, up)
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("ffb35a")
	light.light_energy = 8.0
	light.omni_range = 160.0 * size
	root.add_child(light)
	_waves.append({"root": root, "ball": ball, "bm": bm, "ring": ring, "rm": rm, "light": light, "t": 0.0, "size": size, "up": up})
	Sfx.play_at("eksplosion_stor", pos, 4.0)
	# Kameraet ryster, hvis man er tæt på
	var me := W.local_ship
	if me and is_instance_valid(me):
		var d := me.position.distance_to(pos)
		var cam := get_viewport().get_camera_3d()
		if cam is ChaseCamera and d < 500.0 * size:
			(cam as ChaseCamera).shake = maxf((cam as ChaseCamera).shake, clampf(1.0 - d / (500.0 * size), 0.0, 1.0) * 1.1)


# ---------------------------------------------------------------- kratere og plask

## Et sodsort krater med en kant af opkastet jord og gløder, der dør ud.
func _crater(pl: PlanetBody, up: Vector3, size: float) -> void:
	var r := 16.0 * size
	var ground := pl.position + up * pl.fine_surface_radius(up)
	var f := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var root := Node3D.new()
	root.transform = Transform3D(Basis.looking_at(f, up), ground)
	add_child(root)
	var soil := pl.color_for(pl.height_at(up))
	var burnt := ModelKit.flat(Color(0.09, 0.07, 0.08))
	var scorch := ModelKit.flat(soil.darkened(0.6))
	# Sænket bund og en svedet ring rundt om
	# (lag oven på hinanden, så de ses på skrånende terræn)
	_disc(root, r * 1.25, 0.6, scorch, 0.0)
	_disc(root, r * 0.85, 0.6, burnt, 0.12)
	_disc(root, r * 0.5, 0.6, ModelKit.flat(Color(0.05, 0.04, 0.05)), 0.22)
	var embers := _disc(root, r * 0.3, 0.6, ModelKit.glow(Color("ff7a3d")), 0.3)
	embers.name = "Embers"
	# Kant af jordklumper
	var rim := ModelKit.flat(soil.darkened(0.25))
	var n := int(10 + 6 * size)
	for k in n:
		var a := TAU * k / n + randf_range(-0.2, 0.2)
		var s := r * randf_range(0.14, 0.24)
		var b := MeshInstance3D.new()
		b.mesh = ModelKit.box(s * 1.4, s * 0.8, s)
		b.material_override = rim if k % 3 else scorch
		b.position = Vector3(cos(a), 0.0, sin(a)) * r * randf_range(0.78, 0.98) + Vector3(0, s * 0.15, 0)
		b.rotation = Vector3(randf_range(-0.4, 0.4), -a, randf_range(-0.3, 0.3))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(b)
	root.set_meta("t", 0.0)
	root.set_meta("embers", embers)
	_craters.append(root)
	while _craters.size() > MAX_CRATERS:
		var old: Node3D = _craters.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _disc(parent: Node3D, r: float, h: float, mat: Material, y: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = ModelKit.cyl(r, r * 0.92, h, 14)
	m.material_override = mat
	m.position = Vector3(0, y, 0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


## Plask i vandet: en søjle af vand og skum og ringe, der breder sig på overfladen.
func _splash(pl: PlanetBody, up: Vector3, size: float) -> void:
	var water := pl.position + up * pl.radius
	var cols := [Color("e8f8ff"), Color("9fe2ff"), Color("4dd0ff"), Color.WHITE]
	for k in int(60 * size + 20):
		var dir := (up * randf_range(1.2, 3.0) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.45).normalized()
		W.fx.spawn(water + up * 1.0, dir * randf_range(20, 55) * maxf(size, 0.5), cols[k % cols.size()], randf_range(1.0, 2.6) * maxf(size, 0.6), randf_range(1.0, 2.0))
	W.fx.burst(water + up * 2.0, int(20 * size + 8), 30.0 * size, [Color.WHITE, Color("9fe2ff")], 2.0 * maxf(size, 0.5), 1.0)
	var f := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	for k in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = ModelKit.torus(1.0, 0.08, 28, 4)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.albedo_color = Color(0.9, 0.97, 1.0, 0.9)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.transform = Transform3D(Basis.looking_at(f, up), water + up * 0.4)
		add_child(ring)
		_splashes.append({"ring": ring, "mat": rm, "t": -0.35 * k, "size": size})
	Sfx.play_at("eksplosion", water, -4.0)
	var me := W.local_ship
	if me and is_instance_valid(me):
		var cam := get_viewport().get_camera_3d()
		var d := me.position.distance_to(water)
		if cam is ChaseCamera and d < 300.0 * size:
			(cam as ChaseCamera).shake = maxf((cam as ChaseCamera).shake, clampf(1.0 - d / (300.0 * size), 0.0, 1.0) * 0.6)


func _update_marks(delta: float) -> void:
	for c in _craters:
		if not is_instance_valid(c):
			continue
		var t := float(c.get_meta("t")) + delta
		c.set_meta("t", t)
		var e: MeshInstance3D = c.get_meta("embers")
		if is_instance_valid(e) and e.visible:
			e.visible = t < 6.0 and fmod(t * 3.0, 1.0) < 0.85
			if randf() < delta * 6.0 and t < 8.0:
				W.fx.spawn(c.global_position + c.global_basis.y * 1.5, c.global_basis.y * randf_range(4, 9), Color("3a3048"), randf_range(1.2, 2.2), 2.0)
	var keep: Array[Dictionary] = []
	for s in _splashes:
		s["t"] = float(s["t"]) + delta
		var t: float = s["t"]
		var ring: MeshInstance3D = s["ring"]
		if t > 0.0:
			var rr := (6.0 + t * 30.0) * float(s["size"])
			ring.scale = Vector3(rr, 1.0, rr)
			(s["mat"] as StandardMaterial3D).albedo_color.a = clampf(1.0 - t / 1.6, 0.0, 1.0)
		else:
			ring.scale = Vector3(0.01, 1.0, 0.01)
		if t < 1.6:
			keep.append(s)
		else:
			ring.queue_free()
	_splashes = keep


func _update_waves(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for w in _waves:
		w["t"] = float(w["t"]) + delta
		var t: float = w["t"]
		var s: float = w["size"]
		var ball: MeshInstance3D = w["ball"]
		var bm: StandardMaterial3D = w["bm"]
		var r := RADIUS * s * clampf(t / 0.35, 0.0, 1.0) * 0.8
		ball.scale = Vector3.ONE * maxf(r, 0.01)
		ball.position = (w["up"] as Vector3) * t * 8.0
		bm.albedo_color = Color("ffd23f").lerp(Color("3a2a2a"), clampf((t - 0.25) / 1.2, 0.0, 1.0))
		bm.albedo_color.a = clampf(1.4 - t * 0.9, 0.0, 1.0)
		var ring: MeshInstance3D = w["ring"]
		var rr := RADIUS * s * 2.5 * clampf(t / 0.9, 0.0, 1.0)
		ring.scale = Vector3(rr, rr * 0.5, rr)
		(w["rm"] as StandardMaterial3D).albedo_color.a = clampf(1.0 - t / 0.9, 0.0, 1.0)
		(w["light"] as OmniLight3D).light_energy = maxf(0.0, 8.0 * (1.0 - t / 0.8))
		if t < 1.6:
			keep.append(w)
		else:
			(w["root"] as Node3D).queue_free()
	_waves = keep


# ---------------------------------------------------------------- sigtekryds

## Hvor lander en bombe, der slippes nu? (forudsigelse med samme fysik)
func predict(ship: Ship) -> Dictionary:
	var pl := ship.universe.nearest_planet(ship.position)
	var pos := ship.global_transform * Vector3(0, -1.4, 0.4)
	var vel := ship.forward() * ship.speed + (pos - pl.position).normalized() * -6.0
	var dt := 1.0 / 20.0
	var t := 0.0
	while t < MAX_FALL:
		var down := (pl.position - pos).normalized()
		vel += down * GRAVITY * dt
		vel *= 1.0 - DRAG * dt
		pos += vel * dt
		t += dt
		if pl.ground_altitude(pos) < 0.5:
			var dn := (pos - pl.position).normalized()
			return {"pos": pl.position + dn * (pl.fine_surface_radius(dn) + 0.8), "up": dn, "t": t}
	return {}


func _update_aim() -> void:
	var me := W.local_ship
	aim_valid = false
	if ammo > 0 and me and is_instance_valid(me) and not me.dead and me.state == Ship.State.FLY:
		var pl := me.universe.nearest_planet(me.position)
		if pl.ground_altitude(me.position) < 700.0:
			var hit := predict(me)
			if not hit.is_empty():
				aim_valid = true
				aim_point = hit["pos"]
				var up: Vector3 = hit["up"]
				var f := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
				_aim.global_transform = Transform3D(Basis.looking_at(f, up), aim_point)
				_aim_ring.scale = Vector3.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() / 90.0))
	_aim.visible = false     # sigtekrydset vises ikke (forudsigelsen bruges stadig internt)
