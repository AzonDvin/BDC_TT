extends Control
## Title screen.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UI.vbox(14)
	v.custom_minimum_size = Vector2(420, 0)
	center.add_child(v)
	var title := UI.label("BLACK DEATH CITY", 46, App.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("Tabletop Simulator · Playtest v1.03 rules", 16, Color(0.7, 0.65, 0.55))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	for row in [["New Battle", "res://view/battle_setup.tscn"], ["Warband Builder", "res://view/builder.tscn"]]:
		var b := UI.button(row[0], func(): App.go(row[1]))
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 20)
		v.add_child(b)
	var load_b := UI.button("Continue Saved Battle", _on_load)
	load_b.custom_minimum_size = Vector2(0, 44)
	load_b.add_theme_font_size_override("font_size", 20)
	load_b.disabled = not FileAccess.file_exists(BattleView.SAVE_PATH)
	v.add_child(load_b)
	var q := UI.button("Quit", func(): get_tree().quit())
	q.custom_minimum_size = Vector2(0, 36)
	v.add_child(q)
	var note := UI.label("Black Death City is by Sam Pearson. Unofficial fan-made simulator for playtesting.", 12, Color(0.5, 0.47, 0.42))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)


func _on_load() -> void:
	App.load_battle_path = BattleView.SAVE_PATH
	App.go("res://view/battle.tscn")
