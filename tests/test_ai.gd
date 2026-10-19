extends "res://tests/test_case.gd"
## The computer player (rules/ai.gd): it answers every decision, finishes battles in every scenario, and makes
## sensible basic choices (charge what it can reach, shoot when it can, pick up treasure in reach).

const H := preload("res://tests/helpers.gd")
const GM := "guild_mercenaries"
const VK := "verminkin"


## Runs the AI until the active fighter's activation is over (both sides AI, so defender decisions are answered too).
func _play_activation(b: Battle) -> void:
	var guard := 0
	while guard < 60 and (b.active >= 0 or not b.pending.is_empty()):
		guard += 1
		if not AI.step(b):
			break


func _bare(seed_value := 7) -> Battle:
	var b := H.bare_battle(seed_value)
	b.cfg["ai"] = ["normal", "normal"]
	return b


func test_charges_an_enemy_in_reach() -> void:
	var b := _bare()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 16), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_true(f.charged, "the swordsman should charge an enemy 4.7\" away")
	assert_eq(b.active, -1, "the activation ends")


func test_shoots_a_visible_enemy() -> void:
	var b := _bare()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword", "crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 22), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	var fired := false
	for line in b.history:
		if str(line).contains("fires Crossbow"):
			fired = true
	assert_true(fired, "a crossbowman with a clear shot fires")


func test_picks_up_treasure_in_reach() -> void:
	var b := _bare()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(32, 32), ["sword"])
	b.tokens.append({"type": "treasure", "pos": Vector2(13, 10), "elev": 0.0})
	H.activate(b, f)
	_play_activation(b)
	assert_eq(f.treasure, 1, "treasure 2.4\" away is picked up with a normal move")


func test_leaves_human_decisions_alone() -> void:
	var b := _bare()
	b.cfg["ai"] = ["", "normal"]
	H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30), ["sword"])
	b.turn = 0
	assert_false(AI.should_act(b), "player 1 is human")
	assert_false(AI.step(b), "the AI does nothing on the human's turn")
	b.turn = 1
	assert_true(AI.should_act(b))


func test_battles_finish_in_every_scenario() -> void:
	var facs := Catalog.FACTION_IDS
	var i := 0
	for sc in Scenario.ORDER:
		var b := Battle.new()
		b.setup(Samples.roster(facs[i % 4]), Samples.roster(facs[(i + 2) % 4]), sc, -1, 300 + i)
		b.cfg["ai"] = ["normal", "normal"] if i % 2 == 0 else ["normal", "easy"]
		i += 1
		var steps := 0
		while steps < 6000 and b.round_no <= 15 and AI.step(b):
			steps += 1
		assert_true(b.is_over() or b.round_no > 15, "%s stalled in round %d (phase %s, pending %s, active %d)" % [sc, b.round_no, b.phase, b.pending.get("type", ""), b.active])


func test_controller_survives_save_and_load() -> void:
	var b := Battle.new()
	b.setup(Samples.roster(GM), Samples.roster(VK), "no_quarter", 0, 5)
	b.cfg["ai"] = ["", "normal"]
	for k in 40:
		if not AI.step(b) and not SimpleBot.step(b):
			break
	assert_eq(b.save_to("user://test_ai_save.bdc"), OK)
	var c := Battle.load_from("user://test_ai_save.bdc")
	assert_eq(AI.controller(c, 1), "normal")
	assert_eq(AI.controller(c, 0), "")


func _wizard(b: Battle, pos: Vector2) -> FighterState:
	var w := H.add(b, GM, "guild_wizard", 0, pos, ["arcane_staff"])
	w.prepared = [Catalog.lore(GM, "sanctioned_magic")["spells"][0].duplicate()]   # Arcane Missile, 15"
	w.prepared[0]["lore"] = "sanctioned_magic"
	return w


func _logged(b: Battle, text: String) -> bool:
	for line in b.history:
		if str(line).contains(text):
			return true
	return false


func test_caster_draws_power_when_no_enemy_is_near() -> void:
	var b := _bare()
	var w := _wizard(b, Vector2(4, 4))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(33, 33), ["sword"])
	H.activate(b, w)
	_play_activation(b)
	assert_true(w.statuses.get("drawn_power", false), "nothing within 6\" and nothing in spell range: power up")
	assert_false(w.charged)


func test_caster_casts_an_attack_spell_instead_of_charging() -> void:
	for s in 6:
		var b := _bare(s)
		var w := _wizard(b, Vector2(10, 10))
		H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 16), ["sword"])
		H.activate(b, w)
		_play_activation(b)
		assert_false(w.charged, "a wizard with Arcane Missile doesn't charge (seed %d)" % s)
		assert_true(_logged(b, "Arcane Missile: rolled"), "it casts at the enemy 4.7\" away (seed %d)" % s)
		if not Effects.is_engaged(b, w) and w.on_board() and w.move_kind == "normal":
			assert_true(Effects.dist(w, b.fighters[1]) > 6.0 or not b.fighters[1].on_board(), "then it steps back out of 6\" (seed %d)" % s)


func test_powered_caster_casts_rather_than_drawing_again() -> void:
	var b := _bare()
	var w := _wizard(b, Vector2(10, 10))
	w.statuses["drawn_power"] = true
	H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 22), ["sword"])
	H.activate(b, w)
	_play_activation(b)
	assert_true(_logged(b, "Arcane Missile: rolled"), "with power drawn and a target 10.7\" away, it casts")


func test_powered_caster_with_nothing_to_cast_draws_again_to_keep_power() -> void:
	var b := _bare()
	var w := _wizard(b, Vector2(4, 4))
	w.statuses["drawn_power"] = true
	H.add(b, VK, "verminkin_warrior", 1, Vector2(33, 33), ["sword"])
	H.activate(b, w)
	_play_activation(b)
	assert_true(_logged(b, "draws power"), "no target in range: draw again")
	assert_true(w.statuses.get("drawn_power", false), "the power is still held for the next activation")


## An upper floor (3" up) with a ladder on its east side, or a solid 2" building with a flat roof.
func _platform(b: Battle) -> void:
	b.terrain.append(TerrainPiece.make("Upper floor", "platform", Geo.rect_polygon(Vector2(12, 10), Vector2(3, 3)), 3.0))
	b.terrain.append(TerrainPiece.make("Ladder", "ladder", Geo.rect_polygon(Vector2(13.7, 10), Vector2(0.4, 1.0)), 3.0))


## The fighter's activation in the next round.
func _again(b: Battle, f: FighterState) -> void:
	b.round_no += 1
	f.activated = false
	H.activate(b, f)
	_play_activation(b)


func test_long_range_shooter_climbs_a_ladder() -> void:
	var b := _bare()
	_platform(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(17, 10), ["sword", "crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 32), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_approx(f.elev, 3.0, 0.2, "a crossbowman (20\") goes up the ladder onto the upper floor")
	assert_true(_logged(b, "ladder"), "by the ladder")


func test_long_range_shooter_climbs_a_wall_onto_a_roof() -> void:
	var b := _bare()
	b.terrain.append(TerrainPiece.make("House", "high", Geo.rect_polygon(Vector2(12, 20), Vector2(3, 3)), 2.0))
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(15.3, 20), ["sword", "crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(32, 6), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_approx(f.elev, 2.0, 0.2, "no ladder: it climbs the wall onto the roof")


func test_high_ground_further_away_is_reached_over_two_activations() -> void:
	var b := _bare()
	_platform(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(23, 10), ["sword", "crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(33, 33), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_true(f.pos.distance_to(Vector2(13.7, 10)) < 5.5, "first it walks toward the ladder")
	_again(b, f)
	assert_approx(f.elev, 3.0, 0.2, "then it climbs")


func test_shooter_holds_high_ground_and_shoots() -> void:
	var b := _bare()
	_platform(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(12, 10), ["sword", "crossbow"])
	f.elev = 3.0
	H.add(b, VK, "verminkin_warrior", 1, Vector2(26, 14), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_approx(f.elev, 3.0, 0.01, "stays up while an enemy is in range")
	assert_true(_logged(b, "fires Crossbow"))


func test_short_range_shooter_stays_on_the_floor() -> void:
	var b := _bare()
	_platform(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(17, 10), ["sword", "hand_crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 32), ["sword"])
	H.activate(b, f)
	_play_activation(b)
	assert_approx(f.elev, 0.0, 0.01, "a 12\" weapon isn't worth climbing for")
