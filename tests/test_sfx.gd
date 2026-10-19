extends "res://tests/test_case.gd"
## Sound effects: which log lines make which sounds, and that every sound is synthesised.


func _names(text: String) -> Array:
	return Sfx.events_for(text).map(func(e): return e["name"])


func test_moves_make_footsteps() -> void:
	var walk := _names("Snikk makes a normal move: 5.5\" used.")
	assert_eq(walk.size(), 4, "about one step per 1.4\"")
	assert_true(walk.all(func(n): return n == "step"))
	var charge := Sfx.events_for("Bones II makes a charge move: 4.6\" used.")
	assert_true(charge[0]["gap"] < 0.2, "charges and runs step faster")
	assert_eq(_names("Mausar declares a Normal move: up to 5.0\"."), [], "declaring makes no sound")


func test_hits_misses_saves_and_parries() -> void:
	assert_eq(_names("Bones II rolls: Spear 2✗ 1✗."), ["swing", "swing"], "missed blows whoosh")
	assert_eq(_names("Bones III rolls: Sword 4✓ 5✓ 1✗."), ["swing"])
	assert_eq(_names("Tertius hits Bones II (CRIT) with Club/Mace/Hammer: armour 4+, rolled 2 — not saved; 2 damage (d3)."), ["hit"])
	assert_eq(_names("Kaspar hits Pestor with Spear: armour 4+, rolled 6 — SAVED."), ["clank"], "a saved blow clanks on armour")
	assert_eq(_names("Pestor hits Bones III (CRIT) with Club: armour 5+, rolled 5 — SAVED; Bludgeon still deals 1."), ["hit"])
	assert_eq(_names("Anton parries Pestor's Great Demonic Rot Blade (rolled 6)."), ["parry"])
	assert_eq(_names("Georg's parry fails (rolled 1)."), ["swing"])
	assert_eq(_names("Georg fires Crossbow (Bow 4+): 1✗."), ["shot", "whiz"], "a missed shot whizzes past")
	assert_eq(_names("Tertius fires Blowpipe (Bow 5+): 6!."), ["shot"])
	assert_eq(_names("☠ Bones III is taken down by Tertius."), ["death", "down"], "a death cry, then the fall")
	assert_eq(_names("— Round 2 —"), [])


func test_every_sound_is_synthesised() -> void:
	Sfx.build_streams()
	for n in ["step", "swing", "whiz", "hit", "clank", "parry", "shot", "down", "death"]:
		assert_true(Sfx.has_sound(n), n)
		var w: AudioStreamWAV = Sfx._streams[n][0]
		assert_true(w.data.size() > 1000, "%s has audio data" % n)
		assert_true(w.get_length() < 1.0, "%s is short" % n)


func test_battle_screen_plays_sounds_without_errors() -> void:
	App.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "a_deadly_encounter", "twist": 0, "seed": 9, "ai": ["normal", "normal"]}
	App.load_battle_path = ""
	var view = load("res://view/battle.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	for i in 120:
		view._ai_do_step()
		view.sfx._process(0.3)
	assert_true(view.sfx._next > 0 or view.sfx._queue.size() > 0, "sounds were played or queued")
	view.queue_free()
