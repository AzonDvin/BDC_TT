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
			view._click(spot, 0.0, null)
			if b.pending.get("type", "") in ["deploy", "place"]:
				view._submit_placements()
			continue
		if not b.pending.is_empty():
			view._refresh()
			SimpleBot.answer(b)
			continue
		if b.active < 0:
			var c := b.can_activate_normally(b.turn)
			if c.is_empty():
				break
			view._click(c[0].pos, c[0].elev, c[0])
			continue
		var f2 := b.active_fighter()
		view._refresh()
		if not Effects.is_engaged(b, f2) and b.can_still_move(f2):
			view._declare("normal")
			if view.mode == "move":
				var e := SimpleBot.nearest_enemy(b, f2)
				var dest: Vector2 = f2.pos + (e.pos - f2.pos).normalized() * 2.0
				view._click(dest, f2.elev, null)
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
						var tf := b.fighter(t["uid"])
						view._click(tf.pos, tf.elev, tf)
						shots += 1
						break
				view._set_mode("idle")
				break
		if b.active == f2.uid and b.pending.is_empty():
			view._do(b.end_activation())
	assert_true(moves > 3, "moves made through the UI: %d" % moves)
	assert_true(b.round_no >= 2, "reached round %d" % b.round_no)
	view.queue_free()


func test_terrain_editor_screen() -> void:
	var view = load("res://view/terrain_editor.tscn").instantiate()
	_root().add_child(view)
	for row in view.PALETTE:
		view.tool = row[0]
		view._place(Vector2(18, 18))
	assert_true(view.b.terrain.size() >= 13, "every palette piece placed")
	view._select(view.b.terrain[0])
	view._rotate(PI / 12)
	view._height(0.5)
	view._scale(1.15)
	view._translate(Vector2(1, 0))
	view._duplicate()
	view._delete_group()
	view._random_layout()
	assert_true(view.b.terrain.size() > 5)
	view.name_edit.text = "test layout"
	view._save()
	var d := Layout.load_file(Layout.DIR + "test layout.json")
	assert_eq(d["pieces"].size(), view.b.terrain.size())
	# A saved layout becomes the battlefield.
	var b := Battle.new()
	b.setup(Samples.roster("verminkin"), Samples.roster("death_covens"), "a_deadly_encounter", 0, 5, d)
	assert_eq(b.terrain.size(), d["pieces"].size())
	view.queue_free()


func test_hover_tooltip() -> void:
	App.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "a_deadly_encounter", "twist": 0, "seed": 3}
	App.load_battle_path = ""
	var view = load("res://view/battle.tscn").instantiate()
	_root().add_child(view)
	var b: Battle = view.b
	var g := 0
	while b.round_no < 1 and g < 100:
		g += 1
		SimpleBot.answer(b)
	var f: FighterState = b.on_board()[0]
	var text: String = view._fighter_text(f, false)
	assert_true(text.contains(f.name) and text.contains("Mv"), text)
	view._update_tip(Vector2(-500, -500))
	assert_false(view.tip.visible, "no fighter under the mouse: no tooltip")
	view.queue_free()


func test_battle_setup_screen() -> void:
	var view: Control = load("res://view/battle_setup.tscn").instantiate()
	_root().add_child(view)
	for i in Scenario.ORDER.size() + 1:
		view.scen_opt.select(i)
		view._fill_twists()
		view._update_summary()
		assert_true(view.summary.text.length() > 20)
	view.pick[0].select(2)
	view._update_status()
	assert_true(view.status[0].text.contains("fighters"))
	view.queue_free()


func test_move_clicks_set_destination_not_chain() -> void:
	App.battle_config = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "a_deadly_encounter", "twist": 0, "seed": 8}
	App.load_battle_path = ""
	var view = load("res://view/battle.tscn").instantiate()
	_root().add_child(view)
	var b: Battle = view.b
	var g := 0
	while (b.active < 0 or not b.pending.is_empty()) and g < 200:
		g += 1
		if not b.pending.is_empty():
			SimpleBot.answer(b)
		elif b.active < 0:
			b.activate(b.can_activate_normally(b.turn)[0].uid)
	view._declare("normal")
	var f := b.active_fighter()
	view._click(f.pos + Vector2(1, 0), f.elev, null)
	view._click(f.pos + Vector2(2, 0), f.elev, null)
	assert_eq(view.waypoints.size(), 1, "a second click moves the destination instead of adding a leg")
	assert_true(Vector2(view.waypoints[0].x, view.waypoints[0].y).is_equal_approx(f.pos + Vector2(2, 0)))
	view.queue_free()
