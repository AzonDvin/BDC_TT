extends Control
## Choose the two warbands, the scenario and the twist, then start a hot-seat battle.

var sources: Array = []          # [{"label", "roster": Callable}]
var pick: Array = [null, null]   # OptionButtons
var status: Array = [null, null]
var scen_opt: OptionButton
var twist_opt: OptionButton
var seed_edit: LineEdit


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for fac in Catalog.FACTION_IDS:
		sources.append({"label": "Sample: %s — %s" % [Catalog.faction_name(fac), Samples.LISTS[fac]["name"]], "make": func(): return Samples.roster(fac)})
	for p in Roster.saved_paths():
		sources.append({"label": "Saved: " + p.get_file().get_basename(), "make": func(): return Roster.load_file(p)})
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UI.vbox(12)
	v.custom_minimum_size = Vector2(900, 0)
	center.add_child(UI.panel(v))
	v.add_child(UI.label("NEW BATTLE", 26, App.GOLD))
	var cols := UI.hbox(20)
	v.add_child(cols)
	for p in 2:
		var c := UI.vbox(6)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(UI.label("Player %d" % (p + 1), 20, App.player_color(p)))
		var labels: Array = []
		for s in sources:
			labels.append(s["label"])
		pick[p] = UI.option(labels, p)
		pick[p].item_selected.connect(func(_i): _update_status())
		c.add_child(pick[p])
		status[p] = UI.label("", 13)
		c.add_child(status[p])
		cols.add_child(c)
	var sc := UI.hbox(10)
	sc.add_child(UI.label("Scenario"))
	var names: Array = ["Random (roll d6)"]
	for id in Scenario.ORDER:
		names.append(Scenario.display_name(id))
	scen_opt = UI.option(names, 0)
	scen_opt.item_selected.connect(func(_i): _fill_twists())
	sc.add_child(scen_opt)
	sc.add_child(UI.label("Twist"))
	twist_opt = OptionButton.new()
	twist_opt.custom_minimum_size = Vector2(260, 0)
	sc.add_child(twist_opt)
	sc.add_child(UI.label("Seed"))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size = Vector2(110, 0)
	sc.add_child(seed_edit)
	v.add_child(sc)
	v.add_child(UI.label("Hot-seat: both players share this screen. The game always shows whose decision it is. Fighters stay on the battlefield floor in this version (no climbing or platforms yet).", 13, Color(0.7, 0.65, 0.55)))
	var row := UI.hbox(10)
	var start := UI.button("Start Battle", _on_start)
	start.custom_minimum_size = Vector2(200, 44)
	start.add_theme_font_size_override("font_size", 20)
	row.add_child(start)
	row.add_child(UI.button("Back", func(): App.go("res://view/main_menu.tscn")))
	v.add_child(row)
	_fill_twists()
	_update_status()


func _fill_twists() -> void:
	twist_opt.clear()
	twist_opt.add_item("Random twist")
	if scen_opt.selected > 0:
		var id: String = Scenario.ORDER[scen_opt.selected - 1]
		for t in Scenario.TWISTS[id]:
			twist_opt.add_item(Scenario.twist_name(t) + ("" if t in Scenario.AUTOMATED_TWISTS else " (manual)"))


func _roster(p: int) -> Roster:
	return sources[pick[p].selected]["make"].call()


func _update_status() -> void:
	for p in 2:
		var r := _roster(p)
		if r == null:
			status[p].text = "Could not load this warband."
			continue
		var errs := r.validate()
		status[p].text = "%s · %d fighters · %ds spent · rating %d%s" % [Catalog.faction_name(r.faction), r.members.size(), r.total_cost(), r.rating(),
			"" if errs.is_empty() else "\n⚠ Not legal: " + errs[0]]


func _on_start() -> void:
	var r0 := _roster(0)
	var r1 := _roster(1)
	if r0 == null or r1 == null:
		return
	var sid := "" if scen_opt.selected == 0 else Scenario.ORDER[scen_opt.selected - 1]
	App.battle_config = {"rosters": [r0, r1], "scenario": sid, "twist": twist_opt.selected - 1,
		"seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else -1}
	App.load_battle_path = ""
	App.go("res://view/battle.tscn")
