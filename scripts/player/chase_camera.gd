class_name ChaseCamera
extends Camera3D
## Kamera bag skibet som i Freelancer. Uden skib (titelskærmen) kredser det
## langsomt om et punkt, så verden ses i baggrunden.

const OFFSET := Vector3(0, 2.7, 10.5)
const BASE_FOV := 70.0

var target: Ship
var orbit_center := Vector3.ZERO
var shake := 0.0
var zoom := 1.0           ## 0.55 (tæt på) .. 2.6 (langt ude), glider mod zoom_target
var zoom_target := 1.0
## Førstepersonsvisning fra cockpittet (V, eller rul helt ind med hjulet).
var first_person := false
var cockpit: Cockpit

## Øjets placering i hver skibstype (lokalt, -Z er fremad).
const EYES := {"falk": Vector3(0, 0.78, -1.45), "hveps": Vector3(0, 0.6, -0.95),
	"bison": Vector3(0, 1.2, -1.45), "albatros": Vector3(0, 0.95, -4.6)}

var _up := Vector3.UP
var _orbit_t := 0.0


func _ready() -> void:
	# Kameraet flyttes i _process; skibet bevæger sig i fysik-takten og tegnes
	# interpoleret imellem (project.godot: physics_interpolation), så vi følger den
	# interpolerede position og slår interpolation fra for selve kameraet.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = BASE_FOV
	near = 0.5
	far = 30000.0
	current = true
	cockpit = Cockpit.new()
	cockpit.name = "Cockpit"
	cockpit.visible = false
	add_child(cockpit)


func set_first_person(on: bool) -> void:
	first_person = on
	if not on:
		cockpit.visible = false
		near = 0.5
		if target and is_instance_valid(target):
			target.hide_model = false
		snap()


func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		_follow(delta)
	else:
		_orbit(delta)
	if shake > 0.0:
		position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.6
		shake = maxf(0.0, shake - delta * 1.5)


func _follow(delta: float) -> void:
	var fp := first_person and target.state != Ship.State.LANE and not target.dead
	target.hide_model = fp
	cockpit.visible = fp
	if fp:
		_follow_cockpit(delta)
		return
	near = 0.5
	zoom = lerpf(zoom, zoom_target, 1.0 - exp(-delta * 8.0))
	var t := target.get_global_transform_interpolated()
	var desired := t * _offset()
	var k := 1.0 - exp(-delta * 7.5)
	if global_position.distance_to(desired) > 300.0:
		k = 1.0   # efter et hop eller en teleport
	global_position = global_position.lerp(desired, k)
	_up = _up.lerp(t.basis.y, k).normalized()
	var look := t.origin - t.basis.z * 12.0
	if global_position.distance_to(look) > 0.1:
		look_at(look, _up)
	# Lidt bredere synsfelt ved høj fart og afterburner giver fartfornemmelse
	var fast := clampf(target.speed / maxf(target.max_speed(), 1.0), 0.0, 2.0)
	var want_fov := BASE_FOV + fast * 5.0 + (5.0 if target.boosting else 0.0) + target.jump_fx * 35.0
	fov = lerpf(fov, want_fov, 1.0 - exp(-delta * 4.0)) if target.jump_fx <= 0.0 else want_fov
	if target.state == Ship.State.LANE:
		shake = maxf(shake, 0.06)


func _follow_cockpit(delta: float) -> void:
	near = 0.05
	cockpit.build(target.ship_class, target.paint)
	var t := target.get_global_transform_interpolated()
	global_transform = Transform3D(t.basis.orthonormalized(), t * EYES.get(target.ship_class, EYES["falk"]))
	_up = t.basis.y
	cockpit.update_from(target, delta)
	var fast := clampf(target.speed / maxf(target.max_speed(), 1.0), 0.0, 2.0)
	var want_fov := BASE_FOV + 5.0 + fast * 6.0 + (6.0 if target.boosting else 0.0) + target.jump_fx * 35.0
	fov = lerpf(fov, want_fov, 1.0 - exp(-delta * 4.0)) if target.jump_fx <= 0.0 else want_fov
	if target.state == Ship.State.LANE:
		shake = maxf(shake, 0.03)


func _orbit(delta: float) -> void:
	cockpit.visible = false
	near = 0.5
	_orbit_t += delta * 0.05
	global_position = orbit_center + Vector3(sin(_orbit_t) * 140.0, 40.0, cos(_orbit_t) * 140.0)
	look_at(orbit_center + Vector3(0, 0, -400), Vector3.UP)
	fov = BASE_FOV


## Hop direkte bag skibet (fx efter landing eller jump).
## Kameraets placering bag skibet ved den aktuelle zoom (lidt lavere, når man er tæt på).
func _offset() -> Vector3:
	return Vector3(0, OFFSET.y * pow(zoom, 0.8), OFFSET.z * zoom)


func snap() -> void:
	if target:
		target.reset_physics_interpolation()
		zoom = zoom_target
		global_position = target.global_transform * _offset()
		_up = target.global_basis.y
		if first_person:
			global_transform = Transform3D(target.global_basis.orthonormalized(), target.global_transform * EYES.get(target.ship_class, EYES["falk"]))
