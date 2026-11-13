class_name TerrainNoise
extends RefCounted
## Samme terrænstøj som browser-demoen (1:1-port), så planeterne får de samme
## bløde kontinenter: sinus-baseret hash, trilineær værdistøj og 4 oktaver fBm.


static func hash3(x: float, y: float, z: float) -> float:
	var s := sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
	return s - floorf(s)


## Værdistøj i 0..1 med blød (smoothstep) interpolation.
static func vnoise(x: float, y: float, z: float) -> float:
	var xi := floorf(x)
	var yi := floorf(y)
	var zi := floorf(z)
	var xf := x - xi
	var yf := y - yi
	var zf := z - zi
	var u := xf * xf * (3.0 - 2.0 * xf)
	var v := yf * yf * (3.0 - 2.0 * yf)
	var w := zf * zf * (3.0 - 2.0 * zf)
	var c000 := hash3(xi, yi, zi)
	var c100 := hash3(xi + 1.0, yi, zi)
	var c010 := hash3(xi, yi + 1.0, zi)
	var c110 := hash3(xi + 1.0, yi + 1.0, zi)
	var c001 := hash3(xi, yi, zi + 1.0)
	var c101 := hash3(xi + 1.0, yi, zi + 1.0)
	var c011 := hash3(xi, yi + 1.0, zi + 1.0)
	var c111 := hash3(xi + 1.0, yi + 1.0, zi + 1.0)
	var x00 := c000 + (c100 - c000) * u
	var x10 := c010 + (c110 - c010) * u
	var x01 := c001 + (c101 - c001) * u
	var x11 := c011 + (c111 - c011) * u
	var y0 := x00 + (x10 - x00) * v
	var y1 := x01 + (x11 - x01) * v
	return y0 + (y1 - y0) * w


## 4 oktaver fraktal støj, normaliseret til 0..1 (typisk 0,2–0,8).
static func fbm(x: float, y: float, z: float) -> float:
	var a := 0.5
	var f := 1.0
	var s := 0.0
	var t := 0.0
	for i in 4:
		s += a * vnoise(x * f, y * f, z * f)
		t += a
		a *= 0.5
		f *= 2.03
	return s / t
