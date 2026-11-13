class_name StationMenu
extends Control
## Menuen når man er landet eller docket: pixelscene, rygter, marked, værksted og afgang.
## Alle køb går gennem Game.request_*, så værten afgør resultatet i co-op.

signal launch_requested

var loc_id := ""

var _title: Label
var _sub: Label
var _note: Label
var _scene: TextureRect
var _rumor: Label
var _wallet: Label
var _market: GridContainer
var _tabs: TabContainer
var _board: VBoxContainer
var _base_box: VBoxContainer
var _shop: VBoxContainer
var _yard: VBoxContainer
var _paint: ShipPaint
var _jobs_box: VBoxContainer
var _eq_box: VBoxContainer
var _launch: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(UiTheme.INK, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiTheme.value("", UiTheme.YELLOW, 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_sub = UiTheme.caption("")
	head.add_child(_sub)

	_note = UiTheme.value("", UiTheme.DANGER, 15)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.visible = false
	v.add_child(_note)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 18)
	v.add_child(top)
	var left := VBoxContainer.new()
	top.add_child(left)
	_scene = TextureRect.new()
	_scene.custom_minimum_size = Vector2(384, 216)
	_scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_scene.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene.stretch_mode = TextureRect.STRETCH_SCALE
	left.add_child(_scene)
	_rumor = UiTheme.value("", UiTheme.CYAN, 14)
	_rumor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rumor.custom_minimum_size = Vector2(384, 0)
	left.add_child(_rumor)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	_wallet = UiTheme.value("", UiTheme.TEXT, 16)
	_wallet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_wallet)
	right.add_child(UiTheme.caption("Værksted", UiTheme.PINK))
	_shop = VBoxContainer.new()
	right.add_child(_shop)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_launch = Button.new()
	_launch.text = "ENTER  AFGANG ▲"
	_launch.pressed.connect(func(): launch_requested.emit())
	right.add_child(_launch)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 270)
	v.add_child(_tabs)
	var board_scroll := ScrollContainer.new()
	board_scroll.name = "Concord Patrol"
	board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(board_scroll)
	_board = VBoxContainer.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.add_theme_constant_override("separation", 10)
	board_scroll.add_child(_board)
	var base_scroll := ScrollContainer.new()
	base_scroll.name = "Bastion"
	base_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(base_scroll)
	_base_box = VBoxContainer.new()
	_base_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_box.add_theme_constant_override("separation", 6)
	base_scroll.add_child(_base_box)
	var market_scroll := ScrollContainer.new()
	market_scroll.name = "Marked"
	market_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(market_scroll)
	_market = GridContainer.new()
	_market.columns = 6
	_market.add_theme_constant_override("h_separation", 14)
	_market.add_theme_constant_override("v_separation", 6)
	market_scroll.add_child(_market)
	var yard_scroll := ScrollContainer.new()
	yard_scroll.name = "Værft"
	yard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(yard_scroll)
	_yard = VBoxContainer.new()
	_yard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yard.add_theme_constant_override("separation", 8)
	yard_scroll.add_child(_yard)

	var paint_scroll := ScrollContainer.new()
	paint_scroll.name = "Tilpas skib"
	paint_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(paint_scroll)
	_paint = ShipPaint.new()
	_paint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_scroll.add_child(_paint)

	var jobs_scroll := ScrollContainer.new()
	jobs_scroll.name = "Opslagstavle"
	jobs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(jobs_scroll)
	_jobs_box = VBoxContainer.new()
	_jobs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs_box.add_theme_constant_override("separation", 6)
	jobs_scroll.add_child(_jobs_box)
	W.jobs.jobs_changed.connect(_refresh_jobs)

	var eq_scroll := ScrollContainer.new()
	eq_scroll.name = "Udstyr"
	eq_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(eq_scroll)
	_eq_box = VBoxContainer.new()
	_eq_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eq_box.add_theme_constant_override("separation", 4)
	eq_scroll.add_child(_eq_box)
	Game.fit_changed.connect(_refresh_equipment)
	Game.ship_class_changed.connect(func(_id, _c): _refresh_equipment())

	Game.wallet_changed.connect(_refresh)
	Game.world_changed.connect(_refresh)
	W.missions.board_changed.connect(_refresh)
	W.missions.state_changed.connect(_refresh)
	Game.market_changed.connect(_on_market_changed)
	Game.repaired.connect(func(_h: float): _refresh.call_deferred())


func _on_market_changed(id: String) -> void:
	if id == loc_id:
		_refresh()


func open(id: String, note := "") -> void:
	loc_id = id
	var loc: Dictionary = Game.locations[id]
	_title.text = loc["title"]
	_sub.text = str(loc["sub"]).to_upper()
	_note.text = note
	_note.visible = note != ""
	_scene.texture = SceneArt.texture_for(loc)
	var patrol: bool = loc.get("patrol", false)
	var is_base: bool = loc.get("base", false)
	_tabs.set_tab_hidden(0, not patrol)
	_tabs.set_tab_hidden(1, not is_base)
	_tabs.set_tab_hidden(3, not Game.has_shipyard(id))
	_tabs.set_tab_hidden(4, not (is_base or Game.has_shipyard(id)))
	_tabs.current_tab = 0 if patrol else 2
	_paint.refresh()
	_tabs.set_tab_hidden(5, W.bases.is_plot(id))
	_tabs.set_tab_hidden(6, not Game.has_outfitter(id))
	W.jobs.request_board(id)
	var rumors: Array = loc.get("rumors", [])
	_rumor.text = rumors.pick_random() if not rumors.is_empty() else ""
	visible = true
	_refresh()
	_launch.grab_focus()


func close() -> void:
	visible = false
	loc_id = ""


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("launch"):
		get_viewport().set_input_as_handled()
		launch_requested.emit()


func _refresh() -> void:
	if not visible or loc_id == "":
		return
	var w: Dictionary = Game.wallet
	var used := Game.cargo_total(w["cargo"])
	var full := used >= int(w["cargo_max"])
	var ship := W.local_ship
	var hull := ship.hull if ship else 100.0
	_wallet.text = "%d cr   ·   Last %d/%d   ·   Skrog %d   ·   Pirater nedkæmpet %d" % [
		int(w["credits"]), used, int(w["cargo_max"]), int(hull), int(w.get("kills", 0))]
	_tabs.set_tab_hidden(3, not Game.has_shipyard(loc_id))
	_refresh_yard()
	_refresh_jobs()
	_refresh_equipment()

	for c in _market.get_children():
		c.queue_free()
	for h: String in ["", "VARE", "", "PRIS", "LAST", ""]:
		_market.add_child(UiTheme.caption(h))
	var m: Dictionary = Game.markets[loc_id]
	for g: String in m:
		var e: Dictionary = m[g]
		var price := int(round(e["price"]))
		var have := int(w["cargo"].get(g, 0))
		var swatch := ColorRect.new()
		swatch.color = Game.col(Game.goods[g]["color"])
		swatch.custom_minimum_size = Vector2(12, 12)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_market.add_child(swatch)
		_market.add_child(UiTheme.value(Game.good_name(g)))
		_market.add_child(UiTheme.caption("Sælger" if e["mode"] == "sell" else "Køber"))
		var trend := ""
		if e["price"] > e["base"] * 1.03:
			trend = " ▲"
		elif e["price"] < e["base"] * 0.97:
			trend = " ▼"
		_market.add_child(UiTheme.value("%d cr%s" % [price, trend], UiTheme.YELLOW))
		_market.add_child(UiTheme.value(str(have)))
		var btns := HBoxContainer.new()
		_market.add_child(btns)
		if e["mode"] == "sell":
			btns.add_child(_trade_btn("Køb 1", g, 1, true, int(w["credits"]) >= price and not full))
			btns.add_child(_trade_btn("Køb max", g, 99, true, int(w["credits"]) >= price and not full))
		else:
			btns.add_child(_trade_btn("Sælg 1", g, 1, false, have > 0))
			btns.add_child(_trade_btn("Sælg alt", g, 99, false, have > 0))

	_refresh_board()
	_refresh_base()

	for c in _shop.get_children():
		c.queue_free()
	var ups: Array = Game.location_upgrades(loc_id)
	if ups.is_empty():
		_shop.add_child(UiTheme.value("Intet værksted her.", UiTheme.MUTED, 14))
	for up_id: String in ups:
		var up: Dictionary = Game.universe["upgrades"][up_id]
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if up_id == "repair":
			var cost := int(ceil((100.0 - hull) * float(up["price_per_hull"])))
			b.text = "Reparer skrog · %d cr" % cost if cost > 0 else "Skroget er helt"
			b.disabled = cost <= 0 or int(w["credits"]) <= 0
			b.pressed.connect(func(): Game.request_repair(loc_id, W.local_ship.hull))
		elif up.get("consumable", false):
			var have := int(w.get("missiles", 0))
			var need := Game.missile_max() - have
			b.text = "Missiler %d/%d · fyld op %d cr" % [have, Game.missile_max(), need * int(up["price_each"])] if need > 0 else "Missiler %d/%d · fuldt" % [have, Game.missile_max()]
			b.disabled = need <= 0 or int(w["credits"]) < int(up["price_each"])
			b.pressed.connect(func(): Game.request_upgrade(loc_id, up_id))
		else:
			var level := int(w["upgrades"].get(up_id, 0))
			if level >= int(up["max_level"]):
				b.text = "%s · installeret" % up["name"]
				b.disabled = true
			else:
				var lvl := "" if int(up["max_level"]) == 1 else "  (niveau %d/%d)" % [level, int(up["max_level"])]
				var price := Game.upgrade_price(up_id, level)
				b.text = "%s · %d cr%s" % [up["name"], price, lvl]
				b.disabled = int(w["credits"]) < price
			b.pressed.connect(func(): Game.request_upgrade(loc_id, up_id))
		_shop.add_child(b)
	# Skibets flyveegenskaber (viser effekten af manøvredyserne)
	var h := Game.handling(Game.local_class())
	var base: Dictionary = Game.ship_data["classes"][Game.local_class()]
	var info := UiTheme.value("%s · drejning %d %% · reaktion %d %% · topfart %d" % [h["name"],
		roundi(100.0 * float(h["turn"]) / float(base["turn"])), roundi(100.0 * float(h["agility"]) / float(base["agility"])),
		roundi(float(h["max_speed"]))], UiTheme.MUTED, 13)
	_shop.add_child(info)


## Værftet: køb og skift mellem skibstyperne.
func _refresh_yard() -> void:
	for c in _yard.get_children():
		c.queue_free()
	if not Game.has_shipyard(loc_id):
		return
	var w: Dictionary = Game.wallet
	var owned: Array = Game.owned_ships()
	var current := Game.local_class()
	var slots := Game.ship_slots()
	var full := owned.size() >= slots
	_yard.add_child(UiTheme.value("Dine skibe: %d/%d pladser%s" % [owned.size(), slots,
		"  ·  køb en base eller byg en hangar for flere" if full else ""], UiTheme.CYAN if not full else UiTheme.YELLOW, 14))
	for cls: String in Game.ship_data["order"]:
		var d: Dictionary = Game.ship_data["classes"][cls]
		var row := HBoxContainer.new()
		_yard.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		row.add_child(info)
		info.add_child(UiTheme.value("%s · %s" % [d["name"], d["role"]], UiTheme.YELLOW if cls == current else UiTheme.TEXT, 15))
		var stats := UiTheme.value(ShipStats.line(d), UiTheme.MUTED, 12)
		info.add_child(stats)
		var b := Button.new()
		if cls == current:
			b.text = "FLYVER NU"
			b.disabled = true
		elif cls in owned:
			b.text = "SKIFT TIL"
		else:
			b.text = "KØB · %d cr" % int(d["price"]) if not full else "INGEN PLADS"
			b.disabled = int(w["credits"]) < int(d["price"]) or full
		b.custom_minimum_size = Vector2(170, 0)
		b.pressed.connect(func(): Game.request_ship(loc_id, cls))
		row.add_child(b)


func _refresh_base() -> void:
	for c in _base_box.get_children():
		c.queue_free()
	var lvl := Game.base_level()
	var nxt := Game.next_module()
	var head := "%s · %d fuldførte missioner" % [Game.base_data["name"], lvl]
	if not nxt.is_empty():
		head += "   ·   næste modul: %s om %d" % [nxt["name"], int(nxt["missions"]) - lvl]
	_base_box.add_child(UiTheme.value(head, UiTheme.MUTED, 14))
	for m: Dictionary in Game.base_data["modules"]:
		var open := Game.module_unlocked(m["id"])
		var row := HBoxContainer.new()
		_base_box.add_child(row)
		var mark := UiTheme.value("■" if open else "□", UiTheme.GREEN if open else UiTheme.MUTED, 16)
		row.add_child(mark)
		var nm := UiTheme.value(str(m["name"]), UiTheme.YELLOW if open else UiTheme.MUTED, 16)
		nm.custom_minimum_size = Vector2(170, 0)
		row.add_child(nm)
		var desc := UiTheme.value(str(m["desc"]) if open else "Åbnes efter %d fuldførte missioner" % int(m["missions"]),
			UiTheme.TEXT if open else UiTheme.MUTED, 14)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(desc)


func _refresh_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	var xp := int(Game.wallet.get("xp", 0))
	var nxt := Game.next_rank_xp(xp)
	var rank_text := "Rang: %s · %d xp" % [Game.rank_name(xp), xp]
	if nxt > 0:
		rank_text += " (næste rang ved %d)" % nxt
	_board.add_child(UiTheme.value(rank_text, UiTheme.MUTED, 14))
	var ms := W.missions
	if ms.active:
		var st := ms.client
		_board.add_child(UiTheme.value("AKTIV MISSION: %s" % str(st.get("name", "")).to_upper(), UiTheme.YELLOW, 18))
		var obj := UiTheme.value(str(st.get("objective", "")), UiTheme.CYAN, 15)
		obj.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_board.add_child(obj)
		var abort := Button.new()
		abort.text = "Afbryd mission"
		abort.pressed.connect(func(): ms.request_abort())
		_board.add_child(abort)
		return
	if ms.board.is_empty():
		_board.add_child(UiTheme.value("Ingen missioner lige nu.", UiTheme.MUTED, 14))
	for o: Dictionary in ms.board:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme._box(UiTheme.PANEL_2, UiTheme.LINE, 2, Vector2.ZERO, Color.TRANSPARENT, 10))
		_board.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 6)
		card.add_child(cv)
		var head := HBoxContainer.new()
		cv.add_child(head)
		var title := UiTheme.value(str(o["name"]).to_upper(), UiTheme.YELLOW, 17)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		head.add_child(UiTheme.caption("%s · %s" % [o["difficulty"], Game.systems[o["system"]]["name"]],
			UiTheme.GREEN if o["difficulty"] == "Let" else (UiTheme.YELLOW if o["difficulty"] == "Middel" else UiTheme.DANGER)))
		var brief := UiTheme.value(str(o["brief"]), UiTheme.TEXT, 14)
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cv.add_child(brief)
		var foot := HBoxContainer.new()
		cv.add_child(foot)
		var pay := UiTheme.value("Løn %d cr  ·  %d xp" % [int(o["reward"]), int(o["xp"])], UiTheme.CYAN, 14)
		pay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(pay)
		var take := Button.new()
		var oid := int(o["oid"])
		if ms.can_accept(o):
			take.text = "TAG MISSION ▲"
			take.pressed.connect(func():
				ms.request_accept(oid)
				launch_requested.emit())
		else:
			take.text = "Kræver rang: %s" % Game.mission_data["ranks"][int(o["min_rank"])]["name"]
			take.disabled = true
		foot.add_child(take)


func _trade_btn(text: String, good: String, amount: int, buying: bool, enabled: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func(): Game.request_trade(loc_id, good, amount, buying))
	return b


## Opslagstavlen: sideopgaver fra stedet og dine aktive opgaver.
func _refresh_jobs() -> void:
	if _jobs_box == null or not visible or loc_id == "":
		return
	for c in _jobs_box.get_children():
		c.queue_free()
	_jobs_box.add_child(UiTheme.caption("Opslagstavle · %s" % Jobs.loc_name(loc_id), UiTheme.PINK))
	var offers: Array = W.jobs.board_cache.get(loc_id, [])
	var full := W.jobs.mine.size() >= Jobs.MAX_JOBS
	if offers.is_empty():
		_jobs_box.add_child(UiTheme.value("Ingen opslag lige nu – kig forbi senere.", UiTheme.MUTED, 14))
	for o: Dictionary in offers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_jobs_box.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiTheme.value("%s  ·  %d cr" % [o["title"], int(o["reward"])], UiTheme.YELLOW, 15))
		var d := UiTheme.value(str(o["desc"]) + "  (%d min)" % int(ceil(float(o["time"]) / 60.0)), UiTheme.MUTED, 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
		var b := Button.new()
		b.text = "TAG OPGAVEN" if not full else "FULDT (%d/%d)" % [W.jobs.mine.size(), Jobs.MAX_JOBS]
		b.disabled = full
		b.custom_minimum_size = Vector2(160, 0)
		var oid: String = o["oid"]
		b.pressed.connect(func(): W.jobs.request_accept(loc_id, oid))
		row.add_child(b)
	_jobs_box.add_child(UiTheme.caption("Dine opgaver (%d/%d)" % [W.jobs.mine.size(), Jobs.MAX_JOBS], UiTheme.PINK))
	if W.jobs.mine.is_empty():
		_jobs_box.add_child(UiTheme.value("Ingen – tag en fra tavlen, eller kald et skib op (H) derude.", UiTheme.MUTED, 14))
	for j: Dictionary in W.jobs.mine:
		var row := HBoxContainer.new()
		_jobs_box.add_child(row)
		var t := UiTheme.value("%s  ·  %d cr  ·  %d:%02d" % [j["title"], int(j["reward"]), int(j["time_left"]) / 60, int(j["time_left"]) % 60], UiTheme.TEXT, 14)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var b := Button.new()
		b.text = "OPGIV"
		var jid: int = j["id"]
		b.pressed.connect(func(): W.jobs.request_abandon(jid))
		row.add_child(b)


## Udstyr: skibets pladser (våben, skjold, motor, gadgets). Vælg en plads, og montér
## en del fra lageret eller køb en ny. Afmonterede dele ligger på lageret og kan
## flyttes til et andet skib eller sælges for halv pris.
var _eq_sel: Array = ["vaaben", 0]


func _refresh_equipment() -> void:
	if _eq_box == null or not visible or loc_id == "" or not Game.has_outfitter(loc_id):
		return
	for c in _eq_box.get_children():
		c.queue_free()
	var cls := Game.local_class()
	var f := Game.fit_for(cls)
	var cdata: Dictionary = Game.ship_data["classes"][cls]
	_eq_box.add_child(UiTheme.caption("%s · %d våben · %d gadgets" % [cdata["name"], Game.slot_count(cls, "vaaben"), Game.slot_count(cls, "gadget")], UiTheme.PINK))
	var open_btn := Button.new()
	open_btn.text = "ÅBN RUMSKIBSMANAGEREN (%s) · flyt, installér og køb Mk I–III" % Game.key_name("ship_manager")
	open_btn.pressed.connect(func(): get_tree().call_group("ship_manager", "open_here", loc_id))
	_eq_box.add_child(open_btn)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	_eq_box.add_child(grid)
	for slot: String in Game.equipment["slots"]:
		var vals: Array = f[slot] if f[slot] is Array else [f[slot]]
		for k in vals.size():
			var title := str(Game.equipment["slots"][slot]) + (" %d" % (k + 1) if slot in Game.equipment["multi"] else "")
			grid.add_child(UiTheme.value(title, UiTheme.MUTED, 13))
			grid.add_child(UiTheme.value(str(Game.part(str(vals[k])).get("name", "– tom –")), UiTheme.TEXT, 13))


## Kort talbeskrivelse af en del (til pladsoversigten).
func _part_stats_old(it: Dictionary) -> String:
	if it.is_empty():
		return ""
	match str(it["slot"]):
		"vaaben":
			if it.get("beam", false):
				return "stråle · %d m" % int(it.get("beam_range", 240))
			var dps := float(it.get("dmg_mult", 1.0)) * int(it.get("bolts", 1)) * int(it.get("salvo", 1)) / (float(it.get("cd_mult", 1.0)) * float(it.get("spin_min", 1.0)))
			return "skade %.1f× · %s" % [dps, {1: "ion", 2: "flak", 3: "krystal"}.get(int(it.get("effect", 0)), "laser")]
		"skjold":
			if it.has("layers"):
				return "%d lag" % int(it["layers"])
			return "skjold %d%% · opladning %d%%" % [int(float(it.get("shield_mult", 1.0)) * 100), int(float(it.get("regen_mult", 1.0)) * 100)]
		"gadget":
			return "aktiv" if it.get("active", false) else "passiv"
	return ""
