extends "res://tests/test_case.gd"
## Scenario twists and lingering spell effects.

const H := preload("res://tests/helpers.gd")


func _battle(scen: String, twist: int, seed_value := 9) -> Battle:
	var b := Battle.new()
	b.setup(Samples.roster("guild_mercenaries"), Samples.roster("verminkin"), scen, twist, seed_value)
	var g := 0
	while b.round_no < 1 and g < 200:
		g += 1
		SimpleBot.answer(b)
	return b


func test_every_twist_of_every_scenario_plays() -> void:
	for sc in Scenario.ORDER:
		for i in Scenario.TWISTS[sc].size():
			var b := Battle.new()
			b.setup(Samples.roster("death_covens"), Samples.roster("blighted_cloister"), sc, i, 300 + i)
			var steps := 0
			while steps < 1500 and SimpleBot.step(b) and b.round_no <= 7:
				steps += 1
			assert_true(b.round_no >= 2 or b.is_over(), "%s / %s stalled (phase %s, pending %s)" % [sc, Scenario.TWISTS[sc][i], b.phase, b.pending.get("type", "")])


func test_condemned_offers_a_choice() -> void:
	var b := _battle("a_deadly_encounter", 4)
	b.scen["vp"] = [0, 2]
	var choices := Twists.start_of_round_choices(b)
	assert_eq(choices.size(), 1)
	assert_eq(choices[0]["player"], 0, "the trailing player condemns")


func test_rolling_fog_limits_sight() -> void:
	var b := H.bare_battle()
	b.scen["fog"] = [0]
	var a := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(4, 4))
	var t := H.add(b, "verminkin", "verminkin_warrior", 1, Vector2(14, 4))
	assert_false(Effects.visibility(b, a, t)["visible"], "fogged quarter: no sight beyond 6\"")
	b.scen["fog"] = []
	assert_true(Effects.visibility(b, a, t)["visible"])


func test_eldritch_barrier_penalises_shots_across_it() -> void:
	var b := H.bare_battle()
	var w := H.add(b, "guild_mercenaries", "guild_wizard", 0, Vector2(10, 4))
	var s := H.add(b, "guild_mercenaries", "guild_mercenary", 1, Vector2(4, 10), ["crossbow"])
	var t := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(14, 10))
	b.scen["barriers"] = [{"a": Vector2(9, 7), "b": Vector2(9, 13), "elev": 0.0, "caster": w.uid}]
	var explain: Array = []
	Effects.attack_mod(b, s, s.weapon_by_id("crossbow"), t, true, explain)
	assert_true("Eldritch Barrier -1" in explain)
	w.where = "down"
	explain = []
	Effects.attack_mod(b, s, s.weapon_by_id("crossbow"), t, true, explain)
	assert_false("Eldritch Barrier -1" in explain, "the barrier ends when the caster is taken down")


func test_vortex_blocks_sight() -> void:
	var b := H.bare_battle()
	var a := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(4, 10))
	var t := H.add(b, "verminkin", "verminkin_warrior", 1, Vector2(14, 10))
	b.scen["vortex"] = {"c": Vector2(9, 10), "r": 1.5, "elev": 0.0, "rend": -1, "damage": "d3+1", "caster": -1}
	assert_false(Effects.visibility(b, a, t)["visible"])


func test_plague_pit_blocks_floor_moves() -> void:
	var b := H.bare_battle()
	var f := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(5, 10))
	H.add(b, "verminkin", "verminkin_warrior", 1, Vector2(30, 30))
	b.scen["pits"] = [{"c": Vector2(8, 10), "r": 1.5}]
	H.activate(b, f)
	Movement.declare(b, "normal")
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(10, 10)]))["error"].contains("pit"))


func test_doom_forces_a_reroll_of_a_save() -> void:
	var rerolled := false
	for s in 30:
		var b := H.bare_battle(s)
		var a := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(5, 5))
		var t := H.add(b, "verminkin", "verminkin_warrior", 1, Vector2(6.3, 5), ["shield"])
		t.add_effect({"id": "doomed", "until": "battle"})
		Combat.resolve_hit(b, a, t, Catalog.wargear("guild_mercenaries", "sword"), false, {"melee": true, "rend": 0})
		if b.history[-1].contains("DOOMED") or b.history.any(func(l): return l.contains("DOOMED")):
			rerolled = true
			assert_false(t.has_effect("doomed"), "doom is used up")
			break
	assert_true(rerolled)


func test_saint_trickster_spawns_next_treasure() -> void:
	var b := H.bare_battle()
	b.scen["trickster_left"] = 4
	var tok := {"type": "treasure", "pos": Vector2(18, 18), "elev": 0.0, "trickster": true}
	b.tokens = [tok]
	var f := H.add(b, "guild_mercenaries", "guild_mercenary", 0, Vector2(18.5, 18))
	Scenario.pick_up(b, f, 0)
	assert_eq(b.tokens.size(), 1, "a new treasure appears")
	assert_eq(b.scen["trickster_left"], 3)


func test_drunk_hit_staggers() -> void:
	var b := H.bare_battle(2)
	var f := H.add(b, "guild_mercenaries", "guild_captain", 0, Vector2(18, 18))
	H.add(b, "verminkin", "verminkin_warrior", 1, Vector2(30, 30))
	f.statuses["drunk"] = true
	var ended := 0
	for s in 12:
		b.dice = Dice.new(s)
		f.activated = false
		f.statuses["drunk"] = true
		b.active = -1
		H.activate(b, f)
		if b.active == -1:
			ended += 1
		else:
			b.end_activation()
	assert_between(ended, 5, 12, "on 1-5 the drunk Hit's activation ends")
