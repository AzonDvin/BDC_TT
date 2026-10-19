extends Node
## Terrain editor: build a battlefield by hand, then save it as a layout to fight over.
## Controls: pick a piece in the palette, click the table to place it (Shift keeps placing).
## Click a piece to select it, drag to move it. R / F rotate · Up / Down height · + / - size ·
## Delete removes · Ctrl+D duplicates. Right-drag orbit, middle-drag or WASD pan, wheel zoom.

const PALETTE := [
	["ruin", "Ruin (walls, doorway, window, upper floor)"],
	["house", "Ruined house (walkable roof)"],
	["tower", "Tower with ladder"],
	["wall", "High wall"],
	["low_wall", "Low wall"],
	["rubble", "Rubble"],
	["platform", "Upper floor / platform"],
	["ladder", "Ladder"],
	["door", "Doorway"],
	["window", "Window"],
	["statue", "Statue (impassable)"],
	["tree", "Dead tree (impassable)"],
	["pit", "Deadly pit"],
]

var b: Battle
var board: Board3D
var tool := "select"
var place_rot := 0.0
var selected: Array = []          # pieces in the selected group
var selected_piece: TerrainPiece
var dragging := false
var drag_from := Vector2.ZERO
var hover := Vector2.INF
var _rotating := false
var _panning := false

var info: RichTextLabel
var hint: Label
var name_edit: LineEdit
var load_opt: OptionButton
var scen_opt: OptionButton
var palette_box: VBoxContainer


func _ready() -> void:
	b = Battle.new()
	b.dice = Dice.new(int(Time.get_ticks_usec() % 100000))
	b.scen = {"id": "a_deadly_encounter", "twist_id": "", "vp": [0, 0], "marks": [0, 0], "escaped": [0, 0]}
	board = Board3D.new()
	add_child(board)
	board.build(b)
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var left := UI.vbox(5)
	left.custom_minimum_size = Vector2(290, 0)
	var lp := UI.panel(left)
	lp.position = Vector2(8, 8)
	root.add_child(lp)
	left.add_child(UI.label("TERRAIN EDITOR", 20, App.GOLD))
	palette_box = UI.vbox(3)
	left.add_child(palette_box)
	var sel := UI.button("Select / move", func(): tool = "select"; _refresh())
	palette_box.add_child(sel)
	for row in PALETTE:
		var bt := UI.button(row[1], func(): tool = row[0]; _refresh())
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.add_theme_font_size_override("font_size", 13)
		palette_box.add_child(bt)
	left.add_child(HSeparator.new())
	var r1 := UI.hbox()
	r1.add_child(UI.button("Clear table", func(): b.terrain.clear(); _select(null); _rebuild()))
	left.add_child(r1)
	var r2 := UI.hbox()
	var names: Array = []
	for id in Scenario.ORDER:
		names.append(Scenario.display_name(id))
	scen_opt = UI.option(names, 0)
	scen_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(scen_opt)
	r2.add_child(UI.button("Random", _random_layout, "Generate a random battlefield for this scenario's layout"))
	left.add_child(r2)
	left.add_child(HSeparator.new())
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Layout name"
	name_edit.text = "My District"
	left.add_child(name_edit)
	var r3 := UI.hbox()
	r3.add_child(UI.button("Save layout", _save))
	left.add_child(r3)
	var r4 := UI.hbox()
	load_opt = OptionButton.new()
	load_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r4.add_child(load_opt)
	r4.add_child(UI.button("Load", _load))
	left.add_child(r4)
	left.add_child(UI.button("Back to menu", func(): App.go("res://view/main_menu.tscn")))
	_refresh_load_list()

	var right := UI.vbox(6)
	right.custom_minimum_size = Vector2(330, 0)
	var rp := UI.panel(right)
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.offset_left = -346
	rp.offset_right = -8
	rp.offset_top = 8
	root.add_child(rp)
	info = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	right.add_child(info)
	var ctl := HFlowContainer.new()
	for row in [["⟲ 15°", func(): _rotate(-PI / 12)], ["⟳ 15°", func(): _rotate(PI / 12)], ["Height +", func(): _height(0.5)], ["Height −", func(): _height(-0.5)],
			["Bigger", func(): _scale(1.15)], ["Smaller", func(): _scale(1 / 1.15)], ["Door open/closed", _toggle_door], ["Duplicate", _duplicate],
			["Delete piece", _delete_piece], ["Delete group", _delete_group]]:
		ctl.add_child(UI.button(row[0], row[1]))
	right.add_child(ctl)
	hint = UI.label("", 13, Color(0.75, 0.7, 0.6))
	right.add_child(hint)


# --- Actions ------------------------------------------------------------------------------------

func _next_group() -> int:
	var g := 1
	for t in b.terrain:
		g = maxi(g, t.group + 1)
	return g


func _make(kind: String, pos: Vector2, rot: float) -> Array:
	match kind:
		"ruin":
			return Scenario._ruin(b, pos, rot)
		"house":
			return Scenario._house(b, pos, rot)
		"tower":
			return [TerrainPiece.make("Tower", "high", Geo.rect_polygon(pos, Vector2(3, 3), rot), 8.0),
				TerrainPiece.make("Ladder", "ladder", Geo.rect_polygon(pos + Vector2(1.7, 0).rotated(rot), Vector2(0.4, 1.0), rot), 8.0)]
		"wall":
			return [TerrainPiece.make("Ruined wall", "high", Geo.rect_polygon(pos, Vector2(5, 0.25), rot), 4.0)]
		"low_wall":
			return [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(pos, Vector2(4, 0.4), rot), 1.0)]
		"rubble":
			return [TerrainPiece.make("Rubble", "low", Scenario._blob(b, pos, 1.5), 0.6)]
		"platform":
			return [TerrainPiece.make("Upper floor", "platform", Geo.rect_polygon(pos, Vector2(4, 4), rot), 3.0)]
		"ladder":
			return [TerrainPiece.make("Ladder", "ladder", Geo.rect_polygon(pos, Vector2(0.4, 1.0), rot), 3.0)]
		"door":
			var d := TerrainPiece.make("Doorway", "door", Geo.rect_polygon(pos, Vector2(1.4, 0.25), rot), 4.0)
			d.lintel = 2.8
			return [d]
		"window":
			return [TerrainPiece.make("Window", "window", Geo.rect_polygon(pos, Vector2(1.2, 0.25), rot), 4.0)]
		"statue":
			return [TerrainPiece.make("Statue", "impassable", Geo.circle_polygon(pos, 0.8, 12), 3.0)]
		"tree":
			return [TerrainPiece.make("Dead tree", "impassable", Geo.circle_polygon(pos, 1.2, 10), 5.0)]
		"pit":
			return [TerrainPiece.make("Deadly pit", "deadly", Scenario._blob(b, pos, 1.6), 0.1)]
	return []


func _place(p: Vector2) -> void:
	var pieces := _make(tool, p, place_rot)
	var g := _next_group()
	for t in pieces:
		t.group = g
		b.terrain.append(t)
	_select(pieces[0] if not pieces.is_empty() else null)
	if not Input.is_key_pressed(KEY_SHIFT):
		tool = "select"
	_rebuild()


func _piece_at(p: Vector2) -> TerrainPiece:
	var best: TerrainPiece = null
	for t in b.terrain:
		if Geometry2D.is_point_in_polygon(p, t.polygon) or Geo.base_overlaps_polygon(p, 0.3, t.polygon):
			if best == null or t.height > best.height or (t.kind == "ladder"):
				best = t
	return best


func _select(t: TerrainPiece) -> void:
	selected_piece = t
	selected = []
	if t == null:
		return
	if t.group == 0:
		selected = [t]
		return
	for o in b.terrain:
		if o.group == t.group:
			selected.append(o)


func _centroid(pieces: Array) -> Vector2:
	var c := Vector2.ZERO
	var n := 0
	for t in pieces:
		for p in t.polygon:
			c += p
			n += 1
	return c / maxf(n, 1)


func _translate(delta: Vector2) -> void:
	for t in selected:
		var poly := PackedVector2Array()
		for p in t.polygon:
			poly.append(p + delta)
		t.polygon = poly


func _rotate(ang: float) -> void:
	if selected.is_empty():
		place_rot += ang
		_refresh()
		return
	var c := _centroid(selected)
	for t in selected:
		var poly := PackedVector2Array()
		for p in t.polygon:
			poly.append(c + (p - c).rotated(ang))
		t.polygon = poly
	_rebuild()


func _height(d: float) -> void:
	if selected_piece == null:
		return
	selected_piece.height = clampf(selected_piece.height + d, 0.1, 12.0)
	if selected_piece.kind == "platform":
		# Keep ladders in the same group reaching the floor.
		for t in selected:
			if t.kind == "ladder":
				t.height = selected_piece.height
	_rebuild()


func _scale(k: float) -> void:
	if selected_piece == null:
		return
	var c := _centroid([selected_piece])
	var poly := PackedVector2Array()
	for p in selected_piece.polygon:
		poly.append(c + (p - c) * k)
	selected_piece.polygon = poly
	_rebuild()


func _toggle_door() -> void:
	if selected_piece and selected_piece.kind == "door":
		selected_piece.closed = not selected_piece.closed
		_rebuild()


func _duplicate() -> void:
	if selected.is_empty():
		return
	var g := _next_group()
	var copies: Array = []
	for t in selected:
		var c: TerrainPiece = t.duplicate_piece()
		c.group = g if t.group != 0 else 0
		var poly := PackedVector2Array()
		for p in c.polygon:
			poly.append(p + Vector2(3, 3))
		c.polygon = poly
		b.terrain.append(c)
		copies.append(c)
	_select(copies[0])
	_rebuild()


func _delete_piece() -> void:
	if selected_piece:
		b.terrain.erase(selected_piece)
		_select(null)
		_rebuild()


func _delete_group() -> void:
	for t in selected:
		b.terrain.erase(t)
	_select(null)
	_rebuild()


func _random_layout() -> void:
	b.scen["id"] = Scenario.ORDER[scen_opt.selected]
	b.scen["twist_id"] = ""
	Scenario.generate_terrain(b)
	_select(null)
	_rebuild()


func _save() -> void:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Layout"
	var err := Layout.save(nm, b.terrain, b.board_size)
	hint.text = "Saved \"%s\"." % nm if err == OK else "Save failed (%d)." % err
	_refresh_load_list()


func _refresh_load_list() -> void:
	load_opt.clear()
	for p in Layout.saved_paths():
		load_opt.add_item(p.get_file().get_basename())
		load_opt.set_item_metadata(load_opt.item_count - 1, p)


func _load() -> void:
	if load_opt.item_count == 0:
		return
	var d := Layout.load_file(load_opt.get_item_metadata(load_opt.selected))
	b.terrain = Layout.pieces_of(d)
	name_edit.text = d.get("name", "Layout")
	_select(null)
	_rebuild()


func _rebuild() -> void:
	board.rebuild_terrain()
	_refresh()


# --- Display --------------------------------------------------------------------------------------

func _refresh() -> void:
	for c in palette_box.get_children():
		if c is Button:
			c.modulate = Color.WHITE
	var t := "[b]Tool:[/b] %s\n" % ("select / move" if tool == "select" else tool.replace("_", " ") + " — click the table to place (Shift keeps placing)")
	if tool != "select":
		t += "Placement rotation: %d°\n" % int(round(rad_to_deg(place_rot)))
	if selected_piece:
		var s := selected_piece
		t += "\n[b][color=#d9b45a]%s[/color][/b] (%s)\nHeight %.1f\"%s%s\nGroup: %d piece(s)\n" % [s.name, s.kind, s.height,
			"  · walkable top" if s.has_surface() else "", "  · CLOSED" if s.kind == "door" and s.closed else "", selected.size()]
		var off := false
		for p in s.polygon:
			if p.x < 0 or p.y < 0 or p.x > b.board_size.x or p.y > b.board_size.y:
				off = true
		if off:
			t += "[color=#ff8a70]Part of this piece is off the battlefield.[/color]\n"
	else:
		t += "\nClick a piece to select it."
	t += "\n[color=#a89e88]%d pieces on the table.[/color]" % b.terrain.size()
	info.text = t
	if hint.text == "":
		hint.text = "R / F rotate · Up / Down height · + / - size · Delete removes · Ctrl+D duplicates · drag to move"
	_overlay()


func _overlay() -> void:
	var lines: Array = []
	for s in selected:
		lines.append({"pts": s.polygon, "color": App.GOLD if s == selected_piece else Color(0.9, 0.8, 0.4, 0.5), "closed": true, "z": s.height})
	if tool != "select" and hover != Vector2.INF:
		var ghost := _make(tool, hover, place_rot)
		for g in ghost:
			lines.append({"pts": g.polygon, "color": Color(0.5, 1.0, 0.6, 0.8), "closed": true, "z": 0.05})
	var c := b.board_size / 2.0
	lines.append({"pts": Board3D.circle(c, 6.0, 48), "color": Color(1, 1, 1, 0.12), "closed": true})
	for corner in Scenario.corners(b):
		lines.append({"pts": Board3D.circle(corner, 9.0, 48), "color": Color(1, 1, 1, 0.08), "closed": true})
	board.draw_overlay(lines)


# --- Input ----------------------------------------------------------------------------------------

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
				var p := board.ground_point(mb.position)
				if mb.pressed and p != Vector2.INF:
					if tool != "select":
						_place(p)
					else:
						_select(_piece_at(p))
						dragging = selected_piece != null
						drag_from = p
						_refresh()
				elif not mb.pressed and dragging:
					dragging = false
					_rebuild()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rotating:
			board.orbit(mm.relative.x, mm.relative.y)
		elif _panning:
			board.pan(mm.relative)
		else:
			hover = board.ground_point(mm.position)
			if dragging and hover != Vector2.INF:
				_translate(hover - drag_from)
				drag_from = hover
				board.rebuild_terrain()
			_overlay()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_rotate(PI / 12)
			KEY_F:
				_rotate(-PI / 12)
			KEY_UP:
				_height(0.5)
			KEY_DOWN:
				_height(-0.5)
			KEY_EQUAL, KEY_KP_ADD:
				_scale(1.15)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_scale(1 / 1.15)
			KEY_DELETE, KEY_BACKSPACE:
				_delete_group()
			KEY_D:
				if event.ctrl_pressed:
					_duplicate()
			KEY_ESCAPE:
				tool = "select"
				_select(null)
				_refresh()


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		v.y += 1
	if Input.is_key_pressed(KEY_S):
		v.y -= 1
	if Input.is_key_pressed(KEY_A):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) and not Input.is_key_pressed(KEY_CTRL):
		v.x += 1
	if v != Vector2.ZERO:
		board.pan(v * 900 * delta)
