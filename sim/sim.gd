class_name MunchiesSim
extends RefCounted
## Pure simulation for Munchies. No scene tree, no physics nodes.
## Phase 4: MatchConfig modes, 2–4 holes, player swallow, respawn, match end.

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

const PLAYER_EAT_RATIO := 0.80
const PLAYER_SUCTION_MULT := 1.35
const PLAYER_CONSUME_MULT := 0.55
const PLAYER_PULL_ACCEL := 16.0
const PLAYER_MASS_TRANSFER := 0.60

const HOLE_RESPAWN_DELAY := 2.0
const PROP_RESPAWN_DELAY := 8.0

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

const HOLE_RING_COLORS := [
	Color(0.30, 0.85, 0.78),
	Color(0.95, 0.55, 0.35),
	Color(0.70, 0.55, 0.95),
	Color(0.95, 0.85, 0.35),
]

## Event kinds returned by step().
const EVENT_SWALLOWED := &"Swallowed"
const EVENT_SUCKED := &"Sucked"
const EVENT_ELIMINATED := &"Eliminated"
const EVENT_RESPAWNED := &"Respawned"
const EVENT_MATCH_ENDED := &"MatchEnded"

var tick: int = 0
var elapsed: float = 0.0
var map_half: float = MAP_HALF_DEFAULT
var holes: Array = [] ## Array of Dictionary
var objects: Array = [] ## Array of Dictionary
var parks: Array = [] ## Array of {center: Vector2, radius: float} for drawing
var roads: Array = [] ## Array of Rect2 in meters for drawing
var config: MatchConfig = null
var match_over: bool = false
var match_end_reason: String = ""
var winner_id: int = -1
var rankings: Array = [] ## Array of hole ids best→worst

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
var _pending_hole_respawns: Array = [] ## {id, at}
var _pending_prop_spawns: Array = [] ## {tier, at, x, y}


static func make_hole(id: int, x: float, y: float, is_bot: bool = false, slot: int = 0) -> Dictionary:
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
		"score_changed_tick": 0,
		"is_bot": is_bot,
		"slot": slot,
		"name": ("Bot %d" % (slot + 1)) if is_bot else "You",
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
	_pending_hole_respawns.clear()
	_pending_prop_spawns.clear()
	match_over = false
	match_end_reason = ""
	winner_id = -1
	rankings.clear()
	if config == null:
		config = MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	holes.append(make_hole(_alloc_id(), 0.0, 0.0, false, 0))


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
	config = MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 1)
	_layout_phase2_map(world_seed)
	var pad: Vector2 = SPAWN_PADS[clampi(spawn_pad, 0, SPAWN_PADS.size() - 1)]
	holes.append(make_hole(_alloc_id(), pad.x, pad.y, false, 0))


## Phase 4: match with 2–4 holes (slot 0 human, extras bots).
func setup_match(cfg: MatchConfig, world_seed: int = 42) -> void:
	config = cfg
	_layout_phase2_map(world_seed)
	var n: int = clampi(cfg.hole_count, 2, 4)
	for i in n:
		var pad: Vector2 = SPAWN_PADS[i]
		holes.append(make_hole(_alloc_id(), pad.x, pad.y, i > 0, i))


func _layout_phase2_map(world_seed: int) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = MAP_HALF_DEFAULT
	_next_id = 1
	holes.clear()
	objects.clear()
	parks.clear()
	roads.clear()
	_pending_hole_respawns.clear()
	_pending_prop_spawns.clear()
	match_over = false
	match_end_reason = ""
	winner_id = -1
	rankings.clear()

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
## Returns Array of event Dictionaries.
func step(inputs_by_hole: Dictionary, dt: float) -> Array:
	var events: Array = []
	if dt <= 0.0 or match_over:
		return events

	tick += 1
	elapsed += dt

	_process_hole_respawns(events)
	_process_prop_respawns()

	for hole_v in holes:
		var hole: Dictionary = hole_v
		if not bool(hole["alive"]):
			continue
		var input: Vector2 = inputs_by_hole.get(int(hole["id"]), Vector2.ZERO) as Vector2
		_steer_hole(hole, input, dt)
		_clamp_hole(hole)

	_update_props(dt, events)
	if config != null and config.allow_player_eat:
		_update_player_swallow(dt, events)

	_check_match_end(events)
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


func hole_by_id(id: int) -> Dictionary:
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if int(hole["id"]) == id:
			return hole
	return {}


func _add_mass(hole: Dictionary, mass_gain: float) -> void:
	hole["mass"] = float(hole["mass"]) + mass_gain
	hole["radius"] = sqrt(float(hole["mass"]))
	hole["score"] = roundi(float(hole["mass"]) * SCORE_SCALE)
	hole["score_changed_tick"] = tick


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
			_add_mass(best_hole, mass_gain)
			prop["alive"] = false
			to_remove.append(prop)
			if config != null and config.respawn_props:
				_pending_prop_spawns.append({
					"tier": int(prop["tier"]),
					"at": elapsed + PROP_RESPAWN_DELAY,
					"x": float(prop["x"]),
					"y": float(prop["y"]),
				})
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


func _update_player_swallow(dt: float, events: Array) -> void:
	var alive: Array = _alive_holes()
	if alive.size() < 2:
		return

	# Snapshot ids so we do not double-process in one tick.
	var eliminated_ids: Dictionary = {} ## id -> true

	for attacker_v in alive:
		var attacker: Dictionary = attacker_v
		var aid: int = int(attacker["id"])
		if eliminated_ids.has(aid):
			continue
		var ax: float = float(attacker["x"])
		var ay: float = float(attacker["y"])
		var ar: float = float(attacker["radius"])

		for victim_v in alive:
			var victim: Dictionary = victim_v
			var vid: int = int(victim["id"])
			if vid == aid or eliminated_ids.has(vid) or not bool(victim["alive"]):
				continue
			var vr: float = float(victim["radius"])
			if vr > ar * PLAYER_EAT_RATIO:
				continue
			var vx: float = float(victim["x"])
			var vy: float = float(victim["y"])
			var dx: float = ax - vx
			var dy: float = ay - vy
			var dist: float = sqrt(dx * dx + dy * dy)
			var suction: float = ar * PLAYER_SUCTION_MULT
			if dist >= suction:
				continue

			# Pull victim toward attacker; victim can still steer (already applied this tick).
			if dist > 0.0001:
				var nx: float = dx / dist
				var ny: float = dy / dist
				victim["vx"] = float(victim["vx"]) + nx * PLAYER_PULL_ACCEL * dt
				victim["vy"] = float(victim["vy"]) + ny * PLAYER_PULL_ACCEL * dt
				victim["x"] = vx + float(victim["vx"]) * dt
				victim["y"] = vy + float(victim["vy"]) * dt
				_clamp_hole(victim)
				dx = ax - float(victim["x"])
				dy = ay - float(victim["y"])
				dist = sqrt(dx * dx + dy * dy)

			if dist < ar * PLAYER_CONSUME_MULT and float(victim["radius"]) <= ar * PLAYER_EAT_RATIO:
				var transfer: float = float(victim["mass"]) * PLAYER_MASS_TRANSFER
				_add_mass(attacker, transfer)
				victim["alive"] = false
				victim["vx"] = 0.0
				victim["vy"] = 0.0
				eliminated_ids[vid] = true
				_release_claims(vid)
				if config != null and config.respawn_holes:
					_pending_hole_respawns.append({"id": vid, "at": elapsed + HOLE_RESPAWN_DELAY})
				events.append({
					"kind": EVENT_ELIMINATED,
					"hole_id": aid,
					"victim_id": vid,
					"mass_gained": transfer,
					"x": victim["x"],
					"y": victim["y"],
				})


func _release_claims(hole_id: int) -> void:
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if int(prop["claimed_by"]) == hole_id:
			prop["claimed_by"] = -1


func _process_hole_respawns(events: Array) -> void:
	if config == null or not config.respawn_holes:
		_pending_hole_respawns.clear()
		return
	var keep: Array = []
	for item_v in _pending_hole_respawns:
		var item: Dictionary = item_v
		if float(item["at"]) > elapsed:
			keep.append(item)
			continue
		var hole: Dictionary = hole_by_id(int(item["id"]))
		if hole.is_empty() or bool(hole["alive"]):
			continue
		var pad: Vector2 = _free_spawn_pad()
		hole["x"] = pad.x
		hole["y"] = pad.y
		hole["vx"] = 0.0
		hole["vy"] = 0.0
		hole["mass"] = START_MASS
		hole["radius"] = START_RADIUS
		# Score kept.
		hole["alive"] = true
		events.append({
			"kind": EVENT_RESPAWNED,
			"hole_id": int(hole["id"]),
			"x": pad.x,
			"y": pad.y,
		})
	_pending_hole_respawns = keep


func _free_spawn_pad() -> Vector2:
	## Prefer a pad farthest from alive holes.
	var best: Vector2 = SPAWN_PADS[0]
	var best_score: float = -1.0
	for pad_v in SPAWN_PADS:
		var pad: Vector2 = pad_v
		var min_d: float = INF
		for hole_v in _alive_holes():
			var hole: Dictionary = hole_v
			var d: float = pad.distance_to(Vector2(float(hole["x"]), float(hole["y"])))
			if d < min_d:
				min_d = d
		if min_d > best_score:
			best_score = min_d
			best = pad
	return best


func _process_prop_respawns() -> void:
	if config == null or not config.respawn_props:
		_pending_prop_spawns.clear()
		return
	var keep: Array = []
	for item_v in _pending_prop_spawns:
		var item: Dictionary = item_v
		if float(item["at"]) > elapsed:
			keep.append(item)
			continue
		var tier: int = int(item["tier"])
		var radius: float = float(TIER_RADIUS[clampi(tier, 0, TIER_RADIUS.size() - 1)])
		var pos := _spawn_prop_away_from_holes(Vector2(float(item["x"]), float(item["y"])), radius)
		objects.append(make_prop(_alloc_id(), pos.x, pos.y, tier, radius))
	_pending_prop_spawns = keep


func _spawn_prop_away_from_holes(near: Vector2, radius: float) -> Vector2:
	for _attempt in 24:
		var ang: float = _rng.randf() * TAU
		var dist: float = 4.0 + _rng.randf() * 18.0
		var p := Vector2(
			clampf(near.x + cos(ang) * dist, -map_half + radius, map_half - radius),
			clampf(near.y + sin(ang) * dist, -map_half + radius, map_half - radius)
		)
		var clear := true
		for hole_v in _alive_holes():
			var hole: Dictionary = hole_v
			var suction: float = float(hole["radius"]) * PROP_SUCTION_MULT
			if p.distance_to(Vector2(float(hole["x"]), float(hole["y"]))) < suction + radius:
				clear = false
				break
		if clear:
			return p
	return Vector2(
		clampf(near.x, -map_half + radius, map_half - radius),
		clampf(near.y, -map_half + radius, map_half - radius)
	)


func _check_match_end(events: Array) -> void:
	if match_over or config == null:
		return
	match config.mode:
		MatchConfig.Mode.UNLIMITED:
			return
		MatchConfig.Mode.TIMER:
			if elapsed >= config.duration:
				_end_match("Time", _rank_holes(), events)
		MatchConfig.Mode.SCORE_TARGET:
			for hole_v in holes:
				var hole: Dictionary = hole_v
				if bool(hole["alive"]) and int(hole["score"]) >= config.score_target:
					_end_match(config.end_title(), _rank_holes(), events)
					return
		MatchConfig.Mode.MAP_CLEARED:
			if not any_swallowable_prop():
				_end_match("Map cleared", _rank_holes(), events)
		MatchConfig.Mode.LAST_STANDING:
			var alive: Array = _alive_holes()
			if alive.size() == 1:
				_end_match("Last hole standing", _rank_holes(), events)
			elif alive.is_empty():
				_end_match("Last hole standing", _rank_holes(), events)
			elif not any_swallowable_prop() and not any_player_eat_pair():
				# Fallback so a couch session cannot sit forever.
				_end_match("Last hole standing", _rank_holes(), events)


func _end_match(reason: String, ranked: Array, events: Array) -> void:
	match_over = true
	match_end_reason = reason
	rankings = ranked
	winner_id = int(ranked[0]) if ranked.size() > 0 else -1
	events.append({
		"kind": EVENT_MATCH_ENDED,
		"reason": reason,
		"winner_id": winner_id,
		"rankings": rankings.duplicate(),
	})


## Tie-break: higher score, then larger radius, then earlier score_changed_tick.
func _rank_holes() -> Array:
	var list: Array = holes.duplicate()
	list.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ha: Dictionary = a
		var hb: Dictionary = b
		var sa: int = int(ha["score"])
		var sb: int = int(hb["score"])
		if sa != sb:
			return sa > sb
		var ra: float = float(ha["radius"])
		var rb: float = float(hb["radius"])
		if not is_equal_approx(ra, rb):
			return ra > rb
		return int(ha["score_changed_tick"]) < int(hb["score_changed_tick"])
	)
	var ids: Array = []
	for h in list:
		ids.append(int((h as Dictionary)["id"]))
	return ids


func any_swallowable_prop() -> bool:
	var alive: Array = _alive_holes()
	if alive.is_empty():
		return false
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		var pr: float = float(prop["radius"])
		for hole_v in alive:
			var hole: Dictionary = hole_v
			if pr <= float(hole["radius"]) * PROP_EAT_RATIO:
				return true
	return false


func any_player_eat_pair() -> bool:
	var alive: Array = _alive_holes()
	for a_v in alive:
		var a: Dictionary = a_v
		for b_v in alive:
			var b: Dictionary = b_v
			if int(a["id"]) == int(b["id"]):
				continue
			if float(b["radius"]) <= float(a["radius"]) * PLAYER_EAT_RATIO:
				return true
	return false


func swallowable_prop_count() -> int:
	var n := 0
	var alive: Array = _alive_holes()
	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		var pr: float = float(prop["radius"])
		for hole_v in alive:
			var hole: Dictionary = hole_v
			if pr <= float(hole["radius"]) * PROP_EAT_RATIO:
				n += 1
				break
	return n


func player_hole() -> Dictionary:
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if not bool(hole.get("is_bot", false)):
			return hole
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


func time_remaining() -> float:
	if config == null or config.mode != MatchConfig.Mode.TIMER:
		return 0.0
	return maxf(0.0, config.duration - elapsed)
