class_name SceneArt
extends RefCounted
## Tegner menuernes pixelscener (192 × 108) ud fra stedets farver i universe.json:
## himmel, bakker, jord, bygninger, landingsplads med skib, NPC'er og
## planetens kendetegn (træer, kaktus, lava, krystaller, svampe).
## Stationer får deres egen hangarscene med udsigt til planeten.

const W := 192
const H := 108


static func texture_for(loc: Dictionary) -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	if loc.get("base", false):
		_base(img)
	elif loc.get("kind", "") == "outpost":
		_outpost(img, loc)
	elif loc.get("kind", "") == "station":
		_station(img)
	else:
		_planet(img, loc)
	return ImageTexture.create_from_image(img)


static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var rect := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, W, H))
	if rect.size.x > 0 and rect.size.y > 0:
		img.fill_rect(rect, c)


static func _biome(loc: Dictionary, h: float) -> Color:
	for b: Array in loc["biome"]:
		if h <= float(b[0]):
			return Game.col(b[1])
	return Color.WHITE


static func _planet(img: Image, loc: Dictionary) -> void:
	_landscape(img, loc)
	# Bygninger
	var bld: Array = loc["buildings"]
	_r(img, 14, 50, 36, 24, Game.col(bld[0]))
	_r(img, 12, 46, 40, 5, Game.col(bld[0]).darkened(0.2))
	_r(img, 24, 60, 16, 14, Color("2a1d6b"))
	_r(img, 122, 40, 7, 34, Game.col(bld[1]))
	_r(img, 118, 34, 15, 7, Color.WHITE)
	_r(img, 124, 30, 3, 4, Color("ff4fd8"))
	_pad_and_ship(img, 80)
	_npc(img, 36, 82, Game.col(bld[0]).lightened(0.2))
	_npc(img, 146, 82, Game.col(bld[1]))
	_npc(img, 52, 82, Color("ffd23f"))


static func _pad_and_ship(img: Image, y: int) -> void:
	_r(img, 60, y, 76, 8, Color("5a5f8a"))
	_r(img, 60, y - 1, 76, 2, Color("ffcf3d"))
	_r(img, 94, y + 2, 8, 4, Color("ffcf3d"))
	_r(img, 84, y - 10, 28, 6, Color("f4f4ff"))
	_r(img, 110, y - 8, 6, 3, Color("f4f4ff"))
	_r(img, 80, y - 6, 36, 3, Color("ff4f8b"))
	_r(img, 100, y - 13, 7, 3, Color("2ec4d6"))
	_r(img, 80, y - 9, 2, 5, Color("ffd23f"))
	_r(img, 114, y - 9, 2, 5, Color("ffd23f"))
	_r(img, 77, y - 7, 3, 2, Color("ff9e3d"))


static func _npc(img: Image, x: int, y: int, body: Color) -> void:
	_r(img, x, y, 4, 4, Color("ffd2a1"))
	_r(img, x - 1, y + 4, 6, 6, body)
	_r(img, x, y + 10, 1, 3, Color("2a1d6b"))
	_r(img, x + 3, y + 10, 1, 3, Color("2a1d6b"))


static func _station(img: Image) -> void:
	_r(img, 0, 0, W, H, Color("1e1450"))
	_r(img, 18, 10, 156, 48, Color("120a2e"))
	var star_cols := [Color.WHITE, Color("9fe2ff"), Color("ff9ed2")]
	for i in 46:
		img.set_pixel(18 + (i * 37) % 154, 10 + (i * 23) % 47, star_cols[i % 3])
	for y in range(-16, 17):
		for x in range(-16, 17):
			if x * x + y * y > 256:
				continue
			var n := sin(x * 0.7 + y * 1.3) + sin(x * 0.31 - y * 0.6)
			var c := Color("1a6b3a") if x + y > 12 else (Color("2ed3d6") if n > 0.6 else (Color("6bdc4f") if n > -0.4 else Color("2fa04f")))
			img.set_pixel(138 + x, 34 + y, c)
	for x in range(18, 175, 39):
		_r(img, x - 1, 10, 3, 48, Color("4b3aa8"))
	_r(img, 16, 8, 160, 3, Color("4b3aa8"))
	_r(img, 16, 57, 160, 3, Color("4b3aa8"))
	for x in range(10, W, 30):
		_r(img, x, 2, 10, 2, Color("fff3b0"))
	_r(img, 0, 74, W, H - 74, Color("2a1d6b"))
	for x in range(0, W, 8):
		_r(img, x, 74, 8, 3, Color("ffd23f") if (x / 8) % 2 else Color("120a2e"))
	for x in range(4, W, 24):
		_r(img, x, 90, 14, 1, Color("3a2a85"))
	for c: Array in [[6, 63, Color("ff9e3d")], [18, 63, Color("4dd0ff")], [12, 52, Color("6bdc4f")], [168, 63, Color("4dd0ff")], [178, 63, Color("ff9e3d")]]:
		_r(img, c[0], c[1], 11, 11, c[2])
		_r(img, c[0], c[1], 11, 1, Color("120a2e"))
		_r(img, c[0], c[1], 1, 11, Color("120a2e"))
		_r(img, c[0] + 5, c[1] + 2, 1, 7, Color("120a2e"))
	_pad_and_ship(img, 76)
	_npc(img, 40, 80, Color("ffd23f"))
	_npc(img, 150, 80, Color("7b4dff"))
	_npc(img, 60, 80, Color("ff4f8b"))


static func _base(img: Image) -> void:
	# Hangarbugt i Concords hvide og blå farver med udsigt gennem porten.
	_r(img, 0, 0, W, H, Color("2e6bd6"))
	_r(img, 0, 0, W, 6, Color("e6ecff"))
	_r(img, 24, 10, 144, 50, Color("120a2e"))
	for i in 40:
		img.set_pixel(24 + (i * 37) % 143, 10 + (i * 23) % 49, [Color.WHITE, Color("9fe2ff"), Color("ff9ed2")][i % 3])
	for y in range(-12, 13):
		for x in range(-12, 13):
			if x * x + y * y <= 144:
				img.set_pixel(60 + x, 34 + y, Color("ff9e3d") if x + y < 4 else Color("c96b4a"))
	_r(img, 20, 8, 152, 3, Color("ffd23f"))
	_r(img, 20, 58, 152, 3, Color("ffd23f"))
	_r(img, 20, 8, 4, 53, Color("ffd23f"))
	_r(img, 168, 8, 4, 53, Color("ffd23f"))
	for x in range(30, 166, 12):
		_r(img, x, 12, 6, 1, Color("4dffe1"))
	# Concord-emblem
	for a in 24:
		var t := a / 24.0 * TAU
		img.set_pixel(96 + int(cos(t) * 7.0), 0 + 3 + int(sin(t) * 2.0), Color("ffd23f"))
	_r(img, 0, 70, W, H - 70, Color("e6ecff"))
	_r(img, 0, 70, W, 3, Color("ffd23f"))
	for x in range(0, W, 16):
		_r(img, x, 88, 8, 2, Color("9fb4e8"))
	_r(img, 4, 62, 14, 10, Color("ff7a59"))
	_r(img, 172, 60, 16, 12, Color("4dd0ff"))
	_pad_and_ship(img, 82)
	_npc(img, 38, 84, Color("2e6bd6"))
	_npc(img, 150, 84, Color("2e6bd6"))
	_npc(img, 56, 84, Color("ffd23f"))


## Himmel, bakker, jord og planetens kendetegn (uden by).
static func _landscape(img: Image, loc: Dictionary) -> void:
	var sky := Game.col(loc["sky"])
	var bands := [sky.darkened(0.25), sky.darkened(0.1), sky, sky.lightened(0.25)]
	for i in 4:
		_r(img, 0, i * 15, W, 15, bands[i])
	for y in range(0, 60, 15):
		for x in range(int(y / 15.0) % 2, W, 2):
			img.set_pixel(x, y + 14, bands[mini(3, y / 15 + 1)])
	var decor: String = loc.get("decor", "tree")
	# Sol eller nordlys
	if decor == "crystal":
		for x in W:
			var y := 12 + int(sin(x * 0.06) * 6.0 + sin(x * 0.17) * 2.0)
			_r(img, x, y, 1, 3 if x % 5 else 6, Color("4dff9e") if x % 3 else Color("c77dff"))
	else:
		var sun := Color("ffd23f") if decor != "mushroom" else Color("4dffe1")
		_r(img, 150, 10, 14, 14, sun)
		_r(img, 148, 13, 18, 8, sun)
		_r(img, 153, 8, 8, 18, sun)
	# Skyer
	var cloud := Game.col(loc["cloud"])
	for c: Array in [[20, 14, 22], [70, 22, 30], [118, 8, 18]]:
		_r(img, c[0], c[1], c[2], 4, cloud)
		_r(img, c[0] + 4, c[1] - 3, c[2] - 10, 3, cloud)
	# Bakker, jord og prikker
	var far := _biome(loc, 60)
	var ground := _biome(loc, 20)
	var dots := _biome(loc, 3)
	for x in W:
		var h := 52 + int(sin(x * 0.07) * 5.0 + sin(x * 0.19 + 1.0) * 3.0)
		_r(img, x, h, 1, H - h, far)
	_r(img, 0, 70, W, H - 70, ground)
	for x in range(0, W, 6):
		_r(img, x + (0 if x % 12 else 2), 76 + (14 if x % 18 == 0 else 6), 3, 1, dots)
	# Kendetegn
	match decor:
		"tree":
			for x in [8, 176, 108]:
				_r(img, x, 60, 2, 12, Color("8a5a3c"))
				_r(img, x - 5, 56, 12, 5, Color("2fa04f"))
				_r(img, x - 3, 53, 8, 3, Color("2fa04f"))
		"cactus":
			for x in [10, 176, 140]:
				_r(img, x, 58, 3, 14, Color("3fae6a"))
				_r(img, x - 3, 62, 3, 2, Color("3fae6a"))
				_r(img, x - 3, 59, 2, 4, Color("3fae6a"))
				_r(img, x + 3, 64, 3, 2, Color("3fae6a"))
				_r(img, x + 4, 61, 2, 4, Color("3fae6a"))
		"lava":
			_r(img, 0, 96, 54, 4, Color("ff4f1f"))
			_r(img, 140, 92, 52, 5, Color("ff4f1f"))
			_r(img, 8, 97, 10, 1, Color("ffd23f"))
			_r(img, 150, 93, 14, 1, Color("ffd23f"))
			for x in range(162, 184):
				var top := 30 + absi(x - 173) * 2
				_r(img, x, top, 1, 70 - top, Color("2a1d2a"))
			_r(img, 171, 26, 4, 4, Color("ff9e3d"))
			_r(img, 168, 18, 6, 4, Color("9a8a9a"))
			_r(img, 172, 12, 8, 5, Color("9a8a9a"))
		"crystal":
			for c: Array in [[140, 72], [8, 90], [180, 94]]:
				_r(img, c[0], c[1] - 6, 2, 6, Color("c77dff"))
				_r(img, c[0] + 2, c[1] - 9, 2, 9, Color("c77dff"))
				_r(img, c[0] + 4, c[1] - 5, 2, 5, Color("c77dff"))
				_r(img, c[0] + 2, c[1] - 9, 1, 3, Color("e0c8ff"))
		"mushroom":
			for m: Array in [[8, 64, Color("4dffe1")], [170, 62, Color("ff4f8b")], [144, 66, Color("ffd23f")]]:
				_r(img, m[0] + 3, m[1], 2, 12, Color("ffe8ff"))
				_r(img, m[0], m[1] - 4, 8, 4, m[2])
				_r(img, m[0] + 1, m[1] - 6, 6, 2, m[2])


## Mindre steder på planeterne: landskabet bagved og stedets kendetegn foran.
static func _outpost(img: Image, loc: Dictionary) -> void:
	_landscape(img, loc)
	match str(loc.get("style", "town")):
		"mine":
			for x in [20, 150]:
				for y in range(26, 72, 6):
					_r(img, x, y, 12, 1, Color("ffd23f"))
				_r(img, x, 26, 1, 46, Color("ffd23f"))
				_r(img, x + 11, 26, 1, 46, Color("ffd23f"))
				_r(img, x + 4, 20, 4, 6, Color("8a4a3a"))
				_r(img, x + 5, 16, 2, 4, Color("ff3b3b"))
			for c: Array in [[40, 66, 18], [56, 70, 12]]:
				for y in mini(8, int(c[2]) / 2):
					_r(img, c[0] + y, c[1] + y, c[2] - y * 2, 1, Color("ffe14d") if loc.get("decor", "") != "crystal" else Color("c77dff"))
			_r(img, 120, 46, 10, 26, Color("e6ecff"))
			_r(img, 132, 50, 10, 22, Color("e6ecff"))
			_r(img, 120, 56, 22, 2, Color("ffd23f"))
		"farm":
			for k in 3:
				var x := 14 + k * 26
				for y in 10:
					var w := 22 - absi(y - 2) * 2
					_r(img, x + (22 - w) / 2, 58 + y, w, 1, Color("9fe2ff") if y % 3 else Color("e6ecff"))
			for k in 6:
				_r(img, 140, 74 + k * 4, 52, 2, Color("6bdc4f") if loc.get("decor", "") != "mushroom" else Color("ff4f8b"))
			_r(img, 160, 34, 12, 8, Color("4dd0ff"))
			_r(img, 162, 42, 1, 26, Color("8a8fb0"))
			_r(img, 169, 42, 1, 26, Color("8a8fb0"))
		"research":
			for y in 12:
				var w := 28 - absi(y - 6) * 3
				_r(img, 24 + (28 - w) / 2, 30 + y, w, 1, Color("e6ecff"))
			_r(img, 37, 42, 3, 28, Color("8a8fb0"))
			_r(img, 38, 26, 1, 6, Color("4dffe1"))
			for c: Array in [[132, 62, 14], [156, 66, 10]]:
				for y in c[2]:
					var w2 := int(sqrt(float(c[2] * c[2] - (c[2] - y) * (c[2] - y)))) * 2
					_r(img, c[0] - w2 / 2, c[1] + y - c[2] + 6, w2, 1, Color("9fe2ff"))
			_r(img, 120, 66, 50, 8, Color("e6ecff"))
			_r(img, 120, 68, 50, 2, Color("2ec4d6"))
		"military":
			for x in [14, 40]:
				_r(img, x, 58, 22, 14, Color("5a5f8a"))
				_r(img, x - 1, 54, 24, 4, Color("2e6bd6"))
				_r(img, x + 3, 62, 16, 2, Color("ffe08a"))
			_r(img, 150, 26, 2, 46, Color("e6ecff"))
			_r(img, 152, 30, 14, 9, Color("2e6bd6"))
			_r(img, 156, 32, 6, 5, Color("ffd23f"))
			_r(img, 149, 23, 4, 3, Color("4d8bff"))
		_:
			var bld: Array = loc["buildings"]
			for k in 4:
				var x := 10 + k * 22
				_r(img, x, 56 + (k % 2) * 4, 16, 18, Game.col(bld[k % bld.size()]))
				_r(img, x - 1, 52 + (k % 2) * 4, 18, 4, Game.col(bld[k % bld.size()]).darkened(0.3))
				_r(img, x + 5, 64 + (k % 2) * 4, 5, 10, Color("2a1d6b"))
	_pad_and_ship(img, 80)
	_npc(img, 110, 84, Color("ffd23f"))
