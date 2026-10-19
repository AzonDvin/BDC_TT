class_name FighterModels
extends RefCounted
## 3D figures for fighters, from the KayKit Adventurers and Skeletons packs (CC0, Kay Lousberg, www.kaylousberg.com)
## in res://assets/. Which figure a fighter gets depends on its keywords and type (look_for), its weapons are put in
## its hands (handslot bones), and all characters share one rig, so one animation library drives them all.
## Skeletons and Zombies use the skeleton figures, weapons and clips (rising from the ground, collapsing).
## Creatures (demons, beasts, brutes) come from Quaternius packs (CC0): each brings its own animations, matched to
## roles by name (CREATURE_CLIPS). A fighter with no model (or if a pack is missing) keeps the plain pill; see
## Board3D._make_fighter.

const KAYKIT := "res://assets/kaykit_adventurers/KayKit_Adventurers_2.0_FREE/"
## Optional: the KayKit Character Animations pack (melee, ranged and spellcasting clips for the same rig, CC0).
## These Rig_Medium files from anywhere under this folder are added to the animation library automatically.
const EXTRA_ANIMS := "res://assets/kaykit_character_animations/"
const EXTRA_FILES: PackedStringArray = ["Rig_Medium_CombatMelee.glb", "Rig_Medium_CombatRanged.glb", "Rig_Medium_MovementAdvanced.glb", "Rig_Medium_Special.glb"]
## The KayKit Skeletons pack (Warrior, Minion, Rogue, Mage and their weapons).
const SKELETONS := "res://assets/KayKit_Skeletons/"
## Adventurer weapon model -> skeleton weapon model, for skeleton figures.
const SKELETON_WEAPONS := {
	"sword_1handed": "Skeleton_Blade", "sword_2handed": "Skeleton_Blade", "dagger": "Skeleton_Blade",
	"axe_1handed": "Skeleton_Axe", "axe_2handed": "Skeleton_Axe", "staff": "Skeleton_Staff", "wand": "Skeleton_Staff",
	"crossbow_2handed": "Skeleton_Crossbow", "crossbow_1handed": "Skeleton_Crossbow", "shield_round": "Skeleton_Shield_Small_A",
}
## Creature figures by fighter id: Quaternius Ultimate Monsters, Animated Animals, Rat and Giant (CC0, quaternius.com).
## "size": height relative to the fighter's model height; "length": for long, low animals, body length in base
## diameters instead; "fly": hovers above its base; "tint" multiplies its colours.
const MONSTERS := "res://assets/quaternius_monsters/"
const ANIMALS := "res://assets/quaternius_animals/"
const RAT := "res://assets/quaternius_rat/Rat.glb"
const GIANT := "res://assets/quaternius_giant/Giant.glb"
const CREATURES := {
	"rot_demon": {"scene": MONSTERS + "Demon-LnfIziKv4o.glb"},
	"demonic_rot_herald": {"scene": MONSTERS + "Blue_Demon.glb"},
	"demonic_rotspawn": {"scene": MONSTERS + "Green_Spiky_Blob.glb", "size": 0.8},
	"demonic_rot_colossal": {"scene": MONSTERS + "Yeti-ceRHrn8HHE.glb", "size": 1.15},
	"rotling": {"scene": MONSTERS + "Green_Blob.glb", "size": 0.9},
	"bloat_fly": {"scene": MONSTERS + "Armabee.glb", "fly": true, "size": 0.8},
	"darkcloven_beastman": {"scene": MONSTERS + "Orc.glb"},
	"darkcloven_shaman": {"scene": MONSTERS + "Tribal.glb"},
	"gargoyle": {"scene": MONSTERS + "Goleling_Evolved.glb", "fly": true, "size": 0.7, "tint": Color(0.7, 0.72, 0.72)},
	"dire_bat": {"scene": MONSTERS + "Dragon.glb", "fly": true, "tint": Color(0.55, 0.45, 0.5)},
	"mercenary_ogre": {"scene": GIANT},
	"zombie_ogre": {"scene": GIANT, "tint": Color(0.66, 0.86, 0.52)},           # zombie green
	"hunting_dog": {"scene": ANIMALS + "Husky.gltf", "size": 1.1},
	"dire_wolf": {"scene": ANIMALS + "Wolf.gltf", "size": 1.2, "tint": Color(0.8, 0.85, 0.9)},
	"giant_rat": {"scene": RAT, "length": 1.5},                                     # nose to rump, in base diameters
	"rat_mutant": {"scene": RAT, "length": 1.4, "tint": Color(0.7, 0.6, 0.6)},
}
## Creature clip names by role: each model family names them differently (biped, blob, flyer, animal, rat).
const CREATURE_CLIPS := {
	"idle": ["Idle", "Flying_Idle", "Rat_Idle"],
	"walk": ["Walk", "Rat_Walk", "Fast_Flying", "Flying_Idle"],
	"run": ["Run", "Gallop", "Rat_Run", "Fast_Flying", "Walk"],
	"attack": ["Weapon", "Punch", "Bite_Front", "Headbutt", "Attack", "Rat_Attack"],
	"hit": ["HitReact", "HitRecieve", "Idle_HitReact1"],
	"death": ["Death", "Rat_Death"],
}
static var _native_height := {}     # creature scene -> its height in model units (measured once, from its bones)
const ZOMBIE_TINT := Color(0.66, 0.86, 0.52)      # sickly green over the bone
const BEAST_TINT := Color(0.78, 0.66, 0.55)       # a fur-brown Lycanfell Beast
const STONE_TINT := Color(0.62, 0.62, 0.66)       # brutes: a stone golem look (the pack's Golem is a paid extra)

## Attack clips (KayKit Character Animations names). Several per kind: one is picked at random for variety.
const CLIPS := {
	"melee_1h": ["Melee_1H_Attack_Chop", "Melee_1H_Attack_Slice_Diagonal", "Melee_1H_Attack_Slice_Horizontal", "Melee_1H_Attack_Stab"],
	"melee_2h": ["Melee_2H_Attack_Chop", "Melee_2H_Attack_Slice", "Melee_2H_Attack_Stab"],
	"melee_dual": ["Melee_Dualwield_Attack_Chop", "Melee_Dualwield_Attack_Slice", "Melee_Dualwield_Attack_Stab"],
	"melee_unarmed": ["Melee_Unarmed_Attack_Punch_A", "Melee_Unarmed_Attack_Kick"],
	"block": ["Melee_Block"],
	"shoot_bow": ["Ranged_Bow_Release"],
	"shoot_2h": ["Ranged_2H_Shoot"],
	"shoot_1h": ["Ranged_1H_Shoot"],
	"throw": ["Throw"],
	"cast_attack": ["Ranged_Magic_Shoot"],
	"cast": ["Ranged_Magic_Spellcasting"],
	"draw_power": ["Ranged_Magic_Raise"],
	"reload_1h": ["Ranged_1H_Reload"],
	"reload_2h": ["Ranged_2H_Reload"],
	"dodge": ["Dodge_Left", "Dodge_Right"],
}
## Ranged weapons that are thrown or slung rather than shot.
const THROWN: PackedStringArray = ["sling", "throwing_stars", "fire_bombs", "orb_bombs"]
const MODEL_HEIGHT := 2.2          # rest height of a KayKit character's head, in model units

## Character per fighter role (role_of). "" = keep the pill.
const MAPPING := {
	"caster": "Mage",
	"leader": "Knight",
	"champion": "Barbarian",
	"shooter": "Ranger",
	"henchman": "Rogue_Hooded",
	"henchman_alt": "Rogue",
	"brute": "Barbarian",
	"beast": "",
}

## Weapon id -> KayKit weapon model. Anything not listed (guns, claws, bites...) isn't shown.
const WEAPONS := {
	"sword": "sword_1handed", "cursed_blade": "sword_1handed", "poison_blade": "sword_1handed", "ensorcelled_weapon": "sword_1handed",
	"rat_mutant_blade": "sword_1handed", "demonic_rot_blade": "sword_1handed", "ogre_blade": "sword_1handed",
	"zweihander": "sword_2handed", "great_demonic_rot_blade": "sword_2handed", "ogre_great_weapon": "sword_2handed",
	"axe": "axe_1handed", "club": "axe_1handed", "flail": "axe_1handed", "ogre_mace": "axe_1handed",
	"heavy_axe": "axe_2handed", "warhammer": "axe_2handed", "great_club": "axe_2handed", "great_mace": "axe_2handed", "heavy_flail": "axe_2handed",
	"dagger": "dagger",
	"arcane_staff": "staff", "halberd": "axe_2handed", "ensorcelled_halberd": "axe_2handed",   # no spear model in the pack
	"crossbow": "crossbow_2handed", "arbalest": "crossbow_2handed", "ogre_arbalest": "crossbow_2handed",
	"hand_crossbow": "crossbow_1handed",
	"long_bow": "bow_withString", "short_bow": "bow_withString",
}
const LOOPING: PackedStringArray = ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Running_A", "Running_B", "Running_HoldingBow", "Running_HoldingRifle",
	"Skeletons_Idle", "Skeletons_Walking"]


## The running clip for a fighter: shooters with a two-handed bow or crossbow run holding it.
static func run_clip(f: FighterState) -> String:
	if role_of(f) == "shooter" and library() != null:
		var rm := _ranged_model(f)
		if rm.begins_with("bow") and library().has_animation("Running_HoldingBow"):
			return "Running_HoldingBow"
		if rm == "crossbow_2handed" and library().has_animation("Running_HoldingRifle"):
			return "Running_HoldingRifle"
	return "Running_A"

static var _scenes := {}            # path -> PackedScene (or null if missing)
static var _library: AnimationLibrary


static func available() -> bool:
	return ResourceLoader.exists(KAYKIT + "Characters/gltf/Knight.glb")


## What kind of figure a fighter is: caster, leader, champion, shooter, henchman(_alt), brute or beast.
static func role_of(f: FighterState) -> String:
	if f.category == "beast":
		return "beast"
	if f.category == "brute":
		return "brute"
	if f.is_caster():
		return "caster"
	if f.category in ["leader", "champion"]:
		return f.category
	if _ranged_model(f) != "":
		return "shooter"
	return "henchman" if f.uid % 2 == 0 else "henchman_alt"


static func character_for(f: FighterState) -> String:
	return look_for(f).get("character", "")


static func skeletons_available() -> bool:
	return ResourceLoader.exists(SKELETONS + "characters/gltf/Skeleton_Warrior.glb")


## The figure for a fighter: {"scene", "character", "skeleton" (skeleton weapons and clips), "tint", "zombie"},
## or {} to keep the pill.
static func look_for(f: FighterState) -> Dictionary:
	if CREATURES.has(f.def_id) and ResourceLoader.exists(CREATURES[f.def_id]["scene"]):
		var c: Dictionary = CREATURES[f.def_id]
		return {"scene": c["scene"], "character": c["scene"].get_file().get_basename(), "skeleton": false, "tint": c.get("tint"),
			"zombie": false, "creature": true, "size": c.get("size", 1.0), "length": c.get("length", 0.0), "fly": c.get("fly", false)}
	if f.category == "beast" or f.has_kw("Gargoyle") or f.has_kw("Bat"):
		return {}
	if f.def_id == "lycanfell_beast":
		return {"scene": KAYKIT + "Characters/gltf/Barbarian.glb", "character": "Barbarian", "skeleton": false, "tint": BEAST_TINT, "zombie": false}
	# Vampyres (the Bloodcursed and the Misbegotten) are Skeleton Mages; human Necromancers stay adventurer Mages.
	if f.has_kw("Vampyre") and skeletons_available():
		return {"scene": SKELETONS + "characters/gltf/Skeleton_Mage.glb", "character": "Skeleton_Mage", "skeleton": true, "tint": null, "zombie": false}
	# Vampyres (the Bloodcursed and the Misbegotten) are Skeleton Mages; human Necromancers stay adventurer Mages.
	if f.has_kw("Vampyre") and skeletons_available():
		return {"scene": SKELETONS + "characters/gltf/Skeleton_Mage.glb", "character": "Skeleton_Mage", "skeleton": true, "tint": null, "zombie": false}
	var zombie := f.has_kw("Zombie")
	# Brutes are big stone-grey Skeleton Warriors, golem-like (a Zombie Ogre stays zombie green and shambles).
	if f.category == "brute" and skeletons_available():
		return {"scene": SKELETONS + "characters/gltf/Skeleton_Warrior.glb", "character": "Skeleton_Warrior", "skeleton": true,
			"tint": ZOMBIE_TINT if zombie else STONE_TINT, "zombie": zombie}
	if (f.has_kw("Skeleton") or zombie) and skeletons_available():
		var ch := "Skeleton_Minion"
		if f.is_caster():
			ch = "Skeleton_Mage"
		elif f.category in ["leader", "champion", "brute"]:
			ch = "Skeleton_Warrior"
		elif _ranged_model(f) != "":
			ch = "Skeleton_Rogue"
		elif not zombie and f.uid % 2 == 0:
			ch = "Skeleton_Warrior"
		return {"scene": SKELETONS + "characters/gltf/%s.glb" % ch, "character": ch, "skeleton": true, "tint": ZOMBIE_TINT if zombie else null, "zombie": zombie}
	var ch2: String = MAPPING.get(role_of(f), "")
	if ch2 == "":
		return {}
	return {"scene": KAYKIT + "Characters/gltf/%s.glb" % ch2, "character": ch2, "skeleton": false, "tint": null, "zombie": false}


## Identifies a figure, so the board can rebuild it when it changes (the Lycanfell transforming and back).
static func look_key(f: FighterState) -> String:
	var l := look_for(f)
	return "pill" if l.is_empty() or not available() else "%s|%s" % [l["scene"], l["tint"]]


## The clip a figure idles with, walks with (zombies shamble), dies with and rises with.
static func idle_clip(model: Node3D) -> String:
	return model.get_meta("idle", "Idle_A")


static func walk_clip(model: Node3D, f: FighterState, running: bool) -> String:
	if model.get_meta("creature", false):
		return _creature_role(model, "run" if running else "walk")
	if model.get_meta("zombie", false) and library().has_animation("Skeletons_Walking"):
		return "Skeletons_Walking"
	return run_clip(f) if running else "Walking_A"


static func death_clip(model: Node3D) -> String:
	if model.get_meta("creature", false):
		return _creature_role(model, "death")
	return "Skeletons_Death" if model.get_meta("skeleton", false) and library().has_animation("Skeletons_Death") else "Death_A"


static func rise_clip(model: Node3D) -> String:
	return "Skeletons_Awaken_Floor" if model.get_meta("skeleton", false) and library().has_animation("Skeletons_Awaken_Floor") else ""


## {"r": weapon model or "", "l": ...}: a shooter holds its bow (left) or crossbow (right); others their melee
## weapons (main in the right hand, off-hand weapon or shield in the left).
static func weapons_for(f: FighterState) -> Dictionary:
	var out := {"r": "", "l": ""}
	var rm := _ranged_model(f)
	if rm != "" and role_of(f) == "shooter":
		out["l" if rm.begins_with("bow") else "r"] = rm
		return out
	if not f.melee.is_empty():
		var dw := Combat.default_weapons(f)
		out["r"] = WEAPONS.get(f.melee[dw[0]]["id"], "")
		if dw[1] >= 0:
			out["l"] = WEAPONS.get(f.melee[dw[1]]["id"], "")
	if out["l"] == "" and f.has_item("shield"):
		out["l"] = "shield_round"
	if out["r"] == "" and f.is_caster():
		out["r"] = "wand"
	return out


static func _ranged_model(f: FighterState) -> String:
	for w in f.ranged:
		if WEAPONS.has(w["id"]):
			return WEAPONS[w["id"]]
	return ""


## Builds the figure for a fighter (scaled to its height, weapons in hand, idling), or null to keep the pill.
static func build(f: FighterState) -> Node3D:
	var look := look_for(f)
	if look.is_empty() or not available():
		return null
	var scene := _scene(look["scene"])
	if scene == null:
		return null
	if look.get("creature", false):
		return _build_creature(f, look, scene)
	var model: Node3D = scene.instantiate()
	model.name = "Model"
	model.scale = Vector3.ONE * (f.height / MODEL_HEIGHT)
	model.set_meta("skeleton", look["skeleton"])
	model.set_meta("zombie", look["zombie"])
	if look["tint"] != null:
		_tint(model, look["tint"])
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0] if not model.find_children("*", "Skeleton3D", true, false).is_empty() else null
	if skel != null:
		var held := weapons_for(f)
		for side in ["r", "l"]:
			if held[side] == "":
				continue
			var ws: PackedScene = null
			if look["skeleton"] and SKELETON_WEAPONS.has(held[side]):
				ws = _scene(SKELETONS + "assets/gltf/%s.gltf" % SKELETON_WEAPONS[held[side]])
			if ws == null:
				ws = _scene(KAYKIT + "Assets/gltf/%s.gltf" % held[side])
			if ws == null:
				continue
			var att := BoneAttachment3D.new()
			att.bone_name = "handslot." + side
			skel.add_child(att)
			att.add_child(ws.instantiate())
	var player := AnimationPlayer.new()
	player.name = "Anim"
	model.add_child(player)
	player.root_node = NodePath("..")
	var lib := library()
	if lib != null:
		player.add_animation_library("", lib)
		model.set_meta("idle", "Skeletons_Idle" if look["skeleton"] and lib.has_animation("Skeletons_Idle") else "Idle_A")
		player.play(idle_clip(model))
		player.seek(randf() * 1.0, true)   # don't let a whole warband breathe in step
	return model


## A creature figure: its own AnimationPlayer, scaled from its measured height, flyers hovering over the base.
static func _build_creature(f: FighterState, look: Dictionary, scene: PackedScene) -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	var body: Node3D = scene.instantiate()
	model.add_child(body)
	var dims := _creature_dims(look["scene"], scene)
	var k: float = f.height * float(look["size"]) / maxf(dims["hi"] - dims["lo"], 0.01)
	if float(look["length"]) > 0.0:
		k = f.radius * 2.0 * float(look["length"]) / maxf(dims["len"], 0.01)
	body.scale = Vector3.ONE * k
	body.position.y = -float(dims["lo"]) * k + (f.height * 0.45 if look["fly"] else 0.0)
	model.set_meta("creature", true)
	model.set_meta("skeleton", false)
	model.set_meta("zombie", false)
	if look["tint"] != null:
		_tint(model, look["tint"])
	var players := body.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return model
	var p: AnimationPlayer = players[0]
	var clips := {}
	for role in CREATURE_CLIPS:
		clips[role] = _creature_clip(p, CREATURE_CLIPS[role])
	model.set_meta("clips", clips)
	model.set_meta("player", model.get_path_to(p))
	model.set_meta("idle", clips["idle"])
	for role in ["idle", "walk", "run"]:
		if clips[role] != "":
			p.get_animation(clips[role]).loop_mode = Animation.LOOP_LINEAR
	if clips["idle"] != "":
		p.play(clips["idle"])
		p.seek(randf() * 1.0, true)
	return model


## The first animation whose name (after any "Armature|" prefix) matches one of the wanted names.
static func _creature_clip(p: AnimationPlayer, wanted: Array) -> String:
	for w in wanted:
		for nm in p.get_animation_list():
			var s := String(nm)
			if s == w or s.ends_with("|" + w):
				return s
	return ""


## A creature's size in model units: {"lo", "hi"} bone heights and "len" (longest horizontal extent), measured once
## from its rest pose (the node transforms above the skeleton are multiplied by hand, so nothing enters the tree).
static func _creature_dims(path: String, scene: PackedScene) -> Dictionary:
	if _native_height.has(path):
		return _native_height[path]
	var n: Node3D = scene.instantiate()
	var lo := INF
	var hi := -INF
	var box := AABB()
	var first := true
	for sk in n.find_children("*", "Skeleton3D", true, false):
		var s := sk as Skeleton3D
		var t := Transform3D.IDENTITY
		var node: Node = s
		while node != null and node != n.get_parent():
			if node is Node3D:
				t = (node as Node3D).transform * t
			node = node.get_parent()
		for i in s.get_bone_count():
			var p := (t * s.get_bone_global_rest(i)).origin
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
			box = AABB(p, Vector3.ZERO) if first else box.expand(p)
			first = false
	n.free()
	var d := {"lo": 0.0, "hi": 2.0, "len": 2.0}
	if hi > lo:
		d = {"lo": maxf(lo, 0.0), "hi": lo + (hi - lo) * 1.15, "len": maxf(box.size.x, box.size.z)}   # bones stop short of the head top
	_native_height[path] = d
	return d


## The model's AnimationPlayer: "Anim" for KayKit figures, the creature's own player otherwise.
static func player_of(model: Node3D) -> AnimationPlayer:
	if model.has_meta("player"):
		return model.get_node_or_null(model.get_meta("player")) as AnimationPlayer
	return model.get_node_or_null("Anim") as AnimationPlayer


static func _creature_role(model: Node3D, role: String) -> String:
	return String(model.get_meta("clips", {}).get(role, ""))


static func hit_clip(model: Node3D) -> String:
	return _creature_role(model, "hit") if model.get_meta("creature", false) else "Hit_A"


## Multiplies every surface of a figure by a colour (the green of a Zombie, the fur of the Lycanfell Beast).
static func _tint(model: Node3D, tint: Color) -> void:
	if DisplayServer.get_name() == "headless":
		return   # nothing is drawn, and the headless renderer warns when tinted animal models are freed
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var base := m.get_active_material(i)
			if base is BaseMaterial3D:
				var dup := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = dup.albedo_color * tint
				m.set_surface_override_material(i, dup)


## All the rig's animations (general + movement) in one library; walking, running and idling loop.
static func library() -> AnimationLibrary:
	if _library != null:
		return _library
	var lib := AnimationLibrary.new()
	var files: Array = [KAYKIT + "Animations/gltf/Rig_Medium/Rig_Medium_General.glb", KAYKIT + "Animations/gltf/Rig_Medium/Rig_Medium_MovementBasic.glb"]
	files.append_array(_find_rig_files(EXTRA_ANIMS))
	for path in files:
		var sc := _scene(path)
		if sc == null:
			continue
		var n: Node = sc.instantiate()
		for ap in n.find_children("*", "AnimationPlayer", true, false):
			for nm in (ap as AnimationPlayer).get_animation_list():
				if lib.has_animation(nm):
					continue
				var a: Animation = (ap as AnimationPlayer).get_animation(nm).duplicate()
				if nm in LOOPING:
					a.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(nm, a)
		n.free()
	_library = lib
	return lib


## Rig_Medium*.glb files anywhere under a folder (the optional animation pack).
static func _find_rig_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for sub in d.get_directories():
		if not sub.to_lower() in ["fbx", "rig_large"]:
			out.append_array(_find_rig_files(dir_path.path_join(sub)))
	for file in d.get_files():
		if file in EXTRA_FILES:
			out.append(dir_path.path_join(file))
	return out


## Which clip group fits an action: kind is "melee", "shoot", "block", "cast", "cast_attack", "draw_power",
## "reload" or "dodge"; weapon is the weapon's name from the log (it decides one- or two-handed, bow, thrown...).
static func clip_group(f: FighterState, kind: String, weapon := "") -> String:
	match kind:
		"melee":
			var w := _weapon_named(f.melee, weapon)
			if w.is_empty() and not f.melee.is_empty():
				w = f.melee[Combat.default_weapons(f)[0]]
			var traits: Array = w.get("traits", [])
			if "Natural Weapon" in traits or w.is_empty():
				return "melee_unarmed"
			if "Two-handed" in traits:
				return "melee_2h"
			if not f.melee.is_empty() and Combat.default_weapons(f)[1] >= 0:
				return "melee_dual"
			return "melee_1h"
		"shoot", "reload":
			var r := _weapon_named(f.ranged, weapon)
			if r.is_empty() and not f.ranged.is_empty():
				r = f.ranged[0]
			if kind == "reload":
				return "reload_2h" if "Two-handed" in r.get("traits", []) else "reload_1h"
			if r.get("id", "") in THROWN:
				return "throw"
			if WEAPONS.get(r.get("id", ""), "").begins_with("bow"):
				return "shoot_bow"
			return "shoot_2h" if "Two-handed" in r.get("traits", []) else "shoot_1h"
	return kind


static func _weapon_named(list: Array, weapon: String) -> Dictionary:
	for w in list:
		if w["name"] == weapon or w["id"] == weapon:
			return w
	return {}


## A clip from the group that this library has, or "".
static func attack_clip(f: FighterState, kind: String, weapon := "") -> String:
	var lib := library()
	if lib == null:
		return ""
	var have: Array = []
	for nm in CLIPS.get(clip_group(f, kind, weapon), []):
		if lib.has_animation(nm):
			have.append(nm)
	return have[randi() % have.size()] if not have.is_empty() else ""


## Plays the figure's animation for an action; false if it has none (then the figure lunges instead).
static func play_attack(model: Node3D, f: FighterState, kind: String, weapon := "") -> bool:
	if model.get_meta("creature", false):
		if not kind in ["melee", "shoot", "cast", "cast_attack"]:
			return false
		var c := _creature_role(model, "attack")
		if c == "":
			return false
		play_once(model, c)
		return true
	var clip := attack_clip(f, kind, weapon)
	if clip == "":
		return false
	play_once(model, clip)
	return true


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


## Plays a one-off animation, then returns to idling (or holds the last frame for deaths).
static func play_once(model: Node3D, anim: String, hold := false) -> void:
	var p := player_of(model)
	if p == null or anim == "" or not p.has_animation(anim):
		return
	p.play(anim, 0.1)
	if hold:
		return
	p.animation_finished.connect(func(done: StringName): _back_to_idle(model, p, anim, done), CONNECT_ONE_SHOT)


static func _back_to_idle(model: Node3D, p: AnimationPlayer, anim: String, done: StringName) -> void:
	if is_instance_valid(p) and is_instance_valid(model) and String(done) == anim:
		p.play(idle_clip(model), 0.2)


static func play_loop(model: Node3D, anim: String) -> void:
	var p := player_of(model)
	if p != null and p.has_animation(anim) and p.current_animation != anim:
		p.play(anim, 0.15)
