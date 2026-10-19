extends "res://tests/test_case.gd"
## Plays whole battles with the SimpleBot in every scenario and faction pairing. Any script error in the
## rules flow fails the test (the runner catches errors), and every battle must make real progress.


func _play(fa: String, fb: String, scenario: String, seed_value: int, max_steps := 3000) -> Battle:
	var b := Battle.new()
	b.setup(Samples.roster(fa), Samples.roster(fb), scenario, -1, seed_value)
	var steps := 0
	while steps < max_steps and SimpleBot.step(b):
		steps += 1
		if b.round_no > 12:
			break
	return b


func test_every_scenario_plays() -> void:
	var facs := Catalog.FACTION_IDS
	var i := 0
	for sc in Scenario.ORDER:
		for k in 2:
			var fa: String = facs[i % 4]
			var fb: String = facs[(i + 1 + k) % 4]
			i += 1
			var b := _play(fa, fb, sc, 100 + i)
			assert_true(b.round_no >= 2 or b.is_over(), "%s %s v %s stalled in round %d (phase %s, pending %s)" % [sc, fa, fb, b.round_no, b.phase, b.pending.get("type", "")])
			var downs := 0
			for f in b.fighters:
				if f.where == "down":
					downs += 1
			assert_true(downs > 0 or b.round_no >= 4 or b.is_over(), "%s: nobody was ever taken down" % sc)


func test_mirror_matches_all_factions() -> void:
	for fac in Catalog.FACTION_IDS:
		var b := _play(fac, fac, "a_deadly_encounter", 7)
		assert_true(b.round_no >= 2 or b.is_over(), fac)


func test_save_and_restore_round_trip() -> void:
	var b := Battle.new()
	b.setup(Samples.roster("guild_mercenaries"), Samples.roster("death_covens"), "no_quarter", 0, 42)
	for i in 80:
		if not SimpleBot.step(b):
			break
	var path := "user://test_save.bdc"
	assert_eq(b.save_to(path), OK)
	var c := Battle.load_from(path)
	assert_true(c != null)
	assert_eq(c.round_no, b.round_no)
	assert_eq(c.fighters.size(), b.fighters.size())
	assert_eq(c.dice.d6(), b.dice.d6(), "same RNG stream after load")
	for i in c.fighters.size():
		assert_eq(c.fighters[i].pos, b.fighters[i].pos)
		assert_eq(c.fighters[i].life, b.fighters[i].life)
