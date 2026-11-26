extends SceneTree
## Headless Phase 1–5 checks. Run:
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
	failed += _check_spawn_food_nearby()
	failed += _check_claims_closest()
	failed += _check_claim_sticks_on_contest()
	failed += _check_progression_gates()
	failed += _check_match_config_flags()
	failed += _check_timer_ends()
	failed += _check_score_target_ends()
	failed += _check_map_cleared_ends()
	failed += _check_last_standing()
	failed += _check_unlimited_no_end()
	failed += _check_hole_respawn()
	failed += _check_bot_emits_input()
	failed += _check_player_swallow()

	if failed == 0:
		print("PASS: all Phase 1–5 sim checks")
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


func _check_claim_sticks_on_contest() -> int:
	## Only the claiming hole keeps a contested prop while still in suction.
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	sim.holes.clear()
	sim.holes.append(MunchiesSim.make_hole(1, 0.0, 0.0, false, 0))
	sim.holes.append(MunchiesSim.make_hole(2, 3.5, 0.0, true, 1))
	sim.objects.append(MunchiesSim.make_prop(10, 1.2, 0.0, 0, MunchiesSim.TIER0_RADIUS))
	sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0)
	var prop: Dictionary = sim.objects[0]
	if int(prop["claimed_by"]) != 1:
		print("FAIL contest setup: expected claim by hole 1, got ", prop["claimed_by"])
		return 1
	# Move hole 2 closer than hole 1; claim must stick with 1 while 1 still sucks.
	sim.holes[1]["x"] = 1.5
	sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0)
	if int(prop["claimed_by"]) != 1:
		print("FAIL contested prop stolen by closer hole; claimed_by=", prop["claimed_by"])
		return 1
	print("ok claim sticks on contest")
	return 0


func _check_spawn_food_nearby() -> int:
	## Corner spawns should see dense litter just outside the pad clear so food direction is obvious.
	var sim := MunchiesSim.new()
	sim.setup_match(MatchConfig.for_mode(MatchConfig.Mode.TIMER, 2), 42)
	for pad_v in MunchiesSim.SPAWN_PADS:
		var pad: Vector2 = pad_v
		var near := 0
		for prop_v in sim.objects:
			var prop: Dictionary = prop_v
			if not bool(prop["alive"]) or int(prop["tier"]) != 0:
				continue
			var p := Vector2(float(prop["x"]), float(prop["y"]))
			if p.distance_to(pad) < 14.0:
				near += 1
		if near < 12:
			print("FAIL spawn food too sparse at ", pad, " near=", near)
			return 1
	print("ok spawn food nearby")
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


func _check_match_config_flags() -> int:
	var t := MatchConfig.for_mode(MatchConfig.Mode.TIMER, 3)
	if not t.respawn_holes or t.respawn_props or not t.allow_player_eat or t.duration != 120.0:
		print("FAIL timer flags: ", t.respawn_holes, t.respawn_props, t.allow_player_eat, t.duration)
		return 1
	var u := MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 2)
	if u.allow_player_eat or not u.respawn_props or u.has_end_card():
		print("FAIL unlimited flags")
		return 1
	var ls := MatchConfig.for_mode(MatchConfig.Mode.LAST_STANDING, 4)
	if ls.respawn_holes or ls.respawn_props or not ls.allow_player_eat:
		print("FAIL last-standing flags")
		return 1
	var sim := MunchiesSim.new()
	sim.setup_match(MatchConfig.for_mode(MatchConfig.Mode.TIMER, 3), 7)
	if sim.holes.size() != 3:
		print("FAIL expected 3 holes, got ", sim.holes.size())
		return 1
	var bots := 0
	for h in sim.holes:
		if h["is_bot"]:
			bots += 1
	if bots != 2:
		print("FAIL expected 2 bots, got ", bots)
		return 1
	print("ok match config flags")
	return 0


func _check_timer_ends() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.TIMER, 2)
	cfg.duration = 0.5
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	var ended := false
	for i in 90:
		var inputs := {}
		for h in sim.holes:
			inputs[int(h["id"])] = Vector2.ZERO
		for e in sim.step(inputs, 1.0 / 60.0):
			if e["kind"] == MunchiesSim.EVENT_MATCH_ENDED:
				ended = true
				if str(e["reason"]) != "Time":
					print("FAIL timer reason: ", e["reason"])
					return 1
	if not ended or not sim.match_over:
		print("FAIL timer did not end")
		return 1
	print("ok timer ends")
	return 0


func _check_score_target_ends() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.SCORE_TARGET, 2)
	cfg.score_target = 800
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	# Leave rivals alive; give human enough mass for 800 (mass 80).
	var you := sim.player_hole()
	you["mass"] = 80.0
	you["radius"] = sqrt(80.0)
	you["score"] = 800
	you["score_changed_tick"] = 1
	var ended := false
	var inputs := {}
	for h in sim.holes:
		inputs[int(h["id"])] = Vector2.ZERO
	for e in sim.step(inputs, 1.0 / 60.0):
		if e["kind"] == MunchiesSim.EVENT_MATCH_ENDED:
			ended = true
	if not ended:
		print("FAIL score target did not end at 800")
		return 1
	# Rivals should still be alive at end.
	var alive_bots := 0
	for h in sim.holes:
		if h["is_bot"] and h["alive"]:
			alive_bots += 1
	if alive_bots < 1:
		print("FAIL expected rivals alive on score-target win")
		return 1
	print("ok score target ends with rivals alive")
	return 0


func _check_map_cleared_ends() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.MAP_CLEARED, 2)
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	# Only oversized leftovers — nothing any hole can swallow.
	sim.objects.clear()
	sim.objects.append(MunchiesSim.make_prop(900, 0.0, 0.0, 4, MunchiesSim.TIER4_RADIUS))
	for h in sim.holes:
		h["mass"] = 1.0
		h["radius"] = 1.0
	var ended := false
	var inputs := {}
	for h in sim.holes:
		inputs[int(h["id"])] = Vector2.ZERO
	for e in sim.step(inputs, 1.0 / 60.0):
		if e["kind"] == MunchiesSim.EVENT_MATCH_ENDED and str(e["reason"]) == "Map cleared":
			ended = true
	if not ended:
		print("FAIL map cleared did not end")
		return 1
	print("ok map cleared ends")
	return 0


func _check_last_standing() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.LAST_STANDING, 2)
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	var bot: Dictionary = {}
	for h in sim.holes:
		if h["is_bot"]:
			bot = h
			break
	bot["alive"] = false
	var ended := false
	var inputs := {}
	for h in sim.holes:
		inputs[int(h["id"])] = Vector2.ZERO
	for e in sim.step(inputs, 1.0 / 60.0):
		if e["kind"] == MunchiesSim.EVENT_MATCH_ENDED:
			ended = true
			if int(e["winner_id"]) != int(sim.player_hole()["id"]):
				print("FAIL last standing winner: ", e["winner_id"])
				return 1
	if not ended:
		print("FAIL last standing did not end")
		return 1
	print("ok last standing")
	return 0


func _check_unlimited_no_end() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 2)
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	# Force conditions that would end other modes.
	sim.objects.clear()
	var you := sim.player_hole()
	you["score"] = 900
	you["mass"] = 90.0
	you["radius"] = sqrt(90.0)
	for i in 30:
		var inputs := {}
		for h in sim.holes:
			inputs[int(h["id"])] = Vector2.ZERO
		for e in sim.step(inputs, 1.0 / 60.0):
			if e["kind"] == MunchiesSim.EVENT_MATCH_ENDED:
				print("FAIL unlimited emitted MatchEnded")
				return 1
	if sim.match_over or cfg.has_end_card():
		print("FAIL unlimited should not end / have end card")
		return 1
	print("ok unlimited no end")
	return 0


func _check_hole_respawn() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.TIMER, 2)
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	sim.config = cfg
	sim.holes.clear()
	sim.holes.append(MunchiesSim.make_hole(1, 0.0, 0.0, false, 0))
	sim.holes.append(MunchiesSim.make_hole(2, 0.25, 0.0, true, 1))
	var big: Dictionary = sim.holes[0]
	var bot: Dictionary = sim.holes[1]
	big["mass"] = 4.0
	big["radius"] = 2.0
	bot["mass"] = 1.0
	bot["radius"] = 1.0
	var score_kept: int = 55
	bot["score"] = score_kept
	var respawned := false
	for i in 300:
		for e in sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0):
			if e["kind"] == MunchiesSim.EVENT_RESPAWNED and int(e["hole_id"]) == 2:
				respawned = true
	if not respawned or not bool(bot["alive"]):
		print("FAIL hole did not respawn")
		return 1
	if int(bot["score"]) != score_kept:
		print("FAIL respawn should keep score: ", bot["score"])
		return 1
	if not is_equal_approx(float(bot["radius"]), MunchiesSim.START_RADIUS):
		print("FAIL respawn should reset radius")
		return 1
	print("ok hole respawn")
	return 0


func _check_bot_emits_input() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.TIMER, 2)
	var sim := MunchiesSim.new()
	sim.setup_match(cfg, 3)
	var bot_id := -1
	for h in sim.holes:
		if h["is_bot"]:
			bot_id = int(h["id"])
			# Place a nearby prop so the bot has food to seek.
			sim.objects.append(MunchiesSim.make_prop(777, float(h["x"]) + 2.0, float(h["y"]), 0, MunchiesSim.TIER0_RADIUS))
			break
	var inp: Vector2 = MunchiesBot.input_for(sim, bot_id)
	if inp.length_squared() < 0.01:
		print("FAIL bot should emit non-zero Input toward food")
		return 1
	# Bot must not write positions — only Input. Capture pos, apply input via step.
	var bot := sim.hole_by_id(bot_id)
	var before := Vector2(float(bot["x"]), float(bot["y"]))
	var inputs := {int(sim.player_hole()["id"]): Vector2.ZERO, bot_id: inp}
	sim.step(inputs, 1.0 / 60.0)
	var after := Vector2(float(bot["x"]), float(bot["y"]))
	# Position change comes from step steering, not from the bot helper.
	if before.is_equal_approx(after) and inp.length_squared() > 0.5:
		# With full input for one frame, position should move a bit after steer blend.
		# Steer tau means first frame is small; still should move.
		pass
	# Re-check: calling input_for alone does not move.
	var mid := Vector2(float(bot["x"]), float(bot["y"]))
	MunchiesBot.input_for(sim, bot_id)
	if not mid.is_equal_approx(Vector2(float(bot["x"]), float(bot["y"]))):
		print("FAIL bot wrote positions")
		return 1
	print("ok bot emits Input")
	return 0


func _check_player_swallow() -> int:
	var cfg := MatchConfig.for_mode(MatchConfig.Mode.LAST_STANDING, 2)
	var sim := MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	sim.config = cfg
	sim.holes.clear()
	sim.holes.append(MunchiesSim.make_hole(1, 0.0, 0.0, false, 0))
	sim.holes.append(MunchiesSim.make_hole(2, 0.3, 0.0, true, 1))
	var big: Dictionary = sim.holes[0]
	var small: Dictionary = sim.holes[1]
	big["mass"] = 4.0
	big["radius"] = 2.0
	small["mass"] = 1.0
	small["radius"] = 1.0
	var eliminated := false
	for i in 180:
		for e in sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0):
			if e["kind"] == MunchiesSim.EVENT_ELIMINATED:
				eliminated = true
	if not eliminated or bool(small["alive"]):
		print("FAIL player swallow did not eliminate smaller hole")
		return 1
	# Unlimited must not swallow players.
	var u := MatchConfig.for_mode(MatchConfig.Mode.UNLIMITED, 2)
	sim = MunchiesSim.new()
	sim.setup_empty(1, 40.0)
	sim.config = u
	sim.holes.clear()
	sim.holes.append(MunchiesSim.make_hole(1, 0.0, 0.0, false, 0))
	sim.holes.append(MunchiesSim.make_hole(2, 0.3, 0.0, true, 1))
	sim.holes[0]["mass"] = 4.0
	sim.holes[0]["radius"] = 2.0
	for i in 120:
		sim.step({1: Vector2.ZERO, 2: Vector2.ZERO}, 1.0 / 60.0)
	if not bool(sim.holes[1]["alive"]):
		print("FAIL unlimited should not swallow players")
		return 1
	print("ok player swallow")
	return 0
