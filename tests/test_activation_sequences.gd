extends "res://tests/test_case.gd"
## QA: what a fighter may do in each situation, and whether move→action and action→move behave consistently
## (Activations p.19, Moves pp.20-21, Melee p.23, Hide p.27, Ranged p.28, Heavy p.29, Bloodied p.12).

const H := preload("res://tests/helpers.gd")
const GM := "guild_mercenaries"
const VK := "verminkin"
const WALL_Y := 10.0


func _ok(b: Battle, key: String) -> bool:
	var o := Options.for_active(b)
	if key.begins_with("move:"):
		return o["moves"].get(key.trim_prefix("move:"), "missing") == ""
	return o["actions"].get(key, "missing") == ""


func _why(b: Battle, key: String) -> String:
	var o := Options.for_active(b)
	if key.begins_with("move:"):
		return o["moves"].get(key.trim_prefix("move:"), "missing")
	return o["actions"].get(key, "missing")


## A crossbow-and-sword mercenary at `pos`, an enemy at `enemy_pos`, an optional wall along y = 10.
func _setup(pos: Vector2, enemy_pos: Vector2, wall := false, gear := ["sword", "crossbow"]) -> Array:
	var b := H.bare_battle(7)
	if wall:
		b.terrain = [TerrainPiece.make("Wall", "high", Geo.rect_polygon(Vector2(10, WALL_Y), Vector2(8, 0.25)), 4.0)]
	var f := H.add(b, GM, "guild_mercenary", 0, pos, gear)
	var e := H.add(b, VK, "verminkin_warrior", 1, enemy_pos, ["sword"])
	H.activate(b, f)
	return [b, f, e]


func _move(b: Battle, kind: String, to: Vector2) -> String:
	var f := b.active_fighter()
	var err := Movement.declare(b, kind)
	if err != "" or b.move_plan.is_empty():
		return err
	return Movement.commit(b, PackedVector2Array([f.pos, to]))


# --- Free fighter in the open ----------------------------------------------------------------------

func test_open_ground_start() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30))
	var b: Battle = s[0]
	for k in ["move:normal", "move:run", "move:charge", "shoot:crossbow"]:
		assert_true(_ok(b, k), "%s should be allowed: %s" % [k, _why(b, k)])
	assert_false(_ok(b, "move:disengage"), "not engaged: no disengage")
	assert_false(_ok(b, "melee"), "not engaged: no melee")
	assert_true(_why(b, "hide").contains("terrain"), "open ground: can't hide (%s)" % _why(b, "hide"))


func test_move_then_action() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30))
	var b: Battle = s[0]
	assert_eq(_move(b, "normal", Vector2(8, 20)), "")
	assert_false(_ok(b, "move:normal"), "only one move")
	assert_true(_ok(b, "shoot:crossbow"), "action still available after moving: %s" % _why(b, "shoot:crossbow"))


func test_action_then_move() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30))
	var b: Battle = s[0]
	var e: FighterState = s[2]
	assert_eq(Combat.shoot(b, "crossbow", e.uid), "")
	assert_false(_ok(b, "shoot:crossbow"), "only one action")
	assert_true(_ok(b, "move:normal"), "a normal move after the action is fine: %s" % _why(b, "move:normal"))
	assert_false(_ok(b, "move:run"), "Run must come before the action")
	assert_false(_ok(b, "move:charge"), "Charge must come before the action")
	assert_eq(_move(b, "normal", Vector2(2, 20)), "", "and it can actually be made")


func test_run_forbids_the_action() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 34))
	var b: Battle = s[0]
	assert_eq(_move(b, "run", Vector2(9, 20)), "")
	assert_false(_ok(b, "shoot:crossbow"))
	assert_true(_why(b, "hide").length() > 0)


# --- Engaged ---------------------------------------------------------------------------------------

func test_engaged_start() -> void:
	var s := _setup(Vector2(10, 20), Vector2(10, 21.6))
	var b: Battle = s[0]
	assert_true(Effects.is_engaged(b, s[1]))
	assert_true(_ok(b, "melee"))
	assert_true(_ok(b, "move:disengage"))
	for k in ["move:normal", "move:run", "move:charge", "shoot:crossbow", "hide"]:
		assert_false(_ok(b, k), "%s must not be allowed while engaged" % k)


func test_engaged_melee_then_disengage() -> void:
	var s := _setup(Vector2(10, 20), Vector2(10, 21.6))
	var b: Battle = s[0]
	var e: FighterState = s[2]
	assert_eq(Combat.start_melee(b, e.uid, {"weapons": ["sword"]}), "")
	var g := 0
	while not b.pending.is_empty() and g < 40:
		g += 1
		SimpleBot.answer(b)
	if b.active == s[1].uid and e.on_board() and s[1].on_board():
		assert_true(_ok(b, "move:disengage"), "after the melee action the fighter may still disengage: %s" % _why(b, "move:disengage"))
		assert_false(_ok(b, "melee"), "only one action")


func test_engaged_disengage_then_shoot() -> void:
	var passed_once := false
	for seed_value in 12:
		var s := _setup(Vector2(10, 20), Vector2(10, 21.6))
		var b: Battle = s[0]
		b.dice = Dice.new(seed_value)
		var f: FighterState = s[1]
		Movement.declare(b, "disengage")
		if b.move_plan.is_empty():
			assert_true(f.moved, "failed disengage still uses the move")
			assert_true(_ok(b, "melee"), "...but the action remains, and it is still engaged")
			continue
		assert_eq(Movement.commit(b, PackedVector2Array([f.pos, Vector2(10, 17.5)])), "")
		assert_false(Effects.is_engaged(b, f))
		assert_true(_ok(b, "shoot:crossbow"), "after disengaging it may shoot: %s" % _why(b, "shoot:crossbow"))
		passed_once = true
	assert_true(passed_once)


func test_charge_then_melee() -> void:
	var s := _setup(Vector2(10, 20), Vector2(10, 26))
	var b: Battle = s[0]
	var f: FighterState = s[1]
	var e: FighterState = s[2]
	Movement.declare(b, "charge")
	assert_eq(Movement.commit(b, PackedVector2Array([f.pos, e.pos - Vector2(0, f.radius + e.radius + 0.5)])), "")
	assert_true(_ok(b, "melee"), "charge then melee: %s" % _why(b, "melee"))
	assert_false(_ok(b, "shoot:crossbow"), "engaged after the charge: no shooting")


# --- Hiding --------------------------------------------------------------------------------------

func test_hide_needs_terrain_and_distance() -> void:
	var r := 0.63
	var s := _setup(Vector2(10, WALL_Y + 0.125 + r + 0.2), Vector2(10, 30), true)
	var b: Battle = s[0]
	assert_true(_ok(b, "hide"), "next to the wall: may hide (%s)" % _why(b, "hide"))
	var s2 := _setup(Vector2(10, WALL_Y + 0.125 + r + 0.2), Vector2(13, 12.5), true)
	assert_true(_why(s2[0], "hide").contains("within 3"), "enemy within 3\": %s" % _why(s2[0], "hide"))
	var s3 := _setup(Vector2(10, WALL_Y + 0.125 + r + 0.2), Vector2(10, 12.0), true)
	assert_true(_why(s3[0], "hide").contains("engaged"), "engaged: %s" % _why(s3[0], "hide"))


func test_move_to_wall_then_hide() -> void:
	var r := 0.63
	var s := _setup(Vector2(10, 15.5), Vector2(10, 30), true)
	var b: Battle = s[0]
	assert_false(_ok(b, "hide"), "start in the open: can't hide")
	assert_eq(_move(b, "normal", Vector2(10, WALL_Y + 0.125 + r + 0.15)), "")
	assert_true(_ok(b, "hide"), "after moving up to the wall: may hide (%s)" % _why(b, "hide"))
	assert_eq(Combat.hide(b), "")


func test_hide_then_move_away_loses_hidden() -> void:
	var r := 0.63
	var s := _setup(Vector2(10, WALL_Y + 0.125 + r + 0.15), Vector2(10, 30), true)
	var b: Battle = s[0]
	var f: FighterState = s[1]
	assert_eq(Combat.hide(b), "")
	assert_true(f.statuses.get("hidden", false))
	assert_true(_ok(b, "move:normal"), "hide is the action; a move may follow")
	assert_eq(_move(b, "normal", Vector2(10, 14)), "")
	assert_false(f.statuses.get("hidden", false), "moving away from terrain ends hiding")


# --- Restricted activations -------------------------------------------------------------------------

func test_bloodied_move_or_action_both_orders() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30))
	var b: Battle = s[0]
	var f: FighterState = s[1]
	b.end_activation()
	f.life = 1
	f.activated = false
	b.turn = 0
	b.pending = {}
	b.activate(f.uid)
	assert_eq(_move(b, "normal", Vector2(8, 20)), "")
	assert_true(_why(b, "shoot:crossbow").contains("bloodied"), "move first → no action: %s" % _why(b, "shoot:crossbow"))
	var s2 := _setup(Vector2(5, 20), Vector2(5, 30))
	var b2: Battle = s2[0]
	var f2: FighterState = s2[1]
	b2.end_activation()
	f2.life = 1
	f2.activated = false
	b2.turn = 0
	b2.pending = {}
	b2.activate(f2.uid)
	assert_eq(Combat.shoot(b2, "crossbow", s2[2].uid), "")
	assert_true(_why(b2, "move:normal").contains("bloodied"), "action first → no move: %s" % _why(b2, "move:normal"))


func test_heavy_weapon_both_orders() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30), false, ["sword", "long_bow"])
	var b: Battle = s[0]
	assert_eq(_move(b, "normal", Vector2(8, 20)), "")
	assert_true(_why(b, "shoot:long_bow").contains("Heavy"), "moved → can't fire Heavy: %s" % _why(b, "shoot:long_bow"))
	var s2 := _setup(Vector2(5, 20), Vector2(5, 30), false, ["sword", "long_bow"])
	var b2: Battle = s2[0]
	assert_eq(Combat.shoot(b2, "long_bow", s2[2].uid), "")
	assert_true(_why(b2, "move:normal").contains("Heavy"), "fired Heavy → can't move: %s" % _why(b2, "move:normal"))


func test_reload_forgoes_move_or_action() -> void:
	var s := _setup(Vector2(5, 20), Vector2(5, 30))
	var b: Battle = s[0]
	var f: FighterState = s[1]
	assert_eq(Combat.shoot(b, "crossbow", s[2].uid), "")
	assert_eq(Combat.reload_weapon(b, "crossbow", "move"), "")
	assert_false(_ok(b, "move:normal"), "reloading used the move")
	assert_false("crossbow" in f.needs_reload)


func test_caster_arcane_counts_as_the_action() -> void:
	var b := H.bare_battle(3)
	var w := H.add(b, GM, "guild_wizard", 0, Vector2(5, 20), ["arcane_staff"])
	H.add(b, VK, "verminkin_warrior", 1, Vector2(5, 30))
	w.prepared = [Catalog.lore(GM, "saints")["spells"][2].duplicate()]
	H.activate(b, w)
	assert_true(_ok(b, "draw_power"))
	assert_eq(Magic.draw_power(b), "")
	assert_false(_ok(b, "cast:Godspeed"), "drawing power was the action")
	assert_true(_ok(b, "move:normal"))
	assert_false(_ok(b, "move:charge"), "no charge after an action")
