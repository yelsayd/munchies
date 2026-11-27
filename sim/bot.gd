class_name MunchiesBot
extends RefCounted
## In-process bot: reads the sim and emits Input only. Never writes positions.

const FEAR_MULT := 2.2 ## flee when a larger eater is within this × its suction


static func input_for(sim: MunchiesSim, hole_id: int) -> Vector2:
	var hole: Dictionary = {}
	for h_v in sim.holes:
		var h: Dictionary = h_v
		if int(h["id"]) == hole_id:
			hole = h
			break
	if hole.is_empty() or not bool(hole["alive"]):
		return Vector2.ZERO

	var hx: float = float(hole["x"])
	var hy: float = float(hole["y"])
	var hr: float = float(hole["radius"])
	var pos := Vector2(hx, hy)

	# Flee larger holes that can eat us.
	var flee := Vector2.ZERO
	if sim.config != null and sim.config.allow_player_eat:
		for other_v in sim.holes:
			var other: Dictionary = other_v
			if int(other["id"]) == hole_id or not bool(other["alive"]):
				continue
			var orad: float = float(other["radius"])
			if hr > orad * MunchiesSim.PLAYER_EAT_RATIO:
				continue ## we are not the smaller one
			if orad * MunchiesSim.PLAYER_EAT_RATIO < hr:
				continue ## they cannot eat us
			var op := Vector2(float(other["x"]), float(other["y"]))
			var d: float = pos.distance_to(op)
			var danger: float = orad * MunchiesSim.PLAYER_SUCTION_MULT * FEAR_MULT
			if d < danger and d > 0.001:
				flee += (pos - op).normalized() * ((danger - d) / danger)

	# Seek nearest food this hole can actually cover (skips fallen buildings that are too big).
	var best_food := Vector2.ZERO
	var best_dist: float = INF
	for prop_v in sim.objects:
		var prop: Dictionary = prop_v
		if not bool(prop["alive"]):
			continue
		if not MunchiesSim.hole_can_cover_prop(hr, prop):
			continue
		var claimed: int = int(prop["claimed_by"])
		if claimed != -1 and claimed != hole_id:
			continue
		# Steer toward the cover center (fallen mass sits toward tip_dir).
		var pp: Vector2 = MunchiesSim.prop_cover_center(prop)
		var d: float = pos.distance_to(pp)
		if d < best_dist:
			best_dist = d
			best_food = pp - pos

	var steer := Vector2.ZERO
	if flee.length_squared() > 0.01:
		steer = flee
	elif best_dist < INF:
		steer = best_food
	else:
		# Wander toward map center so bots do not hug a empty corner forever.
		steer = -pos

	if steer.length_squared() < 0.0001:
		return Vector2.ZERO
	return steer.normalized()
