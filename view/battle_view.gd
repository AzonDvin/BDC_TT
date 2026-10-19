class_name BattleView
extends Node
## The battle screen: 3D table + HUD. Hot-seat: whoever's decision it is uses the mouse.
## Controls: left-click select/act · right-drag orbit · middle-drag or WASD pan · wheel zoom ·
## Enter confirm move · Backspace remove waypoint · Esc cancel.

const SAVE_PATH := "user://battle_save.bdc"

var b: Battle
var board: Board3D
var selected := -1
var mode := "idle"          # idle, move, shoot, blast, flame, spell, ability, melee_setup
var mode_data := {}
var waypoints := PackedVector2Array()
var placements := {}
var hover := Vector2.INF
var table_mode := false
var _rotating := false
var _panning := false
var _hint := ""
var _hint_error := false

var top_text: RichTextLabel
var log_box: RichTextLabel
var card: RichTextLabel
var actions: VBoxContainer
var rosters: Array = [null, null]
var hint_label: Label
var pickup_box: CheckBox
var _last_active := -1


func _ready() -> void:
	board = Board3D.new()
	add_child(board)
	_build_hud()
	if App.load_battle_path != "" and FileAccess.file_exists(App.load_battle_path):
		b = Battle.load_from(App.load_battle_path)
		App.load_battle_path = ""
	if b == null:
		b = Battle.new()
		var cfg: Dictionary = App.battle_config
		if cfg.is_empty():
			cfg = {"rosters": [Samples.roster("guild_mercenaries"), Samples.roster("verminkin")], "scenario": "", "twist": -1, "seed": -1}
		b.setup(cfg["rosters"][0], cfg["rosters"][1], cfg["scenario"], cfg["twist"], cfg["seed"])
	b.changed.connect(_refresh)
	b.logged.connect(_on_log)
	board.build(b)
	for line in b.history:
		_on_log(line)
	_refresh()


# =============================================================================================
# HUD construction

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var th := UI.hbox(10)
	top.add_child(th)
	top_text = RichTextLabel.new()
	top_text.bbcode_enabled = true
	top_text.fit_content = true
	top_text.scroll_active = false
	top_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_text.custom_minimum_size = Vector2(600, 0)
	th.add_child(top_text)
	th.add_child(UI.button("Undo", func(): b.undo(); _set_mode("idle"), "Undo the current activation (only before any dice were rolled)"))
	var tt := UI.button("Table tools", _toggle_table, "Move fighters freely, adjust life and statuses — for anything resolved by hand")
	tt.toggle_mode = true
	th.add_child(tt)
	th.add_child(UI.button("Dice", _roll_free_dice, "Roll 2d6 openly (logged)"))
	th.add_child(UI.button("Save", func(): b.save_to(SAVE_PATH); _on_log("(Battle saved.)")))
	th.add_child(UI.button("Menu", func(): b.save_to(SAVE_PATH); App.go("res://view/main_menu.tscn")))
	root.add_child(top)

	var left := UI.vbox(6)
	left.position = Vector2(8, 58)
	left.custom_minimum_size = Vector2(300, 0)
	root.add_child(left)
	for p in 2:
		var box := UI.vbox(1)
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(300, 200)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.add_child(box)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_child(UI.panel(sc))
		rosters[p] = box

	var logp := PanelContainer.new()
	logp.anchor_left = 1.0
	logp.anchor_right = 1.0
	logp.anchor_top = 1.0
	logp.anchor_bottom = 1.0
	logp.offset_left = -380
	logp.offset_right = -8
	logp.offset_top = -330
	logp.offset_bottom = -8
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 13)
	logp.add_child(log_box)
	root.add_child(logp)

	var cardp := PanelContainer.new()
	cardp.anchor_left = 1.0
	cardp.anchor_right = 1.0
	cardp.offset_left = -380
	cardp.offset_right = -8
	cardp.offset_top = 58
	var cs := ScrollContainer.new()
	cs.custom_minimum_size = Vector2(360, 440)
	cs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card = RichTextLabel.new()
	card.bbcode_enabled = true
	card.fit_content = true
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_font_size_override("normal_font_size", 14)
	cs.add_child(card)
	cardp.add_child(cs)
	root.add_child(cardp)

	var actp := PanelContainer.new()
	actp.anchor_top = 1.0
	actp.anchor_bottom = 1.0
	actp.anchor_right = 1.0
	actp.offset_left = 320
	actp.offset_right = -392
	actp.offset_top = -8
	actp.offset_bottom = -8
	actp.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var av := UI.vbox(6)
	av.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label = UI.label("", 14)
	av.add_child(hint_label)
	actions = UI.vbox(6)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av.add_child(actions)
	actp.add_child(av)
	root.add_child(actp)


# =============================================================================================
# Refresh

func _refresh() -> void:
	if b == null:
		return
	if b.active < 0 and mode != "idle" and not mode in ["deploy"]:
		if b.pending.is_empty():
			_set_mode("idle", false)
	if not b.move_plan.is_empty() and mode != "move":
		mode = "move"
	if b.active >= 0 and b.active != _last_active:
		selected = b.active
	_last_active = b.active
	_update_top()
	_update_rosters()
	_update_card()
	_update_actions()
	_update_board()
	if b.active < 0 and b.pending.is_empty() and not b.is_over():
		b.save_to(SAVE_PATH)


func _pname(p: int) -> String:
	return "[color=#%s]%s[/color]" % [App.player_color(p).to_html(false), b.player_names[p]]


func _update_top() -> void:
	var sc := b.scen
	var score := ""
	match sc.get("id", ""):
		"a_deadly_encounter":
			score = "VP %d – %d" % [sc["vp"][0], sc["vp"][1]]
		"no_quarter":
			score = "Domination %d – %d" % [sc["marks"][0], sc["marks"][1]]
		"the_chapel":
			score = "Death marks %d – %d" % [sc["marks"][0], sc["marks"][1]]
		"glimmers_in_the_dark", "the_find":
			score = "Escaped with treasure %d – %d" % [sc["escaped"][0], sc["escaped"][1]]
		"street_of_death":
			score = "Ambusher: %s" % b.player_names[sc["ambusher"]]
	var who := ""
	if b.is_over():
		who = "[b]Battle over[/b]"
	elif not b.pending.is_empty():
		who = "Waiting on %s" % _pname(b.pending.get("player", b.turn))
	elif b.active >= 0:
		who = "%s activating [b]%s[/b]%s" % [_pname(b.turn), b.active_fighter().name, " (surge)" if b.active_is_surge else ""]
	elif b.phase == "activation":
		who = "%s to activate a fighter" % _pname(b.turn)
	top_text.text = "[b]%s[/b] · twist: %s · Round %d · priority %s · underdog %s\n%s   ·   %s" % [
		Scenario.display_name(sc.get("id", "")), Scenario.twist_name(sc.get("twist_id", "")), b.round_no, _pname(b.priority), _pname(b.underdog), who, score]


func _update_rosters() -> void:
	for p in 2:
		var box: VBoxContainer = rosters[p]
		UI.clear(box)
		box.add_child(UI.label(b.player_names[p], 15, App.player_color(p)))
		for f in b.fighters:
			if f.player != p:
				continue
			var state := ""
			match f.where:
				"reserve":
					state = "reserve"
				"down":
					state = "☠ down"
				"escaped":
					state = "escaped"
				_:
					state = "♥%d/%d" % [f.life, f.max_life()] + (" ✓" if f.activated else "") + (" ⟳" if f.surged else "")
			var btn := UI.button("%s  %s" % [f.name, state], func(): _select(f.uid, true))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.add_theme_font_size_override("font_size", 13)
			btn.flat = f.uid != selected
			if f.where != "board":
				btn.modulate = Color(1, 1, 1, 0.5)
			box.add_child(btn)


func _update_card() -> void:
	var f := b.fighter(selected)
	if f == null:
		card.text = "[color=#a89e88]Click a fighter to see their profile.\n\nRight-drag to orbit, wheel to zoom, middle-drag or WASD to pan.[/color]"
		return
	var s: Dictionary = f.stats
	var t := "[b][color=#%s]%s[/color][/b]  [color=#a89e88]%s[/color]\n" % [App.player_color(f.player).to_html(false), f.name, Catalog.fighter_def(f.faction, f.def_id).get("name", "")]
	t += "[color=#a89e88]%s[/color]\n" % ", ".join(f.keywords)
	var arm := Effects.armour_value(b, f) if f.on_board() else int(s["armour"])
	t += "[code]Mv %s  Bl %s  Bw %s  Ar %s  In %s  Wp %s  Life %d/%d[/code]\n" % [s["move"], _tn(s["blade"]), _tn(s["bow"]), "-" if arm >= 7 else "%d+" % arm, s["initiative"], s["willpower"], f.life, f.max_life()]
	for w in f.melee:
		t += "⚔ " + UI.weapon_line(w) + "\n"
	for w in f.ranged:
		var tag := ""
		if w["id"] in f.needs_reload:
			tag = " [color=#e0a060](needs reload)[/color]"
		if w["id"] in f.lost_weapons:
			tag = " [color=#e06060](lost)[/color]"
		t += "➶ " + UI.weapon_line(w) + tag + "\n"
	if f.armour_id != "":
		t += "Armour: %s\n" % Catalog.wargear(f.faction, f.armour_id).get("name", f.armour_id)
	var items: PackedStringArray = []
	for id in f.items:
		items.append(Catalog.wargear(f.faction, id).get("name", id))
	if not items.is_empty():
		t += "Items: %s\n" % ", ".join(items)
	for sid in f.skills:
		var sk := Catalog.skill(f.faction, sid)
		t += "[color=#d9b45a]%s[/color]: %s\n" % [sk.get("name", sid), sk.get("text", "")]
	for sr in Catalog.fighter_def(f.faction, f.def_id).get("special_rules", []):
		t += "[color=#d9b45a]%s[/color]: %s\n" % [sr["name"], sr["text"]]
	if not f.prepared.is_empty():
		t += "\n[b]Prepared spells[/b]\n"
		for sp in f.prepared:
			t += "• %s (%d+ / crit %s+): %s\n" % [sp["name"], sp["casting"], sp.get("critical", "-"), sp["text"]]
	var st: PackedStringArray = []
	for k in f.statuses:
		if f.statuses[k] is bool and f.statuses[k] and not k in ["damaged_this_activation", "bloodied_at_start"]:
			st.append(k.replace("_", " "))
		elif k in ["witchfire", "engineering", "fuse"]:
			st.append("%s %s" % [k, f.statuses[k]])
	for e in f.effects:
		st.append(e["id"].replace("_", " "))
	if f.is_bloodied():
		st.append("BLOODIED")
	if not st.is_empty():
		t += "\n[color=#e0a060]Status: %s[/color]" % ", ".join(st)
	card.text = t


static func _tn(v) -> String:
	return "-" if v == null else "%s+" % v


# =============================================================================================
# Action panel

func _update_actions() -> void:
	UI.clear(actions)
	hint_label.text = _hint
	hint_label.add_theme_color_override("font_color", Color("ff8a70") if _hint_error else App.PAPER)
	if table_mode:
		_actions_table()
		return
	if b.is_over():
		actions.add_child(UI.label("%s\n%s" % [b.result_text, ("%s wins!" % b.player_names[b.winner]) if b.winner >= 0 else ""], 20, App.GOLD))
		var r := UI.hbox()
		r.add_child(UI.button("New battle", func(): App.go("res://view/battle_setup.tscn")))
		r.add_child(UI.button("Main menu", func(): App.go("res://view/main_menu.tscn")))
		actions.add_child(r)
		return
	if not b.pending.is_empty():
		_actions_pending()
		return
	if b.phase != "activation":
		return
	if b.active < 0:
		_actions_pick_fighter()
		return
	_actions_activation()


func _header(text: String, p: int) -> void:
	actions.add_child(UI.label(text, 17, App.player_color(p).lightened(0.25)))


func _row(buttons: Array) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	for x in buttons:
		h.add_child(x)
	actions.add_child(h)
	return h


func _actions_pick_fighter() -> void:
	_header("%s: choose a fighter to activate (click one on the table or below)." % b.player_names[b.turn], b.turn)
	var btns: Array = []
	for f in b.can_activate_normally(b.turn):
		btns.append(UI.button(f.name, func(): _do(b.activate(f.uid))))
	_row(btns)


func _actions_activation() -> void:
	var f := b.active_fighter()
	var p := f.player
	if mode == "move":
		_actions_move(f)
		return
	if mode in ["shoot", "blast", "flame", "spell", "ability", "spell_point"]:
		_header(_hint if _hint != "" else "Pick a target.", p)
		_row([UI.button("Cancel", func(): _set_mode("idle"))])
		return
	if mode == "melee_setup":
		_actions_melee_setup(f)
		return
	var engaged := Effects.is_engaged(b, f)
	var lim := " (move OR action only)" if b.move_or_action_only(f) else ""
	_header("%s activating %s%s" % [b.player_names[p], f.name, lim], p)
	var mv: Array = []
	if b.can_still_move(f):
		if engaged:
			mv.append(UI.button("Disengage (Init test, 3\")", func(): _declare("disengage")))
		else:
			mv.append(UI.button("Normal move (%s\")" % f.stats["move"], func(): _declare("normal")))
			if not f.acted:
				mv.append(UI.button("Run (+d6\")", func(): _declare("run"), "No action this activation afterwards"))
				mv.append(UI.button("Charge (+d6\")", func(): _declare("charge"), "Must end within 1\" of an enemy or the activation ends"))
	if not mv.is_empty():
		actions.add_child(UI.label("MOVE", 13, App.GOLD))
		_row(mv)
	var act: Array = []
	if b.can_still_act(f):
		if engaged:
			act.append(UI.button("Melee attack", func(): _set_mode("melee_setup")))
		for w in f.usable_ranged():
			var err := Combat.check_can_shoot(b, f, w)
			var bt := UI.button("Shoot %s" % w["name"], func(): _start_shoot(w), UI.weapon_line(w) + ("\n" + err if err != "" else ""))
			bt.disabled = err != ""
			act.append(bt)
		if not engaged:
			act.append(UI.button("Hide", func(): _do(Combat.hide(b)), "Must be touching terrain and more than 3\" from enemies"))
		if f.is_caster() and Magic.can_use_arcane(b, f) == "":
			act.append(UI.button("Draw power", func(): _do(Magic.draw_power(b)), "+1 casting die next activation"))
			for sp in f.prepared:
				act.append(UI.button("Cast %s (%d+)" % [sp["name"], sp["casting"]], func(): _start_spell(sp), sp["text"]))
	for wid in f.needs_reload:
		if b.can_still_move(f):
			act.append(UI.button("Reload %s (forgo move)" % f.weapon_by_id(wid).get("name", wid), func(): _do(Combat.reload_weapon(b, wid, "move"))))
		if b.can_still_act(f):
			act.append(UI.button("Reload %s (forgo action)" % f.weapon_by_id(wid).get("name", wid), func(): _do(Combat.reload_weapon(b, wid, "action"))))
	if not act.is_empty():
		actions.add_child(UI.label("ACTION", 13, App.GOLD))
		_row(act)
	var ab: Array = []
	for a in Abilities.list(b, f):
		ab.append(UI.button(a["name"] + (" [bonus]" if a["kind"] == "bonus" else ""), func(): _start_ability(a)))
	if not ab.is_empty():
		actions.add_child(UI.label("SPECIAL", 13, App.GOLD))
		_row(ab)
	_row([UI.button("End activation", func(): _do(b.end_activation()))])


func _actions_move(f: FighterState) -> void:
	var kind: String = b.move_plan.get("kind", "")
	var ev := Movement.evaluate(b, _full_path(), pickup_box != null and pickup_box.button_pressed)
	_header("%s move: up to %.1f\". Click the table to add waypoints (Enter to confirm)." % [kind.capitalize(), b.move_plan.get("allowance", 0.0)], f.player)
	var info := "Used %.1f\" of %.1f\"" % [ev["cost"], ev["allowance"]]
	if ev["crossings"] > 0:
		info += " (incl. %d\" low terrain)" % ev["crossings"]
	if waypoints.is_empty():
		info = "Click where the fighter should go."
	elif not ev["ok"]:
		info += " — " + ev["error"]
	actions.add_child(UI.label(info, 14, Color("ff8a70") if (not ev["ok"] and not waypoints.is_empty()) else App.PAPER))
	var btns: Array = []
	var confirm := UI.button("Confirm move", _confirm_move)
	confirm.disabled = not ev["ok"]
	btns.append(confirm)
	btns.append(UI.button("Remove last point", func(): if not waypoints.is_empty(): waypoints.resize(waypoints.size() - 1); _refresh()))
	btns.append(UI.button("Clear path", func(): waypoints.clear(); _refresh()))
	if kind == "normal":
		btns.append(UI.button("Cancel move", func(): _do(Movement.cancel(b)); waypoints.clear()))
		var keep := pickup_box != null and pickup_box.button_pressed
		pickup_box = CheckBox.new()
		pickup_box.text = "Pick up treasure (-1\")"
		pickup_box.button_pressed = keep
		pickup_box.toggled.connect(func(_v): _refresh())
		btns.append(pickup_box)
	if kind == "charge":
		btns.append(UI.button("Charge fails (end activation)", func(): waypoints.clear(); _do(Movement.fail_charge(b))))
	_row(btns)


func _actions_melee_setup(f: FighterState) -> void:
	_header("Melee attack: choose the target and weapons.", f.player)
	var targets := Effects.engaged_enemies(b, f)
	if not mode_data.has("target") and not targets.is_empty():
		mode_data["target"] = targets[0].uid
	var trow: Array = []
	for t in targets:
		var bt := UI.button(t.name, func(): mode_data["target"] = t.uid; _refresh())
		bt.toggle_mode = true
		bt.button_pressed = mode_data.get("target", -1) == t.uid
		trow.append(bt)
	_row(trow)
	var picker := _weapon_picker(f, mode_data)
	actions.add_child(picker)
	_row([UI.button("Attack!", func(): _do(Combat.start_melee(b, mode_data.get("target", -1), _melee_opts(mode_data))); _set_mode("idle", false)),
		UI.button("Cancel", func(): _set_mode("idle"))])


## Main weapon / off-hand / once-per-battle options; writes into `store`.
func _weapon_picker(f: FighterState, store: Dictionary) -> Control:
	var v := UI.vbox(4)
	var names: Array = []
	for w in f.melee:
		names.append(UI.weapon_line(w))
	if not store.has("main"):
		store["main"] = 0
	var main := UI.option(names, store["main"])
	main.item_selected.connect(func(i): store["main"] = i)
	v.add_child(UI.label("Weapon:"))
	v.add_child(main)
	var offs: Array = ["(no off-hand)"]
	var off_ids: Array = [""]
	for w in f.melee:
		if "Off-hand" in w.get("traits", []):
			offs.append("Off-hand: " + w["name"])
			off_ids.append(w["id"])
	if offs.size() > 1:
		if not store.has("off"):
			store["off"] = 1 if f.melee.size() > 1 and off_ids.size() > 1 and off_ids[1] != f.melee[0]["id"] else 0
		var off := UI.option(offs, store["off"])
		off.item_selected.connect(func(i): store["off"] = i)
		store["off_ids"] = off_ids
		v.add_child(off)
	if f.has_item("net") and not "net" in f.once_per_battle:
		var c := CheckBox.new()
		c.text = "Throw the net (once per battle)"
		c.toggled.connect(func(on): store["net"] = on)
		v.add_child(c)
	if f.has_rule("mesmeric_gaze") and not "mesmeric_gaze" in f.once_per_battle and store.get("attacker", true):
		var c2 := CheckBox.new()
		c2.text = "Mesmeric Gaze (once per battle)"
		c2.toggled.connect(func(on): store["mesmeric"] = on)
		v.add_child(c2)
	if f.has_rule("stand_ground") and not "stand_ground" in f.once_per_battle and not store.get("attacker", true):
		var c3 := CheckBox.new()
		c3.text = "Stand Ground (once per battle)"
		c3.toggled.connect(func(on): store["stand_ground"] = on)
		v.add_child(c3)
	return v


func _melee_opts(store: Dictionary) -> Dictionary:
	var f := b.fighter(store.get("uid", b.active))
	var ids: Array = [f.melee[int(store.get("main", 0))]["id"]]
	var off_ids: Array = store.get("off_ids", [""])
	var oi := int(store.get("off", 0))
	if oi > 0 and oi < off_ids.size() and off_ids[oi] != ids[0]:
		ids.append(off_ids[oi])
	return {"weapons": ids, "net": store.get("net", false), "mesmeric": store.get("mesmeric", false), "stand_ground": store.get("stand_ground", false)}


func _actions_pending() -> void:
	var p := b.pending
	var who: int = p.get("player", 0)
	match p["type"]:
		"choose_first":
			_header("%s has priority: who activates first this round?" % b.player_names[who], who)
			_row([UI.button(b.player_names[0], func(): _do(b.respond({"player": 0}))), UI.button(b.player_names[1], func(): _do(b.respond({"player": 1})))])
		"surge_or_pass":
			_header("%s has no fighters left to activate. Make a surge activation (1 move or 1 action) or pass?" % b.player_names[who], who)
			var btns: Array = []
			for f in b.can_surge(who):
				btns.append(UI.button("Surge: " + f.name, func(): _do(b.respond({"uid": f.uid}))))
			btns.append(UI.button("Pass for this round", func(): _do(b.respond({"pass": true}))))
			_row(btns)
		"flee_test":
			_header("%s must take a Flee test (%d fighters bloodied or down). On a 1 the warband flees." % [b.player_names[who], p["count"]], who)
			_row([UI.button("Roll the Flee test", func(): _do(b.respond({"voluntary": false}))), UI.button("Flee voluntarily", func(): _do(b.respond({"voluntary": true})))])
		"pick_entry":
			_header("%s: pick your entry point (corner). Your opponent takes the opposite corner." % b.player_names[who], who)
			var names := ["North-west", "North-east", "South-east", "South-west"]
			var btns2: Array = []
			for i in 4:
				btns2.append(UI.button(names[i], func(): _do(b.respond({"corner": i}))))
			_row(btns2)
		"deploy", "place":
			_actions_placement(p)
		"pick_reserve_group":
			_header("%s: pick a battle group in reserve to roll reinforcements for." % b.player_names[who], who)
			var btns3: Array = []
			for g in p["groups"]:
				var names2: PackedStringArray = []
				for f in b.fighters:
					if f.player == who and f.where == "reserve" and f.battle_group == g:
						names2.append(f.name)
				btns3.append(UI.button("Group %d: %s" % [g + 1, ", ".join(names2)], func(): _do(b.respond({"group": g}))))
			_row(btns3)
		"melee_weapons":
			var d := b.fighter(p["uid"])
			var a := b.fighter(b.duel["att"])
			_header("%s: %s is attacked by %s. Choose %s's weapons." % [b.player_names[who], d.name, a.name, d.name], who)
			if not mode_data.has("def_store") or mode_data["def_store"].get("uid", -1) != d.uid:
				mode_data["def_store"] = {"uid": d.uid, "attacker": false}
			actions.add_child(_weapon_picker(d, mode_data["def_store"]))
			_row([UI.button("Fight!", func(): var o := _melee_opts(mode_data["def_store"]); mode_data.erase("def_store"); _do(b.respond(o)))])
		"duel_turn":
			_actions_duel(p)
		"volley":
			_header("Volley: all %d attacks go at the target unless you spread them to enemies within 3\" of it." % p["attacks"], who)
			if not mode_data.has("volley"):
				var arr: Array = []
				for i in p["attacks"]:
					arr.append(p["primary"])
				mode_data["volley"] = arr
			var arr2: Array = mode_data["volley"]
			for i in arr2.size():
				var opts: Array = [p["primary"]] + p["candidates"]
				var names3: Array = []
				for u in opts:
					names3.append("Attack %d → %s" % [i + 1, b.fighter(u).name])
				var o := UI.option(names3, opts.find(arr2[i]))
				o.item_selected.connect(func(k): arr2[i] = opts[k])
				actions.add_child(o)
			_row([UI.button("Fire!", func(): var t: Array = mode_data["volley"]; mode_data.erase("volley"); _do(b.respond({"targets": t})))])


func _actions_duel(p: Dictionary) -> void:
	var me := b.fighter(p["uid"])
	var foe := b.fighter(b.duel["def"] if me.uid == b.duel["att"] else b.duel["att"])
	_header("%s: %s's turn in the duel against %s — attack or parry." % [b.player_names[me.player], me.name, foe.name], me.player)
	for f in [me, foe]:
		var parts: PackedStringArray = []
		for r in b.duel["rolls"][str(f.uid)]:
			var face := "%d%s" % [r["nat"], "!" if r["crit"] else ""]
			if r["used"]:
				parts.append("[s][color=#777]%s[/color][/s]" % face)
			elif r["crit"]:
				parts.append("[color=#ffd060][b]%s[/b][/color]" % face)
			elif r["hit"]:
				parts.append("[color=#c0f0c0]%s[/color]" % face)
			else:
				parts.append("[color=#888]%s[/color]" % face)
		actions.add_child(UI.rich("[color=#%s]%s[/color] (♥%d): %s" % [App.player_color(f.player).to_html(false), f.name, f.life, "  ".join(parts)]))
	var btns: Array = []
	for o in Combat.duel_options(b):
		btns.append(UI.button(o["label"], func(): _do(b.respond(o["choice"]))))
	_row(btns)


func _actions_placement(p: Dictionary) -> void:
	var who: int = p["player"]
	var what := "Deploy" if p["type"] == "deploy" else "Reinforcements arrive"
	_header("%s — %s: click inside the highlighted area to place each fighter (click a placed fighter to pick it up again)." % [b.player_names[who], what], who)
	var lines: PackedStringArray = []
	for uid in p["uids"]:
		lines.append("%s%s" % ["✔ " if placements.has(uid) else "• ", b.fighter(uid).name])
	actions.add_child(UI.label(", ".join(lines), 13))
	_row([UI.button("Auto-place the rest", func(): _do(b.respond({"positions": placements.duplicate()})); placements.clear()),
		UI.button("Clear", func(): placements.clear(); _refresh())])


func _actions_table() -> void:
	_header("TABLE TOOLS — click a fighter to select it, then click the table to move it there. Changes are logged.", b.turn)
	var f := b.fighter(selected)
	if f == null:
		return
	var btns: Array = [
		UI.button("Life -1", func(): f.life = maxi(0, f.life - 1); _table_log("%s loses 1 life" % f.name); if f.life == 0: Combat.take_down(b, f, null, "table tools")),
		UI.button("Life +1", func(): f.life = mini(f.max_life(), f.life + 1); _table_log("%s gains 1 life" % f.name)),
		UI.button("Take down" if f.on_board() else "Return to table", func():
			if f.on_board():
				Combat.take_down(b, f, null, "table tools")
			else:
				f.where = "board"
				f.life = maxi(1, f.life)
			_table_log("%s %s" % [f.name, "removed" if not f.on_board() else "returned"])),
		UI.button("Toggle poisoned", func(): f.statuses["poisoned"] = not f.statuses.get("poisoned", false); _table_log("%s poisoned: %s" % [f.name, f.statuses["poisoned"]])),
		UI.button("Toggle hidden", func(): f.statuses["hidden"] = not f.statuses.get("hidden", false); _table_log("%s hidden: %s" % [f.name, f.statuses["hidden"]])),
		UI.button("Toggle activated", func(): f.activated = not f.activated; _table_log("%s activated: %s" % [f.name, f.activated])),
		UI.button("Clear effects", func(): f.effects.clear(); _table_log("%s's effects cleared" % f.name)),
	]
	_row(btns)


func _table_log(text: String) -> void:
	b.log_line("[Table] " + text + ".")
	b.changed.emit()


# =============================================================================================
# Modes and commands

func _do(err: String) -> void:
	if err != "":
		_hint = err
		_hint_error = true
	else:
		_hint = ""
		_hint_error = false
	_refresh()


func _set_mode(m: String, refresh := true) -> void:
	mode = m
	if m == "idle":
		mode_data = {}
		waypoints.clear()
		_hint = ""
		_hint_error = false
	if refresh:
		_refresh()


func _declare(kind: String) -> void:
	waypoints.clear()
	var err := Movement.declare(b, kind)
	if err == "" and not b.move_plan.is_empty():
		mode = "move"
	_do(err)


func _full_path() -> PackedVector2Array:
	var f := b.active_fighter()
	var out := PackedVector2Array()
	if f == null:
		return out
	out.append(f.pos)
	out.append_array(waypoints)
	return out


func _confirm_move() -> void:
	var err := Movement.commit(b, _full_path(), pickup_box != null and pickup_box.button_pressed)
	if err == "":
		waypoints.clear()
		mode = "idle"
	_do(err)


func _start_shoot(w: Dictionary) -> void:
	var f := b.active_fighter()
	mode_data = {"weapon": w["id"]}
	if Effects.weapon_has(f, w, "Blast"):
		mode = "blast"
		_hint = "Click a visible point within %.0f\" for the blast template." % Effects.range_for(b, f, w)
	elif Effects.weapon_has(f, w, "Flame"):
		mode = "flame"
		_hint = "Click to aim the flame template."
	else:
		mode = "shoot"
		var legal := 0
		for t in Combat.ranged_targets(b, f, w):
			if t["legal"]:
				legal += 1
		_hint = "Click a highlighted enemy (closest-target rule). Green = legal target." if legal > 0 else "No legal targets for this weapon."
	_hint_error = false
	_refresh()


func _start_spell(sp: Dictionary) -> void:
	var info := Magic.spell_info(sp["name"])
	mode_data = {"spell": sp["name"], "info": info}
	match info["target"]:
		"none", "closest", "manual":
			_do(Magic.cast(b, sp["name"], {}))
			_set_mode("idle", false)
			_refresh()
		"friendly", "enemy":
			mode = "spell"
			_hint = "%s: click a %s fighter within %.0f\"." % [sp["name"], info["target"], info.get("range", 0.0)]
		"friendly_point":
			mode = "spell"
			_hint = "%s: click the friendly fighter, then where to set it up." % sp["name"]
		"point", "summon":
			mode = "spell_point"
			_hint = "%s: click a point within %.0f\"." % [sp["name"], info.get("range", 0.0)]
		"dir":
			mode = "spell_point"
			_hint = "%s: click to aim." % sp["name"]
	_refresh()


func _start_ability(a: Dictionary) -> void:
	match a["needs"]:
		"none":
			_do(Abilities.use(b, a["id"]))
		"spell":
			var f := b.active_fighter()
			var names: Array = []
			for lore_id in f.lores:
				for s in Catalog.lore(f.faction, lore_id)["spells"]:
					names.append(s["name"])
			_do(Abilities.use(b, a["id"], {"spell": names[0] if not names.is_empty() else ""}))
		_:
			mode = "ability"
			mode_data = {"ability": a}
			_hint = "%s: click %s." % [a["name"], {"enemy": "an enemy fighter", "friendly": "a friendly fighter", "point": "a point on the table"}[a["needs"]]]
			_refresh()


func _toggle_table() -> void:
	table_mode = not table_mode
	_refresh()


func _roll_free_dice() -> void:
	b.log_line("[Dice] 2d6: %d, %d" % [b.dice.d6(), b.dice.d6()])
	b.mark_dice_rolled()
	_refresh()


func _select(uid: int, focus := false) -> void:
	selected = uid
	var f := b.fighter(uid)
	if focus and f and f.on_board():
		board.focus(f.pos)
	_refresh()


# =============================================================================================
# Input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_rotating = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				board.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				board.zoom(1.1)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var p := board.ground_point(mb.position)
					if p != Vector2.INF:
						_click(p, mb.double_click)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			board.orbit(mm.relative.x, mm.relative.y)
		elif _panning:
			board.pan(mm.relative)
		else:
			hover = board.ground_point(mm.position)
			if mode in ["move", "blast", "flame", "spell_point"] or b.pending.get("type", "") in ["deploy", "place"]:
				_update_board()
				if mode == "move":
					_update_actions()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if mode == "move":
					waypoints.clear()
					_refresh()
				elif mode != "idle":
					_set_mode("idle")
			KEY_ENTER, KEY_KP_ENTER:
				if mode == "move":
					_confirm_move()
			KEY_BACKSPACE:
				if mode == "move" and not waypoints.is_empty():
					waypoints.resize(waypoints.size() - 1)
					_refresh()


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		v.y += 1
	if Input.is_key_pressed(KEY_S):
		v.y -= 1
	if Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_D):
		v.x += 1
	if Input.is_key_pressed(KEY_Q):
		board.orbit(-300 * delta, 0)
	if Input.is_key_pressed(KEY_E):
		board.orbit(300 * delta, 0)
	if v != Vector2.ZERO:
		board.pan(v * 900 * delta)


func _click(p: Vector2, double := false) -> void:
	var hit := board.fighter_at(p)
	var pt: String = b.pending.get("type", "")
	if table_mode:
		if hit != null:
			_select(hit.uid)
		elif selected >= 0 and b.fighter(selected) and b.fighter(selected).on_board():
			Movement.place(b, b.fighter(selected), p)
			_table_log("%s moved by hand" % b.fighter(selected).name)
		return
	if pt in ["deploy", "place"]:
		_click_placement(p, hit)
		return
	if pt == "pick_entry":
		var cs := Scenario.corners(b)
		for i in 4:
			if p.distance_to(cs[i]) < 10.0:
				_do(b.respond({"corner": i}))
				return
		return
	var f := b.active_fighter()
	match mode:
		"move":
			waypoints.append(p)
			_refresh()
			return
		"shoot":
			if hit and f and hit.player != f.player:
				_do(Combat.shoot(b, mode_data["weapon"], hit.uid))
				if not _hint_error:
					_set_mode("idle")
			return
		"blast":
			_do(Combat.shoot_blast(b, mode_data["weapon"], p))
			if not _hint_error:
				_set_mode("idle")
			return
		"flame":
			_do(Combat.shoot_flame(b, mode_data["weapon"], p - f.pos))
			if not _hint_error:
				_set_mode("idle")
			return
		"spell":
			var info: Dictionary = mode_data["info"]
			if info["target"] == "friendly_point" and mode_data.has("target"):
				_do(Magic.cast(b, mode_data["spell"], {"target": mode_data["target"], "point": p}))
				if not _hint_error:
					_set_mode("idle")
				return
			if hit:
				if info["target"] == "friendly_point":
					mode_data["target"] = hit.uid
					_hint = "Now click where to set %s up." % hit.name
					_refresh()
					return
				_do(Magic.cast(b, mode_data["spell"], {"target": hit.uid}))
				if not _hint_error:
					_set_mode("idle")
			return
		"spell_point":
			var info2: Dictionary = mode_data["info"]
			var params := {"dir": p - f.pos} if info2["target"] == "dir" else {"point": p}
			_do(Magic.cast(b, mode_data["spell"], params))
			if not _hint_error:
				_set_mode("idle")
			return
		"ability":
			var a: Dictionary = mode_data["ability"]
			var prm := {}
			if a["needs"] == "point":
				prm = {"point": p}
			elif hit:
				prm = {"target": hit.uid}
			else:
				return
			_do(Abilities.use(b, a["id"], prm))
			if not _hint_error:
				_set_mode("idle")
			return
	if hit:
		_select(hit.uid)
		if (double or b.active < 0) and b.pending.is_empty() and b.phase == "activation" and b.active < 0 and hit.player == b.turn and not hit.activated:
			_do(b.activate(hit.uid))


func _click_placement(p: Vector2, hit: FighterState) -> void:
	var pend := b.pending
	if hit and placements.has(hit.uid):
		placements.erase(hit.uid)
		hit.where = "reserve"
		_refresh()
		return
	for uid in pend["uids"]:
		if placements.has(uid):
			continue
		var f := b.fighter(uid)
		var err := Scenario.zone_ok(b, f, p, pend["zone"])
		if err != "":
			_do(err)
			return
		placements[uid] = p
		f.pos = p
		f.where = "board"   # shown on the table while placing; respond() validates again
		if placements.size() == pend["uids"].size():
			var all := placements.duplicate()
			placements.clear()
			_do(b.respond({"positions": all}))
		else:
			_refresh()
		return


# =============================================================================================
# Board overlays

func _update_board() -> void:
	var highlight := {}
	var lines: Array = []
	var fills: Array = []
	var f := b.active_fighter()
	var sel := b.fighter(selected)
	# Engagement ring and weapon ranges for the selected fighter.
	if sel and sel.on_board():
		lines.append({"pts": Board3D.circle(sel.pos, sel.radius + 1.0), "color": Color(1, 1, 1, 0.25), "closed": true})
		for w in sel.usable_ranged():
			var r := Effects.range_for(b, sel, w)
			if r > 0:
				lines.append({"pts": Board3D.circle(sel.pos, sel.radius + r, 96), "color": Color(0.9, 0.8, 0.4, 0.35), "closed": true})
	if f:
		highlight[f.uid] = Color("f2e6a0")
	# Targets
	if mode == "shoot" and f:
		var w := f.weapon_by_id(mode_data["weapon"])
		for t in Combat.ranged_targets(b, f, w):
			highlight[t["uid"]] = Color("60e060") if t["legal"] else Color(0.8, 0.25, 0.2)
	if mode == "move" and f:
		var path := _full_path()
		var with_hover := path.duplicate()
		if hover != Vector2.INF:
			with_hover.append(hover)
		var ev := Movement.evaluate(b, with_hover, pickup_box != null and pickup_box.button_pressed)
		lines.append({"pts": with_hover, "color": Color("80ff80") if ev["ok"] else Color("ff7060")})
		lines.append({"pts": Board3D.circle(f.pos, b.move_plan.get("allowance", 0.0) + 0.0, 96), "color": Color(0.5, 0.8, 1.0, 0.25), "closed": true})
		if hover != Vector2.INF:
			lines.append({"pts": Board3D.circle(hover, f.radius), "color": Color("80ff80") if ev["ok"] else Color("ff7060"), "closed": true})
	if mode == "blast" and hover != Vector2.INF:
		fills.append({"poly": Board3D.circle(hover, Combat.BLAST_RADIUS), "color": Color(1, 0.5, 0.1, 0.35)})
	if mode == "spell_point" and hover != Vector2.INF and f:
		if mode_data["info"]["target"] == "dir":
			fills.append({"poly": Geo.flame_polygon(f.pos + (hover - f.pos).normalized() * f.radius, hover - f.pos, 8.0, float(b.cfg["flame_end_radius"])), "color": Color(0.6, 0.2, 1.0, 0.35)})
		else:
			fills.append({"poly": Board3D.circle(hover, Combat.BLAST_RADIUS), "color": Color(0.6, 0.2, 1.0, 0.35)})
			lines.append({"pts": Board3D.circle(f.pos, f.radius + float(mode_data["info"].get("range", 0.0)), 96), "color": Color(0.7, 0.4, 1.0, 0.4), "closed": true})
	if mode == "flame" and hover != Vector2.INF and f:
		fills.append({"poly": Geo.flame_polygon(f.pos + (hover - f.pos).normalized() * f.radius, hover - f.pos, 8.0, float(b.cfg["flame_end_radius"])), "color": Color(1, 0.4, 0.1, 0.4)})
	var lt: Dictionary = b.scen.get("last_template", {})
	if not lt.is_empty() and lt.get("round", -1) == b.round_no:
		if lt["type"] == "blast":
			lines.append({"pts": Board3D.circle(lt["pos"], Combat.BLAST_RADIUS), "color": Color(1, 0.6, 0.2, 0.6), "closed": true})
		else:
			lines.append({"pts": Geo.flame_polygon(lt["origin"], lt["dir"], 8.0, float(b.cfg["flame_end_radius"])), "color": Color(1, 0.6, 0.2, 0.6), "closed": true})
	if b.pending.get("type", "") in ["deploy", "place"]:
		fills.append_array(_zone_fills(b.pending["zone"], App.player_color(b.pending["player"])))
		if hover != Vector2.INF:
			for uid in b.pending["uids"]:
				if not placements.has(uid):
					var nf := b.fighter(uid)
					var ok := Scenario.zone_ok(b, nf, hover, b.pending["zone"]) == ""
					lines.append({"pts": Board3D.circle(hover, nf.radius), "color": Color("80ff80") if ok else Color("ff7060"), "closed": true})
					break
	if b.pending.get("type", "") == "pick_entry":
		for c in Scenario.corners(b):
			lines.append({"pts": Board3D.circle(c, 9.0, 64), "color": App.player_color(b.pending["player"]), "closed": true})
	# Scenario markings
	var c := Scenario.center(b)
	match b.scen.get("id", ""):
		"a_deadly_encounter":
			lines.append({"pts": Board3D.circle(c, 6.0, 64), "color": Color(0.9, 0.85, 0.6, 0.35), "closed": true})
		"no_quarter":
			lines.append({"pts": PackedVector2Array([Vector2(c.x, 0), Vector2(c.x, b.board_size.y)]), "color": Color(0.9, 0.85, 0.6, 0.3)})
			lines.append({"pts": PackedVector2Array([Vector2(0, c.y), Vector2(b.board_size.x, c.y)]), "color": Color(0.9, 0.85, 0.6, 0.3)})
			lines.append({"pts": Board3D.circle(c, 6.0, 64), "color": Color(0.9, 0.85, 0.6, 0.35), "closed": true})
		"the_chapel":
			var r := Rect2(c - Vector2(6, 8), Vector2(12, 16))
			lines.append({"pts": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), "color": Color(0.9, 0.85, 0.6, 0.4), "closed": true})
		"the_find":
			var r2 := Rect2(c - Vector2(4, 4), Vector2(8, 8))
			lines.append({"pts": PackedVector2Array([r2.position, Vector2(r2.end.x, r2.position.y), r2.end, Vector2(r2.position.x, r2.end.y)]), "color": Color(0.9, 0.85, 0.6, 0.4), "closed": true})
		"street_of_death":
			var x: float = b.board_size.x if b.scen.get("escape_edge", "east") == "east" else 0.0
			lines.append({"pts": PackedVector2Array([Vector2(x, 15.5), Vector2(x, 20.5)]), "color": Color(0.4, 1, 0.4, 0.8)})
	var mire: Dictionary = b.scen.get("black_mire", {})
	if not mire.is_empty():
		fills.append({"poly": Board3D.circle(mire["point"], mire["radius"], 48), "color": Color(0.2, 0.25, 0.1, 0.35)})
	board.draw_overlay(lines, fills)
	board.sync(selected, b.active, highlight)


func _zone_fills(zone: Dictionary, col: Color) -> Array:
	var c := Color(col.r, col.g, col.b, 0.18)
	match zone.get("type", ""):
		"corner":
			var corner: Vector2 = Scenario.corners(b)[zone["corner"]]
			var poly := PackedVector2Array()
			for p in Board3D.circle(corner, zone["radius"], 64):
				if p.x >= 0 and p.y >= 0 and p.x <= b.board_size.x and p.y <= b.board_size.y:
					poly.append(p)
			poly.insert(0, corner)
			var hull := Geometry2D.convex_hull(poly)
			return [{"poly": hull, "color": c}]
		"rect":
			var r: Rect2 = zone["rect"]
			return [{"poly": PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), "color": c}]
		"circle":
			return [{"poly": Board3D.circle(zone["c"], zone["r"]), "color": c}]
		"edges":
			var out: Array = []
			var d: float = zone["depth"]
			var s := b.board_size
			for e in zone["edges"]:
				var rr: Rect2 = [Rect2(0, 0, s.x, d), Rect2(s.x - d, 0, d, s.y), Rect2(0, s.y - d, s.x, d), Rect2(0, 0, d, s.y)][e]
				out.append({"poly": PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), "color": c})
			return out
	return [{"poly": PackedVector2Array([Vector2.ZERO, Vector2(b.board_size.x, 0), b.board_size, Vector2(0, b.board_size.y)]), "color": Color(c.r, c.g, c.b, 0.06)}]


func _on_log(text: String) -> void:
	if log_box == null:
		return
	var col := "#e8dcc0"
	if text.begins_with("—"):
		col = "#d9b45a"
	elif text.contains("☠") or text.contains("taken down"):
		col = "#ff8a70"
	elif text.begins_with("[Table]") or text.begins_with("[Dice]"):
		col = "#a0c0ff"
	log_box.append_text("[color=%s]%s[/color]\n" % [col, text.replace("[", "[lb]") if not text.begins_with("[") else text.replace("[", "[lb]")])
