class_name Effects
extends Node3D
## Pixel-partikler: små kasser der flyver ud og krymper. Bruges til eksplosioner,
## gnister, afterburner, re-entry-flammer og fartstreger. Kun visuelt og lokalt.

const POOL := 900
const EXPLOSION := [Color("ffd23f"), Color("ff7a3d"), Color("ff4f8b"), Color.WHITE]

var _mm: MultiMesh
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max := PackedFloat32Array()
var _size := PackedFloat32Array()
var _next := 0


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = box
	_mm.instance_count = POOL
	_pos.resize(POOL)
	_vel.resize(POOL)
	_life.resize(POOL)
	_max.resize(POOL)
	_size.resize(POOL)
	for i in POOL:
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)


func spawn(pos: Vector3, vel: Vector3, color: Color, size: float, life: float) -> void:
	var i := _next
	_next = (_next + 1) % POOL
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_max[i] = life
	_size[i] = size
	_mm.set_instance_color(i, color)


func burst(pos: Vector3, count: int, speed: float, colors: Array, size: float, life: float) -> void:
	for k in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		spawn(pos, dir * randf_range(speed * 0.3, speed), colors[k % colors.size()],
			size * randf_range(0.6, 1.2), life * randf_range(0.6, 1.1))


func explosion(pos: Vector3, big := false) -> void:
	burst(pos, 36 if big else 22, 38.0 if big else 30.0, EXPLOSION, 1.5 if big else 1.2, 1.3 if big else 1.0)


func _process(delta: float) -> void:
	var damp := 1.0 - delta * 1.5
	for i in POOL:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), _pos[i]))
			continue
		_pos[i] += _vel[i] * delta
		_vel[i] *= damp
		var s := _size[i] * (_life[i] / _max[i])
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), _pos[i]))
