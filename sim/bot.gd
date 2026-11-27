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

	# Flee larger holes that can eat us; hunt smaller ones we can swallow.
	var flee := Vector2.ZERO
	var hunt := Vector2.ZERO
	var hunt_dist: float = INF
	if sim.config != null and sim.config.allow_player_eat:
		for other_v in sim.holes:
			var other: Dictionary = other_v
			if int(other["id"]) == hole_id or not bool(other["alive"]):
				continue
			var orad: float = float(other["radius"])
			var op := Vector2(float(other["x"]), float(other["y"]))
			var d: float = pos.distance_to(op)
			# They can eat us → flee.
			if orad * MunchiesSim.PLAYER_EAT_RATIO >= hr:
				var danger: float = orad * MunchiesSim.PLAYER_SUCTION_MULT * FEAR_MULT
				if d < danger and d > 0.001:
					flee += (pos - op).normalized() * ((danger - d) / danger)
			# We can eat them → chase the nearest meal.
			elif orad <= hr * MunchiesSim.PLAYER_EAT_RATIO and d < hunt_dist:
				hunt_dist = d
				hunt = op - pos

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

	# Prefer hunting a smaller hole when it's in engagement range; else food.
	var hunt_range: float = hr * MunchiesSim.PLAYER_SUCTION_MULT * 5.0
	var steer := Vector2.ZERO
	if flee.length_squared() > 0.01:
		steer = flee
	elif hunt_dist < hunt_range:
		steer = hunt
	elif best_dist < INF:
		steer = best_food
	else:
		# Wander toward map center so bots do not hug a empty corner forever.
		steer = -pos

	if steer.length_squared() < 0.0001:
		return Vector2.ZERO
	return steer.normalized()
