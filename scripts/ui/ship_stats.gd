class_name ShipStats
extends RefCounted
## Tekst og bjælker, der beskriver en skibsklasse (til titelskærm og værft).


## En kort linje med de vigtigste tal.
static func line(d: Dictionary) -> String:
	return "Fart %d · drej %.1f · skjold %d · panser %d %% · last %+d · %d kanoner · %d missiler" % [
		int(d["max_speed"]), float(d["turn"]), int(d["shield"]), roundi(100.0 / float(d["armor"])),
		int(d.get("cargo_bonus", 0)), (d["guns"] as Array).size(), int(d.get("missiles", 8))]


## Værdier 0..1 til bjælker: [navn, værdi]
static func bars(d: Dictionary) -> Array:
	return [
		["Fart", (float(d["max_speed"]) - 40.0) / 40.0],
		["Manøvre", (float(d["turn"]) - 1.2) / 2.0],
		["Holdbarhed", (float(d["shield"]) / 90.0 + 0.6 / float(d["armor"])) / 2.0],
		["Ildkraft", (d["guns"] as Array).size() * (0.16 / float(d["fire_cooldown"])) / 4.0],
		["Last", (12.0 + float(d.get("cargo_bonus", 0))) / 24.0],
	]
