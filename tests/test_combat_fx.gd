extends "res://tests/test_case.gd"
## Attack visuals: which log lines make which effects, and that they play during a battle without errors.

const NAMES := {"Hans": 1, "Tik-Tik": 2, "Bones I": 3, "Bones III": 4, "Mausar": 5}


func _ev(text: String) -> Array:
	var list: Array = NAMES.keys()
	list.sort_custom(func(x, y): return x.length() > y.length())
	return CombatFx.events_for(text, NAMES, list)


func test_shots_hits_and_misses() -> void:
	var e := _ev("Hans fires Crossbow (Bow 4+): 4✓ 1✗ 6!.")
	assert_eq(e[0]["kind"], "shot")
	assert_eq(e[0]["from"], 1)
	assert_eq(e[0]["weapon"], "Crossbow")
	assert_eq(e[0]["results"], ["hit", "miss", "crit"])
	var h := _ev("Hans hits Tik-Tik with Crossbow: no armour roll possible; 1 damage (1).")
	assert_eq([h[0]["kind"], h[0]["from"], h[0]["to"], h[0]["dmg"], h[0]["saved"]], ["hit", 1, 2, 1, false])
	var s := _ev("Bones III hits Bones I (CRIT) with Sword: armour 5+, rolled 6 — SAVED.")
	assert_eq([s[0]["from"], s[0]["to"], s[0]["crit"], s[0]["saved"]], [4, 3, true, true], "longest names match first")
	var bl := _ev("Bones III hits Bones I (CRIT) with Club: armour 5+, rolled 5 — SAVED; Bludgeon still deals 1.")
	assert_eq([bl[0]["dmg"], bl[0]["saved"]], [1, false])


func test_melee_misses_parries_spells_and_damage() -> void:
	assert_eq(_ev("Bones I rolls: Spear 2✗ 1✗.")[0]["text"], "MISS ×2")
	assert_eq(_ev("Bones I rolls: Spear 5✓."), [], "no misses, nothing to show")
	assert_eq(_ev("Hans parries Tik-Tik's Sword (rolled 6).")[0]["kind"], "parry")
	assert_eq(_ev("Hans's parry fails (rolled 1).")[0]["text"], "PARRY FAILS")
	var c := _ev("Mausar casts Arcane Missile: rolled 6 + Willpower 4 = 10 vs 7+ — CRITICAL CAST.")
	assert_eq([c[0]["kind"], c[0]["ok"]], ["cast", true])
	assert_true(_ev("Mausar attempts Raise Zombie: rolled 6, 6 — MISCAST!")[0]["miscast"])
	assert_eq(_ev("Uncontrolled Burst of Power (10): Mausar suffers 2 damage and is taken down."), [], "only lines that start with the fighter")
	assert_eq(_ev("Mausar suffers 2 damage (impact).")[0]["text"], "-2")
	assert_eq(_ev("— Round 2 —"), [])


func test_effects_play_through_a_battle() -> void:
	App.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "a_deadly_encounter", "twist": 0, "seed": 21, "ai": ["normal", "normal"]}
	App.load_battle_path = ""
	var view = load("res://view/battle.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	var played := 0
	for i in 220:
		view._ai_do_step()
		played += view.fx._queue.size()
		view.fx._process(0.5)
		if view.b.is_over():
			break
	assert_true(played > 0, "attack effects were queued and played")
	view.queue_free()
