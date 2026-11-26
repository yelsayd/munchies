extends SceneTree
## Headless Phase 1 + Phase 2 checks. Run:
##   godot --headless --path . -s res://tests/test_sim.gd

func _init() -> void:
	var probe := MunchiesSim.new()
	if probe == null:
		print("FAIL: MunchiesSim failed to instantiate (script compile error)")
		quit(1)
		return

	var failed := 0
	failed += _check_start_state()
	failed += _check_too_big_not_eaten()
	failed += _check_litter_swallow_and_grow()
	failed += _check_slowdown()
	failed += _check_map_clamp()
	failed += _check_phase2_map()
	failed += _check_claims_closest()
	failed += _check_progression_gates()

	if failed == 0:
		print("PASS: all Phase 1+2 sim checks")
		quit(0)
	else:
		print("FAIL: %d check(s) failed" % failed)
		quit(1)


func _check_start_state() -> int:
	var sim := MunchiesSim.new()
	sim.setup_phase1(7)
	var hole := sim.player_hole()
	if not is_equal_approx(float(hole["radius"]), 1.0):
		print("FAIL start radius: ", hole["radius"])
		return 1
	if int(hole["score"]) != 10:
		print("FAIL start score: ", hole["score"])
		return 1
	if sim.alive_prop_count() < 50:
		print("FAIL expected dense litter, got ", sim.alive_prop_count())
		return 1
	print("ok start state")
	return 0


func _check_too_big_not_eaten() -> int:
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 30.0)
	var too_big := 1.15
	sim.objects.append(MunchiesSim.make_prop(99, 0.0, 0.0, 2, too_big))
	var hole := sim.player_hole()
	var before := sim.alive_prop_count()
	var mass_before: float = float(hole["mass"])
	assert(too_big > float(hole["radius"]) * MunchiesSim.PROP_EAT_RATIO)
	for i in 120:
		sim.step({int(hole["id"]): Vector2.ZERO}, 1.0 / 60.0)
	if sim.alive_prop_count() != before:
		print("FAIL too-big prop was swallowed")
		return 1
	if not is_equal_approx(float(hole["mass"]), mass_before):
		print("FAIL mass changed on too-big prop")
		return 1
	print("ok too-big gate")
	return 0


func _check_litter_swallow_and_grow() -> int:
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 30.0)
	sim.objects.append(MunchiesSim.make_prop(50, 0.05, 0.0, 0, MunchiesSim.TIER0_RADIUS))
	var hole := sim.player_hole()
	var mass_before: float = float(hole["mass"])
	var swallowed := false
	for i in 180:
		var events: Array = sim.step({int(hole["id"]): Vector2.ZERO}, 1.0 / 60.0)
		for e in events:
			if e["kind"] == MunchiesSim.EVENT_SWALLOWED:
				swallowed = true
	if not swallowed:
		print("FAIL litter not swallowed")
		return 1
	if float(hole["mass"]) <= mass_before:
		print("FAIL mass did not grow")
		return 1
	if float(hole["radius"]) <= 1.0:
		print("FAIL radius did not grow: ", hole["radius"])
		return 1
	if sim.alive_prop_count() != 0:
		print("FAIL prop still alive after swallow")
		return 1
	print("ok litter swallow + grow")
	return 0


func _check_slowdown() -> int:
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 30.0)
	var hole := sim.player_hole()
	hole["vx"] = 0.0
	hole["vy"] = 0.0
	for i in 90:
		sim.step({int(hole["id"]): Vector2(1, 0)}, 1.0 / 60.0)
	var speed_small := absf(float(hole["vx"]))

	hole["mass"] = 25.0
	hole["radius"] = 5.0
	hole["vx"] = 0.0
	hole["vy"] = 0.0
	for i in 90:
		sim.step({int(hole["id"]): Vector2(1, 0)}, 1.0 / 60.0)
	var speed_big := absf(float(hole["vx"]))

	if speed_big >= speed_small * 0.95:
		print("FAIL expected slowdown: small=", speed_small, " big=", speed_big)
		return 1
	if speed_big < MunchiesSim.SPEED_BASE * MunchiesSim.SPEED_FLOOR * 0.5:
		print("FAIL big hole too slow: ", speed_big)
		return 1
	print("ok slowdown small=", snappedf(speed_small, 0.01), " big=", snappedf(speed_big, 0.01))
	return 0


func _check_map_clamp() -> int:
	var sim := MunchiesSim.new()
	sim.setup_phase2(1, 0)
	var hole := sim.player_hole()
	hole["x"] = sim.map_half + 10.0
	hole["y"] = 0.0
	hole["vx"] = 20.0
	sim.step({int(hole["id"]): Vector2(1, 0)}, 1.0 / 60.0)
	var limit := sim.map_half - float(hole["radius"]) * 0.5
	if float(hole["x"]) > limit + 0.01:
		print("FAIL clamp: x=", hole["x"], " limit=", limit)
		return 1
	if float(hole["vx"]) > 0.0:
		print("FAIL outward velocity not cancelled: ", hole["vx"])
		return 1
	print("ok map clamp")
	return 0


func _check_phase2_map() -> int:
	var sim := MunchiesSim.new()
	sim.setup_phase2(42, 0)
	if not is_equal_approx(sim.map_half, 80.0):
		print("FAIL map_half expected 80, got ", sim.map_half)
		return 1
	var counts: Dictionary = sim.count_by_tier()
	# Approximate plan counts; spawn-pad clearing trims a few.
	if int(counts.get(0, 0)) < 100:
		print("FAIL tier0 too sparse: ", counts)
		return 1
	if int(counts.get(1, 0)) < 40:
		print("FAIL tier1 too sparse: ", counts)
		return 1
	if int(counts.get(2, 0)) < 20:
		print("FAIL tier2 too sparse: ", counts)
		return 1
	if int(counts.get(3, 0)) < 10:
		print("FAIL tier3 too sparse: ", counts)
		return 1
	if int(counts.get(4, 0)) < 5:
		print("FAIL tier4 too sparse: ", counts)
		return 1
	if sim.parks.size() < 3:
		print("FAIL expected parks")
		return 1
	if MunchiesSim.SPAWN_PADS.size() != 4:
		print("FAIL expected 4 spawn pads")
		return 1
	var hole := sim.player_hole()
	var spawn: Vector2 = MunchiesSim.SPAWN_PADS[0]
	if Vector2(float(hole["x"]), float(hole["y"])).distance_to(spawn) > 0.1:
		print("FAIL hole not on spawn pad 0")
		return 1
	print("ok phase2 map tiers=", counts)
	return 0


func _check_claims_closest() -> int:
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	# Two holes; prop nearer hole B should be claimed by B.
	sim.holes.append(MunchiesSim.make_hole(2, 4.0, 0.0))
	sim.objects.append(MunchiesSim.make_prop(10, 3.2, 0.0, 0, MunchiesSim.TIER0_RADIUS))
	var events: Array = sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0)
	var prop: Dictionary = sim.objects[0]
	if int(prop["claimed_by"]) != 2:
		print("FAIL claim expected hole 2, got ", prop["claimed_by"], " events=", events.size())
		return 1
	print("ok claims closest")
	return 0


func _check_progression_gates() -> int:
	## Start hole can eat tier 0; cannot eat tier 2/3/4.
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	sim.objects.append(MunchiesSim.make_prop(1, 0.0, 0.0, 2, MunchiesSim.TIER2_RADIUS))
	sim.objects.append(MunchiesSim.make_prop(2, 0.0, 0.0, 3, MunchiesSim.TIER3_RADIUS))
	var hole := sim.player_hole()
	for i in 90:
		sim.step({int(hole["id"]): Vector2.ZERO}, 1.0 / 60.0)
	if sim.alive_prop_count() != 2:
		print("FAIL start should not eat vehicles/buildings")
		return 1
	# Grow enough for vehicles (need radius >= 1.30/0.95 ≈ 1.37).
	hole["mass"] = 2.0
	hole["radius"] = sqrt(2.0)
	# Move vehicle onto hole and swallow.
	sim.objects.clear()
	sim.objects.append(MunchiesSim.make_prop(3, 0.05, 0.0, 2, MunchiesSim.TIER2_RADIUS))
	var swallowed_vehicle := false
	for i in 180:
		for e in sim.step({int(hole["id"]): Vector2.ZERO}, 1.0 / 60.0):
			if e["kind"] == MunchiesSim.EVENT_SWALLOWED and int(e["tier"]) == 2:
				swallowed_vehicle = true
	if not swallowed_vehicle:
		print("FAIL mid-game should eat vehicles at radius ", hole["radius"])
		return 1
	print("ok progression gates")
	return 0
