class_name SiteArt
extends RefCounted
## Pixelscener (192 × 108) til fund på planeterne: planetens landskab bagved og
## vraget, ruinen, kapslen eller piratlejren i forgrunden, med dit skib landet ved siden af.

const W := 192
const H := 108


static func texture_for(site: Dictionary, planet: Dictionary) -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	SceneArt._landscape(img, planet)
	var looted: bool = site.get("looted", false)
	match site["kind"]:
		"vrag": _wreck(img, site["mission"] != "", looted)
		"ruin": _ruin(img)
		"forsyning": _pod(img, looted)
		"piratlejr": _camp(img, site.get("cleared", false))
	_ship(img, 150, 84)
	return ImageTexture.create_from_image(img)


static func _r(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	SceneArt._r(img, x, y, w, h, c)


static func _ship(img: Image, x: int, y: int) -> void:
	_r(img, x, y, 26, 5, Color("f4f4ff"))
	_r(img, x + 24, y + 1, 6, 3, Color("f4f4ff"))
	_r(img, x - 2, y + 4, 32, 3, Color("ff4f8b"))
	_r(img, x + 16, y - 3, 7, 3, Color("2ec4d6"))
	_r(img, x - 2, y + 1, 2, 5, Color("ffd23f"))
	_r(img, x + 4, y + 7, 2, 4, Color("5a5f8a"))
	_r(img, x + 20, y + 7, 2, 4, Color("5a5f8a"))


static func _wreck(img: Image, mission: bool, looted: bool) -> void:
	# Krater og brændemærke
	_r(img, 20, 86, 110, 6, Color("3a2d24"))
	_r(img, 30, 84, 90, 3, Color("2a2238"))
	# Skrog på skrå: trinvis "skrå" linje af blokke
	for k in 14:
		var x := 26 + k * 6
		var y := 58 + int(k * 1.6)
		_r(img, x, y, 7, 18, Color("d9d2ff"))
		_r(img, x, y + 6, 7, 3, Color("23203a") if k % 3 else Color("4dffe1"))
		_r(img, x, y + 15, 7, 3, Color("2e6bd6"))
	_r(img, 18, 52, 12, 20, Color("d9d2ff"))       # førerkabine
	_r(img, 20, 55, 8, 4, Color("2ec4d6"))
	_r(img, 112, 74, 14, 10, Color("5a5f8a"))      # knækket bagende
	_r(img, 108, 72, 4, 4, Color("23203a"))
	# Spredte containere
	if not looted:
		for c: Array in [[60, 84, Color("ff7a59")], [74, 88, Color("6bdc4f")], [128, 86, Color("ffd23f")]]:
			_r(img, c[0], c[1], 10, 8, c[2])
			_r(img, c[0], c[1], 10, 1, Color("23203a"))
	# Røg
	for i in 10:
		var c := Color("5a5470") if i % 3 else Color("8a8fb0")
		_r(img, 98 + int(sin(i * 1.3) * 4.0) - i, 56 - i * 5, 6 + i / 2, 4, c)
	# Nødsender
	_r(img, 40, 40, 1, 14, Color("d9d2ff"))
	_r(img, 39, 37, 3, 3, Color("6bdc4f") if mission else Color("ff3b3b"))


static func _ruin(img: Image) -> void:
	var stone := Color("4a3f6b")
	var dark := Color("3a3155")
	var glyph := Color("9fe2ff")
	_r(img, 18, 82, 112, 10, dark)
	_r(img, 22, 80, 104, 3, stone)
	for x in [34, 102]:
		_r(img, x, 30, 12, 52, stone)
		_r(img, x + 5, 36, 2, 40, glyph)
		_r(img, x - 2, 76, 16, 6, dark)
	_r(img, 28, 22, 92, 10, stone)
	for k in 6:
		_r(img, 46 + k * 10, 25, 4, 4, glyph)
	# Væltet søjle
	_r(img, 112, 84, 34, 8, stone)
	_r(img, 114, 86, 30, 1, dark)
	# Svævende krystal
	for y in 14:
		var w := 7 - absi(y - 7)
		_r(img, 74 - w, 44 + y, w * 2, 1, Color("c77dff") if y < 7 else Color("8a4dff"))
	_r(img, 72, 47, 2, 3, Color("e0c8ff"))


static func _pod(img: Image, looted: bool) -> void:
	_r(img, 40, 88, 60, 4, Color("3a2d24"))
	# Kapsel (lidt skæv)
	for k in 6:
		_r(img, 60 + k, 48 + k * 6, 20, 6, Color("e6ecff"))
	_r(img, 62, 44, 16, 5, Color("e6ecff"))
	_r(img, 63, 66, 21, 4, Color("2e6bd6"))
	for x in range(64, 86, 4):
		_r(img, x, 78, 2, 4, Color("ffd23f"))
	_r(img, 70, 32, 1, 12, Color("d9d2ff"))
	_r(img, 69, 30, 3, 3, Color("6bdc4f"))
	if looted:
		_r(img, 68, 56, 8, 8, Color("23203a"))   # åben luge
	# Faldskærm
	_r(img, 96, 86, 40, 4, Color("ff9e3d"))
	_r(img, 100, 84, 30, 2, Color("e6ecff"))


static func _camp(img: Image, cleared: bool) -> void:
	_r(img, 0, 86, W, 8, Color("3a2d24"))
	# Containere
	for c: Array in [[10, 70, Color("3a2350")], [30, 74, Color("8a4a3a")], [20, 60, Color("3a2350")]]:
		_r(img, c[0], c[1], 22, 14, c[2])
		_r(img, c[0], c[1], 22, 1, Color("120a2e"))
		_r(img, c[0] + 10, c[1] + 2, 1, 10, Color("120a2e"))
	# Telte
	for t: Array in [[64, 86], [96, 86]]:
		for y in 14:
			_r(img, t[0] - y, t[1] - 14 + y, y * 2 + 1, 1, Color("ff3b3b"))
		_r(img, t[0] - 2, t[1] - 6, 5, 6, Color("2a1d2a"))
	# Mast med flag
	_r(img, 124, 34, 2, 52, Color("5a5470"))
	_r(img, 126, 34, 14, 9, Color("ff3b3b") if not cleared else Color("5a5470"))
	_r(img, 129, 36, 4, 4, Color("120a2e"))
	_r(img, 123, 31, 4, 3, Color("ff3b3b"))
	# Bål
	_r(img, 84, 88, 6, 3, Color("ff9e3d"))
	_r(img, 86, 85, 2, 3, Color("ffd23f"))
