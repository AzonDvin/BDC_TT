class_name FighterState
extends RefCounted
## A fighter during a battle. Built from a roster member; all mutable battle state lives here.
## Uses only plain Variant types so to_dict()/from_dict() can copy it generically (save, undo, AI simulation).

var uid := 0
var player := 0
var faction := ""
var def_id := ""
var name := ""
var category := ""
var keywords: PackedStringArray = []
var special: PackedStringArray = []      # special rule ids from the fighter scroll
var skills: PackedStringArray = []
var stats := {}                          # move, blade, bow, armour, initiative, willpower, life (after armour/mutations)
var radius := 0.63
var height := 1.6
var melee: Array = []                    # weapon dicts (always at least one; Unarmed Strike if none)
var ranged: Array = []                   # 0 or 1 weapon dicts (+ item weapons like Bomb-Bolt)
var armour_id := ""
var items: PackedStringArray = []
var lores: PackedStringArray = []
var signature_spells: PackedStringArray = []
var prepared: Array = []                 # spell dicts with "lore" added

var pos := Vector2.ZERO
var life := 4
var where := "reserve"                   # reserve | board | down | escaped
var battle_group := 0
var summoned := false

# Round / activation bookkeeping
var activated := false
var surged := false
var moved := false
var acted := false
var charged := false
var move_kind := ""
var once_per_activation: PackedStringArray = []
var once_per_battle: PackedStringArray = []

# Weapon state: per weapon id
var needs_reload: PackedStringArray = []
var lost_weapons: PackedStringArray = []

var statuses := {}                       # poisoned, hidden, drawn_power, entwined, harried, rotten_insides, ...
var effects: Array = []                  # [{"id", "until": "round"|"battle", ...}]
var treasure := 0
var marks: PackedStringArray = []        # scenario marks, e.g. "hit"


static func from_member(roster: Roster, m: Dictionary, p_player: int, p_uid: int) -> FighterState:
	var f := FighterState.new()
	var def := roster.def_of(m)
	f.uid = p_uid
	f.player = p_player
	f.faction = roster.faction
	f.def_id = m["def"]
	f.name = m.get("name", def["name"])
	f.category = def["category"]
	f.keywords = PackedStringArray(def["keywords"])
	for sr in def.get("special_rules", []):
		f.special.append(sr["id"])
	f.skills = PackedStringArray(m.get("skills", []))
	f.stats = def["stats"].duplicate()
	for o in def.get("options", []):
		if o["id"] == m.get("option", ""):
			for k in o.get("set_stats", {}):
				f.stats[k] = o["set_stats"][k]
			for kw in o.get("add_keywords", []):
				f.keywords.append(kw)
	f.radius = Geo.radius_from_mm(Catalog.base_mm(def))
	f.height = Catalog.model_height(def)
	for id in roster.carried(m):
		f._equip(Catalog.wargear(roster.faction, id))
	if f.melee.is_empty():
		f.melee.append(Catalog.wargear(roster.faction, "unarmed_strike"))
	f.lores = PackedStringArray(def.get("lores", []))
	f.signature_spells = PackedStringArray(m.get("signature_spells", []))
	f.life = int(f.stats["life"])
	return f


func _equip(w: Dictionary) -> void:
	match w.get("kind", ""):
		"melee":
			melee.append(w)
		"ranged":
			ranged.append(w)
		"armour":
			armour_id = w["id"]
			stats["armour"] = int(w["armour"])
			if w.has("move_mod") and stats["move"] is int:
				stats["move"] = int(stats["move"]) + int(w["move_mod"])
		"item":
			items.append(w["id"])
			if w.has("weapon"):
				var iw: Dictionary = w["weapon"].duplicate(true)
				iw["id"] = w["id"]
				iw["from_item"] = true
				iw["kind"] = "ranged" if iw.has("range") else ("melee" if iw.has("attacks") else "special")
				if iw["kind"] == "ranged":
					ranged.append(iw)


func has_kw(k: String) -> bool:
	return k in keywords


func has_rule(id: String) -> bool:
	return id in special or id in skills


func has_item(id: String) -> bool:
	return id in items


func on_board() -> bool:
	return where == "board"


func max_life() -> int:
	return int(stats["life"])


func is_bloodied() -> bool:
	return on_board() and life == 1


func is_caster() -> bool:
	return has_kw("Wizard") or has_kw("Priest")


func can_be_poisoned() -> bool:
	return not (has_kw("Demon") or has_kw("Undead") or has_item("gas_mask") or has_rule("black_blood"))


func is_unshakeable() -> bool:
	return has_rule("unshakeable")


func causes_fear() -> bool:
	return has_rule("fear") or has_rule("dread_aura")


func weapon_by_id(id: String) -> Dictionary:
	for w in melee:
		if w["id"] == id:
			return w
	for w in ranged:
		if w["id"] == id:
			return w
	return {}


func usable_ranged() -> Array:
	var out: Array = []
	for w in ranged:
		if not w["id"] in lost_weapons:
			out.append(w)
	return out


func has_effect(id: String) -> bool:
	for e in effects:
		if e["id"] == id:
			return true
	return false


func effect(id: String) -> Dictionary:
	for e in effects:
		if e["id"] == id:
			return e
	return {}


func add_effect(e: Dictionary) -> void:
	remove_effect(e["id"])
	effects.append(e)


func remove_effect(id: String) -> void:
	for i in range(effects.size() - 1, -1, -1):
		if effects[i]["id"] == id:
			effects.remove_at(i)


func start_activation_reset() -> void:
	moved = false
	acted = false
	charged = false
	move_kind = ""
	once_per_activation = PackedStringArray()


func to_dict() -> Dictionary:
	var d := {}
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = get(p["name"])
			d[p["name"]] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return d


static func from_dict(d: Dictionary) -> FighterState:
	var f := FighterState.new()
	for k in d:
		var v = d[k]
		f.set(k, v.duplicate(true) if (v is Array or v is Dictionary) else v)
	return f
