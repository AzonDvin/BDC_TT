extends Control
## Choose the two warbands, the scenario, twist and battlefield, then start a hot-seat battle.
## Layout: a scrollable form in the middle, with the Start / Back buttons pinned to the bottom so they are
## always on screen whatever the window size.

const SCENARIO_SUMMARY := {
	"a_deadly_encounter": "Two warbands clash. Score victory points for each enemy taken down and for holding the centre; first to 8 at the end of a round wins.",
	"glimmers_in_the_dark": "Treasure lies near the centre. The first warband to get 3 fighters off the table carrying treasure wins.",
	"no_quarter": "Fight for the four quarters of the district. From round 3, control quarters to earn domination marks; 10 wins.",
	"the_chapel": "A ruined chapel holds treasure in its corners. Each enemy taken down is a death mark; 8 wins.",
	"street_of_death": "The underdog ambushes a marked enemy Leader or Champion (the Hit) as they try to escape down the street.",
	"the_find": "The Defender guards a stash in the central holding; the Attacker tries to get 3 treasures off the table first.",
}

var sources: Array = []
var pick: Array = [null, null]
var status: Array = [null, null]
var scen_opt: OptionButton
var twist_opt: OptionButton
var seed_edit: LineEdit
var layout_opt: OptionButton
var played_by: Array = [null, null]
const CONTROLLERS := [["Human", ""], ["Computer (normal)", "normal"], ["Computer (easy)", "easy"]]
var summary: Label


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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var outer := UI.vbox(12)
	margin.add_child(outer)
	outer.add_child(_plain("NEW BATTLE", 30, App.GOLD))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var form := UI.vbox(16)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	# Warbands, side by side
	var cols := UI.hbox(24)
	form.add_child(cols)
	var labels: Array = []
	for s in sources:
		labels.append(s["label"])
	for p in 2:
		var c := UI.vbox(6)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(_plain("Player %d" % (p + 1), 22, App.player_color(p)))
		pick[p] = UI.option(labels, p)
		pick[p].add_theme_font_size_override("font_size", 17)
		pick[p].item_selected.connect(func(_i): _update_status())
		c.add_child(pick[p])
		var by: Array = []
		for c2 in CONTROLLERS:
			by.append("Played by: " + c2[0])
		played_by[p] = UI.option(by, 0 if p == 0 else 1)
		played_by[p].tooltip_text = "Human: you make this player's decisions. Computer: the AI plays this warband (normal plans moves, objectives and targets; easy just heads for the nearest enemy)."
		c.add_child(played_by[p])
		status[p] = UI.label("", 15, Color(0.8, 0.76, 0.68))
		c.add_child(status[p])
		var panel := UI.panel(c)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(panel)

	# Battle settings as a label / control grid
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	var grid_panel := UI.panel(grid)
	form.add_child(grid_panel)

	var names: Array = ["Random (roll a d6)"]
	for id in Scenario.ORDER:
		names.append(Scenario.display_name(id))
	scen_opt = UI.option(names, 0)
	scen_opt.item_selected.connect(func(_i): _fill_twists(); _update_summary())
	_grid_row(grid, "Scenario", scen_opt)
	twist_opt = OptionButton.new()
	twist_opt.item_selected.connect(func(_i): _update_summary())
	_grid_row(grid, "Twist", twist_opt)
	layout_opt = OptionButton.new()
	layout_opt.add_item("Random ruins for the scenario")
	for p in Layout.saved_paths():
		layout_opt.add_item("Layout: " + p.get_file().get_basename())
		layout_opt.set_item_metadata(layout_opt.item_count - 1, p)
	_grid_row(grid, "Battlefield", layout_opt)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random (enter a number to replay the same dice)"
	_grid_row(grid, "Dice seed", seed_edit)

	summary = UI.label("", 16, App.PAPER)
	var sp := UI.panel(summary)
	form.add_child(sp)
	form.add_child(UI.label("One player: set the other side to a Computer opponent. Hot-seat: set both to Human and share this screen; the game always shows whose decision it is. Make your own warbands in the Warband Builder and battlefields in the Terrain Editor.", 14, Color(0.7, 0.65, 0.55)))

	# Pinned buttons
	var row := UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	var back := UI.button("Back", func(): App.go("res://view/main_menu.tscn"))
	back.custom_minimum_size = Vector2(140, 48)
	back.add_theme_font_size_override("font_size", 18)
	row.add_child(back)
	var start := UI.button("Start Battle  ▶", _on_start)
	start.custom_minimum_size = Vector2(240, 48)
	start.add_theme_font_size_override("font_size", 22)
	row.add_child(start)
	outer.add_child(row)

	_fill_twists()
	_update_status()
	_update_summary()


## A single-line label that never wraps (wrapping labels in rows collapse to one character wide).
func _plain(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := UI.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _grid_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := _plain(text, 18, App.GOLD)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size = Vector2(420, 38)
	control.add_theme_font_size_override("font_size", 17)
	grid.add_child(control)


func _fill_twists() -> void:
	twist_opt.clear()
	twist_opt.add_item("Random twist")
	if scen_opt.selected > 0:
		var id: String = Scenario.ORDER[scen_opt.selected - 1]
		for t in Scenario.TWISTS[id]:
			twist_opt.add_item(Scenario.twist_name(t))


func _update_summary() -> void:
	if scen_opt.selected == 0:
		summary.text = "The scenario is rolled when the battle starts (d6), as in the book: A Deadly Encounter, Glimmers in the Dark, No Quarter, The Chapel, Street of Death or The Find. The twist is rolled too."
		return
	var id: String = Scenario.ORDER[scen_opt.selected - 1]
	var tw := "rolled at the start" if twist_opt.selected <= 0 else Scenario.twist_name(Scenario.TWISTS[id][twist_opt.selected - 1])
	var tw_text := Scenario.twist_description(Scenario.TWISTS[id][twist_opt.selected - 1]) if twist_opt.selected > 0 and Scenario.TWISTS.has(id) and twist_opt.selected - 1 < Scenario.TWISTS[id].size() else ""
	summary.text = "%s — %s\nTwist: %s.%s" % [Scenario.display_name(id), SCENARIO_SUMMARY.get(id, ""), tw, (" " + tw_text) if tw_text != "" else ""]


func _roster(p: int) -> Roster:
	return sources[pick[p].selected]["make"].call()


func _update_status() -> void:
	for p in 2:
		var r := _roster(p)
		if r == null:
			status[p].text = "Could not load this warband."
			continue
		var errs := r.validate()
		status[p].text = "%s · %d fighters · %d silver spent · rating %d%s" % [Catalog.faction_name(r.faction), r.members.size(), r.total_cost(), r.rating(),
			"" if errs.is_empty() else "\n⚠ Not legal: " + errs[0]]


func _on_start() -> void:
	var r0 := _roster(0)
	var r1 := _roster(1)
	if r0 == null or r1 == null:
		return
	var sid := "" if scen_opt.selected == 0 else Scenario.ORDER[scen_opt.selected - 1]
	App.battle_config = {"rosters": [r0, r1], "scenario": sid, "twist": twist_opt.selected - 1,
		"seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else -1,
		"layout": Layout.load_file(layout_opt.get_item_metadata(layout_opt.selected)) if layout_opt.selected > 0 else {},
		"ai": [CONTROLLERS[played_by[0].selected][1], CONTROLLERS[played_by[1].selected][1]]}
	App.load_battle_path = ""
	App.go("res://view/battle.tscn")
