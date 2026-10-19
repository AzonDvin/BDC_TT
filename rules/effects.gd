class_name Effects
extends RefCounted
## Every rule that changes a number lives here: effective stats, attack modifiers, armour, damage, visibility.
## Keeping them in one place makes it possible to answer "why is this 5+?" (see explain arrays) and to test them.


# --- Engagement --------------------------------------------------------------------------------

static func engaged_enemies(b: Battle, f: FighterState) -> Array:
	var out: Array = []
	if not f.on_board():
		return out
	for o in b.fighters:
		if o.on_board() and o.player != f.player and Geo.within(f.pos, f.radius, o.pos, o.radius, 1.0):
			out.append(o)
	return out


static func is_engaged(b: Battle, f: FighterState) -> bool:
	return not engaged_enemies(b, f).is_empty()


# --- Auras and nearby helpers ------------------------------------------------------------------

static func _friendly_aura(b: Battle, f: FighterState, effect_id: String) -> Dictionary:
	for o in b.fighters:
		if o.on_board() and o.player == f.player:
			var e: Dictionary = o.effect(effect_id)
			if not e.is_empty() and f.pos.distance_to(o.pos) - o.radius - f.radius <= float(e.get("radius", 6.0)) + Geo.EPS:
				return e
	return {}


static func _friendly_with_rule_within(b: Battle, f: FighterState, rule: String, inches: float, include_self := false) -> bool:
	for o in b.fighters:
		if o.on_board() and o.player == f.player and (include_self or o != f) and o.has_rule(rule):
			if Geo.within(f.pos, f.radius, o.pos, o.radius, inches):
				return true
	return false


# --- Movement ---------------------------------------------------------------------------------

## Base Move value for a move about to be made (before run/charge dice and terrain penalties).
static func move_value(b: Battle, f: FighterState, rolled_2d6 := 0) -> float:
	var mv: float
	if f.has_effect("rotten_insides"):
		return 2.0
	if str(f.stats["move"]) == "2d6":
		mv = float(rolled_2d6)
	else:
		mv = float(f.stats["move"])
	if not _friendly_aura(b, f, "aura_godspeed").is_empty():
		mv += 1.0
	if _friendly_with_rule_within(b, f, "shepherd_the_afflicted", 6.0):
		mv += 1.0
	if f.has_kw("Thrall") and not _friendly_aura(b, f, "aura_death_march").is_empty():
		mv += 2.0
	return mv


# --- Armour -----------------------------------------------------------------------------------

## The number needed on the armour roll before Rend (7 = no save possible, i.e. '-').
static func armour_value(b: Battle, f: FighterState, ctx := {}) -> int:
	var a := int(f.stats["armour"])
	var improve := 0
	if f.has_item("shield"):
		improve += 1
		if f.has_rule("shield_expert") and ctx.get("defending_vs_charge", false):
			improve += 1
	if ctx.get("cover", false):
		improve += 1
	if f.has_effect("will_of_the_saints") or f.has_effect("ethereal_armour") or f.has_effect("protective_shroud"):
		improve += 1
	for o in b.fighters:
		if o.on_board() and o.player == f.player:
			var cg: Dictionary = o.effect("consecrated_ground")
			if not cg.is_empty() and f.pos.distance_to(cg["point"]) <= float(cg["radius"]) + f.radius:
				improve += 1
				break
	var worsen := 0
	if f.has_effect("rotten_armour"):
		worsen += 1
	var attacker: FighterState = ctx.get("attacker", null)
	if (f.has_kw("Demon") or f.has_kw("Undead")) and ctx.get("melee", false) and attacker != null and attacker.has_item("lantern_torch"):
		worsen += 1
	for e in engaged_enemies(b, f):
		if e.has_rule("vector_of_entropy"):
			worsen += 1
			break
	a = a - improve + worsen
	a = maxi(a, 2)
	return 7 if a >= 7 else a


static func ignores_rend(f: FighterState) -> bool:
	return f.has_rule("demonic_wards") or f.has_effect("spirit_guardian")


# --- Attack rolls -----------------------------------------------------------------------------

static func hit_value(f: FighterState, ranged: bool) -> int:
	var v = f.stats["bow"] if ranged else f.stats["blade"]
	return 7 if v == null else int(v)


static func crit_threshold(b: Battle, att: FighterState, w: Dictionary, ranged: bool) -> int:
	var t := 6
	if weapon_has(att, w, "Arcane"):
		t = 5
	if ranged and att.has_rule("crackshot"):
		t = 5
	if not ranged and att.charged and att.has_rule("one_cut_one_kill"):
		t = 5
	return t


## Modifier added to each attack roll. `explain` collects human-readable reasons.
static func attack_mod(b: Battle, att: FighterState, w: Dictionary, target: FighterState, ranged: bool, explain: Array = []) -> int:
	var m := 0
	if weapon_has(att, w, "Unwieldy") and not (not ranged and att.has_rule("great_weapon_master")):
		m -= 1
		explain.append("Unwieldy -1")
	if ranged:
		if att.has_rule("steady_aim") and not att.moved:
			m += 1
			explain.append("Steady Aim +1")
	else:
		if att.has_effect("bless_thy_blade"):
			m += 1
			explain.append("Blessed blades +1")
		for aura in ["aura_rabid_fervour", "aura_attack_attack", "aura_unholy_sermon"]:
			if not _friendly_aura(b, att, aura).is_empty():
				m += 1
				explain.append("%s +1" % aura.trim_prefix("aura_").capitalize())
				break
		if b.scen.get("twist_id", "") == "beggars_desperation" and att.treasure == 0 and target != null and target.treasure > 0:
			m += 1
			explain.append("Beggar's Desperation +1")
		if target != null and target.has_effect("blood_frenzy_zone"):
			pass
	if att.has_effect("disorientated"):
		m -= 1
		explain.append("Disorientated -1")
	if target != null and target.has_rule("shroud_of_flies"):
		m -= 1
		explain.append("Shroud of Flies -1")
	return m


## Effective weapon traits, including temporary enchantments (Flaming Weapon, Fetid/Cursed Blades, Putrid Blessing...).
static func weapon_traits(f: FighterState, w: Dictionary) -> Array:
	var traits: Array = w.get("traits", []).duplicate()
	for e in f.effects:
		if e.has("grant_traits") and (e.get("weapon", "") == "" or e.get("weapon", "") == w.get("id", "")):
			if w.get("kind", "melee") == "melee" or e.get("any_weapon", false):
				for t in e["grant_traits"]:
					if not t in traits:
						traits.append(t)
	if w.get("kind", "melee") == "melee":
		if f.has_rule("purveyor_of_poisons") and not "Poison" in traits:
			traits.append("Poison")
		if f.has_rule("unholy_strength") and not "Bludgeon" in traits:
			traits.append("Bludgeon")
		if f.has_effect("stand_ground"):
			for t in ["Brace", "Bludgeon"]:
				if not t in traits:
					traits.append(t)
	return traits


static func weapon_has(f: FighterState, w: Dictionary, trait_name: String) -> bool:
	for t in weapon_traits(f, w):
		if (t as String).begins_with(trait_name):
			return true
	return false


## Number of attack dice for a weapon in this attack.
static func attacks_for(b: Battle, f: FighterState, w: Dictionary, offhand: bool, has_held_item_with_2h := false) -> int:
	if offhand:
		return 2 if f.has_rule("dual_weapon_wielder") else 1
	var n := b.dice.roll(w.get("attacks", "1"))
	if w.get("kind", "melee") == "melee":
		if has_held_item_with_2h and weapon_has(f, w, "Two-handed"):
			n -= 1
		if f.has_rule("ambush") and f.charged:
			n += 1
		if f.has_effect("entwined") or f.has_effect("mesmerised"):
			n -= 1
		if b.scen.get("blood_frenzy", false) and Scenario.in_chapel(b, f.pos):
			n += 1
	return maxi(n, 0)


static func rend_for(b: Battle, att: FighterState, w: Dictionary, target: FighterState) -> int:
	var r := int(w.get("rend", 0))
	if w.get("kind", "melee") == "melee" or w.get("special_attack", false):
		var fw := att.effect("flaming_weapon")
		if not fw.is_empty() and fw.get("weapon", "") == w.get("id", ""):
			r -= 1
		if att.has_rule("purveyor_of_poisons") and "Poison" in w.get("traits", []):
			r -= 1
		if att.has_rule("back_stabber") and target != null and engaged_enemies(b, target).size() > 1:
			r -= 1
		if w.get("id", "") in ["crushing_bulk", "splat"] and att.has_item("wheel_spikes"):
			r -= 1
	else:
		var su := att.effect("souped_up")
		if not su.is_empty() and su.get("weapon", "") == w.get("id", ""):
			r -= 1
	return r


static func damage_expr(b: Battle, att: FighterState, w: Dictionary, crit: bool, target: FighterState) -> String:
	var expr: String = (w.get("crit") if crit and w.get("crit") != null else w.get("damage", "1"))
	var add := 0
	var melee: bool = w.get("kind", "melee") == "melee"
	if att != null and melee:
		if att.has_rule("fight_till_the_end") and att.is_bloodied():
			add += 1
		if att.has_effect("demonic_strength"):
			add += 1
		if crit and att.has_rule("chill_touch"):
			add += 1
		if crit and not _friendly_aura(b, att, "aura_holy_strength").is_empty():
			add += 1
	if target != null and target.has_rule("the_black_benediction"):
		add -= 1
	return Dice.add(expr, add)


static func range_for(b: Battle, f: FighterState, w: Dictionary) -> float:
	if not w.has("range") or str(w["range"]) == "flame":
		return 0.0
	var r := float(w["range"])
	if f.has_rule("marksman"):
		r += 3.0
	if f.has_item("periscope") and not f.moved and "Two-handed" in w.get("traits", []):
		r += 5.0
	if _friendly_with_rule_within(b, f, "master_of_dark_science", 6.0, true):
		r += 3.0
	return r


# --- Visibility (p.9) and cover (p.28) --------------------------------------------------------

## {"visible": bool, "obscured": bool}. Top-down approximation: lines from the observer's head (base centre)
## to points across the target's base. High terrain and other fighters block lines; low terrain close to the
## target hides its lower body (obscured). See the bdc-rules-expert ambiguities list.
static func visibility(b: Battle, obs: FighterState, tgt: FighterState) -> Dictionary:
	return visibility_from_point(b, obs.pos, obs, tgt)


static func visibility_from_point(b: Battle, from: Vector2, obs: FighterState, tgt: FighterState, ignore_hidden := false) -> Dictionary:
	if obs == tgt:
		return {"visible": true, "obscured": false}
	var limit: float = b.scen.get("visibility_limit", 0.0)
	if limit > 0.0 and from.distance_to(tgt.pos) - tgt.radius > limit:
		return {"visible": false, "obscured": false}
	var lines := 0
	var clear := 0
	var low_obscured := false
	for s in Geo.base_samples(tgt.pos, tgt.radius):
		lines += 1
		var blocked := false
		for t in b.terrain:
			if t.blocks_sight(tgt.height) and Geo.segment_crosses_polygon(from, s, t.polygon):
				blocked = true
				break
		if not blocked:
			for o in b.fighters:
				if o.on_board() and o != tgt and o != obs and Geo.segment_hits_circle(from, s, o.pos, o.radius * 0.9):
					blocked = true
					break
		if blocked:
			continue
		clear += 1
		for t in b.terrain:
			if t.is_low() and t.height < tgt.height:
				var entry = Geo.first_entry(from, s, t.polygon)
				if entry != null and (entry as Vector2).distance_to(tgt.pos) <= float(b.cfg["low_cover_range"]) + tgt.radius:
					low_obscured = true
	var visible := clear > 0
	var obscured := visible and (clear < lines or low_obscured)
	if visible and not ignore_hidden and obs != null and obs.player != tgt.player:
		if tgt.statuses.get("hidden", false) and obscured and not _sniffed(b, obs.player, tgt):
			visible = false
		if tgt.has_rule("shadow_lurker") and from.distance_to(tgt.pos) - tgt.radius > 9.0 and _near_terrain(b, tgt, 0.5):
			visible = false
	return {"visible": visible, "obscured": obscured}


static func _sniffed(b: Battle, player: int, tgt: FighterState) -> bool:
	for o in b.fighters:
		if o.on_board() and o.player == player and o.has_rule("sniff_em_out") and Geo.within(o.pos, o.radius, tgt.pos, tgt.radius, 9.0):
			return true
	return false


static func _near_terrain(b: Battle, f: FighterState, inches: float) -> bool:
	for t in b.terrain:
		if Geo.base_overlaps_polygon(f.pos, f.radius + inches, t.polygon):
			return true
	return false


static func touching_terrain(b: Battle, f: FighterState) -> bool:
	return _near_terrain(b, f, 0.1)


## Cover for a ranged attack: obscured, or protected by an aura such as Gathering Shadows.
static func in_cover(b: Battle, att: FighterState, tgt: FighterState, vis: Dictionary) -> bool:
	if vis.get("obscured", false):
		return true
	return not _friendly_aura(b, tgt, "aura_gathering_shadows").is_empty()
