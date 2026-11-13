class_name Hud
extends Control
## Cockpit-HUD i fuld opløsning oven på pixelbilledet: skjold, skrog, kredit, last,
## fart, system og højde, pirater, piloter i co-op, markører for steder, andre
## spillere og pirater, landingsprompt, advarsler, beskeder og skærmblink.

var camera: ChaseCamera
var view: SubViewportContainer
var universe: Universe
var ship: Ship
var ships: Dictionary = {}     ## peer-id -> Ship (alle, til markører)

var _box_left: PanelContainer
var _box_right: PanelContainer
var _shield: ProgressBar
var _shield_val: Label
var _hull: ProgressBar
var _hull_val: Label
var _credits: Label
var _cargo: Label
var _speed: ProgressBar
var _speed_val: Label
var _boost: Label
var _system: Label
var _alt_cap: Label
var _alt: Label
var _pirates: Label
var _boss: BossBar
var _arms: ArmsPanel
var _pilots: Label
var _scan: Label
var _missiles: Label
var _flares: Label
var _bombs: Label
var _rank: Label
var _mission: PanelContainer
var _jobs: PanelContainer
var _jobs_list: VBoxContainer
var _jobs_shown := ""
var _hail_hint: Label
var _m_name: Label
var _m_obj: Label
var _m_prog: Label
var _m_timer: Label
var _m_escort: ProgressBar
var _m_escort_val: Label
var _m_escort_row: HBoxContainer
var _prompt: Label
var _warn: Label
var _toast: Label
var _flash: ColorRect
var _hitflash: ColorRect
var _cursor: ColorRect
var _reticle: Panel
var _markers: Array[Label] = []
var _lock_overlay: LockOverlay
var _lock_label: Label
var _lock_hint: Label
## F9: ydelsesvisning (billeder pr. sekund og de langsomste billeder)
var perf_visible := false
var _perf: Label
var _frame_ms: Array[float] = []
var _toast_t := 0.0
var _hit_t := 0.0

## Markører på skærmen (F7): 0 = alle, 1 = færre (kun de vigtigste og nærmeste), 2 = kun mål
var marker_mode := 1
const MARKER_MODE_NAMES := ["alle", "færre", "kun mål"]
const MARKER_COLORS := {"planet": UiTheme.PINK, "station": UiTheme.CYAN, "gate": UiTheme.VIOLET, "lane": UiTheme.YELLOW, "base": Color("6fa8ff"), "outpost": Color("ffb36b"), "plot": Color("6bdc4f")}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_boss = BossBar.new()
	add_child(_boss)
	_arms = ArmsPanel.new()
	add_child(_arms)

	_flash = _fullscreen(Color(UiTheme.VIOLET, 0.0))
	_hitflash = _fullscreen(Color(UiTheme.DANGER, 0.0))

	# Venstre boks: skib og økonomi
	_box_left = _box()
	_box_left.position = Vector2(16, 16)
	var vl := VBoxContainer.new()
	vl.add_theme_constant_override("separation", 6)
	_box_left.add_child(vl)
	var sh := _bar_row(vl, "Skjold", UiTheme.CYAN)
	_shield = sh[0]
	_shield_val = sh[1]
	var hu := _bar_row(vl, "Skrog", UiTheme.GREEN)
	_hull = hu[0]
	_hull_val = hu[1]
	_credits = _row(vl, "Kredit")
	_cargo = _row(vl, "Last")
	var sp := _bar_row(vl, "Fart", UiTheme.YELLOW)
	_speed = sp[0]
	_speed_val = sp[1]
	_speed.max_value = Ship.MAX_SPEED + Ship.BOOST_SPEED
	_boost = UiTheme.caption("Boost", UiTheme.YELLOW)
	(_speed.get_parent() as HBoxContainer).add_child(_boost)
	_missiles = _row(vl, "Missil")
	_flares = _row(vl, "Flares")
	_bombs = _row(vl, "Bomber")

	# Højre boks: navigation, pirater og piloter
	_box_right = _box()
	var vr := VBoxContainer.new()
	vr.add_theme_constant_override("separation", 6)
	_box_right.add_child(vr)
	_system = _row(vr, "System")
	var ar := HBoxContainer.new()
	vr.add_child(ar)
	_alt_cap = UiTheme.caption("Højde")
	ar.add_child(_alt_cap)
	_alt = UiTheme.value("–")
	ar.add_child(_alt)
	_pirates = _row(vr, "Pirater")
	_rank = _row(vr, "Rang")
	_pilots = _row(vr, "Piloter")
	_scan = _row(vr, "Scanner")

	# Missionspanel under venstre boks
	_mission = _box()
	_mission.position = Vector2(16, 236)
	_mission.custom_minimum_size = Vector2(300, 0)
	var vm := VBoxContainer.new()
	vm.add_theme_constant_override("separation", 4)
	_mission.add_child(vm)
	_m_name = UiTheme.value("", UiTheme.YELLOW, 15)
	vm.add_child(_m_name)
	_m_obj = UiTheme.value("", UiTheme.TEXT, 14)
	_m_obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_m_obj.custom_minimum_size = Vector2(280, 0)
	vm.add_child(_m_obj)
	_m_prog = UiTheme.value("", UiTheme.CYAN, 13)
	vm.add_child(_m_prog)
	_m_timer = UiTheme.value("", UiTheme.YELLOW, 18)
	vm.add_child(_m_timer)
	var er := _bar_row(vm, "Fragtskib", UiTheme.GREEN)
	_m_escort = er[0]
	_m_escort_val = er[1]
	_m_escort_row = _m_escort.get_parent() as HBoxContainer
	_mission.visible = false

	# Sideopgaver (opslagstavle og opkald)
	_jobs = _box()
	_jobs.custom_minimum_size = Vector2(300, 0)
	_jobs_list = VBoxContainer.new()
	_jobs_list.add_theme_constant_override("separation", 2)
	_jobs.add_child(_jobs_list)
	_jobs.visible = false
	_hail_hint = UiTheme.value("", UiTheme.CYAN, 14)
	_hail_hint.add_theme_constant_override("outline_size", 5)
	_hail_hint.add_theme_color_override("font_outline_color", UiTheme.INK)
	add_child(_hail_hint)

	_warn = UiTheme.value("", UiTheme.YELLOW, 18)
	_warn.add_theme_constant_override("outline_size", 6)
	_warn.add_theme_color_override("font_outline_color", UiTheme.INK)
	add_child(_warn)

	_prompt = UiTheme.value("", UiTheme.INK, 18)
	var ps := StyleBoxFlat.new()
	ps.bg_color = UiTheme.YELLOW
	ps.shadow_color = UiTheme.PINK
	ps.shadow_offset = Vector2(4, 4)
	ps.shadow_size = 1
	ps.set_content_margin_all(10)
	_prompt.add_theme_stylebox_override("normal", ps)
	_prompt.visible = false
	add_child(_prompt)

	_toast = UiTheme.value("", UiTheme.TEXT, 16)
	var ts := StyleBoxFlat.new()
	ts.bg_color = UiTheme.PANEL_2
	ts.border_color = UiTheme.PINK
	ts.set_border_width_all(2)
	ts.set_content_margin_all(8)
	_toast.add_theme_stylebox_override("normal", ts)
	_toast.visible = false
	add_child(_toast)

	_reticle = Panel.new()
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.border_color = Color(UiTheme.CYAN, 0.7)
	rs.set_border_width_all(2)
	_reticle.add_theme_stylebox_override("panel", rs)
	_reticle.size = Vector2(20, 20)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reticle)

	_lock_overlay = LockOverlay.new()
	_lock_overlay.hud = self
	_lock_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock_overlay)
	_lock_label = UiTheme.value("", UiTheme.DANGER, 12)
	_lock_label.add_theme_constant_override("outline_size", 4)
	_lock_label.add_theme_color_override("font_outline_color", UiTheme.INK)
	_lock_label.visible = false
	add_child(_lock_label)
	_perf = UiTheme.value("", UiTheme.GREEN, 13)
	_perf.visible = false
	add_child(_perf)
	_lock_hint = UiTheme.caption("R/T: LÅS · HØJREKLIK: SEKUNDÆRE VÅBEN · G: MISSIL · F: FLARES · Q/E: RUL · C: SCAN · M: KORT", UiTheme.MUTED)
	add_child(_lock_hint)

	_cursor = ColorRect.new()
	_cursor.color = UiTheme.YELLOW
	_cursor.size = Vector2(6, 6)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor)


func _fullscreen(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _box() -> PanelContainer:
	var b := PanelContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme._box(Color(UiTheme.INK, 0.75), UiTheme.LINE, 2, Vector2.ZERO, Color.TRANSPARENT, 10)
	b.add_theme_stylebox_override("panel", sb)
	add_child(b)
	return b


func _row(parent: Container, caption: String) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var cap := UiTheme.caption(caption)
	cap.custom_minimum_size = Vector2(64, 0)
	h.add_child(cap)
	var v := UiTheme.value("–")
	h.add_child(v)
	return v


func _bar_row(parent: Container, caption: String, color: Color) -> Array:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var cap := UiTheme.caption(caption)
	cap.custom_minimum_size = Vector2(64, 0)
	h.add_child(cap)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(120, 10)
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	h.add_child(bar)
	var v := UiTheme.value("0")
	v.custom_minimum_size = Vector2(34, 0)
	h.add_child(v)
	return [bar, v]


func show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	_toast.reset_size()
	_toast_t = 2.2


## Rødt blink når skroget rammes, blåt når skjoldet tager det.
func damage_flash(hull_hit: bool) -> void:
	_hitflash.color = Color(UiTheme.DANGER if hull_hit else UiTheme.CYAN, 0.3 if hull_hit else 0.18)
	_hit_t = 0.35


func _process(delta: float) -> void:
	var flying := ship != null and is_instance_valid(ship)
	_box_left.visible = flying
	_box_right.visible = flying
	var aiming := flying and ship.state == Ship.State.FLY and ship.steering and not ship.dead
	_cursor.visible = aiming
	_reticle.visible = aiming
	_cursor.position = get_global_mouse_position() - Vector2(3, 3)
	_cursor.color = UiTheme.CYAN if flying and ship.rolling_with_mouse else UiTheme.YELLOW
	_reticle.position = size / 2.0 - Vector2(10, 10)
	var rstyle := _reticle.get_theme_stylebox("panel") as StyleBoxFlat
	rstyle.border_color = Color(UiTheme.DANGER, 0.95) if aiming and ship.aim_assist_active() else Color(UiTheme.CYAN, 0.7)
	_update_perf(delta)
	_lock_hint.visible = aiming and not camera.cockpit.visible
	if _lock_hint.visible:
		_lock_hint.text = "%s: NÆRMESTE FJENDE · %s: NÆSTE MÅL · %s: MISSIL · %s: FLARES · %s: BOMBE · %s: SCAN · %s: KORT · ESC: MENU" % [
			Game.key_name("target_nearest"), Game.key_name("lock"), Game.key_name("missile"), Game.key_name("flare"),
			Game.key_name("bomb"), Game.key_name("scan"), Game.key_name("map")]
		if ship.handling.get("special", "") == "traktor":
			_lock_hint.text = "%s (HOLD): TRAKTORSTRÅLE · " % Game.key_name("tractor") + _lock_hint.text
	_lock_hint.reset_size()
	_lock_hint.position = Vector2(roundf((size.x - _lock_hint.size.x) / 2.0), size.y - 28)
	_update_lock_label(aiming)
	_arms.ship = ship if flying else null
	_arms.visible = flying and ship.loadout != null and ship.state == Ship.State.FLY and not ship.dead and not camera.cockpit.visible
	if _arms.visible:
		_arms.queue_redraw()
		_arms.position = Vector2(16, size.y - _arms.size.y - 40.0)
	_lock_overlay.queue_redraw()

	_toast_t -= delta
	if _toast_t <= 0.0:
		_toast.visible = false
	_toast.position = Vector2(roundf((size.x - _toast.size.x) / 2.0), 150)
	_hit_t -= delta
	if _hit_t <= 0.0:
		_hitflash.color.a = maxf(0.0, _hitflash.color.a - delta * 2.0)

	if not flying:
		_mission.visible = false
		_prompt.visible = false
		_warn.text = ""
		_hide_markers(0)
		_flash.color.a = 0.0
		return

	var w: Dictionary = Game.wallet
	_shield.max_value = ship.shield_max
	_shield.value = ship.shield
	var layers := int(ship.handling.get("layers", 0))
	if layers > 0 and ship.shield_max > 0.0:
		var up := int(floor(ship.shield / (ship.shield_max / layers) + 0.01))
		_shield_val.text = "■".repeat(mini(up, layers)) + "□".repeat(maxi(0, layers - up))
	else:
		_shield_val.text = str(int(ship.shield))
	_hull.value = ship.hull
	_hull_val.text = str(int(maxf(ship.hull, 0.0)))
	var hull_fill := _hull.get_theme_stylebox("fill") as StyleBoxFlat
	hull_fill.bg_color = UiTheme.DANGER if ship.hull < 30.0 else UiTheme.GREEN
	_credits.text = "%d cr" % int(w["credits"])
	_cargo.text = "%d/%d" % [Game.cargo_total(w["cargo"]), int(w["cargo_max"])]
	_missiles.text = "%d/%d  (%s)" % [int(w.get("missiles", 0)), Game.missile_max(), Game.key_name("missile")]
	if W.missiles:
		_flares.text = "klar (%s)" % Game.key_name("flare") if W.missiles.flare_cool <= 0.0 else "lader op %d s" % ceili(W.missiles.flare_cool)
		_flares.add_theme_color_override("font_color", UiTheme.GREEN if W.missiles.flare_cool <= 0.0 else UiTheme.MUTED)
	if W.bombs:
		_bombs.get_parent().visible = W.bombs.ammo > 0
		_bombs.text = "%d  (%s)" % [W.bombs.ammo, Game.key_name("bomb")]
	_speed.max_value = ship.max_speed() + ship.boost_speed()
	_speed.value = ship.speed
	_speed_val.text = str(int(ship.speed))
	_boost.visible = ship.boosting or ship.cruise != 0
	if ship.cruise == 2:
		_boost.text = "CRUISE"
	elif ship.cruise == 1:
		_boost.text = "CRUISE %d%%" % int(ship.cruise_t / Ship.CRUISE_CHARGE * 100.0)
	else:
		_boost.text = "BOOST"
	_box_right.position = Vector2(size.x - _box_right.size.x - 16, 16)

	var sys_id := universe.system_at(ship.position)
	_system.text = str(Game.systems[sys_id]["name"])
	var p := universe.nearest_planet(ship.position)
	var alt := p.altitude(ship.position)
	if alt < p.atmo_top:
		_alt_cap.text = "HØJDE"
		_alt.text = "%d m" % maxi(0, int(p.ground_altitude(ship.position)))
	else:
		_alt_cap.text = p.display_name.to_upper()
		_alt.text = _dist(alt)
	var pirate_pos: Array[Vector3] = []
	if W.pirates:
		pirate_pos = W.pirates.positions_in(sys_id)
	_pirates.text = "%d   ·   nedkæmpet %d" % [pirate_pos.size(), int(w.get("kills", 0))]
	_boss.boss = W.pirates.boss_near(ship.position, sys_id) if W.pirates else -1
	_boss.visible = _boss.boss >= 0 and not ship.dead
	if _boss.visible:
		_boss.position = Vector2(size.x / 2.0 - BossBar.WIDTH / 2.0, 70.0)
		_boss.queue_redraw()
	var names := []
	for id: int in Game.roster:
		names.append(Game.roster[id]["name"])
	_pilots.text = ", ".join(names)
	var xp := int(w.get("xp", 0))
	_rank.text = "%s · %d xp" % [Game.rank_name(xp), xp]
	if W.sites:
		var cool := W.sites.scan_cool
		_scan.text = "klar (%s)" % Game.key_name("scan") if cool <= 0.0 else "lader op %d s" % ceili(cool)
		_scan.add_theme_color_override("font_color", UiTheme.GREEN if cool <= 0.0 else UiTheme.MUTED)
	_update_mission()
	_update_jobs()

	_flash.color.a = ship.jump_fx * 0.85
	var wx := W.weather.effect_at(ship.position) if W.weather else {"type": "", "k": 0.0}
	if W.missiles and W.missiles.incoming() > 0 and not ship.dead:
		_warn.text = "⚠ MISSIL LÅST PÅ DIG · F = FLARES"
	elif ship.cruise == 2 and not ship.dead:
		_warn.text = "» CRUISE · X/S FOR AT STOPPE «"
	elif W.assault and W.assault.near(ship.position) and W.assault.exposure(ship.position) > 0.6 and ship.state == Ship.State.FLY and not ship.dead:
		_warn.text = "⚠ LUFTSKYTS SPORER DIG – FLYV LAVERE NED I KLØFTEN"
	elif ship.reentry:
		_warn.text = "▲ RE-ENTRY ▲"
	elif W.weather and W.weather.heat and not ship.dead:
		_warn.text = "⚠ VARME · LAVA – STIG OP!"
	elif float(wx["k"]) > 0.3 and ship.state == Ship.State.FLY:
		_warn.text = str(Weather.TYPES[wx["type"]]["warn"]).to_upper()
	elif alt < p.atmo_top and alt > p.atmo_top * 0.4 and ship.state == Ship.State.FLY:
		_warn.text = "ATMOSFÆRE"
	elif ship.hull < 30.0 and not ship.dead:
		_warn.text = "SKROG KRITISK"
	else:
		_warn.text = ""
	_warn.reset_size()
	_warn.position = Vector2(roundf((size.x - _warn.size.x) / 2.0), size.y * 0.18)

	# Landingsprompt
	var spot := universe.landing_spot(ship.position) if ship.state == Ship.State.FLY and not ship.dead else {}
	_prompt.visible = not spot.is_empty()
	if _prompt.visible:
		var verb := "DOCK VED" if spot["kind"] == "station" else ("LAND VED" if spot["kind"] == "site" else "LAND PÅ")
		if ship.speed < Ship.LAND_SPEED:
			_prompt.text = "L  %s %s" % [verb, str(spot["name"]).to_upper()]
		else:
			_prompt.text = "SÆNK FARTEN FOR AT " + ("DOCKE" if spot["kind"] == "station" else "LANDE")
		_prompt.reset_size()
		_prompt.position = Vector2(roundf((size.x - _prompt.size.x) / 2.0), size.y - 120)

	# Markører
	var used := 0
	if ship.state != Ship.State.LANDED and ship.state != Ship.State.JUMP and not ship.dead:
		var pois: Array = universe.points_of_interest(sys_id, ship.position) if marker_mode < 2 else []
		if marker_mode == 1:
			# Færre: planeter, stationer, basen og gates – og kun de 6 nærmeste
			pois = pois.filter(func(q: Dictionary) -> bool: return q["kind"] in ["planet", "station", "gate", "base"])
			pois.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return ship.position.distance_squared_to(a["pos"]) < ship.position.distance_squared_to(b["pos"]))
			pois = pois.slice(0, 6)
		for poi: Dictionary in pois:
			var d := ship.position.distance_to(poi["pos"])
			if d < 25.0 or (poi["kind"] == "lane" and ship.state == Ship.State.LANE):
				continue
			var label := str(poi["label"])
			if poi["kind"] == "planet" and W.weather:
				var pl := universe.nearest_planet(poi["pos"])
				if W.weather.level.get(pl.id, 0.0) > 0.3:
					label += " · " + str(Weather.TYPES[W.weather.type_of(pl.id)]["name"])
			_place(used, poi["pos"], "%s %s" % [label, _dist(d)], MARKER_COLORS[poi["kind"]])
			used += 1
		for id: int in ships:
			var other: Ship = ships[id]
			if other == ship or not is_instance_valid(other) or other.dead or universe.system_at(other.position) != sys_id:
				continue
			_place(used, other.position, "%s %s" % [other.display_name, _dist(ship.position.distance_to(other.position))], other.paint)
			used += 1
		var locked_pos := W.pirates.position_of(ship.lock_target) if ship.lock_target >= 0 and W.pirates else Vector3.INF
		var radar := W.weather.radar_range(ship.position) if W.weather else INF
		for pm: Dictionary in W.pirates.markers_in(sys_id) if W.pirates else []:
			var pp: Vector3 = pm["pos"]
			if pp.distance_to(locked_pos) < 0.5 or ship.position.distance_to(pp) > radar:
				continue
			var lab: String = ("☠ " if pm["boss"] else "") + str(pm["label"])
			_place(used, pp, "%s %s" % [lab, _dist(ship.position.distance_to(pp))], Color("ff3b3b") if pm["boss"] else UiTheme.DANGER)
			used += 1
		if W.patrols:
			for pp in W.patrols.positions_in(sys_id):
				var dd := ship.position.distance_to(pp)
				if dd < (1500.0 if marker_mode == 0 else 600.0) and dd > 20.0 and marker_mode < 2:
					_place(used, pp, "CONCORD %s" % _dist(dd), Color("6fa8ff"))
					used += 1
		if W.jobs:
			for j: Dictionary in W.jobs.mine:
				if str(j.get("system", "")) != sys_id:
					continue
				var tp := W.jobs.target_of(j)
				if tp != Vector3.ZERO:
					_place(used, tp, "▣ %s %s" % [str(j["title"]).to_upper(), _dist(ship.position.distance_to(tp))], Color("ff9ed2"))
					used += 1
		if W.assault and W.assault.active() and W.assault.planet.system_id == sys_id:
			for m in W.assault.markers(ship.position):
				var label: String = m["label"]
				if label != "✦":
					label += " " + _dist(float(m["d"]))
				_place(used, m["pos"], label, m["color"])
				used += 1
		used = _place_sites(used, sys_id)
		used = _place_waypoint(used, sys_id)
		var ms := W.missions
		if ms and ms.active and ms.client.get("system", "") == sys_id:
			var esc: Dictionary = ms.client.get("escort", {})
			if not esc.is_empty() and esc.get("alive", false):
				_place(used, esc["pos"], "%s %s" % [esc["name"], _dist(ship.position.distance_to(esc["pos"]))], UiTheme.GREEN)
				used += 1
			elif ms.client.get("has_target", false):
				var tp: Vector3 = ms.client["target"]
				_place(used, tp, "MÅL %s" % _dist(ship.position.distance_to(tp)), UiTheme.GREEN)
				used += 1
	_hide_markers(used)


## Fund, man har scannet (vrag, ruiner, kapsler, piratlejre) inden for 4 km.
func _place_sites(used: int, sys_id: String) -> int:
	if W.sites == null:
		return used
	var ms := W.missions
	var searching: bool = ms != null and ms.active and ms.client.get("type", "") == "search"
	for s in W.sites.known_in(sys_id):
		# Missionens vrag vises af missionsmarkøren
		if s["looted"] or (s["mission"] != "" and searching):
			continue
		var d := ship.position.distance_to(s["pos"])
		if d > (4000.0 if marker_mode == 0 else 1500.0) or d < 25.0 or marker_mode == 2:
			continue
		var c := Game.col(Sites.KINDS[s["kind"]]["color"])
		_place(used, s["pos"], "%s %s" % [Sites.KINDS[s["kind"]]["label"], _dist(d)], c)
		used += 1
	return used


## Markeringen fra kortet. I et andet system peges der på den gate, der fører derhen.
func _place_waypoint(used: int, sys_id: String) -> int:
	var wp: Dictionary = W.waypoint
	if wp.is_empty():
		return used
	var target: Vector3 = wp["pos"]
	var label := "◆ %s" % str(wp["label"])
	if wp["system"] != sys_id:
		var g := W.gate_towards(sys_id, wp["system"])
		if g.is_empty():
			return used
		target = g["pos"]
		label += " (via gate)"
	elif ship.position.distance_to(target) < 60.0:
		W.waypoint = {}
		Sfx.play("markering", -4.0, 0.0)
		show_toast("Markering nået: %s" % str(wp["label"]).capitalize())
		return used
	_place(used, target, "%s %s" % [label, _dist(ship.position.distance_to(target))], UiTheme.YELLOW)
	return used + 1


func _update_lock_label(aiming: bool) -> void:
	_lock_label.visible = false
	if not aiming or ship.lock_target < 0 or W.pirates == null:
		return
	var tp := W.pirates.position_of(ship.lock_target)
	if camera.is_position_behind(tp):
		return
	var p := camera.unproject_position(tp) * float(view.stretch_shrink)
	if not Rect2(Vector2.ZERO, size).has_point(p):
		return
	_lock_label.visible = true
	var state := "LÅST" if ship.is_locked() else "LÅSER …"
	_lock_label.text = "%s · %s %s" % [state, W.pirates.display_name(ship.lock_target).to_upper(), _dist(ship.position.distance_to(tp))]
	_lock_label.add_theme_color_override("font_color", UiTheme.DANGER if ship.is_locked() else UiTheme.YELLOW)
	_lock_label.reset_size()
	var box := LockOverlay.box_size(ship.position.distance_to(tp))
	_lock_label.position = (p + Vector2(-_lock_label.size.x / 2.0, box / 2.0 + 12.0)).round()


## Tegner lock-on: hjørneklammer om målet, livsbjælke, forudsigelsespunkt og en pil,
## når målet er uden for skærmen.
class LockOverlay extends Control:
	var hud: Hud

	static func box_size(dist: float) -> float:
		return clampf(3000.0 / maxf(dist, 1.0), 26.0, 70.0)

	func _screen(world: Vector3) -> Vector2:
		return hud.camera.unproject_position(world) * float(hud.view.stretch_shrink)

	func _draw() -> void:
		var ship := hud.ship
		if ship == null or not is_instance_valid(ship) or ship.state != Ship.State.FLY or ship.dead or not ship.steering:
			return
		# Kanonsigte: hvor skuddene går (gult, når markøren er uden for kanonernes rækkevidde)
		if not hud.camera.is_position_behind(ship.aim_point):
			var ap := _screen(ship.aim_point)
			var ac := Color(UiTheme.YELLOW, 0.9) if ship.aim_clamped else Color(UiTheme.GREEN, 0.9)
			draw_arc(ap, 9.0, 0.0, TAU, 16, ac, 2.0)
			for v: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				draw_line(ap + v * 5.0, ap + v * 12.0, ac, 2.0)
		if ship.lock_target < 0 or W.pirates == null:
			return
		var tp := W.pirates.position_of(ship.lock_target)
		var locked := ship.is_locked()
		var col := UiTheme.DANGER if locked else UiTheme.YELLOW
		var center := size / 2.0
		var behind := hud.camera.is_position_behind(tp)
		var p := _screen(tp)
		if behind or not Rect2(Vector2.ZERO, size).grow(-20.0).has_point(p):
			# Pil i kanten mod målet
			var dir := (p - center) * (-1.0 if behind else 1.0)
			if dir.length() < 1.0:
				dir = Vector2.DOWN
			dir = dir.normalized()
			var tip := center + dir * minf(size.x, size.y) * 0.42
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([tip + dir * 14.0, tip - dir * 6.0 + side * 10.0, tip - dir * 6.0 - side * 10.0]), col)
			return
		# Klammer; under låsning trækker de sig sammen om målet
		var s := box_size(ship.position.distance_to(tp))
		if not locked:
			s *= 1.0 + 1.5 * (1.0 - ship.lock_t / Ship.LOCK_TIME)
		var h := s / 2.0
		var l := maxf(6.0, s * 0.3)
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner := p + c * h
			draw_line(corner, corner - Vector2(c.x * l, 0), col, 2.0)
			draw_line(corner, corner - Vector2(0, c.y * l), col, 2.0)
		# Livsbjælke over klammerne
		var hp := W.pirates.hp_fraction(ship.lock_target)
		var bar := Rect2(p + Vector2(-h, -h - 9.0), Vector2(s, 4.0))
		draw_rect(bar, Color(UiTheme.INK, 0.8))
		draw_rect(Rect2(bar.position, Vector2(s * hp, 4.0)), UiTheme.GREEN if hp > 0.4 else UiTheme.DANGER)
		var shf := W.pirates.shield_fraction(ship.lock_target)
		if shf > 0.0:
			draw_rect(Rect2(bar.position - Vector2(0, 5), Vector2(s, 3.0)), Color(UiTheme.INK, 0.8))
			draw_rect(Rect2(bar.position - Vector2(0, 5), Vector2(s * shf, 3.0)), UiTheme.CYAN)
		if not locked:
			return
		# Forudsigelsespunkt: skyd her for at ramme
		var lead := ship.lead_point()
		if hud.camera.is_position_behind(lead):
			return
		var lp := _screen(lead)
		if lp.distance_to(p) > 4.0:
			draw_dashed_line(p, lp, Color(col, 0.6), 1.0, 4.0)
		var lc := UiTheme.GREEN if ship.aim_assist_active() else col
		draw_arc(lp, 7.0, 0.0, TAU, 12, lc, 2.0)
		draw_rect(Rect2(lp - Vector2(1.5, 1.5), Vector2(3, 3)), lc)


func _update_mission() -> void:
	var ms := W.missions
	_mission.visible = ms != null and ms.active and not ms.client.is_empty() and ms.client.get("active", false)
	if not _mission.visible:
		return
	var st := ms.client
	_m_name.text = "◆ " + str(st.get("name", "")).to_upper()
	_m_obj.text = str(st.get("objective", ""))
	_m_prog.text = str(st.get("progress", ""))
	_m_prog.visible = _m_prog.text != ""
	var t := float(st.get("timer", -1.0))
	_m_timer.visible = t >= 0.0
	if _m_timer.visible:
		_m_timer.text = "TID: %d:%02d" % [int(t) / 60, int(t) % 60]
		_m_timer.add_theme_color_override("font_color", UiTheme.DANGER if t < 20.0 else UiTheme.YELLOW)
	var esc: Dictionary = st.get("escort", {})
	_m_escort_row.visible = not esc.is_empty() and esc.get("alive", false)
	if _m_escort_row.visible:
		_m_escort.max_value = float(esc["max"])
		_m_escort.value = float(esc["hp"])
		_m_escort_val.text = "%d%%" % int(100.0 * float(esc["hp"]) / float(esc["max"]))


func _place(i: int, world_pos: Vector3, text: String, color: Color) -> void:
	while _markers.size() <= i:
		var nl := UiTheme.value("", UiTheme.TEXT, 12)
		nl.add_theme_constant_override("outline_size", 4)
		nl.add_theme_color_override("font_outline_color", UiTheme.INK)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(nl)
		_markers.append(nl)
	var l := _markers[i]
	l.visible = true
	var center := size / 2.0
	var p := camera.unproject_position(world_pos) * float(view.stretch_shrink)
	var behind := camera.is_position_behind(world_pos)
	var on_screen := not behind and Rect2(Vector2.ZERO, size).has_point(p)
	l.text = ("◇ " if on_screen else "‹ ") + text
	l.add_theme_color_override("font_color", color)
	if not on_screen:
		var dir := (p - center) * (-1.0 if behind else 1.0)
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		p = center + dir.normalized() * maxf(size.x, size.y)
	l.reset_size()
	p.x = clampf(p.x, 20.0, size.x - l.size.x - 20.0)
	var top := 240.0
	if _mission.visible:
		top = _mission.position.y + _mission.size.y + 14.0   # hold markører fri af missionspanelet
	# I cockpittet dækker instrumentbrættet den nederste del af billedet
	var bottom := size.y * 0.74 if camera.cockpit.visible else size.y - 160.0
	if camera.cockpit.visible and on_screen and p.y > bottom:
		l.visible = false
		return
	p.y = clampf(p.y, top, bottom)
	l.position = p - Vector2(8, l.size.y / 2.0)
	# Skub ned, hvis markøren overlapper en anden (typisk i skærmkanten).
	for tries in 12:
		var rect := Rect2(l.position, l.size).grow(1.0)
		var clash := false
		for k in i:
			if _markers[k].visible and rect.intersects(Rect2(_markers[k].position, _markers[k].size)):
				clash = true
				break
		if not clash:
			break
		l.position.y += l.size.y + 2.0
	if camera.cockpit.visible and l.position.y > bottom:
		l.visible = false
	l.modulate.a = 1.0 if on_screen else 0.6


func _hide_markers(from: int) -> void:
	for i in range(from, _markers.size()):
		_markers[i].visible = false


static func _dist(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m >= 1000.0 else "%d m" % int(m)


func _update_perf(delta: float) -> void:
	_frame_ms.append(delta * 1000.0)
	if _frame_ms.size() > 240:
		_frame_ms.pop_front()
	_perf.visible = perf_visible
	if not perf_visible:
		return
	var worst := 0.0
	var spikes := 0
	var avg := 0.0
	for ms in _frame_ms:
		worst = maxf(worst, ms)
		avg += ms
	avg /= maxf(_frame_ms.size(), 1.0)
	for ms in _frame_ms:
		if ms > avg * 1.8:
			spikes += 1
	_perf.text = "FPS %d · %.1f ms · værst %.1f ms · hak %d · terræn %.0f ms · tegnekald %d" % [
		Engine.get_frames_per_second(), avg, worst, spikes, TerrainDetail.last_build_ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	_perf.reset_size()
	_perf.position = Vector2(roundf((size.x - _perf.size.x) / 2.0), 6)


func _update_jobs() -> void:
	var list: Array = W.jobs.mine if W.jobs else []
	_jobs.visible = not list.is_empty() and ship != null and ship.state != Ship.State.LANDED
	if _jobs.visible:
		var key := ""
		for j: Dictionary in list:
			key += "%s|%d;" % [j["title"], int(j["time_left"])]
		if key != _jobs_shown:
			_jobs_shown = key
			for c in _jobs_list.get_children():
				c.queue_free()
			_jobs_list.add_child(UiTheme.caption("Opgaver", UiTheme.PINK))
			for j: Dictionary in list:
				var t := float(j["time_left"])
				var l := UiTheme.value("▣ %s · %d:%02d" % [j["title"], int(t) / 60, int(t) % 60], UiTheme.TEXT if t > 30.0 else UiTheme.DANGER, 12)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(280, 0)
				_jobs_list.add_child(l)
		var y := 236.0
		if _mission.visible:
			y = _mission.position.y + _mission.size.y + 8.0
		_jobs.position = Vector2(16, y)
	# Hjælpetekst, når et civilt skib er tæt nok på til et opkald
	_hail_hint.visible = false
	if ship and ship.state == Ship.State.FLY and not ship.dead and W.traffic:
		var i := W.traffic.nearest_hailable(ship.position)
		if i >= 0:
			_hail_hint.visible = true
			_hail_hint.text = "%s: kald %s op" % [Game.key_name("hail"), W.traffic.name_of(i)]
			_hail_hint.reset_size()
			_hail_hint.position = Vector2(roundf((size.x - _hail_hint.size.x) / 2.0), size.y - (190.0 if camera.cockpit.visible else 56.0))


## Chefbjælke øverst på skærmen, når en piratkaptajn er tæt på: navn, skjold og skrog.
class BossBar extends Control:
	const WIDTH := 420.0
	var boss := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(WIDTH, 34)
		visible = false

	func _draw() -> void:
		if boss < 0 or W.pirates == null or not W.pirates.is_active(boss):
			return
		var font := get_theme_default_font()
		var title := "☠ " + W.pirates.display_name(boss).to_upper() + " · PIRATKAPTAJN"
		draw_string(font, Vector2(0, 11), title, HORIZONTAL_ALIGNMENT_CENTER, WIDTH, 13, Color("ff3b3b"))
		var hp := W.pirates.hp_fraction(boss)
		var sh := W.pirates.shield_fraction(boss)
		draw_rect(Rect2(0, 16, WIDTH, 10), Color(UiTheme.INK, 0.85))
		draw_rect(Rect2(0, 16, WIDTH * hp, 10), Color("ff3b3b") if hp > 0.5 else Color("ff9e3d"))
		draw_rect(Rect2(0, 16, WIDTH, 10), Color(1, 1, 1, 0.35), false, 1.0)
		if sh > 0.0:
			draw_rect(Rect2(0, 28, WIDTH * sh, 4), UiTheme.CYAN)
		draw_rect(Rect2(WIDTH * 0.5 - 1, 14, 2, 14), Color(1, 1, 1, 0.5))   # forstærkninger ved 50 %


## Våben og gadgets nederst til venstre (FTL-agtigt): én linje pr. våben med
## opladningsbjælke og én pr. gadgetplads med tast og status.
class ArmsPanel extends Control:
	const ROW := 15.0
	const BAR := 110.0
	var ship: Ship

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(300, 40)
		visible = false

	func _draw() -> void:
		if ship == null or not is_instance_valid(ship) or ship.loadout == null:
			return
		var font := get_theme_default_font()
		var ws := ship.loadout.weapon_state()
		var gs := ship.loadout.gadget_state()
		var h := 8.0 + (ws.size() + gs.size()) * ROW + (6.0 if not gs.is_empty() else 0.0)
		size = Vector2(320, h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.INK, 0.7))
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.VIOLET, 0.6), false, 1.0)
		var y := 4.0
		for w: Dictionary in ws:
			var c: Color = w["color"]
			var on: bool = w.get("on", true)
			if not on:
				c = UiTheme.MUTED.darkened(0.3)
			draw_string(font, Vector2(6, y + 11), Game.key_name("weapon_%d" % (int(w.get("slot", 0)) + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.YELLOW if on else UiTheme.MUTED)
			draw_string(font, Vector2(20, y + 11), "S" if int(w.get("group", 0)) == 1 else "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.CYAN if int(w.get("group", 0)) == 1 else UiTheme.PINK)
			var bx := 34.0
			draw_rect(Rect2(bx, y + 3, BAR, 8), Color(0, 0, 0, 0.6))
			var fill := BAR * float(w["charge"])
			var col := c if w["ready"] else c.darkened(0.45)
			if w.get("hot", false):
				col = Color("ff3b3b")
			draw_rect(Rect2(bx, y + 3, fill, 8), col)
			if w.has("spin"):
				draw_rect(Rect2(bx, y + 11, BAR * float(w["spin"]), 2), Color("fff07a"))
			var label := str(w["name"]).to_upper()
			if not on:
				label += "  · FRA"
			elif w.get("beam", false):
				label += "  · OVEROPHEDET" if w.get("hot", false) else "  · VARME %d%%" % int((1.0 - float(w["charge"])) * 100.0)
			draw_string(font, Vector2(bx + BAR + 8, y + 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE if w["ready"] and on else UiTheme.MUTED)
			y += ROW
		if not gs.is_empty():
			y += 3.0
			draw_line(Vector2(6, y - 2), Vector2(size.x - 6, y - 2), Color(UiTheme.VIOLET, 0.5), 1.0)
		for g: Dictionary in gs:
			var key := Game.key_name("gadget_%d" % int(g["key"])) if g["active"] else "–"
			var nm := str(g["name"]).to_upper()
			var col := UiTheme.MUTED
			if g["id"] != "":
				col = UiTheme.CYAN if g["on"] else Color.WHITE
			draw_string(font, Vector2(8, y + 11), "[%s]" % key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.YELLOW if g["active"] else UiTheme.MUTED)
			draw_string(font, Vector2(40, y + 11), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
			if g["active"]:
				var r := float(g["ready"])
				draw_rect(Rect2(size.x - 70, y + 4, 60, 6), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(size.x - 70, y + 4, 60 * r, 6), UiTheme.GREEN if r >= 1.0 else UiTheme.YELLOW)
			elif g["on"]:
				draw_string(font, Vector2(size.x - 52, y + 11), "AKTIV", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.CYAN)
			y += ROW
