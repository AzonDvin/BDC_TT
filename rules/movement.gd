class_name Movement
extends RefCounted
## Moves (pp.20-22): Normal, Run, Charge, Disengage. A move is declared first (Run/Charge roll their extra d6,
## Disengage takes its Initiative test), then committed with a path of waypoints in inches.

const TOKEN_RADIUS := 0.5


## Declares a move for the active fighter. Returns "" or an error.
static func declare(b: Battle, kind: String) -> String:
	var f := b.active_fighter()
	if f == null:
		return "No fighter is activating."
	if not b.move_plan.is_empty():
		return "A move is already declared."
	if not b.can_still_move(f):
		return "%s cannot make a move now." % f.name
	var engaged := Effects.is_engaged(b, f)
	var extra := 0
	var rolled_2d6 := 0
	var notes: PackedStringArray = []
	match kind:
		"normal":
			if engaged:
				return "Engaged fighters can only Disengage."
		"run", "charge":
			if engaged:
				return "Engaged fighters can only Disengage."
			if f.acted:
				return "A %s move must come before any action." % kind.capitalize()
			if b.move_or_action_only(f) and kind == "charge" and b.cfg.get("bloodied_strict", true):
				notes.append("only a move OR an action this activation, so no attack after the charge")
			extra = b.dice.d6()
			notes.append("+%d\" (d6)" % extra)
		"disengage":
			if not engaged:
				return "Only engaged fighters can Disengage."
			var t := b.dice.test(int(f.stats["initiative"]))
			b.mark_dice_rolled()
			if not t["pass"]:
				f.moved = true
				f.move_kind = "disengage"
				b.log_line("%s fails to disengage (rolled %d vs Initiative %d); the move is used." % [f.name, t["roll"], f.stats["initiative"]])
				b.changed.emit()
				return ""
			b.log_line("%s disengages (rolled %d vs Initiative %d): up to 3\"." % [f.name, t["roll"], f.stats["initiative"]])
			b.move_plan = {"uid": f.uid, "kind": kind, "allowance": 3.0}
			b.changed.emit()
			return ""
		_:
			return "Unknown move %s" % kind
	if str(f.stats["move"]) == "2d6":
		rolled_2d6 = b.dice.d6() + b.dice.d6()
		notes.insert(0, "Move 2d6 = %d\"" % rolled_2d6)
	var allowance := Effects.move_value(b, f, rolled_2d6) + extra
	if f.has_rule("impetuous") and not "impetuous" in f.once_per_battle:
		var imp := b.dice.d6()
		f.once_per_battle.append("impetuous")
		allowance += imp
		notes.append("Impetuous +%d\"" % imp)
	if extra > 0 or rolled_2d6 > 0 or "impetuous" in f.once_per_battle:
		b.mark_dice_rolled()
	b.move_plan = {"uid": f.uid, "kind": kind, "allowance": allowance}
	b.log_line("%s declares a %s move: up to %.1f\"%s." % [f.name, kind.capitalize(), allowance, (" (" + ", ".join(notes) + ")") if not notes.is_empty() else ""])
	b.changed.emit()
	return ""


## A Normal move declared but not yet made can be withdrawn (nothing was rolled).
static func cancel(b: Battle) -> String:
	if b.move_plan.is_empty():
		return "No move declared."
	if b.move_plan["kind"] != "normal":
		return "Dice were rolled for this move; it can't be withdrawn."
	b.move_plan = {}
	b.changed.emit()
	return ""


## Checks a path for the declared move without changing anything.
## Returns {"ok", "error", "cost", "length", "allowance", "deadly": int, "pickup_token": index or -1}.
static func evaluate(b: Battle, path: PackedVector2Array, pickup := false) -> Dictionary:
	var out := {"ok": false, "error": "", "cost": 0.0, "length": 0.0, "allowance": 0.0, "deadly": 0, "pickup_token": -1, "crossings": 0}
	if b.move_plan.is_empty():
		out["error"] = "Declare a move first."
		return out
	var f := b.fighter(b.move_plan["uid"])
	var kind: String = b.move_plan["kind"]
	out["allowance"] = b.move_plan["allowance"]
	if path.size() < 2:
		out["error"] = "Pick a destination."
		return out
	if not path[0].is_equal_approx(f.pos):
		path[0] = f.pos
	var flying := f.has_kw("Fly")
	var length := Geo.path_length(path)
	var crossings := 0
	var deadly := 0
	for t in b.terrain:
		var crossed := _path_enters(path, t.polygon)
		if t.is_low() and crossed and not flying:
			crossings += 1
		if t.kind == "deadly" and crossed and not flying:
			deadly += 1
		if t.blocks_movement():
			if flying:
				if Geo.base_overlaps_polygon(path[path.size() - 1], f.radius, t.polygon):
					out["error"] = "Flying fighters can't end a move on %s." % t.name
					return out
			elif Geo.path_touches_polygon(path, f.radius, t.polygon):
				out["error"] = "The path runs into %s." % t.name
				return out
	var mire := 0
	var m: Dictionary = b.scen.get("black_mire", {})
	if not m.is_empty() and not f.has_kw("Cloister") and not flying:
		if Geo.path_min_gap(path, 0.0, m["point"], 0.0) <= float(m["radius"]):
			mire = 1
	var cost := length + crossings + 2.0 * mire
	if pickup:
		cost += 1.0
	out["length"] = length
	out["cost"] = cost
	out["deadly"] = deadly
	out["crossings"] = crossings
	if cost > float(b.move_plan["allowance"]) + Geo.EPS:
		out["error"] = "Too far: %.1f\" of %.1f\"%s." % [cost, b.move_plan["allowance"], (" (incl. %d\" for low terrain)" % crossings) if crossings > 0 else ""]
		return out
	for p in path:
		if not Geo.base_inside_board(p, f.radius, b.board_size):
			out["error"] = "No part of a fighter may cross the battlefield edge."
			return out
	var end := path[path.size() - 1]
	var near_enemy := false
	for o in b.on_board():
		if o == f:
			continue
		var gap := Geo.path_min_gap(path, f.radius, o.pos, o.radius)
		if gap < -Geo.EPS and not flying:
			out["error"] = "Fighters can't move through %s." % o.name
			return out
		if flying and Geo.signed_gap(end, f.radius, o.pos, o.radius) < -Geo.EPS:
			out["error"] = "Can't end a move on top of %s." % o.name
			return out
		if o.player != f.player:
			var end_gap := Geo.base_gap(end, f.radius, o.pos, o.radius)
			if end_gap <= 1.0 + Geo.EPS:
				near_enemy = true
			if kind in ["normal", "run"] and gap < 1.0 - Geo.EPS:
				out["error"] = "A %s move can't come within 1\" of an enemy (%s)." % [kind, o.name]
				return out
			if kind == "disengage" and end_gap <= 1.0 + Geo.EPS:
				out["error"] = "A Disengage must finish more than 1\" from all enemies."
				return out
	if kind == "charge" and not near_enemy:
		out["error"] = "A Charge must finish within 1\" of an enemy."
		return out
	if pickup:
		out["pickup_token"] = treasure_in_reach(b, f, end)
		if out["pickup_token"] < 0:
			out["error"] = "No treasure within 1/2\" of the destination."
			return out
	out["ok"] = true
	return out


static func _path_enters(path: PackedVector2Array, poly: PackedVector2Array) -> bool:
	for i in range(1, path.size()):
		if Geo.segment_crosses_polygon(path[i - 1], path[i], poly):
			return true
	return false


static func treasure_in_reach(b: Battle, f: FighterState, at: Vector2) -> int:
	if f.treasure > 0 or f.category == "beast" or f.has_kw("Thrall"):
		return -1
	if not Scenario.can_pick_up(b, f):
		return -1
	for i in b.tokens.size():
		var t: Dictionary = b.tokens[i]
		if t["type"] == "treasure" and Geo.base_gap(at, f.radius, t["pos"], TOKEN_RADIUS) <= 0.5 + Geo.EPS:
			return i
	return -1


static func commit(b: Battle, path: PackedVector2Array, pickup := false) -> String:
	var ev := evaluate(b, path, pickup)
	if not ev["ok"]:
		return ev["error"]
	var f := b.fighter(b.move_plan["uid"])
	var kind: String = b.move_plan["kind"]
	if pickup and kind != "normal":
		return "Treasure can only be picked up during a Normal move."
	var from := f.pos
	f.pos = path[path.size() - 1]
	f.moved = true
	f.move_kind = kind
	if kind == "charge":
		f.charged = true
	b.move_plan = {}
	b.log_line("%s makes a %s move of %.1f\" (%.1f\" used)." % [f.name, kind, from.distance_to(f.pos) if path.size() == 2 else ev["length"], ev["cost"]])
	for i in ev["deadly"]:
		var dmg := b.dice.d3()
		b.mark_dice_rolled()
		b.log_line("%s crosses deadly terrain and suffers %d damage." % [f.name, dmg])
		Combat.apply_damage(b, f, dmg, null, "deadly terrain")
	if not f.on_board():
		b.changed.emit()
		return ""
	if pickup and ev["pickup_token"] >= 0:
		Scenario.pick_up(b, f, ev["pickup_token"])
	_update_hidden(b)
	if kind == "charge":
		Combat.after_charge(b, f)
	Scenario.after_move(b, f)
	b.changed.emit()
	return ""


## A charge with no legal path: the fighter doesn't move and its activation ends immediately (p.20).
static func fail_charge(b: Battle) -> String:
	if b.move_plan.get("kind", "") != "charge":
		return "No charge declared."
	var f := b.fighter(b.move_plan["uid"])
	b.move_plan = {}
	f.moved = true
	f.move_kind = "charge"
	b.log_line("%s's charge fails; the activation ends." % f.name)
	return b.end_activation()


## Hidden fighters stop being hidden when an enemy is within 3" or they're no longer touching terrain (p.27).
static func _update_hidden(b: Battle) -> void:
	for h in b.on_board():
		if not h.statuses.get("hidden", false):
			continue
		var lost := not Effects.touching_terrain(b, h)
		for o in b.on_board():
			if o.player != h.player and Geo.within(h.pos, h.radius, o.pos, o.radius, 3.0):
				lost = true
		if lost:
			h.statuses.erase("hidden")
			b.log_line("%s is no longer hidden." % h.name)


## Moves a fighter without rules (scatter, set-up, table tools). Keeps it on the board and off terrain.
static func place(b: Battle, f: FighterState, at: Vector2) -> void:
	at.x = clampf(at.x, f.radius, b.board_size.x - f.radius)
	at.y = clampf(at.y, f.radius, b.board_size.y - f.radius)
	f.pos = at
	_update_hidden(b)


## Scatter (p.22): random direction, stop at high terrain or when touching another fighter.
static func scatter(b: Battle, f: FighterState, inches: float) -> void:
	if f.is_unshakeable():
		b.log_line("%s is Unshakeable and doesn't scatter." % f.name)
		return
	var dir := b.dice.direction()
	var step := 0.1
	var travelled := 0.0
	var pos := f.pos
	var low_paid: Array = []
	var budget := inches
	while travelled + step <= budget:
		var nxt := pos + dir * step
		var stop := false
		if not Geo.base_inside_board(nxt, f.radius, b.board_size):
			stop = true
		for t in b.terrain:
			if t.blocks_movement() and Geo.base_overlaps_polygon(nxt, f.radius, t.polygon):
				stop = true
			elif t.is_low() and not t in low_paid and Geo.base_overlaps_polygon(nxt, f.radius, t.polygon):
				low_paid.append(t)
				budget -= 1.0
		for o in b.on_board():
			if o != f and Geo.signed_gap(nxt, f.radius, o.pos, o.radius) <= 0.0:
				stop = true
		if stop:
			break
		pos = nxt
		travelled += step
	b.log_line("%s scatters %.1f\"." % [f.name, f.pos.distance_to(pos)])
	f.pos = pos
	_update_hidden(b)
