class_name Scenario
extends RefCounted
## The six scenarios of Chapter 3 (pp.35-48): battlefield, battle groups, deployment, reserves and
## reinforcements, treasure, twists and victory conditions. State lives in battle.scen.

const NAMES := {
	"a_deadly_encounter": "A Deadly Encounter",
	"glimmers_in_the_dark": "Glimmers in the Dark",
	"no_quarter": "No Quarter",
	"the_chapel": "The Chapel",
	"street_of_death": "Street of Death",
	"the_find": "The Find",
}
const ORDER: PackedStringArray = ["a_deadly_encounter", "glimmers_in_the_dark", "no_quarter", "the_chapel", "street_of_death", "the_find"]

const TWISTS := {
	"a_deadly_encounter": ["a_brewing_storm", "battle_for_the_tower", "outflank", "delayed_arrival", "condemned", "the_chest"],
	"glimmers_in_the_dark": ["cursed_coin", "false_riches", "thieves_in_the_dark", "beggars_desperation", "saint_tricksters_game", "upturned_wagon"],
	"no_quarter": ["rolling_fog", "show_of_strength", "the_forsaken_quarter", "turf_war", "the_critical_quarter", "saints_statue"],
	"the_chapel": ["a_hidden_trove", "desecrated_ground", "the_saints_sarcophagus"],
	"street_of_death": ["drunk_as_an_eel", "heavy_downpour", "vow_of_blood", "hidden_tunnel", "shadows_lurk_above", "tip_off"],
	"the_find": ["on_fire", "defiant_stand", "barricaded_holdout", "delayed_arrival", "surrounded_on_all_sides", "old_debt_collectors_house"],
}

## Twists the simulator applies automatically; the rest are shown to the players to resolve on the table.
const AUTOMATED_TWISTS: PackedStringArray = ["a_brewing_storm", "outflank", "delayed_arrival", "thieves_in_the_dark", "beggars_desperation",
	"upturned_wagon", "false_riches", "show_of_strength", "turf_war", "a_hidden_trove", "heavy_downpour", "vow_of_blood", "tip_off",
	"defiant_stand", "old_debt_collectors_house", "battle_for_the_tower", "cursed_coin", "saints_statue", "surrounded_on_all_sides"]


static func display_name(id: String) -> String:
	return NAMES.get(id, id)


static func twist_name(id: String) -> String:
	return id.replace("_", " ").capitalize()


static func center(b: Battle) -> Vector2:
	return b.board_size / 2.0


static func corners(b: Battle) -> Array:
	return [Vector2(0, 0), Vector2(b.board_size.x, 0), b.board_size, Vector2(0, b.board_size.y)]


# =============================================================================================
# Setup

static func setup(b: Battle, id: String, twist_index: int) -> void:
	if not NAMES.has(id):
		id = ORDER[b.dice.d6() - 1]
	var twists: Array = TWISTS[id]
	if twist_index < 0:
		twist_index = (b.dice.d3() if twists.size() == 3 else b.dice.d6()) - 1
	var twist_id: String = twists[clampi(twist_index, 0, twists.size() - 1)]
	b.scen = {"id": id, "twist_id": twist_id, "vp": [0, 0], "marks": [0, 0], "escaped": [0, 0], "groups": 2,
		"deploy_radius": 12.0, "reinforce_round": [3, 3], "entry": [-1, -1]}
	b.log_line("Scenario: %s. Twist: %s%s." % [NAMES[id], twist_name(twist_id), "" if twist_id in AUTOMATED_TWISTS else " (resolve its effects on the table)"])
	match id:
		"a_deadly_encounter":
			b.scen["groups"] = 3 if twist_id == "outflank" else 2
			b.scen["reinforce_round"] = [6, 6] if twist_id == "delayed_arrival" else [3, 3]
		"glimmers_in_the_dark":
			b.scen["groups"] = 3
			b.scen["reinforce_round"] = [2, 2]
		"no_quarter":
			b.scen["groups"] = 1 if twist_id == "show_of_strength" else 3
			b.scen["deploy_radius"] = 9.0
			b.scen["reinforce_round"] = [2, 2]
		"the_chapel":
			b.scen["groups"] = 3
			b.scen["deploy_radius"] = 9.0
		"street_of_death":
			b.scen["ambusher"] = b.underdog
			b.scen["defender"] = b.other(b.underdog)
			b.scen["reinforce_round"] = [0, 0]
			b.scen["reinforce_round"][b.underdog] = 2
			b.scen["reinforce_round"][b.other(b.underdog)] = 3
		"the_find":
			b.scen["deploy_radius"] = 6.0
			b.scen["reinforce_round"] = [6, 6] if twist_id == "delayed_arrival" else [3, 3]
	match twist_id:
		"thieves_in_the_dark":
			b.scen["visibility_limit"] = 9.0
		"heavy_downpour":
			b.scen["visibility_limit"] = 9.0
			b.scen["rain"] = true
	generate_terrain(b)
	_place_treasure(b)
	_assign_battle_groups(b)
	if id == "street_of_death":
		_setup_street(b)
	elif id == "the_find":
		var attacker := b.dice.roll_off()
		b.scen["attacker"] = attacker
		b.scen["defender"] = b.other(attacker)
		b.log_line("%s is the Attacker, %s the Defender." % [b.player_names[attacker], b.player_names[b.other(attacker)]])
		b.pending = {"type": "pick_entry", "player": attacker}
	else:
		var w := b.dice.roll_off()
		b.log_line("%s wins the deployment roll-off and picks an entry point." % b.player_names[w])
		b.pending = {"type": "pick_entry", "player": w}
	b.phase = "deploy"


## Splits each warband into battle groups as equal as possible (p.35), randomly.
static func _assign_battle_groups(b: Battle) -> void:
	var n: int = b.scen["groups"]
	for p in 2:
		var mine: Array = []
		for f in b.fighters:
			if f.player == p:
				mine.append(f)
		for i in range(mine.size() - 1, 0, -1):
			var j := b.dice.rng.randi_range(0, i)
			var tmp = mine[i]
			mine[i] = mine[j]
			mine[j] = tmp
		for i in mine.size():
			mine[i].battle_group = i % n
			mine[i].where = "reserve"


static func _setup_street(b: Battle) -> void:
	var defender: int = b.scen["defender"]
	var cands: Array = []
	for f in b.fighters:
		if f.player == defender and (f.has_kw("Leader") or f.has_kw("Champion")):
			cands.append(f)
	var hit: FighterState = cands[b.dice.rng.randi_range(0, cands.size() - 1)] if not cands.is_empty() else null
	var all_def: Array = []
	for f in b.fighters:
		if f.player == defender:
			all_def.append(f)
	if hit == null:
		hit = all_def[0]
	hit.marks.append("hit")
	if b.scen["twist_id"] == "vow_of_blood":
		hit.stats["life"] = int(hit.stats["life"]) + 3
		hit.life = int(hit.stats["life"])
	var escorts := b.dice.d6()
	b.log_line("The Hit is %s, escorted by %d fighter(s). Ambusher: %s." % [hit.name, escorts, b.player_names[b.scen["ambusher"]]])
	var others: Array = []
	for f in all_def:
		if f != hit:
			others.append(f)
	# Escorts can't be Leaders or Champions; everyone else forms 2 battle groups in reserve.
	var escorts_left := escorts
	var k := 0
	for f in others:
		if escorts_left > 0 and not (f.has_kw("Leader") or f.has_kw("Champion")):
			f.battle_group = 0
			escorts_left -= 1
		else:
			f.battle_group = 1 + (k % 2)
			k += 1
	hit.battle_group = 0
	b.scen["escape_edge"] = "east" if b.dice.d6() >= 4 else "west"
	b.log_line("The escape edge is the %s end of the street." % b.scen["escape_edge"])
	b.pending = {}
	_deploy_next(b, [defender, b.scen["ambusher"]])


static func respond(b: Battle, choice: Dictionary) -> String:
	var p := b.pending
	match p["type"]:
		"pick_entry":
			var c := int(choice.get("corner", -1))
			if c < 0 or c > 3:
				return "Pick a corner."
			var w: int = p["player"]
			b.scen["entry"][w] = c
			b.scen["entry"][b.other(w)] = (c + 2) % 4
			b.pending = {}
			b.log_line("%s takes the %s entry point; %s the opposite corner." % [b.player_names[w], ["north-west", "north-east", "south-east", "south-west"][c], b.player_names[b.other(w)]])
			if b.scen["id"] == "the_find":
				_deploy_next(b, [w, b.other(w)])
			else:
				_deploy_next(b, [w, b.other(w)])
		"pick_reserve_group":
			var g := int(choice.get("group", -1))
			if not g in p["groups"]:
				return "Pick one of the battle groups in reserve."
			b.pending = {}
			_roll_reinforcements(b, p["player"], g)
	b.changed.emit()
	return ""


# --- Deployment ---------------------------------------------------------------------------------

static func _deploy_next(b: Battle, order: Array) -> void:
	b.scen["deploy_order"] = order
	_deploy_step(b)


static func _deploy_step(b: Battle) -> void:
	var order: Array = b.scen["deploy_order"]
	if order.is_empty():
		b.pending = {}
		b.log_line("Deployment complete.")
		b.begin_round()
		return
	var p: int = order[0]
	var group := 0
	if b.scen["id"] != "street_of_death" or p == b.scen.get("ambusher", -1):
		var groups: Array = []
		for f in b.fighters:
			if f.player == p and not f.battle_group in groups:
				groups.append(f.battle_group)
		group = groups[b.dice.rng.randi_range(0, groups.size() - 1)]
	var uids: Array = []
	for f in b.fighters:
		if f.player == p and f.battle_group == group and f.where == "reserve":
			uids.append(f.uid)
	if b.scen["id"] == "the_find" and b.scen.get("twist_id", "") == "surrounded_on_all_sides" and p == b.scen["attacker"]:
		uids = []
		for f in b.fighters:
			if f.player == p:
				uids.append(f.uid)
	if b.scen["groups"] == 1:
		uids = []
		for f in b.fighters:
			if f.player == p:
				uids.append(f.uid)
	b.pending = {"type": "deploy", "player": p, "uids": uids, "zone": deploy_zone(b, p)}
	b.log_line("%s deploys battle group %d (%d fighters); the rest wait in reserve." % [b.player_names[p], group + 1, uids.size()])
	b.changed.emit()


static func deploy_zone(b: Battle, p: int) -> Dictionary:
	match b.scen["id"]:
		"street_of_death":
			if p == b.scen["defender"]:
				var west: bool = b.scen["escape_edge"] == "west"
				var r := Rect2(Vector2(18.0 if west else 0.0, 15.5), Vector2(b.board_size.x - 18.0, 5.0))
				return {"type": "rect", "rect": r}
			return {"type": "any", "min_enemy": 12.0}
		"the_find":
			if p == b.scen["defender"]:
				return {"type": "rect", "rect": Rect2(center(b) - Vector2(7, 7), Vector2(14, 14))}
			if b.scen.get("twist_id", "") == "surrounded_on_all_sides":
				return {"type": "edges", "edges": [0, 1, 2, 3], "depth": 6.0, "min_enemy": 0.0}
	return {"type": "corner", "corner": b.scen["entry"][p], "radius": b.scen["deploy_radius"]}


## "" if fighter f may be set up at pos within zone.
static func zone_ok(b: Battle, f: FighterState, pos: Vector2, zone: Dictionary) -> String:
	match zone.get("type", "any"):
		"corner":
			if not Geo.wholly_within_point(pos, f.radius, corners(b)[zone["corner"]], zone["radius"]):
				return "Must be wholly within %.0f\" of the entry point." % zone["radius"]
		"rect":
			var r: Rect2 = zone["rect"]
			if not r.grow(-f.radius + Geo.EPS).has_point(pos):
				return "Must be wholly within the deployment area."
		"circle":
			if pos.distance_to(zone["c"]) + f.radius > float(zone["r"]) + Geo.EPS:
				return "Must be within the marked area."
		"edges":
			var depth: float = zone["depth"]
			var ok := false
			for e in zone["edges"]:
				if _edge_distance(b, pos, e) + f.radius <= depth + Geo.EPS:
					ok = true
			if not ok:
				return "Must be wholly within %.0f\" of a permitted battlefield edge." % depth
	var min_enemy: float = zone.get("min_enemy", 0.0)
	for o in b.on_board(b.other(f.player)):
		if min_enemy > 0.0 and Geo.base_gap(pos, f.radius, o.pos, o.radius) <= min_enemy:
			return "Must be more than %.0f\" from all enemy fighters." % min_enemy
	return Magic._placement_ok(b, f, pos)


## edge index: 0 north (y=0), 1 east (x=W), 2 south (y=H), 3 west (x=0)
static func _edge_distance(b: Battle, pos: Vector2, e: int) -> float:
	match e:
		0:
			return pos.y
		1:
			return b.board_size.x - pos.x
		2:
			return b.board_size.y - pos.y
	return pos.x


## Edges touching a corner: corner 0 (NW) -> north & west, etc.
static func corner_edges(c: int) -> Array:
	return [[0, 3], [0, 1], [1, 2], [2, 3]][c]


## choice: {"positions": {uid: Vector2}} (any missing are auto-placed) or {"auto": true}.
static func respond_placement(b: Battle, choice: Dictionary) -> String:
	var p := b.pending
	var uids: Array = p["uids"]
	var positions: Dictionary = choice.get("positions", {})
	var zone: Dictionary = p["zone"]
	for uid in uids:
		var f := b.fighter(uid)
		if positions.has(uid):
			var err := zone_ok(b, f, positions[uid], zone)
			if err != "":
				return "%s: %s" % [f.name, err]
			f.pos = positions[uid]
			f.where = "board"
		else:
			var spot := auto_spot(b, f, zone)
			if spot == Vector2.INF:
				return "No room to place %s; place fighters by hand." % f.name
			f.pos = spot
			f.where = "board"
	b.pending = {}
	if p["type"] == "deploy":
		(b.scen["deploy_order"] as Array).pop_front()
		_deploy_step(b)
	else:
		for uid in uids:
			b.log_line("%s arrives on the battlefield." % b.fighter(uid).name)
		if not _continue_arrivals(b):
			_reinforce_step(b)
	b.changed.emit()
	return ""


static func auto_spot(b: Battle, f: FighterState, zone: Dictionary) -> Vector2:
	var cands: Array = []
	var step := 0.75
	var x := f.radius
	while x <= b.board_size.x - f.radius:
		var y := f.radius
		while y <= b.board_size.y - f.radius:
			cands.append(Vector2(x, y))
			y += step
		x += step
	var anchor := center(b)
	match zone.get("type", ""):
		"corner":
			anchor = corners(b)[zone["corner"]]
		"rect":
			anchor = (zone["rect"] as Rect2).get_center()
		"circle":
			anchor = zone["c"]
	cands.sort_custom(func(a, c): return a.distance_to(anchor) < c.distance_to(anchor))
	for c in cands:
		if zone_ok(b, f, c, zone) == "":
			return c
	return Vector2.INF


static func find_spot(b: Battle, f: FighterState, near: Vector2, radius: float) -> Vector2:
	return auto_spot(b, f, {"type": "circle", "c": near, "r": radius + f.radius})


# --- Start of round: twists and reinforcements (p.36) -------------------------------------------

static func start_of_round(b: Battle) -> void:
	var tw: String = b.scen.get("twist_id", "")
	if tw == "a_brewing_storm" and b.round_no > 1 and not b.scen.get("rain", false):
		var r := b.dice.d6()
		if r >= 5:
			b.scen["rain"] = true
			b.scen["visibility_limit"] = 12.0
			b.log_line("The storm breaks (rolled %d): visibility 12\", -1 to misfire rolls." % r)
		else:
			b.log_line("The rain holds off (rolled %d)." % r)
	if tw == "heavy_downpour" and b.round_no >= 2 and b.scen.get("rain", false):
		var r2 := b.dice.d6()
		if r2 < b.round_no:
			b.scen["rain"] = false
			b.scen.erase("visibility_limit")
			b.log_line("The downpour ends (rolled %d)." % r2)
	b.scen.erase("black_mire")
	# Rise Again (Undying Lords): on a 6 the fighter returns near where it fell, healing d3.
	for f in b.fighters:
		if f.where == "down" and f.has_rule("rise_again") and not "rise_again" in f.once_per_battle and f.statuses.has("rise_again_marker"):
			var r := b.dice.d6()
			if r == 6:
				var spot := find_spot(b, f, f.statuses["rise_again_marker"], 4.0)
				if spot != Vector2.INF:
					f.once_per_battle.append("rise_again")
					f.where = "board"
					f.pos = spot
					f.life = b.dice.d3()
					b.log_line("%s rises again with %d life!" % [f.name, f.life])
	b.scen["sor_queue"] = [b.priority, b.other(b.priority)]
	_reinforce_step(b)


static func _reserve_groups(b: Battle, p: int) -> Array:
	var groups: Array = []
	for f in b.fighters:
		if f.player == p and f.where == "reserve" and not f.battle_group in groups:
			groups.append(f.battle_group)
	return groups


static func _reinforce_step(b: Battle) -> void:
	var q: Array = b.scen.get("sor_queue", [])
	while not q.is_empty():
		var p: int = q.pop_front()
		var rr: int = b.scen["reinforce_round"][p]
		if b.scen.get("twist_id", "") == "tip_off" and p == b.scen.get("defender", -1):
			rr = 3
		if b.round_no < rr:
			continue
		var groups := _reserve_groups(b, p)
		if groups.is_empty():
			continue
		if groups.size() == 1:
			_roll_reinforcements(b, p, groups[0])
		else:
			b.pending = {"type": "pick_reserve_group", "player": p, "groups": groups}
			b.changed.emit()
		return
	b.pending = {}
	b._begin_activations()


static func _roll_reinforcements(b: Battle, p: int, group: int) -> void:
	var arriving: Array = []
	var text: PackedStringArray = []
	var street: bool = b.scen["id"] == "street_of_death"
	for f in b.fighters:
		if f.player != p or f.where != "reserve" or f.battle_group != group:
			continue
		var r := b.dice.d6()
		if street:
			arriving.append({"uid": f.uid, "zone": {"type": "edges", "edges": [_street_edge(b, r)], "depth": 6.0, "min_enemy": 6.0}})
			text.append("%s %d" % [f.name, r])
			continue
		if r <= 2:
			text.append("%s %d (not yet)" % [f.name, r])
			continue
		text.append("%s %d (%s)" % [f.name, r, "outflank" if r == 6 else "arrival"])
		if r == 6:
			arriving.append({"uid": f.uid, "zone": {"type": "edges", "edges": [0, 1, 2, 3], "depth": 3.0, "min_enemy": 6.0}})
		else:
			arriving.append({"uid": f.uid, "zone": {"type": "edges", "edges": corner_edges(b.scen["entry"][p]), "depth": 3.0, "min_enemy": 6.0}})
	b.log_line("%s's reinforcements (group %d): %s." % [b.player_names[p], group + 1, ", ".join(text)])
	_place_arrivals(b, p, arriving)


static func _street_edge(b: Battle, r: int) -> int:
	# Map (p.45): one roll per fighter picks an edge. 1 = the far end of the street, 6 = the escape end,
	# 2-3 and 4-5 = the long sides (exact assignment is a ruling; the map is schematic).
	var escape_e: int = 1 if b.scen.get("escape_edge", "east") == "east" else 3
	var far_e: int = 3 if escape_e == 1 else 1
	if r == 1:
		return far_e
	if r == 6:
		return escape_e
	return 0 if r <= 3 else 2


static func _place_arrivals(b: Battle, p: int, arriving: Array) -> void:
	if arriving.is_empty():
		_reinforce_step(b)
		return
	# Each arriving fighter is placed one at a time so zones can differ per fighter.
	var first: Dictionary = arriving.pop_front()
	b.scen["arrivals"] = arriving
	b.pending = {"type": "place", "player": p, "uids": [first["uid"]], "zone": first["zone"]}
	b.scen["arrivals_player"] = p
	b.changed.emit()


## Overrides _reinforce_step continuation for queued arrivals.
static func _continue_arrivals(b: Battle) -> bool:
	var arrivals: Array = b.scen.get("arrivals", [])
	if arrivals.is_empty():
		return false
	var nxt: Dictionary = arrivals.pop_front()
	b.pending = {"type": "place", "player": b.scen["arrivals_player"], "uids": [nxt["uid"]], "zone": nxt["zone"]}
	b.changed.emit()
	return true


# --- Activation hooks ---------------------------------------------------------------------------

static func start_of_activation(b: Battle, f: FighterState) -> void:
	Magic.start_of_activation(b, f)


static func end_of_activation(b: Battle, f: FighterState) -> void:
	var tw: String = b.scen.get("twist_id", "")
	if tw == "cursed_coin" and f.treasure > 0 and not (f.has_kw("Demon") or f.has_kw("Undead")):
		var t := b.dice.test(int(f.stats["willpower"]))
		if not t["pass"]:
			var d := b.dice.d3()
			b.log_line("The cursed coin burns %s (rolled %d): %d damage." % [f.name, t["roll"], d])
			f.statuses["cursed_coin_damage"] = true
			Combat.apply_damage(b, f, d, null, "Cursed Coin")
			f.statuses["damaged_this_activation"] = false  # no drop test for this damage
	if tw == "saints_statue" and f.on_board() and f.pos.distance_to(center(b)) - f.radius <= 6.0 and not (f.has_kw("Demon") or f.has_kw("Undead")):
		b.heal(f, b.dice.d3(), "Saint's Statue")
	if b.scen["id"] == "the_chapel" and b.scen.get("grass_sprouts", false) and in_chapel(b, f.pos):
		if f.has_kw("Demon") or f.has_kw("Undead"):
			Combat.apply_damage(b, f, 1, null, "consecrated grass")
		else:
			b.heal(f, 1, "the Saint's grass")


static func after_move(b: Battle, f: FighterState) -> void:
	if not f.on_board():
		return
	var edge_near := false
	for e in 4:
		if _edge_distance(b, f.pos, e) - f.radius <= 1.0 + Geo.EPS:
			edge_near = true
	var engaged := Effects.is_engaged(b, f)
	if f.treasure > 0 and edge_near and not engaged:
		f.where = "escaped"
		f.treasure = 0
		b.scen["escaped"][f.player] += 1
		b.log_line("%s escapes the battlefield with treasure! (%d escaped)" % [f.name, b.scen["escaped"][f.player]])
		if b.scen["id"] in ["glimmers_in_the_dark", "the_find"] and b.scen["escaped"][f.player] >= 3:
			b.end_battle(f.player, "%s has 3 fighters escape with treasure." % b.player_names[f.player])
			return
		if b.active == f.uid:
			b.end_activation()
		return
	if b.scen["id"] == "street_of_death" and "hit" in f.marks and not engaged:
		var escape_e: int = 1 if b.scen["escape_edge"] == "east" else 3
		if _edge_distance(b, f.pos, escape_e) - f.radius <= 1.0 + Geo.EPS:
			b.end_battle(f.player, "%s, the Hit, escapes the ambush." % f.name)
	if b.scen.get("twist_id", "") == "false_riches":
		for i in range(b.tokens.size() - 1, -1, -1):
			var t: Dictionary = b.tokens[i]
			if t["type"] == "treasure" and not t.get("checked", false) and Geo.within(f.pos, f.radius, t["pos"], 0.5, 3.0):
				t["checked"] = true
				var r := b.dice.d6()
				if r <= 2:
					b.tokens.remove_at(i)
					b.log_line("The treasure near %s is worthless (rolled %d) and removed." % [f.name, r])


# --- Treasure ------------------------------------------------------------------------------------

static func can_pick_up(b: Battle, f: FighterState) -> bool:
	if b.scen.get("id", "") == "the_find" and f.player == b.scen.get("defender", -1) and b.round_no < 3:
		return b.scen.get("twist_id", "") == "surrounded_on_all_sides"
	return true


static func pick_up(b: Battle, f: FighterState, index: int) -> void:
	b.tokens.remove_at(index)
	f.treasure = 1
	b.log_line("%s picks up treasure." % f.name)


static func drop_treasure(b: Battle, f: FighterState) -> void:
	if f.treasure <= 0:
		return
	f.treasure = 0
	var spot := f.pos + Vector2.from_angle(b.dice.rng.randf() * TAU) * (f.radius + 0.5)
	spot.x = clampf(spot.x, 0.5, b.board_size.x - 0.5)
	spot.y = clampf(spot.y, 0.5, b.board_size.y - 0.5)
	b.tokens.append({"type": "treasure", "pos": spot})
	b.log_line("Treasure is dropped next to %s." % f.name)


static func _place_treasure(b: Battle) -> void:
	var c := center(b)
	var tw: String = b.scen["twist_id"]
	var pts: Array = []
	match b.scen["id"]:
		"glimmers_in_the_dark":
			if tw == "upturned_wagon":
				for i in 6:
					pts.append(c + Vector2.from_angle(TAU * i / 6.0) * 2.2)
			else:
				var n := 5 if tw == "false_riches" else 3
				pts.append(c + b.dice.direction() * b.dice.rng.randf_range(0.0, 2.5))
				var tries := 0
				while pts.size() < n and tries < 500:
					tries += 1
					var p: Vector2 = c + b.dice.direction() * b.dice.rng.randf_range(3.0, 7.5)
					var ok := true
					for q in pts:
						if (q as Vector2).distance_to(p) <= 3.0:
							ok = false
					if ok and _token_spot_clear(b, p):
						pts.append(p)
		"the_chapel":
			var half := Vector2(6, 8)
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(c + (half - Vector2(1.6, 1.6)) * s)
			if tw == "a_hidden_trove":
				pts.append(c)
			else:
				pts.resize(3)
		"the_find":
			var n2 := 8 if tw == "old_debt_collectors_house" else 5
			for i in n2:
				pts.append(c + Vector2.from_angle(TAU * i / n2) * (1.2 if i % 2 == 0 else 2.4))
	for p in pts:
		b.tokens.append({"type": "treasure", "pos": p})
	if not pts.is_empty():
		b.log_line("%d treasure token(s) placed." % pts.size())


static func _token_spot_clear(b: Battle, p: Vector2) -> bool:
	for t in b.terrain:
		if t.blocks_movement() and Geo.base_overlaps_polygon(p, 0.6, t.polygon):
			return false
	return true


static func on_flee(b: Battle, p: int) -> void:
	for f in b.on_board(p):
		if f.treasure > 0:
			if b.dice.d6() == 1:
				drop_treasure(b, f)
			else:
				b.log_line("%s escapes with the treasure as the warband flees." % f.name)


# --- Victory ---------------------------------------------------------------------------------

static func on_taken_down(b: Battle, f: FighterState, by: FighterState) -> void:
	var opp := b.other(f.player)
	match b.scen.get("id", ""):
		"a_deadly_encounter":
			b.scen["vp"][opp] += 1
			b.log_line("%s scores 1 victory point (Death Marks): %d VP." % [b.player_names[opp], b.scen["vp"][opp]])
		"the_chapel":
			b.scen["marks"][opp] += 1
			b.log_line("%s scores a death mark: %d." % [b.player_names[opp], b.scen["marks"][opp]])
			if b.scen["twist_id"] == "desecrated_ground" and not b.scen.get("desecrated_triggered", false) and in_chapel(b, f.pos):
				b.scen["desecrated_triggered"] = true
				var r := b.dice.d6()
				var txt: String = ["", "Light Rain", "Light Rain", "Heavy Rain", "Grass Sprouts", "Blood Frenzy", "Thunder Claps"][r]
				b.log_line("Desecrated Ground (%d): %s." % [r, txt])
				if r == 3:
					b.scen["rain"] = true
					b.scen["visibility_limit"] = 12.0
				elif r == 4:
					b.scen["grass_sprouts"] = true
				elif r == 5:
					b.scen["blood_frenzy"] = true
		"street_of_death":
			if "hit" in f.marks:
				b.end_battle(b.scen["ambusher"], "%s, the Hit, has been taken down." % f.name)


static func must_take_flee_test(b: Battle, p: int) -> bool:
	if b.scen.get("id", "") == "street_of_death" and p == b.scen.get("defender", -1):
		return false
	if b.scen.get("twist_id", "") == "defiant_stand" and p == b.scen.get("defender", -1):
		return false
	if b.scen.get("twist_id", "") == "battle_for_the_tower":
		for f in b.on_board(p):
			if (f.has_kw("Leader") or f.has_kw("Champion")) and Geo.wholly_within_point(f.pos, f.radius, center(b), 6.0):
				b.log_line("%s holds the tower: Flee test passed automatically." % b.player_names[p])
				return false
	return true


static func end_of_round(b: Battle) -> void:
	match b.scen.get("id", ""):
		"a_deadly_encounter":
			var holders := _holders_near_centre(b, 6.0)
			if holders.size() == 1:
				var p: int = holders[0]
				var pts := 3 if b.scen["twist_id"] == "battle_for_the_tower" else b.dice.d3()
				b.scen["vp"][p] += pts
				b.log_line("%s holds the centre: +%d VP (%d)." % [b.player_names[p], pts, b.scen["vp"][p]])
			var vp: Array = b.scen["vp"]
			if (vp[0] >= 8 or vp[1] >= 8) and vp[0] != vp[1]:
				var w := 0 if vp[0] > vp[1] else 1
				b.end_battle(w, "Victory points %d to %d." % [vp[w], vp[1 - w]])
		"no_quarter":
			if b.round_no >= 3:
				_score_quarters(b)
				var m: Array = b.scen["marks"]
				if (m[0] >= 10 or m[1] >= 10) and m[0] != m[1]:
					var w2 := 0 if m[0] > m[1] else 1
					b.end_battle(w2, "Domination marks %d to %d." % [m[w2], m[1 - w2]])
		"the_chapel":
			var dm: Array = b.scen["marks"]
			if (dm[0] >= 8 or dm[1] >= 8) and dm[0] != dm[1]:
				var w3 := 0 if dm[0] > dm[1] else 1
				b.end_battle(w3, "Death marks %d to %d." % [dm[w3], dm[1 - w3]])


static func _holders_near_centre(b: Battle, r: float) -> Array:
	var present := [false, false]
	for f in b.on_board():
		if f.pos.distance_to(center(b)) - f.radius <= r + Geo.EPS:
			present[f.player] = true
	if present[0] and not present[1]:
		return [0]
	if present[1] and not present[0]:
		return [1]
	return []


static func quarter_of(b: Battle, f: FighterState) -> int:
	var c := center(b)
	if Geo.wholly_within_point(f.pos, f.radius, c, 6.0):
		return -1
	var minp := f.pos - Vector2(f.radius, f.radius)
	var maxp := f.pos + Vector2(f.radius, f.radius)
	if maxp.x <= c.x and maxp.y <= c.y:
		return 0
	if minp.x >= c.x and maxp.y <= c.y:
		return 1
	if minp.x >= c.x and minp.y >= c.y:
		return 2
	if maxp.x <= c.x and minp.y >= c.y:
		return 3
	return -1


static func _score_quarters(b: Battle) -> void:
	for q in 4:
		var n := [0, 0]
		for f in b.on_board():
			if quarter_of(b, f) == q:
				n[f.player] += 1
		for p in 2:
			if n[p] > n[1 - p]:
				var pts := 1
				if b.scen["twist_id"] == "turf_war" and q == b.scen["entry"][1 - p]:
					pts = 3
				b.scen["marks"][p] += pts
				b.log_line("%s controls quarter %d: +%d domination (%d)." % [b.player_names[p], q + 1, pts, b.scen["marks"][p]])


static func in_chapel(b: Battle, pos: Vector2) -> bool:
	return Rect2(center(b) - Vector2(6, 8), Vector2(12, 16)).has_point(pos)


# =============================================================================================
# Terrain generation: a ruined district laid out per scenario.

static func generate_terrain(b: Battle) -> void:
	b.terrain = []
	var c := center(b)
	var keep_clear: Array = []   # Rect2 areas that must stay open
	var id: String = b.scen["id"]
	for corner in corners(b):
		keep_clear.append(Rect2(corner - Vector2(4.5, 4.5), Vector2(9, 9)))
	match id:
		"a_deadly_encounter", "glimmers_in_the_dark":
			keep_clear.append(Rect2(c - Vector2(3, 3), Vector2(6, 6)))
			if b.scen["twist_id"] == "battle_for_the_tower":
				b.terrain.append(TerrainPiece.make("Tower", "high", Geo.rect_polygon(c, Vector2(3, 3)), 8.0))
		"no_quarter":
			keep_clear.append(Rect2(Vector2(c.x - 2.5, 0), Vector2(5, b.board_size.y)))
			keep_clear.append(Rect2(Vector2(0, c.y - 2.5), Vector2(b.board_size.x, 5)))
			if b.scen["twist_id"] == "saints_statue":
				b.terrain.append(TerrainPiece.make("Saint's Statue", "impassable", Geo.circle_polygon(c, 1.0, 12), 4.0))
		"the_chapel":
			var r := Rect2(c - Vector2(6, 8), Vector2(12, 16))
			keep_clear.append(r.grow(1.5))
			_corner_ruins(b, r, "Chapel ruin")
			if b.scen["twist_id"] == "the_saints_sarcophagus":
				b.terrain.append(TerrainPiece.make("Sarcophagus", "impassable", Geo.rect_polygon(c, Vector2(1.2, 2.2)), 1.2))
		"street_of_death":
			keep_clear.append(Rect2(Vector2(0, 15.5), Vector2(b.board_size.x, 5)))
		"the_find":
			var hr := Rect2(c - Vector2(4, 4), Vector2(8, 8))
			keep_clear.append(hr.grow(1.5))
			_corner_ruins(b, hr, "Holding ruin", 2.5)
	var dense := 14 if id == "street_of_death" else 10
	var attempts := 0
	var placed := 0
	while placed < dense and attempts < 400:
		attempts += 1
		var kind_roll := b.dice.d6()
		var pos := Vector2(b.dice.rng.randf_range(3, b.board_size.x - 3), b.dice.rng.randf_range(3, b.board_size.y - 3))
		var ang := float(b.dice.rng.randi_range(0, 3)) * PI / 2.0
		var pieces: Array = []
		if kind_roll <= 3:
			pieces = _ruin(b, pos, ang)
		elif kind_roll == 4:
			pieces = [TerrainPiece.make("Ruined house", "high", Geo.rect_polygon(pos, Vector2(b.dice.rng.randf_range(3.5, 5.0), b.dice.rng.randf_range(3.5, 5.0)), ang), b.dice.rng.randf_range(4.0, 6.0))]
		elif kind_roll == 5:
			pieces = [TerrainPiece.make("Low wall", "low", Geo.rect_polygon(pos, Vector2(b.dice.rng.randf_range(3.0, 5.0), 0.4), ang), 1.0)]
		else:
			pieces = [TerrainPiece.make("Rubble", "low", _blob(b, pos, b.dice.rng.randf_range(1.2, 2.0)), 0.6)]
		if _fits(b, pieces, keep_clear):
			b.terrain.append_array(pieces)
			placed += 1
	# A few extra low walls give cover in open ground.
	attempts = 0
	var extras := 0
	while extras < 4 and attempts < 200:
		attempts += 1
		var pos2 := Vector2(b.dice.rng.randf_range(4, b.board_size.x - 4), b.dice.rng.randf_range(4, b.board_size.y - 4))
		var piece := TerrainPiece.make("Low wall", "low", Geo.rect_polygon(pos2, Vector2(3.0, 0.4), float(b.dice.rng.randi_range(0, 3)) * PI / 2.0), 1.0)
		if _fits(b, [piece], keep_clear if id != "street_of_death" else keep_clear.slice(0, 4)):
			b.terrain.append(piece)
			extras += 1


static func _ruin(b: Battle, pos: Vector2, ang: float) -> Array:
	var a := b.dice.rng.randf_range(3.5, 6.0)
	var l := b.dice.rng.randf_range(3.0, 5.0)
	var h := b.dice.rng.randf_range(2.5, 5.0)
	var t := 0.5
	var w1 := Geo.rect_polygon(pos + Vector2(a / 2.0, 0).rotated(ang), Vector2(a, t), ang)
	var w2 := Geo.rect_polygon(pos + Vector2(0, l / 2.0).rotated(ang), Vector2(t, l), ang)
	var rub := _blob(b, pos + Vector2(a * 0.5, l * 0.45).rotated(ang), 0.9)
	return [TerrainPiece.make("Ruined wall", "high", w1, h), TerrainPiece.make("Ruined wall", "high", w2, h * 0.8), TerrainPiece.make("Rubble", "low", rub, 0.5)]


static func _corner_ruins(b: Battle, r: Rect2, nm: String, arm := 3.5) -> void:
	var cs := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for i in 4:
		var c: Vector2 = cs[i]
		var d: Vector2 = dirs[i]
		b.terrain.append(TerrainPiece.make(nm, "high", Geo.rect_polygon(c + Vector2(d.x * arm / 2.0, 0), Vector2(arm, 0.5)), 4.0))
		b.terrain.append(TerrainPiece.make(nm, "high", Geo.rect_polygon(c + Vector2(0, d.y * arm / 2.0), Vector2(0.5, arm)), 4.0))


static func _blob(b: Battle, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(c + Vector2.from_angle(TAU * i / 8.0) * r * b.dice.rng.randf_range(0.7, 1.1))
	return pts


static func _fits(b: Battle, pieces: Array, keep_clear: Array) -> bool:
	for p in pieces:
		var bounds := _bounds(p.polygon)
		if bounds.position.x < 1.0 or bounds.position.y < 1.0 or bounds.end.x > b.board_size.x - 1.0 or bounds.end.y > b.board_size.y - 1.0:
			return false
		for k in keep_clear:
			if (k as Rect2).intersects(bounds):
				return false
		for t in b.terrain:
			if _bounds(t.polygon).grow(2.2).intersects(bounds):
				return false
	return true


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r
