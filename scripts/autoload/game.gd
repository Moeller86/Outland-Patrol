extends Node
## Global spiltilstand: universdata, markeder og spillernes tegnebøger.
##
## Økonomien er host-autoritativ: kun serveren ændrer priser, kredit og last.
## Klienter sender anmodninger med rpc_id(1, ...) og modtager resultatet tilbage.
## I solo-spil er man selv server (OfflineMultiplayerPeer), så koden er den samme.

signal ship_spawned(id: int, info: Dictionary)
signal ship_removed(id: int)
signal wallet_changed
signal market_changed(loc_id: String)
signal toast(msg: String)
signal player_joined(id: int)        ## Kun på serveren
signal repaired(hull: float)
signal world_changed
signal ship_class_changed(id: int, ship_class: String)
signal look_changed(id: int, look: Dictionary)

const UNIVERSE_PATH := "res://data/universe.json"
const MISSIONS_PATH := "res://data/missions.json"
const BASE_PATH := "res://data/base.json"
const START_CREDITS := 100
const CARGO_MAX := 12
const PLAYER_COLORS := ["ff4f8b", "2ec4d6", "ffd23f", "6bdc4f"]

var universe: Dictionary = {}
var mission_data: Dictionary = {}
var base_data: Dictionary = {}
var ship_data: Dictionary = {}
var bases_data: Dictionary = {}
var mouse_sensitivity := 1.0     ## Styrefølsomhed (+/- i spillet), gemmes i settings.cfg
## Gruppens fælles fremskridt (gemmes hos værten, spejles til alle).
var world: Dictionary = {"missions_completed": 0}
## Gemmefil hos værten. Tests kan pege den et andet sted hen.
var save_path := "user://outland_patrol_save.json"
## Kun på serveren: gemte piloter efter navn -> tegnebog
var saved_pilots: Dictionary = {}
var _save_dirty := false
var _save_t := 0.0
var goods: Dictionary = {}
var systems: Dictionary = {}
## id -> lokationsdata (planeter og stationer), med ekstra felter: kind, system, world_pos
var locations: Dictionary = {}
## lokation -> vare -> {mode, base, price}. mode "sell" = stedet sælger, "buy" = stedet køber.
var markets: Dictionary = {}
## Kun på serveren: peer-id -> {name, color, credits, cargo, cargo_max, upgrades}
var players: Dictionary = {}
## Offentlig info om alle spillere (spejlet på alle maskiner): id -> {name, color}
var roster: Dictionary = {}
## Den lokale spillers tegnebog, spejlet fra serveren.
const START_MISSILES := 4
var wallet: Dictionary = {"credits": START_CREDITS, "cargo": {}, "cargo_max": CARGO_MAX, "upgrades": {}, "kills": 0, "xp": 0, "missiles": START_MISSILES}

var _drift_t := 0.0


func _ready() -> void:
	_setup_input()
	_load_universe()


## Navnet på handlingens første tast, til hjælpetekster ("R", "Shift" …).
func key_name(action: String) -> String:
	var k := key_of(action)
	return "–" if k == 0 else OS.get_keycode_string(k)


## Første tast for en handling (0 hvis ingen).
func key_of(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return (ev as InputEventKey).physical_keycode
	return 0


## Sæt handlingens primære tast. Andre handlinger, der brugte tasten, mister den.
## Returnerer navnet på den handling, der mistede tasten (eller "").
func rebind(action: String, key: int) -> String:
	var lost := ""
	for a: String in DEFAULT_KEYS:
		if a == action:
			continue
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == key:
				InputMap.action_erase_event(a, ev)
				lost = a
	var keep: Array[InputEvent] = []
	var first := true
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			if first:
				first = false
				continue      # den gamle primære tast erstattes
			keep.append(ev)
		else:
			keep.append(ev)
	InputMap.action_erase_events(action)
	var nk := InputEventKey.new()
	nk.physical_keycode = key as Key
	InputMap.action_add_event(action, nk)
	for ev in keep:
		if not (ev is InputEventKey and (ev as InputEventKey).physical_keycode == key):
			InputMap.action_add_event(action, ev)
	return lost


func reset_keys() -> void:
	for a: String in DEFAULT_KEYS:
		InputMap.action_erase_events(a)
	_setup_input()


## Taster til settings.cfg: handling -> liste af taster.
func key_bindings() -> Dictionary:
	var out := {}
	for a: String in DEFAULT_KEYS:
		var keys: Array = []
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey:
				keys.append(int((ev as InputEventKey).physical_keycode))
		out[a] = keys
	return out


func apply_key_bindings(b: Dictionary) -> void:
	for a: String in b:
		if not DEFAULT_KEYS.has(a) or not (b[a] is Array):
			continue
		var mouse: Array[InputEvent] = []
		for ev in InputMap.action_get_events(a):
			if not ev is InputEventKey:
				mouse.append(ev)
		InputMap.action_erase_events(a)
		for k in b[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k) as Key
			InputMap.action_add_event(a, ev)
		for ev in mouse:
			InputMap.action_add_event(a, ev)


func forget_pilot(pname: String) -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and data.has("pilots"):
		(data["pilots"] as Dictionary).erase(pname)
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(data, "\t"))
			f.close()


# ---------------------------------------------------------------- data

## Standardtaster. Den første tast i hver liste kan ændres i ESC-menuen.
const DEFAULT_KEYS := {
	"throttle_up": [KEY_W, KEY_UP], "throttle_down": [KEY_S, KEY_DOWN],
	"strafe_left": [KEY_A], "strafe_right": [KEY_D],
	"roll_left": [KEY_Q], "roll_right": [KEY_E],
	"boost": [KEY_SHIFT], "fire": [KEY_SPACE], "target_nearest": [KEY_R], "lock": [KEY_T], "missile": [KEY_G], "flare": [KEY_F],
	"bomb": [KEY_B], "cruise": [KEY_X], "scan": [KEY_C], "land": [KEY_L], "launch": [KEY_ENTER, KEY_KP_ENTER],
	"map": [KEY_M], "cockpit": [KEY_V], "cargo": [KEY_I], "hail": [KEY_H], "tractor": [KEY_Z],
	"fire_2": [KEY_CTRL], "ship_manager": [KEY_U],
	"weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3], "weapon_4": [KEY_4], "weapon_5": [KEY_5],
	"gadget_1": [KEY_6], "gadget_2": [KEY_7], "gadget_3": [KEY_8], "gadget_4": [KEY_9],
}
## Navne på handlingerne i tastmenuen (i den viste rækkefølge).
const ACTION_NAMES := [
	["throttle_up", "Mere fart"], ["throttle_down", "Mindre fart / stop cruise"],
	["strafe_left", "Glid til venstre"], ["strafe_right", "Glid til højre"],
	["roll_left", "Rul til venstre"], ["roll_right", "Rul til højre"],
	["boost", "Efterbrænder"], ["fire", "Skyd – primære våben (+ venstreklik)"], ["fire_2", "Skyd – sekundære våben (+ højreklik)"], ["target_nearest", "Lås nærmeste fjende"], ["lock", "Næste mål"],
	["missile", "Missil"], ["flare", "Flares"], ["bomb", "Bombe"], ["cruise", "Cruise-drev"],
	["scan", "Scanner"], ["land", "Land / dok"], ["launch", "Afgang"], ["map", "Kort"], ["cockpit", "Cockpit / kamera"], ["cargo", "Lastrum (smid last ud)"], ["ship_manager", "Rumskibsmanager"], ["hail", "Kald skib op"], ["tractor", "Traktorstråle (hold)"],
	["weapon_1", "Våben 1 til/fra"], ["weapon_2", "Våben 2 til/fra"], ["weapon_3", "Våben 3 til/fra"],
	["weapon_4", "Våben 4 til/fra"], ["weapon_5", "Våben 5 til/fra"],
	["gadget_1", "Gadget 1 (aktiv)"], ["gadget_2", "Gadget 2 (aktiv)"], ["gadget_3", "Gadget 3 (aktiv)"], ["gadget_4", "Gadget 4 (aktiv)"],
]
var invert_y := false
## Testtilstand (indtil spillet er færdigt): alle skibe kan vælges fra start, og
## ESC-menuen har en side med testværktøjer (opgraderinger, missiler, bomber …).
## Slås til/fra under ESC → Indstillinger og gemmes i settings.cfg.
var test_mode := true
## Udstyr (data/equipment.json) og det monterede udstyr for den lokale pilot: skib -> {plads: id}
var equipment: Dictionary = {}
var fit: Dictionary = {}
signal fit_changed


func _setup_input() -> void:
	for action: String in DEFAULT_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in DEFAULT_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", click)
	var mid := InputEventMouseButton.new()
	mid.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("missile", mid)
	var side := InputEventMouseButton.new()
	side.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("fire_2", side)
	# Højre musetast: sekundære våben (rul med Q/E, lås mål med R/T)
	var rclick := InputEventMouseButton.new()
	rclick.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("fire_2", rclick)
	var mclick := InputEventMouseButton.new()
	mclick.button_index = MOUSE_BUTTON_MIDDLE
	InputMap.action_add_event("missile", mclick)


func _load_universe() -> void:
	var text := FileAccess.get_file_as_string(UNIVERSE_PATH)
	universe = JSON.parse_string(text)
	goods = universe["goods"]
	systems = universe["systems"]
	bases_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/bases.json"))
	# Byggegrunde: på planeter som små landingssteder, i rummet som tomme platforme.
	for plot: Dictionary in bases_data["plots"]:
		if plot["kind"] == "ground":
			for sys_id: String in systems:
				for p: Dictionary in systems[sys_id].get("planets", []):
					if p["id"] == plot["planet"]:
						var outs: Array = p.get("outposts", [])
						outs.append({"id": plot["id"], "name": plot["name"], "kind": "plot", "dist": plot["dist"],
							"bearing": plot["bearing"], "pad_h": 12, "title": str(plot["name"]).to_upper(),
							"sub": "Byggegrund", "market": {}, "upgrades": [], "rumors": []})
						p["outposts"] = outs
		else:
			var sts: Array = systems[plot["system"]].get("stations", [])
			sts.append({"id": plot["id"], "name": plot["name"], "pos": plot["pos"], "plot": true,
				"title": str(plot["name"]).to_upper(), "sub": "Byggegrund i rummet", "market": {}, "upgrades": []})
			systems[plot["system"]]["stations"] = sts
	for sys_id: String in systems:
		var sys: Dictionary = systems[sys_id]
		var origin := vec(sys["origin"])
		for p: Dictionary in sys.get("planets", []):
			p["kind"] = "planet"
			p["system"] = sys_id
			p["world_pos"] = origin + vec(p["pos"])
			locations[p["id"]] = p
			# Mindre landingssteder på planeten (mine, landbrug, forskning ...)
			for o: Dictionary in p.get("outposts", []):
				var loc := o.duplicate(true)
				loc["style"] = o["kind"]
				loc["kind"] = "outpost"
				loc["system"] = sys_id
				loc["planet"] = p["id"]
				loc["world_pos"] = p["world_pos"]
				for key: String in ["sky", "cloud", "biome", "decor", "flora", "buildings", "atmo"]:
					loc[key] = p[key]
				if o["kind"] == "military":
					loc["upgrades"] = (loc["upgrades"] as Array) + ["missiles"]
				locations[o["id"]] = loc
		for s: Dictionary in sys.get("stations", []):
			s["kind"] = "station"
			s["system"] = sys_id
			s["world_pos"] = origin + vec(s["pos"])
			locations[s["id"]] = s
	reset_markets()
	mission_data = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_PATH))
	base_data = JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	ship_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/ships.json"))
	equipment = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))


func reset_markets() -> void:
	markets.clear()
	for id: String in locations:
		var m := {}
		var src: Dictionary = locations[id].get("market", {})
		for g: String in src:
			var e: Dictionary = src[g]
			m[g] = {"mode": e["mode"], "base": float(e["base"]), "price": float(e["base"])}
		markets[id] = m


func reset_session() -> void:
	players.clear()
	roster.clear()
	world = {"missions_completed": 0}
	reset_markets()
	wallet = {"credits": START_CREDITS, "cargo": {}, "cargo_max": CARGO_MAX, "upgrades": {}, "kills": 0, "xp": 0, "missiles": START_MISSILES}


static func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


static func col(hex: String) -> Color:
	return Color.html(hex)


static func cargo_total(cargo: Dictionary) -> int:
	var n := 0
	for k: String in cargo:
		n += int(cargo[k])
	return n


func good_name(id: String) -> String:
	return goods[id]["name"]


func combat(key: String) -> float:
	return float(universe["combat"][key])


## Pris for næste niveau af en opgradering (dyrere for hvert niveau, hvis "price_step" er sat).
func upgrade_price(upgrade_id: String, level: int) -> int:
	var up: Dictionary = universe["upgrades"][upgrade_id]
	return int(up.get("price", 0)) + int(up.get("price_step", 0)) * level


## Flyveegenskaber for en skibsklasse inkl. den lokale spillers opgraderinger.
func handling(ship_class: String = "") -> Dictionary:
	if ship_class == "":
		ship_class = ship_data["default"]
	var h: Dictionary = (ship_data["classes"][ship_class] as Dictionary).duplicate()
	var lvl := upgrade_level("thrusters")
	if lvl > 0:
		var up: Dictionary = universe["upgrades"]["thrusters"]
		h["turn"] = float(h["turn"]) * (1.0 + float(up["turn_bonus"]) * lvl)
		h["roll"] = float(h["roll"]) * (1.0 + float(up["turn_bonus"]) * lvl)
		h["agility"] = float(h["agility"]) * (1.0 + float(up["agility_bonus"]) * lvl)
		h["accel"] = float(h["accel"]) * (1.0 + float(up["accel_bonus"]) * lvl)
		h["max_speed"] = float(h["max_speed"]) * (1.0 + float(up["speed_bonus"]) * lvl)
		h["boost"] = float(h["boost"]) * (1.0 + float(up["speed_bonus"]) * lvl)
	# Monteret udstyr: våben (hver sin kanon og genopladning), skjold, motor og gadgets
	var f := fit_for(ship_class)
	var parts: Array[String] = []
	var wslot: Array[int] = []
	for k in (f["vaaben"] as Array).size():
		var w: String = f["vaaben"][k]
		if w != "":
			parts.append(w)
			wslot.append(k)
	parts.append(f["skjold"])
	parts.append(f["motor"])
	for g: String in f["gadget"]:
		if g != "":
			parts.append(g)
	var weapons: Array = []
	var gadgets: Array = []
	for item_id in parts:
		var it := part(item_id)
		if it.is_empty():
			continue
		for k: String in ["turn", "roll"]:
			h[k] = float(h[k]) * float(it.get("turn_mult", 1.0))
		h["agility"] = float(h["agility"]) * float(it.get("agility_mult", 1.0))
		h["max_speed"] = float(h["max_speed"]) * float(it.get("speed_mult", 1.0)) if it["slot"] != "vaaben" else float(h["max_speed"])
		h["boost"] = float(h["boost"]) * (float(it.get("speed_mult", 1.0)) * float(it.get("boost_mult", 1.0)) if it["slot"] != "vaaben" else 1.0)
		h["shield"] = float(h["shield"]) * float(it.get("shield_mult", 1.0))
		h["regen_mult"] = float(h.get("regen_mult", 1.0)) * float(it.get("regen_mult", 1.0))
		h["armor"] = float(h.get("armor", 1.0)) * float(it.get("armor_mult", 1.0))
		h["scan_mult"] = float(h.get("scan_mult", 1.0)) * float(it.get("scan_mult", 1.0))
		h["scan_range"] = float(h.get("scan_range", 1.0)) * float(it.get("scan_range", 1.0))
		h["reload_mult"] = float(h.get("reload_mult", 1.0)) * float(it.get("reload_mult", 1.0))
		if it.has("layers"):
			h["layers"] = int(it["layers"])
		match str(it["slot"]):
			"vaaben":
				var wd := it.duplicate()
				wd["id"] = item_id
				var k := wslot[weapons.size()]
				wd["slot"] = k
				wd["group"] = int((f["grupper"] as Array)[k])
				weapons.append(wd)
			"gadget":
				gadgets.append(part_base(item_id))
	h["weapons"] = weapons
	h["gadgets"] = gadgets
	h["gadget_slots"] = f["gadget"]
	h["weapon"] = weapons[0] if not weapons.is_empty() else {}
	if "traktor" in gadgets:
		h["special"] = "traktor"
	return h


# ---------------------------------------------------------------- dele og Mk-niveauer

## Hver del findes i Mk I–III. En dels id er "<grunddel>" (Mk I) eller "<grunddel>@<mk>",
## fx "puls@2" = Pulslaser Mk II. Højere Mk er stærkere, dyrere og kræver højere rang.
const MK_MAX := 3
const MK_NAMES := ["", "Mk I", "Mk II", "Mk III"]
const MK_PRICE := [0.0, 1.0, 2.2, 4.0]
const MK_RANK := [0, 0, 1, 3]          ## rang-indeks: Mk II kræver Pilot, Mk III Kaptajn
const MK_FREE_BASE := 400              ## prisgrundlag for Mk II/III af standarddelene
var _part_cache: Dictionary = {}


static func part_base(item_id: String) -> String:
	return item_id.get_slice("@", 0)


static func part_mk(item_id: String) -> int:
	return clampi(int(item_id.get_slice("@", 1)), 1, MK_MAX) if "@" in item_id else 1


static func part_id(base: String, mk: int) -> String:
	return base if mk <= 1 else "%s@%d" % [base, mk]


## En del med Mk-niveauet regnet ind: navn ("Pulslaser Mk II"), pris og værdier.
## Tom ordbog, hvis delen ikke findes.
func part(item_id: String) -> Dictionary:
	if item_id == "":
		return {}
	if _part_cache.has(item_id):
		return _part_cache[item_id]
	var base := part_base(item_id)
	var src: Dictionary = equipment.get("items", {}).get(base, {})
	if src.is_empty():
		return {}
	var mk := part_mk(item_id)
	var it := src.duplicate(true)
	_apply_mk(it, mk)
	it["base"] = base
	it["mk"] = mk
	it["base_name"] = src["name"]
	it["name"] = "%s %s" % [src["name"], MK_NAMES[mk]]
	var bp := int(src.get("price", 0))
	if bp == 0 and mk > 1:
		bp = MK_FREE_BASE
	it["price"] = int(round(bp * MK_PRICE[mk] / 50.0) * 50) if mk > 1 else bp
	_part_cache[item_id] = it
	return it


static func _apply_mk(it: Dictionary, mk: int) -> void:
	var f := float(mk - 1)
	if f <= 0.0:
		it["power"] = 1.0
		return
	match str(it["slot"]):
		"vaaben":
			for k: String in ["dmg_mult", "dps"]:
				if it.has(k):
					it[k] = float(it[k]) * (1.0 + 0.18 * f)
			if it.has("cd_mult"):
				it["cd_mult"] = float(it["cd_mult"]) * (1.0 - 0.05 * f)
			if it.has("heat_time"):
				it["heat_time"] = float(it["heat_time"]) * (1.0 + 0.15 * f)
			if it.has("beam_range"):
				it["beam_range"] = float(it["beam_range"]) + 20.0 * f
		"skjold":
			it["shield_mult"] = float(it.get("shield_mult", 1.0)) * (1.0 + 0.15 * f)
			it["regen_mult"] = float(it.get("regen_mult", 1.0)) * (1.0 + 0.1 * f)
			if it.has("layers"):
				it["layers"] = int(it["layers"]) + int(f / 2.0)
		"motor":
			it["speed_mult"] = float(it.get("speed_mult", 1.0)) * (1.0 + 0.04 * f)
			it["turn_mult"] = float(it.get("turn_mult", 1.0)) * (1.0 + 0.04 * f)
			it["boost_mult"] = float(it.get("boost_mult", 1.0)) * (1.0 + 0.04 * f)
		"gadget":
			if it.has("cooldown"):
				it["cooldown"] = float(it["cooldown"]) * pow(0.85, f)
			if it.has("duration"):
				it["duration"] = float(it["duration"]) + f
			if it.has("radius"):
				it["radius"] = float(it["radius"]) + 25.0 * f
			if it.has("reload_mult"):
				it["reload_mult"] = 1.0 - (1.0 - float(it["reload_mult"])) * (1.0 + 0.33 * f)
			if it.has("armor_mult"):
				it["armor_mult"] = 1.0 - (1.0 - float(it["armor_mult"])) * (1.0 + 0.25 * f)
			if it.has("scan_range"):
				it["scan_range"] = 1.0 + (float(it["scan_range"]) - 1.0) * (1.0 + 0.3 * f)
			if it.has("scan_mult"):
				it["scan_mult"] = 1.0 - (1.0 - float(it["scan_mult"])) * (1.0 + 0.2 * f)
	it["power"] = 1.0 + 0.3 * f


## Må den lokale pilot købe dette Mk-niveau? (rang)
func mk_allowed(mk: int, xp := -1) -> bool:
	if xp < 0:
		xp = int(wallet.get("xp", 0))
	return rank_index(xp) >= MK_RANK[clampi(mk, 0, MK_MAX)]


## Gadgettens styrke (1.0 for Mk I, 1.3 Mk II, 1.6 Mk III) på det lokale skib.
func gadget_power(gadget_base: String) -> float:
	for g: String in fit_for(local_class())["gadget"]:
		if part_base(g) == gadget_base:
			return float(part(g).get("power", 1.0))
	return 1.0


## Antal pladser af en slags på en skibsklasse (våben og gadgets; skjold og motor: 1).
func slot_count(cls: String, slot: String) -> int:
	if not (slot in equipment.get("multi", [])):
		return 1
	var c: Dictionary = ship_data["classes"].get(cls, {})
	return int((c.get("slots", {}) as Dictionary).get(slot, 2 if slot == "vaaben" else 1))


## Monteret udstyr på et skib, normaliseret: {vaaben: [..], skjold: id, motor: id, gadget: [..]}.
## Tomme våbenpladser fyldes med standardlaseren, indtil spilleren selv tømmer dem ("").
## Gamle gemte skibe (én våbenplads + "special") omsættes automatisk.
func normalize_fit(cls: String, raw: Dictionary) -> Dictionary:
	var def: Dictionary = equipment.get("default", {})
	var out := {}
	for slot: String in equipment.get("slots", {}):
		var n := slot_count(cls, slot)
		var v = raw.get(slot, null)
		if slot == "gadget" and v == null and raw.has("special"):
			v = [raw["special"]]
		if slot in equipment.get("multi", []):
			var arr: Array = []
			if v is Array:
				arr = (v as Array).duplicate()
			elif v is String:
				arr = [v]
			while arr.size() < n:
				arr.append(str(def.get(slot, "")))
			arr.resize(n)
			for k in n:
				arr[k] = str(arr[k]) if arr[k] != null else ""
			out[slot] = arr
		else:
			out[slot] = str(v) if v is String and v != "" else str(def.get(slot, ""))
	# Våbengrupper: 0 = primær (venstre klik / mellemrum), 1 = sekundær (Ctrl / sideknap)
	var n := slot_count(cls, "vaaben")
	var groups: Array = []
	var raw_g = raw.get("grupper", [])
	for k in n:
		groups.append(clampi(int(raw_g[k]), 0, 1) if raw_g is Array and k < (raw_g as Array).size() else 0)
	out["grupper"] = groups
	return out


## Det monterede udstyr på et skib (lokal pilot).
func fit_for(cls: String) -> Dictionary:
	return normalize_fit(cls, fit.get(cls, {}))


## Har den lokale pilots aktuelle skib denne gadget monteret?
func has_gadget(gadget_id: String, cls := "") -> bool:
	for g: String in fit_for(cls if cls != "" else local_class())["gadget"]:
		if part_base(g) == gadget_id:
			return true
	return false


## Server: har en spillers aktuelle skib en bestemt gadget?
func server_has_gadget(id: int, gadget_id: String) -> bool:
	if not players.has(id):
		return false
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	for g: String in normalize_fit(cls, (p.get("fit", {}) as Dictionary).get(cls, {}))["gadget"]:
		if part_base(g) == gadget_id:
			return true
	return false


## Server: styrken af en spillers gadget (1.0 hvis den ikke er monteret).
func server_gadget_power(id: int, gadget_id: String) -> float:
	if not players.has(id):
		return 1.0
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	for g: String in normalize_fit(cls, (p.get("fit", {}) as Dictionary).get(cls, {}))["gadget"]:
		if part_base(g) == gadget_id:
			return float(part(g).get("power", 1.0))
	return 1.0


## Kan man købe udstyr her? (stationer, Concord-basen og dreadnoughten)
func has_outfitter(loc_id: String) -> bool:
	var loc: Dictionary = locations.get(loc_id, {})
	return loc.get("kind", "") == "station" and not loc.get("plot", false)


## Lageret: afmonterede og købte dele, der ikke sidder på et skib: id -> antal.
var parts: Dictionary = {}


## Montér en del på det skib, man flyver. Ligger delen på lageret, bruges den derfra;
## ellers købes den. Den gamle del lægges på lageret. `idx` = plads (-1: første ledige).
func request_equip(loc_id: String, item_id: String, idx := -1) -> void:
	_srv_equip.rpc_id(1, loc_id, item_id, idx)


## Tag en del af (den lægges på lageret). Skjold og motor erstattes af standarddelen.
func request_unequip(loc_id: String, slot: String, idx := 0) -> void:
	_srv_unequip.rpc_id(1, loc_id, slot, idx)


## Sæt et våben i primær (0) eller sekundær (1) gruppe. Kan gøres overalt.
func request_weapon_group(idx: int, group: int) -> void:
	_srv_weapon_group.rpc_id(1, idx, group)


@rpc("any_peer", "call_local", "reliable")
func _srv_weapon_group(idx: int, group: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	var all_fit: Dictionary = p.get("fit", {})
	var f := normalize_fit(cls, all_fit.get(cls, {}))
	var g: Array = f["grupper"]
	if idx < 0 or idx >= g.size():
		return
	g[idx] = clampi(group, 0, 1)
	all_fit[cls] = f
	p["fit"] = all_fit
	_save_dirty = true
	_send_fit(id)


## Sælg en del fra lageret for halv pris.
func request_sell_part(loc_id: String, item_id: String) -> void:
	_srv_sell_part.rpc_id(1, loc_id, item_id)


## Må spilleren ændre udstyr her? I hangarer (stationer og egne baser med hangar).
func _equip_ok(id: int, loc_id: String) -> bool:
	return players.has(id) and (can_refit(loc_id) or test_mode)


## Kan man flytte og installere udstyr her? (stationer med udstyrsforhandler og egne
## baser med hangar). Nye dele kan kun købes hos en forhandler.
func can_refit(loc_id: String) -> bool:
	return has_outfitter(loc_id) or can_switch_ships(loc_id)


## Byt om på to pladser af samme slags (fx våben 1 og våben 2).
func request_move(loc_id: String, slot: String, a: int, b: int) -> void:
	_srv_move.rpc_id(1, loc_id, slot, a, b)


@rpc("any_peer", "call_local", "reliable")
func _srv_move(loc_id: String, slot: String, a: int, b: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not _equip_ok(id, loc_id) or not (slot in equipment.get("multi", [])):
		return
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	var all_fit: Dictionary = p.get("fit", {})
	var f := normalize_fit(cls, all_fit.get(cls, {}))
	var arr: Array = f[slot]
	if a < 0 or b < 0 or a >= arr.size() or b >= arr.size() or a == b:
		return
	var t = arr[a]
	arr[a] = arr[b]
	arr[b] = t
	if slot == "vaaben":
		var g: Array = f["grupper"]
		var tg = g[a]
		g[a] = g[b]
		g[b] = tg
	all_fit[cls] = f
	p["fit"] = all_fit
	_save_dirty = true
	_send_fit(id)


func _stash_add(p: Dictionary, item_id: String, n: int) -> void:
	var it := part(item_id)
	if item_id == "" or it.is_empty() or int(it.get("price", 0)) == 0:
		return    # standarddele er gratis og fylder ikke på lageret
	var st: Dictionary = p.get("parts", {})
	st[item_id] = int(st.get(item_id, 0)) + n
	if int(st[item_id]) <= 0:
		st.erase(item_id)
	p["parts"] = st


@rpc("any_peer", "call_local", "reliable")
func _srv_equip(loc_id: String, item_id: String, idx: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	var it := part(item_id)
	if not _equip_ok(id, loc_id) or it.is_empty():
		return
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	var slot: String = it["slot"]
	var all_fit: Dictionary = p.get("fit", {})
	var f := normalize_fit(cls, all_fit.get(cls, {}))
	var multi: bool = slot in equipment.get("multi", [])
	if multi:
		var arr: Array = f[slot]
		if idx < 0 or idx >= arr.size():
			idx = arr.find("")
			if idx < 0:
				idx = arr.find(equipment["default"].get(slot, "")) if slot == "vaaben" else -1
			if idx < 0:
				idx = 0
	var cur: String = f[slot][idx] if multi else f[slot]
	if cur == item_id:
		return
	var stash: Dictionary = p.get("parts", {})
	var price := int(it["price"])
	var from_stash := int(stash.get(item_id, 0)) > 0
	if not from_stash and price > 0:
		if not (has_outfitter(loc_id) or test_mode):
			_cl_toast.rpc_id(id, "Her er ingen udstyrsforhandler – kun dele fra lageret kan installeres")
			return
		if not test_mode and rank_index(int(p.get("xp", 0))) < MK_RANK[int(it["mk"])]:
			_cl_toast.rpc_id(id, "%s kræver rang %s" % [it["name"], mission_data["ranks"][MK_RANK[int(it["mk"])]]["name"]])
			return
		if int(p["credits"]) < price:
			_cl_toast.rpc_id(id, "Ikke nok kredit til %s" % it["name"])
			return
		p["credits"] = int(p["credits"]) - price
	elif from_stash:
		_stash_add(p, item_id, -1)
	_stash_add(p, cur, 1)
	if multi:
		(f[slot] as Array)[idx] = item_id
	else:
		f[slot] = item_id
	all_fit[cls] = f
	p["fit"] = all_fit
	_save_dirty = true
	_send_wallet(id)
	_send_fit(id)
	var how := "fra lageret" if from_stash else ("købt for %d cr" % price if price > 0 else "")
	var old_name: String = part(cur).get("name", "")
	var msg := "%s monteret" % it["name"]
	if how != "":
		msg += " (%s)" % how
	if old_name != "" and int(part(cur).get("price", 0)) > 0:
		msg += " · %s lagt på lageret" % old_name
	_cl_toast.rpc_id(id, msg)


@rpc("any_peer", "call_local", "reliable")
func _srv_unequip(loc_id: String, slot: String, idx: int) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not _equip_ok(id, loc_id) or not equipment["slots"].has(slot):
		return
	var p: Dictionary = players[id]
	var cls: String = p.get("ship", "falk")
	var all_fit: Dictionary = p.get("fit", {})
	var f := normalize_fit(cls, all_fit.get(cls, {}))
	var cur := ""
	if slot in equipment.get("multi", []):
		var arr: Array = f[slot]
		if idx < 0 or idx >= arr.size() or arr[idx] == "":
			return
		if slot == "vaaben" and arr.count("") >= arr.size() - 1:
			_cl_toast.rpc_id(id, "Skibet skal have mindst ét våben")
			return
		cur = arr[idx]
		arr[idx] = ""
	else:
		cur = f[slot]
		f[slot] = str(equipment["default"].get(slot, ""))
		if cur == f[slot]:
			return
	_stash_add(p, cur, 1)
	all_fit[cls] = f
	p["fit"] = all_fit
	_save_dirty = true
	_send_fit(id)


@rpc("any_peer", "call_local", "reliable")
func _srv_sell_part(loc_id: String, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not _equip_ok(id, loc_id):
		return
	var p: Dictionary = players[id]
	var st: Dictionary = p.get("parts", {})
	if int(st.get(item_id, 0)) <= 0:
		return
	var it := part(item_id)
	_stash_add(p, item_id, -1)
	var got := int(it["price"]) / 2
	p["credits"] = int(p["credits"]) + got
	_save_dirty = true
	_send_wallet(id)
	_send_fit(id)
	_cl_toast.rpc_id(id, "%s solgt for %d cr" % [it["name"], got])


func _send_fit(id: int) -> void:
	var p: Dictionary = players[id]
	_cl_fit.rpc_id(id, p.get("fit", {}), p.get("parts", {}))


@rpc("authority", "call_local", "reliable")
func _cl_fit(f: Dictionary, st: Dictionary = {}) -> void:
	fit = f.duplicate(true)
	parts = st.duplicate()
	fit_changed.emit()


func missile_max() -> int:
	return missile_max_for(local_class())


## Et missil er affyret (lokalt trukket fra med det samme; værten retter tallet).
func request_spend_missile() -> void:
	_srv_spend_missile.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _srv_spend_missile() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if players.has(id):
		players[id]["missiles"] = maxi(0, int(players[id].get("missiles", 0)) - 1)
		_send_wallet(id)


## Lokal spillers opgraderingsniveau (fx "laser", "shield").
func upgrade_level(id: String) -> int:
	return int(wallet["upgrades"].get(id, 0))


# ---------------------------------------------------------------- server: spillere

func server_add_player(id: int, pname: String, ship_choice := "") -> void:
	if not multiplayer.is_server():
		return
	var color: String = PLAYER_COLORS[players.size() % PLAYER_COLORS.size()]
	var starts: Array = ship_data["order"] if test_mode else ship_data.get("start", ship_data["order"])
	var cls: String = ship_choice if ship_choice in starts else str(ship_data["default"])
	players[id] = {"name": pname, "color": color, "credits": START_CREDITS, "cargo": {},
		"cargo_max": CARGO_MAX + int(ship_data["classes"][cls].get("cargo_bonus", 0)), "upgrades": {}, "kills": 0, "xp": 0,
		"missiles": mini(START_MISSILES, missile_max_for(cls)), "ship": cls, "ships": [cls]}
	# Kendt pilot? Så fortsætter vedkommende, hvor han slap.
	if saved_pilots.has(pname):
		var sv: Dictionary = saved_pilots[pname]
		for k: String in ["credits", "cargo", "cargo_max", "upgrades", "kills", "xp", "missiles", "ship", "ships", "look", "fit", "parts"]:
			if sv.has(k):
				players[id][k] = sv[k]
		players[id]["credits"] = int(players[id]["credits"])
		players[id]["cargo_max"] = int(players[id]["cargo_max"])
		players[id]["missiles"] = int(players[id]["missiles"])
		# Testtilstand: det valgte skib bruges også for kendte piloter
		if test_mode and ship_data["classes"].has(ship_choice):
			var ships: Array = players[id].get("ships", [])
			if not (ship_choice in ships):
				ships.append(ship_choice)
			players[id]["ships"] = ships
			players[id]["ship"] = ship_choice
	# Fortæl den nye spiller om dem, der allerede er her.
	for other: int in players:
		if other != id:
			_cl_spawn.rpc_id(id, other, _public(other), players.keys().find(other))
	# Fortæl alle (også serveren selv) om den nye.
	_cl_spawn.rpc(id, _public(id), players.keys().find(id))
	_cl_markets_full.rpc_id(id, _all_prices())
	_cl_world.rpc_id(id, world)
	_send_wallet(id)
	_send_fit(id)
	player_joined.emit(id)


func server_remove_player(id: int) -> void:
	if not multiplayer.is_server() or not players.has(id):
		return
	server_save()
	players.erase(id)
	_cl_despawn.rpc(id)


func _public(id: int) -> Dictionary:
	return {"name": players[id]["name"], "color": players[id]["color"], "ship": players[id].get("ship", "falk"),
		"look": players[id].get("look", {})}


@rpc("any_peer", "call_remote", "reliable")
func srv_register(pname: String, ship_choice := "") -> void:
	server_add_player(_sender(), pname.strip_edges().left(16), ship_choice)


# ---------------------------------------------------------------- skibe og værft

## Skibsklassen, den lokale spiller flyver.
func local_class() -> String:
	var me := multiplayer.get_unique_id() if multiplayer.multiplayer_peer else 1
	return str(roster.get(me, {}).get("ship", ship_data["default"]))


func missile_max_for(cls: String) -> int:
	return int(ship_data["classes"].get(cls, ship_data["classes"]["falk"]).get("missiles", 8))


func missile_max_of(id: int) -> int:
	return missile_max_for(str(players.get(id, {}).get("ship", "falk")))


## Har stedet et værft? (Solhavn altid, Bastion Kepler når værftet er bygget.)
func has_shipyard(loc_id: String) -> bool:
	var loc: Dictionary = locations.get(loc_id, {})
	if loc.get("shipyard", false):
		return true
	return loc.get("base", false) and module_unlocked("shipyard")


## Hvor mange skibe kan man eje? 2 uden egen base, +1 for hver base gruppen ejer og
## +3 for hver base med Hangar og værksted.
const BASE_SHIP_SLOTS := 2


func ship_slots() -> int:
	var n := BASE_SHIP_SLOTS
	for plot_id: String in world.get("bases", {}):
		var st: Dictionary = world["bases"][plot_id]
		if st.get("owned", false):
			n += 1 + 3 * int(st.get("modules", {}).get("hangar", 0))
	return n


## Kan man købe nye skibe her? (værfter på stationer og Concord-basen – ikke egne baser)
func can_buy_ships(loc_id: String) -> bool:
	var loc: Dictionary = locations.get(loc_id, {})
	if loc.get("shipyard", false):
		return true
	return loc.get("base", false) and module_unlocked("shipyard")


## Kan man skifte mellem sine egne skibe her? (også i hangaren på en egen base)
func can_switch_ships(loc_id: String) -> bool:
	if can_buy_ships(loc_id):
		return true
	var st := base_state(loc_id)
	return st.get("owned", false) and int(st.get("modules", {}).get("hangar", 0)) > 0


func owned_ships() -> Array:
	return wallet.get("ships", [local_class()])


func request_ship(loc_id: String, cls: String) -> void:
	_srv_ship.rpc_id(1, loc_id, cls)


@rpc("any_peer", "call_local", "reliable")
func _srv_ship(loc_id: String, cls: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id) or not ship_data["classes"].has(cls) or not can_switch_ships(loc_id):
		return
	var p: Dictionary = players[id]
	var data: Dictionary = ship_data["classes"][cls]
	var ships: Array = p.get("ships", [p.get("ship", "falk")])
	if p.get("ship", "") == cls:
		return
	var new_max := CARGO_MAX + int(p["upgrades"].get("cargo", 0)) * int(universe["upgrades"]["cargo"]["cargo_bonus"]) + int(data.get("cargo_bonus", 0))
	if cargo_total(p["cargo"]) > new_max:
		_cl_toast.rpc_id(id, "Sælg noget af lasten først – %s har kun plads til %d" % [data["name"], new_max])
		return
	if not (cls in ships):
		if not can_buy_ships(loc_id):
			_cl_toast.rpc_id(id, "Nye skibe købes på et værft – her kan du kun skifte mellem dine egne")
			return
		if ships.size() >= ship_slots():
			_cl_toast.rpc_id(id, "Ingen plads til flere skibe (%d/%d) – køb en base, eller byg en hangar på jeres base" % [ships.size(), ship_slots()])
			return
		if int(p["credits"]) < int(data["price"]):
			_cl_toast.rpc_id(id, "%s koster %d cr" % [data["name"], int(data["price"])])
			return
		p["credits"] = int(p["credits"]) - int(data["price"])
		ships.append(cls)
		p["ships"] = ships
		_cl_toast.rpc_id(id, "%s købt!" % data["name"])
	else:
		_cl_toast.rpc_id(id, "Skiftet til %s" % data["name"])
	p["ship"] = cls
	p["cargo_max"] = new_max
	p["missiles"] = mini(int(p.get("missiles", 0)), missile_max_for(cls))
	_send_wallet(id)
	_cl_ship_class.rpc(id, cls)


## Tilpasning af skibet (hangaren): farver, mønster og navn.
const LOOK_KEYS := ["paint", "accent", "engine", "flame", "pattern", "ship_name"]


func local_look() -> Dictionary:
	return roster.get(multiplayer.get_unique_id(), {}).get("look", {})


func request_look(look: Dictionary) -> void:
	_srv_look.rpc_id(1, look)


@rpc("any_peer", "call_local", "reliable")
func _srv_look(look: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id):
		return
	var clean := {}
	for k: String in LOOK_KEYS:
		if look.has(k):
			var v := str(look[k])
			if k == "ship_name":
				clean[k] = v.strip_edges().left(16)
			elif k == "pattern":
				if ShipModel.PATTERNS.has(v):
					clean[k] = v
			elif Color.html_is_valid(v):
				clean[k] = v.trim_prefix("#").left(6)
	players[id]["look"] = clean
	_save_dirty = true
	_cl_look.rpc(id, clean)


@rpc("authority", "call_local", "reliable")
func _cl_look(id: int, look: Dictionary) -> void:
	if roster.has(id):
		roster[id]["look"] = look
	look_changed.emit(id, look)


@rpc("authority", "call_local", "reliable")
func _cl_ship_class(id: int, cls: String) -> void:
	if roster.has(id):
		roster[id]["ship"] = cls
	ship_class_changed.emit(id, cls)


@rpc("authority", "call_local", "reliable")
func _cl_spawn(id: int, info: Dictionary, index: int) -> void:
	info["index"] = index
	roster[id] = info
	ship_spawned.emit(id, info)


@rpc("authority", "call_local", "reliable")
func _cl_despawn(id: int) -> void:
	roster.erase(id)
	ship_removed.emit(id)


func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


# ---------------------------------------------------------------- handel

## Kaldes af UI på enhver maskine. Serveren afgør resultatet.
func request_trade(loc_id: String, good: String, amount: int, buying: bool) -> void:
	_srv_trade.rpc_id(1, loc_id, good, amount, buying)


func request_upgrade(loc_id: String, upgrade_id: String) -> void:
	_srv_upgrade.rpc_id(1, loc_id, upgrade_id)


@rpc("any_peer", "call_local", "reliable")
func _srv_trade(loc_id: String, good: String, amount: int, buying: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id) or not markets.has(loc_id) or not markets[loc_id].has(good):
		return
	var p: Dictionary = players[id]
	var g: Dictionary = markets[loc_id][good]
	if buying != (g["mode"] == "sell"):
		return
	var done := 0
	var total := 0
	for i in amount:
		var price := int(round(g["price"]))
		if buying:
			if p["credits"] < price or cargo_total(p["cargo"]) >= p["cargo_max"]:
				break
			p["credits"] -= price
			p["cargo"][good] = int(p["cargo"].get(good, 0)) + 1
			g["price"] = minf(g["base"] * 1.6, g["price"] * 1.02)
		else:
			if int(p["cargo"].get(good, 0)) <= 0:
				break
			p["credits"] += price
			p["cargo"][good] = int(p["cargo"][good]) - 1
			g["price"] = maxf(g["base"] * 0.5, g["price"] * 0.97)
		done += 1
		total += price
	_send_wallet(id)
	_cl_market.rpc(loc_id, _prices(loc_id))
	if done > 0:
		var verb := "Købt" if buying else "Solgt"
		var prefix := "−" if buying else "+"
		_cl_toast.rpc_id(id, "%s %d %s · %s%d cr" % [verb, done, good_name(good).to_lower(), prefix, total])
	elif buying:
		_cl_toast.rpc_id(id, "Ikke nok kredit eller plads i lastrummet")


@rpc("any_peer", "call_local", "reliable")
func _srv_upgrade(loc_id: String, upgrade_id: String) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id) or not locations.has(loc_id):
		return
	if not (upgrade_id in location_upgrades(loc_id)):
		return
	if upgrade_id == "repair":
		return
	var up: Dictionary = universe["upgrades"][upgrade_id]
	var p: Dictionary = players[id]
	if up.get("consumable", false):
		# Missiler: fyld op til fuldt magasin
		var have := int(p.get("missiles", 0))
		var mx := missile_max_of(id)
		var n := mini(mx - have, int(p["credits"]) / int(up["price_each"]))
		if n <= 0:
			_cl_toast.rpc_id(id, "Magasinet er fuldt" if have >= mx else "Ikke nok kredit")
			return
		p["credits"] -= n * int(up["price_each"])
		p["missiles"] = have + n
		_send_wallet(id)
		_cl_toast.rpc_id(id, "+%d missiler (%d/%d)" % [n, have + n, mx])
		return
	var level := int(p["upgrades"].get(upgrade_id, 0))
	var price := upgrade_price(upgrade_id, level)
	if level >= int(up["max_level"]) or p["credits"] < price:
		_cl_toast.rpc_id(id, "Kan ikke købe %s" % up["name"])
		return
	p["credits"] -= price
	p["upgrades"][upgrade_id] = level + 1
	if upgrade_id == "cargo":
		p["cargo_max"] += int(up["cargo_bonus"])
	_send_wallet(id)
	_cl_toast.rpc_id(id, "%s installeret" % up["name"])


# ---------------------------------------------------------------- testværktøjer

## Testtilstand: udfør et testværktøj for spilleren (kun når test_mode er slået til hos værten).
func request_test(action: String, arg := "") -> void:
	_srv_test.rpc_id(1, action, arg)


@rpc("any_peer", "call_local", "reliable")
func _srv_test(action: String, arg: String) -> void:
	if not multiplayer.is_server() or not test_mode:
		return
	var id := _sender()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var msg := ""
	match action:
		"credits":
			p["credits"] = int(p["credits"]) + 10000
			msg = "+10.000 cr"
		"upgrades":
			for up_id: String in universe["upgrades"]:
				var up: Dictionary = universe["upgrades"][up_id]
				if up.has("max_level"):
					var before := int(p["upgrades"].get(up_id, 0))
					p["upgrades"][up_id] = int(up["max_level"])
					if up_id == "cargo":
						p["cargo_max"] = int(p["cargo_max"]) + int(up["cargo_bonus"]) * (int(up["max_level"]) - before)
			msg = "Alle opgraderinger på max"
		"ammo":
			p["missiles"] = missile_max_of(id)
			msg = "Fuldt missilmagasin (%d)" % int(p["missiles"])
		"all_ships":
			p["ships"] = (ship_data["order"] as Array).duplicate()
			msg = "Alle %d skibe er dine" % (p["ships"] as Array).size()
		"ship":
			if ship_data["classes"].has(arg):
				var ships: Array = p.get("ships", [])
				if not (arg in ships):
					ships.append(arg)
					p["ships"] = ships
				p["ship"] = arg
				_cl_ship_class.rpc(id, arg)
				p["missiles"] = mini(int(p.get("missiles", 0)), missile_max_of(id))
				msg = "Skifter til %s" % ship_data["classes"][arg]["name"]
		"rank":
			p["xp"] = int(p["xp"]) + 500
			msg = "+500 xp"
		"parts":
			var st: Dictionary = p.get("parts", {})
			for base: String in equipment["items"]:
				for mk in range(1, MK_MAX + 1):
					var pid := part_id(base, mk)
					if int(part(pid).get("price", 0)) > 0:
						st[pid] = maxi(int(st.get(pid, 0)), 1 if mk > 1 else 2)
			p["parts"] = st
			_send_fit(id)
			msg = "Alle dele i Mk I–III på lageret – åbn rumskibsmanageren (U)"
		"pirates":
			var s: Ship = W.ships.get(id)
			if s and is_instance_valid(s) and W.pirates:
				msg = "Pirater sendt ud: " + W.pirates.server_test_spawn(s.position, W.universe.system_at(s.position), arg)
		"unlock_base":
			world["missions_completed"] = maxi(int(world.get("missions_completed", 0)), 20)
			server_world_changed()
			msg = "Alle moduler på Concord-basen er låst op"
	_send_wallet(id)
	if msg != "":
		_cl_toast.rpc_id(id, "TEST: " + msg)
	_cl_test_done.rpc_id(id, action)


signal test_done(action: String)


@rpc("authority", "call_local", "reliable")
func _cl_test_done(action: String) -> void:
	test_done.emit(action)


func _send_wallet(id: int) -> void:
	var p: Dictionary = players[id]
	_save_dirty = true
	_cl_wallet.rpc_id(id, p["credits"], p["cargo"], p["cargo_max"], p["upgrades"], p["kills"], p["xp"], int(p.get("missiles", 0)), p.get("ships", ["falk"]))


@rpc("authority", "call_local", "reliable")
func _cl_wallet(credits: int, cargo: Dictionary, cargo_max: int, upgrades: Dictionary, kills: int, xp: int, missiles: int, ships: Array) -> void:
	wallet = {"credits": credits, "cargo": cargo.duplicate(), "cargo_max": cargo_max,
		"upgrades": upgrades.duplicate(), "kills": kills, "xp": xp, "missiles": missiles, "ships": ships.duplicate()}
	wallet_changed.emit()


# ---------------------------------------------------------------- basen og gruppens fremskridt

func base_level() -> int:
	return int(world.get("missions_completed", 0))


func module_unlocked(module_id: String) -> bool:
	for m: Dictionary in base_data["modules"]:
		if m["id"] == module_id:
			return base_level() >= int(m["missions"])
	return false


## Næste modul, der ikke er åbnet endnu (eller tom ordbog).
func next_module() -> Dictionary:
	for m: Dictionary in base_data["modules"]:
		if base_level() < int(m["missions"]):
			return m
	return {}


## Opgraderinger et sted tilbyder. Basen tilbyder flere, efterhånden som moduler åbnes.
func location_upgrades(loc_id: String) -> Array:
	var ups: Array = locations.get(loc_id, {}).get("upgrades", []).duplicate()
	if locations.get(loc_id, {}).get("base", false):
		for m: Dictionary in base_data["modules"]:
			if m.has("upgrade") and module_unlocked(m["id"]) and not (m["upgrade"] in ups):
				ups.append(m["upgrade"])
	return ups


## Server: en mission er fuldført. Returnerer navnet på et nyt modul, hvis et blev åbnet.
func server_mission_completed() -> String:
	var before := next_module()
	world["missions_completed"] = base_level() + 1
	_cl_world.rpc(world)
	_save_dirty = true
	if not before.is_empty() and base_level() >= int(before["missions"]):
		return before["name"]
	return ""


## Server: fælles verdenstilstand (fx egne baser) er ændret – send den ud og gem snart.
func server_world_changed() -> void:
	_cl_world.rpc(world)
	_save_dirty = true


func plot_data(plot_id: String) -> Dictionary:
	for p: Dictionary in bases_data["plots"]:
		if p["id"] == plot_id:
			return p
	return {}


func base_module_data(module_id: String) -> Dictionary:
	for m: Dictionary in bases_data["modules"]:
		if m["id"] == module_id:
			return m
	return {}


## Gruppens base på en byggegrund (tom hvis den ikke er købt).
func base_state(plot_id: String) -> Dictionary:
	return world.get("bases", {}).get(plot_id, {})


@rpc("authority", "call_local", "reliable")
func _cl_world(w: Dictionary) -> void:
	world = w.duplicate()
	world_changed.emit()


# ---------------------------------------------------------------- rang og erfaring

## Rang-indeks for et antal erfaringspoint.
func rank_index(xp: int) -> int:
	var ranks: Array = mission_data["ranks"]
	var idx := 0
	for i in ranks.size():
		if xp >= int(ranks[i]["xp"]):
			idx = i
	return idx


func rank_name(xp: int) -> String:
	return mission_data["ranks"][rank_index(xp)]["name"]


## Erfaring nødvendig til næste rang (eller -1 ved højeste rang).
func next_rank_xp(xp: int) -> int:
	var ranks: Array = mission_data["ranks"]
	var i := rank_index(xp)
	return int(ranks[i + 1]["xp"]) if i + 1 < ranks.size() else -1


## Server: udbetal missionsbelønning til én spiller.
func server_reward(id: int, credits: int, xp: int) -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	p["credits"] = int(p["credits"]) + credits
	p["xp"] = int(p["xp"]) + xp
	_send_wallet(id)


# ---------------------------------------------------------------- gem og indlæs (kun værten)

func server_load() -> void:
	saved_pilots = {}
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and data.has("pilots"):
		saved_pilots = data["pilots"]
	if data is Dictionary and data.has("world"):
		world = data["world"]
		world["missions_completed"] = int(world.get("missions_completed", 0))


func server_save() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or not multiplayer.is_server():
		return
	for id: int in players:
		var p: Dictionary = players[id]
		saved_pilots[p["name"]] = {"credits": p["credits"], "cargo": p["cargo"], "cargo_max": p["cargo_max"],
			"upgrades": p["upgrades"], "kills": p["kills"], "xp": p["xp"], "missiles": p["missiles"],
			"ship": p.get("ship", "falk"), "ships": p.get("ships", ["falk"]), "look": p.get("look", {}), "fit": p.get("fit", {}), "parts": p.get("parts", {})}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": 2, "pilots": saved_pilots, "world": world}, "\t"))
		f.close()
	_save_dirty = false


# ---------------------------------------------------------------- reparation, død, dusør og last

func request_repair(loc_id: String, hull: float) -> void:
	_srv_repair.rpc_id(1, loc_id, hull)


func report_death() -> void:
	_srv_death.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _srv_repair(loc_id: String, hull: float) -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id) or not ("repair" in location_upgrades(loc_id)):
		return
	var p: Dictionary = players[id]
	var per := float(universe["upgrades"]["repair"]["price_per_hull"])
	var cost := int(ceil((100.0 - hull) * per))
	var pay := mini(cost, int(p["credits"]))
	if pay <= 0:
		_cl_toast.rpc_id(id, "Ikke nok kredit til reparation")
		return
	p["credits"] -= pay
	_send_wallet(id)
	_cl_repaired.rpc_id(id, minf(100.0, hull + pay / per))
	_cl_toast.rpc_id(id, "Skroget er repareret · −%d cr" % pay)


@rpc("authority", "call_local", "reliable")
func _cl_repaired(hull: float) -> void:
	repaired.emit(hull)


@rpc("any_peer", "call_local", "reliable")
func _srv_death() -> void:
	if not multiplayer.is_server():
		return
	var id := _sender()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	p["credits"] = maxi(0, int(p["credits"]) - int(combat("salvage_fee")))
	p["cargo"] = {}
	_send_wallet(id)


## Smid `amount` stk. af en vare ud af lastrummet (i luften). amount <= 0 = alt.
func request_jettison(good: String, amount: int) -> void:
	_srv_jettison.rpc_id(1, good, amount)


@rpc("any_peer", "call_local", "reliable")
func _srv_jettison(good: String, amount: int) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var have := int(p["cargo"].get(good, 0))
	var n := have if amount <= 0 else mini(amount, have)
	var s: Ship = W.ships.get(id)
	if n <= 0 or s == null or not is_instance_valid(s) or s.state != Ship.State.FLY:
		return
	p["cargo"][good] = have - n
	if int(p["cargo"][good]) <= 0:
		p["cargo"].erase(good)
	_send_wallet(id)
	_save_dirty = true
	var back := -s.forward()
	W.pickups.server_jettison(good, s.position + back * 7.0, s.forward() * s.speed * 0.6 + back * 14.0, mini(n, 20), id)
	server_toast(id, "Smed %d %s ud af lastrummet" % [n, good_name(good).to_lower()])


## Server: læg én vare i en spillers lastrum. Returnerer false hvis der ikke er plads.
func server_add_cargo(id: int, kind: String) -> bool:
	if not players.has(id):
		return false
	var p: Dictionary = players[id]
	if cargo_total(p["cargo"]) >= int(p["cargo_max"]):
		return false
	p["cargo"][kind] = int(p["cargo"].get(kind, 0)) + 1
	_send_wallet(id)
	return true


func server_award_bounty(id: int, mult := 1.0, what := "Pirat") -> void:
	if not players.has(id):
		return
	var p: Dictionary = players[id]
	var scrap := server_has_gadget(id, "skrotarm")
	var bounty := int(round(combat("bounty") * mult * ((1.0 + 0.25 * server_gadget_power(id, "skrotarm")) if scrap else 1.0)))
	p["credits"] += bounty
	p["kills"] = int(p["kills"]) + 1
	_send_wallet(id)
	_cl_toast.rpc_id(id, "%s nedkæmpet · +%d cr dusør" % [what, bounty])
	if mult >= 4.0:
		p["xp"] = int(p["xp"]) + int(mult * 15.0)


func server_toast(id: int, msg: String) -> void:
	if players.has(id):
		_cl_toast.rpc_id(id, msg)


## Server: ændr en pris med en faktor (fx når et fragtskib leverer) og send den ud.
func server_nudge_price(loc_id: String, good: String, factor: float) -> void:
	if not markets.has(loc_id) or not markets[loc_id].has(good):
		return
	var g: Dictionary = markets[loc_id][good]
	g["price"] = clampf(g["price"] * factor, g["base"] * 0.5, g["base"] * 1.6)
	_cl_market.rpc(loc_id, _prices(loc_id))


func _prices(loc_id: String) -> Dictionary:
	var out := {}
	for g: String in markets[loc_id]:
		out[g] = markets[loc_id][g]["price"]
	return out


func _all_prices() -> Dictionary:
	var out := {}
	for loc: String in markets:
		out[loc] = _prices(loc)
	return out


@rpc("authority", "call_local", "reliable")
func _cl_market(loc_id: String, prices: Dictionary) -> void:
	if not markets.has(loc_id):
		return
	for g: String in prices:
		if markets[loc_id].has(g):
			markets[loc_id][g]["price"] = prices[g]
	market_changed.emit(loc_id)


@rpc("authority", "call_local", "reliable")
func _cl_markets_full(all: Dictionary) -> void:
	for loc: String in all:
		_cl_market(loc, all[loc])


@rpc("authority", "call_local", "reliable")
func _cl_toast(msg: String) -> void:
	toast.emit(msg)


func _process(delta: float) -> void:
	# Serveren lader priserne glide langsomt tilbage mod udgangspunktet.
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or players.is_empty():
		return
	_save_t += delta
	if _save_dirty and _save_t > 2.0:
		_save_t = 0.0
		server_save()
	_drift_t += delta
	if _drift_t < 3.0:
		return
	for loc: String in markets:
		for g: String in markets[loc]:
			var e: Dictionary = markets[loc][g]
			e["price"] = lerpf(e["price"], e["base"], 0.03)
	_drift_t = 0.0
	_cl_markets_full.rpc(_all_prices())
