class_name MunchiesSim
extends RefCounted
## Pure simulation for Munchies. No scene tree, no physics nodes.
## Phase 1: one hole, tier 0/1 props, keyboard-driven Input into step().

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

const TIER0_RADIUS := 0.25
const TIER1_RADIUS := 0.55
## Larger than startRadius × 0.95 so the Phase 1 size gate is playable.
const PHASE1_TOO_BIG_RADIUS := 1.15

## Event kinds returned by step().
const EVENT_SWALLOWED := &"Swallowed"
const EVENT_SUCKED := &"Sucked"

var tick: int = 0
var elapsed: float = 0.0
var map_half: float = 30.0
var holes: Array = [] ## Array of Dictionary
var objects: Array = [] ## Array of Dictionary
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


func setup_phase1(world_seed: int = 1) -> void:
	_rng.seed = world_seed
	tick = 0
	elapsed = 0.0
	map_half = 30.0
	_next_id = 1
	holes.clear()
	objects.clear()

	# One hole near center, clear of the densest litter.
	holes.append(make_hole(_alloc_id(), 0.0, 0.0))

	# Dense litter (tier 0) in a center park + a second clump.
	_scatter_props(0, TIER0_RADIUS, 80, Vector2(0, 0), 12.0)
	_scatter_props(0, TIER0_RADIUS, 40, Vector2(14, -10), 8.0)

	# Street props (tier 1) — too big at start (need radius >= ~0.58).
	_scatter_props(1, TIER1_RADIUS, 36, Vector2(-8, 10), 14.0)
	_scatter_props(1, TIER1_RADIUS, 20, Vector2(16, 12), 10.0)

	# Oversized markers (radius > start × 0.95). Phase 1 still only scatters
	# tier 0/1 food; these prove the size gate until tier 2 arrives in Phase 2.
	for i in 5:
		var a: float = _rng.randf() * TAU
		var d: float = 5.0 + _rng.randf() * 5.0
		objects.append(make_prop(_alloc_id(), cos(a) * d, sin(a) * d, 1, PHASE1_TOO_BIG_RADIUS))


func _alloc_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func _scatter_props(tier: int, radius: float, count: int, center: Vector2, spread: float) -> void:
	for i in count:
		var ang := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * spread
		var x := center.x + cos(ang) * dist
		var y := center.y + sin(ang) * dist
		# Keep clear of the spawn hole.
		if Vector2(x, y).length() < START_RADIUS * 2.5:
			continue
		x = clampf(x, -map_half + radius, map_half - radius)
		y = clampf(y, -map_half + radius, map_half - radius)
		objects.append(make_prop(_alloc_id(), x, y, tier, radius))


## inputs_by_hole: Dictionary[int, Vector2] with each component in [-1, 1].
## Returns Array of event Dictionaries: {kind, hole_id, prop_id?, mass_gained?}
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


func _update_props(dt: float, events: Array) -> void:
	var hole: Dictionary = _alive_hole()
	if hole.is_empty():
		return

	var hx: float = float(hole["x"])
	var hy: float = float(hole["y"])
	var hr: float = float(hole["radius"])
	var hole_id: int = int(hole["id"])
	var suction_r: float = hr * PROP_SUCTION_MULT
	var consume_r: float = hr * PROP_CONSUME_MULT
	var eat_limit: float = hr * PROP_EAT_RATIO

	var to_remove: Array = []

	for prop_v in objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue

		var px: float = float(prop["x"])
		var py: float = float(prop["y"])
		var pr: float = float(prop["radius"])
		var dx: float = hx - px
		var dy: float = hy - py
		var dist: float = sqrt(dx * dx + dy * dy)

		var can_eat: bool = pr <= eat_limit
		if not can_eat:
			# Too big: clear claim, no pull. Hole passes over.
			prop["claimed_by"] = -1
			prop["vx"] = 0.0
			prop["vy"] = 0.0
			continue

		if dist < suction_r:
			prop["claimed_by"] = hole_id
			if dist > 0.0001:
				var nx: float = dx / dist
				var ny: float = dy / dist
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
			# Recompute after pull for consume test.
			dx = hx - float(prop["x"])
			dy = hy - float(prop["y"])
			dist = sqrt(dx * dx + dy * dy)

			if dist < consume_r and float(prop["radius"]) <= eat_limit:
				var mass_gain: float = pr * pr
				hole["mass"] = float(hole["mass"]) + mass_gain
				hole["radius"] = sqrt(float(hole["mass"]))
				hole["score"] = roundi(float(hole["mass"]) * SCORE_SCALE)
				prop["alive"] = false
				to_remove.append(prop)
				events.append({
					"kind": EVENT_SWALLOWED,
					"hole_id": hole_id,
					"prop_id": prop["id"],
					"mass_gained": mass_gain,
					"tier": prop["tier"],
				})
		else:
			if int(prop["claimed_by"]) == hole_id:
				prop["claimed_by"] = -1
			prop["vx"] = 0.0
			prop["vy"] = 0.0

	for dead in to_remove:
		objects.erase(dead)


func _alive_hole() -> Dictionary:
	for hole_v in holes:
		var hole: Dictionary = hole_v
		if bool(hole["alive"]):
			return hole
	return {}


func player_hole() -> Dictionary:
	return holes[0] as Dictionary


func alive_prop_count() -> int:
	var n := 0
	for p in objects:
		if p["alive"]:
			n += 1
	return n
