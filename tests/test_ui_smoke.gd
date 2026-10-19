extends "res://tests/test_case.gd"
## Drives the real screens through their own handlers (no rendering) so errors in UI code fail tests.

func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_builder_screen() -> void:
	var view: Control = load("res://view/builder.tscn").instantiate()
	_root().add_child(view)
	view._on_faction(1)
	view._recruit("verminkin_warrior")
	view._fill_editor()
	view._on_origin(2)
	view._set_roster(Samples.roster("death_covens"))
	view.selected_uid = view.roster.members[0]["uid"]
	view._refresh()
	view.queue_free()


func test_battle_screen_flow() -> void:
	App.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("blighted_cloister")], "scenario": "a_deadly_encounter", "twist": 2, "seed": 77}
	App.load_battle_path = ""
	var view = load("res://view/battle.tscn").instantiate()
	_root().add_child(view)
	var b: Battle = view.b
	var moves := 0
	var shots := 0
	var guard := 0
	while guard < 400 and not b.is_over() and b.round_no <= 3:
		guard += 1
		if b.pending.get("type", "") in ["deploy", "place"]:
			# Click the first fighter into place through the view, then auto-place the rest.
			var p: Dictionary = b.pending
			var f := b.fighter(p["uids"][0])
			var spot := Scenario.auto_spot(b, f, p["zone"])
			view._click(spot)
			if b.pending.get("type", "") in ["deploy", "place"]:
				view._do(b.respond({"positions": view.placements.duplicate()}))
				view.placements.clear()
			continue
		if not b.pending.is_empty():
			view._refresh()
			SimpleBot.answer(b)
			continue
		if b.active < 0:
			var c := b.can_activate_normally(b.turn)
			if c.is_empty():
				break
			view._click(c[0].pos)
			continue
		var f2 := b.active_fighter()
		view._refresh()
		if not Effects.is_engaged(b, f2) and b.can_still_move(f2):
			view._declare("normal")
			if view.mode == "move":
				var e := SimpleBot.nearest_enemy(b, f2)
				view._click(f2.pos + (e.pos - f2.pos).normalized() * 2.0)
				view._update_board()
				view._confirm_move()
				if f2.moved:
					moves += 1
				else:
					view._do(Movement.cancel(b))
					view._set_mode("idle")
		for w in f2.usable_ranged():
			if Combat.check_can_shoot(b, f2, w) == "" and not Effects.weapon_has(f2, w, "Blast") and not Effects.weapon_has(f2, w, "Flame"):
				view._start_shoot(w)
				view._update_board()
				for t in Combat.ranged_targets(b, f2, w):
					if t["legal"]:
						view._click(b.fighter(t["uid"]).pos)
						shots += 1
						break
				view._set_mode("idle")
				break
		if b.active == f2.uid and b.pending.is_empty():
			view._do(b.end_activation())
	assert_true(moves > 3, "moves made through the UI: %d" % moves)
	assert_true(b.round_no >= 2, "reached round %d" % b.round_no)
	view.queue_free()
