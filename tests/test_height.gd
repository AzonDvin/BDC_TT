extends "res://tests/test_case.gd"
## Height rules: platforms, ladders, climbing, jumping, falling, vantage, 3D distance and sight (pp.16, 21-22, 28, 31).

const H := preload("res://tests/helpers.gd")
const GM := "guild_mercenaries"
const VK := "verminkin"


## A 6x6 upper floor at 3" over (10..16, 10..16), a wall under its west edge, and a ladder on its east edge.
func _ruin(b: Battle) -> void:
	b.terrain.append(TerrainPiece.make("Floor", "platform", Geo.rect_polygon(Vector2(13, 13), Vector2(6, 6)), 3.0))
	b.terrain.append(TerrainPiece.make("Wall", "high", Geo.rect_polygon(Vector2(9.75, 13), Vector2(0.5, 6)), 4.0))
	b.terrain.append(TerrainPiece.make("Ladder", "ladder", Geo.rect_polygon(Vector2(16.2, 13), Vector2(0.4, 1.0)), 3.0))


func _levels(a: float, c: float) -> PackedFloat32Array:
	return PackedFloat32Array([a, c])


func test_ladder_costs_one_inch() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(17.3, 13))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	Movement.declare(b, "normal")
	var ev := Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(15.3, 13)]), false, _levels(0, 3))
	assert_true(ev["ok"], ev["error"])
	assert_approx(ev["cost"], 1.0, 0.01, "ladder: 1\" instead of measuring the climb")
	assert_eq(Movement.commit(b, PackedVector2Array([f.pos, Vector2(15.3, 13)]), false, _levels(0, 3)), "")
	assert_approx(f.elev, 3.0)


func test_climbing_a_wall_counts_vertical_distance() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(8.8, 13))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	Movement.declare(b, "normal")
	var ev := Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(10.7, 13)]), false, _levels(0, 3))
	assert_true(ev["ok"], ev["error"])
	assert_approx(ev["cost"], 3.0 + 1.9, 0.01, "3\" up + 1.9\" across")
	assert_false(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(10.9, 13)]), false, _levels(0, 3))["ok"], "5.1\" is over a 5\" move")


func test_beasts_cannot_climb() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var dog := H.add(b, GM, "hunting_dog", 0, Vector2(8.8, 13))
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, dog)
	Movement.declare(b, "normal")
	var ev := Movement.evaluate(b, PackedVector2Array([dog.pos, Vector2(10.9, 13)]), false, _levels(0, 3))
	assert_false(ev["ok"])
	assert_true(ev["error"].contains("can't climb"), ev["error"])


func test_jumping_down_causes_impact_damage() -> void:
	var b := H.bare_battle(3)
	b.terrain.append(TerrainPiece.make("Roof", "high", Geo.rect_polygon(Vector2(13, 13), Vector2(4, 4)), 4.0))
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(14.5, 13))
	f.elev = 4.0
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	Movement.declare(b, "normal")
	var path := PackedVector2Array([f.pos, Vector2(16.5, 13)])
	var ev := Movement.evaluate(b, path, false, _levels(4, 0), "jump")
	assert_true(ev["ok"], ev["error"])
	assert_approx(ev["cost"], 2.0, 0.01, "only the horizontal distance counts when jumping")
	assert_eq(ev["drops"], [4.0])
	Movement.commit(b, path, false, _levels(4, 0), "jump")
	assert_approx(f.elev, 0.0)
	assert_true(b.history.any(func(l): return l.contains("impact rolls")), "4\" drop: impact damage is rolled")


func test_jump_gap_max_three_inches() -> void:
	var b := H.bare_battle()
	b.terrain.append(TerrainPiece.make("Roof A", "high", Geo.rect_polygon(Vector2(10, 10), Vector2(4, 4)), 4.0))
	b.terrain.append(TerrainPiece.make("Roof B", "high", Geo.rect_polygon(Vector2(16.5, 10), Vector2(4, 4)), 4.0))
	b.terrain.append(TerrainPiece.make("Roof C", "high", Geo.rect_polygon(Vector2(25, 10), Vector2(4, 4)), 4.0))
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(11.5, 10))
	f.elev = 4.0
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	Movement.declare(b, "run")
	b.move_plan["allowance"] = 20.0
	assert_true(Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(15.5, 10)]), false, _levels(4, 4))["ok"], "2.5\" gap: jump it")
	var ev := Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(24, 10)]), false, _levels(4, 4))
	assert_false(ev["ok"], "too far to jump straight across two gaps")


func test_must_end_on_a_surface() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var f := H.add(b, GM, "guild_mercenary", 0, Vector2(15, 13))
	f.elev = 3.0
	H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
	H.activate(b, f)
	Movement.declare(b, "normal")
	var ev := Movement.evaluate(b, PackedVector2Array([f.pos, Vector2(18, 13)]), false, _levels(3, 3))
	assert_false(ev["ok"], "can't end standing on air")


func test_engagement_and_range_are_3d() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var up := H.add(b, GM, "guild_mercenary", 0, Vector2(12, 12))
	up.elev = 3.0
	var down := H.add(b, VK, "verminkin_warrior", 1, Vector2(12, 12))
	assert_false(Effects.near(up, down, 1.0), "3\" above: not engaged")
	assert_approx(Effects.dist(up, down), 3.0)


func test_floors_block_sight_and_vantage_helps() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var under := H.add(b, GM, "guild_mercenary", 0, Vector2(13, 13))
	var above := H.add(b, VK, "verminkin_warrior", 1, Vector2(13.5, 13.5))
	above.elev = 3.0
	assert_false(Effects.visibility(b, under, above)["visible"], "the upper floor hides fighters on it from those below")
	var sniper := H.add(b, VK, "verminkin_warrior", 1, Vector2(14.5, 11), ["sling"])
	sniper.elev = 3.0
	var target := H.add(b, GM, "guild_mercenary", 0, Vector2(25, 11))
	assert_true(Effects.visibility(b, sniper, target)["visible"])
	var explain: Array = []
	assert_eq(Effects.attack_mod(b, sniper, sniper.weapon_by_id("sling"), target, true, explain), 1)
	assert_true("Vantage +1" in explain)


func test_low_wall_obscures_only_when_close() -> void:
	var b := H.bare_battle()
	var a := H.add(b, GM, "guild_mercenary", 0, Vector2(5, 10))
	var t := H.add(b, VK, "verminkin_warrior", 1, Vector2(15, 10))
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(13.9, 10), Vector2(0.4, 4)), 1.0)]
	var v := Effects.visibility(b, a, t)
	assert_true(v["visible"] and v["obscured"], "low wall in front of the target hides its legs")
	b.terrain = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(Vector2(5.9, 10), Vector2(0.4, 4)), 1.0)]
	v = Effects.visibility(b, a, t)
	assert_false(v["obscured"], "a low wall right in front of the shooter doesn't")


func test_blast_misses_fighters_three_inches_above() -> void:
	var b := H.bare_battle()
	_ruin(b)
	var low := H.add(b, GM, "guild_mercenary", 0, Vector2(20, 13))
	var high := H.add(b, GM, "guild_mercenary", 0, Vector2(14, 13))
	high.elev = 3.0
	assert_true(low in Combat.blast_hits(b, Vector2(20, 13), 0.0))
	assert_false(high in Combat.blast_hits(b, Vector2(14.3, 13), 0.0))
	assert_true(high in Combat.blast_hits(b, Vector2(14.3, 13), 3.0))


func test_damage_near_open_edge_can_cause_fall() -> void:
	var fell := 0
	for s in 30:
		var b := H.bare_battle(s)
		_ruin(b)
		var f := H.add(b, GM, "guild_recruit", 0, Vector2(15.6, 13))
		f.elev = 3.0
		f.life = 3
		H.add(b, VK, "verminkin_warrior", 1, Vector2(30, 30))
		assert_true(Height.near_open_edge(b, f))
		Combat.apply_damage(b, f, 1, null, "test")
		b.after_action()
		if f.elev < 1.0:
			fell += 1
	assert_between(fell, 5, 25, "Initiative 2: about 2 in 3 fall")
