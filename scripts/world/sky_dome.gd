class_name SkyDome
extends Node3D
## Farverig rumhimmel: tågebaggrund, stjerner og sol. Følger kameraet,
## så den altid ligger "uendeligt" langt væk, og skifter farver pr. system.

const DOME_RADIUS := 9000.0

var _nebula_mat := ShaderMaterial.new()
var _star_mat := StandardMaterial3D.new()
var _sun_mat := StandardMaterial3D.new()
var _halo_mat := StandardMaterial3D.new()
var _sun: Node3D
var _textures: Dictionary = {}
var sun_dir := Vector3(-0.7, 0.35, 0.25).normalized()


func _ready() -> void:
	# Tåge: indvendig kugle med en farvet støjtekstur.
	var sphere := SphereMesh.new()
	sphere.radius = DOME_RADIUS
	sphere.height = DOME_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_nebula_mat.shader = load("res://shaders/nebula.gdshader")
	var neb := MeshInstance3D.new()
	neb.name = "Nebula"
	neb.mesh = sphere
	neb.material_override = _nebula_mat
	neb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(neb)

	# Stjerner: små firkanter, der altid er én pixel store.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.006, 0.006)
	_star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_mat.fixed_size = true
	_star_mat.vertex_color_use_as_albedo = true
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_mat.disable_fog = true
	quad.material = _star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 1600
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var cols := [Color.WHITE, Color("9ff2ff"), Color("ffb3e6"), Color("fff299")]
	for i in mm.instance_count:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		mm.set_instance_transform(i, Transform3D(Basis(), d * DOME_RADIUS * 0.9))
		mm.set_instance_color(i, cols[i % cols.size()])
	var stars := MultiMeshInstance3D.new()
	stars.name = "Stars"
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.extra_cull_margin = 16384.0
	add_child(stars)

	# Solen med glorie.
	_sun = Node3D.new()
	add_child(_sun)
	for spec: Array in [[170.0, _sun_mat, 1.0], [320.0, _halo_mat, 0.25]]:
		var m: StandardMaterial3D = spec[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.disable_fog = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var s := SphereMesh.new()
		s.radius = spec[0]
		s.height = spec[0] * 2.0
		s.radial_segments = 12
		s.rings = 8
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sun.add_child(mi)


## Skift tåge- og solfarver til et nyt system.
func set_system(sys: Dictionary) -> void:
	var key: String = sys["name"]
	if not _textures.has(key):
		_textures[key] = _make_nebula(Game.col(sys["space"]), sys["nebula"], key.hash())
	_nebula_mat.set_shader_parameter("nebula", _textures[key])
	var sun := Game.col(sys["sun"])
	_sun_mat.albedo_color = sun
	var halo := sun.lerp(Color("ff9e3d"), 0.5)
	halo.a = 0.25
	_halo_mat.albedo_color = halo
	sun_dir = Game.vec(sys["sun_dir"]).normalized()
	_sun.position = sun_dir * DOME_RADIUS * 0.85


## 0 = rummet, 1 = dybt i atmosfæren (himlen skjuler stjerner og tåge).
func set_atmosphere(t: float, sky_color: Color) -> void:
	var a := 1.0 - t
	_nebula_mat.set_shader_parameter("atmosphere", t)
	_nebula_mat.set_shader_parameter("sky_color", sky_color)
	_star_mat.albedo_color = Color(1, 1, 1, a)
	_sun_mat.albedo_color.a = maxf(a, 0.35)


func _make_nebula(space: Color, colors: Array, seed_value: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.006
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 0.62, 0.74, 0.86, 1.0])
	grad.colors = PackedColorArray([space, space, space.lerp(Game.col(colors[0]), 0.45),
		space.lerp(Game.col(colors[1]), 0.6), space.lerp(Game.col(colors[2]), 0.55), Game.col(colors[2])])
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = grad
	return tex
