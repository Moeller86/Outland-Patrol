class_name Ship
extends Node3D
## Et skib i verden. Spillerens eget skib styres lokalt (det har netværks-
## autoriteten) og sender sin tilstand ud ca. 20 gange i sekundet.
## Andres skibe glider blødt hen mod den sidst modtagne position.
##
## Skjold og skrog styres af ejeren selv: piratskud og kollisioner tjekkes på
## ejerens maskine. Penge, last og dusør går altid gennem værten (Game).

signal landed(loc_id: String)
signal launched
signal damaged(hull_hit: bool)
signal destroyed
signal salvaged(loc_id: String)
signal lock_changed

enum State { FLY, LANDING, LANDED, LANE, JUMP }

const MAX_SPEED := 55.0
const BOOST_SPEED := 65.0
const LAND_SPEED := 28.0
const SEND_INTERVAL := 0.05
const FIRE_COOLDOWN := 0.16
const BASE_SHIELD := 50.0
const GUNS := [Vector3(2.2, 0, -1.2), Vector3(-2.2, 0, -1.2)]
const BOLT_SPEED := 280.0
## Lock-on: T eller højreklik låser den pirat, der er tættest på sigtekornet.
const LOCK_RANGE := 900.0
const LOCK_CONE := 0.8          ## cos(37°): så bredt man kan låse
const LOCK_TIME := 0.4          ## sekunder fra "låser" til "låst"
const ASSIST_CONE := 0.982      ## cos(11°): inden for dette sigter kanonerne selv mod forudsigelsespunktet

var peer_id := 1
var display_name := "Pilot"
var paint := Color("ff4f8b")
var universe: Universe

var state := State.FLY
var speed := 0.0
var throttle := 0.3
var docked_at := ""
var jump_fx := 0.0           ## 0..1 til skærmblink og kamera-FOV under hop
var steering := true         ## Slås fra når en menu er åben
var boosting := false
## Cruise-drev (X): lader op i CRUISE_CHARGE s og flyver derefter CRUISE_SPEED m/s.
## Sværere at styre, ingen våben, og falder ud ved skade eller tæt på jorden.
const CRUISE_SPEED := 260.0
const CRUISE_CHARGE := 1.5
const CRUISE_MIN_GROUND := 55.0
var cruise := 0          ## 0 = fra, 1 = lader op, 2 = aktiv
var cruise_t := 0.0
var reentry := false

var hull := 100.0
var shield := BASE_SHIELD
var shield_max := BASE_SHIELD
var dead := false

var model: ShipModel
var hide_model := false
var slot := 0
var look: Dictionary = {}
var loadout: Loadout             ## Våben og gadgets (kun på det lokale skib)
var cloaked := false             ## Kappen er aktiv (sendes til alle, så piraterne mister os)
var tractor_on := false   ## Traktorstrålen er tændt (specialudstyr, hold Z)  ## Tilpasning: farver, mønster, skibsnavn             ## Plads i Concord-basens hangar (spillerens nummer i gruppen)   ## Skjult i førstepersonsvisning (kun for spilleren selv)
var ship_class := ""             ## Tom = standardskibet (Falk)
var handling: Dictionary = {}    ## Flyveegenskaber (skibsklasse + opgraderinger)
var _ang := Vector3.ZERO         ## Drejehastighed (pitch, yaw, roll) i rad/s, glattet
var _strafe := 0.0
## Højre musetast: kort klik låser et mål, holdt inde ruller man ved at trække musen til siden.
const RMB_TAP_TIME := 0.25
const RMB_TAP_MOVE := 10.0      ## pixels – mere bevægelse end dette er rul, ikke klik
var rolling_with_mouse := false
var _rmb_down := false
var _rmb_t := 0.0
var _rmb_anchor := Vector2.ZERO
var _rmb_moved := 0.0
var _bank := 0.0
var _lane := {}
var _landing := {}
var _jump := {}
var _lane_cool := 0.0
var _gate_cool := 0.0
var _fire_cool := 0.0
var _since_hit := 99.0
var _send_t := 0.0
var _net_pos := Vector3.ZERO
var _net_rot := Quaternion.IDENTITY
var _net_has := false
var _label: Label3D

var lock_target := -1           ## Pirat-indeks eller -1
var aim_dir := Vector3.FORWARD   ## Hvor kanonerne peger (mod musemarkøren, inden for gimbal-keglen)
var aim_point := Vector3.ZERO    ## Punktet, skuddene samles i
var aim_clamped := false         ## Markøren er uden for det, kanonerne kan nå
var lock_t := 0.0
var _alarm_t := 0.0


func setup(id: int, info: Dictionary, uni: Universe) -> void:
	peer_id = id
	name = "Ship_%d" % id
	display_name = info.get("name", "Pilot")
	ship_class = str(info.get("ship", "falk"))
	paint = Game.col(info.get("color", "ff4f8b"))
	look = (info.get("look", {}) as Dictionary).duplicate()
	universe = uni
	set_multiplayer_authority(id)


func _ready() -> void:
	handling = Game.handling(ship_class)
	_make_model()
	if is_local():
		Game.wallet_changed.connect(_refresh_upgrades)
		Game.fit_changed.connect(_refresh_upgrades)
		Game.repaired.connect(func(h: float): hull = h)
		_refresh_upgrades()
		loadout = Loadout.new(self)
		add_child(loadout)
	else:
		_label = Label3D.new()
		_label.text = _label_text()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.fixed_size = true
		_label.pixel_size = 0.0012
		_label.font_size = 24
		_label.outline_size = 6
		_label.modulate = paint
		_label.no_depth_test = true
		_label.position = Vector3(0, 3, 0)
		add_child(_label)


func is_local() -> bool:
	return is_multiplayer_authority()


func forward() -> Vector3:
	return -global_basis.z


func laser_damage() -> float:
	return (2.0 if Game.upgrade_level("laser") > 0 else 1.0) * float(handling.get("damage", 1.0))


func _make_model() -> void:
	if model:
		model.queue_free()
	if look.has("paint"):
		paint = Game.col(look["paint"])
	model = ShipModel.new()
	model.paint = paint
	model.ship_class = ship_class
	model.apply_look(look)
	add_child(model)
	_apply_cloak_look()


## Skift skibstype (fra værftet). Kaldes på alle maskiner.
func set_look(l: Dictionary) -> void:
	look = l.duplicate()
	_make_model()
	if _label:
		_label.text = _label_text()


func _label_text() -> String:
	var sn := str(look.get("ship_name", ""))
	return display_name if sn == "" else "%s\n«%s»" % [display_name, sn]


func set_class(cls: String) -> void:
	ship_class = cls
	handling = Game.handling(ship_class)
	_make_model()
	shield_max = 0.0
	_refresh_upgrades()
	shield = shield_max


func guns() -> Array:
	return handling.get("guns", GUNS)


func max_speed() -> float:
	return float(handling.get("max_speed", MAX_SPEED))


func boost_speed() -> float:
	return float(handling.get("boost", BOOST_SPEED))


func _refresh_upgrades() -> void:
	handling = Game.handling(ship_class)
	var bonus := float(Game.universe["upgrades"]["shield"]["shield_bonus"])
	var new_max := float(handling.get("shield", BASE_SHIELD)) + bonus * Game.upgrade_level("shield")
	if new_max > shield_max:
		shield = new_max
	shield_max = new_max
	shield = minf(shield, shield_max)


func _physics_process(delta: float) -> void:
	if is_local():
		if state != State.FLY:
			_ang = Vector3.ZERO
			_strafe = 0.0
		if not dead:
			match state:
				State.FLY: _fly(delta)
				State.LANDING: _do_landing(delta)
				State.LANE: _do_lane(delta)
				State.JUMP: _do_jump(delta)
			_since_hit += delta
			# Skjoldet lader op efter 3 s uden træffere (lagskjold: hele tiden). Et
			# overladet skjold (skjoldbatteri) får lov at falde langsomt tilbage.
			if shield > shield_max:
				shield = maxf(shield_max, shield - 2.0 * delta)
			elif _since_hit > 3.0 or handling.has("layers"):
				shield = minf(shield_max, shield + 8.0 * float(handling.get("regen_mult", 1.0)) * delta)
			_update_lock(delta)
		_update_sound(delta)
		_send_t += delta
		if _send_t >= SEND_INTERVAL and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			_send_t = 0.0
			_net_state.rpc(position, quaternion, speed, state, dead, boosting)
	elif _net_has:
		var k := 1.0 - exp(-delta * 12.0)
		if position.distance_to(_net_pos) > 300.0:
			position = _net_pos
		position = position.lerp(_net_pos, k)
		quaternion = quaternion.slerp(_net_rot, k)
	model.thrust = speed / max_speed()
	model.rotation.z = _bank
	model.visible = not dead and not hide_model
	if boosting and not dead and randf() < 0.6:
		W.fx.spawn(global_transform * Vector3(randf_range(-1.2, 1.2), randf_range(-0.4, 0.2), 4.2),
			-forward() * 10.0, Color("ffd23f"), 0.35, 0.35)


# ---------------------------------------------------------------- flyvning

## Styring: musens afstand fra midten giver en ønsket drejehastighed, og skibet glider
## blødt hen mod den (agility). Det giver en flydende, men hurtig fornemmelse.
## Drejeevne, reaktion og acceleration kommer fra skibsklassen og opgraderinger.
func _fly(delta: float) -> void:
	var ax := 0.0
	var ay := 0.0
	var mouse_roll := 0.0
	if steering:
		var vp := get_tree().root
		var m := vp.get_mouse_position()
		var sz := Vector2(vp.size)
		if sz.x > 0 and sz.y > 0:
			var st := mouse_steer(m, sz, false, delta)
			ax = st.x
			ay = st.y
			mouse_roll = st.z
	elif _rmb_down:
		_rmb_down = false
		rolling_with_mouse = false
	var roll := clampf(Input.get_axis("roll_right", "roll_left") + mouse_roll, -1.0, 1.0)
	var turn := float(handling["turn"])
	# Afterburner gør skibet lidt mindre adræt
	if boosting:
		turn *= 0.8
	if cruise == 2:
		turn *= 0.45
	var sens := Game.mouse_sensitivity
	var want := Vector3(clampf(ay * sens, -1.0, 1.0) * turn * 0.9, -clampf(ax * sens, -1.0, 1.0) * turn, roll * float(handling["roll"]))
	_ang = _ang.lerp(want, 1.0 - exp(-float(handling["agility"]) * delta))
	var b := basis
	b = b * Basis(Vector3.RIGHT, _ang.x * delta)
	b = b * Basis(Vector3.UP, _ang.y * delta)
	b = b * Basis(Vector3.BACK, _ang.z * delta)
	basis = b.orthonormalized()
	# Skibsmodellen krænger ind i svinget
	_bank = lerpf(_bank, clampf(_ang.y / turn, -1.0, 1.0) * 0.75, 1.0 - exp(-8.0 * delta))

	if Input.is_action_pressed("throttle_up"):
		throttle = minf(1.0, throttle + 0.9 * delta)
	if Input.is_action_pressed("throttle_down"):
		throttle = maxf(0.0, throttle - 0.9 * delta)
	boosting = Input.is_action_pressed("boost") and cruise != 2
	if steering and Input.is_action_just_pressed("cruise"):
		toggle_cruise()
	_update_cruise(delta)
	var target := throttle * max_speed() + (boost_speed() if boosting else 0.0)
	if cruise == 2:
		target = CRUISE_SPEED
	var accel := float(handling["accel"]) * (1.6 if boosting else 1.0) * (0.6 if cruise == 2 else 1.0)
	if target < speed:
		accel *= 1.3    # bremser lidt hurtigere, end den speeder op
	speed = lerpf(speed, target, 1.0 - exp(-accel * delta))
	_strafe = lerpf(_strafe, Input.get_axis("strafe_left", "strafe_right") * float(handling["strafe"]), 1.0 - exp(-6.0 * delta))
	position += forward() * speed * delta + global_basis.x * _strafe * delta
	if W.weather:
		position += W.weather.wind_at(position) * delta

	_update_aim()
	if loadout:
		var can := steering and cruise != 2
		loadout.tick(delta, can and Input.is_action_pressed("fire"), can and Input.is_action_pressed("fire_2"))

	_collide_planet(delta)
	_collide_stations()
	if W.assault and W.assault.active():
		var push := W.assault.collide(position)
		if push != Vector3.INF:
			position = push
			if speed > 15.0:
				Game.toast.emit("Kollision!")
				W.fx.burst(position, 12, 14.0, [Color("ffd23f"), Color.WHITE, Color("ff7a3d")], 0.8, 0.6)
				take_damage(10.0 + speed * 0.3)
			speed *= 0.35
	if W.asteroids and W.asteroids.collide(position, 2.0):
		take_damage(12.0 + speed * 0.2)
		speed *= 0.3
		Game.toast.emit("Kollision!")
	if W.pirates and W.pirates.ram_check(position):
		take_damage(20.0)
		speed *= 0.5
	if dead:
		return

	_lane_cool -= delta
	_gate_cool -= delta
	if _lane_cool <= 0.0:
		var l := universe.lane_entry(position)
		if not l.is_empty():
			_start_lane(l)
			return
	if _gate_cool <= 0.0:
		var g := universe.gate_at(position)
		if not g.is_empty():
			_start_jump(g)
			return
	if steering and Input.is_action_just_pressed("target_nearest"):
		lock_nearest()
	if steering and Input.is_action_just_pressed("lock"):
		cycle_lock()
	if steering and Input.is_action_just_pressed("scan"):
		scan()
	if steering and Input.is_action_just_pressed("missile"):
		fire_missile()
	if steering and Input.is_action_just_pressed("bomb") and cruise != 2:
		drop_bomb()
	tractor_on = steering and "traktor" in handling.get("gadgets", []) and Input.is_action_pressed("tractor")
	if steering and Input.is_action_just_pressed("flare"):
		var err := W.missiles.fire_flares(self)
		if err != "":
			Game.toast.emit(err)
	if Input.is_action_just_pressed("land"):
		try_land()


func toggle_cruise() -> void:
	if cruise != 0:
		stop_cruise("")
		return
	if state != State.FLY or dead:
		return
	var pl := universe.nearest_planet(position)
	if pl.ground_altitude(position) < CRUISE_MIN_GROUND * 1.5:
		Game.toast.emit("For tæt på jorden til cruise")
		return
	cruise = 1
	cruise_t = 0.0
	Sfx.play("scan", -6.0)


func stop_cruise(msg: String) -> void:
	if cruise == 0:
		return
	cruise = 0
	cruise_t = 0.0
	if msg != "":
		Game.toast.emit(msg)


func _update_cruise(delta: float) -> void:
	if cruise == 0:
		return
	if state != State.FLY or dead:
		cruise = 0
		return
	if Input.is_action_pressed("throttle_down") and steering:
		stop_cruise("")
		return
	var pl := universe.nearest_planet(position)
	var ga := pl.ground_altitude(position)
	if cruise == 2 and ga < CRUISE_MIN_GROUND:
		stop_cruise("Cruise afbrudt – terræn forude")
		speed = minf(speed, max_speed() + boost_speed())
		return
	# Varsling: terrænet foran (ca. 2 s frem) er for tæt på
	if cruise == 2:
		var ahead := position + forward() * speed * 1.2
		if pl.ground_altitude(ahead) < CRUISE_MIN_GROUND * 0.6:
			stop_cruise("Cruise afbrudt – terræn forude")
			speed = minf(speed, max_speed() + boost_speed())
			return
	if cruise == 1:
		cruise_t += delta
		if cruise_t >= CRUISE_CHARGE:
			cruise = 2
			throttle = 1.0
			Sfx.play("lane", -6.0)


## Musestyring: (sving, stigning, rul) fra musens position. Højre musetast er nu
## sekundære våben (se Game._setup_input), så `rmb` bruges ikke længere fra spillet;
## rul med Q/E og lås mål med R/T. Rul-med-mus findes stadig, hvis `rmb` sendes ind.
func mouse_steer(m: Vector2, sz: Vector2, rmb: bool, delta: float) -> Vector3:
	var x := m.x
	var roll := 0.0
	if rmb and not _rmb_down:
		_rmb_down = true
		_rmb_t = 0.0
		_rmb_anchor = m
		_rmb_moved = 0.0
	if _rmb_down:
		_rmb_t += delta
		_rmb_moved = maxf(_rmb_moved, absf(m.x - _rmb_anchor.x))
		rolling_with_mouse = _rmb_moved > RMB_TAP_MOVE or _rmb_t > RMB_TAP_TIME
		if rolling_with_mouse:
			x = _rmb_anchor.x
			# Højre = rul højre. En kvart skærmbredde giver fuldt rul.
			roll = -clampf(_deadzone((m.x - _rmb_anchor.x) / (sz.x * 0.25)), -1.0, 1.0)
		if not rmb:
			_rmb_down = false
			if rolling_with_mouse:
				rolling_with_mouse = false
				Input.warp_mouse(Vector2(_rmb_anchor.x, m.y))
				x = _rmb_anchor.x
			else:
				cycle_lock()
	var ax := _curve(_deadzone(x / sz.x * 2.0 - 1.0))
	var ay := _curve(_deadzone(-(m.y / sz.y * 2.0 - 1.0))) * (-1.0 if Game.invert_y else 1.0)
	return Vector3(ax, ay, roll)


func _deadzone(v: float) -> float:
	return 0.0 if absf(v) < 0.04 else (v - signf(v) * 0.04) / 0.96


## Blød kurve: præcis tæt på midten, fuld drejning ude ved kanten.
static func _curve(v: float) -> float:
	return signf(v) * minf(1.0, pow(absf(v) * 1.1, 1.12))


func _collide_planet(delta: float) -> void:
	var p := universe.nearest_planet(position)
	if p == null:
		return
	# Grotternes klippevægge
	var cp := Cave.push(p, position)
	if cp["hit"]:
		position = cp["pos"]
		if speed > 18.0:
			Game.toast.emit("Ramte klippen!")
			W.fx.burst(position, 10, 12.0, [Color("8a6bbf"), Color.WHITE], 0.7, 0.6)
			take_damage(speed * 0.35)
		speed *= 0.4
	var rel := position - p.position
	var dir := rel.normalized()
	var surf := p.fine_surface_radius(dir) + 2.0
	if rel.length() < surf:
		position = p.position + dir * (surf + 0.5)
		if speed > 12.0:
			Game.toast.emit("Ramte jorden!")
			W.fx.burst(position, 14, 15.0, [Color("8a5a3c"), Color("6bdc4f"), Color.WHITE], 0.8, 0.8)
			take_damage(speed * 0.6)
		speed *= 0.25
	# Re-entry: kun når man dykker hurtigt ned gennem den øvre atmosfære,
	# ikke når man flyver vandret hen over bakker og bjerge.
	var alt := rel.length() - p.radius
	var above_ground := rel.length() - surf
	reentry = alt < p.atmo_top and alt > p.atmo_top * 0.35 and above_ground > 30.0 \
		and speed > 35.0 and forward().dot(dir) < -0.3
	if reentry:
		for k in 2:
			var c: Color = [Color("ff7a3d"), Color("ffd23f"), Color("ff4f8b")][randi() % 3]
			W.fx.spawn(position + forward() * 3.5 + Vector3(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)),
				-forward() * 25.0, c, randf_range(0.5, 1.1), 0.4)
		hull -= delta * 1.2
		if hull <= 0.0:
			_die()


func _collide_stations() -> void:
	for s in universe.stations:
		if s.mobile:
			if position.distance_to(s.position) < 120.0:
				var mp := s.collide_mobile(position)
				if mp != Vector3.INF:
					position = mp
					if speed > 12.0:
						Game.toast.emit("Ramte dreadnoughten!")
						take_damage(speed * 0.3)
					speed *= 0.3
			continue
		if s.is_base:
			if position.distance_to(s.position) < 90.0:
				var push := s.collide_point(position)
				if push != Vector3.INF:
					position = push
					if speed > 12.0:
						Game.toast.emit("Ramte basen!")
						take_damage(speed * 0.3)
					speed *= 0.3
			continue
		var d := position.distance_to(s.position)
		if d < s.collide_radius:
			position = s.position + (position - s.position).normalized() * (s.collide_radius + 0.5)
			if speed > 12.0:
				Game.toast.emit("Ramte stationen!")
				take_damage(speed * 0.4)
			speed *= 0.3


# ---------------------------------------------------------------- kamp

## Kanonerne sigter mod musemarkøren (som i Freelancer): en stråle fra kameraet gennem
## markøren, samlet på en pirat, der ligger tæt på strålen, ellers 300 m ude. Kanonerne kan
## kun dreje en vis vinkel væk fra næsen (gimbal, afhænger af skibstypen).
func _update_aim() -> void:
	aim_dir = forward()
	aim_point = position + aim_dir * 300.0
	aim_clamped = false
	if not steering:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	var cont := vp.get_parent() as SubViewportContainer
	if cam == null:
		return
	var shrink := float(cont.stretch_shrink) if cont else 1.0
	var m := get_tree().root.get_mouse_position() / shrink
	aim_from_ray(cam.project_ray_origin(m), cam.project_ray_normal(m))


## Sigt kanonerne langs en stråle (fra kameraet gennem musemarkøren).
func aim_from_ray(ro: Vector3, rd: Vector3) -> void:
	aim_clamped = false
	var dist := 300.0
	if W.pirates:
		var best := INF
		for pp in W.pirates.positions_in(universe.system_at(position)):
			var to := pp - ro
			var along := to.dot(rd)
			if along > 10.0 and along < 900.0 and (to - rd * along).length() < maxf(5.0, along * 0.06) and along < best:
				best = along
				dist = along
	var p := ro + rd * dist
	var want := (p - position).normalized()
	var ang := forward().angle_to(want)
	var g := deg_to_rad(float(handling.get("gimbal", 20.0)))
	if ang > g:
		want = forward().slerp(want, g / ang).normalized()
		aim_clamped = true
	aim_dir = want
	aim_point = position + want * position.distance_to(p)


## Affyr alle våben én gang (uanset genopladning) – bruges af tests og ved første tryk.
func fire() -> void:
	if loadout == null:
		return
	loadout.rebuild()
	for w in loadout._w:
		var d: Dictionary = w["def"]
		if not d.get("beam", false):
			loadout._fire_weapon(w, d)


## Kappe (gadget): skibet bliver næsten usynligt, og piraterne mister det.
func set_cloak(on: bool) -> void:
	cloaked = on
	_apply_cloak_look()


func _apply_cloak_look() -> void:
	if model == null:
		return
	var tr := (0.85 if is_local() else 0.97) if cloaked else 0.0
	for mi in model.find_children("*", "GeometryInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = tr
	if _label:
		_label.visible = not cloaked and not dead


@rpc("authority", "call_remote", "reliable")
func _net_cloak(on: bool) -> void:
	set_cloak(on)


# ---------------------------------------------------------------- lock-on

## Lock-on-rækkevidde (kortere i en sandstorm).
func lock_range() -> float:
	return LOCK_RANGE * (W.weather.lock_mul(position) if W.weather else 1.0)


func is_locked() -> bool:
	return lock_target >= 0 and lock_t >= LOCK_TIME


## T/højreklik: lås målet tættest på sigtekornet; tryk igen for at skifte til det næste.
## Er ingen pirater foran, låses den nærmeste inden for rækkevidde.
func cycle_lock() -> void:
	if W.pirates == null or state != State.FLY or dead:
		return
	var sys := universe.system_at(position)
	var cand := W.pirates.lock_candidates(position, forward(), lock_range(), LOCK_CONE, sys)
	if cand.is_empty():
		cand = W.pirates.lock_candidates(position, forward(), lock_range(), -1.0, sys)
	if cand.is_empty():
		if lock_target >= 0:
			clear_lock(true)
		else:
			Game.toast.emit("Ingen mål inden for rækkevidde")
		return
	var next: int = cand[0]
	var at := cand.find(lock_target)
	if at >= 0:
		next = cand[(at + 1) % cand.size()]
		if next == lock_target:
			return
	_set_lock(next)


## Lås den nærmeste fjende (som "Target closest enemy" i Freelancer). Trykker man
## igen, mens den allerede er låst, skiftes til den næstnærmeste.
func lock_nearest() -> void:
	if W.pirates == null or state != State.FLY or dead:
		return
	var sys := universe.system_at(position)
	var cand := W.pirates.lock_candidates(position, forward(), lock_range(), -1.0, sys)
	if cand.is_empty():
		Game.toast.emit("Ingen fjender inden for rækkevidde")
		return
	cand.sort_custom(func(a: int, b: int) -> bool:
		return position.distance_squared_to(W.pirates.position_of(a)) < position.distance_squared_to(W.pirates.position_of(b)))
	var next: int = cand[0]
	if next == lock_target and cand.size() > 1:
		next = cand[1]
	if next != lock_target:
		_set_lock(next)


func _set_lock(i: int) -> void:
	lock_target = i
	lock_t = 0.0
	Sfx.play("laaser", -2.0, 0.0)
	lock_changed.emit()


func clear_lock(with_sound := false) -> void:
	if lock_target < 0:
		return
	lock_target = -1
	lock_t = 0.0
	if with_sound:
		Sfx.play("lock_tabt", -3.0, 0.0)
	lock_changed.emit()


func _update_lock(delta: float) -> void:
	if lock_target < 0:
		return
	if W.pirates == null or state != State.FLY or dead:
		clear_lock()
		return
	if not W.pirates.is_active(lock_target):
		# Målet er skudt ned: skift automatisk til det næste foran os, hvis der er et.
		var cand := W.pirates.lock_candidates(position, forward(), lock_range(), LOCK_CONE, universe.system_at(position))
		lock_target = -1
		if cand.is_empty():
			lock_changed.emit()
		else:
			_set_lock(cand[0])
		return
	if position.distance_to(W.pirates.position_of(lock_target)) > lock_range() * 1.3:
		clear_lock(true)
		Game.toast.emit("Målet slap væk")
		return
	if lock_t < LOCK_TIME:
		lock_t += delta
		if lock_t >= LOCK_TIME:
			Sfx.play("laast", -2.0, 0.0)


## Hvor man skal skyde for at ramme det låste mål (målets fart og skuddenes fart).
func lead_point() -> Vector3:
	if lock_target < 0 or W.pirates == null:
		return position + forward() * 100.0
	var tp := W.pirates.position_of(lock_target)
	var tv := W.pirates.velocity_of(lock_target)
	var bs := BOLT_SPEED + speed
	var aim := tp
	for k in 3:
		var t := position.distance_to(aim) / bs
		aim = tp + tv * t
	return aim


## Missil (R / midterste museknap) mod det låste mål.
func drop_bomb() -> void:
	if W.bombs == null:
		return
	var err := W.bombs.drop(self)
	if err != "" and err != "busy":
		Game.toast.emit(err)


func fire_missile() -> void:
	if W.missiles == null or state != State.FLY or dead:
		return
	var err := W.missiles.fire_player(self)
	if err != "" and err != "busy":
		Game.toast.emit(err)


## Scanner (C): en puls, der finder vrag, ruiner, kapsler og piratlejre i nærheden.
func scan() -> void:
	if W.sites == null or state != State.FLY or dead:
		return
	var found := W.sites.scan(position)
	var storm := " – sandstormen forstyrrer" if W.weather and W.weather.scan_mul(position) < 0.9 else ""
	if found < 0:
		Game.toast.emit("Scanneren lader op …")
	elif found == 0:
		Game.toast.emit("Scanning: ingen nye signaler" + storm)
	else:
		Game.toast.emit("Scanning: %d %s fundet%s" % [found, "nyt signal" if found == 1 else "nye signaler", storm])


## Sigtehjælp: låst mål og forudsigelsespunktet inden for ca. 11° af næsen.
func aim_assist_active() -> bool:
	if not is_locked():
		return false
	var to_lead := (lead_point() - position).normalized()
	if forward().dot(to_lead) > ASSIST_CONE:
		return true
	# Sigter man med musen tæt på forudsigelsespunktet, og kan kanonerne nå det, hjælper de også.
	var g := deg_to_rad(float(handling.get("gimbal", 20.0)))
	return aim_dir.dot(to_lead) > cos(deg_to_rad(6.0)) and forward().angle_to(to_lead) < g


# ---------------------------------------------------------------- lyd

func _update_sound(delta: float) -> void:
	if not is_local():
		return
	var flying := not dead and (state == State.FLY or state == State.LANDING or state == State.LANE)
	var level := 0.0
	if flying:
		level = 0.35 + 0.5 * clampf(speed / max_speed(), 0.0, 1.0) + (0.25 if boosting else 0.0)
	Sfx.set_engine(level, 0.7 + speed / (max_speed() + boost_speed()) * 0.9)
	# Alarm ved kritisk skrog
	_alarm_t -= delta
	if flying and hull < 30.0 and _alarm_t <= 0.0:
		_alarm_t = 1.4
		Sfx.play("alarm", -8.0, 0.0)
	# Kampmusik, når pirater er tæt på
	var danger := false
	if W.pirates and not dead and state != State.LANDED:
		danger = W.pirates.nearest_visible(position, 650.0) != Vector3.INF
	Sfx.set_combat(danger)


## Skade fra omgivelserne (fx varme over lava) uden lyd og blink hver frame.
func environment_damage(amount: float) -> void:
	if dead or state != State.FLY:
		return
	amount *= float(handling.get("armor", 1.0))
	_since_hit = 0.0
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hull -= amount - absorbed
	if hull <= 0.0:
		_die()


## Skade på eget skib. Skjoldet tager det første.
func take_damage(amount: float) -> void:
	if dead or state != State.FLY:
		return
	if cruise != 0:
		stop_cruise("Cruise afbrudt – du bliver ramt!")
	amount *= float(handling.get("armor", 1.0))
	_since_hit = 0.0
	var rest := amount
	var layers := int(handling.get("layers", 0))
	if layers > 0 and shield_max > 0.0:
		# Lagskjold: et helt lag stopper hele skuddet; et halvt opladet lag stopper intet.
		var layer := shield_max / float(layers)
		if shield >= layer - 0.01:
			shield -= layer
			rest = 0.0
	else:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		rest = amount - absorbed
	hull -= rest
	Sfx.play("skrog" if rest > 0.0 else "skjold", -3.0)
	damaged.emit(rest > 0.0)
	if hull <= 0.0:
		_die()


func _die() -> void:
	if dead:
		return
	dead = true
	hull = 0.0
	speed = 0.0
	reentry = false
	boosting = false
	cruise = 0
	W.fx.explosion(position, true)
	Sfx.play("eksplosion_stor", 2.0)
	clear_lock()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_net_boom.rpc(position)
	destroyed.emit()
	await get_tree().create_timer(1.6).timeout
	_salvage()


## Efter at være skudt ned: bjærges til nærmeste by i systemet mod et gebyr.
func _salvage() -> void:
	Game.report_death()
	var sys := universe.system_at(position)
	hull = 60.0
	shield = shield_max
	dead = false
	# Hjem til Concord-basen, hvis systemet har en; ellers nærmeste by.
	var base := universe.home_base(sys)
	if base:
		dock_at(base.id)
		salvaged.emit(base.id)
		return
	var best: PlanetBody = null
	var bd := INF
	for p in universe.planets:
		if p.system_id == sys and p.pad_top.distance_to(position) < bd:
			bd = p.pad_top.distance_to(position)
			best = p
	position = best.pad_top + best.pad_dir * 1.9
	basis = Basis.looking_at(best.tangent, best.pad_dir)
	hull = 60.0
	shield = shield_max
	dead = false
	state = State.LANDED
	docked_at = best.id
	salvaged.emit(best.id)


# ---------------------------------------------------------------- landing og docking

## Forsøger at lande på/docke ved det nærmeste sted. Returnerer en fejlkode eller "".
## Placér skibet docket ved en station (fx ved start i basens hangar).
func dock_at(station_id: String, slot := 0) -> void:
	var s := universe.station(station_id)
	if s.is_base:
		# Egen plads i hangaren, næsen ud mod åbningen
		position = s.pad_world(slot) + s._body_xf().basis.y * 1.6
		basis = Basis.looking_at(s.dock_dir, s._body_xf().basis.y)
	else:
		var side := s.dock_dir.cross(Vector3.UP if absf(s.dock_dir.y) < 0.95 else Vector3.RIGHT).normalized()
		position = s.dock_pos + s.dock_dir * 4.0 + side * (slot * 7.0 - 3.5 if slot > 0 else 0.0)
		basis = Basis.looking_at(-s.dock_dir, Vector3.UP if absf(s.dock_dir.y) < 0.9 else Vector3.RIGHT)
	state = State.LANDED
	docked_at = station_id
	speed = 0.0
	reset_physics_interpolation()
	throttle = 0.0
	boosting = false
	cruise = 0


func try_land() -> String:
	if state != State.FLY or dead:
		return "busy"
	var spot := universe.landing_spot(position)
	if spot.is_empty():
		Game.toast.emit("Flyv hen til en landingsplads eller en dok")
		return "far"
	if speed >= LAND_SPEED:
		Game.toast.emit("For hurtigt – sænk farten")
		return "fast"
	var to_pos: Vector3
	var to_basis: Basis
	if spot["kind"] == "planet":
		var pad: Dictionary = universe.pad_of(spot["id"])["pad"]
		var pd: Vector3 = pad["dir"]
		var f := forward() - pd * forward().dot(pd)
		if f.length() < 0.01:
			f = pad["tangent"]
		to_basis = Basis.looking_at(f.normalized(), pd)
		to_pos = (pad["top"] as Vector3) + pd * 1.9
	elif spot["kind"] == "site":
		var site := W.sites.get_site(str(spot["id"]).trim_prefix("site:"))
		var up: Vector3 = site["land_up"]
		var f := forward() - up * forward().dot(up)
		if f.length() < 0.01:
			f = site["tangent"]
		to_basis = Basis.looking_at(f.normalized(), up)
		to_pos = (site["land"] as Vector3) + up * 1.9
	else:
		var s := universe.station(spot["id"])
		if s.is_base:
			# Land på sin egen plads i hangaren, næsen vendt ud mod åbningen
			to_basis = Basis.looking_at(s.dock_dir, s._body_xf().basis.y)
			to_pos = s.pad_world(slot) + s._body_xf().basis.y * 1.6
		else:
			to_basis = Basis.looking_at(-s.dock_dir, Vector3.UP if absf(s.dock_dir.y) < 0.9 else Vector3.RIGHT)
			to_pos = s.dock_pos + s.dock_dir * 4.0
	_landing = {"t": 0.0, "dur": 1.8 if spot["kind"] == "station" else 1.6, "id": spot["id"],
		"from_pos": position, "from_rot": quaternion, "to_pos": to_pos, "to_rot": to_basis.get_rotation_quaternion()}
	state = State.LANDING
	boosting = false
	cruise = 0
	clear_lock()
	Sfx.play("dock", -4.0, 0.0)
	return ""


func _do_landing(delta: float) -> void:
	_landing["t"] += delta / _landing["dur"]
	var k := smoothstep(0.0, 1.0, _landing["t"])
	position = (_landing["from_pos"] as Vector3).lerp(_landing["to_pos"], k)
	quaternion = (_landing["from_rot"] as Quaternion).slerp(_landing["to_rot"], k)
	speed *= 0.9
	_bank = lerpf(_bank, 0.0, 0.1)
	if _landing["t"] >= 1.0:
		position = _landing["to_pos"]
		quaternion = _landing["to_rot"]
		state = State.LANDED
		docked_at = _landing["id"]
		speed = 0.0
		throttle = 0.0
		landed.emit(docked_at)


func launch() -> void:
	if state != State.LANDED:
		return
	var po := universe.pad_of(docked_at)
	if docked_at.begins_with("site:"):
		var site := W.sites.get_site(docked_at.trim_prefix("site:"))
		var sup: Vector3 = site.get("land_up", position.normalized())
		var f := forward() - sup * forward().dot(sup)
		basis = Basis.looking_at(sup, f.normalized() if f.length() > 0.01 else Vector3.FORWARD)
		position = (site.get("land", position) as Vector3) + sup * 6.0
	elif not po.is_empty():
		# Let lodret op fra landingspladsen.
		var pad: Dictionary = po["pad"]
		var pd: Vector3 = pad["dir"]
		var up := forward() - pd * forward().dot(pd)
		basis = Basis.looking_at(pd, up.normalized() if up.length() > 0.01 else pad["tangent"])
		position = (pad["top"] as Vector3) + pd * 6.0
	else:
		var s := universe.station(docked_at)
		if s.is_base:
			# Let fra pladsen og flyv ud gennem hangarens åbning
			basis = Basis.looking_at(s.dock_dir, s._body_xf().basis.y)
			position = s.pad_world(slot) + s._body_xf().basis.y * 3.0
		else:
			basis = Basis.looking_at(s.dock_dir, Vector3.UP if absf(s.dock_dir.y) < 0.9 else Vector3.RIGHT)
			position = s.dock_pos + s.dock_dir * 10.0
	docked_at = ""
	state = State.FLY
	speed = 22.0
	reset_physics_interpolation()
	throttle = 0.5
	Sfx.play("afgang", -4.0, 0.0)
	launched.emit()


# ---------------------------------------------------------------- trade lane

func _start_lane(l: Dictionary) -> void:
	var a: Vector3 = l["a"]
	var b: Vector3 = l["b"]
	_lane = {"a": a, "dir": (b - a).normalized(), "d": 0.0, "len": a.distance_to(b)}
	position = a
	state = State.LANE
	reset_physics_interpolation()
	boosting = false
	cruise = 0
	clear_lock()
	Sfx.play("lane", -4.0, 0.0)
	Game.toast.emit("Trade lane · hold fast")


func _do_lane(delta: float) -> void:
	_lane["d"] += Universe.LANE_SPEED * delta
	speed = Universe.LANE_SPEED
	var dir: Vector3 = _lane["dir"]
	position = (_lane["a"] as Vector3) + dir * minf(_lane["d"], _lane["len"])
	var target := Basis.looking_at(dir, global_basis.y).get_rotation_quaternion()
	quaternion = quaternion.slerp(target, minf(1.0, delta * 4.0))
	_bank = lerpf(_bank, 0.0, 0.1)
	for k in 3:
		W.fx.spawn(position + dir * randf_range(20, 60) + Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)),
			-dir * 260.0, Color("4dffe1"), 0.35, 0.3)
	if _lane["d"] >= _lane["len"]:
		position += dir * 20.0
		state = State.FLY
		_lane_cool = 3.0
		speed = max_speed()
		throttle = 1.0
		Game.toast.emit("Ude af trade lanen")


# ---------------------------------------------------------------- jump gate

func _start_jump(g: Dictionary) -> void:
	_jump = {"t": 0.0, "to": g["to"], "done": false}
	state = State.JUMP
	boosting = false
	cruise = 0
	clear_lock()
	Sfx.play("hop", -2.0, 0.0)
	Game.toast.emit("Hopper …")


func _do_jump(delta: float) -> void:
	_jump["t"] += delta
	var t: float = _jump["t"]
	speed = 60.0 + t * 500.0 if t < 0.8 else 60.0
	position += forward() * speed * delta
	if t < 0.8:
		for k in 4:
			W.fx.spawn(position + forward() * randf_range(15, 50) + Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10)),
				-forward() * 300.0, Color("c77dff") if t < 0.4 else Color.WHITE, 0.4, 0.25)
	if t >= 0.8 and not _jump["done"]:
		_jump["done"] = true
		var dst: Dictionary = universe.gates[_jump["to"]]
		var dir: Vector3 = dst["dir"]
		position = (dst["pos"] as Vector3) + dir * 30.0
		basis = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
		reset_physics_interpolation()
		var sys: Dictionary = Game.systems[dst["system"]]
		Game.toast.emit("Velkommen til " + str(sys["name"]))
	jump_fx = t / 0.8 if t < 0.8 else maxf(0.0, 1.0 - (t - 0.8) / 0.7)
	if t >= 1.5:
		jump_fx = 0.0
		state = State.FLY
		_gate_cool = 3.0
		speed = 40.0
		throttle = 0.7


# ---------------------------------------------------------------- netværk

@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, rot: Quaternion, spd: float, st: int, is_dead: bool, is_boost: bool) -> void:
	if not _net_has:
		position = pos
		quaternion = rot
	_net_pos = pos
	_net_rot = rot
	_net_has = true
	speed = spd
	state = st as State
	dead = is_dead
	boosting = is_boost
	if _label:
		_label.visible = not dead


@rpc("authority", "call_remote", "unreliable")
func _net_fire(pos: Vector3, dir: Vector3, spd: float, color: Color) -> void:
	var right := (dir.cross(Vector3.UP)).normalized() * 2.2
	W.bolts.fire(pos + right, dir, spd, color, Bolts.Kind.REMOTE)
	W.bolts.fire(pos - right, dir, spd, color, Bolts.Kind.REMOTE)
	Sfx.play_at("laser", pos, -6.0)


@rpc("authority", "call_remote", "reliable")
func _net_boom(pos: Vector3) -> void:
	W.fx.explosion(pos, true)
	Sfx.play_at("eksplosion_stor", pos, 2.0)
