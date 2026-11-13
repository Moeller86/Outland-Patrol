extends Node
## Lyd og musik. Alle lyde ligger som WAV-filer i sounds/ og er lavet af
## tools/make_sounds.py (syntetiseret retro-lyd, ingen samples).
##
##   Sfx.play("laser")                 – lyd uden retning (cockpit, brugerflade)
##   Sfx.play_at("eksplosion", pos)    – 3D-lyd i verden (aftager med afstanden)
##   Sfx.set_engine(niveau, pitch)     – motorbrummet for eget skib
##   Sfx.set_combat(true/false)        – glider mellem rum- og kampmusik
##
## To lydbusser, "Musik" og "Effekter", som kan slås fra hver for sig (F4/F5).

const SOUNDS := ["laser", "laser_tung", "laser_pirat", "taarn", "traef", "skjold", "skrog",
	"eksplosion", "eksplosion_stor", "sten", "opsamling", "laaser", "laast", "lock_tabt",
	"klik", "bekraeft", "besked", "kort", "markering", "alarm", "dock", "afgang", "lane", "hop",
	"mission_start", "mission_ok", "mission_fejl", "rang", "scan", "fund", "torden", "knitren", "lava",
	"ion", "flak", "straale", "kaede", "krystal", "kappe", "emp", "drone", "batteri"]
const POOL_2D := 10
const POOL_3D := 24
const MUSIC_DB := -9.0
const MIN_GAP := 0.035          ## Samme lyd højst så ofte (undgår støjmure)

var music_on := true
var sfx_on := true

var _streams: Dictionary = {}
var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0
var _last_played: Dictionary = {}
var _root3d: Node3D
var _engine: AudioStreamPlayer
var _music_space: AudioStreamPlayer
var _music_combat: AudioStreamPlayer
var _combat := 0.0
var _combat_target := 0.0
var _engine_level := 0.0
var _engine_target := 0.0
var _engine_pitch := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for s: String in SOUNDS:
		var path := "res://sounds/%s.wav" % s
		if ResourceLoader.exists(path):
			_streams[s] = load(path)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = "Effekter"
		add_child(p)
		_players_2d.append(p)
	_engine = AudioStreamPlayer.new()
	_engine.bus = "Effekter"
	_engine.stream = _looped("motor")
	_engine.volume_db = -80.0
	add_child(_engine)
	_music_space = _music_player("musik_rum")
	_music_combat = _music_player("musik_kamp")
	if _music_space.stream:
		_music_space.play()
	if _music_combat.stream:
		_music_combat.play()
	_music_combat.volume_db = -80.0
	get_tree().node_added.connect(_on_node_added)


func _setup_buses() -> void:
	for bus_name: String in ["Musik", "Effekter"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")


func _looped(sound: String) -> AudioStream:
	var path := "res://sounds/%s.wav" % sound
	if not ResourceLoader.exists(path):
		return null
	var st := load(path) as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	return st


func _music_player(sound: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Musik"
	p.stream = _looped(sound)
	p.volume_db = MUSIC_DB
	add_child(p)
	return p


## Verdensknuden, som 3D-lyde skal ligge i (samme 3D-verden som kameraet).
func attach_world(root: Node3D) -> void:
	for p in _players_3d:
		if is_instance_valid(p):
			p.queue_free()
	_players_3d.clear()
	_root3d = root
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "Effekter"
		p.unit_size = 45.0
		p.max_distance = 1400.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.panning_strength = 0.8
		root.add_child(p)
		_players_3d.append(p)


func _allowed(sound: String) -> bool:
	if not sfx_on or not _streams.has(sound):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -1.0)) < MIN_GAP:
		return false
	_last_played[sound] = now
	return true


func play(sound: String, volume_db := 0.0, pitch_var := 0.04) -> void:
	if not _allowed(sound):
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.06) -> void:
	if _players_3d.is_empty():
		play(sound, volume_db - 6.0, pitch_var)
		return
	if not _allowed(sound):
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = _streams[sound]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


## Motorbrum for eget skib: level 0..1 (0 = slukket), pitch omkring 1.
## Vejrlyde, der looper (vind, regn, varme): level 0..1, glides blødt.
var _ambient: Dictionary = {}        ## navn -> {player, level, target}


func set_ambient(sound: String, level: float) -> void:
	if not _ambient.has(sound):
		if level <= 0.0:
			return
		var p := AudioStreamPlayer.new()
		p.bus = "Effekter"
		p.stream = _looped(sound)
		p.volume_db = -80.0
		add_child(p)
		_ambient[sound] = {"player": p, "level": 0.0, "target": 0.0}
	_ambient[sound]["target"] = clampf(level, 0.0, 1.0)


func set_engine(level: float, pitch: float) -> void:
	_engine_target = level
	_engine_pitch = pitch


func set_combat(on: bool) -> void:
	_combat_target = 1.0 if on else 0.0


func set_music(on: bool) -> void:
	music_on = on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Musik"), not on)


func set_sfx(on: bool) -> void:
	sfx_on = on
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Effekter"), not on)


func _process(delta: float) -> void:
	# Motor
	for sound: String in _ambient:
		var a: Dictionary = _ambient[sound]
		var p: AudioStreamPlayer = a["player"]
		a["level"] = move_toward(a["level"], a["target"], delta * 0.6)
		if a["level"] > 0.01 and p.stream:
			if not p.playing:
				p.play()
			p.volume_db = linear_to_db(a["level"]) - 4.0
		elif p.playing:
			p.stop()
	_engine_level = move_toward(_engine_level, _engine_target, delta * 2.0)
	if _engine_level > 0.01 and _engine.stream:
		if not _engine.playing:
			_engine.play()
		_engine.volume_db = linear_to_db(_engine_level) - 10.0
		_engine.pitch_scale = lerpf(_engine.pitch_scale, clampf(_engine_pitch, 0.4, 3.0), minf(1.0, delta * 4.0))
	elif _engine.playing:
		_engine.stop()
	# Musik: krydsfade mellem rum og kamp (kampen kommer hurtigt, går langsomt)
	_combat = move_toward(_combat, _combat_target, delta * (0.8 if _combat_target > _combat else 0.15))
	_music_space.volume_db = MUSIC_DB + linear_to_db(maxf(0.0001, 1.0 - _combat))
	_music_combat.volume_db = MUSIC_DB + 1.0 + linear_to_db(maxf(0.0001, _combat))


# Klik-lyd på alle knapper i brugerfladen.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		var b := node as BaseButton
		if not b.pressed.is_connected(_on_button):
			b.pressed.connect(_on_button)


func _on_button() -> void:
	play("klik", -2.0, 0.0)


func _exit_tree() -> void:
	# Stop alt og slip lydene, så intet hænger ved, når spillet lukkes.
	for p: Node in get_children():
		if p is AudioStreamPlayer:
			(p as AudioStreamPlayer).stop()
			(p as AudioStreamPlayer).stream = null
	for p in _players_3d:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()
