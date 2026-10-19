class_name UI
extends RefCounted
## Small helpers for building Control trees in code.


static func label(text: String, size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, cb: Callable, tooltip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.pressed.connect(cb)
	return b


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(child)
	return p


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	if not items.is_empty():
		o.select(clampi(selected, 0, items.size() - 1))
	return o


static func rich(bbcode: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = bbcode
	r.scroll_active = false
	return r


## JSON numbers load as floats: show 6.0 as "6", keep strings like "2d6" or "flame".
static func num(v) -> String:
	if v is float and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return str(v)


const TYPE_TAGS := {"leader": "L", "champion": "C", "henchman": "H", "brute": "Br", "beast": "Bs"}
const TYPE_NAMES := {"leader": "Leader", "champion": "Champion", "henchman": "Henchman", "brute": "Brute", "beast": "Beast"}


## A fighter's display name with its type tag, e.g. "[L] Wolfram" (display only; the stored name is unchanged).
static func tagged_name(f: FighterState) -> String:
	return "[%s] %s" % [TYPE_TAGS.get(f.category, "?"), f.name]


static func weapon_line(w: Dictionary) -> String:
	var rng := ""
	if w.has("range"):
		rng = ("Flame" if str(w["range"]) == "flame" else "%s\"" % num(w["range"])) + " "
	var rend := "-" if int(w.get("rend", 0)) == 0 else num(w["rend"])
	var crit = w.get("crit")
	return "%s  %sA%s  R%s  D%s/%s  %s" % [w.get("name", "?"), rng, w.get("attacks", "1"), rend, w.get("damage", "1"), "-" if crit == null else str(crit), ", ".join(w.get("traits", []))]


static func traits_tooltip(traits: Array) -> String:
	var lines: PackedStringArray = []
	for t in traits:
		lines.append("%s: %s" % [t, Catalog.trait_reminder(t)])
	return "\n".join(lines)
