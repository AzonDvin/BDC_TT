class_name Options
extends RefCounted
## What the activating fighter may do right now, with the reason when it can't (pp.19-28).
## The battle screen builds its buttons from this, and the QA tests check it, so both always agree.
##
## Returns {"moves": {kind: reason}, "actions": {key: reason}}; reason "" = allowed.
## Action keys: "melee", "shoot:<weapon id>", "hide", "draw_power", "cast:<spell name>".

const MOVES: PackedStringArray = ["normal", "run", "charge", "disengage"]


static func for_active(b: Battle) -> Dictionary:
	var out := {"moves": {}, "actions": {}}
	var f := b.active_fighter()
	if f == null:
		return out
	var engaged := Effects.is_engaged(b, f)
	var move_block := _move_block(b, f)
	for kind in MOVES:
		var why := move_block
		if why == "":
			match kind:
				"normal":
					if engaged:
						why = "engaged in melee: only a Disengage move"
				"run", "charge":
					if engaged:
						why = "engaged in melee: only a Disengage move"
					elif f.acted:
						why = "only before making an action this activation"
				"disengage":
					if not engaged:
						why = "not engaged in melee"
		out["moves"][kind] = why
	var act_block := _action_block(b, f)
	out["actions"]["melee"] = act_block if act_block != "" else ("" if engaged else "not engaged in melee")
	for w in f.usable_ranged():
		var err := Combat.check_can_shoot(b, f, w)
		out["actions"]["shoot:" + w["id"]] = act_block if act_block != "" else err
	out["actions"]["hide"] = Combat.hide_problem(b, f)
	if f.is_caster():
		var arc := Magic.can_use_arcane(b, f)
		out["actions"]["draw_power"] = arc
		for sp in f.prepared:
			out["actions"]["cast:" + sp["name"]] = arc
	return out


static func _move_block(b: Battle, f: FighterState) -> String:
	if f.moved:
		return "already moved this activation" if f.move_kind != "reload" else "forgone to reload"
	if f.has_effect("heavy_fired"):
		return "fired a Heavy weapon this activation"
	if b.move_or_action_only(f) and f.acted:
		return "surge activation: a move OR an action" if b.active_is_surge else "bloodied: a move OR an action"
	return ""


static func _action_block(b: Battle, f: FighterState) -> String:
	if f.acted:
		return "already made an action this activation"
	if f.move_kind == "run":
		return "made a Run move (no action after running)"
	if b.move_or_action_only(f) and f.moved:
		return "surge activation: a move OR an action" if b.active_is_surge else "bloodied: a move OR an action"
	return ""


## Short summary for reports: allowed options only.
static func allowed(b: Battle) -> PackedStringArray:
	var o := for_active(b)
	var out := PackedStringArray()
	for k in o["moves"]:
		if o["moves"][k] == "":
			out.append("move:" + k)
	for k in o["actions"]:
		if o["actions"][k] == "":
			out.append(k)
	return out
