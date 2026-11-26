class_name MunchiesSim
extends RefCounted
## Pure simulation for Munchies. No scene tree, no physics nodes.
## Phase 2: five tiers, 160 m hand-laid map, suction + claims, speed curve.

const START_RADIUS := 1.0
const START_MASS := 1.0
const SCORE_SCALE := 10.0

const SPEED_BASE := 14.0
const SPEED_FLOOR := 0.32
const STEER_TAU := 0.15

const PROP_EAT_RATIO := 0.95
const PROP_SUCTION_MULT := 2.0
const PROP_CONSUME_MULT := 0.45
const PROP_PULL_ACCEL := 28.0
const PROP_PULL_MAX_SPEED := 18.0

## Tier radii (m) from the plan table.
const TIER_RADIUS := [0.25, 0.55, 1.30, 3.20, 6.50]
const TIER0_RADIUS := 0.25
const TIER1_RADIUS := 0.55
const TIER2_RADIUS := 1.30
const TIER3_RADIUS := 3.20
const TIER4_RADIUS := 6.50

## Full map is 160 × 160 m → half-extent 80.
const MAP_HALF_DEFAULT := 80.0

## Corner spawn pads (outside the heaviest food, path inward).
const SPAWN_PADS := [
	Vector2(-55.0, -55.0),
	Vector2(55.0, -55.0),
	Vector2(-55.0, 55.0),
	Vector2(55.0, 55.0),
]

## Event kinds returned by step().
const EVENT_SWALLOWED := &"Swallowed"
const EVENT_SUCKED := &"Sucked"

var tick: int = 0
var elapsed: float = 0.0
var map_half: float = MAP_HALF_DEFAULT
var holes: Array = [] ## Array of Dictionary
var objects: Array = [] ## Array of Dictionary
var parks: Array = [] ## Array of {center: Vector2, radius: float} for drawing
var roads: Array = [] ## Array of Rect2 in meters for drawing
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


static func make_hole(id: int, x: float, y: float) -> Dictionary:
	return {
		"id": id,
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"mass": START_MASS,
		"radius": START_RADIUS,
		"score": roundi(START_MASS * SCORE_SCALE),
		"alive": true,
	}


static func make_prop(id: int, x: float, y: float, tier: int, radius: float) -> Dictionary:
	return {
		"id": id,
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"radius": radius,
		"tier": tier,
		"claimed_by": -1,
		"alive": true,
	}


func setup_empty(world_seed: int = 1, half: float = 30.0) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = half
	_next_id = 1
	holes.clear()
	objects.clear()
	parks.clear()
	roads.clear()
	holes.append(make_hole(_alloc_id(), 0.0, 0.0))


## Compact Phase 1 layout kept for regression checks.
func setup_phase1(world_seed: int = 1) -> void:
	setup_empty(world_seed, 30.0)
	_scatter_props(0, TIER0_RADIUS, 80, Vector2(0, 0), 12.0, START_RADIUS * 2.5)
	_scatter_props(0, TIER0_RADIUS, 40, Vector2(14, -10), 8.0, 0.0)
	_scatter_props(1, TIER1_RADIUS, 36, Vector2(-8, 10), 14.0, 0.0)
	_scatter_props(1, TIER1_RADIUS, 20, Vector2(16, 12), 10.0, 0.0)
	for i in 5:
		var a: float = _rng.randf() * TAU
		var d: float = 5.0 + _rng.randf() * 5.0
		objects.append(make_prop(_alloc_id(), cos(a) * d, sin(a) * d, 1, 1.15))


## Phase 2: 160 m hand-laid map, five tiers, four corner spawns.
func setup_phase2(world_seed: int = 42, spawn_pad: int = 0) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = MAP_HALF_DEFAULT
	_next_id = 1
	holes.clear()
	objects.clear()
	parks.clear()
	roads.clear()

	var pad: Vector2 = SPAWN_PADS[clampi(spawn_pad, 0, SPAWN_PADS.size() - 1)]
	holes.append(make_hole(_alloc_id(), pad.x, pad.y))

	# Parks: center + two side parks (dense tier 0 / 1).
	parks = [
		{"center": Vector2(0, 0), "radius": 18.0},
		{"center": Vector2(28, -22), "radius": 14.0},
		{"center": Vector2(-30, 24), "radius": 14.0},
	]

	# Road / lot bands (cosmetic + tier-2 placement guides).
	roads = [
		Rect2(-70, -6, 140, 12),
		Rect2(-6, -70, 12, 140),
		Rect2(-50, 30, 40, 10),
		Rect2(20, -45, 35, 10),
		Rect2(-40, -50, 10, 35),
		Rect2(35, 20, 10, 40),
	]

	# --- Tier 0 litter (140): packed in parks so every spawn can eat within a second ---
	_scatter_props(0, TIER0_RADIUS, 55, Vector2(0, 0), 16.0, 3.0)
	_scatter_props(0, TIER0_RADIUS, 42, Vector2(28, -22), 12.0, 2.0)
	_scatter_props(0, TIER0_RADIUS, 43, Vector2(-30, 24), 12.0, 2.0)
	# Trail of litter from each spawn inward so early game is never empty.
	_scatter_along_line(0, TIER0_RADIUS, 12, Vector2(-55, -55), Vector2(-20, -20))
	_scatter_along_line(0, TIER0_RADIUS, 12, Vector2(55, -55), Vector2(20, -20))
	_scatter_along_line(0, TIER0_RADIUS, 12, Vector2(-55, 55), Vector2(-20, 20))
	_scatter_along_line(0, TIER0_RADIUS, 12, Vector2(55, 55), Vector2(20, 20))

	# --- Tier 1 street props (70): parks + near roads ---
	_scatter_props(1, TIER1_RADIUS, 22, Vector2(0, 0), 20.0, 4.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(28, -22), 14.0, 3.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(-30, 24), 14.0, 3.0)
	_scatter_props(1, TIER1_RADIUS, 16, Vector2(0, 0), 45.0, 8.0)

	# --- Tier 2 vehicles (28): roads and lots ---
	_place_on_roads(2, TIER2_RADIUS, 28)

	# --- Tier 3 small buildings (16): edges with path gaps ---
	_place_edge_landmarks(3, TIER3_RADIUS, [
		Vector2(-68, -20), Vector2(-68, 20),
		Vector2(68, -25), Vector2(68, 15),
		Vector2(-25, -68), Vector2(20, -68),
		Vector2(-15, 68), Vector2(25, 68),
		Vector2(-50, -60), Vector2(50, -60),
		Vector2(-50, 60), Vector2(50, 60),
		Vector2(-60, 0), Vector2(60, 5),
		Vector2(0, -62), Vector2(5, 62),
	])

	# --- Tier 4 blocks (6): far corners / edges as landmarks, not walls ---
	_place_edge_landmarks(4, TIER4_RADIUS, [
		Vector2(-70, -70),
		Vector2(70, -70),
		Vector2(-70, 70),
		Vector2(70, 70),
		Vector2(0, -72),
		Vector2(0, 72),
	])

	_clear_spawn_pads()


func _alloc_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _scatter_props(
	tier: int,
	radius: float,
	count: int,
	center: Vector2,
	spread: float,
	clear_radius: float
) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 8:
		attempts += 1
		var ang: float = _rng.randf() * TAU
		var dist: float = sqrt(_rng.randf()) * spread
		var x: float = center.x + cos(ang) * dist
		var y: float = center.y + sin(ang) * dist
		if clear_radius > 0.0 and Vector2(x, y).length() < clear_radius:
			continue
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))
		placed += 1


func _scatter_along_line(tier: int, radius: float, count: int, a: Vector2, b: Vector2) -> void:
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var p: Vector2 = a.lerp(b, t)
		p.x += _rng.randf_range(-1.5, 1.5)
		p.y += _rng.randf_range(-1.5, 1.5)
		p.x = clampf(p.x, -map_half + radius, map_half - radius)
		p.y = clampf(p.y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), p.x, p.y, tier, radius))


func _place_on_roads(tier: int, radius: float, count: int) -> void:
	if roads.is_empty():
		_scatter_props(tier, radius, count, Vector2.ZERO, 50.0, 10.0)
		return
	for i in count:
		var road: Rect2 = roads[i % roads.size()]
		var x: float = _rng.randf_range(road.position.x + radius, road.position.x + road.size.x - radius)
		var y: float = _rng.randf_range(road.position.y + radius, road.position.y + road.size.y - radius)
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))


func _place_edge_landmarks(tier: int, radius: float, positions: Array) -> void:
	for pos_v in positions:
		var pos: Vector2 = pos_v
		pos.x = clampf(pos.x, -map_half + radius, map_half - radius)
		pos.y = clampf(pos.y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), pos.x, pos.y, tier, radius))


func _clear_spawn_pads() -> void:
	## Drop props that sit on a spawn pad so a corner start is free.
	var keep: Array = []
	for prop_v in objects:
		var prop: Dictionary = prop_v
		var p := Vector2(float(prop["x"]), float(prop["y"]))
		var blocked := false
		for pad_v in SPAWN_PADS:
			var pad: Vector2 = pad_v
			if p.distance_to(pad) < START_RADIUS * 3.0 + float(prop["radius"]):
				blocked = true
				break
		if not blocked:
			keep.append(prop)
	objects = keep


## inputs_by_hole: Dictionary[int, Vector2] with each component in [-1, 1].
## Returns Array of event Dictionaries: {kind, hole_id, prop_id?, mass_gained?, tier?, x?, y?, radius?}
func step(inputs_by_hole: Dictionary, dt: float) -> Array:
	var events: Array = []
	if dt <= 0.0:
		return events

	tick += 1
	elapsed += dt

	for hole_v in holes:
		var hole: Dictionary = hole_v
		if not bool(hole["alive"]):
			continue
		var input: Vector2 = inputs_by_hole.get(int(hole["id"]), Vector2.ZERO) as Vector2
		_steer_hole(hole, input, dt)
		_clamp_hole(hole)

	_update_props(dt, events)
	return events


func _steer_hole(hole: Dictionary, input: Vector2, dt: float) -> void:
	var radius: float = float(hole["radius"])
	var speed: float = SPEED_BASE * clampf(START_RADIUS / radius, SPEED_FLOOR, 1.0)
	var desired := Vector2.ZERO
	var mag: float = input.length()
	if mag > 0.0001:
		# Keyboard vectors are normalized by the view; stick magnitude scales speed.
		desired = input.normalized() * speed * minf(mag, 1.0)

	var vx: float = float(hole["vx"])
	var vy: float = float(hole["vy"])
	var blend: float = 1.0 - exp(-dt / STEER_TAU)
	vx += (desired.x - vx) * blend
	vy += (desired.y - vy) * blend
	hole["vx"] = vx
	hole["vy"] = vy
	hole["x"] = float(hole["x"]) + vx * dt
	hole["y"] = float(hole["y"]) + vy * dt


func _clamp_hole(hole: Dictionary) -> void:
	var r: float = float(hole["radius"]) * 0.5
	var min_c: float = -map_half + r
	var max_c: float = map_half - r
	var x: float = float(hole["x"])
	var y: float = float(hole["y"])
	var vx: float = float(hole["vx"])
	var vy: float = float(hole["vy"])

	if x < min_c:
		x = min_c
		if vx < 0.0:
			vx = 0.0
	elif x > max_c:
		x = max_c
		if vx > 0.0:
			vx = 0.0

	if y < min_c:
		y = min_c
		if vy < 0.0:
			vy = 0.0
	elif y > max_c:
		y = max_c
		if vy > 0.0:
			vy = 0.0

	hole["x"] = x
	hole["y"] = y
	hole["vx"] = vx
	hole["vy"] = vy


func _alive_holes() -> Array:
	var out: Array = []
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if bool(hole["alive"]):
			out.append(hole)
	return out


func _update_props(dt: float, events: Array) -> void:
	var alive: Array = _alive_holes()
	if alive.is_empty():
		return

	var to_remove: Array = []

	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue

		var px: float = float(prop["x"])
		var py: float = float(prop["y"])
		var pr: float = float(prop["radius"])

		# Closest qualifying hole claims; others ignore a claimed prop.
		var best_hole: Dictionary = {}
		var best_dist: float = INF
		for hole_v in alive:
			var hole: Dictionary = hole_v
			var hr: float = float(hole["radius"])
			if pr > hr * PROP_EAT_RATIO:
				continue
			var dx: float = float(hole["x"]) - px
			var dy: float = float(hole["y"]) - py
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist < hr * PROP_SUCTION_MULT and dist < best_dist:
				best_dist = dist
				best_hole = hole

		if best_hole.is_empty():
			# Too big for everyone nearby, or out of suction: clear claim, no pull.
			prop["claimed_by"] = -1
			prop["vx"] = 0.0
			prop["vy"] = 0.0
			continue

		var hole_id: int = int(best_hole["id"])
		var claimed: int = int(prop["claimed_by"])
		if claimed != -1 and claimed != hole_id:
			# Another hole already owns it — only the claimer may pull.
			var still_claimer := false
			for hole_v2 in alive:
				var h2: Dictionary = hole_v2
				if int(h2["id"]) == claimed:
					var hr2: float = float(h2["radius"])
					if pr <= hr2 * PROP_EAT_RATIO:
						var ddx: float = float(h2["x"]) - px
						var ddy: float = float(h2["y"]) - py
						var d2: float = sqrt(ddx * ddx + ddy * ddy)
						if d2 < hr2 * PROP_SUCTION_MULT:
							best_hole = h2
							best_dist = d2
							hole_id = claimed
							still_claimer = true
					break
			if not still_claimer:
				prop["claimed_by"] = hole_id
		else:
			prop["claimed_by"] = hole_id

		var hx: float = float(best_hole["x"])
		var hy: float = float(best_hole["y"])
		var hr: float = float(best_hole["radius"])
		var eat_limit: float = hr * PROP_EAT_RATIO
		var consume_r: float = hr * PROP_CONSUME_MULT

		if best_dist > 0.0001:
			var nx: float = (hx - px) / best_dist
			var ny: float = (hy - py) / best_dist
			var pvx: float = float(prop["vx"]) + nx * PROP_PULL_ACCEL * dt
			var pvy: float = float(prop["vy"]) + ny * PROP_PULL_ACCEL * dt
			var speed: float = sqrt(pvx * pvx + pvy * pvy)
			if speed > PROP_PULL_MAX_SPEED:
				var s: float = PROP_PULL_MAX_SPEED / speed
				pvx *= s
				pvy *= s
			prop["vx"] = pvx
			prop["vy"] = pvy
			prop["x"] = px + pvx * dt
			prop["y"] = py + pvy * dt
			events.append({"kind": EVENT_SUCKED, "hole_id": hole_id, "prop_id": prop["id"]})

		var cdx: float = hx - float(prop["x"])
		var cdy: float = hy - float(prop["y"])
		var cdist: float = sqrt(cdx * cdx + cdy * cdy)
		if cdist < consume_r and pr <= eat_limit:
			var mass_gain: float = pr * pr
			best_hole["mass"] = float(best_hole["mass"]) + mass_gain
			best_hole["radius"] = sqrt(float(best_hole["mass"]))
			best_hole["score"] = roundi(float(best_hole["mass"]) * SCORE_SCALE)
			prop["alive"] = false
			to_remove.append(prop)
			events.append({
				"kind": EVENT_SWALLOWED,
				"hole_id": hole_id,
				"prop_id": prop["id"],
				"mass_gained": mass_gain,
				"tier": prop["tier"],
				"x": prop["x"],
				"y": prop["y"],
				"radius": pr,
			})

	for dead in to_remove:
		objects.erase(dead)


func player_hole() -> Dictionary:
	return holes[0] as Dictionary


func alive_prop_count() -> int:
	var n := 0
	for p in objects:
		if p["alive"]:
			n += 1
	return n


func count_by_tier() -> Dictionary:
	var counts := {0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	for p in objects:
		if not p["alive"]:
			continue
		var t: int = int(p["tier"])
		counts[t] = int(counts.get(t, 0)) + 1
	return counts
