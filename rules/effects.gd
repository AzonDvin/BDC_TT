class_name Effects
extends RefCounted
## Every rule that changes a number lives here: effective stats, attack modifiers, armour, damage, visibility.
## Keeping them in one place makes it possible to answer "why is this 5+?" (see explain arrays) and to test them.


# --- Distance and engagement -------------------------------------------------------------------

## Base-to-base distance between two fighters, including height differences (p.7).
static func dist(a: FighterState, b2: FighterState) -> float:
	return Height.gap3(a.pos, a.radius, a.elev, b2.pos, b2.radius, b2.elev)


static func near(a: FighterState, b2: FighterState, inches: float) -> bool:
	return dist(a, b2) <= inches + Geo.EPS


static func engaged_enemies(b: Battle, f: FighterState) -> Array:
	var out: Array = []
	if not f.on_board():
		return out
	for o in b.fighters:
		if o.on_board() and o.player != f.player and Effects.near(f, o, 1.0):
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
			if Effects.near(f, o, inches):
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
		if target != null and att.elev - target.elev >= 3.0 - Geo.EPS:
			m += 1
			explain.append("Vantage +1")
		if target != null and Twists.ranged_penalty(b, att, target) < 0:
			m -= 1
			explain.append("Eldritch Barrier -1")
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

## {"visible": bool, "obscured": bool} (p.9). Sight lines run from the observer's eye to points on the target's
## body (three heights across its base). A line is blocked by solid terrain (walls, low terrain, platform slabs,
## closed doors, window sills/lintels: TerrainPiece.solid_bands) or by another fighter's body.
## Visible if any line is clear; obscured if some are blocked.
static func visibility(b: Battle, obs: FighterState, tgt: FighterState) -> Dictionary:
	return visibility_from_point(b, obs.pos, eye_height(obs), obs, tgt)


static func eye_height(f: FighterState) -> float:
	return f.elev + f.height * 0.9


static func visibility_from_point(b: Battle, from: Vector2, from_z: float, obs: FighterState, tgt: FighterState, ignore_hidden := false) -> Dictionary:
	if obs == tgt:
		return {"visible": true, "obscured": false}
	var limit: float = b.scen.get("visibility_limit", 0.0)
	var fog: float = fog_limit(b, from, tgt.pos)
	if fog > 0.0 and (limit <= 0.0 or fog < limit):
		limit = fog
	if limit > 0.0 and from.distance_to(tgt.pos) - tgt.radius > limit:
		return {"visible": false, "obscured": false}
	var lines := 0
	var clear := 0
	var heights := [tgt.elev + 0.25, tgt.elev + tgt.height * 0.55, tgt.elev + tgt.height * 0.95]
	for s in Geo.base_samples(tgt.pos, tgt.radius * 0.8, 6):
		for z in heights:
			lines += 1
			if not sight_blocked(b, Vector3(from.x, from.y, from_z), Vector3(s.x, s.y, z), obs, tgt):
				clear += 1
	var visible := clear > 0
	var obscured := visible and clear < lines
	if visible and not ignore_hidden and obs != null and obs.player != tgt.player:
		if tgt.statuses.get("hidden", false) and obscured and not _sniffed(b, obs.player, tgt):
			visible = false
		if tgt.has_rule("shadow_lurker") and from.distance_to(tgt.pos) - tgt.radius > 9.0 and _near_terrain(b, tgt, 0.5):
			visible = false
	return {"visible": visible, "obscured": obscured}


## Is the sight line from a to c blocked? Points are (x, y, height) in inches.
static func sight_blocked(b: Battle, a: Vector3, c: Vector3, obs: FighterState = null, tgt: FighterState = null) -> bool:
	var a2 := Vector2(a.x, a.y)
	var c2 := Vector2(c.x, c.y)
	var seg_len := maxf(a2.distance_to(c2), 0.0001)
	for t in b.terrain:
		var bands: Array = t.solid_bands()
		if bands.is_empty():
			continue
		var parts := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a2, c2]), t.polygon)
		for part in parts:
			var z0 := lerpf(a.z, c.z, a2.distance_to(part[0]) / seg_len)
			var z1 := lerpf(a.z, c.z, a2.distance_to(part[part.size() - 1]) / seg_len)
			var lo := minf(z0, z1)
			var hi := maxf(z0, z1)
			for band in bands:
				if hi >= band.x + 0.01 and lo <= band.y - 0.01:
					return true
	for o in b.fighters:
		if o.on_board() and o != obs and o != tgt:
			var q := Geometry2D.get_closest_point_to_segment(o.pos, a2, c2)
			if q.distance_to(o.pos) < o.radius * 0.9:
				var z := lerpf(a.z, c.z, a2.distance_to(q) / seg_len)
				if z >= o.elev and z <= o.elev + o.height:
					return true
	var vortex: Dictionary = b.scen.get("vortex", {})
	if not vortex.is_empty():
		var vq := Geometry2D.get_closest_point_to_segment(vortex["c"], a2, c2)
		var vz := lerpf(a.z, c.z, a2.distance_to(vq) / seg_len)
		if vq.distance_to(vortex["c"]) < float(vortex["r"]) and absf(vz - float(vortex["elev"])) < 3.0:
			return true
	return false


## Rolling Fog (No Quarter twist): no sight beyond 6" if either end is in a fogged quarter.
static func fog_limit(b: Battle, a: Vector2, c: Vector2) -> float:
	var fogged: Array = b.scen.get("fog", [])
	if fogged.is_empty():
		return 0.0
	var ctr := b.board_size / 2.0
	for p in [a, c]:
		var q := (0 if p.x < ctr.x else 1) if p.y < ctr.y else (3 if p.x < ctr.x else 2)
		if q in fogged:
			return 6.0
	return 0.0


static func _sniffed(b: Battle, player: int, tgt: FighterState) -> bool:
	for o in b.fighters:
		if o.on_board() and o.player == player and o.has_rule("sniff_em_out") and Effects.near(o, tgt, 9.0):
			return true
	return false


static func _near_terrain(b: Battle, f: FighterState, inches: float) -> bool:
	for t in b.terrain:
		if Geo.base_overlaps_polygon(f.pos, f.radius + inches, t.polygon):
			return true
	return false


## "Touching terrain" (Hide, p.27). On a real table bases are pushed up against the wall; on screen we allow a
## small gap so a fighter placed next to a wall by clicking still counts as touching it.
const TOUCH_TOLERANCE := 0.35


static func touching_terrain(b: Battle, f: FighterState) -> bool:
	return f.elev > Height.LEVEL_EPS or _near_terrain(b, f, TOUCH_TOLERANCE)


## Cover for a ranged attack: obscured, or protected by an aura such as Gathering Shadows.
static func in_cover(b: Battle, att: FighterState, tgt: FighterState, vis: Dictionary) -> bool:
	if vis.get("obscured", false):
		return true
	return not _friendly_aura(b, tgt, "aura_gathering_shadows").is_empty()
