class_name Catalog
extends RefCounted
## Read-only access to the Black Death City data files in res://data/bdc/.
## The JSON is transcribed from the Playtest v1.03 rulebook (see the bdc-rules-expert skill for conventions).

const DATA_DIR := "res://data/bdc/"
const FACTION_IDS: PackedStringArray = ["guild_mercenaries", "verminkin", "death_covens", "blighted_cloister"]

static var _core: Dictionary = {}
static var _factions: Dictionary = {}


static func core() -> Dictionary:
	if _core.is_empty():
		_core = _load_json(DATA_DIR + "core.json")
	return _core


static func faction(id: String) -> Dictionary:
	if not _factions.has(id):
		_factions[id] = _load_json(DATA_DIR + id + ".json")
	return _factions[id]


static func faction_name(id: String) -> String:
	return faction(id).get("name", id)


static func fighter_def(faction_id: String, def_id: String) -> Dictionary:
	for f in faction(faction_id)["fighters"]:
		if f["id"] == def_id:
			return f
	return {}


static func origin(faction_id: String, origin_id: String) -> Dictionary:
	for o in faction(faction_id)["origins"]:
		if o["id"] == origin_id:
			return o
	return {}


## Looks up any wargear id in a faction: returns the dict with an added "kind" (melee/ranged/armour/item).
static func wargear(faction_id: String, id: String) -> Dictionary:
	var f := faction(faction_id)
	for kind in ["melee_weapons", "ranged_weapons", "armour", "items"]:
		for w in f[kind]:
			if w["id"] == id:
				var out: Dictionary = w.duplicate(true)
				out["kind"] = {"melee_weapons": "melee", "ranged_weapons": "ranged", "armour": "armour", "items": "item"}[kind]
				return out
	if id == "unarmed_strike":
		var u: Dictionary = core()["unarmed_strike"].duplicate(true)
		u["kind"] = "melee"
		return u
	return {}


static func lore(faction_id: String, lore_id: String) -> Dictionary:
	for l in faction(faction_id)["lores"]:
		if l["id"] == lore_id:
			return l
	return {}


## All skill tables a fighter may pick from: the faction's tables it qualifies for, plus Veteran Skills.
static func skill_tables_for(faction_id: String, def: Dictionary) -> Array:
	var out: Array = [core()["veteran_skills"]]
	var kw: Array = def.get("keywords", [])
	var leader_or_champ: bool = "Leader" in kw or "Champion" in kw
	for t in faction(faction_id)["skills"]:
		var e: String = t["eligible"]
		var ok := true
		if e.contains("Leaders and Champions only") and not leader_or_champ:
			ok = false
		if e.contains("Undead Aristocrat") and not ("Undead" in kw and "Aristocrat" in kw):
			ok = false
		if e.contains("Undead Skeleton") and not ("Undead" in kw and "Skeleton" in kw):
			ok = false
		if e.contains("Mercenary") and not "Mercenary" in kw:
			ok = false
		if e.contains("Cloister") and not "Cloister" in kw:
			ok = false
		if e.contains("Verminkin") and not "Verminkin" in kw:
			ok = false
		if ok:
			out.append(t)
	return out


static func skill(faction_id: String, skill_id: String) -> Dictionary:
	for s in core()["veteran_skills"]["skills"]:
		if s["id"] == skill_id:
			return s
	for t in faction(faction_id)["skills"]:
		for s in t["skills"]:
			if s["id"] == skill_id:
				return s
	return {}


static func trait_reminder(trait_name: String) -> String:
	var base := trait_name.split(" 0-")[0]
	for t in core()["weapon_traits"]:
		if t["id"] == base:
			return t["reminder"]
	return ""


## Base diameter in mm for a fighter: data override, else by category (the book allows 25-40mm humans, 40-60mm large).
static func base_mm(def: Dictionary) -> float:
	if def.has("base_mm"):
		return float(def["base_mm"])
	match def.get("category", ""):
		"brute":
			return 50.0
		"beast":
			return 32.0
	return 32.0


## Model height in inches, used for line of sight against terrain.
static func model_height(def: Dictionary) -> float:
	match def.get("category", ""):
		"brute":
			return 2.4
		"beast":
			return 1.0
	return 1.6


static func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Catalog: could not parse %s" % path)
		return {}
	return data
