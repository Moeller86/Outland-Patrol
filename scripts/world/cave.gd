class_name Cave
extends RefCounted
## Mål og kollision for grotterne (tunneler gennem klippeformationer).
## Tunnelen ligger langs grottens retning; aksen er AXIS_H meter over jorden.

const LENGTH := 170.0
const TUBE_R := 16.0
const OUTER_R := 44.0
const AXIS_H := 20.0


## Grottens koordinatsystem (planet-lokalt): -Z langs tunnelen, Y op.
static func frame(p: PlanetBody, f: Dictionary) -> Transform3D:
	var d: Vector3 = f["dir"]
	return Transform3D(Basis.looking_at(f["heading_dir"], d), d * (p.radius + float(f["base_h"]) + AXIS_H))


## Skub et punkt ud af klippen. Returnerer {pos, hit} (verdenskoordinater).
static func push(p: PlanetBody, pos: Vector3) -> Dictionary:
	var rel := pos - p.position
	var d := rel.normalized()
	for f in p.features:
		if f["type"] != "cave" or d.dot(f["dir"]) < f["cos_reach"]:
			continue
		var fr := frame(p, f)
		var l := fr.affine_inverse() * rel
		if absf(l.z) > LENGTH / 2.0 or l.y < -AXIS_H:
			continue
		var r := Vector2(l.x, l.y).length()
		if r < TUBE_R - 3.0 or r > OUTER_R:
			continue
		# Inde i klippen: ind i tunnelen eller ud på ydersiden, hvad der er nærmest
		var inward := r < (TUBE_R + OUTER_R) * 0.5
		var target_r := TUBE_R - 3.2 if inward else OUTER_R + 0.5
		var v := Vector2(l.x, l.y) / maxf(r, 0.01)
		l.x = v.x * target_r
		l.y = v.y * target_r
		return {"pos": p.position + fr * l, "hit": true}
	return {"pos": pos, "hit": false}


## Er punktet inde i en tunnel?
static func inside(p: PlanetBody, pos: Vector3) -> bool:
	var rel := pos - p.position
	var d := rel.normalized()
	for f in p.features:
		if f["type"] != "cave" or d.dot(f["dir"]) < f["cos_reach"]:
			continue
		var l := frame(p, f).affine_inverse() * rel
		if absf(l.z) < LENGTH / 2.0 and Vector2(l.x, l.y).length() < TUBE_R:
			return true
	return false
