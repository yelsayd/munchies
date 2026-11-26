extends SceneTree
## Headless Phase 1 checks. Run:
##   godot --headless --path . -s res://tests/test_sim.gd

func _init() -> void:
	# Ensure the global class compiled before asserting gameplay rules.
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

	if failed == 0:
		print("PASS: all Phase 1 sim checks")
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
	sim.setup_phase1(1)
	# Clear scatter; place a prop larger than startRadius × 0.95 on the hole.
	sim.objects.clear()
	var too_big := 1.15
	sim.objects.append(MunchiesSim.make_prop(99, 0.0, 0.0, 1, too_big))
	var hole := sim.player_hole()
	hole["x"] = 0.0
	hole["y"] = 0.0
	hole["radius"] = 1.0
	hole["mass"] = 1.0
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
	sim.setup_phase1(1)
	sim.objects.clear()
	# Litter under the hole — must swallow and grow.
	sim.objects.append(MunchiesSim.make_prop(50, 0.05, 0.0, 0, MunchiesSim.TIER0_RADIUS))
	var hole := sim.player_hole()
	hole["x"] = 0.0
	hole["y"] = 0.0
	var mass_before: float = hole["mass"]
	var swallowed := false
	for i in 180:
		var events: Array = sim.step({hole["id"]: Vector2.ZERO}, 1.0 / 60.0)
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
	sim.setup_phase1(1)
	var hole := sim.player_hole()
	# Measure top speed at start radius.
	hole["vx"] = 0.0
	hole["vy"] = 0.0
	for i in 90:
		sim.step({hole["id"]: Vector2(1, 0)}, 1.0 / 60.0)
	var speed_small := absf(float(hole["vx"]))

	# Inflate and measure again.
	hole["mass"] = 25.0
	hole["radius"] = 5.0
	hole["vx"] = 0.0
	hole["vy"] = 0.0
	for i in 90:
		sim.step({hole["id"]: Vector2(1, 0)}, 1.0 / 60.0)
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
	sim.setup_phase1(1)
	var hole := sim.player_hole()
	hole["x"] = sim.map_half + 10.0
	hole["y"] = 0.0
	hole["vx"] = 20.0
	sim.step({hole["id"]: Vector2(1, 0)}, 1.0 / 60.0)
	var limit := sim.map_half - float(hole["radius"]) * 0.5
	if float(hole["x"]) > limit + 0.01:
		print("FAIL clamp: x=", hole["x"], " limit=", limit)
		return 1
	if float(hole["vx"]) > 0.0:
		print("FAIL outward velocity not cancelled: ", hole["vx"])
		return 1
	print("ok map clamp")
	return 0
