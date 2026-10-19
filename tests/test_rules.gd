extends "res://tests/test_case.gd"
## Rules tests. Page numbers refer to the Black Death City Playtest v1.03 rulebook.

const H := preload("res://tests/helpers.gd")
const GM := "guild_mercenaries"
const VK := "verminkin"


# --- Data & rosters (pp.49-51) -----------------------------------------------------------------

func test_sample_warbands_are_legal() -> void:
	for fac in Catalog.FACTION_IDS:
		var r := Samples.roster(fac)
		var errs := r.validate()
		assert_true(errs.is_empty(), "%s: %s" % [fac, ", ".join(errs)])
		assert_between(r.total_cost(), 700, 1000, fac + " cost")


func test_roster_catches_violations() -> void:
	var r := Samples.roster(GM)
	r.add_member("noble")  # second leader
	var m := r.add_member("guild_mercenary")
	m["equipment"] = ["long_rifle"]  # champion list only
	var m2 := r.add_member("guild_mercenary")
	m2["equipment"] = ["shield", "blackpowder_rifle"]  # held item + two-handed ranged
	var errs := " | ".join(r.validate())
	assert_true(errs.contains("exactly 1 Leader"), errs)
	assert_true(errs.contains("cannot take Long Rifle"), errs)
	assert_true(errs.contains("held item with a two-handed ranged"), errs)


func test_roster_rare_and_budget() -> void:
	var r := Samples.roster(GM)
	for i in 2:
		var m := r.add_member("guild_mercenary")
		m["equipment"] = ["volley_rifle"]  # Rare 0-1
	var errs := " | ".join(r.validate())
	assert_true(errs.contains("Rare 0-1"), errs)
	assert_true(errs.contains("Over budget"), errs)


func test_origin_overrides_limits() -> void:
	var r := Roster.new()
	r.faction = "blighted_cloister"
	r.origin = "knights_militant"
	assert_eq(r.limit_for("cloister_knight"), 99)
	r.origin = "blessed_rabble"
	assert_eq(r.limit_for("cloister_knight"), 3)


# --- Dice (p.8) ---------------------------------------------------------------------------------

func test_dice_expressions() -> void:
	var d := Dice.new(3)
	for i in 300:
		assert_between(d.d3(), 1, 3)
		assert_between(d.roll("d3+1"), 2, 4)
		var x := d.roll("3d6x5")
		assert_true(x % 5 == 0 and x >= 15 and x <= 90, "3d6x5 = %d" % x)
	assert_eq(Dice.add("d3", 1), "d3+1")
	assert_eq(Dice.add("d3+1", -1), "d3")
	assert_eq(Dice.add("2", 1), "3")


func test_tests_pass_on_low_rolls() -> void:
	var d := Dice.new(9)
	for i in 100:
		var t := d.test(3)
		assert_eq(t["pass"], t["roll"] <= 3)


# --- Visibility & cover (pp.9, 28) ---------------------------------------------------------------

func test_high_wall_blocks_low_wall_obscures() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10))
	var t := H.add(b, VK, "verminkin_warrior", 1, Vector2(15, 10))
	assert_true(Effects.visibility(b, a, t)["visible"])
	assert_false(Effects.visibility(b, a, t)["obscured"])
	b.terrain.append(TerrainPiece.make("Wall", "high", Geo.rect_polygon(Vector2(10, 10), Vector2(0.5, 6)), 3.0))
	assert_false(Effects.visibility(b, a, t)["visible"], "high wall blocks")
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(14, 10), Vector2(0.4, 4)), 1.0)]
	var v := Effects.visibility(b, a, t)
	assert_true(v["visible"] and v["obscured"], "low wall next to target: visible but obscured")
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(6.5, 10), Vector2(0.4, 4)), 1.0)]
	assert_false(Effects.visibility(b, a, t)["obscured"], "low wall far from the target doesn't hide it")


func test_hidden_fighter_invisible_when_obscured() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10))
	var t := H.add(b, VK, "verminkin_warrior", 1, Vector2(15, 10))
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(14, 10), Vector2(0.4, 4)), 1.0)]
	t.statuses["hidden"] = true
	assert_false(Effects.visibility(b, a, t)["visible"])
	H.add(b, GM, "hunting_dog", 0, Vector2(9, 14))
	assert_true(Effects.visibility(b, a, t)["visible"], "Sniff 'em Out reveals hidden fighters within 9\"")


# --- Moves (pp.20-22) ---------------------------------------------------------------------------

func test_normal_move_limits() -> void:
	var b := H.bare_battle()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(5, 12))
	assert_eq(H.activate(b, f), "")
	assert_eq(Movement.declare(b, "normal"), "")
	assert_approx(b.move_plan["allowance"], 5.0)
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(10.1, 5)]))["error"].begins_with("Too far"))
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(5, 10)]))["error"].contains("within 1\""), "can't come within 1\" of an enemy")
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(7.5, 5), Vector2(0.4, 4)), 1.0)]
	var ev := Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(9.5, 5)]))
	assert_true(ev["error"].begins_with("Too far"), "4.5\" + 1\" for low terrain > 5\"")
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(8.9, 5)]))["ok"])
	assert_eq(Movement.commit(b, PackedVector2Array([f.pos, Vector2(8.9, 5)])), "")
	assert_true(f.moved)
	assert_true(Movement.declare(b, "normal") != "", "only one move per activation")


func test_charge_must_end_engaged_or_fails() -> void:
	var b := H.bare_battle(5)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	var e := H.add(b, VK, "verminkin_warrior", 1, Vector2(5, 11))
	H.activate(b, f)
	assert_eq(Movement.declare(b, "charge"), "")
	assert_true(b.move_plan["allowance"] >= 6.0)
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(8, 5)]))["error"].contains("within 1\""))
	var stop := e.pos - Vector2(0, f.radius + e.radius + 0.5)
	assert_eq(Movement.commit(b, PackedVector2Array([f.pos, stop])), "")
	assert_true(f.charged and Effects.is_engaged(b, f))
	# A failed charge ends the activation.
	var b2 := H.bare_battle(5)
	var g := H.add(b2, GM, "guild_mercenary", 0, Vector2(2, 2))
	H.add(b2, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b2, g)
	Movement.declare(b2, "charge")
	assert_eq(Movement.fail_charge(b2), "")
	assert_eq(b2.active, -1)
	assert_eq(g.pos, Vector2(2, 2))


func test_cannot_move_through_buildings_or_fighters() -> void:
	var b := H.bare_battle()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	H.add(b, GM, "guild_mercenary", 0, Vector2(7, 5))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	b.terrain = [TerrainPiece.make("House", "high", Geo.rect_polygon(Vector2(5, 8), Vector2(4, 1)), 4.0)]
	H.activate(b, f)
	Movement.declare(b, "normal")
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(9, 5)]))["error"].contains("through"))
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(5, 9.5)]))["error"].contains("runs into"))


func test_disengage_needs_initiative_and_distance() -> void:
	var b := H.bare_battle(2)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 11.6))
	H.activate(b, f)
	assert_true(Movement.declare(b, "normal") != "", "engaged fighters can only disengage")
	assert_eq(Movement.declare(b, "disengage"), "")
	if b.move_plan.is_empty():
		assert_true(f.moved, "failed disengage uses the move")
	else:
		assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(10, 9.5)]))["error"].contains("more than 1\""))
		assert_eq(Movement.commit(b, PackedVector2Array([f.pos, Vector2(10, 7.4)])), "")


# --- Attacks (pp.24, 28) -------------------------------------------------------------------------

func test_rend_can_make_saves_impossible() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	var t := H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 5))
	assert_eq(Effects.armour_value(b, t), 6)
	var axe := Catalog.wargear(GM, "axe")
	var start := t.life
	Combat.resolve_hit(b, a, t, axe, false, {"melee": true, "rend": -1})
	assert_eq(t.life, start - 1, "6+ vs Rend -1: no armour roll, 1 damage")
	assert_true(b.history[-1].contains("no armour roll"), b.history[-1])


func test_shield_and_cover_improve_armour() -> void:
	var b := H.bare_battle()
	var t := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5), ["shield", "cuirass"])
	assert_eq(Effects.armour_value(b, t), 4)
	assert_eq(Effects.armour_value(b, t, {"cover": true}), 3)
	var plate := H.add(b, "blighted_cloister", "knight_abbot", 0, Vector2(9, 5), ["shield"])
	assert_eq(Effects.armour_value(b, plate, {"cover": true}), 2, "4+ improved twice = 2+")
	plate.add_effect({"id": "will_of_the_saints", "until": "round"})
	assert_eq(Effects.armour_value(b, plate, {"cover": true}), 2, "never better than 2+")


func test_closest_target_rule() -> void:
	var b := H.bare_battle()
	var s := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10), ["crossbow"])
	var near := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 10))
	var mid := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 14))
	var far := H.add(b, VK, "verminkin_warrior", 1, Vector2(18, 4))
	var w := s.weapon_by_id("crossbow")
	var legal := []
	for e in Combat.ranged_targets(b, s, w):
		if e["legal"]:
			legal.append(e["uid"])
	assert_eq(legal, [near.uid], "only the closest visible enemy")
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(11, 10), Vector2(0.4, 3)), 1.0)]
	legal = []
	for e in Combat.ranged_targets(b, s, w):
		if e["legal"]:
			legal.append(e["uid"])
	assert_eq(legal, [near.uid, mid.uid], "closest is obscured, so the closest non-obscured is also legal")
	assert_false(far.uid in legal)


func test_engaged_enemies_cannot_be_shot() -> void:
	var b := H.bare_battle()
	var s := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10), ["crossbow"])
	H.add(b, GM, "guild_mercenary", 0, Vector2(12, 11.6))
	var engaged := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 10))
	var free := H.add(b, VK, "verminkin_warrior", 1, Vector2(16, 6))
	var w := s.weapon_by_id("crossbow")
	for e in Combat.ranged_targets(b, s, w):
		if e["uid"] == engaged.uid:
			assert_false(e["legal"])
		if e["uid"] == free.uid:
			assert_true(e["legal"])


func test_shooting_marks_reload_and_action() -> void:
	var b := H.bare_battle(4)
	var s := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10), ["crossbow"])
	var t := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 10))
	H.activate(b, s)
	assert_eq(Combat.shoot(b, "crossbow", t.uid), "")
	assert_true(s.acted)
	assert_true("crossbow" in s.needs_reload)
	assert_true(Combat.check_can_shoot(b, s, s.weapon_by_id("crossbow")) != "")
	assert_eq(Combat.reload_weapon(b, "crossbow", "move"), "")
	assert_false("crossbow" in s.needs_reload)
	assert_true(s.moved)


func test_heavy_weapon_after_move() -> void:
	var b := H.bare_battle()
	var s := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10), ["long_bow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(20, 10))
	H.activate(b, s)
	Movement.declare(b, "normal")
	Movement.commit(b, PackedVector2Array([s.pos, Vector2(7, 10)]))
	assert_true(Combat.check_can_shoot(b, s, s.weapon_by_id("long_bow")).contains("Heavy"))


# --- Melee duel (pp.23-26) ---------------------------------------------------------------------

func _duel_setup(seed_value: int) -> Array:
	var b := H.bare_battle(seed_value)
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword", "shield", "cuirass"])
	var d := H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 11.4), ["axe", "dagger"])
	H.activate(b, a)
	return [b, a, d]


func test_melee_duel_runs_to_completion() -> void:
	for s in 20:
		var setup := _duel_setup(s)
		var b: Battle = setup[0]
		var a: FighterState = setup[1]
		var d: FighterState = setup[2]
		assert_eq(Combat.start_melee(b, d.uid, {"weapons": ["sword"]}), "")
		assert_eq(b.pending["type"], "melee_weapons")
		assert_eq(b.pending["player"], 1, "the defender picks their own weapons")
		assert_eq(b.respond({"weapons": ["axe", "dagger"]}), "")
		var guard := 0
		while b.pending.get("type", "") == "duel_turn" and guard < 30:
			guard += 1
			var opts := Combat.duel_options(b)
			assert_false(opts.is_empty())
			assert_eq(b.respond(opts[guard % opts.size()]["choice"]), "")
		assert_true(b.duel.is_empty(), "duel finished")
		assert_true(a.acted)


func test_charger_has_initiative_unless_brace() -> void:
	var b := H.bare_battle(1)
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	var d := H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 11.4), ["spear"])
	H.activate(b, a)
	a.charged = true
	Combat.start_melee(b, d.uid, {"weapons": ["sword"]})
	b.respond({"weapons": ["spear"]})
	assert_true(b.history.any(func(l): return l.contains("braces against the charge")))
	var b2 := H.bare_battle(1)
	var a2 := H.add(b2, GM, "guild_mercenary", 0, Vector2(10, 10), ["sword"])
	var d2 := H.add(b2, VK, "verminkin_warrior", 1, Vector2(10, 11.4), ["sword"])
	H.activate(b2, a2)
	a2.charged = true
	Combat.start_melee(b2, d2.uid, {"weapons": ["sword"]})
	b2.respond({"weapons": ["sword"]})
	assert_true(b2.history.any(func(l): return l.contains("charged and has the initiative")))


func test_parrying_a_crit_needs_a_crit() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["axe"])
	var d := H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 11.4), ["sword"])
	b.duel = {"att": a.uid, "def": d.uid, "turn": d.uid, "guard_used": [], "feint_used": false, "rolls": {
		str(a.uid): [{"w": "axe", "name": "Axe", "nat": 6, "crit": true, "hit": true, "used": false, "can_parry": true, "parryable": true, "guard": false}],
		str(d.uid): [{"w": "sword", "name": "Sword", "nat": 5, "crit": false, "hit": true, "used": false, "can_parry": true, "parryable": true, "guard": true}],
	}}
	for o in Combat.duel_options(b):
		assert_false(o["choice"]["action"] == "parry", "a normal hit can't parry a critical hit")
	d.skills.append("duellist")
	var can_parry := false
	for o in Combat.duel_options(b):
		if o["choice"]["action"] == "parry":
			can_parry = true
	assert_true(can_parry, "Duellist can parry crits with any success")


func test_guard_miss_can_parry_a_hit_once() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["axe"])
	var d := H.add(b, GM, "guild_mercenary", 1, Vector2(10, 11.4), ["sword"])
	b.duel = {"att": a.uid, "def": d.uid, "turn": d.uid, "guard_used": [], "feint_used": false, "rolls": {
		str(a.uid): [{"w": "axe", "name": "Axe", "nat": 4, "crit": false, "hit": true, "used": false, "can_parry": true, "parryable": true, "guard": false}],
		str(d.uid): [{"w": "sword", "name": "Sword", "nat": 2, "crit": false, "hit": false, "used": false, "can_parry": true, "parryable": true, "guard": true}],
	}}
	var parry := {}
	for o in Combat.duel_options(b):
		if o["choice"]["action"] == "parry":
			parry = o["choice"]
	assert_false(parry.is_empty(), "a Guard miss can parry a hit")


# --- Activations (pp.12, 19) --------------------------------------------------------------------

func test_bloodied_gets_move_or_action() -> void:
	var b := H.bare_battle()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5), ["crossbow"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(25, 25))
	f.life = 1
	H.activate(b, f)
	Movement.declare(b, "normal")
	Movement.commit(b, PackedVector2Array([f.pos, Vector2(7, 5)]))
	assert_false(b.can_still_act(f), "bloodied: no action after moving")
	b.heal(f, 1)
	assert_true(b.can_still_act(f), "healing lifts the penalty for this activation")


func test_surge_activation_flow() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	var x := H.add(b, VK, "verminkin_warrior", 1, Vector2(25, 25))
	var y := H.add(b, VK, "verminkin_warrior", 1, Vector2(28, 25))
	b.turn = 0
	assert_eq(b.activate(a.uid), "")
	b.end_activation()
	assert_eq(b.turn, 1)
	b.activate(x.uid)
	b.end_activation()
	assert_eq(b.pending.get("type", ""), "surge_or_pass", "player 0 is out of fighters and may surge")
	assert_eq(b.respond({"uid": a.uid}), "")
	assert_true(a.surged and b.active == a.uid)
	Movement.declare(b, "normal")
	Movement.commit(b, PackedVector2Array([a.pos, Vector2(7, 5)]))
	assert_false(b.can_still_act(a), "surge: a move OR an action")
	b.end_activation()
	assert_eq(b.turn, 1)
	b.activate(y.uid)


func test_flee_test_triggers_at_five() -> void:
	var b := H.bare_battle(11)
	for i in 6:
		var f := H.add(b, GM, "guild_mercenary", 0, Vector2(3 + i * 2, 3))
		if i < 5:
			f.where = "down"
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	assert_eq(b._flee_count(0), 5)
	assert_eq(b._flee_count(1), 0)


func test_poison_never_kills_alone() -> void:
	var b := H.bare_battle()
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	f.life = 2
	f.statuses["poisoned"] = true
	H.activate(b, f)
	assert_eq(f.life, 1)
	assert_false(f.statuses.get("poisoned", false), "poison ends at 1 life")


func test_undead_cannot_be_poisoned() -> void:
	var b := H.bare_battle()
	var z := H.add(b, "death_covens", "zombie", 0, Vector2(5, 5))
	assert_false(z.can_be_poisoned())


# --- Magic (pp.33-34) ----------------------------------------------------------------------------

func test_casting_and_miscast_bookkeeping() -> void:
	var cast_ok := 0
	for s in 40:
		var b := H.bare_battle(s)
		var w := H.add(b, GM, "guild_wizard", 0, Vector2(5, 5), ["arcane_staff"])
		var e := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 5))
		w.prepared = [Catalog.lore(GM, "sanctioned_magic")["spells"][0].duplicate()]
		w.prepared[0]["lore"] = "sanctioned_magic"
		H.activate(b, w)
		assert_eq(Magic.cast(b, "Arcane Missile", {}), "")
		assert_true(w.acted or not w.on_board())
		if e.life < 4:
			cast_ok += 1
	assert_between(cast_ok, 5, 40, "Arcane Missile sometimes wounds")


func test_draw_power_adds_a_die() -> void:
	var b := H.bare_battle(8)
	var w := H.add(b, GM, "guild_wizard", 0, Vector2(5, 5), ["arcane_staff"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 5))
	w.prepared = [Catalog.lore(GM, "saints")["spells"][2].duplicate()]
	H.activate(b, w)
	assert_eq(Magic.draw_power(b), "")
	assert_true(w.statuses.get("drawn_power", false))
	b.end_activation()
	b.turn = 0
	w.activated = false
	b.pending = {}
	b.activate(w.uid)
	assert_true(w.statuses.get("drawn_power", false), "still available on the next activation")
	Magic.cast(b, "Godspeed", {})
	assert_true(b.history.any(func(l): return l.contains("rolled") and l.contains(",")), "two casting dice")


func test_placement_rejects_overlapping_bases() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10))
	var probe := FighterState.new()
	probe.radius = a.radius
	probe.player = 0
	assert_true(Magic._placement_ok(b, probe, Vector2(10.5, 10)).contains("Overlaps"))
	assert_eq(Magic._placement_ok(b, probe, Vector2(11.3, 10)), "")


func test_placement_keeps_bases_out_of_walls() -> void:
	var b := H.bare_battle()
	b.terrain = [TerrainPiece.make("Thin wall", "high", Geo.rect_polygon(Vector2(10, 10), Vector2(6, 0.25)), 4.0)]
	var probe := FighterState.new()
	probe.radius = Geo.radius_from_mm(32.0)
	probe.player = 0
	assert_true(Magic._placement_ok(b, probe, Vector2(10, 10.5)).contains("overlap"), "centre beside the wall, base overlapping it")
	assert_eq(Magic._placement_ok(b, probe, Vector2(10, 10.9)), "")


func test_auto_deployment_never_overlaps_terrain() -> void:
	for sc in Scenario.ORDER:
		for s in 3:
			var b := Battle.new()
			b.setup(Samples.roster("verminkin"), Samples.roster("blighted_cloister"), sc, -1, 500 + s)
			var g := 0
			while b.round_no < 4 and g < 400 and not b.is_over():
				g += 1
				if not SimpleBot.step(b):
					break
			for f in b.on_board():
				for t in b.terrain:
					if t.blocks_movement() and f.elev <= Height.LEVEL_EPS:
						assert_false(Geo.base_overlaps_polygon(f.pos, f.radius - 0.02, t.polygon), "%s %s overlaps %s at %s" % [sc, f.name, t.name, f.pos])


func test_hide_next_to_a_wall() -> void:
	var b := H.bare_battle()
	b.terrain = [TerrainPiece.make("Wall", "high", Geo.rect_polygon(Vector2(10, 10), Vector2(6, 0.25)), 4.0)]
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10.125 + 0.63 + 0.2))  # 0.2" gap, as when placed by clicking
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	assert_eq(Combat.hide_problem(b, f), "")
	assert_eq(Combat.hide(b), "")
	assert_true(f.statuses.get("hidden", false))
	var b2 := H.bare_battle()
	var g := H.add(b2, GM, "guild_mercenary", 0, Vector2(10, 10))
	H.add(b2, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b2, g)
	assert_true(Combat.hide_problem(b2, g).contains("terrain"), "open ground: the reason is shown")


func test_dice_are_fair_and_seeds_unpredictable() -> void:
	var d := Dice.new(2024)
	var counts := [0, 0, 0, 0, 0, 0, 0]
	var n := 120000
	for i in n:
		counts[d.d6()] += 1
	var chi := 0.0
	for f in range(1, 7):
		chi += pow(counts[f] - n / 6.0, 2) / (n / 6.0)
	assert_true(chi < 20.5, "d6 chi-square %.1f (fair dice: well under 20.5)" % chi)
	var b1 := Battle.new()
	b1.setup(Samples.roster("verminkin"), Samples.roster("death_covens"), "a_deadly_encounter", 0)
	var b2 := Battle.new()
	b2.setup(Samples.roster("verminkin"), Samples.roster("death_covens"), "a_deadly_encounter", 0)
	assert_true(b1.dice.rng.seed != b2.dice.rng.seed, "two random battles get different seeds")
	assert_true(b1.history.any(func(l): return l.begins_with("Dice seed:")), "the seed is logged for replays")
	var b3 := Battle.new()
	b3.setup(Samples.roster("verminkin"), Samples.roster("death_covens"), "a_deadly_encounter", 0, b1.dice.rng.seed)
	assert_eq(b3.terrain.size(), b1.terrain.size(), "same seed, same battle")


func test_summoned_fighter_activates_the_same_round() -> void:
	var b: Battle
	var z: FighterState = null
	for s in 80:
		b = H.bare_battle(s)
		var n := H.add(b, "death_covens", "necromancer", 0, Vector2(10, 10), ["arcane_staff"])
		H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 20), ["sword"])
		H.add(b, VK, "verminkin_warrior", 1, Vector2(14, 20), ["sword"])
		n.prepared = [Catalog.lore("death_covens", "necromancy")["spells"][2].duplicate()]
		H.activate(b, n)
		Magic.cast(b, "Raise Zombie", {"point": Vector2(10, 12.0)})
		for f in b.fighters:
			if f.summoned:
				z = f
		if z != null:
			break
	assert_true(z != null, "Raise Zombie succeeded on some seed")
	assert_false(z.activated, "summoned fighters join unactivated")
	b.end_activation()
	assert_eq(b.turn, 1)
	b.activate(b.can_activate_normally(1)[0].uid)
	b.end_activation()
	assert_eq(b.turn, 0, "player 0 still has a fighter to activate this round: the Zombie")
	assert_true(z in b.can_activate_normally(0))
	assert_eq(b.activate(z.uid), "")


func test_offhand_choices_and_defaults() -> void:
	var b := H.bare_battle()
	var one := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 5), ["dagger"])
	assert_eq(Combat.default_weapons(one), [0, -1], "one weapon: nothing to choose, no off-hand")
	assert_true(Combat.offhand_choices(one, 0).is_empty(), "a weapon can't be its own off-hand")
	var two := H.add(b, GM, "guild_mercenary", 0, Vector2(8, 5), ["dagger", "axe"])
	var dw := Combat.default_weapons(two)
	assert_eq(two.melee[dw[0]]["id"], "axe", "the more damaging off-hand weapon is the main weapon")
	assert_eq(two.melee[dw[1]]["id"], "dagger", "the less damaging one goes in the off hand")
	var big := H.add(b, GM, "guild_mercenary", 0, Vector2(11, 5), ["zweihander", "dagger"])
	assert_true(Combat.offhand_choices(big, 0).is_empty(), "two-handed main weapon: no off-hand")
	var pair := H.add(b, GM, "guild_mercenary", 0, Vector2(14, 5), ["dagger", "dagger"])
	assert_eq(Combat.weapon_ids(pair, 0, 1), ["dagger", "dagger"])
	assert_eq(Combat._check_weapons(pair, ["dagger", "dagger"]), "", "two of the same weapon can be dual-wielded")
	assert_true(Combat._check_weapons(one, ["dagger", "dagger"]) != "", "but not one dagger twice")


func test_melee_without_choice_uses_suggested_weapons() -> void:
	var b := H.bare_battle(4)
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(10, 10), ["dagger", "axe"])
	var d := H.add(b, VK, "verminkin_warrior", 1, Vector2(10, 11.4), ["sword"])
	H.activate(b, a)
	assert_eq(Combat.start_melee(b, d.uid, {}), "")
	assert_eq(b.duel["att_w"], ["axe", "dagger"])


## p.33: drawn power lasts until the end of the fighter's next activation; drawing again then keeps it going.
func test_drawn_power_expires_after_next_activation_unless_redrawn() -> void:
	var b := H.bare_battle(8)
	var w := H.add(b, GM, "guild_wizard", 0, Vector2(5, 5), ["arcane_staff"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	w.prepared = [Catalog.lore(GM, "saints")["spells"][2].duplicate()]
	var again := func():
		b.turn = 0
		w.activated = false
		b.pending = {}
		b.activate(w.uid)
	H.activate(b, w)
	assert_eq(Magic.draw_power(b), "")
	b.end_activation()
	again.call()
	assert_eq(Magic.draw_power(b), "", "can draw again on the next activation")
	b.end_activation()
	again.call()
	assert_true(w.statuses.get("drawn_power", false), "redrawn power carries to the following activation")
	b.end_activation()   # neither cast nor drew
	assert_false(w.statuses.get("drawn_power", false), "unused power is lost when that activation ends")


## p.33: one casting die miscasts on a natural 1, two dice on any double: 1 in 6 either way.
func test_miscast_odds_one_and_two_dice() -> void:
	var b := H.bare_battle(99)
	var f := FighterState.new()
	for n in [1, 2]:
		var miscasts := 0
		for i in 6000:
			if Magic._casting_roll(b, f, n)["miscast"]:
				miscasts += 1
		assert_between(miscasts / 6000.0, 0.15, 0.183, "%d dice miscast rate" % n)
