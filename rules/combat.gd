class_name Combat
extends RefCounted
## Attacks: ranged (p.28), templates (pp.31-32), resolving hits (p.24) and the melee duel (pp.23-26).

const BLAST_RADIUS := 1.5


# =============================================================================================
# Damage

static func apply_damage(b: Battle, f: FighterState, amount: int, source: FighterState, why := "") -> void:
	if amount <= 0 or not f.on_board():
		return
	var sw := f.effect("swollen")
	if not sw.is_empty() and int(sw["left"]) > 0:
		var absorbed := mini(int(sw["left"]), amount)
		sw["left"] = int(sw["left"]) - absorbed
		amount -= absorbed
		b.log_line("%s's Swollen Form absorbs %d damage." % [f.name, absorbed])
		if amount <= 0:
			return
	f.life -= amount
	f.statuses["damaged_this_activation"] = true
	f.statuses["damaged_ever"] = true
	if f.elev > Height.LEVEL_EPS:
		f.statuses["fall_check"] = true
	if f.life <= 0:
		f.life = 0
		take_down(b, f, source, why)
	elif f.life == 1 and f.statuses.get("poisoned", false):
		f.statuses.erase("poisoned")
		b.log_line("%s is no longer poisoned (1 life remaining)." % f.name)


static func take_down(b: Battle, f: FighterState, by: FighterState, why := "") -> void:
	if not f.on_board():
		return
	var engaged := Effects.engaged_enemies(b, f)
	f.where = "down"
	f.life = 0
	f.statuses.clear()
	b.log_line("☠ %s is taken down%s." % [f.name, (" by %s" % by.name) if by != null else (" (%s)" % why if why != "" else "")])
	if f.treasure > 0:
		Scenario.drop_treasure(b, f)
	if f.has_rule("drag_down_into_the_earth") and not engaged.is_empty():
		var victim: FighterState = engaged[0]
		var d := b.dice.d3()
		b.log_line("%s drags %s down into the earth: %d damage." % [f.name, victim.name, d])
		apply_damage(b, victim, d, f, "Drag Down Into the Earth")
	if f.has_rule("vessel_of_black_rot"):
		for o in b.on_board(b.other(f.player)):
			if Effects.near(f, o, 6.0) and o.can_be_poisoned() and b.dice.d6() >= 4:
				o.statuses["poisoned"] = true
				b.log_line("%s is poisoned by the Vessel of Black Rot." % o.name)
	for o in b.on_board():
		if o.has_rule("last_rites") and Effects.near(f, o, 6.0):
			b.heal(o, 1, "Last Rites")
	if f.has_rule("rise_again") and not "rise_again" in f.once_per_battle:
		f.statuses["rise_again_marker"] = f.pos
	Scenario.on_taken_down(b, f, by)


# =============================================================================================
# Resolving a hit (p.24)

## profile: {"name", "rend", "damage", "crit", "traits", "kind"}. ctx: {"melee": bool, "cover": bool,
## "defending_vs_charge": bool, "rend": int (already modified)}. Returns damage dealt.
static func resolve_hit(b: Battle, att: FighterState, tgt: FighterState, profile: Dictionary, crit: bool, ctx := {}) -> int:
	if not tgt.on_board():
		return 0
	var label: String = profile.get("name", "attack")
	if crit and tgt.has_rule("blessed_by_the_saints") and tgt.statuses.get("blessed_round", -1) != b.round_no:
		tgt.statuses["blessed_round"] = b.round_no
		crit = false
		b.log_line("Blessed by the Saints: the critical hit on %s becomes a normal hit." % tgt.name)
	var actx := ctx.duplicate()
	actx["attacker"] = att
	var armour := Effects.armour_value(b, tgt, actx)
	var rend: int = ctx.get("rend", int(profile.get("rend", 0)))
	if Effects.ignores_rend(tgt):
		rend = 0
	var needed := armour - rend
	var saved := false
	var text := "%s hits %s%s with %s" % [att.name if att != null else "The attack", tgt.name, " (CRIT)" if crit else "", label]
	if armour >= 7 or needed > 6:
		text += ": no armour roll possible"
	else:
		var r := b.dice.d6()
		saved = r >= needed
		if saved and tgt.has_effect("doomed"):
			tgt.remove_effect("doomed")
			var r2 := b.dice.d6()
			text += ": armour %d+, rolled %d but DOOMED — re-rolled %d" % [armour, r, r2]
			r = r2
			saved = r >= needed
			text += " — %s" % ("SAVED" if saved else "not saved")
		else:
			text += ": armour %d+%s, rolled %d — %s" % [armour, (" vs Rend %d (needs %d+)" % [rend, needed]) if rend != 0 else "", r, "SAVED" if saved else "not saved"]
	var dealt := 0
	if saved:
		if crit and _profile_has(att, profile, "Bludgeon"):
			text += "; Bludgeon still deals 1"
			b.log_line(text + ".")
			apply_damage(b, tgt, 1, att, label)
			dealt = 1
		else:
			b.log_line(text + ".")
		if ctx.get("melee", false) and tgt.has_effect("spirit_guardian") and att != null and att.on_board():
			b.log_line("The Spirit Guardian lashes back at %s." % att.name)
			apply_damage(b, att, 1, tgt, "Spirit Guardian")
		return dealt
	var expr: String
	if att != null and profile.get("kind", "") in ["melee", "ranged"]:
		expr = Effects.damage_expr(b, att, profile, crit, tgt)
	else:
		expr = str(profile.get("crit") if crit and profile.get("crit") != null else profile.get("damage", "1"))
		if tgt.has_rule("the_black_benediction"):
			expr = Dice.add(expr, -1)
	dealt = maxi(1, b.dice.roll(expr)) if tgt.has_rule("the_black_benediction") else b.dice.roll(expr)
	b.log_line(text + "; %d damage (%s)." % [dealt, expr])
	apply_damage(b, tgt, dealt, att, label)
	if crit and dealt > 0 and _profile_has(att, profile, "Poison") and tgt.on_board() and tgt.can_be_poisoned() and tgt.life > 1:
		tgt.statuses["poisoned"] = true
		b.log_line("%s is poisoned." % tgt.name)
	if dealt > 0 and ctx.get("melee", false) and att != null and att.has_rule("vampyric_bite") and att.on_board():
		b.heal(att, 1, "Vampyric Bite")
	return dealt


static func _profile_has(att: FighterState, profile: Dictionary, trait_name: String) -> bool:
	if att != null and profile.get("kind", "") in ["melee", "ranged"]:
		return Effects.weapon_has(att, profile, trait_name)
	for t in profile.get("traits", []):
		if (t as String).begins_with(trait_name):
			return true
	return false


# =============================================================================================
# Ranged attacks (p.28)

## Eligible targets for a ranged weapon, closest first: [{"uid", "gap", "obscured", "legal", "reason"}].
static func ranged_targets(b: Battle, f: FighterState, w: Dictionary) -> Array:
	var out: Array = []
	var rng := Effects.range_for(b, f, w)
	var engaged := Effects.engaged_enemies(b, f)
	var point_blank := not engaged.is_empty()
	for o in b.on_board(b.other(f.player)):
		var gap := Effects.dist(f, o)
		var vis := Effects.visibility(b, f, o)
		var e := {"uid": o.uid, "gap": gap, "obscured": vis["obscured"], "visible": vis["visible"], "legal": false, "reason": ""}
		if point_blank:
			if o in engaged:
				e["legal"] = true
				e["reason"] = "Point Blank Shot"
			else:
				e["reason"] = "engaged: only fighters in melee with it"
		elif not vis["visible"]:
			e["reason"] = "not visible"
		elif gap > rng + Geo.EPS:
			e["reason"] = "out of range (%.1f\" > %.0f\")" % [gap, rng]
		elif Effects.is_engaged(b, o):
			e["reason"] = "engaged in melee"
		else:
			e["legal"] = true
		out.append(e)
	out.sort_custom(func(a, c): return a["gap"] < c["gap"])
	if point_blank:
		return out
	# Closest-target rule: the closest eligible enemy, or the closest non-obscured one if the closest is obscured.
	var first_seen := false
	var clear_seen := false
	for e in out:
		if not e["legal"]:
			continue
		if not first_seen:
			first_seen = true
			if not e["obscured"]:
				clear_seen = true
			continue
		if not clear_seen and not e["obscured"]:
			clear_seen = true
			continue
		e["legal"] = false
		e["reason"] = "not the closest eligible target"
	return out


static func check_can_shoot(b: Battle, f: FighterState, w: Dictionary) -> String:
	if f == null or f.uid != b.active:
		return "No fighter is activating."
	if not b.can_still_act(f):
		return "%s can't make an action now." % f.name
	if f.stats["bow"] == null:
		return "%s can't make ranged attacks." % f.name
	if w.is_empty() or w["id"] in f.lost_weapons:
		return "That weapon can't be used."
	if w["id"] in f.needs_reload:
		return "%s must be reloaded first." % w["name"]
	if "One-use" in w.get("traits", []) or w.get("from_item", false):
		if ("used:" + w["id"]) in f.once_per_battle:
			return "%s has already been used this battle." % w["name"]
	if Effects.weapon_has(f, w, "Heavy") and f.moved:
		return "Heavy weapons can't be used after moving."
	if Effects.is_engaged(b, f):
		if not f.has_rule("point_blank_shot"):
			return "Engaged fighters can't make ranged attacks."
		if Effects.weapon_has(f, w, "Heavy"):
			return "Point Blank Shot can't use Heavy weapons."
	return ""


static func _after_firing(b: Battle, f: FighterState, w: Dictionary) -> void:
	f.acted = true
	b.mark_dice_rolled()
	if Effects.weapon_has(f, w, "Reload"):
		f.needs_reload.append(w["id"])
	if "One-use" in w.get("traits", []) or w.get("from_item", false):
		f.once_per_battle.append("used:" + w["id"])
	if Effects.weapon_has(f, w, "Heavy"):
		f.add_effect({"id": "heavy_fired", "until": "round"})


static func _point_blank_gate(b: Battle, f: FighterState) -> bool:
	if not Effects.is_engaged(b, f):
		return true
	var t := b.dice.test(int(f.stats["initiative"]))
	b.log_line("%s tries a Point Blank Shot: rolled %d vs Initiative %d — %s." % [f.name, t["roll"], f.stats["initiative"], "success" if t["pass"] else "failed, the action ends"])
	return t["pass"]


## Ranged attack against a fighter. For Volley weapons with several attacks, a "volley" decision follows.
static func shoot(b: Battle, weapon_id: String, target_uid: int) -> String:
	var f := b.active_fighter()
	var w := f.weapon_by_id(weapon_id) if f else {}
	var err := check_can_shoot(b, f, w)
	if err != "":
		return err
	if Effects.weapon_has(f, w, "Blast") or Effects.weapon_has(f, w, "Flame"):
		return "Template weapons are aimed at a point or direction."
	var legal := false
	for e in ranged_targets(b, f, w):
		if e["uid"] == target_uid:
			legal = e["legal"]
			if not legal:
				return "Illegal target: %s." % e["reason"]
	if not legal:
		return "Illegal target."
	if not b.harried_check(f, "action"):
		return ""
	var attacks := b.dice.roll(w["attacks"])
	b.mark_dice_rolled()
	if Effects.weapon_has(f, w, "Volley") and attacks > 1:
		var t := b.fighter(target_uid)
		var cands: Array = []
		for o in b.on_board(b.other(f.player)):
			if o != t and Effects.near(t, o, 3.0) and not Effects.is_engaged(b, o) and Effects.visibility(b, f, o)["visible"]:
				cands.append(o.uid)
		if not cands.is_empty():
			b.pending = {"type": "volley", "player": f.player, "weapon": weapon_id, "primary": target_uid, "attacks": attacks, "candidates": cands}
			b.changed.emit()
			return ""
	var targets: Array = []
	for i in attacks:
		targets.append(target_uid)
	if not _point_blank_gate(b, f):
		f.acted = true
		b.changed.emit()
		return ""
	_resolve_ranged(b, f, w, targets)
	return ""


## choice: {"targets": [uid per attack]}
static func respond_volley(b: Battle, choice: Dictionary) -> String:
	var p := b.pending
	var f := b.fighter(p["uid"]) if p.has("uid") else b.active_fighter()
	var w := f.weapon_by_id(p["weapon"])
	var targets: Array = choice.get("targets", [])
	if targets.size() != int(p["attacks"]):
		targets = []
		for i in p["attacks"]:
			targets.append(p["primary"])
	for t in targets:
		if int(t) != int(p["primary"]) and not int(t) in p["candidates"]:
			return "Volley attacks must go to the target or enemies within 3\" of it."
	b.pending = {}
	_resolve_ranged(b, f, w, targets)
	return ""


static func _resolve_ranged(b: Battle, f: FighterState, w: Dictionary, targets: Array) -> void:
	_after_firing(b, f, w)
	var natural_ones := 0
	var hits: Array = []
	var rolls: PackedStringArray = []
	for tuid in targets:
		var t := b.fighter(int(tuid))
		if t == null or not t.on_board():
			continue
		var explain: Array = []
		var mod := Effects.attack_mod(b, f, w, t, true, explain)
		var nat := b.dice.d6()
		if nat == 1:
			natural_ones += 1
		var crit := nat >= Effects.crit_threshold(b, f, w, true)
		var hit := crit or (nat != 1 and nat + mod >= Effects.hit_value(f, true))
		rolls.append("%d%s" % [nat, "!" if crit else ("✓" if hit else "✗")])
		if hit:
			hits.append({"t": t, "crit": crit})
	b.log_line("%s fires %s (Bow %d+%s): %s." % [f.name, w["name"], Effects.hit_value(f, true), "" if targets.is_empty() else "", " ".join(rolls)])
	var hit_fighters: Array = []
	for h in hits:
		var t: FighterState = h["t"]
		var vis := Effects.visibility(b, f, t)
		var cover := Effects.in_cover(b, f, t, vis)
		if cover:
			b.log_line("%s is in cover (+1 Armour)." % t.name)
		resolve_hit(b, f, t, w, h["crit"], {"melee": false, "cover": cover, "rend": Effects.rend_for(b, f, w, t)})
		if not t in hit_fighters:
			hit_fighters.append(t)
	if natural_ones > 0 and Effects.weapon_has(f, w, "Misfire"):
		misfire(b, f, w)
	_scare(b, f, w, hit_fighters)
	b.after_action()
	b.changed.emit()


static func misfire(b: Battle, f: FighterState, w: Dictionary) -> void:
	var souped: bool = not f.effect("souped_up").is_empty() and f.effect("souped_up").get("weapon", "") == w["id"]
	var r := 1 if souped else b.dice.d6()
	if not souped and r <= 2 and (f.has_rule("blackpowder_specialist") or Effects._friendly_with_rule_within(b, f, "master_of_dark_science", 6.0, true)):
		var r2 := b.dice.d6()
		b.log_line("Misfire roll %d re-rolled: %d." % [r, r2])
		r = r2
	if b.scen.get("rain", false):
		r = maxi(1, r - 1)
	if r == 1:
		var d := b.dice.d3()
		b.log_line("MISFIRE — Backfire! %s explodes in %s's hands: %d damage, weapon lost." % [w["name"], f.name, d])
		f.lost_weapons.append(w["id"])
		apply_damage(b, f, d, null, "backfire")
	elif r == 2:
		b.log_line("MISFIRE — Clogged! %s can't be used again this battle." % w["name"])
		f.lost_weapons.append(w["id"])
	else:
		b.log_line("Misfire — Flash-in-the-Pan (rolled %d)." % r)


static func _scare(b: Battle, f: FighterState, w: Dictionary, hit_fighters: Array) -> void:
	if not Effects.weapon_has(f, w, "Scare"):
		return
	for t in hit_fighters:
		if t.on_board() and not Effects.is_engaged(b, t):
			var test := b.dice.test(int(t.stats["willpower"]))
			if not test["pass"]:
				b.log_line("%s is scared (rolled %d) and scatters." % [t.name, test["roll"]])
				Movement.scatter(b, t, b.dice.d6())


# --- Templates ---------------------------------------------------------------------------------

## Can a point (at height to_z) be seen from `from` (eye height from_z)? Used for template placement.
static func point_visible(b: Battle, from: Vector2, to: Vector2, ignore: Array = [], from_z := 1.5, to_z := 0.3) -> bool:
	var obs: FighterState = ignore[0] if not ignore.is_empty() else null
	var tgt: FighterState = ignore[1] if ignore.size() > 1 else null
	return not Effects.sight_blocked(b, Vector3(from.x, from.y, from_z), Vector3(to.x, to.y, to_z), obs, tgt)


## Fighters hit by a blast template centred at `c` on level `elev` (p.31), plus fighters engaged with them.
## Fighters 3" or more above or below the centre aren't hit; visibility and cover are judged from the centre.
static func blast_hits(b: Battle, c: Vector2, elev := 0.0) -> Array:
	var hit: Array = []
	for o in b.on_board():
		if absf(o.elev - elev) >= 3.0:
			continue
		if o.pos.distance_to(c) - o.radius <= BLAST_RADIUS + Geo.EPS:
			var probe := FighterState.new()
			probe.pos = c
			var vis := Effects.visibility_from_point(b, c, elev + 0.5, probe, o, true)
			if vis["visible"]:
				hit.append(o)
	return _with_engaged(b, hit)


static func blast_cover(b: Battle, c: Vector2, elev: float, t: FighterState) -> bool:
	var probe := FighterState.new()
	probe.pos = c
	return Effects.visibility_from_point(b, c, elev + 0.5, probe, t, true)["obscured"]


## Fighters hit by the flame template from fighter f pointing along dir (p.32), plus engaged fighters.
static func flame_hits(b: Battle, f: FighterState, dir: Vector2) -> Array:
	var poly := Geo.flame_polygon(f.pos + dir.normalized() * f.radius, dir, 8.0, float(b.cfg["flame_end_radius"]))
	var hit: Array = []
	for o in b.on_board():
		if o != f and absf(o.elev - f.elev) < 3.0 and Geo.base_overlaps_polygon(o.pos, o.radius, poly) and Effects.visibility_from_point(b, f.pos, Effects.eye_height(f), f, o, true)["visible"]:
			hit.append(o)
	return _with_engaged(b, hit)


static func _with_engaged(b: Battle, hit: Array) -> Array:
	var out := hit.duplicate()
	for h in hit:
		for e in Effects.engaged_enemies(b, h):
			if not e in out:
				out.append(e)
	return out


## Scatters a blast centre d6x2" (or `inches`), stopping at high terrain (p.31).
static func scatter_point(b: Battle, c: Vector2, inches: float) -> Vector2:
	var dir := b.dice.direction()
	var p := c
	var step := 0.1
	var moved := 0.0
	while moved + step <= inches:
		var nxt := p + dir * step
		var blocked := false
		for t in b.terrain:
			if t.blocks_movement() and Geometry2D.is_point_in_polygon(nxt, t.polygon):
				blocked = true
		if blocked or nxt.x < 0 or nxt.y < 0 or nxt.x > b.board_size.x or nxt.y > b.board_size.y:
			break
		p = nxt
		moved += step
	return p


static func shoot_blast(b: Battle, weapon_id: String, point: Vector2, elev := 0.0) -> String:
	var f := b.active_fighter()
	var w := f.weapon_by_id(weapon_id) if f else {}
	var err := check_can_shoot(b, f, w)
	if err != "":
		return err
	if not Effects.weapon_has(f, w, "Blast"):
		return "Not a blast weapon."
	var rng := Effects.range_for(b, f, w)
	var d3 := Vector2(f.pos.distance_to(point) - f.radius, elev - f.elev).length()
	if d3 > rng + Geo.EPS:
		return "That point is out of range (%.0f\")." % rng
	if not point_visible(b, f.pos, point, [f], Effects.eye_height(f), elev + 0.3):
		return "That point isn't visible."
	if not _point_blank_gate(b, f):
		f.acted = true
		b.changed.emit()
		return ""
	_after_firing(b, f, w)
	var nat := b.dice.d6()
	var mod := Effects.attack_mod(b, f, w, null, true)
	if nat == 1 and Effects.weapon_has(f, w, "Misfire"):
		b.log_line("%s fires %s: rolled 1 — misfire, the template is removed." % [f.name, w["name"]])
		misfire(b, f, w)
		b.changed.emit()
		return ""
	var c := point
	if nat + mod < Effects.hit_value(f, true):
		var dist := b.dice.d6() * 2
		c = scatter_point(b, point, dist)
		if elev > 0.0 and not Height.supports(b, c, elev):
			elev = Height.level_below(b, c, elev)
		b.log_line("%s fires %s: rolled %d — miss, the blast scatters %d\"." % [f.name, w["name"], nat, dist])
	else:
		b.log_line("%s fires %s: rolled %d — on target." % [f.name, w["name"], nat])
	b.scen["last_template"] = {"type": "blast", "pos": c, "elev": elev, "round": b.round_no}
	var hits := blast_hits(b, c, elev)
	for t in hits:
		resolve_hit(b, f, t, w, false, {"melee": false, "cover": blast_cover(b, c, elev, t), "rend": Effects.rend_for(b, f, w, t)})
	_scare(b, f, w, hits)
	b.after_action()
	b.changed.emit()
	return ""


static func shoot_flame(b: Battle, weapon_id: String, dir: Vector2) -> String:
	var f := b.active_fighter()
	var w := f.weapon_by_id(weapon_id) if f else {}
	var err := check_can_shoot(b, f, w)
	if err != "":
		return err
	if not Effects.weapon_has(f, w, "Flame"):
		return "Not a flame weapon."
	if dir.length() < 0.01:
		return "Pick a direction."
	if not _point_blank_gate(b, f):
		f.acted = true
		b.changed.emit()
		return ""
	_after_firing(b, f, w)
	b.scen["last_template"] = {"type": "flame", "origin": f.pos + dir.normalized() * f.radius, "dir": dir.normalized(), "round": b.round_no}
	var hits := flame_hits(b, f, dir)
	b.log_line("%s unleashes %s: %d fighter(s) caught in the flames." % [f.name, w["name"], hits.size()])
	for t in hits:
		resolve_hit(b, f, t, w, false, {"melee": false, "cover": false, "rend": Effects.rend_for(b, f, w, t)})
	_scare(b, f, w, hits)
	b.after_action()
	b.changed.emit()
	return ""


# =============================================================================================
# Other actions

## Why the active fighter can't hide right now, or "" if it can (p.27).
static func hide_problem(b: Battle, f: FighterState) -> String:
	if f == null or not b.can_still_act(f):
		return "no action left"
	if Effects.is_engaged(b, f):
		return "engaged in melee"
	if not Effects.touching_terrain(b, f):
		return "not touching terrain (move up against a wall or other terrain)"
	for o in b.on_board(b.other(f.player)):
		if Effects.near(f, o, 3.0):
			return "%s is within 3\" (%.1f\")" % [o.name, Effects.dist(f, o)]
	return ""


static func hide(b: Battle) -> String:
	var f := b.active_fighter()
	var problem := hide_problem(b, f)
	if problem != "":
		return "Can't hide: " + problem + "."
	if not b.harried_check(f, "action"):
		return ""
	f.acted = true
	f.statuses["hidden"] = true
	b.log_line("%s hides." % f.name)
	b.changed.emit()
	return ""


## Reload (p.30): forgo the Move or the Action. Shooting Drills: pass a Willpower test to forgo nothing.
static func reload_weapon(b: Battle, weapon_id: String, use: String) -> String:
	var f := b.active_fighter()
	if f == null or not weapon_id in f.needs_reload:
		return "Nothing to reload."
	if Effects.is_engaged(b, f):
		return "Can't reload while engaged."
	if f.has_rule("shooting_drills") and not "drills" in f.once_per_activation:
		f.once_per_activation.append("drills")
		var t := b.dice.test(int(f.stats["willpower"]))
		b.mark_dice_rolled()
		if t["pass"]:
			f.needs_reload.remove_at(f.needs_reload.find(weapon_id))
			b.log_line("%s reloads with Shooting Drills (rolled %d) without losing a move or action." % [f.name, t["roll"]])
			b.changed.emit()
			return ""
	if use == "move":
		if not b.can_still_move(f):
			return "No move left to forgo."
		f.moved = true
		f.move_kind = "reload"
	else:
		if not b.can_still_act(f):
			return "No action left to forgo."
		f.acted = true
	f.needs_reload.remove_at(f.needs_reload.find(weapon_id))
	b.log_line("%s reloads (forgoing their %s)." % [f.name, use])
	b.changed.emit()
	return ""


## Splat! (Rolling-Contraption) and Ram Horns (Darkcloven) trigger after a charge.
static func after_charge(b: Battle, f: FighterState) -> void:
	var enemies := Effects.engaged_enemies(b, f)
	if enemies.is_empty():
		return
	enemies.sort_custom(func(a, c): return a.pos.distance_to(f.pos) < c.pos.distance_to(f.pos))
	var t: FighterState = enemies[0]
	for rule_id in ["splat", "ram_horns"]:
		if not f.has_rule(rule_id):
			continue
		var def := Catalog.fighter_def(f.faction, f.def_id)
		for sr in def.get("special_rules", []):
			if sr["id"] == rule_id:
				var a: Dictionary = sr["attack"]
				var profile := {"name": sr["name"], "id": rule_id, "rend": a["rend"], "damage": a["damage"], "crit": null, "traits": [], "kind": "special"}
				var rend: int = a["rend"] - (1 if rule_id == "splat" and f.has_item("wheel_spikes") else 0)
				b.mark_dice_rolled()
				b.log_line("%s: %d hits on %s." % [sr["name"], a["count"], t.name])
				for i in int(a["count"]):
					resolve_hit(b, f, t, profile, false, {"melee": true, "rend": rend})


# =============================================================================================
# Melee duel (pp.23-26)

static func melee_targets(b: Battle, f: FighterState) -> Array:
	return Effects.engaged_enemies(b, f)


## Starts a melee attack action. opts: {"weapons": [main_id, offhand_id?], "net": bool, "mesmeric": bool}
static func start_melee(b: Battle, target_uid: int, opts: Dictionary) -> String:
	var f := b.active_fighter()
	if f == null:
		return "No fighter is activating."
	if not b.can_still_act(f):
		return "%s can't make an action now." % f.name
	var t := b.fighter(target_uid)
	if t == null or not t in Effects.engaged_enemies(b, f):
		return "The target must be an enemy engaged with %s." % f.name
	if opts.get("weapons", []).is_empty():
		var dw := default_weapons(f)
		opts["weapons"] = weapon_ids(f, dw[0], dw[1])
	var err := _check_weapons(f, opts.get("weapons", []))
	if err != "":
		return err
	if not b.harried_check(f, "action"):
		return ""
	f.acted = true
	b.mark_dice_rolled()
	b.duel = {"att": f.uid, "def": t.uid, "att_w": opts.get("weapons", [f.melee[0]["id"]]), "att_opts": opts,
		"def_w": [], "rolls": {}, "turn": -1, "guard_used": [], "feint_used": false}
	b.log_line("%s makes a melee attack against %s." % [f.name, t.name])
	b.pending = {"type": "melee_weapons", "player": t.player, "uid": t.uid}
	b.changed.emit()
	return ""


## Rough damage value of one attack with a weapon (used to suggest which weapon goes in which hand).
static func attack_value(w: Dictionary) -> float:
	var crit = w.get("crit")
	var v := Dice.average(str(w.get("damage", "1"))) + 0.35 * (Dice.average(str(crit)) if crit != null else 0.0) - 0.3 * int(w.get("rend", 0))
	if "Unwieldy" in w.get("traits", []):
		v *= 0.8
	return v


## Indices into f.melee that may be used off-hand alongside the weapon at main_index (p.23): an Off-hand
## weapon, not the main weapon itself, and never when the fighter has a two-handed weapon.
static func offhand_choices(f: FighterState, main_index: int) -> Array:
	var out: Array = []
	if main_index < 0 or main_index >= f.melee.size() or "Two-handed" in f.melee[main_index].get("traits", []):
		return out
	for w in f.ranged:
		if "Two-handed" in w.get("traits", []):
			return out
	for i in f.melee.size():
		if i != main_index and "Off-hand" in f.melee[i].get("traits", []):
			out.append(i)
	return out


## Best off-hand partner for a main weapon (the most valuable valid one), or -1.
static func default_offhand(f: FighterState, main_index: int) -> int:
	var best := -1
	for i in offhand_choices(f, main_index):
		if best < 0 or attack_value(f.melee[i]) > attack_value(f.melee[best]):
			best = i
	return best


## Suggested [main index, off-hand index or -1]: the split with the most total damage, so with two
## off-hand weapons the less damaging one goes in the off hand (it only gets 1 attack).
static func default_weapons(f: FighterState) -> Array:
	if f.melee.size() <= 1:
		return [0, -1]
	var best := [0, -1]
	var best_total := -INF
	for m in f.melee.size():
		var w: Dictionary = f.melee[m]
		var total := Dice.average(str(w.get("attacks", "1"))) * attack_value(w)
		var off := default_offhand(f, m)
		if off >= 0:
			total += attack_value(f.melee[off])
		if total > best_total:
			best_total = total
			best = [m, off]
	return best


## Weapon ids for a melee attack from indices into f.melee.
static func weapon_ids(f: FighterState, main_index: int, off_index: int) -> Array:
	var ids: Array = [f.melee[main_index]["id"]]
	if off_index >= 0 and off_index != main_index:
		ids.append(f.melee[off_index]["id"])
	return ids


static func _check_weapons(f: FighterState, ids: Array) -> String:
	if ids.is_empty():
		return "Pick a melee weapon."
	var main := f.weapon_by_id(ids[0])
	if main.is_empty() or main.get("kind", "") != "melee":
		return "Pick a melee weapon."
	if ids.size() > 1:
		var off := f.weapon_by_id(ids[1])
		var copies := 0
		for w in f.melee:
			if w["id"] == ids[0]:
				copies += 1
		if off.is_empty() or (ids[1] == ids[0] and copies < 2):
			return "Pick a different off-hand weapon."
		if not "Off-hand" in off.get("traits", []):
			return "%s can't be used off-hand." % off["name"]
		if "Two-handed" in main.get("traits", []):
			return "No off-hand attacks with a two-handed weapon."
		for w in f.ranged:
			if "Two-handed" in w.get("traits", []):
				return "No off-hand attacks while equipped with a two-handed weapon."
	return ""


static func _holds_item_with_2h(f: FighterState) -> bool:
	for id in f.items:
		var w := Catalog.wargear(f.faction, id)
		if w.get("held", false):
			return true
	return false


static func respond_duel(b: Battle, choice: Dictionary) -> String:
	var p := b.pending
	if p["type"] == "melee_weapons":
		var d := b.fighter(p["uid"])
		var ids: Array = choice.get("weapons", [d.melee[0]["id"]])
		var err := _check_weapons(d, ids)
		if err != "":
			return err
		b.duel["def_w"] = ids
		b.duel["def_opts"] = choice
		b.pending = {}
		_duel_roll(b)
		return ""
	if p["type"] == "duel_turn":
		return _duel_act(b, choice)
	return "Not a melee decision."


static func _duel_roll(b: Battle) -> void:
	var a := b.fighter(b.duel["att"])
	var d := b.fighter(b.duel["def"])
	# Nets and Mesmeric Gaze are resolved at the start of the action.
	for pair in [[a, d, b.duel["att_opts"]], [d, a, b.duel.get("def_opts", {})]]:
		var me: FighterState = pair[0]
		var foe: FighterState = pair[1]
		var o: Dictionary = pair[2]
		if o.get("net", false) and me.has_item("net") and not "net" in me.once_per_battle:
			me.once_per_battle.append("net")
			var t := b.dice.test(int(me.stats["initiative"]))
			if t["pass"]:
				foe.add_effect({"id": "entwined", "until": "battle"})
			b.log_line("%s throws a net (rolled %d): %s." % [me.name, t["roll"], "%s is entwined" % foe.name if t["pass"] else "missed"])
		if o.get("stand_ground", false) and me.has_rule("stand_ground") and not "stand_ground" in me.once_per_battle and me == d and a.charged:
			me.once_per_battle.append("stand_ground")
			me.add_effect({"id": "stand_ground", "until": "round"})
			b.log_line("%s stands their ground (Brace and Bludgeon)." % me.name)
	if b.duel["att_opts"].get("mesmeric", false) and a.has_rule("mesmeric_gaze") and not "mesmeric_gaze" in a.once_per_battle:
		a.once_per_battle.append("mesmeric_gaze")
		var ra := b.dice.d6() + int(a.stats["willpower"])
		var rd := b.dice.d6() + int(d.stats["willpower"])
		if ra > rd:
			d.add_effect({"id": "mesmerised", "until": "round"})
		b.log_line("Mesmeric Gaze: %d vs %d — %s." % [ra, rd, "%s is mesmerised" % d.name if ra > rd else "resisted"])
	# Initiative (step 3)
	var init_uid: int
	var d_brace := false
	for id in b.duel["def_w"]:
		if Effects.weapon_has(d, d.weapon_by_id(id), "Brace"):
			d_brace = true
	if a.charged and d_brace:
		init_uid = d.uid
		b.log_line("%s braces against the charge and has the initiative." % d.name)
	elif a.charged:
		init_uid = a.uid
		b.log_line("%s charged and has the initiative." % a.name)
	else:
		var ia := b.dice.d6() + int(a.stats["initiative"])
		var id_ := b.dice.d6() + int(d.stats["initiative"])
		init_uid = a.uid if ia >= id_ else d.uid
		b.log_line("Initiative: %s %d vs %s %d — %s." % [a.name, ia, d.name, id_, b.fighter(init_uid).name])
	# Attack rolls (step 4)
	b.duel["rolls"] = {str(a.uid): _roll_side(b, a, b.duel["att_w"], d), str(d.uid): _roll_side(b, d, b.duel["def_w"], a)}
	b.duel["turn"] = init_uid
	_duel_next(b, init_uid)


static func _roll_side(b: Battle, f: FighterState, ids: Array, foe: FighterState) -> Array:
	var dice_out: Array = []
	var weapons: Array = []
	for i in ids.size():
		weapons.append({"w": f.weapon_by_id(ids[i]), "offhand": i > 0})
	for id in f.items:
		var it := Catalog.wargear(f.faction, id)
		if it.has("weapon") and it["weapon"].has("attacks") and not it["weapon"].has("range"):
			var iw: Dictionary = it["weapon"].duplicate(true)
			iw["id"] = id
			iw["kind"] = "melee"
			weapons.append({"w": iw, "offhand": false, "companion": true})
	var held_2h := _holds_item_with_2h(f)
	var summary: PackedStringArray = []
	for entry in weapons:
		var w: Dictionary = entry["w"]
		var n := 1 if entry.get("companion", false) else Effects.attacks_for(b, f, w, entry["offhand"], held_2h)
		var mod := Effects.attack_mod(b, f, w, foe, false)
		var thr := Effects.crit_threshold(b, f, w, false)
		var parts: PackedStringArray = []
		for k in n:
			var nat := b.dice.d6()
			var crit := nat >= thr
			var hit := crit or (nat != 1 and nat + mod >= Effects.hit_value(f, false))
			var natural := Effects.weapon_has(f, w, "Natural Weapon")
			var wrap := Effects.weapon_has(f, w, "Wrap")
			dice_out.append({"w": w["id"], "name": w["name"], "nat": nat, "crit": crit, "hit": hit, "used": false,
				"can_parry": not natural and not wrap, "parryable": not wrap, "guard": Effects.weapon_has(f, w, "Guard")})
			parts.append("%d%s" % [nat, "!" if crit else ("✓" if hit else "✗")])
		summary.append("%s %s" % [w["name"], " ".join(parts)])
	b.log_line("%s rolls: %s." % [f.name, "; ".join(summary)])
	return dice_out


static func _successes(b: Battle, uid: int) -> Array:
	var out: Array = []
	var rolls: Array = b.duel["rolls"][str(uid)]
	for i in rolls.size():
		if rolls[i]["hit"] and not rolls[i]["used"]:
			out.append(i)
	return out


## Options for the fighter whose turn it is: [{"label", "choice"}].
static func duel_options(b: Battle) -> Array:
	if b.duel.is_empty():
		return []
	var me: int = b.duel["turn"]
	var foe: int = b.duel["def"] if me == b.duel["att"] else b.duel["att"]
	var fme := b.fighter(me)
	var mine: Array = b.duel["rolls"][str(me)]
	var theirs: Array = b.duel["rolls"][str(foe)]
	var out: Array = []
	for i in _successes(b, me):
		var r: Dictionary = mine[i]
		out.append({"label": "Attack with %s (%d%s)" % [r["name"], r["nat"], " CRIT" if r["crit"] else ""], "choice": {"action": "attack", "die": i}})
	var parry_dice: Array = []
	for i in mine.size():
		var r: Dictionary = mine[i]
		if r["used"]:
			continue
		if r["hit"] and r["can_parry"]:
			parry_dice.append(i)
		elif not r["hit"] and r["guard"] and r["can_parry"] and not me in b.duel["guard_used"]:
			parry_dice.append(i)
	for j in _successes(b, foe):
		var tr: Dictionary = theirs[j]
		if not tr["parryable"]:
			continue
		for i in parry_dice:
			var r: Dictionary = mine[i]
			var guard_miss: bool = not r["hit"]
			if tr["crit"] and not (r["crit"] or (fme.has_rule("duellist") and not guard_miss)):
				continue
			out.append({"label": "Parry their %s %d%s using %s %d%s" % [tr["name"], tr["nat"], " CRIT" if tr["crit"] else "", r["name"], r["nat"], " (Guard miss)" if guard_miss else ""],
				"choice": {"action": "parry", "die": i, "target": j}})
			break  # one way of parrying each enemy die is enough for the menu
	return out


static func _duel_next(b: Battle, uid: int) -> void:
	var a := b.fighter(b.duel["att"])
	var d := b.fighter(b.duel["def"])
	if not a.on_board() or not d.on_board():
		_end_duel(b)
		return
	var other: int = b.duel["def"] if uid == b.duel["att"] else b.duel["att"]
	var me := uid
	if _successes(b, me).is_empty():
		me = other
	if _successes(b, me).is_empty():
		_end_duel(b)
		return
	b.duel["turn"] = me
	var f := b.fighter(me)
	b.pending = {"type": "duel_turn", "player": f.player, "uid": me}
	b.changed.emit()


static func _duel_act(b: Battle, choice: Dictionary) -> String:
	var me: int = b.duel["turn"]
	var foe: int = b.duel["def"] if me == b.duel["att"] else b.duel["att"]
	var fme := b.fighter(me)
	var ffoe := b.fighter(foe)
	var mine: Array = b.duel["rolls"][str(me)]
	var theirs: Array = b.duel["rolls"][str(foe)]
	var legal := false
	for o in duel_options(b):
		if o["choice"]["action"] == choice.get("action") and int(o["choice"]["die"]) == int(choice.get("die", -1)) and int(o["choice"].get("target", -1)) == int(choice.get("target", -1)):
			legal = true
	if not legal and choice.get("action") == "parry":
		# The menu lists one way to parry each die; accept any valid pairing too.
		legal = _parry_valid(b, fme, mine, theirs, int(choice.get("die", -1)), int(choice.get("target", -1)))
	if not legal:
		return "That isn't a legal choice."
	b.pending = {}
	var i := int(choice["die"])
	if choice["action"] == "attack":
		mine[i]["used"] = true
		var w := fme.weapon_by_id(mine[i]["w"])
		if w.is_empty():
			w = Catalog.wargear(fme.faction, mine[i]["w"]).get("weapon", {}).duplicate(true)
			w["id"] = mine[i]["w"]
			w["kind"] = "melee"
		var ctx := {"melee": true, "rend": Effects.rend_for(b, fme, w, ffoe),
			"defending_vs_charge": foe == b.duel["def"] and b.fighter(b.duel["att"]).charged}
		resolve_hit(b, fme, ffoe, w, mine[i]["crit"], ctx)
	else:
		var j := int(choice["target"])
		var guard_miss: bool = not mine[i]["hit"]
		mine[i]["used"] = true
		if guard_miss:
			b.duel["guard_used"].append(me)
		var mod := 0
		if ffoe.has_rule("dirty_fighter"):
			mod -= 1
		if ffoe.has_rule("relentless_attacker"):
			mod -= 1
		if fme.has_effect("disorientated"):
			mod -= 1
		var r := b.dice.d6()
		var ok := r != 1 and r + mod >= 2
		if ok and ffoe.has_rule("feint") and not b.duel["feint_used"]:
			b.duel["feint_used"] = true
			var fr := b.dice.d6()
			if fr >= r:
				b.log_line("%s parries (rolled %d) but %s feints (rolled %d): the hit stands and becomes a CRITICAL hit." % [fme.name, r, ffoe.name, fr])
				theirs[j]["crit"] = true
				_duel_next(b, foe)
				return ""
		if ok:
			theirs[j]["used"] = true
			b.log_line("%s parries %s's %s (rolled %d%s)." % [fme.name, ffoe.name, theirs[j]["name"], r, ("%+d" % mod) if mod != 0 else ""])
		else:
			b.log_line("%s's parry fails (rolled %d%s)." % [fme.name, r, ("%+d" % mod) if mod != 0 else ""])
			if ffoe.has_rule("dirty_fighter"):
				apply_damage(b, fme, 1, ffoe, "Dirty Fighter")
	_duel_next(b, foe)
	return ""


static func _parry_valid(b: Battle, fme: FighterState, mine: Array, theirs: Array, i: int, j: int) -> bool:
	if i < 0 or i >= mine.size() or j < 0 or j >= theirs.size():
		return false
	var r: Dictionary = mine[i]
	var t: Dictionary = theirs[j]
	if r["used"] or t["used"] or not t["hit"] or not t["parryable"] or not r["can_parry"]:
		return false
	var guard_miss: bool = not r["hit"]
	if guard_miss and (not r["guard"] or fme.uid in b.duel["guard_used"]):
		return false
	if t["crit"] and not (r["crit"] or (fme.has_rule("duellist") and not guard_miss)):
		return false
	return true


static func _end_duel(b: Battle) -> void:
	for uid in [b.duel.get("att", -1), b.duel.get("def", -1)]:
		var f := b.fighter(uid)
		if f:
			f.remove_effect("mesmerised")
	b.log_line("The melee attack action ends.")
	b.duel = {}
	b.pending = {}
	b.after_action()
	var a := b.active_fighter()
	if a != null and not a.on_board():
		b.end_activation()
		return
	b.changed.emit()
