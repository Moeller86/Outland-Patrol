class_name W
extends RefCounted
## Genveje til verdens-systemerne, så de kan finde hinanden uden lange node-stier.
## Sættes af main.gd, når verden bygges.

static var universe: Universe
static var fx: Effects
static var bolts: Bolts
static var asteroids: AsteroidField
static var pickups: Pickups
static var pirates: Pirates
static var freighters: Freighters
static var missions: Missions
static var sites: Sites
static var weather: Weather
static var missiles: Missiles
static var patrols: Patrols
static var bases: PlayerBases
static var bombs: Bombs
static var assault: Assault
static var traffic: Traffic
static var jobs: Jobs
static var ships: Dictionary = {}       ## peer-id -> Ship (samme ordbog som i main.gd)
static var local_ship: Ship
## Markering sat på kortet: {pos, label, system} eller tom.
static var waypoint: Dictionary = {}


static func is_server() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.get_multiplayer().multiplayer_peer != null and tree.get_multiplayer().is_server()


## Skibe, der flyver frit i rummet (kan angribes og samle op).
static func active_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for id: int in ships:
		var s: Ship = ships[id]
		if is_instance_valid(s) and not s.dead and s.state == Ship.State.FLY:
			out.append(s)
	return out


## Rute gennem jump gates: den gate i `from_sys`, der fører nærmest mod `to_sys` (tom hvis samme system).
static func gate_towards(from_sys: String, to_sys: String) -> Dictionary:
	if from_sys == to_sys or universe == null:
		return {}
	# Bredde-først-søgning over systemerne
	var first := {}          # system -> første gate fra from_sys
	var queue: Array[String] = [from_sys]
	var seen := {from_sys: true}
	while not queue.is_empty():
		var sys: String = queue.pop_front()
		for gid: String in universe.gates:
			var g: Dictionary = universe.gates[gid]
			if g["system"] != sys:
				continue
			var dest: String = universe.gates[g["to"]]["system"]
			if seen.has(dest):
				continue
			seen[dest] = true
			first[dest] = g if sys == from_sys else first[sys]
			if dest == to_sys:
				return first[dest]
			queue.append(dest)
	return {}
