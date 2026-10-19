class_name Magic
extends RefCounted
## Arcane actions (pp.33-34) and the spell lores of all four factions.
## Each spell has a targeting type the UI uses:
##   none      - no target (auras centred on the caster, Witchfire, Dark Vitality)
##   closest   - the rules pick the closest visible enemy in range
##   friendly / enemy - pick a fighter (range in "range")
##   point     - pick a point (blast templates, Black Mire, Consecrated Ground)
##   dir       - pick a direction (flame template, Sanguine Spear)
##   friendly_point - pick a friendly fighter, then where to set it up
##   summon    - pick where to set up the summoned fighter
##   manual    - effect is shown for the players to resolve on the table

const SPELLS := {
	# Lore of Sanctioned Magic
	"Arcane Missile": {"target": "closest", "range": 15.0},
	"Flaming Weapon": {"target": "friendly", "range": 6.0, "crit_range": 12.0, "visible": true},
	"Eldritch Barrier": {"target": "two_points", "range": 9.0, "gap": 6.0, "crit_gap": 9.0, "visible": true},
	"Silence": {"target": "enemy", "range": 12.0, "crit_range": 18.0, "visible": true},
	"Torrent of Fire": {"target": "dir"},
	"Umbral Vortex": {"target": "point", "range": 15.0, "visible": true},
	# Lore of the Saints
	"Healing Essence": {"target": "friendly", "range": 15.0, "visible": true},
	"Bless Thy Blade": {"target": "friendly", "range": 9.0, "visible": true},
	"Godspeed": {"target": "none"},
	"Will of the Saints": {"target": "friendly", "range": 15.0, "visible": true},
	"Holy Strength": {"target": "none"},
	"Consecrated Ground": {"target": "point", "range": 12.0, "visible": true},
	# Lore of the Under-Tunnels
	"Shadow Leap": {"target": "friendly_point", "range": 3.0, "place_range": 9.0, "crit_place_range": 12.0, "visible": true, "self_ok": true},
	"Doom": {"target": "enemy", "range": 12.0, "crit_range": 18.0, "visible": true},
	"Chain Lightning": {"target": "closest", "range": 12.0},
	"Tunnel from Below": {"target": "point", "range": 12.0},
	"Gathering Shadows": {"target": "none"},
	"Bouncing Blast": {"target": "point", "range": 15.0, "visible": true},
	# Lore of Poxes
	"Spray of Vomit": {"target": "dir"},
	"Fetid Blades": {"target": "friendly", "range": 6.0, "crit_range": 12.0},
	"Rabid Fervour": {"target": "none"},
	"Rotten Armour": {"target": "enemy", "range": 18.0, "visible": true},
	"Dark Vitality": {"target": "none"},
	"Plague Bomb": {"target": "point", "range": 12.0, "visible": true},
	# Lore of Necromancy
	"Witchfire": {"target": "none"},
	"Ethereal Armour": {"target": "friendly", "range": 6.0, "crit_range": 12.0, "visible": true},
	"Raise Zombie": {"target": "summon", "range": 3.0, "crit_range": 9.0, "summon": "zombie"},
	"Twilight Translocation": {"target": "friendly_point", "range": 6.0, "place_range": 15.0, "crit_place_range": 18.0, "visible": true},
	"Death Blast": {"target": "point", "range": 12.0},
	"Balefire": {"target": "dir"},
	# Lore of Blood
	"Draw Blood": {"target": "closest", "range": 9.0},
	"Cursed Blades": {"target": "friendly", "range": 6.0, "crit_range": 12.0},
	"Raise Skeleton": {"target": "summon", "range": 3.0, "crit_range": 9.0, "summon": "skeleton_warrior"},
	"Recall": {"target": "friendly_point", "range": 99.0, "place_range": 3.0, "thrall": true},
	"Bat Scream": {"target": "dir"},
	"Sanguine Spear": {"target": "dir"},
	# Lore of Blessed Maggots
	"Swollen Form": {"target": "friendly", "range": 9.0, "crit_range": 12.0, "visible": true},
	"Black Mire": {"target": "point", "range": 6.0, "visible": true},
	"Erupting Sores": {"target": "closest", "range": 9.0, "crit_range": 12.0},
	"Rain of Filth": {"target": "point", "range": 12.0},
	"Putrid Blessing": {"target": "friendly", "range": 6.0, "crit_range": 12.0},
	"Black Bile": {"target": "dir"},
	# Demonic Lore of Rot
	"Summon Rotling": {"target": "summon", "range": 3.0, "crit_range": 9.0, "summon": "rotling"},
	"Demonic Strength": {"target": "friendly", "range": 6.0, "kw": ["Demon", "Beastman"]},
	"Rotten Insides": {"target": "closest", "range": 9.0, "crit_range": 12.0},
	"Plague Wind": {"target": "point", "range": 15.0},
	"Protective Shroud": {"target": "friendly", "range": 6.0, "crit_range": 12.0, "kw": ["Demon", "Beastman"]},
	"Plague Pit": {"target": "point", "range": 9.0, "visible": true},
}


static func spell_info(name: String) -> Dictionary:
	return SPELLS.get(name, {"target": "manual"})


# --- Preparing spells (p.34) ----------------------------------------------------------------

static func prepare_spells(b: Battle) -> void:
	for f in b.fighters:
		if f.lores.is_empty():
			continue
		f.prepared = []
		var names: PackedStringArray = []
		for lore_id in f.lores:
			var lore := Catalog.lore(f.faction, lore_id)
			for s in lore["spells"]:
				if s["name"] in f.signature_spells:
					_add_prepared(f, s, lore_id, names)
			var r := b.dice.d6()
			for s in lore["spells"]:
				if int(s["n"]) == r:
					_add_prepared(f, s, lore_id, names)
		b.log_line("%s prepares: %s." % [f.name, ", ".join(names)])


static func _add_prepared(f: FighterState, s: Dictionary, lore_id: String, names: PackedStringArray) -> void:
	for p in f.prepared:
		if p["name"] == s["name"]:
			return  # duplicates are wasted, not re-rolled
	var sp: Dictionary = s.duplicate(true)
	sp["lore"] = lore_id
	f.prepared.append(sp)
	names.append(s["name"])


# --- Arcane actions -----------------------------------------------------------------------------

static func can_use_arcane(b: Battle, f: FighterState) -> String:
	if f == null or f.uid != b.active:
		return "No fighter is activating."
	if not f.is_caster():
		return "Only Wizards and Priests can make arcane actions."
	if not b.can_still_act(f):
		return "%s can't make an action now." % f.name
	if f.statuses.get("drained", false):
		return "%s's magic is drained for the rest of the battle." % f.name
	if f.has_effect("silenced"):
		return "%s is Silenced this round." % f.name
	return ""


static func draw_power(b: Battle) -> String:
	var f := b.active_fighter()
	var err := can_use_arcane(b, f)
	if err != "":
		return err
	if not b.harried_check(f, "action"):
		return ""
	f.acted = true
	f.statuses["drawn_power"] = true
	f.statuses.erase("drawn_power_used_window")
	b.log_line("%s draws power (an extra casting die next activation)." % f.name)
	b.changed.emit()
	return ""


## params: {"target": uid, "point": Vector2, "dir": Vector2}
static func cast(b: Battle, spell_name: String, params: Dictionary) -> String:
	var f := b.active_fighter()
	var err := can_use_arcane(b, f)
	if err != "":
		return err
	var spell := {}
	for s in f.prepared:
		if s["name"] == spell_name:
			spell = s
	if spell.is_empty():
		return "%s hasn't prepared %s." % [f.name, spell_name]
	err = _validate_target(b, f, spell_name, params, false)
	if err != "":
		return err
	if spell_name in ["Raise Zombie", "Raise Skeleton", "Summon Rotling"] and _summoned_count(b, f.player) >= 3:
		return "A warband can't have more than 3 summoned fighters."
	if not b.harried_check(f, "action"):
		return ""
	f.acted = true
	b.mark_dice_rolled()
	var n_dice := 2 if f.statuses.get("drawn_power", false) else 1
	f.statuses.erase("drawn_power")
	f.statuses.erase("drawn_power_used_window")
	var roll := _casting_roll(b, f, n_dice)
	if roll["miscast"] and f.has_item("grimoire") and not "grimoire" in f.once_per_battle:
		f.once_per_battle.append("grimoire")
		b.log_line("%s re-rolls the casting roll with the Grimoire." % f.name)
		roll = _casting_roll(b, f, n_dice)
	var total: int = roll["sum"] + int(f.stats["willpower"])
	if not roll["miscast"] and total < int(spell["casting"]) and f.has_item("grimoire") and not "grimoire" in f.once_per_battle:
		f.once_per_battle.append("grimoire")
		b.log_line("%s re-rolls the casting roll with the Grimoire." % f.name)
		roll = _casting_roll(b, f, n_dice)
		total = roll["sum"] + int(f.stats["willpower"])
	var crit := false
	if roll["miscast"]:
		b.log_line("%s attempts %s: %s — MISCAST!" % [f.name, spell_name, roll["text"]])
		var outcome := _miscast(b, f)
		if outcome != "burst":
			b.after_action()
			b.changed.emit()
			return ""
		crit = true
	else:
		if total < int(spell["casting"]):
			b.log_line("%s attempts %s: %s + Willpower %d = %d vs %d+ — the spell fails." % [f.name, spell_name, roll["text"], f.stats["willpower"], total, spell["casting"]])
			b.changed.emit()
			return ""
		crit = total >= int(spell.get("critical", 99))
		b.log_line("%s casts %s: %s + Willpower %d = %d vs %d+%s." % [f.name, spell_name, roll["text"], f.stats["willpower"], total, spell["casting"], " — CRITICAL CAST" if crit else ""])
	if f.on_board():
		_resolve(b, f, spell, crit, params)
	b.after_action()
	b.changed.emit()
	return ""


static func _casting_roll(b: Battle, f: FighterState, n: int) -> Dictionary:
	var rolls := b.dice.roll_many(n)
	var s := 0
	for r in rolls:
		s += r
	var miscast := (n == 1 and rolls[0] == 1) or (n >= 2 and _has_double(rolls))
	return {"rolls": rolls, "sum": s, "miscast": miscast, "text": "rolled %s" % ", ".join(rolls.map(func(x): return str(x)))}


static func _has_double(rolls: Array) -> bool:
	for i in rolls.size():
		for j in range(i + 1, rolls.size()):
			if rolls[i] == rolls[j]:
				return true
	return false


## Miscast table (p.33). Returns "fail", "down" or "burst" (spell is critically cast).
static func _miscast(b: Battle, f: FighterState) -> String:
	var r := b.dice.d6() + b.dice.d6()
	if r <= 5 and f.has_item("ensorcelled_bell") and not "bell" in f.once_per_battle:
		f.once_per_battle.append("bell")
		var r2 := b.dice.d6() + b.dice.d6()
		b.log_line("Miscast roll %d re-rolled with the Ensorcelled Bell: %d." % [r, r2])
		r = r2
	if r == 2:
		b.log_line("Inferno of Sorcery (%d): %s explodes in balefire!" % [r, f.name])
		for o in Combat.blast_hits(b, f.pos, f.elev):
			if o != f:
				Combat.apply_damage(b, o, b.dice.d6(), f, "Inferno of Sorcery")
		Combat.take_down(b, f, null, "Inferno of Sorcery")
		return "down"
	if r <= 5:
		b.log_line("Arcane Explosion (%d): the spell fails and eldritch fire erupts." % r)
		for o in Combat.blast_hits(b, f.pos, f.elev):
			Combat.apply_damage(b, o, b.dice.d3(), f, "Arcane Explosion")
		return "fail"
	if r <= 7:
		b.log_line("Drained Magic (%d): %s can't use arcane actions for the rest of the battle." % [r, f.name])
		f.statuses["drained"] = true
		return "fail"
	var d := b.dice.d3()
	b.log_line("Uncontrolled Burst of Power (%d): %s suffers %d damage%s." % [r, f.name, d, "" if f.life > d else " and is taken down"])
	Combat.apply_damage(b, f, d, null, "Uncontrolled Burst of Power")
	return "burst" if f.on_board() else "down"


# --- Targeting --------------------------------------------------------------------------------

static func _range(info: Dictionary, crit: bool) -> float:
	return float(info.get("crit_range", info.get("range", 0.0))) if crit else float(info.get("range", 0.0))


static func _validate_target(b: Battle, f: FighterState, name: String, params: Dictionary, crit: bool) -> String:
	var info := spell_info(name)
	var rng := _range(info, true)  # allow the critical range at declaration; the effect re-checks it
	match info["target"]:
		"friendly", "enemy", "friendly_point":
			var t := b.fighter(int(params.get("target", -1)))
			if t == null or not t.on_board():
				return "Pick a target fighter."
			var friendly: bool = info["target"] != "enemy"
			if friendly != (t.player == f.player):
				return "Pick a %s fighter." % ("friendly" if friendly else "enemy")
			if t == f and info["target"] == "friendly_point" and not info.get("self_ok", false):
				return "Pick another fighter."
			if info.has("kw"):
				var ok := false
				for k in info["kw"]:
					if t.has_kw(k):
						ok = true
				if not ok:
					return "The target must be a %s." % " or ".join(info["kw"])
			if info.get("thrall", false) and not t.has_kw("Thrall"):
				return "The target must be a Thrall."
			if t != f and not Effects.near(f, t, rng):
				return "Out of range (%.0f\")." % rng
			if info.get("visible", false) and not Effects.visibility(b, f, t)["visible"]:
				return "The target must be visible."
			if name == "Silence" and not t.is_caster():
				return "Silence targets an enemy Wizard or Priest."
			if info["target"] == "friendly_point":
				if not params.has("point"):
					return "Pick where to set the fighter up."
				var place_rng := float(info.get("crit_place_range", info.get("place_range", 0.0)))
				var pt: Vector2 = params["point"]
				if f.pos.distance_to(pt) > place_rng + f.radius + Geo.EPS:
					return "Too far from the caster (%.0f\")." % place_rng
				return _placement_ok(b, t, pt, params.get("elev", 0.0))
		"point", "summon":
			if not params.has("point"):
				return "Pick a point."
			var pt: Vector2 = params["point"]
			var pel: float = params.get("elev", 0.0)
			if Vector2(f.pos.distance_to(pt) - f.radius, pel - f.elev).length() > rng + Geo.EPS:
				return "That point is out of range (%.0f\")." % rng
			if info.get("visible", false) and not Combat.point_visible(b, f.pos, pt, [f], Effects.eye_height(f), pel + 0.3):
				return "That point isn't visible."
			if info["target"] == "summon":
				var probe := FighterState.new()
				probe.radius = Geo.radius_from_mm(32.0)
				probe.player = f.player
				return _placement_ok(b, probe, pt, pel)
		"dir":
			if not params.has("dir") or (params["dir"] as Vector2).length() < 0.01:
				return "Pick a direction."
		"two_points":
			if not params.has("point") or not params.has("point2"):
				return "Pick two points."
			for key in ["point", "point2"]:
				var q: Vector2 = params[key]
				if f.pos.distance_to(q) - f.radius > float(info["range"]) + Geo.EPS:
					return "Both points must be within %.0f\" of the caster." % info["range"]
				if not Combat.point_visible(b, f.pos, q, [f], Effects.eye_height(f), float(params.get("elev", 0.0)) + 0.3):
					return "Both points must be visible."
			if (params["point"] as Vector2).distance_to(params["point2"]) > float(info["crit_gap"]) + Geo.EPS:
				return "The points must be within %.0f\" of each other." % info["crit_gap"]
		"closest":
			if _closest_enemy(b, f, _range(info, false)) == null and _closest_enemy(b, f, _range(info, true)) == null:
				return "No visible enemy within range."
	return ""


static func _placement_ok(b: Battle, f: FighterState, pt: Vector2, elev := 0.0) -> String:
	if not Geo.base_inside_board(pt, f.radius, b.board_size):
		return "That's off the battlefield."
	if not Height.supports(b, pt, elev):
		return "There's no floor or platform to stand on there."
	if elev > Height.LEVEL_EPS and f.has_rule("large_and_heavy"):
		return "Large and Heavy fighters must be set up on the battlefield floor."
	# The whole base must be clear of walls, statues and ladders on this level, not just its centre.
	var blocker := Height.base_clear(b, pt, f.radius, elev)
	if blocker != "":
		return "Can't stand there: the base would overlap %s." % blocker
	for o in b.on_board():
		if o == f:
			continue
		if absf(o.elev - elev) < minf(maxf(f.height, 1.0), o.height) and Geo.signed_gap(pt, f.radius, o.pos, o.radius) < -Geo.EPS:
			return "Overlaps %s." % o.name
		if o.player != f.player and Height.gap3(pt, f.radius, elev, o.pos, o.radius, o.elev) <= 1.0 + Geo.EPS:
			return "Must not be set up engaged in melee."
	return ""


static func _closest_enemy(b: Battle, f: FighterState, rng: float, from_pos := Vector2.INF, exclude: Array = []) -> FighterState:
	var origin := f.pos if from_pos == Vector2.INF else from_pos
	var best: FighterState = null
	var best_d := INF
	for o in b.on_board(b.other(f.player)):
		if o in exclude:
			continue
		var d: float = origin.distance_to(o.pos) - o.radius - (f.radius if from_pos == Vector2.INF else 0.0)
		if d <= rng + Geo.EPS and d < best_d and Effects.visibility(b, f, o)["visible"]:
			best = o
			best_d = d
	return best


static func _warded(b: Battle, caster: FighterState, t: FighterState) -> bool:
	if t.player != caster.player and t.armour_id == "warded_robes":
		var r := b.dice.d6()
		if r >= 4:
			b.log_line("%s's Warded Robes shrug off the spell (rolled %d)." % [t.name, r])
			return true
	return false


static func _summoned_count(b: Battle, player: int) -> int:
	var n := 0
	for o in b.fighters:
		if o.player == player and o.summoned and o.on_board():
			n += 1
	return n


# --- Effects -----------------------------------------------------------------------------------

static func _spell_attack(spell: Dictionary, crit: bool, name: String) -> Dictionary:
	var a: Dictionary = spell.get("attack", {"rend": 0, "damage": "1"})
	var p := {"name": name, "rend": int(a["rend"]), "damage": str(a["damage"]), "crit": null, "traits": [], "kind": "spell"}
	if crit:
		match name:
			"Arcane Missile", "Balefire":
				p["damage"] = Dice.add(p["damage"], 1)
			"Torrent of Fire":
				p["rend"] = -2
			"Spray of Vomit":
				p["damage"] = "d3"
	return p


static func _hit(b: Battle, f: FighterState, t: FighterState, profile: Dictionary, cover := false) -> int:
	if _warded(b, f, t):
		return 0
	return Combat.resolve_hit(b, f, t, profile, false, {"melee": false, "cover": cover, "rend": profile["rend"]})


static func _resolve(b: Battle, f: FighterState, spell: Dictionary, crit: bool, params: Dictionary) -> void:
	var name: String = spell["name"]
	var info := spell_info(name)
	var target: FighterState = b.fighter(int(params.get("target", -1))) if params.has("target") else null
	var profile := _spell_attack(spell, crit, name)
	match name:
		"Arcane Missile", "Chain Lightning":
			var t := _closest_enemy(b, f, _range(info, crit))
			if t == null:
				b.log_line("No target in range.")
				return
			_hit(b, f, t, profile)
			if name == "Chain Lightning":
				var chain: Array = [t]
				for k in (2 if crit else 1):
					var nxt: FighterState = null
					for o in b.on_board(b.other(f.player)):
						if o in chain:
							continue
						var near := false
						for c in chain:
							if Effects.near(c, o, 3.0):
								near = true
						if near and Effects.visibility(b, chain[-1], o)["visible"]:
							nxt = o
							break
					if nxt == null:
						break
					chain.append(nxt)
					b.log_line("The lightning arcs to %s." % nxt.name)
					_hit(b, f, nxt, profile)
		"Draw Blood":
			var t2 := _closest_enemy(b, f, 9.0)
			if t2 and not _warded(b, f, t2):
				var dmg := 2 if crit else 1
				Combat.apply_damage(b, t2, dmg, f, "Draw Blood")
				b.heal(f, dmg, "Draw Blood")
		"Erupting Sores":
			var t3 := _closest_enemy(b, f, _range(info, crit))
			if t3 and not _warded(b, f, t3):
				var dmg2 := b.dice.d3()
				b.log_line("%s's sores erupt: %d damage." % [t3.name, dmg2])
				Combat.apply_damage(b, t3, dmg2, f, "Erupting Sores")
				if t3.on_board() and not b.dice.test(int(t3.stats["willpower"]))["pass"]:
					Movement.scatter(b, t3, b.dice.d6())
		"Rotten Insides":
			var t4 := _closest_enemy(b, f, _range(info, crit))
			if t4 and not _warded(b, f, t4):
				Combat.apply_damage(b, t4, 1, f, "Rotten Insides")
				if t4.on_board():
					t4.add_effect({"id": "rotten_insides", "until": "battle"})
					b.log_line("%s has rotten insides (Move 2\")." % t4.name)
		"Flaming Weapon", "Fetid Blades", "Cursed Blades":
			if _warded(b, f, target):
				return
			var w: Dictionary = target.melee[0]
			var grants := ["Arcane"] if name == "Flaming Weapon" else ["Arcane", "Poison"]
			target.add_effect({"id": "flaming_weapon" if name == "Flaming Weapon" else "enchanted_weapon", "until": "round", "weapon": w["id"], "grant_traits": grants})
			b.log_line("%s's %s is enchanted (%s)." % [target.name, w["name"], ", ".join(grants)])
		"Putrid Blessing":
			target.add_effect({"id": "putrid_blessing", "until": "round", "weapon": "", "grant_traits": ["Arcane", "Poison"]})
			b.log_line("%s's melee weapons gain Arcane and Poison." % target.name)
		"Silence":
			if not _warded(b, f, target):
				target.add_effect({"id": "silenced", "until": "round"})
				b.log_line("%s is silenced." % target.name)
		"Doom":
			if not _warded(b, f, target):
				target.add_effect({"id": "doomed", "until": "battle"})
				b.log_line("%s is doomed: once, you may make it re-roll an attack, parry or armour roll (resolve on the table)." % target.name)
		"Rotten Armour":
			if not _warded(b, f, target):
				target.add_effect({"id": "rotten_armour", "until": "battle" if crit else "round"})
				b.log_line("%s's armour rots (-1 Armour)." % target.name)
		"Healing Essence":
			b.heal(target, 3 if crit else b.dice.d3(), name)
		"Bless Thy Blade", "Will of the Saints", "Ethereal Armour", "Demonic Strength", "Protective Shroud", "Swollen Form":
			var ids := {"Bless Thy Blade": "bless_thy_blade", "Will of the Saints": "will_of_the_saints", "Ethereal Armour": "ethereal_armour",
				"Demonic Strength": "demonic_strength", "Protective Shroud": "protective_shroud", "Swollen Form": "swollen"}
			var targets: Array = [target]
			if crit and name in ["Bless Thy Blade", "Will of the Saints", "Demonic Strength"]:
				var second := _second_friendly(b, f, target, _range(info, false), info.get("kw", []))
				if second:
					targets.append(second)
			for t5 in targets:
				var e := {"id": ids[name], "until": "round"}
				if name == "Swollen Form":
					e["left"] = 3
				t5.add_effect(e)
				b.log_line("%s: %s." % [name, t5.name])
		"Godspeed", "Holy Strength", "Gathering Shadows", "Rabid Fervour":
			var radius: float = {"Godspeed": 12.0 if crit else 9.0, "Holy Strength": 9.0 if crit else 6.0, "Gathering Shadows": 9.0 if crit else 6.0, "Rabid Fervour": 9.0 if crit else 6.0}[name]
			f.add_effect({"id": "aura_" + name.to_snake_case(), "until": "round", "radius": radius})
			b.log_line("%s surrounds %s with a %.0f\" aura." % [name, f.name, radius])
		"Consecrated Ground":
			for o in b.fighters:
				o.remove_effect("consecrated_ground")
			f.add_effect({"id": "consecrated_ground", "until": "battle", "point": params["point"], "radius": 6.0 if crit else 3.0})
			b.log_line("The ground is consecrated.")
		"Dark Vitality":
			for o in b.on_board(f.player):
				if Effects.near(f, o, 6.0 if crit else 3.0):
					b.heal(o, 1, name)
		"Witchfire":
			var n := 3 if crit else b.dice.d3()
			f.statuses["witchfire"] = mini(3, int(f.statuses.get("witchfire", 0)) + n)
			b.log_line("%s now has %d witchfire token(s)." % [f.name, f.statuses["witchfire"]])
		"Torrent of Fire", "Spray of Vomit", "Balefire", "Black Bile", "Bat Scream":
			var dir: Vector2 = params["dir"]
			b.scen["last_template"] = {"type": "flame", "origin": f.pos + dir.normalized() * f.radius, "dir": dir.normalized(), "round": b.round_no}
			for t6 in Combat.flame_hits(b, f, dir):
				if name == "Bat Scream":
					if _warded(b, f, t6):
						continue
					Combat.apply_damage(b, t6, 1, f, name)
					if t6.on_board():
						var test := b.dice.d6() + (1 if crit else 0)
						if test > int(t6.stats["willpower"]):
							t6.add_effect({"id": "disorientated", "until": "round"})
							b.log_line("%s is disorientated." % t6.name)
					continue
				_hit(b, f, t6, profile)
				if name == "Black Bile" and crit and t6.on_board() and t6.can_be_poisoned() and not b.dice.test(int(t6.stats["willpower"]))["pass"]:
					t6.statuses["poisoned"] = true
					b.log_line("%s is poisoned." % t6.name)
		"Sanguine Spear":
			var dir2: Vector2 = (params["dir"] as Vector2).normalized()
			var length := 15.0 if crit else 12.0
			var a := f.pos + dir2 * f.radius
			var c := a + dir2 * length
			for o in b.on_board(b.other(f.player)):
				if Geometry2D.get_closest_point_to_segment(o.pos, a, c).distance_to(o.pos) <= o.radius + 0.5 and Effects.visibility(b, f, o)["visible"]:
					var dealt2 := _hit(b, f, o, profile)
					if dealt2 > 0:
						b.heal(f, dealt2, name)
		"Umbral Vortex", "Bouncing Blast", "Plague Bomb", "Death Blast", "Rain of Filth":
			var c2: Vector2 = params["point"]
			var c2_elev: float = params.get("elev", 0.0)
			if not crit:  # every one of these spells skips its first scatter on a critical cast
				var s := b.dice.d6()
				c2 = Combat.scatter_point(b, c2, s)
				if not Height.supports(b, c2, c2_elev):
					c2_elev = Height.level_below(b, c2, c2_elev + 0.01) if c2_elev > 0.0 else 0.0
				b.log_line("The template scatters %d\"." % s)
			var passes := 2 if name == "Bouncing Blast" else 1
			for k in passes:
				if k == 1:
					var s2 := b.dice.d6()
					c2 = Combat.scatter_point(b, c2, s2)
					if not Height.supports(b, c2, c2_elev):
						c2_elev = Height.level_below(b, c2, c2_elev + 0.01) if c2_elev > 0.0 else 0.0
					b.log_line("The blast bounces %d\"." % s2)
				b.scen["last_template"] = {"type": "blast", "pos": c2, "elev": c2_elev, "round": b.round_no}
				for t7 in Combat.blast_hits(b, c2, c2_elev):
					if name == "Rain of Filth":
						b.heal(t7, b.dice.d3(), name)
						continue
					var probe := FighterState.new()
					probe.pos = c2
					var cover: bool = Effects.visibility_from_point(b, c2, c2_elev + 0.5, probe, t7, true)["obscured"]
					_hit(b, f, t7, profile, cover)
					if name == "Plague Bomb" and t7.on_board() and t7.can_be_poisoned():
						t7.statuses["poisoned"] = true
			if name == "Umbral Vortex":
				b.scen["vortex"] = {"c": c2, "r": Combat.BLAST_RADIUS, "elev": c2_elev, "rend": profile["rend"], "damage": profile["damage"], "caster": f.uid}
				b.log_line("The vortex lingers until the end of the round: it blocks sight, and fighters starting in it or moving across it are hit.")
		"Plague Wind":
			var c3: Vector2 = params["point"]
			b.scen["last_template"] = {"type": "blast", "pos": c3, "round": b.round_no}
			for t8 in Combat.blast_hits(b, c3, params.get("elev", 0.0)):
				if t8.player == f.player or _warded(b, f, t8):
					continue
				var r := b.dice.d6() + (1 if crit else 0)
				if r > int(t8.stats["willpower"]) and t8.can_be_poisoned():
					t8.statuses["poisoned"] = true
					b.log_line("%s is poisoned by the Plague Wind." % t8.name)
		"Black Mire":
			b.scen["black_mire"] = {"point": params["point"], "radius": 9.0 if crit else 6.0}
			b.log_line("The ground becomes a mire (-2\" for non-Cloister fighters moving across it).")
		"Plague Pit":
			var c4: Vector2 = params["point"]
			for t9 in Combat.blast_hits(b, c4):
				var away: Vector2 = (t9.pos - c4)
				if away.length() < 0.01:
					away = Vector2.RIGHT
				Movement.place(b, t9, c4 + away.normalized() * (Combat.BLAST_RADIUS + t9.radius + 0.05))
				var test2 := b.dice.test(int(t9.stats["initiative"]))
				if not test2["pass"]:
					Combat.apply_damage(b, t9, b.dice.d3(), f, name)
					if t9.on_board() and t9.can_be_poisoned():
						t9.statuses["poisoned"] = true
			var pits: Array = b.scen.get("pits", [])
			pits.append({"c": c4, "r": Combat.BLAST_RADIUS})
			b.scen["pits"] = pits
			for i in range(b.tokens.size() - 1, -1, -1):
				if b.tokens[i]["type"] == "treasure" and (b.tokens[i]["pos"] as Vector2).distance_to(c4) <= Combat.BLAST_RADIUS:
					b.tokens.remove_at(i)
					b.log_line("Treasure tumbles into the pit and is lost.")
			b.log_line("A plague pit opens: fighters on the floor can't cross it this round.")
		"Eldritch Barrier":
			var p1: Vector2 = params["point"]
			var p2: Vector2 = params["point2"]
			var gap: float = info["crit_gap"] if crit else info["gap"]
			if p1.distance_to(p2) > gap:
				p2 = p1 + (p2 - p1).normalized() * gap
			var bars: Array = b.scen.get("barriers", [])
			bars.append({"a": p1, "b": p2, "elev": float(params.get("elev", 0.0)), "caster": f.uid})
			b.scen["barriers"] = bars
			b.log_line("An Eldritch Barrier shimmers into being (%.1f\" long) until the end of the round." % p1.distance_to(p2))
		"Shadow Leap", "Twilight Translocation", "Recall":
			var pt: Vector2 = params["point"]
			var pel2: float = params.get("elev", 0.0)
			if _placement_ok(b, target, pt, pel2) == "":
				target.pos = pt
				target.elev = pel2
				b.log_line("%s is set up again elsewhere." % target.name)
		"Raise Zombie", "Raise Skeleton", "Summon Rotling":
			var nf := summon(b, f, info["summon"], params["point"], params.get("elev", 0.0))
			if nf:
				b.log_line("A %s rises to join %s's warband." % [nf.name, b.player_names[f.player]])
		"Tunnel from Below":
			var c5: Vector2 = Combat.scatter_point(b, params["point"], b.dice.d6())
			var n2 := b.dice.d3()
			var placed := 0
			for o in b.fighters:
				if placed >= n2:
					break
				if o.player == f.player and o.where == "reserve":
					var spot := Scenario.find_spot(b, o, c5, Combat.BLAST_RADIUS)
					if spot != Vector2.INF:
						o.where = "board"
						o.pos = spot
						o.activated = false  # arrives unactivated: every fighter on the battlefield activates each round (p.19)
						placed += 1
						b.log_line("%s emerges from the tunnel." % o.name)
		_:
			b.log_line("%s: %s (resolve on the table)." % [name, spell.get("text", "")])


static func _second_friendly(b: Battle, f: FighterState, first: FighterState, rng: float, kws: Array) -> FighterState:
	for o in b.on_board(f.player):
		if o == first or not Effects.near(f, o, rng):
			continue
		if not kws.is_empty():
			var ok := false
			for k in kws:
				if o.has_kw(k):
					ok = true
			if not ok:
				continue
		return o
	return null


static func summon(b: Battle, caster: FighterState, def_id: String, at: Vector2, elev := 0.0) -> FighterState:
	var r := Roster.new()
	r.faction = caster.faction
	var m := r.add_member(def_id)
	if def_id == "skeleton_warrior":
		m["equipment"] = ["cuirass", "shield", "sword"]
	var nf := FighterState.from_member(r, m, caster.player, b.new_uid())
	nf.summoned = true
	nf.where = "board"
	nf.pos = at
	nf.elev = elev
	# Joins the warband unactivated: every fighter on the battlefield must activate each round (p.19),
	# so a fighter summoned this round gets its own activation this round.
	nf.activated = false
	b.fighters.append(nf)
	return nf


## Witchfire bonus action: spend a token to hit the closest visible enemy within 12".
static func witchfire_attack(b: Battle) -> String:
	var f := b.active_fighter()
	if f == null or int(f.statuses.get("witchfire", 0)) <= 0:
		return "No witchfire tokens."
	if "witchfire" in f.once_per_activation:
		return "Only once per activation."
	var t := _closest_enemy(b, f, 12.0)
	if t == null:
		return "No visible enemy within 12\"."
	f.once_per_activation.append("witchfire")
	f.statuses["witchfire"] = int(f.statuses["witchfire"]) - 1
	b.mark_dice_rolled()
	_hit(b, f, t, {"name": "Witchfire", "rend": 0, "damage": "d3", "crit": null, "traits": [], "kind": "spell"})
	b.changed.emit()
	return ""


## Consecrated Ground: the caster must pass a Willpower test at the start of each activation or it ends.
static func start_of_activation(b: Battle, f: FighterState) -> void:
	if f.has_effect("consecrated_ground"):
		var t := b.dice.test(int(f.stats["willpower"]))
		if not t["pass"]:
			f.remove_effect("consecrated_ground")
			b.log_line("%s loses focus (rolled %d): Consecrated Ground ends." % [f.name, t["roll"]])
