extends Node
## Hovedscenen. Bygger pixel-renderpipelinen, verden og brugerfladen, og
## forbinder netværk, skibe og menuer.
##
## Pixel-pipeline: hele 3D-verdenen ligger i en SubViewport, der renderes i
## lav opløsning (standard ca. 400 linjer, F2 skifter) og skaleres op uden udglatning. Palette- og
## dither-shaderen ligger på SubViewportContaineren. HUD og menuer tegnes
## ovenpå i fuld opløsning.

## Grafikindstillinger. F2 skifter pixelstørrelse, F3 skifter dithering.
const PIXEL_PRESETS := [
	{"name": "Grov", "lines": 270.0},
	{"name": "Mellem", "lines": 400.0},
	{"name": "Fin", "lines": 540.0},
	{"name": "Fuld opløsning", "lines": 0.0},
]
const DITHER_PRESETS := [
	{"name": "Retro", "levels": 6.0, "dither": 0.95, "saturation": 1.3},
	{"name": "Blød", "levels": 12.0, "dither": 0.45, "saturation": 1.25},
	{"name": "Fra", "levels": 255.0, "dither": 0.0, "saturation": 1.2},
]
const SETTINGS_PATH := "user://settings.cfg"
var pause_menu: PauseMenu
var cargo_panel: CargoPanel
var ship_manager: ShipManager
var comm_panel: CommPanel
var last_saved := ""
const KEYS_VERSION := 3
var _restarting := false
var fullscreen := false

var pixel_mode := 1
var dither_mode := 1

var view: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var env: Environment
var sun_light: DirectionalLight3D
var sky: SkyDome
var universe: Universe
var players_root: Node3D
var camera: ChaseCamera
var terrain: TerrainDetail
var hud: Hud
var title: TitleScreen
var menu: StationMenu
var debrief: Debrief
var star_map: StarMap
var site_menu: SiteMenu
var base_menu: BaseMenu

## Start docket i Concord-basens hangar (tests kan slå det fra og starte i rummet).
var start_docked := true

var ships: Dictionary = {}      ## peer-id -> Ship
var local_ship: Ship
var _current_system := ""


func _ready() -> void:
	_build_view()
	_build_world()
	_build_ui()
	_load_settings()
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	_apply_dither()

	Net.started.connect(_on_net_started)
	Net.status.connect(title.set_status)
	Net.stopped.connect(_on_net_stopped)
	Game.ship_spawned.connect(_on_ship_spawned)
	Game.ship_removed.connect(_on_ship_removed)
	Game.ship_class_changed.connect(func(id: int, cls: String):
		if ships.has(id):
			(ships[id] as Ship).set_class(cls))
	Game.look_changed.connect(func(id: int, l: Dictionary):
		if ships.has(id):
			(ships[id] as Ship).set_look(l))
	Game.toast.connect(hud.show_toast)
	Game.toast.connect(func(_m: String): Sfx.play("besked", -10.0, 0.0))
	star_map.closed.connect(_on_map_closed)

	title.solo_pressed.connect(func(p: String): Net.start_solo(p))
	title.host_pressed.connect(func(p: String, port: int): Net.host(p, port))
	title.join_pressed.connect(func(p: String, addr: String, port: int): Net.join(p, addr, port))
	title.test_mission_pressed.connect(start_test_mission)
	menu.launch_requested.connect(_on_launch)
	site_menu.launch_requested.connect(_on_launch)
	base_menu.launch_requested.connect(_on_launch)
	W.missions.mission_started.connect(func(n: String):
		hud.show_toast("Mission startet: %s" % n)
		Sfx.play("mission_start", -3.0, 0.0))
	W.missions.mission_ended.connect(_on_mission_ended)
	debrief.closed.connect(_on_debrief_closed)


# ---------------------------------------------------------------- opbygning

func _build_view() -> void:
	view = SubViewportContainer.new()
	view.name = "View"
	view.stretch = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/palette_dither.gdshader")
	view.material = mat
	add_child(view)
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.audio_listener_enable_3d = true
	view.add_child(viewport)


func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	viewport.add_child(world)

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8a8fd6")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Eksponentiel tåge: tiltager jævnt med afstanden og virker ens i alle renderere.
	env.fog_enabled = false
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	sun_light = DirectionalLight3D.new()
	sun_light.light_color = Color("fff1d6")
	sun_light.light_energy = 1.05
	world.add_child(sun_light)

	sky = SkyDome.new()
	sky.name = "Sky"
	world.add_child(sky)

	universe = Universe.new()
	universe.name = "Universe"
	world.add_child(universe)
	W.universe = universe
	W.ships = ships
	Sfx.attach_world(world)

	# Systemerne, der skal kunne kalde RPC'er, har faste navne på alle maskiner.
	W.fx = _add_world(Effects.new(), "Effects")
	W.bolts = _add_world(Bolts.new(), "Bolts")
	W.pickups = _add_world(Pickups.new(), "Pickups")
	W.asteroids = _add_world(AsteroidField.new(), "Asteroids")
	W.pirates = _add_world(Pirates.new(), "Pirates")
	W.freighters = _add_world(Freighters.new(), "Freighters")
	W.sites = _add_world(Sites.new(), "Sites")
	W.weather = _add_world(Weather.new(), "Weather")
	W.missiles = _add_world(Missiles.new(), "Missiles")
	W.patrols = _add_world(Patrols.new(), "Patrols")
	W.bases = _add_world(PlayerBases.new(), "PlayerBases")
	W.bombs = _add_world(Bombs.new(), "Bombs")
	W.assault = _add_world(Assault.new(), "Assault")
	W.traffic = _add_world(Traffic.new(), "Traffic")
	W.jobs = _add_world(Jobs.new(), "Jobs")
	W.missions = _add_world(Missions.new(), "Missions")

	players_root = Node3D.new()
	players_root.name = "Players"
	world.add_child(players_root)

	camera = ChaseCamera.new()
	camera.name = "Camera"
	camera.orbit_center = universe.station("kepler_station").position
	world.add_child(camera)
	terrain = TerrainDetail.new()
	terrain.name = "TerrainDetail"
	terrain.camera = camera
	world.add_child(terrain)
	_set_system("kepler")


func _add_world(node: Node, node_name: String) -> Node:
	node.name = node_name
	world.add_child(node)
	return node


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.theme = UiTheme.build()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	hud = Hud.new()
	hud.name = "Hud"
	hud.camera = camera
	hud.view = view
	hud.universe = universe
	hud.ships = ships
	root.add_child(hud)
	menu = StationMenu.new()
	menu.name = "StationMenu"
	root.add_child(menu)
	debrief = Debrief.new()
	debrief.name = "Debrief"
	root.add_child(debrief)
	base_menu = BaseMenu.new()
	base_menu.name = "BaseMenu"
	root.add_child(base_menu)
	site_menu = SiteMenu.new()
	site_menu.name = "SiteMenu"
	root.add_child(site_menu)
	star_map = StarMap.new()
	star_map.name = "StarMap"
	root.add_child(star_map)
	title = TitleScreen.new()
	title.name = "Title"
	root.add_child(title)
	cargo_panel = CargoPanel.new()
	cargo_panel.name = "CargoPanel"
	cargo_panel.closed.connect(_on_map_closed)
	root.add_child(cargo_panel)
	ship_manager = ShipManager.new()
	ship_manager.name = "ShipManager"
	ship_manager.closed.connect(_on_map_closed)
	comm_panel = CommPanel.new()
	comm_panel.name = "CommPanel"
	comm_panel.closed.connect(_on_map_closed)
	W.traffic.hail_received.connect(func(_i, _n, _h, _t, _o):
		if local_ship and local_ship.state == Ship.State.FLY:
			local_ship.steering = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE)
	root.add_child(comm_panel)
	root.add_child(ship_manager)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.main = self
	root.add_child(pause_menu)


func _on_resize() -> void:
	var h := float(get_viewport().get_visible_rect().size.y)
	var lines: float = PIXEL_PRESETS[pixel_mode]["lines"]
	# Rund ned, så billedet aldrig får færre linjer end forudindstillingen.
	view.stretch_shrink = 1 if lines <= 0.0 else clampi(int(h / lines), 1, 8)


func _apply_dither() -> void:
	var p: Dictionary = DITHER_PRESETS[dither_mode]
	var mat := view.material as ShaderMaterial
	mat.set_shader_parameter("levels", p["levels"])
	mat.set_shader_parameter("dither_strength", p["dither"])
	mat.set_shader_parameter("saturation", p["saturation"])


func _unhandled_input(event: InputEvent) -> void:
	# Musehjul: zoom kameraet ind og ud (kortet bruger selv hjulet, når det er åbent)
	if event is InputEventMouseButton and event.pressed and not star_map.visible and not title.visible:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var zoom_in := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if camera.first_person:
				if not zoom_in:
					camera.set_first_person(false)   # rul ud: tilbage bag skibet
			elif zoom_in and camera.zoom_target <= 0.56:
				toggle_cockpit()                     # rul helt ind: ind i cockpittet
			else:
				var k := 1.0 / 1.12 if zoom_in else 1.12
				camera.zoom_target = clampf(camera.zoom_target * k, 0.55, 2.6)
			_save_settings()
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := event as InputEventKey
	if key.physical_keycode == KEY_ESCAPE and comm_panel.visible:
		comm_panel.close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("hail") and not title.visible and local_ship and local_ship.state == Ship.State.FLY and not star_map.visible:
		hail()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_ESCAPE and ship_manager.visible:
		ship_manager.close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ship_manager") and not title.visible and local_ship and not star_map.visible and not comm_panel.visible:
		toggle_ship_manager()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_ESCAPE and cargo_panel.visible:
		cargo_panel.close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cargo") and not title.visible and local_ship and not star_map.visible:
		toggle_cargo()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_F6 and not title.visible:
		save_game()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_ESCAPE:
		if not title.visible and not star_map.visible and not pause_menu.visible:
			pause_menu.open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("cockpit") and not title.visible:
		toggle_cockpit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map"):
		toggle_map()
		get_viewport().set_input_as_handled()
		return
	if key.physical_keycode == KEY_F11 or (key.physical_keycode == KEY_ENTER and key.alt_pressed):
		fullscreen = not fullscreen
		_apply_fullscreen()
		hud.show_toast("Fuldskærm: %s" % ("til" if fullscreen else "fra"))
		_save_settings()
		get_viewport().set_input_as_handled()
		return
	match key.physical_keycode:
		KEY_F2:
			pixel_mode = (pixel_mode + 1) % PIXEL_PRESETS.size()
			_on_resize()
			var lines := int(get_viewport().get_visible_rect().size.y) / view.stretch_shrink
			hud.show_toast("Pixelstørrelse: %s (%d linjer)" % [PIXEL_PRESETS[pixel_mode]["name"], lines])
			_save_settings()
		KEY_F3:
			dither_mode = (dither_mode + 1) % DITHER_PRESETS.size()
			_apply_dither()
			hud.show_toast("Dithering: %s" % DITHER_PRESETS[dither_mode]["name"])
			_save_settings()
		KEY_EQUAL, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT:
			var up := key.physical_keycode == KEY_EQUAL or key.physical_keycode == KEY_KP_ADD
			Game.mouse_sensitivity = clampf(Game.mouse_sensitivity + (0.1 if up else -0.1), 0.5, 2.0)
			hud.show_toast("Styrefølsomhed: %d %%" % roundi(Game.mouse_sensitivity * 100.0))
			_save_settings()
		KEY_F7:
			hud.marker_mode = (hud.marker_mode + 1) % 3
			hud.show_toast("Markører: %s" % Hud.MARKER_MODE_NAMES[hud.marker_mode])
			_save_settings()
		KEY_F9:
			hud.perf_visible = not hud.perf_visible
		KEY_F4:
			Sfx.set_music(not Sfx.music_on)
			hud.show_toast("Musik: %s" % ("til" if Sfx.music_on else "fra"))
			_save_settings()
		KEY_F5:
			Sfx.set_sfx(not Sfx.sfx_on)
			hud.show_toast("Lydeffekter: %s" % ("til" if Sfx.sfx_on else "fra"))
			_save_settings()


## Kald det nærmeste civile skib op (H).
func hail() -> void:
	if comm_panel.visible:
		comm_panel.close()
		return
	var i := W.traffic.nearest_hailable(local_ship.position)
	if i < 0:
		hud.show_toast("Ingen skibe at kalde op inden for %d m" % int(Traffic.HAIL_RANGE))
		return
	W.traffic.request_hail(i)


## Lastrummet (I). Under flyvning flyver skibet ligeud imens, som når kortet er åbent.
## Rumskibsmanageren (U): overblik over skibet; i en hangar kan udstyret flyttes og installeres.
func toggle_ship_manager() -> void:
	if ship_manager.visible:
		ship_manager.close()
		return
	if local_ship == null or debrief.visible:
		return
	var at := ""
	if menu.visible:
		at = menu.loc_id
	elif base_menu.visible:
		at = base_menu.plot_id
	if cargo_panel.visible:
		cargo_panel.close()
	ship_manager.open(local_ship, at)
	if local_ship.state == Ship.State.FLY:
		local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func toggle_cargo() -> void:
	if cargo_panel.visible:
		cargo_panel.close()
		return
	if local_ship == null or debrief.visible:
		return
	cargo_panel.open(local_ship)
	if local_ship.state == Ship.State.FLY:
		local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Gem spillet nu (F6 / ESC-menuen). Kun værten gemmer; i co-op gemmes alles
## fremskridt hos værten.
func save_game() -> bool:
	if local_ship == null:
		return false
	if not multiplayer.is_server():
		hud.show_toast("Værten gemmer spillet – dit fremskridt gemmes hos værten")
		return false
	Game.server_save()
	var t := Time.get_time_dict_from_system()
	last_saved = "%02d:%02d" % [t["hour"], t["minute"]]
	hud.show_toast("Spillet er gemt (%s)" % last_saved)
	Sfx.play("bekraeft", -4.0, 0.0)
	return true


## Kortet (M). Åbnes over alt andet undtagen titelskærmen; skibet flyver ligeud imens.
func toggle_map() -> void:
	if star_map.visible:
		star_map.close()
		return
	if title.visible or local_ship == null or debrief.visible:
		return
	star_map.ship = local_ship
	star_map.open()
	local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_map_closed() -> void:
	if local_ship and not cargo_panel.visible and not ship_manager.visible and not comm_panel.visible and not star_map.visible and not menu.visible and not site_menu.visible and not base_menu.visible and not debrief.visible and local_ship.state != Ship.State.LANDED:
		local_ship.steering = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	pixel_mode = clampi(int(cfg.get_value("graphics", "pixel_mode", pixel_mode)), 0, PIXEL_PRESETS.size() - 1)
	dither_mode = clampi(int(cfg.get_value("graphics", "dither_mode", dither_mode)), 0, DITHER_PRESETS.size() - 1)
	fullscreen = bool(cfg.get_value("graphics", "fullscreen", false))
	_apply_fullscreen()
	Game.mouse_sensitivity = clampf(float(cfg.get_value("controls", "sensitivity", 1.0)), 0.5, 2.0)
	camera.zoom_target = clampf(float(cfg.get_value("controls", "camera_zoom", 1.0)), 0.55, 2.6)
	camera.zoom = camera.zoom_target
	camera.first_person = bool(cfg.get_value("controls", "first_person", false))
	Sfx.set_music(bool(cfg.get_value("audio", "music", true)))
	Sfx.set_sfx(bool(cfg.get_value("audio", "sfx", true)))
	set_volume("Musik", float(cfg.get_value("audio", "music_volume", 0.8)), false)
	set_volume("Effekter", float(cfg.get_value("audio", "sfx_volume", 0.9)), false)
	Game.invert_y = bool(cfg.get_value("controls", "invert_y", false))
	Game.test_mode = bool(cfg.get_value("game", "test_mode", true))
	hud.marker_mode = int(cfg.get_value("controls", "marker_mode", 1))
	var keys = cfg.get_value("controls", "keys", {})
	# Gemte taster fra før R blev "lås nærmeste fjende" bruges ikke (version 2)
	var kv := int(cfg.get_value("controls", "keys_version", 1))
	if keys is Dictionary and not keys.is_empty() and kv >= 2:
		if kv < 3:
			# Version 3: 1–5 slår våben til/fra, gadgets er flyttet til 6–9
			for k in 4:
				keys.erase("gadget_%d" % (k + 1))
		Game.apply_key_bindings(keys)


func toggle_cockpit() -> void:
	camera.set_first_person(not camera.first_person)
	hud.show_toast("Cockpit" if camera.first_person else "Kamera bag skibet")
	_save_settings()


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "pixel_mode", pixel_mode)
	cfg.set_value("graphics", "dither_mode", dither_mode)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("controls", "sensitivity", Game.mouse_sensitivity)
	cfg.set_value("controls", "camera_zoom", camera.zoom_target)
	cfg.set_value("controls", "first_person", camera.first_person)
	cfg.set_value("audio", "music", Sfx.music_on)
	cfg.set_value("audio", "sfx", Sfx.sfx_on)
	cfg.set_value("audio", "music_volume", get_volume("Musik"))
	cfg.set_value("audio", "sfx_volume", get_volume("Effekter"))
	cfg.set_value("controls", "invert_y", Game.invert_y)
	cfg.set_value("game", "test_mode", Game.test_mode)
	cfg.set_value("controls", "marker_mode", hud.marker_mode)
	cfg.set_value("controls", "keys", Game.key_bindings())
	cfg.set_value("controls", "keys_version", KEYS_VERSION)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- ESC-menuen

func save_settings() -> void:
	_save_settings()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_fullscreen()
	_save_settings()


func set_pixel_mode(i: int) -> void:
	pixel_mode = clampi(i, 0, PIXEL_PRESETS.size() - 1)
	_on_resize()
	_save_settings()


func set_dither_mode(i: int) -> void:
	dither_mode = clampi(i, 0, DITHER_PRESETS.size() - 1)
	_apply_dither()
	_save_settings()


## Lydstyrke 0–1 for en lydbus ("Musik" eller "Effekter").
func set_volume(bus: String, x: float, save := true) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(x, 0.001)))
	if save:
		_save_settings()


func get_volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return 1.0 if i < 0 else clampf(db_to_linear(AudioServer.get_bus_volume_db(i)), 0.0, 1.0)


## Afbryd den aktive mission og start den samme igen fra begyndelsen.
func restart_mission() -> void:
	if not W.missions.active or not multiplayer.is_server() or local_ship == null:
		return
	var offer: Dictionary = (W.missions._m["offer"] as Dictionary).duplicate(true)
	_restarting = true
	W.missions._srv_abort()
	await get_tree().process_frame
	_restarting = false
	debrief.visible = false
	if local_ship.dead:
		hud.show_toast("Vent, til skibet er bjærget, og prøv igen")
		return
	if local_ship.state != Ship.State.FLY:
		_on_launch()
		for k in 3:
			await get_tree().process_frame
	local_ship.hull = 100.0
	local_ship.shield = local_ship.shield_max
	W.missions._server_start(offer)
	await get_tree().process_frame
	if offer["type"] == "assault":
		_place_before_assault(offer["name"])
	else:
		local_ship.steering = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		hud.show_toast("Missionen er genstartet")


## Slet den nuværende pilots fremskridt og start igen som ny pilot (solo).
func restart_as_new_pilot() -> void:
	var pname := Net.local_name
	Net.leave()
	_on_net_stopped("")
	Game.forget_pilot(pname)
	await get_tree().process_frame
	Net.start_solo(pname)


func to_title() -> void:
	Net.leave()
	_on_net_stopped("")


# ---------------------------------------------------------------- netværk og skibe

func _on_net_started() -> void:
	for id: int in ships.keys():
		_on_ship_removed(id)
	title.set_status("")


func _on_net_stopped(msg: String) -> void:
	for id: int in ships.keys():
		_on_ship_removed(id)
	menu.close()
	site_menu.close()
	base_menu.close()
	star_map.close()
	W.waypoint = {}
	title.visible = true
	title.set_status(msg)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_ship_spawned(id: int, info: Dictionary) -> void:
	if ships.has(id):
		return
	var ship := Ship.new()
	ship.setup(id, info, universe)
	var sys: Dictionary = Game.systems["kepler"]
	var spawn := Game.vec(sys["origin"]) + Game.vec(sys.get("spawn", [0, 0, 0]))
	ship.slot = int(info.get("index", 0)) % StationBody.PAD_COUNT
	ship.position = spawn + Vector3(int(info.get("index", 0)) * 10.0, 0, 0)
	players_root.add_child(ship)
	ships[id] = ship
	var base := universe.home_base("kepler")
	var docked := start_docked and base != null
	if docked:
		ship.dock_at(base.id, ship.slot)
	if ship.is_local():
		local_ship = ship
		W.local_ship = ship
		ship.landed.connect(_on_landed)
		ship.damaged.connect(_on_damaged)
		ship.salvaged.connect(_on_salvaged)
		camera.target = ship
		camera.snap()
		hud.ship = ship
		title.visible = false
		if docked:
			_on_landed(base.id)
			hud.show_toast("Velkommen til %s, pilot" % base.display_name)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif Net.is_online:
		hud.show_toast("%s er med i co-op" % ship.display_name)


func _on_ship_removed(id: int) -> void:
	if not ships.has(id):
		return
	var ship: Ship = ships[id]
	ships.erase(id)
	if ship == local_ship:
		local_ship = null
		W.local_ship = null
		camera.target = null
		hud.ship = null
	elif Net.is_online:
		hud.show_toast("%s forlod spillet" % ship.display_name)
	ship.queue_free()


func _on_landed(loc_id: String) -> void:
	star_map.close()
	if W.jobs and not loc_id.begins_with("site:"):
		W.jobs.request_landed(loc_id)
	local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if loc_id.begins_with("site:"):
		site_menu.open(loc_id.trim_prefix("site:"))
	elif W.bases.is_plot(loc_id):
		base_menu.open(loc_id)
	else:
		menu.open(loc_id)


func _on_damaged(hull_hit: bool) -> void:
	hud.damage_flash(hull_hit)
	camera.shake = maxf(camera.shake, 0.6 if hull_hit else 0.3)


func _on_salvaged(loc_id: String) -> void:
	star_map.close()
	local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.snap()
	var fee := int(Game.combat("salvage_fee"))
	menu.open(loc_id, "Dit skib blev skudt ned og bjærget hertil. Bjærgning: %d cr. Lasten gik tabt." % fee)


func _on_mission_ended(result: Dictionary) -> void:
	if _restarting:
		return
	star_map.close()
	Sfx.play("mission_ok" if result.get("success", false) else "mission_fejl", -3.0, 0.0)
	if local_ship:
		local_ship.steering = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	debrief.show_result(result)


func _on_debrief_closed() -> void:
	if local_ship and not menu.visible and not site_menu.visible and local_ship.state != Ship.State.LANDED:
		local_ship.steering = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif menu.visible:
		menu._refresh()


## Testgenvej fra startskærmen: spil solo og hop direkte ind i en mission. Skibet
## placeres i luften lige før fæstningens kløft og flyver ind mod den.
func start_test_mission(pilot: String, template_id: String) -> void:
	Net.start_solo(pilot)
	for k in 6:
		await get_tree().process_frame
	if local_ship == null:
		return
	var tpl := {}
	for t: Dictionary in Game.mission_data["templates"]:
		if t["id"] == template_id:
			tpl = t
	if tpl.is_empty():
		return
	if W.missions.active:
		W.missions._srv_abort()
		await get_tree().process_frame
	if local_ship.state != Ship.State.FLY:
		_on_launch()
		for k in 3:
			await get_tree().process_frame
	W.missions._server_start(W.missions._make_offer(tpl))
	await get_tree().process_frame
	_place_before_assault(tpl["name"])


## Placér skibet i luften lige før fæstningens kløft med næsen ind mod den.
func _place_before_assault(mission_name: String) -> void:
	if not W.assault.active() or local_ship == null:
		return
	var p := W.assault.planet
	var f: Dictionary = {}
	for ff in p.features:
		if ff["type"] == "canyon":
			f = ff
			break
	var a: Vector3 = f["a"]
	var b: Vector3 = f["b"]
	# 350 m før kløftens start, 120 m oppe, med næsen ind langs kløften
	var start_d := a.slerp(b, -350.0 / (p.radius * a.angle_to(b)))
	var along := (a - start_d).normalized()
	local_ship.position = p.position + start_d * (p.surface_radius(start_d) + 120.0)
	local_ship.basis = Basis.looking_at(along, start_d)
	local_ship.speed = 40.0
	local_ship.throttle = 0.6
	local_ship._ang = Vector3.ZERO
	local_ship.reset_physics_interpolation()
	local_ship.steering = true
	camera.snap()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.show_toast("%s – flyv ned i kløften!" % mission_name)


func _on_launch() -> void:
	if local_ship == null:
		return
	star_map.close()
	menu.close()
	site_menu.close()
	base_menu.close()
	local_ship.launch()
	local_ship.steering = true
	camera.snap()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.show_toast("Afgang – god tur")


# ---------------------------------------------------------------- himmel og atmosfære

func _process(_delta: float) -> void:
	var cam_pos := camera.global_position
	sky.position = cam_pos
	var sys_id := universe.system_at(cam_pos)
	if sys_id != _current_system:
		_set_system(sys_id)
	var space := Game.col(Game.systems[sys_id]["space"])
	var p := universe.nearest_planet(cam_pos)
	var atmo := 0.0
	var sky_col := space
	if p and p.system_id == sys_id:
		atmo = smoothstep(p.atmo_top, p.atmo_top * 0.3, p.altitude(cam_pos))
		sky_col = p.sky_color
	var bg := space.lerp(sky_col, atmo)
	var fog_col := bg
	# Ca. 25 % tåge ved 200 m og 80 % ved 1 km, når man er helt nede i atmosfæren.
	var density := 0.0016 * atmo
	var dark := 0.0
	# Vejr: sandstorm = tæt sandtåge, tordenvejr = mørkt med lynglimt, vulkanudbrud = røg
	var wx := W.weather.effect_at(cam_pos) if W.weather else {"type": "", "k": 0.0}
	var k: float = wx["k"]
	if k > 0.0:
		match wx["type"]:
			"sandstorm":
				fog_col = bg.lerp(Color("b8763f"), k)
				bg = fog_col
				density += 0.0055 * k
			"lightning":
				dark = 0.55 * k
				fog_col = bg.lerp(Color("2a3448"), k * 0.8)
				bg = fog_col.lerp(Color("eef3ff"), W.weather.flash * 0.7)
				density += 0.0025 * k
			"lava":
				dark = 0.35 * k
				fog_col = bg.lerp(Color("5a2a24"), k * 0.8)
				bg = fog_col
				density += 0.004 * k
	env.background_color = bg
	env.fog_light_color = fog_col
	env.fog_enabled = density > 0.00001
	env.fog_density = density
	sun_light.light_energy = 1.05 * (1.0 - dark) + (W.weather.flash * 1.5 if W.weather else 0.0)
	env.ambient_light_energy = 0.6 * (1.0 - dark * 0.5) + (W.weather.flash * 0.8 if W.weather else 0.0)
	# Uvejr skjuler stjerner og tåger helt
	sky.set_atmosphere(maxf(atmo, k), bg)


func _set_system(sys_id: String) -> void:
	_current_system = sys_id
	var sys: Dictionary = Game.systems[sys_id]
	sky.set_system(sys)
	sun_light.basis = Basis.looking_at(-sky.sun_dir, Vector3.UP)
	sun_light.light_color = Game.col(sys["sun"]).lerp(Color.WHITE, 0.6)


func _exit_tree() -> void:
	# Tøm de delte material-/teksturlagre, så intet hænger ved, når spillet lukkes.
	ModelKit._tex.clear()
	ModelKit._mats.clear()
