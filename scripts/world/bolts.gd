class_name Bolts
extends Node3D
## Laserskud. Tre slags:
##  OWN     – den lokale spillers skud. Træffere tjekkes her og meldes til værten.
##  REMOTE  – andre spilleres skud. Kun visuelt.
##  PIRATE  – piratskud. Hver maskine tjekker mod sit eget skib; værten tjekker
##            også mod fragtskibene.

enum Kind { OWN, REMOTE, PIRATE }

const POOL := 96
const HIT_DAMAGE_PIRATE := 7.0

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _speed := PackedFloat32Array()
var _life := PackedFloat32Array()
var _kind := PackedInt32Array()
var _dmg := PackedFloat32Array()
var _fx := PackedInt32Array()      ## 0 = intet, 1 = ion, 2 = flak, 3 = krystal (se equipment.json)
var _next := 0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.22, 3.4)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = POOL
	_pos.resize(POOL)
	_dir.resize(POOL)
	_speed.resize(POOL)
	_life.resize(POOL)
	_dmg.resize(POOL)
	_fx.resize(POOL)
	_kind.resize(POOL)
	for i in POOL:
		_hide(i)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)


func fire(pos: Vector3, dir: Vector3, speed: float, color: Color, kind: Kind, damage := 1.0, effect := 0) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	_pos[i] = pos
	_dir[i] = dir.normalized()
	_speed[i] = speed
	_life[i] = 1.4 if kind != Kind.PIRATE else 2.0
	_kind[i] = kind
	_fx[i] = effect
	_dmg[i] = damage if kind != Kind.PIRATE or damage != 1.0 else HIT_DAMAGE_PIRATE
	_mm.set_instance_color(i, color)
	_place(i)


func _process(delta: float) -> void:
	var me := W.local_ship
	var server := W.is_server()
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			if _fx[i] == 2:     # flakgranaten springer for enden af sin bane
				W.fx.burst(_pos[i], 14, 22.0, [Color("ffb347"), Color("ffd23f"), Color("8a8fb0")], 0.9, 0.6)
			_hide(i)
			continue
		# Træffere tjekkes langs hele strækningen, skuddet flyver i denne frame
		# (ellers kan hurtige skud springe hen over et mål ved høj fart).
		var from := _pos[i]
		_pos[i] += _dir[i] * _speed[i] * delta
		var p := _pos[i]
		match _kind[i]:
			Kind.OWN:
				if _own_hit(from, p, _dmg[i], _fx[i]):
					match _fx[i]:
						1: _kill(i, [Color("4d8bff"), Color("9fe2ff"), Color.WHITE])
						2:
							W.fx.burst(_pos[i], 26, 30.0, [Color("ffb347"), Color("ffd23f"), Color.WHITE], 1.2, 0.7)
							Sfx.play_at("traef", _pos[i], 0.0)
							_kill(i, [Color("ffb347")])
						3: _kill(i, [Color("c77dff"), Color("f0d0ff"), Color.WHITE])
						_: _kill(i, [Color.WHITE, Color("ffd23f")])
					continue
			Kind.PIRATE:
				if me and is_instance_valid(me) and not me.dead and me.state == Ship.State.FLY and seg_dist(from, p, me.position) < 2.8:
					_kill(i, [Color("2ec4d6"), Color.WHITE] if me.shield > 0.0 else [Color("ff6a2a"), Color("ffd23f")])
					me.take_damage(_dmg[i])
					continue
				if server and W.missions and W.missions.server_bolt_hit(p, _dmg[i]):
					_kill(i, [Color("ff6a2a"), Color("ffd23f")])
					continue
				if server and W.bases and W.bases.server_bolt_hit(p, _dmg[i]):
					_kill(i, [Color("6bdc4f"), Color.WHITE])
					continue
				if server and W.patrols and W.patrols.server_bolt_hit(p, _dmg[i]):
					_kill(i, [Color("4d8bff"), Color.WHITE])
					continue
				if server and W.traffic and W.traffic.server_bolt_hit(p, _dmg[i]):
					_kill(i, [Color("ff6a2a"), Color("ffd23f")])
					continue
				if server and W.freighters and W.freighters.server_bolt_hit(p, _dmg[i]):
					_kill(i, [Color("ff6a2a"), Color("ffd23f")])
					continue
		_place(i)


func _own_hit(a: Vector3, b: Vector3, dmg: float, effect := 0) -> bool:
	if W.pirates and W.pirates.hit_test(a, b, dmg, effect):
		return true
	if W.assault and W.assault.active() and W.assault.hit_test(a, b, dmg):
		return true
	if W.asteroids and W.asteroids.hit_test(b, dmg):
		return true
	return false


## Afstand fra punktet p til linjestykket a–b.
static func seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _kill(i: int, colors: Array) -> void:
	W.fx.burst(_pos[i], 6, 14.0, colors, 0.6, 0.4)
	_life[i] = 0.0
	_hide(i)


func _place(i: int) -> void:
	var b := Basis.looking_at(_dir[i], Vector3.UP if absf(_dir[i].y) < 0.95 else Vector3.RIGHT)
	_mm.set_instance_transform(i, Transform3D(b, _pos[i]))


func _hide(i: int) -> void:
	_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
