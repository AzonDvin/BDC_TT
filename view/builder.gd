extends Control
## Warband builder (Chapter 4): faction, origin, recruit fighters, buy wargear, pick skills and signature spells.
## The roster is validated live against every recruitment rule.

var roster := Roster.new()
var selected_uid := -1

var name_edit: LineEdit
var faction_opt: OptionButton
var origin_opt: OptionButton
var summary: Label
var errors_box: RichTextLabel
var recruit_list: VBoxContainer
var member_list: VBoxContainer
var editor: VBoxContainer
var load_opt: OptionButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.055, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var cols := UI.hbox(10)
	margin.add_child(cols)

	# Left: warband settings
	var left := UI.vbox(8)
	left.custom_minimum_size = Vector2(330, 0)
	cols.add_child(UI.panel(left))
	left.add_child(UI.label("WARBAND", 20, App.GOLD))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Warband name"
	name_edit.text_changed.connect(func(t): roster.name = t)
	left.add_child(name_edit)
	left.add_child(UI.label("Faction"))
	var fac_names: Array = []
	for id in Catalog.FACTION_IDS:
		fac_names.append(Catalog.faction_name(id))
	faction_opt = UI.option(fac_names)
	faction_opt.item_selected.connect(_on_faction)
	left.add_child(faction_opt)
	left.add_child(UI.label("Origin"))
	origin_opt = OptionButton.new()
	origin_opt.item_selected.connect(_on_origin)
	left.add_child(origin_opt)
	summary = UI.label("", 16)
	left.add_child(summary)
	errors_box = RichTextLabel.new()
	errors_box.bbcode_enabled = true
	errors_box.custom_minimum_size = Vector2(0, 160)
	errors_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(errors_box)
	var row := UI.hbox()
	row.add_child(UI.button("Save", _on_save))
	row.add_child(UI.button("New", func(): _set_roster(_fresh(Catalog.FACTION_IDS[faction_opt.selected]))))
	row.add_child(UI.button("Sample", func(): _set_roster(Samples.roster(Catalog.FACTION_IDS[faction_opt.selected]))))
	left.add_child(row)
	var row2 := UI.hbox()
	load_opt = OptionButton.new()
	load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(load_opt)
	row2.add_child(UI.button("Load", _on_load))
	left.add_child(row2)
	left.add_child(UI.button("Back to menu", func(): App.go("res://view/main_menu.tscn")))

	# Middle: available fighters
	var mid := UI.vbox(4)
	mid.custom_minimum_size = Vector2(330, 0)
	var mid_scroll := ScrollContainer.new()
	mid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	recruit_list = UI.vbox(3)
	recruit_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_scroll.add_child(recruit_list)
	mid.add_child(UI.label("RECRUIT", 20, App.GOLD))
	mid.add_child(mid_scroll)
	cols.add_child(UI.panel(mid))

	# Right: roster + editor
	var right := UI.hbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var roster_col := UI.vbox(4)
	roster_col.custom_minimum_size = Vector2(300, 0)
	roster_col.add_child(UI.label("ROSTER", 20, App.GOLD))
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	member_list = UI.vbox(3)
	member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(member_list)
	roster_col.add_child(rs)
	right.add_child(UI.panel(roster_col))
	var es := ScrollContainer.new()
	es.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	es.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor = UI.vbox(6)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	es.add_child(editor)
	var ep := UI.panel(es)
	ep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(ep)

	if App.edit_roster_path != "" and FileAccess.file_exists(App.edit_roster_path):
		_set_roster(Roster.load_file(App.edit_roster_path))
	else:
		_set_roster(Samples.roster(Catalog.FACTION_IDS[0]))
	_refresh_load_list()


func _fresh(fac: String) -> Roster:
	var r := Roster.new()
	r.faction = fac
	r.name = "New %s warband" % Catalog.faction_name(fac)
	r.origin = Catalog.faction(fac)["origins"][0]["id"]
	return r


func _set_roster(r: Roster) -> void:
	roster = r
	selected_uid = -1
	name_edit.text = r.name
	faction_opt.select(Catalog.FACTION_IDS.find(r.faction))
	_fill_origins()
	_refresh()


func _fill_origins() -> void:
	origin_opt.clear()
	var origins: Array = Catalog.faction(roster.faction)["origins"]
	for i in origins.size():
		var o: Dictionary = origins[i]
		origin_opt.add_item("%s (Leader: %s)" % [o["name"], Catalog.fighter_def(roster.faction, o["leader"])["name"]], i)
		if o["id"] == roster.origin:
			origin_opt.select(i)


func _on_faction(i: int) -> void:
	var fac: String = Catalog.FACTION_IDS[i]
	if fac != roster.faction:
		_set_roster(_fresh(fac))


func _on_origin(i: int) -> void:
	roster.origin = Catalog.faction(roster.faction)["origins"][i]["id"]
	_refresh()


func _refresh() -> void:
	summary.text = "Spent %d / %d silver   (left %d)\nFighters: %d / 15   Rating: %d" % [roster.total_cost(), Roster.STARTING_SILVER, roster.silver_left(), roster.members.size(), roster.rating()]
	var errs := roster.validate()
	if errs.is_empty():
		errors_box.text = "[color=#8fd18f]✔ This warband is legal and ready to fight.[/color]"
	else:
		errors_box.text = "[color=#e08a7a]" + "\n".join(Array(errs).map(func(e): return "• " + e)) + "[/color]"
	_fill_recruits()
	_fill_members()
	_fill_editor()


func _fill_recruits() -> void:
	UI.clear(recruit_list)
	var cats := [["leader", "Leaders (1)"], ["champion", "Champions (0-3)"], ["henchman", "Henchmen (5+)"], ["brute", "Brutes (0-2)"], ["beast", "Beasts (0-3)"]]
	for c in cats:
		recruit_list.add_child(UI.label(c[1], 15, App.GOLD))
		for d in Catalog.faction(roster.faction)["fighters"]:
			if d["category"] != c[0] or d.get("not_recruitable", false):
				continue
			var lim := roster.limit_for(d["id"])
			var b := UI.button("%s%s  —  %ds" % ["0-%d " % lim if lim >= 0 and lim < 99 else "", d["name"], d["cost"]], func(): _recruit(d["id"]))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = _def_tooltip(d)
			recruit_list.add_child(b)


func _def_tooltip(d: Dictionary) -> String:
	var s: Dictionary = d["stats"]
	var lines: PackedStringArray = []
	lines.append("%s — %s" % [d["name"], ", ".join(d["keywords"])])
	lines.append("Move %s  Blade %s  Bow %s  Armour %s  Init %s  Will %s  Life %s" % [UI.num(s["move"]), _tn(s["blade"]), _tn(s["bow"]), _tn(s["armour"]), UI.num(s["initiative"]), UI.num(s["willpower"]), UI.num(s["life"])])
	lines.append("Wargear lists: %s" % ", ".join(d.get("wargear_lists", [])) if not d.get("exclusive_wargear", false) else "Fixed wargear only")
	for sr in d.get("special_rules", []):
		lines.append("%s: %s" % [sr["name"], sr["text"]])
	lines.append("Rulebook p.%s" % d.get("page", "?"))
	return "\n".join(lines)


static func _tn(v) -> String:
	return "-" if v == null else "%s+" % UI.num(v)


func _recruit(def_id: String) -> void:
	var m := roster.add_member(def_id)
	selected_uid = m["uid"]
	_refresh()


func _fill_members() -> void:
	UI.clear(member_list)
	var order := {"leader": 0, "champion": 1, "henchman": 2, "brute": 3, "beast": 4}
	var sorted := roster.members.duplicate()
	sorted.sort_custom(func(a, b): return order[roster.def_of(a)["category"]] < order[roster.def_of(b)["category"]])
	for m in sorted:
		var d := roster.def_of(m)
		var bad := not roster.validate_member(m).is_empty()
		var b := UI.button("%s%s (%s) — %ds" % ["⚠ " if bad else "", m["name"], d["name"], roster.member_cost(m)], func(): selected_uid = m["uid"]; _fill_editor())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = m["uid"] == selected_uid
		member_list.add_child(b)


func _fill_editor() -> void:
	UI.clear(editor)
	var m := roster.member(selected_uid)
	if m.is_empty():
		editor.add_child(UI.label("Recruit fighters from the middle column, then click a fighter in your roster to equip them.\n\nHover over a fighter to see their profile.", 15))
		return
	var d := roster.def_of(m)
	editor.add_child(UI.label(d["name"], 22, App.GOLD))
	editor.add_child(UI.label(", ".join(d["keywords"]), 13, Color(0.7, 0.65, 0.55)))
	var ne := LineEdit.new()
	ne.text = m["name"]
	ne.text_changed.connect(func(t): m["name"] = t; _fill_members())
	editor.add_child(ne)
	var s: Dictionary = d["stats"]
	editor.add_child(UI.label("Move %s   Blade %s   Bow %s   Armour %s   Initiative %s   Willpower %s   Life %s" % [UI.num(s["move"]), _tn(s["blade"]), _tn(s["bow"]), _tn(s["armour"]), UI.num(s["initiative"]), UI.num(s["willpower"]), UI.num(s["life"])]))
	editor.add_child(UI.label("Cost with wargear: %ds   Starting XP: %s   (p.%s)" % [roster.member_cost(m), d["starting_xp"], d.get("page", "?")], 13))
	for sr in d.get("special_rules", []):
		editor.add_child(UI.label("• %s: %s" % [sr["name"], sr["text"]], 13))
	if d.has("options"):
		var names: Array = ["(no mutation)"]
		var sel := 0
		for i in d["options"].size():
			names.append("%s (+%ds)" % [d["options"][i]["name"], d["options"][i]["cost"]])
			if d["options"][i]["id"] == m.get("option", ""):
				sel = i + 1
		var oo := UI.option(names, sel)
		oo.item_selected.connect(func(i): m["option"] = "" if i == 0 else d["options"][i - 1]["id"]; _refresh())
		editor.add_child(oo)
	editor.add_child(HSeparator.new())
	editor.add_child(UI.label("WARGEAR", 16, App.GOLD))
	for id in d.get("fixed_wargear", []):
		var w := Catalog.wargear(roster.faction, id)
		editor.add_child(UI.label("• %s (included)" % _gear_text(w), 13))
	for i in m["equipment"].size():
		var id: String = m["equipment"][i]
		var w := Catalog.wargear(roster.faction, id)
		var h := UI.hbox()
		var l := UI.label("• %s — %ds" % [_gear_text(w), w.get("cost", 0)], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = UI.traits_tooltip(w.get("traits", [])) + ("\n" + w.get("text", "") if w.has("text") else "")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		h.add_child(l)
		h.add_child(UI.button("✕", func(): m["equipment"].remove_at(i); _refresh()))
		editor.add_child(h)
	var allowed := roster.allowed_wargear(m)
	for kind in ["melee", "ranged", "armour", "items"]:
		if allowed[kind].is_empty():
			continue
		var ids: Array = allowed[kind]
		var names: Array = ["+ Add %s..." % {"melee": "melee weapon", "ranged": "ranged weapon", "armour": "armour", "items": "item"}[kind]]
		for id in ids:
			var w := Catalog.wargear(roster.faction, id)
			names.append("%s — %ds" % [w.get("name", id), w.get("cost", 0)])
		var o := UI.option(names, 0)
		o.item_selected.connect(func(i):
			if i > 0:
				m["equipment"].append(ids[i - 1])
				_refresh())
		editor.add_child(o)
	var n_skills: int = int(d.get("recruit_skills", 0)) + d.get("starting_skills", []).size()
	if n_skills > 0:
		editor.add_child(HSeparator.new())
		editor.add_child(UI.label("SKILLS (%d)" % n_skills, 16, App.GOLD))
		for i in m["skills"].size():
			var sid: String = m["skills"][i]
			var sk := Catalog.skill(roster.faction, sid)
			var h2 := UI.hbox()
			var l2 := UI.label("• %s: %s" % [sk.get("name", sid), sk.get("text", "")], 13)
			l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h2.add_child(l2)
			if not sid in d.get("starting_skills", []):
				h2.add_child(UI.button("✕", func(): m["skills"].remove_at(i); _refresh()))
			editor.add_child(h2)
		if m["skills"].size() < n_skills:
			var sids: Array = []
			var snames: Array = ["+ Add skill..."]
			for t in Catalog.skill_tables_for(roster.faction, d):
				for sk in t["skills"]:
					if not sk["id"] in m["skills"]:
						sids.append(sk["id"])
						snames.append("%s (%s)" % [sk["name"], t["table"]])
			var so := UI.option(snames, 0)
			so.item_selected.connect(func(i):
				if i > 0:
					m["skills"].append(sids[i - 1])
					_refresh())
			editor.add_child(so)
	var n_sig := int(d.get("signature_spells", 0))
	if n_sig > 0:
		editor.add_child(HSeparator.new())
		editor.add_child(UI.label("SIGNATURE SPELLS (%d)" % n_sig, 16, App.GOLD))
		for i in m["signature_spells"].size():
			var h3 := UI.hbox()
			var l3 := UI.label("• " + m["signature_spells"][i], 13)
			l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h3.add_child(l3)
			h3.add_child(UI.button("✕", func(): m["signature_spells"].remove_at(i); _refresh()))
			editor.add_child(h3)
		if m["signature_spells"].size() < n_sig:
			var spells: Array = []
			var spnames: Array = ["+ Add signature spell..."]
			for lore_id in d["lores"]:
				for sp in Catalog.lore(roster.faction, lore_id)["spells"]:
					if not sp["name"] in m["signature_spells"]:
						spells.append(sp["name"])
						spnames.append("%s (%d+) — %s" % [sp["name"], sp["casting"], sp["text"].left(60)])
			var spo := UI.option(spnames, 0)
			spo.item_selected.connect(func(i):
				if i > 0:
					m["signature_spells"].append(spells[i - 1])
					_refresh())
			editor.add_child(spo)
	var problems := roster.validate_member(m)
	if not problems.is_empty():
		editor.add_child(UI.label("\n".join(problems), 13, Color("e08a7a")))
	editor.add_child(HSeparator.new())
	editor.add_child(UI.button("Remove this fighter", func(): roster.remove_member(selected_uid); selected_uid = -1; _refresh()))


func _gear_text(w: Dictionary) -> String:
	match w.get("kind", ""):
		"melee", "ranged":
			return UI.weapon_line(w)
		"armour":
			return "%s (Armour %d+)" % [w["name"], w["armour"]]
	return "%s%s" % [w.get("name", "?"), " [held]" if w.get("held", false) else ""]


func _on_save() -> void:
	roster.name = name_edit.text.strip_edges() if name_edit.text.strip_edges() != "" else "Warband"
	var err := roster.save()
	summary.text += "\n" + ("Saved." if err == OK else "Save failed (%d)." % err)
	_refresh_load_list()


func _refresh_load_list() -> void:
	load_opt.clear()
	for p in Roster.saved_paths():
		load_opt.add_item(p.get_file().get_basename())
		load_opt.set_item_metadata(load_opt.item_count - 1, p)


func _on_load() -> void:
	if load_opt.item_count == 0:
		return
	var r := Roster.load_file(load_opt.get_item_metadata(load_opt.selected))
	if r:
		_set_roster(r)
