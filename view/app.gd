extends Node
## Autoload "App": settings passed between scenes, the UI theme, and player colours.

const PLAYER_COLORS := [Color("c8423b"), Color("3f7fd6")]
const GOLD := Color("d9b45a")
const PAPER := Color("e8dcc0")
const INK := Color("1b1915")

var battle_config := {}          # {"rosters": [Roster, Roster], "scenario": id, "twist": int, "seed": int, "layout": {}, "ai": ["", "normal"]}
var load_battle_path := ""
var ai_speed := 1                # computer player pace: index into BattleView.AI_SPEEDS
var sound_on := true
const SETTINGS_PATH := "user://settings.cfg"
var edit_roster_path := ""
var theme: Theme


func _ready() -> void:
	theme = build_theme()
	get_tree().root.theme = theme
	load_settings()


## Player preferences kept between sessions: sound on/off and the computer's pace.
func load_settings() -> void:
	var c := ConfigFile.new()
	if c.load(SETTINGS_PATH) == OK:
		sound_on = bool(c.get_value("game", "sound_on", true))
		ai_speed = int(c.get_value("game", "ai_speed", 1))
	apply_sound()


func save_settings() -> void:
	var c := ConfigFile.new()
	c.set_value("game", "sound_on", sound_on)
	c.set_value("game", "ai_speed", ai_speed)
	c.save(SETTINGS_PATH)


func apply_sound() -> void:
	AudioServer.set_bus_mute(0, not sound_on)


func player_color(p: int) -> Color:
	return PLAYER_COLORS[clampi(p, 0, 1)]


func go(scene: String) -> void:
	get_tree().change_scene_to_file(scene)


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.085, 0.08, 0.93)
	panel.border_color = Color(0.55, 0.45, 0.25, 0.8)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.2, 0.18, 0.15)
	btn.border_color = Color(0.5, 0.42, 0.25)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.content_margin_left = 10
	btn.content_margin_right = 10
	btn.content_margin_top = 4
	btn.content_margin_bottom = 4
	var hover := btn.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.3, 0.26, 0.19)
	var pressed := btn.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.45, 0.36, 0.18)
	var disabled := btn.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.13, 0.12, 0.11)
	disabled.border_color = Color(0.25, 0.22, 0.18)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, PAPER)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.42, 0.38))
	t.set_color("font_color", "Label", PAPER)
	t.set_color("default_color", "RichTextLabel", PAPER)
	var le := StyleBoxFlat.new()
	le.bg_color = Color(0.05, 0.05, 0.05)
	le.border_color = Color(0.4, 0.35, 0.25)
	le.set_border_width_all(1)
	le.set_content_margin_all(5)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("normal", "SpinBox", le)
	t.set_color("font_color", "LineEdit", PAPER)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.06, 0.055, 0.05, 0.97)
	tip.border_color = GOLD
	tip.set_border_width_all(1)
	tip.set_content_margin_all(6)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", PAPER)
	return t
